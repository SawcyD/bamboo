--!strict
-- Ground drops: bamboo that overflowed a full bag, waiting to be walked over.
--
-- Drops are real server-owned state, not client decoration: the server decides
-- what a drop is worth, who may pick it up, and when it expires. The visual is
-- parented into the plot so every client sees the same field.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Sickles = Core:GetDomain("Sickles")
local Relay = Core:GetShared("Network")

local DropService = {}
local Framework

local DROP_TAG = "BambooDrop"
local PICKUP_TICK_SECONDS = 0.15
local EXPIRY_TICK_SECONDS = 1

type Drop = {
	Id: number,
	Amount: number,
	Rarity: string,
	Position: Vector3,
	SpawnedAt: number,
	Model: BasePart,
}

type PlotDrops = {
	Plot: any,
	Folder: Folder,
	-- Insertion-ordered, so trimming to MaxPerPlot always drops the oldest.
	Drops: { Drop },
}

local _plotDrops: { [string]: PlotDrops } = {}
local _nextDropId = 0

-- ── visuals ──────────────────────────────────────────────────────────────────

local function _buildDropPart(drop: Drop, parent: Instance): BasePart
	local rarity = Bamboo.Rarity.Get(drop.Rarity)
	local scale = 0.8 + math.min(drop.Amount / 20, 1) * 0.7

	local part = Instance.new("Part")
	part.Name = "BambooDrop"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(1.9 * scale, 0.55 * scale, 0.55 * scale)
	part.Color = rarity.color
	part.Material = Enum.Material.Grass
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(drop.Position + Vector3.new(0, 1.6, 0))
		* CFrame.Angles(0, math.random() * math.pi * 2, math.rad(90))

	-- The client bobs, spins, and blinks these; it needs the amount for the label
	-- and the spawn clock to know how close the drop is to expiring.
	part:SetAttribute("Amount", drop.Amount)
	part:SetAttribute("Rarity", drop.Rarity)
	part:SetAttribute("SpawnedAt", workspace:GetServerTimeNow())
	part:AddTag(DROP_TAG)
	part.Parent = parent

	return part
end

-- ── registry ─────────────────────────────────────────────────────────────────

local function _stateFor(plot: any): PlotDrops
	local state = _plotDrops[plot.Id]
	if state then
		return state
	end

	local existing = plot.Model:FindFirstChild("Drops")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "Drops"
	folder.Parent = plot.Model

	state = { Plot = plot, Folder = folder, Drops = {} }
	_plotDrops[plot.Id] = state
	return state
end

local function _removeDrop(state: PlotDrops, index: number)
	local drop = state.Drops[index]
	if not drop then
		return
	end
	drop.Model:Destroy()
	table.remove(state.Drops, index)
end

-- A fresh drop close enough to an existing one of the same rarity merges into
-- it, so a four-stalk break leaves a few worthwhile piles instead of a dozen.
local function _findMergeTarget(state: PlotDrops, position: Vector3, rarity: string): Drop?
	local radiusSq = Bamboo.Drops.MergeRadius ^ 2
	for _, drop in state.Drops do
		if drop.Rarity == rarity and (drop.Position - position).Magnitude ^ 2 <= radiusSq then
			return drop
		end
	end
	return nil
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

local function _tickExpiry()
	local now = os.clock()
	local despawn = Bamboo.Drops.DespawnSeconds

	for _, state in _plotDrops do
		for index = #state.Drops, 1, -1 do
			if now - state.Drops[index].SpawnedAt >= despawn then
				_removeDrop(state, index)
			end
		end
	end
end

-- Magnet sickles vacuum from much further out; everyone else uses the base
-- radius. Read per player, since it depends on what they have equipped.
local function _pickupRadiusFor(player: Player): number
	local SickleService = Framework:GetService("SickleService")
	local equipped = SickleService.GetEquipped(player)
	if equipped.ability == "Magnet" then
		return Bamboo.Drops.PickupRadius * Sickles.Abilities.MagnetRadiusMultiplier
	end
	return Bamboo.Drops.PickupRadius
end

