--!strict
-- Client-only bamboo renderer.
--
-- The server owns the field registry, health, growth clock, and rewards. It
-- sends only compact state records. This controller derives the fixed planting
-- positions, builds visuals locally, streams distant plots out, and animates
-- only stalks that are actually growing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local BambooModel = Core:GetShared("BambooModel")
local Relay = Core:GetShared("Network")
local StalkPose = require(script.Parent.Parent:WaitForChild("Modules"):WaitForChild("StalkPose"))

local BambooGrowthController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local GROWTH_BIND = "BambooGrowth"

-- Plots are laid out 220 studs apart. Keeping a little more than one plot in
-- the stream radius lets nearby players' fields remain visible without building
-- every field in a 12-plot server on every client.
local STREAM_DISTANCE = 360
local STREAM_DISTANCE_SQ = STREAM_DISTANCE * STREAM_DISTANCE
local REFRESH_SECONDS = 0.5
-- Stalk models built per frame. Lowered from 12 with the forest pass: a stalk is
-- now ~14 parts rather than ~10, so the old budget was building ~40% more parts
-- per frame than it was tuned for.
local BUILD_PER_FRAME = 8
local CUT_CORPSE_SECONDS = 0.85

type StalkEntry = {
	Id: number,
	Rarity: string,
	Mutation: string,
	VisualSeed: number,
	Stage: number,
	CutAt: number?,
	Model: Model?,
	Cutting: boolean,
}

type FieldEntry = {
	PlotId: string,
	PlotIndex: number,
	Plot: Model?,
	Folder: Folder?,
	Slots: { CFrame }?,
	GrowthLevel: number,
	RegrowSeconds: number,
	Stalks: { [number]: StalkEntry },
	Growing: { [number]: StalkEntry },
	Order: { number },
	BuildCursor: number,
	Active: boolean,
}

local _fields: { [string]: FieldEntry } = {}
local _frameBound = false
local _refreshAccumulator = 0
local _receivedSnapshot = false

local function _newField(plotId: string, plotIndex: number): FieldEntry
	return {
		PlotId = plotId,
		PlotIndex = plotIndex,
		Plot = nil,
		Folder = nil,
		Slots = nil,
		GrowthLevel = 0,
		RegrowSeconds = Bamboo.Value.RegrowSeconds(0),
		Stalks = {},
		Growing = {},
		Order = {},
		BuildCursor = 1,
		Active = false,
	}
end

local function _plotFor(field: FieldEntry): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end

	local plot = plots:FindFirstChild(field.PlotId)
	if plot and plot:IsA("Model") then
		field.Plot = plot
		return plot
	end

	field.Plot = nil
	return nil
end

local function _isOwned(field: FieldEntry): boolean
	local plot = field.Plot
	return plot ~= nil and plot:GetAttribute("OwnerUserId") == LOCAL_PLAYER.UserId
end

local function _observerPosition(): Vector3?
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position
	end

	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function _isInStream(field: FieldEntry): boolean
	if _isOwned(field) then
		return true
	end

	local plot = field.Plot
	local fieldPart = plot and plot:FindFirstChild("Field") :: BasePart?
	local observer = _observerPosition()
	if not fieldPart or not observer then
		return false
	end

	local offset = fieldPart.Position - observer
	return offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z <= STREAM_DISTANCE_SQ
end

local function _ensureFolder(field: FieldEntry): Folder?
	local plot = field.Plot
	if not plot then
		return nil
	end

	local existing = plot:FindFirstChild("Bamboo")
	if existing and not existing:IsA("Folder") then
		existing:Destroy()
		existing = nil
	end

	-- A pre-update server folder would contain replicated models. Remove it on
	-- this client so there can never be duplicate visuals during a live update.
	if existing and existing:GetAttribute("ClientOnly") ~= true then
		existing:Destroy()
		existing = nil
	end

	if not existing then
		local folder = Instance.new("Folder")
		folder.Name = "Bamboo"
		folder:SetAttribute("ClientOnly", true)
		folder.Parent = plot
		existing = folder
	end

	field.Folder = existing :: Folder
	return field.Folder
