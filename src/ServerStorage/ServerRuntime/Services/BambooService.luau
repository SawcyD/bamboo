--!strict
-- Authoritative bamboo field: stalk state, growth, and swing resolution.
--
-- The client only ever says "I swung, here, facing this way". This service owns
-- which stalks exist, how healthy they are, what they are worth, and who may hit
-- them, so a modified client can at best swing on cooldown like everyone else.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Sickles = Core:GetDomain("Sickles")
local BambooModel = Core:GetShared("BambooModel")
local Relay = Core:GetShared("Network")

local BambooService = {}
local Framework

-- How far the reported swing origin may sit from the player's actual root
-- before we treat the packet as bogus.
local MAX_ORIGIN_DRIFT = 14
local GROWTH_TICK_SECONDS = 0.5
local COMBO_TICK_SECONDS = 0.25

type Stalk = {
	Id: number,
	Slot: CFrame,
	Rarity: string,
	Health: number,
	Stage: number,
	Model: Model?,
	-- os.clock() the stalk was cut; nil while it is standing.
	CutAt: number?,
	-- Rarity luck captured from the cutter's combo, applied when this stalk
	-- reseeds. A hot streak leaves behind a richer field.
	ReplantLuck: number?,
}

type PlotState = {
	Plot: any,
	Folder: Folder,
	Stalks: { Stalk },
	Rng: Random,
}

type SwingState = {
	LastSwing: number,
	ComboCount: number,
	ComboExpires: number,
	-- Walk speed the character had before the combo touched it, so the bonus
	-- can be removed without guessing at a baseline.
	BaseWalkSpeed: number?,
	-- Fractional combo value bonus carried between stalks. Without it, a +10%
	-- bonus on a 2-bamboo stalk floors straight back to 2 and the reward tier
	-- is invisible for exactly the bamboo a new player cuts most.
	ValueRemainder: number,
}

local _plotStates: { [string]: PlotState } = {}
local _swingState: { [Player]: SwingState } = {}
-- Server-owned stream for ability procs, so a client can never predict a Reaper.
local _rng = Random.new(os.clock() * 1e6 % 2 ^ 31)

-- ── stalk construction ───────────────────────────────────────────────────────

local function _destroyStalkModel(stalk: Stalk)
	if stalk.Model then
		stalk.Model:Destroy()
		stalk.Model = nil
	end
end

-- Builds (or rebuilds) the visual for a stalk at its current stage.
local function _spawnStalkModel(state: PlotState, stalk: Stalk)
	_destroyStalkModel(stalk)

	local visual = Bamboo.Rarity.RollVisual(stalk.Rarity, state.Rng)
	local model = BambooModel.Build(visual, stalk.Slot, state.Rng)
	model.Name = "Stalk" .. stalk.Id
	model:SetAttribute("StalkId", stalk.Id)
	model:SetAttribute("Stage", stalk.Stage)
	model:SetAttribute("Rarity", stalk.Rarity)
	BambooModel.ApplyStage(model, stalk.Stage, stalk.Slot)
	model.Parent = state.Folder

	stalk.Model = model
end

local function _setStage(stalk: Stalk, stage: number)
	if stalk.Stage == stage then
		return
	end
	stalk.Stage = stage
	if stalk.Model then
		BambooModel.ApplyStage(stalk.Model, stage, stalk.Slot)
		stalk.Model:SetAttribute("Stage", stage)
	end
end

-- Rerolls a cut stalk as a fresh shoot and starts it growing again.
local function _replant(state: PlotState, stalk: Stalk)
	stalk.Rarity = Bamboo.Rarity.Roll(state.Rng, stalk.ReplantLuck)
	stalk.ReplantLuck = nil
	stalk.Health = Bamboo.Rarity.Get(stalk.Rarity).health
	stalk.Stage = Bamboo.Field.Stage.Shoot
	_spawnStalkModel(state, stalk)
end

-- ── growth ───────────────────────────────────────────────────────────────────

-- The owner's Growth Speed level, read once per plot per tick rather than once
-- per stalk.
local function _growthLevelFor(plot: any): number
	local owner = plot.Owner
	if not owner then
		return 0
	end
	local DataService = Framework:GetService("DataService")
	return DataService.Get(owner, "GrowthSpeedLevel") or 0
end

local function _tickGrowth()
	local now = os.clock()

	for _, state in _plotStates do
		local growthLevel = _growthLevelFor(state.Plot)
		local regrowSeconds = Bamboo.Value.RegrowSeconds(growthLevel)

		for _, stalk in state.Stalks do
			local cutAt = stalk.CutAt
			if cutAt == nil then
				continue
			end

			-- A cut stalk reseeds on the next tick so the ground is never bare for
			-- long; the stage thresholds then walk it back up to Mature.
			if stalk.Model == nil then
				_replant(state, stalk)
			end

			local elapsed = now - cutAt
			_setStage(stalk, Bamboo.Value.StageAt(elapsed, growthLevel))
			if elapsed >= regrowSeconds then
				stalk.CutAt = nil
			end
		end
	end
