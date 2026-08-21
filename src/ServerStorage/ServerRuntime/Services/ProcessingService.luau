--!strict
-- Raw Bamboo -> Straw: deposit-by-request, then automatic batch processing.
--
-- The player carries bamboo from the stockpile (StockpileService) to the
-- processor and presses [E] to deposit it — CarriedBamboo -> ProcessorInput,
-- all of it, in one request. The client only ever asks; the server decides
-- whether the request is even legal (owns the plot, close enough) and moves
-- the real number itself.
--
-- A second tick, mirroring BambooService's growth tick, converts whole batches
-- on a fixed clock independent of any player action. A completed batch sells
-- immediately: Straw is never held as inventory waiting on a manual sale, its
-- value goes straight into PendingEarnings, which only becomes spendable Money
-- at the Cash Collector.
--
-- ProcessorInput and PendingEarnings live on the player's own profile, not on
-- transient per-plot state, so they survive relog exactly like BambooStock and
-- Money. That also means processing only ever runs for a plot with an online
-- owner: PlotService releases a plot's Owner when its player leaves, so a
-- departed player's backlog simply stops advancing rather than needing an
-- explicit "is this player online" check here. That is the whole offline-
-- processing rule — there is no separate flag for it.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local Relay = Core:GetShared("Network")

local ProcessingService = {}
local Framework

local BATCH_TICK_SECONDS = 1
-- Extra radius around the processor pad, matching the rest of the plot's
-- proximity checks (stockpile, sell/cash pad) so players don't have to stand
-- dead centre.
local PROCESSOR_PAD_PADDING = 3

-- Seconds since the last completed batch, per plot. Deliberately not saved to
-- the profile: losing a partial countdown on relog costs nothing (no bamboo is
-- in flight mid-batch, only whole units in the input buffer), and re-deriving
-- it fresh is simpler than reconciling a stale timestamp against a rebuilt plot.
local _batchClocks: { [string]: number } = {}

-- ── deposit ──────────────────────────────────────────────────────────────────

local function _isAtProcessor(root: BasePart, processor: BasePart): boolean
	local offset = processor.CFrame:PointToObjectSpace(root.Position)
	local half = processor.Size * 0.5
	return math.abs(offset.X) <= half.X + PROCESSOR_PAD_PADDING
		and math.abs(offset.Z) <= half.Z + PROCESSOR_PAD_PADDING
		and math.abs(offset.Y) <= 8
end

--[[
	Moves everything a player is carrying into the processor's input buffer.
	Safe to call when nothing is carried (a no-op).
	@param player Player The depositor.
	@return number Bamboo actually moved (0 if there was nothing to move).
]]
function ProcessingService.Deposit(player: Player): number
	local DataService = Framework:GetService("DataService")

	local carried = DataService.Get(player, "CarriedBamboo") or 0
	if carried <= 0 then
		return 0
	end

	-- Two increments, same callback, no yield between them: the bamboo is never
	-- observably in both places or in neither.
	DataService.Increment(player, "CarriedBamboo", -carried)
	DataService.Increment(player, "ProcessorInput", carried)
	return carried
end

local function _onDepositRequest(_payload: any, player: Player)
	local PlotService = Framework:GetService("PlotService")

	local plot = PlotService.GetPlot(player)
	if not plot then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if not _isAtProcessor(root, plot.Processor) then
		return
	end

	ProcessingService.Deposit(player)
end

-- ── batching ─────────────────────────────────────────────────────────────────

local function _tickBatches(dt: number)
	local PlotService = Framework:GetService("PlotService")
	local DataService = Framework:GetService("DataService")

	for _, plot in PlotService.GetAllPlots() do
		local owner = plot.Owner
		if not owner then
			-- No online owner: nothing to advance, and nothing to leak either —
			-- the clock entry is dropped so a plot that changes hands starts fresh
			-- rather than inheriting a stranger's partial countdown.
			_batchClocks[plot.Id] = nil
			continue
		end

		local batchSeconds = Bamboo.Value.ProcessorBatchSeconds(DataService.Get(owner, "ProcessingSpeedLevel") or 0)
		local elapsed = (_batchClocks[plot.Id] or 0) + dt
		if elapsed < batchSeconds then
			_batchClocks[plot.Id] = elapsed
			continue
		end

		local input = DataService.Get(owner, "ProcessorInput") or 0

		if Bamboo.Processing.HasBatchInput(input) then
			DataService.Increment(owner, "ProcessorInput", -Bamboo.Processing.InputPerBatch)
			-- Sold the instant it's produced: Straw is never inventory, so there is
			-- no output buffer to fill or empty.
			local earnings = Bamboo.Processing.SellValue(Bamboo.Processing.OutputPerBatch)
			DataService.Increment(owner, "PendingEarnings", earnings)
			-- Batch completed; the clock restarts rather than carrying overflow
			-- time, so a machine that sat idle (no input) doesn't fire a burst of
			-- instant batches the moment input arrives.
			_batchClocks[plot.Id] = 0
		else
			-- Not enough input: try again next tick rather than losing the
			-- accumulated time. Nothing is consumed, so nothing is at risk.
			_batchClocks[plot.Id] = elapsed
		end
	end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function ProcessingService:Start(fw: any)
	Framework = fw

	Relay.Bamboo.DepositToProcessor.listen(_onDepositRequest)

	local batchAccumulator = 0

	RunService.Heartbeat:Connect(function(dt: number)
		batchAccumulator += dt
		if batchAccumulator >= BATCH_TICK_SECONDS then
			local step = batchAccumulator
			batchAccumulator = 0
			_tickBatches(step)
		end
	end)
end

return ProcessingService
