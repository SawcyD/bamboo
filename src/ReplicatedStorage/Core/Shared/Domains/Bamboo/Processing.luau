--!strict
-- Raw Bamboo → Straw: the first processing recipe.
--
-- Deliberately one machine, one recipe, one plot each. The player carries raw
-- bamboo from the stockpile and deposits it into the processor's input buffer;
-- the processor consumes it in whole batches over time and sells the Straw it
-- produces automatically, straight into PendingEarnings — Straw is never held
-- as inventory waiting on a manual sale. StrawSellValue is worth more per
-- raw-bamboo-equivalent than selling raw bamboo directly, which is the entire
-- incentive to run the loop instead of stopping at the stockpile.
--
-- Every number here is a starting balance value, not a measured one — see the
-- "needs tuning" call-out in the delivery report.

local Processing = {}

-- Raw bamboo consumed and Straw produced per completed batch. A batch is
-- all-or-nothing: the processor never consumes a partial InputPerBatch, so the
-- input buffer always holds whole, accounted-for units.
Processing.InputPerBatch = 10
Processing.OutputPerBatch = 5

-- Seconds one batch takes at Processing Speed level 0. InputPerBatch/BatchSeconds
-- = 10/10 = 1 bamboo/sec consumed — the starting rate the Processing Speed
-- upgrade (Value.ProcessorBatchSeconds) scales up from. Deliberately slower
-- than level-0 harvesting (~2.5 bamboo/sec) so a backlog builds and cutting is
-- never blocked waiting on the machine.
Processing.BatchSeconds = 10

-- Raw bamboo the input buffer can hold. Effectively uncapped for this pass —
-- the intended bottleneck is processing speed and carry capacity, not storage
-- space — kept as a real number only so InputRoom stays a meaningful call.
Processing.MaxInputBuffer = 1_000_000

-- Money one Straw is worth. At OutputPerBatch/InputPerBatch = 1:2, one Straw
-- represents 2 raw bamboo; StrawSellValue 3 is 1.5 money per raw-bamboo
-- equivalent versus Economy.MoneyPerBamboo's 1 — a 50% premium for processing,
-- against the cost of carrying bamboo there and waiting on the batch clock.
Processing.StrawSellValue = 3

--[[
	Money a stock of Straw is worth.
	@param straw number Straw being sold.
	@return number Payout in money.
]]
function Processing.SellValue(straw: number): number
	return straw * Processing.StrawSellValue
end

--[[
	Whether the input buffer holds enough for one more batch.
	@param input number Raw bamboo currently in the input buffer.
	@return boolean True when a batch can start.
]]
function Processing.HasBatchInput(input: number): boolean
	return input >= Processing.InputPerBatch
end

--[[
	How much more raw bamboo the input buffer can accept right now.
	@param input number Raw bamboo currently in the input buffer.
	@return number Room remaining, never negative.
]]
function Processing.InputRoom(input: number): number
	return math.max(Processing.MaxInputBuffer - input, 0)
end

return Processing
