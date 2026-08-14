--!strict
-- Ordered list of data migrations; append only, never edit or remove existing entries.
-- Each entry runs once per profile (tracked by id in data._migrations).

type MigrationEntry = {
	id: string,
	desc: string,
	run: (data: any) -> any,
}

local migrations: { MigrationEntry } = {
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