end

local function _ensureSlots(field: FieldEntry)
	if field.Slots then
		return
	end

	local plot = field.Plot
	local fieldPart = plot and plot:FindFirstChild("Field") :: BasePart?
	if not fieldPart then
		return
	end

	-- This is the same seed and transform used by PlotService. Sending 180 CFrames
	-- per plot would erase much of the bandwidth win, so positions are derived
	-- once on the clients that actually stream the plot.
	local offsets = Bamboo.Field.BuildSlots(
		Bamboo.Value.MaxPossibleStalks(),
		fieldPart.Size.X * 0.5,
		Random.new(field.PlotIndex * 7919)
	)
	local base = fieldPart.CFrame * CFrame.new(0, -0.1, 0)
	local slots = {}
	for index, offset in offsets do
		slots[index] = base * CFrame.new(offset)
	end
	field.Slots = slots
end

local function _destroyModel(stalk: StalkEntry)
	if stalk.Model then
		-- Release the pose entry before the Instance goes, so the shared pose loop
		-- never holds a destroyed model waiting for its own sweep to notice.
		StalkPose.Unregister(stalk.Model)
		stalk.Model:Destroy()
		stalk.Model = nil
	end
	stalk.Cutting = false
end

local function _unloadField(field: FieldEntry)
	if field.Folder then
		field.Folder:Destroy()
		field.Folder = nil
	end
	for _, stalk in field.Stalks do
		-- The folder destroy already removed the Instance, but clearing the
		-- references is what lets the stream-in path rebuild the field.
		_destroyModel(stalk)
	end
	field.BuildCursor = 1
	field.Active = false
end

local function _recordFromPayload(raw: any): StalkEntry?
	if type(raw) ~= "table" or type(raw.id) ~= "number" then
		return nil
	end

	return {
		Id = raw.id,
		Rarity = if type(raw.rarity) == "string" then raw.rarity else "Normal",
		Mutation = if type(raw.mutation) == "string" then raw.mutation else "None",
		VisualSeed = if type(raw.visualSeed) == "number" then raw.visualSeed else raw.id,
		Stage = if type(raw.stage) == "number" then raw.stage else Bamboo.Field.Stage.Mature,
		CutAt = if type(raw.cutAt) == "number" then raw.cutAt else nil,
		Model = nil,
		Cutting = false,
	}
end

local function _fieldFor(plotId: string, plotIndex: number?): FieldEntry
	local field = _fields[plotId]
	if field then
		if plotIndex then
			field.PlotIndex = plotIndex
		end
		return field
	end

	field = _newField(plotId, plotIndex or tonumber(string.match(plotId, "%d+")) or 0)
	_fields[plotId] = field
	return field
end

local function _applyPlotSnapshot(raw: any)
	if type(raw) ~= "table" or type(raw.plotId) ~= "string" then
		return
	end

	local field = _fieldFor(raw.plotId, raw.plotIndex)
	field.GrowthLevel = if type(raw.growthLevel) == "number" then raw.growthLevel else 0
	field.RegrowSeconds = if type(raw.regrowSeconds) == "number"
		then raw.regrowSeconds
		else Bamboo.Value.RegrowSeconds(field.GrowthLevel)

	local oldStalks = field.Stalks
	local oldOrder = field.Order
	field.Stalks = {}
	field.Growing = {}
	field.Order = {}
	field.BuildCursor = 1

	local seen: { [number]: boolean } = {}
	for _, rawStalk in (raw.stalks or {}) do
		local entry = _recordFromPayload(rawStalk)
		if entry then
			seen[entry.Id] = true
			local old = oldStalks[entry.Id]
			if
				old
				and old.Model
				and not old.Cutting
				and old.VisualSeed == entry.VisualSeed
				and old.Rarity == entry.Rarity
			then
				entry.Model = old.Model
				entry.Cutting = old.Cutting
			else
				if old then
					_destroyModel(old)
				end
			end
			field.Stalks[entry.Id] = entry
			if entry.CutAt then
				field.Growing[entry.Id] = entry
			end
			table.insert(field.Order, entry.Id)
		end
	end

	for _, id in oldOrder do
		if not seen[id] and oldStalks[id] then
			_destroyModel(oldStalks[id])
		end
	end

	table.sort(field.Order)
	field.Active = _isInStream(field)
	if field.Active then
		_ensureFolder(field)
		-- Only the owned plot derives its layout inline. The initial snapshot
		-- carries every plot in stream range, and deriving all of them here is the
		-- join-time freeze; the rest are picked up one per refresh tick.
		if _isOwned(field) then
			_ensureSlots(field)
		end
	end
