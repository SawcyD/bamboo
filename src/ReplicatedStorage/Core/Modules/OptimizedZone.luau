--!strict
--[[
	OptimizedZone: spatial trigger zones for players and tagged instances.

	Detection runs through Roblox's spatial queries (GetPartBoundsInBox /
	GetPartBoundsInRadius) on a single shared Heartbeat — one connection drives
	every zone instead of one-per-zone — and each zone only re-checks at its own
	DetectionRate, staggered across frames so they don't all spike together.

	Quick start
	-----------
		local Zone = Core:Get("OptimizedZone")

		local lobby = Zone.fromPart(workspace.LobbyZone, {
			Priority = 1,
			StayTime = 3,
		})

		lobby.PlayerEntered:Connect(function(player) print(player, "entered") end)
		lobby.PlayerExited:Connect(function(player) print(player, "left") end)
		lobby.PlayerStayed:Connect(function(player) print(player, "stayed 3s") end)

	Constructors
	------------
		Zone.fromPart(part, opts?)            single BasePart (box, may move/rotate)
		Zone.fromParts({part, ...}, opts?)    compound zone: inside any part
		Zone.fromContainer(model, opts?)      every BasePart descendant of a model
		Zone.fromRegion(cframe, size, opts?)  virtual box, no instance needed
		Zone.fromSphere(centerOrPart, r, o?)  spherical zone
		Zone.new(part, opts?)                 alias for fromPart

	Options (all optional)
	----------------------
		DetectionMode   "Center" (HumanoidRootPart, default) | "WholeBody"
		DetectionRate   checks per second (default 30); lower = cheaper
		StayTime        seconds inside before PlayerStayed fires (default 5)
		NearbyDistance  fire PlayerNearby within this many studs of the zone
		NearbyRate      max PlayerNearby fires/sec (default = DetectionRate)
		Priority        higher wins GetTopZone / overlap resolution (default 0)
		ExitPadding     hysteresis: studs you must leave past the edge to exit
		Tags            { "Tag", ... } also track tagged instances (ItemEntered/Exited)
		ShouldTrigger   (subject) -> boolean filter, re-checked live each step
		DetectsPlayers  set false for a tags-only zone (default true)
		AutoStart       false to create the zone paused (default true)

	Signals (typed)
	---------------
		PlayerEntered (player) | PlayerExited (player) | PlayerStayed (player)
		PlayerNearby (player, distance)
		ItemEntered (instance, tag) | ItemExited (instance, tag) | ItemStayed (instance, tag)

	Lifecycle: Start() / Stop() / Enable() / Disable() / Destroy().
	Promises:  OnPlayerEnteredAsync(player?) / WaitForEmpty().
	Debug:     ShowDebug(color?) / HideDebug() to visualize the volume in Studio.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
-- Signal is required directly (not via Core:Get) so its exported types resolve
-- for autocomplete on zone.PlayerEntered:Connect(...) etc.
local Signal = require(script.Parent:WaitForChild("Signal"))
local Janitor = Core:Get("Janitor")
local Promise = Core:GetPackage("Promise")
-- shared Hz scheduler: zones tick from the one game-wide Heartbeat, not their own
local Scheduler = require(script.Parent:WaitForChild("Scheduler"))

local DEFAULTS = {
	DetectionRate = 30,
	StayTime = 5,
	DetectionMode = "Center",
}

-- one OverlapParams reused for every query; FilterDescendantsInstances is set
-- per-query (synchronous, single-threaded, so sharing is safe)
local sharedParams = OverlapParams.new()
sharedParams.FilterType = Enum.RaycastFilterType.Include

--------------------------------------------------------------------------------
-- geometry helpers
--------------------------------------------------------------------------------

local function pointInBox(cframe: CFrame, size: Vector3, point: Vector3): boolean
	local rel = cframe:PointToObjectSpace(point)
	local half = size * 0.5
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

--------------------------------------------------------------------------------
-- module-level registries (shared across all zones)
--------------------------------------------------------------------------------

local playerZones: { [Player]: { [any]: boolean } } = {}

local function registerPlayerZone(player: Player, zone: any)
	local set = playerZones[player]
	if not set then
		set = {}
		playerZones[player] = set
	end
	set[zone] = true
end

local function unregisterPlayerZone(player: Player, zone: any)
	local set = playerZones[player]
	if set then
		set[zone] = nil
		if next(set) == nil then
			playerZones[player] = nil
		end
	end
end

--------------------------------------------------------------------------------
-- running-zone registry (for GetZonesAtPoint) + shared per-frame part cache
--------------------------------------------------------------------------------

-- zones currently ticking; each owns a Scheduler handle that drives its _step
local runningZones: { [any]: boolean } = {}

-- per-frame cache of character parts, shared by every zone ticking this frame.
-- Keyed on Scheduler.GetFrame() so all zones stepping in the same Heartbeat build
-- the include list at most once.
local partCache = {
	Center = { frame = -1, parts = {} :: { BasePart }, map = {} :: { [BasePart]: Player } },
	WholeBody = { frame = -1, parts = {} :: { BasePart }, map = {} :: { [BasePart]: Player } },
}

local function getPlayerParts(mode: string): ({ BasePart }, { [BasePart]: Player })
	local cache = partCache[mode] or partCache.Center
	local frameId = Scheduler.GetFrame()
	if cache.frame == frameId then
		return cache.parts, cache.map
	end

	local parts: { BasePart } = {}
	local map: { [BasePart]: Player } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end
		if mode == "WholeBody" then
			for _, child in character:GetChildren() do
				if child:IsA("BasePart") then
					table.insert(parts, child)
					map[child] = player
				end
			end
		else
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				table.insert(parts, root)
				map[root] = player
			end
		end
	end

	cache.frame = frameId
	cache.parts = parts
	cache.map = map
	return parts, map
end

--------------------------------------------------------------------------------
-- Zone class
--------------------------------------------------------------------------------

local Zone = {}
Zone.__index = Zone

type Box = { part: BasePart?, cframe: CFrame?, size: Vector3? }
type PlayerRecord = { stay: number, stayFired: boolean }
type ItemRecord = { stay: number, stayFired: boolean }

type Options = {
	DetectionMode: ("Center" | "WholeBody")?,
	DetectionRate: number?,
	StayTime: number?,
	NearbyDistance: number?,
	NearbyRate: number?,
	Priority: number?,
	ExitPadding: number?,
	Tags: { string }?,
	ShouldTrigger: ((subject: Instance) -> boolean)?,
	DetectsPlayers: boolean?,
	AutoStart: boolean?,
}

export type ZoneInstance = typeof(setmetatable(
	{} :: {
		Janitor: any,
		Enabled: boolean,
		Priority: number,
		DetectionMode: string,
		DetectionRate: number,
		StayTime: number,
		NearbyDistance: number?,
		NearbyRate: number,
		ExitPadding: number,
		DetectsPlayers: boolean,
		ShouldTrigger: ((subject: Instance) -> boolean)?,

		PlayerEntered: Signal.Signal<Player>,
		PlayerExited: Signal.Signal<Player>,
		PlayerStayed: Signal.Signal<Player>,
		PlayerNearby: Signal.Signal<Player, number>,
		ItemEntered: Signal.Signal<Instance, string>,
		ItemExited: Signal.Signal<Instance, string>,
		ItemStayed: Signal.Signal<Instance, string>,

		_shape: string,
		_boxes: { Box },
		_sphere: { anchor: BasePart?, center: Vector3, radius: number }?,
		_handle: Scheduler.Handle?,
		_players: { [Player]: PlayerRecord },
		_items: { [Instance]: ItemRecord },
		_nearby: { [Player]: number },
		_tags: { string }?,
		_tagsDirty: boolean,
		_tagParts: { BasePart },
		_tagOwner: { [BasePart]: Instance },
		_tagPartOf: { [Instance]: BasePart },
		_tagOf: { [Instance]: string },
		_taggedSubjects: { Instance },
		_debug: { Instance }?,
	},
	Zone
))

--------------------------------------------------------------------------------
-- construction
--------------------------------------------------------------------------------

local function build(shape: string, opts: Options?): ZoneInstance
	local options: Options = opts or {}
	local self = setmetatable({}, Zone)

	self.Janitor = Janitor.new()
	self.Enabled = true
	self.Priority = options.Priority or 0
	self.DetectionMode = options.DetectionMode or DEFAULTS.DetectionMode
	self.DetectionRate = math.max(options.DetectionRate or DEFAULTS.DetectionRate, 1)
	self.StayTime = options.StayTime or DEFAULTS.StayTime
	self.NearbyDistance = options.NearbyDistance
	self.NearbyRate = math.max(options.NearbyRate or self.DetectionRate, 1)
	self.ExitPadding = math.max(options.ExitPadding or 0, 0)
	self.DetectsPlayers = options.DetectsPlayers ~= false
	self.ShouldTrigger = options.ShouldTrigger

	self._shape = shape
	self._boxes = {}
	self._players = {}
	self._items = {}
	self._nearby = {}

	self.PlayerEntered = Signal.new()
	self.PlayerExited = Signal.new()
	self.PlayerStayed = Signal.new()
	self.PlayerNearby = Signal.new()
	self.ItemEntered = Signal.new()
	self.ItemExited = Signal.new()
	self.ItemStayed = Signal.new()
	for _, sig in
		{
			self.PlayerEntered,
			self.PlayerExited,
			self.PlayerStayed,
			self.PlayerNearby,
			self.ItemEntered,
			self.ItemExited,
			self.ItemStayed,
		}
	do
		self.Janitor:Add(sig, "Destroy")
	end

	if options.Tags and #options.Tags > 0 then
		self._tags = options.Tags
		self._tagsDirty = true
		self._tagParts = {}
		self._tagOwner = {}
		self._tagPartOf = {}
		self._tagOf = {}
		self._taggedSubjects = {}
		for _, tag in options.Tags do
			local function markDirty()
				self._tagsDirty = true
			end
			self.Janitor:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(markDirty))
			self.Janitor:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(markDirty))
		end
	end

	if options.AutoStart ~= false then
		self:Start()
	end

	return (self :: any) :: ZoneInstance
