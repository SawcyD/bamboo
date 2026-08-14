--!strict
-- Runs pending migrations against a profile's data table

local Migration = {}

function Migration.Run(data: any): any
	local migrations = require(script.Parent:WaitForChild("Migrations"))

	if not data._migrations then
		data._migrations = {}
	end

	local ran: { [string]: boolean } = {}
	for _, id in data._migrations do
		ran[id] = true
	end

	for _, entry in migrations do
		if ran[entry.id] then
			continue
		end
		local ok, err = pcall(function()
			data = entry.run(data)
		end)
		if ok then
			table.insert(data._migrations, entry.id)
		else
			warn("Migration failed for id=" .. entry.id .. ":", err)
		end
	end

	return data
end

return Migration