end

-- ── combo ────────────────────────────────────────────────────────────────────
--
-- The server owns the combo outright. It already knows which stalks actually
-- broke, so the client is never asked — it is only told, and only when the
-- number moves.

local function _swingStateFor(player: Player): SwingState
	local state = _swingState[player]
	if not state then
		state = { LastSwing = 0, ComboCount = 0, ComboExpires = 0, ValueRemainder = 0 }
		_swingState[player] = state
	end
	return state
end

local function _publishCombo(player: Player, swing: SwingState, milestone: number)
	Relay.Bamboo.ComboState.sendTo({
		combo = swing.ComboCount,
		windowSeconds = if swing.ComboCount > 0 then Bamboo.Combo.TimeoutSeconds else 0,
		milestone = milestone,
	}, player)
end

-- Movement is the one combo reward that lives on the character rather than in a
-- calculation, so it is applied and removed explicitly.
local function _applyMoveSpeed(player: Player, swing: SwingState)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Captured on first use rather than assumed, so another system raising walk
	-- speed isn't quietly overwritten.
	if swing.BaseWalkSpeed == nil then
		swing.BaseWalkSpeed = humanoid.WalkSpeed
	end

	humanoid.WalkSpeed = (swing.BaseWalkSpeed :: number) + Bamboo.Combo.Rewards(swing.ComboCount).moveSpeed
end

local function _endCombo(player: Player, swing: SwingState)
	if swing.ComboCount == 0 then
		return
	end
	swing.ComboCount = 0
	swing.ComboExpires = 0
	swing.ValueRemainder = 0
	_applyMoveSpeed(player, swing)
	_publishCombo(player, swing, 0)
end

-- Drops combos whose grace period ran out. Cheap enough to run on a fast tick:
-- one comparison per player.
local function _tickCombos()
	local now = os.clock()
	for player, swing in _swingState do
		if swing.ComboCount > 0 and now >= swing.ComboExpires then
			_endCombo(player, swing)
		end
	end
end

-- ── swing resolution ─────────────────────────────────────────────────────────