end

function Zone.fromPart(part: BasePart, opts: Options?): ZoneInstance
	local self = build("Box", opts)
	self._boxes = { { part = part } }
	return self
end

function Zone.fromParts(parts: { BasePart }, opts: Options?): ZoneInstance
	local self = build("Box", opts)
	for _, part in parts do
		table.insert(self._boxes, { part = part })
	end
	return self
end

function Zone.fromContainer(container: Instance, opts: Options?): ZoneInstance
	local self = build("Box", opts)
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(self._boxes, { part = descendant })
		end
	end
	if container:IsA("BasePart") then
		table.insert(self._boxes, { part = container })
	end
	return self
end

function Zone.fromRegion(cframe: CFrame, size: Vector3, opts: Options?): ZoneInstance
	assert(size.X > 0 and size.Y > 0 and size.Z > 0, "OptimizedZone.fromRegion: size must be positive on every axis")
	local self = build("Box", opts)
	self._boxes = { { cframe = cframe, size = size } }
	return self
end

function Zone.fromSphere(center: Vector3 | BasePart, radius: number, opts: Options?): ZoneInstance
	assert(radius > 0, "OptimizedZone.fromSphere: radius must be positive")
	local self = build("Sphere", opts)
	if typeof(center) == "Instance" then
		self._sphere = { anchor = center, center = center.Position, radius = radius }
	else
		self._sphere = { anchor = nil, center = center, radius = radius }
	end
	return self