end

local function _currentScale(field: FieldEntry, stalk: StalkEntry, now: number): number
	if not stalk.CutAt then
		return 1
	end
	local elapsed = math.max(now - stalk.CutAt, 0)
	return Bamboo.Value.GrowthScale(elapsed, field.GrowthLevel)
end

local function _currentStage(field: FieldEntry, stalk: StalkEntry, now: number): number
	if not stalk.CutAt then
		return Bamboo.Field.Stage.Mature
	end
	local elapsed = math.max(now - stalk.CutAt, 0)
	return Bamboo.Value.StageAt(elapsed, field.GrowthLevel)
end

local function _buildModel(field: FieldEntry, stalk: StalkEntry, now: number)
	if stalk.Model or stalk.Cutting or not field.Folder or not field.Slots then
		return
	end

	local base = field.Slots[stalk.Id]
	if not base then
		return
	end

	local rng = Random.new(stalk.VisualSeed)
	local visual = Bamboo.Rarity.RollVisual(stalk.Rarity, rng)
	visual.mutation = stalk.Mutation
	local model = BambooModel.Build(visual, base, rng)
	model.Name = "Stalk" .. stalk.Id
	model:SetAttribute("StalkId", stalk.Id)
	model:SetAttribute("Rarity", stalk.Rarity)
	model:SetAttribute("Mutation", stalk.Mutation)
	model:SetAttribute("Stage", stalk.Stage)
	local scale = _currentScale(field, stalk, now)
	model:SetAttribute("GrowthScale", scale)
	BambooModel.ApplyScale(model, scale, base)
	model.Parent = field.Folder
	stalk.Model = model
	stalk.Stage = _currentStage(field, stalk, now)
	model:SetAttribute("Stage", stalk.Stage)

	-- Hand the stalk to the shared pose loop. `base` is the authoritative rest
	-- frame: every sway, recoil, and topple is a rotation of it, which is what
	-- keeps repeated hits from accumulating drift.
	StalkPose.Register(model, stalk.Id, base, stalk.Rarity, stalk.Stage, scale)
end

local function _applyCut(field: FieldEntry, raw: any)
	local stalk = _recordFromPayload(raw.stalk)
	if not stalk then
		return
	end

	local old = field.Stalks[stalk.Id]
	if old then
		stalk.Model = old.Model
		stalk.Cutting = old.Cutting
	end
	field.Stalks[stalk.Id] = stalk
	if stalk.CutAt then
		field.Growing[stalk.Id] = stalk
	end
	if not table.find(field.Order, stalk.Id) then
		table.insert(field.Order, stalk.Id)
	end

	local model = stalk.Model
	if model and _isOwned(field) then
		stalk.Cutting = true
		task.delay(CUT_CORPSE_SECONDS, function()
			if stalk.Model == model and stalk.Cutting then
				_destroyModel(stalk)
			end
		end)
	else
		_destroyModel(stalk)
	end
end

local function _applyReplant(field: FieldEntry, raw: any)
	local nextStalk = _recordFromPayload(raw.stalk)
	if not nextStalk then
		return
	end

	local old = field.Stalks[nextStalk.Id]
	if old then
		_destroyModel(old)
	end
	field.Stalks[nextStalk.Id] = nextStalk
	if nextStalk.CutAt then
		field.Growing[nextStalk.Id] = nextStalk
	else
		field.Growing[nextStalk.Id] = nil
	end
	if not table.find(field.Order, nextStalk.Id) then
		table.insert(field.Order, nextStalk.Id)
		table.sort(field.Order)
	end
	-- Re-scan from the beginning: a server-side Chain cut can have removed a
	-- stalk whose id was already passed by the incremental build cursor.
	field.BuildCursor = 1
