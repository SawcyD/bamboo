--!strict
-- Ordered list of data migrations; append only, never edit or remove existing entries.
-- Each entry runs once per profile (tracked by id in data._migrations).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")

type MigrationEntry = {
	id: string,
	desc: string,
	run: (data: any) -> any,
}

local migrations: { MigrationEntry } = {
	{
		id = "v2_bamboo_phase1",
		desc = "Add Phase 1 farm fields (money, bag, upgrade levels, lifetime stats)",
		run = function(data: any): any
			local defaults = {
				Money = 0,
				Bag = 0,
				SwingSpeedLevel = 0,
				MultiHitLevel = 0,
				YieldLevel = 0,
				LifetimeBambooCut = 0,
				LifetimeBambooCollected = 0,
			}
			for key, value in defaults do
				if type(data[key]) ~= "number" then
					data[key] = value
				end
			end
			return data
		end,
	},

	{
		id = "v3_field_upgrades",
		desc = "Add Storage, Growth Speed, and Field Density upgrade levels",
		run = function(data: any): any
			for _, key in { "StorageLevel", "GrowthSpeedLevel", "DensityLevel" } do
				if type(data[key]) ~= "number" then
					data[key] = 0
				end
			end
			return data
		end,
	},

	{
		id = "v4_sickles_and_crates",
		desc = "Give every profile the starter sickle and an empty crate history",
		run = function(data: any): any
			if type(data.OwnedSickles) ~= "table" then
				data.OwnedSickles = {}
			end
			-- Everyone owns the starter sickle; it is the fallback the swing
			-- resolver falls back to, so it must always be in the inventory.
			if type(data.OwnedSickles.starter_sickle) ~= "number" then
				data.OwnedSickles.starter_sickle = 1
			end
			if type(data.EquippedSickle) ~= "string" then
				data.EquippedSickle = "starter_sickle"
			end
			if type(data.CratesOpened) ~= "number" then
				data.CratesOpened = 0
			end
			return data
		end,
	},

	{
		id = "v5_luck",
		desc = "Add luck and timed luck-boost fields",
		run = function(data: any): any
			for _, key in { "Luck", "LuckBoost", "LuckBoostExpiresAt" } do
				if type(data[key]) ~= "number" then
					data[key] = 0
				end
			end
			return data
		end,
	},

	{
		id = "v6_highest_combo",
		desc = "Track the best harvesting combo a player has reached",
		run = function(data: any): any
			if type(data.HighestCombo) ~= "number" then
				data.HighestCombo = 0
			end
			return data
		end,
	},

	{
		id = "v7_processing",
		desc = "Add the Raw Bamboo -> Straw processor's input and output buffers",
		run = function(data: any): any
			for _, key in { "ProcessorInput", "StrawStock" } do
				if type(data[key]) ~= "number" then
					data[key] = 0
				end
			end
			return data
		end,
	},

	{
		id = "v8_stockpile_processing_flow",
		desc = "Replace Bag/StorageLevel/StrawStock with the stockpile -> carry -> processor -> earnings loop",
		run = function(data: any): any
			-- Raw bamboo that was sitting in the bag becomes stockpile.
			local bag = data.Bag
			if type(data.BambooStock) ~= "number" then
				data.BambooStock = 0
			end
			if type(bag) == "number" then
				data.BambooStock += bag
			end
			data.Bag = nil

			if type(data.CarriedBamboo) ~= "number" then
				data.CarriedBamboo = 0
			end

			-- Storage level becomes Carry level: same progression, new purpose.
			if type(data.CarryLevel) ~= "number" then
				local storageLevel = data.StorageLevel
				data.CarryLevel = if type(storageLevel) == "number" then storageLevel else 0
			end
			data.StorageLevel = nil

			if type(data.ProcessorInput) ~= "number" then
				data.ProcessorInput = 0
			end

			-- Any Straw already produced is sold into pending earnings rather than
			-- lost, using the same sell-value formula the processor itself uses.
			if type(data.PendingEarnings) ~= "number" then
				data.PendingEarnings = 0
			end
			local straw = data.StrawStock
			if type(straw) == "number" and straw > 0 then
				data.PendingEarnings += Bamboo.Processing.SellValue(straw)
			end
			data.StrawStock = nil

			return data
		end,
	},

	{
		id = "v9_unlimited_carry",
		desc = "Remove CarryLevel: carrying bamboo has no capacity limit, so the Carry upgrade no longer exists",
		run = function(data: any): any
			data.CarryLevel = nil
			return data
		end,
	},

	{
		id = "v10_processing_speed",
		desc = "Add the Processing Speed upgrade level, replacing the removed Carry upgrade's board slot",
		run = function(data: any): any
			if type(data.ProcessingSpeedLevel) ~= "number" then
				data.ProcessingSpeedLevel = 0
			end
			return data
		end,
	},

	-- Example:
	-- {
	-- 	id = "v2_add_settings",
	-- 	desc = "Add Settings table with default audio volumes",
	-- 	run = function(data: any): any
	-- 		if type(data.Settings) ~= "table" then
	-- 			data.Settings = {}
	-- 		end
	-- 		return data
	-- 	end,
	-- },
}

return migrations