end

-- familiar alias
Zone.new = Zone.fromPart

--------------------------------------------------------------------------------
-- geometry accessors (read live so welded / moving parts just work)
--------------------------------------------------------------------------------

function Zone._boxCFrame(_self: ZoneInstance, box: Box): CFrame
	return if box.part then box.part.CFrame else box.cframe :: CFrame
end

function Zone._boxSize(_self: ZoneInstance, box: Box): Vector3
	return if box.part then box.part.Size else box.size :: Vector3
end

function Zone._sphereCenter(self: ZoneInstance): Vector3
	local sphere = self._sphere :: { anchor: BasePart?, center: Vector3, radius: number }
	return if sphere.anchor then sphere.anchor.Position else sphere.center
end

function Zone._containsPoint(self: ZoneInstance, point: Vector3): boolean
	if self._shape == "Sphere" then
		local sphere = self._sphere :: { center: Vector3, radius: number, anchor: BasePart? }
		return (self:_sphereCenter() - point).Magnitude <= sphere.radius
	end
	for _, box in self._boxes do
		if pointInBox(self:_boxCFrame(box), self:_boxSize(box), point) then
			return true
		end
	end
	return false
end

function Zone._nearestCenter(self: ZoneInstance, point: Vector3): number
	if self._shape == "Sphere" then
		return (self:_sphereCenter() - point).Magnitude
	end
	local best = math.huge
	for _, box in self._boxes do
		local distance = (self:_boxCFrame(box).Position - point).Magnitude
		if distance < best then
			best = distance
		end
	end
	return best
