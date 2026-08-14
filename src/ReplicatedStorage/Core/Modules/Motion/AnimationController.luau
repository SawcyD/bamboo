--!strict
-- AnimationTrack controller for player characters, NPCs, and custom rigs.

local Janitor = require(script.Parent.Parent:WaitForChild("Janitor"))
local Signal = require(script.Parent.Parent:WaitForChild("Signal"))

local AnimationController = {}
AnimationController.__index = AnimationController

local DEFAULT_FADE_TIME = 0.15
local DEFAULT_WALK_SPEED = 8
local DEFAULT_RUN_SPEED = 16

export type AnimationDefinition = {
	Id: string,
	Looped: boolean?,
	Priority: Enum.AnimationPriority?,
}

export type Profile = {
	Animations: { [string]: AnimationDefinition | string },
	Locomotion: {
		Idle: string?,
		Walk: string?,
		Run: string?,
		WalkSpeed: number?,
		RunSpeed: number?,
	}?,
}

export type PlayOptions = {
	FadeTime: number?,
	Weight: number?,
	Speed: number?,
	Layer: string?,
	Restart: boolean?,
}

export type ControllerType = {
	Started: any,
	Stopped: any,
	Changed: any,
	Play: (self: ControllerType, name: string, options: PlayOptions?) -> AnimationTrack?,
	Crossfade: (self: ControllerType, name: string, fadeTime: number?, layer: string?) -> AnimationTrack?,
	Stop: (self: ControllerType, name: string, fadeTime: number?) -> (),
	StopLayer: (self: ControllerType, layer: string, fadeTime: number?) -> (),
	StopAll: (self: ControllerType, fadeTime: number?) -> (),
	SetState: (self: ControllerType, name: string, fadeTime: number?, layer: string?) -> AnimationTrack?,
	UpdateLocomotion: (self: ControllerType, horizontalSpeed: number, fadeTime: number?) -> AnimationTrack?,
	AdjustSpeed: (self: ControllerType, name: string, speed: number) -> boolean,
	AdjustWeight: (self: ControllerType, name: string, weight: number, fadeTime: number?) -> boolean,
	Preload: (self: ControllerType, names: { string }?) -> (),
	GetTracks: (self: ControllerType) -> { string },
	GetLength: (self: ControllerType, name: string) -> number?,
	BindMarker: (
		self: ControllerType,
		name: string,
		markerName: string,
		callback: (...any) -> ()
	) -> RBXScriptConnection?,
	BindEnded: (self: ControllerType, name: string, callback: () -> ()) -> RBXScriptConnection?,
	TrackEnded: (self: ControllerType, name: string, callback: () -> ()) -> RBXScriptConnection?,
	GetTrack: (self: ControllerType, name: string) -> AnimationTrack?,
	IsPlaying: (self: ControllerType, name: string) -> boolean,
	SetProfile: (self: ControllerType, profile: Profile) -> (),
	GetProfile: (self: ControllerType) -> Profile,
	Destroy: (self: ControllerType) -> (),
}

type TrackRecord = {
	Animation: Animation,
	Track: AnimationTrack,
}

type ControllerImpl = ControllerType & {
	_actor: Model,
	_animator: Animator,
	_profile: Profile,
	_tracks: { [string]: TrackRecord },
	_layers: { [string]: string },
	_janitor: any,
	_destroyed: boolean,
}

local function _getDefinition(profile: Profile, name: string): AnimationDefinition?
	local definition = profile.Animations[name]
	if type(definition) == "string" then
		return { Id = definition }
	end
	return definition
end

local function _getAnimator(actor: Model): Animator
	local rigController = actor:FindFirstChildOfClass("Humanoid") or actor:FindFirstChildOfClass("AnimationController")
	if not rigController then
		local animationController = Instance.new("AnimationController")
		animationController.Name = "MotionController"
		animationController.Parent = actor
		rigController = animationController
	end

	local animator = rigController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = rigController
	end
	return animator
end

