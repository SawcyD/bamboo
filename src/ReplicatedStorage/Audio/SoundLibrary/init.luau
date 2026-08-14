--!strict
-- Combines all sound category tables and provides Find/FindIn helpers

local SFX = require(script:WaitForChild("SFX"))
local UILib = require(script:WaitForChild("UI"))
local Music = require(script:WaitForChild("Music"))
local Environment = require(script:WaitForChild("Environment"))
local Voice = require(script:WaitForChild("Voice"))

local SoundLibrary = {
	SFX = SFX,
	UI = UILib,
	Music = Music,
	Environment = Environment,
	Voice = Voice,
}

local _all: { [string]: { data: any, categoryName: string } } = {}

-- build lookup map at require time
for categoryName, categoryTable in SoundLibrary do
	if type(categoryTable) == "table" then
		for soundName, data in categoryTable :: any do
			_all[soundName] = { data = data, categoryName = categoryName }
		end
	end
end

-- searches all categories; returns (data, categoryName)
function SoundLibrary.Find(soundName: string): (any?, string?)
	local entry = _all[soundName]
	if entry then
		return entry.data, entry.categoryName
	end
	return nil, nil
end

-- searches a specific category by name
function SoundLibrary.FindIn(soundName: string, categoryName: string): any?
	local category = (SoundLibrary :: any)[categoryName]
	if not category then
		warn("SoundLibrary.FindIn: unknown category:", categoryName)
		return nil
	end
	return category[soundName]
end

return SoundLibrary