end

local function _applyDelta(payload: any)
	if type(payload) ~= "table" then
		return
	end

	if payload.kind == "clear" and type(payload.plotId) == "string" then
		local field = _fields[payload.plotId]
		if field then
			_unloadField(field)
			_fields[payload.plotId] = nil
		end
		return
	end

	if payload.kind == "snapshot" then
		_applyPlotSnapshot(payload.plot)
		return
	end

	if payload.kind ~= "changes" or type(payload.changes) ~= "table" then
		return
	end

	for _, change in payload.changes do
		if type(change) ~= "table" or type(change.plotId) ~= "string" then
			continue
		end
		local field = _fieldFor(change.plotId, change.plotIndex)
		if change.kind == "config" then
			field.GrowthLevel = if type(change.growthLevel) == "number" then change.growthLevel else field.GrowthLevel
			field.RegrowSeconds = if type(change.regrowSeconds) == "number"
				then change.regrowSeconds
				else field.RegrowSeconds
		elseif change.kind == "stalk" and change.action == "cut" then
			_applyCut(field, change)
		elseif change.kind == "stalk" and change.action == "replant" then
			_applyReplant(field, change)
		end
	end
end

-- Deriving a plot's slot layout is the single most expensive thing this
-- controller does: Field.BuildSlots dart-throws for a fully-upgraded field and
-- then runs a farthest-point traversal, which is O(n^2) in the stalk count. At
-- Field.DensityMaxStalks possible stalks that is still tens of thousands of
-- operations, synchronously.
--
-- Doing that for every plot inside the 360-stud stream radius in one frame is a
-- visible freeze on join, and a freeze is not harmless here: it used to make the
-- rotor bank a hitch's worth of swings and burst them past the server's rate
-- limit. So only one *unowned* plot is derived per refresh tick, spreading the
-- cost over a few seconds. The owned plot is always derived immediately — that
-- is the field the player is standing in.
local function _refreshFields()
	local deferred: FieldEntry? = nil

	for _, field in _fields do
		_plotFor(field)
		local shouldBeActive = _isInStream(field)
		if shouldBeActive then
			field.Active = true
			_ensureFolder(field)
			if field.Slots or _isOwned(field) then
				_ensureSlots(field)
			elseif not deferred then
				-- First plot still missing a layout; the rest wait their turn.
				deferred = field
			end
		elseif field.Active then
			_unloadField(field)
		end
	end

	if deferred then
		_ensureSlots(deferred)
	end
end

local function _processBuildQueue(now: number)
	local budget = BUILD_PER_FRAME
	for _, field in _fields do
		if budget <= 0 then
			break
		end
		if not field.Active or not field.Folder or not field.Slots then
			continue
		end

		while budget > 0 and field.BuildCursor <= #field.Order do
			local id = field.Order[field.BuildCursor]
			field.BuildCursor += 1
			local stalk = field.Stalks[id]
			if stalk and not stalk.Model and not stalk.Cutting then
				_buildModel(field, stalk, now)
				budget -= 1
			end
		end
	end
end