local function _stopRecord(record: TrackRecord, fadeTime: number)
	if record.Track.IsPlaying then
		record.Track:Stop(fadeTime)
	end
end

function AnimationController.new(actor: Model, profile: Profile?): ControllerType
	assert(actor:IsA("Model"), "Motion.AnimationController: actor must be a Model")
	local controller = setmetatable({
		_actor = actor,
		_animator = _getAnimator(actor),
		_profile = profile or { Animations = {} },
		_tracks = {},
		_layers = {},
		_janitor = Janitor.new(),
		_destroyed = false,
		Started = Signal.new(),
		Stopped = Signal.new(),
		Changed = Signal.new(),
	}, AnimationController) :: ControllerImpl

	controller._janitor:Add(actor.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			controller:Destroy()
		end
	end))
	return controller
end

function AnimationController:_load(name: string): AnimationTrack?
	local existing = self._tracks[name]
	if existing then
		return existing.Track
	end

	local definition = _getDefinition(self._profile, name)
	if not definition or definition.Id == "" then
		warn("Motion.AnimationController: missing animation definition " .. name)
		return nil
	end

	local animation = Instance.new("Animation")
	animation.Name = "Motion_" .. name
	animation.AnimationId = definition.Id
	local ok, track = pcall(function()
		return self._animator:LoadAnimation(animation)
	end)
	if not ok then
		animation:Destroy()
		warn("Motion.AnimationController: failed to load " .. name .. ": " .. tostring(track))
		return nil
	end

	track.Looped = definition.Looped == true
	if definition.Priority then
		track.Priority = definition.Priority
	end
	self._tracks[name] = { Animation = animation, Track = track }
	self._janitor:Add(track.Stopped:Connect(function()
		if self._destroyed then
			return
		end
		for layer, activeName in self._layers do
			if activeName == name then
				self._layers[layer] = nil
			end
		end
		self.Stopped:Fire(name, track)
	end))
	return track
end

function AnimationController:Play(name: string, options: PlayOptions?): AnimationTrack?
	if self._destroyed then
		return nil
	end
	local track = self:_load(name)
	if not track then
		return nil
	end
	options = options or {}
	local fadeTime = options.FadeTime or DEFAULT_FADE_TIME
	if options.Layer then
		local previousName = self._layers[options.Layer]
		if previousName and previousName ~= name then
			self:Stop(previousName, fadeTime)
		end
		self._layers[options.Layer] = name
	end
	if options.Restart and track.IsPlaying then
		track:Stop(0)
	end
	if track.IsPlaying and not options.Restart then
		if options.Speed then
			track:AdjustSpeed(options.Speed)
		end
		if options.Weight then
			track:AdjustWeight(options.Weight, fadeTime)
		end
		return track
	end
	track:Play(fadeTime, options.Weight or 1, options.Speed or 1)
	self.Started:Fire(name, track)
	return track
end

function AnimationController:Crossfade(name: string, fadeTime: number?, layer: string?): AnimationTrack?
	return self:Play(name, {
		FadeTime = fadeTime,
		Layer = layer or "Base",
	})
end

function AnimationController:Stop(name: string, fadeTime: number?)
	local record = self._tracks[name]
	if not record then
		return
	end
	local duration = fadeTime or DEFAULT_FADE_TIME
	_stopRecord(record, duration)
	for layer, activeName in self._layers do
		if activeName == name then
			self._layers[layer] = nil
		end
	end
end

function AnimationController:StopLayer(layer: string, fadeTime: number?)
	local name = self._layers[layer]
	if name then
		self:Stop(name, fadeTime)
	end
end

function AnimationController:StopAll(fadeTime: number?)
	for name in self._tracks do
		self:Stop(name, fadeTime)
	end
end

function AnimationController:SetState(name: string, fadeTime: number?, layer: string?): AnimationTrack?
	local previous = self._layers[layer or "Base"]
	local track = self:Crossfade(name, fadeTime, layer)
	if track and previous ~= name then
		self.Changed:Fire(name, previous, layer or "Base")
	end
	return track