end

-- run the spatial query (boxes or sphere) inflated by `padding`, calling `onHit`
-- for every part returned. `sharedParams.FilterDescendantsInstances` must be set
-- by the caller first.
function Zone._forEachHit(self: ZoneInstance, padding: number, onHit: (BasePart) -> ())
	if self._shape == "Sphere" then
		local sphere = self._sphere :: { center: Vector3, radius: number, anchor: BasePart? }
		for _, part in workspace:GetPartBoundsInRadius(self:_sphereCenter(), sphere.radius + padding, sharedParams) do
			onHit(part)
		end
	else
		local inflate = Vector3.one * (padding * 2)
		for _, box in self._boxes do
			for _, part in
				workspace:GetPartBoundsInBox(self:_boxCFrame(box), self:_boxSize(box) + inflate, sharedParams)
			do
				onHit(part)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- per-tick detection
--------------------------------------------------------------------------------

function Zone._playerInInner(self: ZoneInstance, player: Player, mode: string): boolean
	local character = player.Character
	if not character then
		return false
	end
	if mode == "WholeBody" then
		for _, child in character:GetChildren() do
			if child:IsA("BasePart") and self:_containsPoint(child.Position) then
				return true
			end
		end
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and self:_containsPoint((root :: BasePart).Position)
end

function Zone._stepPlayers(self: ZoneInstance, dt: number, now: number)
	local mode = self.DetectionMode
	local includeParts, partToPlayer = getPlayerParts(mode)
	sharedParams.FilterDescendantsInstances = includeParts

	-- players with at least one relevant part inside the OUTER (padded) boundary
	local outer: { [Player]: boolean } = {}
	self:_forEachHit(self.ExitPadding, function(part)
		local player = partToPlayer[part]
		if player then
			outer[player] = true
		end
	end)

	local shouldTrigger = self.ShouldTrigger
	for _, player in Players:GetPlayers() do
		local record = self._players[player]
		local allowed = (shouldTrigger == nil) or shouldTrigger(player)

		local isInside: boolean
		if not allowed then
			isInside = false
		elseif record then
			-- already inside: lenient exit at the padded boundary (hysteresis)
			isInside = outer[player] == true
		else
			-- entering: strict, must be within the true inner volume
			isInside = (outer[player] == true) and self:_playerInInner(player, mode)
		end

		if isInside and not record then
			record = { stay = 0, stayFired = false }
			self._players[player] = record
			registerPlayerZone(player, self)
			self.PlayerEntered:Fire(player)
		elseif (not isInside) and record then
			self._players[player] = nil
			unregisterPlayerZone(player, self)
			self.PlayerExited:Fire(player)
			record = nil
		end

		if record and not record.stayFired then
			record.stay += dt
			if record.stay >= self.StayTime then
				record.stayFired = true
				self.PlayerStayed:Fire(player)
			end
		end

		if self.NearbyDistance and allowed then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local distance = self:_nearestCenter(root.Position)
				if distance <= self.NearbyDistance and now >= (self._nearby[player] or 0) then
					self._nearby[player] = now + (1 / self.NearbyRate)
					self.PlayerNearby:Fire(player, distance)
				end
			end
		end
	end
end

function Zone._refreshTagParts(self: ZoneInstance)
	if not self._tagsDirty then
		return
	end
	self._tagsDirty = false
	table.clear(self._tagParts)
	table.clear(self._tagOwner)
	table.clear(self._tagPartOf)
	table.clear(self._tagOf)
	table.clear(self._taggedSubjects)

	for _, tag in self._tags :: { string } do
		for _, instance in CollectionService:GetTagged(tag) do
			local part: BasePart? = nil
			if instance:IsA("Model") then
				part = instance.PrimaryPart
			elseif instance:IsA("BasePart") then
				part = instance
			end
			if part then
				table.insert(self._tagParts, part)
				self._tagOwner[part] = instance
				self._tagPartOf[instance] = part
				self._tagOf[instance] = tag
				table.insert(self._taggedSubjects, instance)
			end
		end
	end
end

