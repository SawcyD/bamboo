--!strict
-- Ordered list of data migrations; append only, never edit or remove existing entries.
-- Each entry runs once per profile (tracked by id in data._migrations).

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