-- Mature stalks inside the swing cone, nearest first, capped to multiHit.
local function _gatherTargets(
	state: PlotState,
	origin: Vector3,
	look: Vector3,
	multiHit: number,
	range: number
): { Stalk }
	local sickle = Bamboo.Tool
	local rangeSq = range * range
	-- A full-circle rotor has no facing to test against.
	local sweepsFullCircle = sickle.SwingArcDegrees >= 360
	local minDot = math.cos(math.rad(sickle.SwingArcDegrees * 0.5))
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if not sweepsFullCircle and flatLook.Magnitude < 1e-3 then
		return {}
	end
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.new(0, 0, -1)

	local candidates: { { stalk: Stalk, distSq: number } } = {}
	for _, stalk in state.Stalks do
		if stalk.Stage ~= Bamboo.Field.Stage.Mature or stalk.Model == nil then
			continue
		end

		local toStalk = stalk.Slot.Position - origin
		local flat = Vector3.new(toStalk.X, 0, toStalk.Z)
		local distSq = flat.X * flat.X + flat.Z * flat.Z
		if distSq > rangeSq or distSq < 1e-4 then
			continue
		end
		if not sweepsFullCircle and flat.Unit:Dot(flatLook) < minDot then
			continue
		end

		table.insert(candidates, { stalk = stalk, distSq = distSq })
	end

	table.sort(candidates, function(a, b)
		return a.distSq < b.distSq
	end)

	local targets: { Stalk } = {}
	for i = 1, math.min(multiHit, #candidates) do
		table.insert(targets, candidates[i].stalk)
	end
	return targets
end

-- Chain Cut: the nearest mature stalk to one that just broke, skipping any
-- already in this swing so a chain can't double-hit the same stalk.
local function _findChainTarget(state: PlotState, from: Vector3, alreadyHit: { [number]: boolean }): Stalk?
	local radiusSq = Sickles.Abilities.ChainRadius ^ 2
	local best: Stalk? = nil
	local bestDistSq = radiusSq

	for _, stalk in state.Stalks do
		if alreadyHit[stalk.Id] or stalk.Stage ~= Bamboo.Field.Stage.Mature or stalk.Model == nil then
			continue
		end
		local distSq = (stalk.Slot.Position - from).Magnitude ^ 2
		if distSq < bestDistSq then
			bestDistSq = distSq
			best = stalk
		end
	end

	return best
end

local function _onSwing(payload: any, player: Player)
	local PlotService = Framework:GetService("PlotService")
	local DataService = Framework:GetService("DataService")

	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	local state = _plotStates[plot.Id]
	if not state then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	local origin = payload.origin :: Vector3
	if (origin - root.Position).Magnitude > MAX_ORIGIN_DRIFT then
		return
	end

	local SickleService = Framework:GetService("SickleService")
	local yieldLevel = DataService.Get(player, "YieldLevel") or 0
	-- Damage, range, multi-hit, and swing time all come from the equipped
	-- sickle combined with upgrade levels — resolved server-side, never sent.
	local stats = SickleService.GetStats(player)

	local swing = _swingStateFor(player)
	local now = os.clock()

	-- Combo bonuses are read from the server's own combo count. The client is
	-- never asked what its combo is; it is only ever told.
	if swing.ComboCount > 0 and now >= swing.ComboExpires then
		_endCombo(player, swing)
	end
	local comboBefore = swing.ComboCount
	local rewards = Bamboo.Combo.Rewards(comboBefore)

	local cooldown = stats.swingTime * (1 - rewards.swingSpeed) - Bamboo.Tool.SwingToleranceSeconds
	if now - swing.LastSwing < cooldown then
		return
	end
	swing.LastSwing = now

	local targets = _gatherTargets(state, origin, payload.look, stats.multiHit, stats.range)
	if #targets == 0 then
		return
	end

	local DropService = Framework:GetService("DropService")
	local bag = DataService.Get(player, "Bag") or 0
	local capacity = Bamboo.Value.BagCapacity(DataService.Get(player, "StorageLevel") or 0)

	local hits: { any } = {}
	local breaks = 0
	local collected = 0
	local dropped = 0
	local cut = 0
	local chained = 0

	-- Stalks this swing has already touched, so Chain never revisits one.
	local touched: { [number]: boolean } = {}
	for _, stalk in targets do
		touched[stalk.Id] = true
	end

	-- Resolves one stalk being struck. Shared by the swing itself and by Chain,
	-- so a chained break pays out and drops exactly like a normal one.
	local function _strike(stalk: Stalk, damage: number, viaChain: boolean)
		stalk.Health -= damage
		local broke = stalk.Health <= 0

		if broke then
			breaks += 1
			cut += 1
			if viaChain then
				chained += 1
			end

			local reward = Bamboo.Value.StalkReward(stalk.Rarity, yieldLevel)
			-- Bountiful: a broken stalk sometimes pays out double.
			if stats.ability == "Bountiful" and _rng:NextNumber() < stats.abilityPotency then
				reward *= Sickles.Abilities.BountifulMultiplier
			end
			-- Combo value bonus, carried as a fraction so small percentages stay
			-- real on 2-bamboo stalks. The maths lives in the domain.
			reward, swing.ValueRemainder = Bamboo.Combo.ApplyValueBonus(reward, rewards.value, swing.ValueRemainder)

			local room = math.max(capacity - bag - collected, 0)
			local taken = math.min(reward, room)
			collected += taken

			-- Anything the bag couldn't hold falls where the stalk stood, so a
			-- full bag costs you a trip rather than the bamboo itself.
			local overflow = reward - taken
			if overflow > 0 then
				DropService.Spawn(plot, stalk.Slot.Position, overflow, stalk.Rarity)
				dropped += overflow
			end

			stalk.CutAt = now
			-- Captured now rather than read at replant time, so the luck that
			-- reseeds this stalk is the luck it was cut at.
			stalk.ReplantLuck = rewards.rarityLuck
			_destroyStalkModel(stalk)
			stalk.Stage = Bamboo.Field.Stage.Shoot
		end

		table.insert(hits, {
			id = stalk.Id,
			position = stalk.Slot.Position,
			rarity = stalk.Rarity,
			broke = broke,
			health = math.max(stalk.Health, 0),
			chained = viaChain,
		})

		return broke
	end

	for _, stalk in targets do
		-- Reaper: a hit sometimes fells the stalk outright, whatever its health.
		local damage = stats.damage
		if stats.ability == "Reaper" and _rng:NextNumber() < stats.abilityPotency then
			damage = stalk.Health
		end

		local broke = _strike(stalk, damage, false)

		-- Chain Cut: a break can carry into the nearest untouched neighbour.
		if broke and stats.ability == "Chain" and _rng:NextNumber() < stats.abilityPotency then
			local neighbour = _findChainTarget(state, stalk.Slot.Position, touched)
			if neighbour then
				touched[neighbour.Id] = true
				-- A chain always fells what it reaches; a partial chain would be
				-- invisible to the player and read as the ability not firing.
				_strike(neighbour, neighbour.Health, true)
			end
		end
	end

	-- Only felled stalks build the combo: a swing that merely damaged something
	-- leaves it untouched, and the grace period is not refreshed either.
	local milestone = 0
	if breaks > 0 then
		swing.ComboCount = comboBefore + breaks
		swing.ComboExpires = now + Bamboo.Combo.TimeoutSeconds
		milestone = Bamboo.Combo.MilestoneCrossed(comboBefore, swing.ComboCount) or 0

		_applyMoveSpeed(player, swing)
		_publishCombo(player, swing, milestone)

		local best = DataService.Get(player, "HighestCombo") or 0
		if swing.ComboCount > best then
			DataService.Set(player, "HighestCombo", swing.ComboCount)
		end
	end

	if collected > 0 then
		DataService.Increment(player, "Bag", collected)
		DataService.Increment(player, "LifetimeBambooCollected", collected)
	end
	if cut > 0 then
		DataService.Increment(player, "LifetimeBambooCut", cut)
	end

	Relay.Bamboo.SwingResult.sendTo({
		hits = hits,
		breaks = breaks,
		combo = swing.ComboCount,
		collected = collected,
		dropped = dropped,
		chained = chained,
	}, player)
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function BambooService:Start(fw: any)
	Framework = fw

	Relay.Bamboo.Swing.listen(_onSwing)

	Players.PlayerRemoving:Connect(function(player: Player)
		_swingState[player] = nil
	end)

	local function onCharacter(player: Player)
		local swing = _swingState[player]
		if swing then
			swing.BaseWalkSpeed = nil
			_endCombo(player, swing)
		end
	end
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
	end)

	local growthAccumulator = 0
	local comboAccumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		growthAccumulator += dt
		if growthAccumulator >= GROWTH_TICK_SECONDS then
			growthAccumulator = 0
			_tickGrowth()
		end

		comboAccumulator += dt
		if comboAccumulator >= COMBO_TICK_SECONDS then
			comboAccumulator = 0
			_tickCombos()
		end
	end)