function Zone._stepTagged(self: ZoneInstance, dt: number, _now: number)
	self:_refreshTagParts()
	sharedParams.FilterDescendantsInstances = self._tagParts

	local outer: { [Instance]: boolean } = {}
	self:_forEachHit(self.ExitPadding, function(part)
		local owner = self._tagOwner[part]
		if owner then
			outer[owner] = true
		end
	end)

	local shouldTrigger = self.ShouldTrigger
	for _, instance in self._taggedSubjects do
		if not instance.Parent then
			continue
		end
		local allowed = (shouldTrigger == nil) or shouldTrigger(instance)
		local record = self._items[instance]

		local isInside: boolean
		if not allowed then
			isInside = false
		elseif record then
			isInside = outer[instance] == true
		else
			local part = self._tagPartOf[instance]
			isInside = (outer[instance] == true) and part ~= nil and self:_containsPoint(part.Position)
		end

		if isInside and not record then
			record = { stay = 0, stayFired = false }
			self._items[instance] = record
			self.ItemEntered:Fire(instance, self._tagOf[instance])
		elseif (not isInside) and record then
			self._items[instance] = nil
			self.ItemExited:Fire(instance, self._tagOf[instance])
			record = nil
		end

		if record and not record.stayFired then
			record.stay += dt
			if record.stay >= self.StayTime then
				record.stayFired = true
				self.ItemStayed:Fire(instance, self._tagOf[instance])
			end
		end
	end
end

function Zone._step(self: ZoneInstance, dt: number, now: number)
	if self.DetectsPlayers then
		self:_stepPlayers(dt, now)
	end
	if self._tags then
		self:_stepTagged(dt, now)
	end
end

-- fire exits for everyone currently inside and clear tracking state
function Zone._flush(self: ZoneInstance)
	for player in self._players do
		self._players[player] = nil
		unregisterPlayerZone(player, self)
		self.PlayerExited:Fire(player)
	end
	for instance in self._items do
		self._items[instance] = nil
		self.ItemExited:Fire(instance, self._tagOf and self._tagOf[instance] or "")
	end
	table.clear(self._nearby)
end

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

function Zone.Start(self: ZoneInstance)
	if self._handle then
		return
	end
	runningZones[self] = true
	self._handle = Scheduler.Every(self.DetectionRate, function(dt)
		if self.Enabled then
			self:_step(dt, workspace:GetServerTimeNow())
		end
	end)
end

function Zone.Stop(self: ZoneInstance)
	if self._handle then
		self._handle:Disconnect()
		self._handle = nil
	end
	runningZones[self] = nil
	self:_flush()
end

function Zone.Enable(self: ZoneInstance)
	self.Enabled = true
end

function Zone.Disable(self: ZoneInstance)
	self.Enabled = false
	self:_flush()
end

function Zone.Destroy(self: ZoneInstance)
	self:Stop()
	self:HideDebug()
	self.Janitor:Cleanup()
	table.clear(self._players)
	table.clear(self._items)
	table.clear(self._nearby)
	table.clear(self._boxes)
end

--------------------------------------------------------------------------------
-- queries
--------------------------------------------------------------------------------

function Zone.GetPlayers(self: ZoneInstance): { Player }
	local out = {}
	for player in self._players do
		table.insert(out, player)
	end
	return out
end

function Zone.GetPlayerCount(self: ZoneInstance): number
	local count = 0
	for _ in self._players do
		count += 1
	end
	return count
end

function Zone.IsPlayerInside(self: ZoneInstance, player: Player): boolean
	return self._players[player] ~= nil
end

function Zone.GetItems(self: ZoneInstance): { Instance }
	local out = {}
	for instance in self._items do
		table.insert(out, instance)
	end
	return out
end

function Zone.IsEmpty(self: ZoneInstance): boolean
	return next(self._players) == nil and next(self._items) == nil
end

function Zone.IsPointInside(self: ZoneInstance, point: Vector3): boolean
	return self:_containsPoint(point)
end

function Zone.SetPriority(self: ZoneInstance, priority: number)
	self.Priority = priority
end

function Zone.SetDetectionRate(self: ZoneInstance, rate: number)
	self.DetectionRate = math.max(rate, 1)
	if self._handle then
		self._handle:SetRate(self.DetectionRate)
	end
end

