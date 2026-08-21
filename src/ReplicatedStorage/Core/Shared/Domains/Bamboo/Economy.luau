--!strict
-- The raw-bamboo sell rate.
--
-- Combo tuning used to live here; it now has its own module (Combo.luau) since
-- it grew rewards and milestones.

local Economy = {}

Economy.MoneyPerBamboo = 1

--[[
	Money a bag of raw bamboo is worth.
	@param bamboo number Bamboo being sold.
	@return number Payout in money.
]]
function Economy.SellValue(bamboo: number): number
	return bamboo * Economy.MoneyPerBamboo
end

return Economy