end

function AnimationController:UpdateLocomotion(horizontalSpeed: number, fadeTime: number?): AnimationTrack?
	local locomotion = self._profile.Locomotion
	if not locomotion then
		return nil
	end
	local idle = locomotion.Idle
	local walk = locomotion.Walk
	local run = locomotion.Run
	local walkSpeed = locomotion.WalkSpeed or DEFAULT_WALK_SPEED
	local runSpeed = locomotion.RunSpeed or DEFAULT_RUN_SPEED
	local name: string?
	local playbackSpeed = 1
	if horizontalSpeed <= 0.05 then
		name = idle
	elseif run and horizontalSpeed >= runSpeed then
		name = run
		playbackSpeed = math.max(0.1, horizontalSpeed / runSpeed)
	else
		name = walk or run
		if name == walk then
			playbackSpeed = math.max(0.1, horizontalSpeed / walkSpeed)
		elseif run then
			playbackSpeed = math.max(0.1, horizontalSpeed / runSpeed)
		end
	end
	if not name then
		return nil
	end
	local track = self:SetState(name, fadeTime, "Base")
	if track then
		track:AdjustSpeed(playbackSpeed)
	end
	return track
end

function AnimationController:AdjustSpeed(name: string, speed: number): boolean
	local record = self._tracks[name]
	if not record then
		return false
	end
	record.Track:AdjustSpeed(speed)
	return true
end

function AnimationController:AdjustWeight(name: string, weight: number, fadeTime: number?): boolean
	local record = self._tracks[name]
	if not record then
		return false
	end
	record.Track:AdjustWeight(weight, fadeTime or DEFAULT_FADE_TIME)
	return true
end

function AnimationController:GetTracks(): { string }
	local result = {}
	for name in self._tracks do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

function AnimationController:GetLength(name: string): number?
	local track = self:_load(name)
	return track and track.Length
end

function AnimationController:Preload(names: { string }?)
	if names then
		for _, name in names do
			self:_load(name)
		end
		return
	end
	for name in self._profile.Animations do
		self:_load(name)
	end
end

function AnimationController:BindMarker(
	name: string,
	markerName: string,
	callback: (...any) -> ()
): RBXScriptConnection?
	local track = self:_load(name)
	if not track then
		return nil
	end
	local connection = track:GetMarkerReachedSignal(markerName):Connect(callback)
	self._janitor:Add(connection)
	return connection
end

function AnimationController:BindEnded(name: string, callback: () -> ()): RBXScriptConnection?
	local track = self:_load(name)
	if not track then
		return nil
	end
	local connection = track.Ended:Connect(callback)
	self._janitor:Add(connection)
	return connection
end

-- Backwards-compatible name from the previous animator wrapper.
function AnimationController:TrackEnded(name: string, callback: () -> ()): RBXScriptConnection?
	return self:BindEnded(name, callback)
end

function AnimationController:GetTrack(name: string): AnimationTrack?
	return self._tracks[name] and self._tracks[name].Track or nil
end

function AnimationController:IsPlaying(name: string): boolean
	local track = self:GetTrack(name)
	return track ~= nil and track.IsPlaying
end

function AnimationController:SetProfile(profile: Profile)
	assert(type(profile) == "table" and type(profile.Animations) == "table", "Motion: invalid animation profile")
	for _, record in self._tracks do
		_stopRecord(record, 0)
		record.Track:Destroy()
		record.Animation:Destroy()
	end
	table.clear(self._tracks)
	table.clear(self._layers)
	self._profile = profile
end

function AnimationController:GetProfile(): Profile
	return self._profile
end

function AnimationController:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, record in self._tracks do
		_stopRecord(record, 0)
		record.Track:Destroy()
		record.Animation:Destroy()
	end
	table.clear(self._tracks)
	table.clear(self._layers)
	self._janitor:Destroy()
	self.Started:Destroy()
	self.Stopped:Destroy()
	self.Changed:Destroy()
end

return AnimationController
