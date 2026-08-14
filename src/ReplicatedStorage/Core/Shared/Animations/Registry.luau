--!strict
-- Lazy animation-profile registry.
-- Profile modules are required only when their stable ID is requested. Roblox
-- caches each ModuleScript, so the profile itself is not reloaded per NPC.

local Profiles = require(script.Parent.Profiles)

export type AnimationDefinition = Profiles.AnimationDefinition
export type Profile = Profiles.Profile

local sources: { [string]: ModuleScript } = {
	shopkeeper = script.Parent.Catalog.NPC.Shopkeeper :: ModuleScript,
	bartender = script.Parent.Catalog.NPC.Bartender :: ModuleScript,
	gym_teacher = script.Parent.Catalog.NPC.GymTeacher :: ModuleScript,
}

local loaded: { [string]: Profile } = {}
local removed: { [string]: boolean } = {}

local Registry = {}

local function validateProfile(profile: any): Profile
	assert(type(profile) == "table" and type(profile.Animations) == "table", "Animations.Registry: invalid profile")
	for name, definition in profile.Animations do
		assert(type(name) == "string" and #name > 0, "Animations.Registry: animation name is required")
		if type(definition) == "string" then
			assert(definition ~= "", "Animations.Registry: animation id is required")
		else
			assert(
				type(definition) == "table" and type(definition.Id) == "string" and definition.Id ~= "",
				"Animations.Registry: invalid animation definition"
			)
		end
	end
	return profile :: Profile
end

function Registry.Get(name: string): Profile?
	if removed[name] then
		return nil
	end

	local cached = loaded[name]
	if cached then
		return cached
	end

	local source = sources[name]
	if not source then
		return nil
	end

	local profile = validateProfile(require(source))
	loaded[name] = profile
	return profile
end

function Registry.Require(name: string): Profile
	local profile = Registry.Get(name)
	assert(profile, "Animations.Registry: profile not found: " .. name)
	return profile
end

function Registry.Register(name: string, profile: Profile)
	assert(type(name) == "string" and #name > 0, "Animations.Registry: profile name is required")
	assert(
		(sources[name] == nil or removed[name]) and loaded[name] == nil,
		"Animations.Registry: duplicate profile " .. name
	)
	removed[name] = nil
	loaded[name] = validateProfile(profile)
end

function Registry.Replace(name: string, profile: Profile)
	assert(type(name) == "string" and #name > 0, "Animations.Registry: profile name is required")
	removed[name] = nil
	loaded[name] = validateProfile(profile)
end

function Registry.GetAnimation(profileName: string, animationName: string): AnimationDefinition | string?
	local profile = Registry.Get(profileName)
	return profile and profile.Animations[animationName]
end

function Registry.List(): { string }
	local result = {}
	for name in sources do
		if not removed[name] then
			table.insert(result, name)
		end
	end
	for name in loaded do
		if sources[name] == nil and not removed[name] then
			table.insert(result, name)
		end
	end
	table.sort(result)
	return result
end

function Registry.Remove(name: string)
	loaded[name] = nil
	removed[name] = true
end

function Registry.Clear()
	table.clear(loaded)
	for name in sources do
		removed[name] = true
	end
end

function Registry.Reset()
	table.clear(loaded)
	table.clear(removed)
end

return Registry