end

--[[
	Fills a plot's field with mature bamboo, ready to cut immediately.
	@param plot Plot The plot record from PlotService.
]]
function BambooService.PopulatePlot(plot: any)
	BambooService.ClearPlot(plot)

	local folder = Instance.new("Folder")
	folder.Name = "Bamboo"
	folder.Parent = plot.Model

	local state: PlotState = {
		Plot = plot,
		Folder = folder,
		Stalks = {},
		Rng = Random.new(os.clock() * 1e6 % 2 ^ 31),
	}

	_plotStates[plot.Id] = state
	BambooService.SyncFieldSize(plot)
end

--[[
	Grows or shrinks a plot's field to match its owner's Density level.
	New stalks are planted Mature so buying the upgrade pays off immediately.
	@param plot Plot The plot record from PlotService.
]]
function BambooService.SyncFieldSize(plot: any)
	local state = _plotStates[plot.Id]
	if not state then
		return
	end

	local owner = plot.Owner
	local densityLevel = 0
	if owner then
		local DataService = Framework:GetService("DataService")
		densityLevel = DataService.Get(owner, "DensityLevel") or 0
	end

	local target = math.min(Bamboo.Value.MaxStalks(densityLevel), #plot.Slots)

	for index = #state.Stalks + 1, target do
		local rarity = Bamboo.Rarity.Roll(state.Rng)
		local stalk: Stalk = {
			Id = index,
			Slot = plot.Slots[index],
			Rarity = rarity,
			Health = Bamboo.Rarity.Get(rarity).health,
			Stage = Bamboo.Field.Stage.Mature,
			Model = nil,
			CutAt = nil,
		}
		table.insert(state.Stalks, stalk)
		_spawnStalkModel(state, stalk)
	end

	-- Only reachable if Density is ever rebalanced downward; kept so the field
	-- can never end up with more stalks than the level allows.
	for index = #state.Stalks, target + 1, -1 do
		_destroyStalkModel(state.Stalks[index])
		table.remove(state.Stalks, index)
	end
end

--[[
	Tears down a plot's field and forgets its stalk state.
	@param plot Plot The plot record from PlotService.
]]
function BambooService.ClearPlot(plot: any)
	local DropService = Framework and Framework:GetService("DropService")
	if DropService then
		DropService.ClearPlot(plot)
	end

	local state = _plotStates[plot.Id]
	if state then
		state.Folder:Destroy()
		_plotStates[plot.Id] = nil
	end
	local stale = plot.Model:FindFirstChild("Bamboo")
	if stale then
		stale:Destroy()
	end
end

return BambooService