local function _tickPickup()
	local PlotService = Framework:GetService("PlotService")
	local DataService = Framework:GetService("DataService")

	for _, player in Players:GetPlayers() do
		local plot = PlotService.GetPlot(player)
		if not plot then
			continue
		end
		local state = _plotDrops[plot.Id]
		if not state or #state.Drops == 0 then
			continue
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end

		-- The stockpile has no capacity limit, so there is never a reason to skip
		-- a pickup here — unlike the old bag, room is never the blocker.
		local room = math.huge

		local radiusSq = _pickupRadiusFor(player) ^ 2
		local collected: { any } = {}
		local total = 0

		for index = #state.Drops, 1, -1 do
			if room <= 0 then
				break
			end
			local drop = state.Drops[index]
			if (drop.Position - root.Position).Magnitude ^ 2 > radiusSq then
				continue
			end

			local taken = math.min(drop.Amount, room)
			room -= taken
			total += taken
			table.insert(collected, { position = drop.Position, amount = taken, rarity = drop.Rarity })

			drop.Amount -= taken
			if drop.Amount <= 0 then
				_removeDrop(state, index)
			else
				-- Partial pickup: the pile shrinks rather than vanishing.
				drop.Model:SetAttribute("Amount", drop.Amount)
			end
		end

		if total > 0 then
			DataService.Increment(player, "BambooStock", total)
			DataService.Increment(player, "LifetimeBambooCollected", total)
			Relay.Bamboo.DropsCollected.sendTo({ drops = collected, total = total }, player)
		end
	end
end

function DropService:Start(fw: any)
	Framework = fw

	local pickupAccumulator = 0
	local expiryAccumulator = 0

	RunService.Heartbeat:Connect(function(dt: number)
		pickupAccumulator += dt
		if pickupAccumulator >= PICKUP_TICK_SECONDS then
			pickupAccumulator = 0
			_tickPickup()
		end

		expiryAccumulator += dt
		if expiryAccumulator >= EXPIRY_TICK_SECONDS then
			expiryAccumulator = 0
			_tickExpiry()
		end
	end)
end

-- ── public API ───────────────────────────────────────────────────────────────

--[[
	Drops bamboo on the ground for a plot's owner to walk over later.
	Merges into a nearby pile of the same rarity when there is one.
	@param plot Plot The plot record from PlotService.
	@param position Vector3 Where the stalk stood.
	@param amount number Bamboo the drop is worth; ignored when <= 0.
	@param rarity string Rarity id, which sets the drop's colour.
]]
function DropService.Spawn(plot: any, position: Vector3, amount: number, rarity: string)
	if amount <= 0 then
		return
	end

	local state = _stateFor(plot)

	local merged = _findMergeTarget(state, position, rarity)
	if merged then
		merged.Amount += amount
		merged.Model:SetAttribute("Amount", merged.Amount)
		-- Merging refreshes the timer, so an active field never expires under you.
		merged.SpawnedAt = os.clock()
		merged.Model:SetAttribute("SpawnedAt", workspace:GetServerTimeNow())
		return
	end

	_nextDropId += 1
	local drop: Drop = {
		Id = _nextDropId,
		Amount = amount,
		Rarity = rarity,
		Position = position,
		SpawnedAt = os.clock(),
		Model = nil :: any,
	}
	drop.Model = _buildDropPart(drop, state.Folder)
	table.insert(state.Drops, drop)

	-- Trim from the front so the oldest pile is the one that goes.
	while #state.Drops > Bamboo.Drops.MaxPerPlot do
		_removeDrop(state, 1)
	end
end

--[[
	Clears every drop on a plot, e.g. when its owner leaves.
	@param plot Plot The plot record from PlotService.
]]
function DropService.ClearPlot(plot: any)
	local state = _plotDrops[plot.Id]
	if state then
		state.Folder:Destroy()
		_plotDrops[plot.Id] = nil
	end
	local stale = plot.Model:FindFirstChild("Drops")
	if stale then
		stale:Destroy()
	end
end

--[[
	How much loose bamboo is sitting on a plot right now.
	@param plot Plot The plot record from PlotService.
	@return number Total bamboo across every drop.
]]
function DropService.GetPendingAmount(plot: any): number
	local state = _plotDrops[plot.Id]
	if not state then
		return 0
	end
	local total = 0
	for _, drop in state.Drops do
		total += drop.Amount
	end
	return total
end

return DropService