local function _updateGrowing(now: number)
	for _, field in _fields do
		if not field.Active or not field.Slots then
			continue
		end
		for id, stalk in field.Growing do
			local model = stalk.Model
			if not stalk.CutAt then
				field.Growing[id] = nil
				continue
			end
			if not model or stalk.Cutting then
				continue
			end

			local stage = _currentStage(field, stalk, now)
			local scale = _currentScale(field, stalk, now)
			local stageChanged = stage ~= stalk.Stage
			if stageChanged then
				stalk.Stage = stage
				model:SetAttribute("Stage", stage)
			end
			BambooModel.ApplyScale(model, scale, field.Slots[stalk.Id])
			-- ApplyScale relaid every part from the slot frame, so the pose loop's
			-- cached rest pivot has to be refreshed before it rotates the stalk.
			StalkPose.SyncGrowth(model, stage, scale, stalk.Rarity)
			if stageChanged then
				-- Reaching a new stage gets a scale punch. Mature is the one that
				-- matters: it is the visual announcement that the stalk is cuttable.
				StalkPose.Pop(model, stage)
			end
			if stage == Bamboo.Field.Stage.Mature and scale >= 0.999 then
				-- The server may keep the timestamp until its next growth tick; the
				-- client no longer needs to spend a frame on this settled stalk.
				stalk.CutAt = nil
				field.Growing[id] = nil
			end
		end
	end
end

local function _hasFrameWork(): boolean
	for _, field in _fields do
		if field.Active and field.BuildCursor <= #field.Order then
			return true
		end
		if field.Active then
			for _, stalk in field.Growing do
				if stalk.Model and not stalk.Cutting then
					return true
				end
			end
		end
	end
	return false
end

local function _frameUpdate(_dt: number)
	local now = workspace:GetServerTimeNow()
	_processBuildQueue(now)
	_updateGrowing(now)

	if not _hasFrameWork() and _frameBound then
		RunService:UnbindFromRenderStep(GROWTH_BIND)
		_frameBound = false
	end
end

local function _ensureFrameLoop()
	if _frameBound or not _hasFrameWork() then
		return
	end
	_frameBound = true
	RunService:BindToRenderStep(GROWTH_BIND, Enum.RenderPriority.Character.Value + 1, _frameUpdate)
end

function BambooGrowthController:GetOwnedFolder(): Folder?
	for _, field in _fields do
		if _isOwned(field) then
			return field.Folder
		end
	end
	return nil
end

-- Used by the sickle rotor. It reads the compact state/slot cache instead of
-- walking every rendered descendant on every render frame.
function BambooGrowthController:HasMatureInRange(origin: Vector3, range: number): boolean
	local rangeSq = range * range
	local now = workspace:GetServerTimeNow()
	for _, field in _fields do
		if _isOwned(field) and field.Active and field.Slots then
			for _, stalk in field.Stalks do
				local stage = if stalk.CutAt then _currentStage(field, stalk, now) else stalk.Stage
				if stage == Bamboo.Field.Stage.Mature then
					local slot = field.Slots[stalk.Id]
					if slot then
						local offset = slot.Position - origin
						if offset.X * offset.X + offset.Z * offset.Z <= rangeSq then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

function BambooGrowthController:Start(_fw: any)
	Relay.Bamboo.StateSnapshot.listen(function(payload: any)
		_receivedSnapshot = true
		local seen: { [string]: boolean } = {}
		for _, plot in payload.plots or {} do
			if type(plot) == "table" and type(plot.plotId) == "string" then
				seen[plot.plotId] = true
			end
			_applyPlotSnapshot(plot)
		end
		local stalePlotIds = {}
		for plotId, field in _fields do
			if not seen[plotId] then
				_unloadField(field)
				table.insert(stalePlotIds, plotId)
			end
		end
		for _, plotId in stalePlotIds do
			_fields[plotId] = nil
		end
		_ensureFrameLoop()
	end)
	Relay.Bamboo.StateDelta.listen(_applyDelta)

	RunService.Heartbeat:Connect(function(dt: number)
		_refreshAccumulator += dt
		if _refreshAccumulator < REFRESH_SECONDS then
			return
		end
		_refreshAccumulator = 0
		_refreshFields()
		_ensureFrameLoop()
	end)

	-- The request is delayed slightly so the server's BambooService listener and
	-- the replicated plot models are both ready. A retry covers slow first loads.
	task.delay(0.75, function()
		if not _receivedSnapshot then
			Relay.Bamboo.StateRequest.send({})
		end
	end)
	task.delay(2.5, function()
		if not _receivedSnapshot then
			Relay.Bamboo.StateRequest.send({})
		end
	end)
end

return BambooGrowthController
