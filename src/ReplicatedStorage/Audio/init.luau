--!strict
-- Audio facade; delegates all playback to SoundUtil

local Audio = {}

local SoundUtil = require(script:WaitForChild("SoundUtil"))
local SoundLibrary = require(script:WaitForChild("SoundLibrary"))

Audio.Util = SoundUtil
Audio.Library = SoundLibrary

function Audio:Play(soundName: string, category: string?, properties: { [string]: any }?)
	SoundUtil.Play(soundName, category, properties)
end

function Audio:PlayAt(soundName: string, position: Vector3, category: string?, properties: { [string]: any }?)
	SoundUtil.PlayAt(soundName, position, category, properties)
end

function Audio:PlayOn(soundName: string, instance: Instance, category: string?, properties: { [string]: any }?)
	SoundUtil.PlayOn(soundName, instance, category, properties)
end

function Audio:Get(soundName: string, category: string?, properties: { [string]: any }?): Sound?
	return SoundUtil.Get(soundName, category, properties)
end

function Audio:SetVolumeScale(group: string, scale: number)
	SoundUtil.SetVolumeScale(group, scale)
end

function Audio:SetMasterVolume(scale: number)
	SoundUtil.SetVolumeScale("Master", scale)
end

return Audio
