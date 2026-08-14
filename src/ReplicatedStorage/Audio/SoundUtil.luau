--!strict

local SoundService = game:GetService("SoundService")

local SoundUtil = {}

-- volume scale multipliers per group
local _volumeScales: { [string]: number } = {
	Master = 1,
	SFX = 1,
	Voice = 1,
	UI = 1,
	Music = 1,
	Environment = 1,
	Ambient = 1,
}

-- resolves a single value, {min, max} range, or array of options
local function resolve(value: any, default: any): any
	if value == nil then
		return default
	end
	if type(value) == "table" then
		if value[1] ~= nil and value[2] ~= nil and #value == 2 and type(value[1]) == "number" then
			-- {min, max} range
			return value[1] + math.random() * (value[2] - value[1])
		else
			-- array of options
			return value[math.random(1, #value)]
		end
	end
	return value
end

-- finds a SoundGroup in SoundService by name
local function getSoundGroup(name: string): SoundGroup?
	return SoundService:FindFirstChild(name) :: SoundGroup?
end

-- builds a Sound instance from a sound data table, optionally overriding properties
local function buildSound(soundData: any, properties: { [string]: any }?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundData.SoundId or ""
	sound.Volume = resolve(soundData.Volume, 1) * (_volumeScales["Master"] or 1)
	sound.PlaybackSpeed = resolve(soundData.PlaybackSpeed, 1)
	sound.Looped = soundData.Looped or false
	if soundData.RollOffMaxDistance then
		sound.RollOffMaxDistance = soundData.RollOffMaxDistance
	end
	if soundData.SoundGroup then
		local group = getSoundGroup(soundData.SoundGroup)
		if group then
			sound.SoundGroup = group
		end
		local scale = _volumeScales[soundData.SoundGroup]
		if scale then
			sound.Volume *= scale
		end
	end
	if soundData.Effects then
		for effectClass, effectProps in soundData.Effects do
			local effect = Instance.new(effectClass) :: any
			for prop, val in effectProps do
				effect[prop] = val
			end
			effect.Parent = sound
		end
	end
	if properties then
		for prop, val in properties do
			(sound :: any)[prop] = val
		end
	end
	sound.Volume = math.clamp(sound.Volume, 0, 10)
	return sound
end

-- Destroys `instances` when the sound finishes. Ended alone is not enough: it never
-- fires for looped sounds, failed asset loads, or sounds stopped early — so also
-- watch Stopped and fall back to a timer once the length is known.
local function cleanupWhenDone(sound: Sound, instances: { Instance })
	local destroyed = false
	local function destroyAll()
		if destroyed then
			return
		end
		destroyed = true
		for _, instance in instances do
			instance:Destroy()
		end
	end

	if sound.Looped then
		-- Caller owns the lifetime of looped sounds; clean up only if it gets stopped.
		sound.Stopped:Connect(destroyAll)
		return
	end

	sound.Ended:Connect(destroyAll)
	sound.Stopped:Connect(destroyAll)
	task.spawn(function()
		local deadline = os.clock() + 10
		while not sound.IsLoaded and os.clock() < deadline do
			task.wait(0.1)
		end
		if destroyed then
			return
		end
		if not sound.IsLoaded then
			destroyAll() -- asset never loaded; Ended will not fire
			return
		end
		local length = sound.TimeLength
		if length > 0 then
			task.delay(length / math.max(sound.PlaybackSpeed, 0.05) + 1, destroyAll)
		end
	end)
end

-- parents the sound, plays it, and destroys it when it finishes
local function playAndCleanup(sound: Sound, parent: Instance)
	sound.Parent = parent
	sound:Play()
	cleanupWhenDone(sound, { sound })
end

-- finds sound data in SoundLibrary, loading it lazily
local function findSound(soundName: string, category: string?): (any?, string?)
	local SoundLibrary = require(script.Parent:WaitForChild("SoundLibrary"))
	return SoundLibrary.Find(soundName, category)
end

function SoundUtil.Play(soundName: string, category: string?, properties: { [string]: any }?)
	local data = findSound(soundName, category)
	if not data then
		warn("SoundUtil.Play: sound not found:", soundName)
		return
	end
	local sid = data.SoundId or ""
	if sid == "rbxassetid://0" or sid == "" then
		return
	end
	local sound = buildSound(data, properties)
	playAndCleanup(sound, SoundService)
end

function SoundUtil.PlayAt(soundName: string, position: Vector3, category: string?, properties: { [string]: any }?)
	local data = findSound(soundName, category)
	if not data then
		warn("SoundUtil.PlayAt: sound not found:", soundName)
		return
	end
	local sid = data.SoundId or ""
	if sid == "rbxassetid://0" or sid == "" then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Position = position
	part.Parent = workspace
	local sound = buildSound(data, properties)
	sound.Parent = part
	sound:Play()
	cleanupWhenDone(sound, { part })
end

function SoundUtil.PlayOn(soundName: string, instance: Instance, category: string?, properties: { [string]: any }?)
	local data = findSound(soundName, category)
	if not data then
		warn("SoundUtil.PlayOn: sound not found:", soundName)
		return
	end
	local sid = data.SoundId or ""
	if sid == "rbxassetid://0" or sid == "" then
		return
	end
	local sound = buildSound(data, properties)
	playAndCleanup(sound, instance)
end

-- returns a built Sound instance without playing it
function SoundUtil.Get(soundName: string, category: string?, properties: { [string]: any }?): Sound?
	local data = findSound(soundName, category)
	if not data then
		warn("SoundUtil.Get: sound not found:", soundName)
		return nil
	end
	return buildSound(data, properties)
end

function SoundUtil.SetVolumeScale(group: string, scale: number)
	_volumeScales[group] = scale
end

function SoundUtil.GetVolumeScales(): { [string]: number }
	return _volumeScales
end

return SoundUtil