-- move a region/sphere zone (errors on part-backed zones — move the part instead)
function Zone.Relocate(self: ZoneInstance, cframe: CFrame)
	if self._shape == "Sphere" then
		local sphere = self._sphere :: { anchor: BasePart?, center: Vector3, radius: number }
		assert(not sphere.anchor, "Relocate: this sphere follows an anchor part; move the part instead")
		sphere.center = cframe.Position
		return
	end
	local box = self._boxes[1]
	assert(box and not box.part, "Relocate: only region zones (fromRegion) can be relocated")
	box.cframe = cframe
end

--------------------------------------------------------------------------------
-- promises
--------------------------------------------------------------------------------

function Zone.OnPlayerEnteredAsync(self: ZoneInstance, player: Player?)
	return Promise.new(function(resolve)
		if player and self._players[player] then
			resolve(player)
			return
		end
		local connection
		connection = self.PlayerEntered:Connect(function(entered)
			if player == nil or entered == player then
				connection:Disconnect()
				resolve(entered)
			end
		end)
	end)
end

function Zone.WaitForEmpty(self: ZoneInstance)
	return Promise.new(function(resolve)
		if self:IsEmpty() then
			resolve()
			return
		end
		local connection
		connection = self.PlayerExited:Connect(function()
			if self:IsEmpty() then
				connection:Disconnect()
				resolve()
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- debug visualization (opt-in)
--------------------------------------------------------------------------------

function Zone.ShowDebug(self: ZoneInstance, color: Color3?)
	if self._debug then
		return
	end
	local adornments: { Instance } = {}
	self._debug = adornments
	local fill = color or Color3.fromRGB(0, 170, 255)

	if self._shape == "Sphere" then
		local sphere = self._sphere :: { center: Vector3, radius: number, anchor: BasePart? }
		local anchor = sphere.anchor
		if not anchor then
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = Vector3.one
			part.CFrame = CFrame.new(sphere.center)
			part.Parent = workspace
			anchor = part
			table.insert(adornments, part)
		end
		local adorn = Instance.new("SphereHandleAdornment")
		adorn.Adornee = anchor
		adorn.Radius = sphere.radius
		adorn.AlwaysOnTop = true
		adorn.ZIndex = 0
		adorn.Transparency = 0.7
		adorn.Color3 = fill
		adorn.Parent = anchor
		table.insert(adornments, adorn)
		return
	end

	for _, box in self._boxes do
		local adornee = box.part
		if not adornee then
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = self:_boxSize(box)
			part.CFrame = self:_boxCFrame(box)
			part.Parent = workspace
			adornee = part
			table.insert(adornments, part)
		end
		local adorn = Instance.new("BoxHandleAdornment")
		adorn.Adornee = adornee
		adorn.Size = self:_boxSize(box)
		adorn.AlwaysOnTop = true
		adorn.ZIndex = 0
		adorn.Transparency = 0.7
		adorn.Color3 = fill
		adorn.Parent = adornee
		table.insert(adornments, adorn)
	end
end

function Zone.HideDebug(self: ZoneInstance)
	if not self._debug then
		return
	end
	for _, instance in self._debug do
		instance:Destroy()
	end
	self._debug = nil
end

--------------------------------------------------------------------------------
-- statics
--------------------------------------------------------------------------------

function Zone.GetPlayersNotInAnyZone(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if not playerZones[player] then
			table.insert(out, player)
		end
	end
	return out
end

function Zone.GetPlayerZones(player: Player): { ZoneInstance }
	local out = {}
	local set = playerZones[player]
	if set then
		for zone in set do
			table.insert(out, zone)
		end
	end
	table.sort(out, function(a, b)
		return a.Priority > b.Priority
	end)
	return out
end

function Zone.GetTopZone(player: Player): ZoneInstance?
	local top: any = nil
	local set = playerZones[player]
	if set then
		for zone in set do
			if not top or zone.Priority > top.Priority then
				top = zone
			end
		end
	end
	return top
end

function Zone.GetZonesAtPoint(point: Vector3): { ZoneInstance }
	local out = {}
	for zone in runningZones do
		if zone:_containsPoint(point) then
			table.insert(out, zone)
		end
	end
	table.sort(out, function(a, b)
		return a.Priority > b.Priority
	end)
	return out
end

--------------------------------------------------------------------------------
-- cleanup on leave
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	local set = playerZones[player]
	if set then
		for zone in set do
			zone._players[player] = nil
			zone._nearby[player] = nil
			zone.PlayerExited:Fire(player)
		end
		playerZones[player] = nil
	end
end)

return Zone
