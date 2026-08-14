--!strict
-- Client camera blur/zoom for stacked UI focus.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local CameraEffects = {}
CameraEffects.__index = CameraEffects

export type CameraEffectsInstance = typeof(setmetatable(
	{} :: {
		player: Player,
		camera: Camera,
		originalFOV: number,
		activeUICount: number,
		blurEffect: BlurEffect,
		activeTweens: { blur: Tween?, zoom: Tween? },
	},
	CameraEffects
))

local CONFIG = {
	blur = {
		size = 20,
		tweenIn = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		tweenOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	},
	zoom = {
		fieldOfView = 50,
		tweenIn = TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
		tweenOut = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
}

function CameraEffects.new(): CameraEffectsInstance
	local camera = workspace.CurrentCamera
	assert(camera, "[CameraEffects] CurrentCamera required")

	local self = setmetatable({}, CameraEffects)
	self.player = Players.LocalPlayer
	self.camera = camera
	self.originalFOV = camera.FieldOfView or 70
	self.activeUICount = 0
	self.activeTweens = {}

	local existingBlur = camera:FindFirstChildOfClass("BlurEffect")
	if existingBlur and existingBlur.Name == "UIBlurEffect" then
		existingBlur:Destroy()
	end

	local blur = Instance.new("BlurEffect")
	blur.Name = "UIBlurEffect"
	blur.Size = 0
	blur.Parent = camera
	self.blurEffect = blur

	CameraEffects.setupCameraChangeHandler(self)

	return self :: CameraEffectsInstance
end

function CameraEffects.setupCameraChangeHandler(self: CameraEffectsInstance)
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local nextCamera = workspace.CurrentCamera
		if not nextCamera then
			return
		end
		self.camera = nextCamera
		self.originalFOV = nextCamera.FieldOfView or 70

		if self.blurEffect.Parent ~= self.camera then
			self.blurEffect.Parent = self.camera
		end

		if self.activeUICount > 0 then
			CameraEffects.applyEffects(self, true)
		end
	end)
end

function CameraEffects.cancelTweens(self: CameraEffectsInstance)
	for _, tween in pairs(self.activeTweens) do
		if tween then
			tween:Cancel()
		end
	end
	self.activeTweens = {}
end

function CameraEffects.applyEffects(self: CameraEffectsInstance, skipAnimation: boolean?)
	CameraEffects.cancelTweens(self)

	if skipAnimation then
		-- Instant application (for camera respawn)
		self.blurEffect.Size = CONFIG.blur.size
		self.camera.FieldOfView = CONFIG.zoom.fieldOfView
	else
		-- Animated application
		local blurTween = TweenService:Create(self.blurEffect, CONFIG.blur.tweenIn, { Size = CONFIG.blur.size })

		local zoomTween =
			TweenService:Create(self.camera, CONFIG.zoom.tweenIn, { FieldOfView = CONFIG.zoom.fieldOfView })

		blurTween:Play()
		zoomTween:Play()

		self.activeTweens.blur = blurTween
		self.activeTweens.zoom = zoomTween
	end
end

function CameraEffects.removeEffects(self: CameraEffectsInstance, skipAnimation: boolean?)
	CameraEffects.cancelTweens(self)

	if skipAnimation then
		-- Instant removal
		self.blurEffect.Size = 0
		self.camera.FieldOfView = self.originalFOV
	else
		-- Animated removal
		local blurTween = TweenService:Create(self.blurEffect, CONFIG.blur.tweenOut, { Size = 0 })

		local zoomTween = TweenService:Create(self.camera, CONFIG.zoom.tweenOut, { FieldOfView = self.originalFOV })

		blurTween:Play()
		zoomTween:Play()

		self.activeTweens.blur = blurTween
		self.activeTweens.zoom = zoomTween
	end
end

function CameraEffects.enableForUI(self: CameraEffectsInstance)
	self.activeUICount = self.activeUICount + 1

	if self.activeUICount == 1 then
		CameraEffects.applyEffects(self, false)
	end

	return self.activeUICount
end

function CameraEffects.disableForUI(self: CameraEffectsInstance)
	self.activeUICount = math.max(0, self.activeUICount - 1)

	if self.activeUICount == 0 then
		CameraEffects.removeEffects(self, false)
	end

	return self.activeUICount
end

function CameraEffects.getActiveUICount(self: CameraEffectsInstance)
	return self.activeUICount
end

function CameraEffects.forceReset(self: CameraEffectsInstance)
	self.activeUICount = 0
	CameraEffects.removeEffects(self, true)
end

function CameraEffects.setBlurSize(_self: CameraEffectsInstance, size: number)
	CONFIG.blur.size = size
end

function CameraEffects.setZoomFOV(_self: CameraEffectsInstance, fov: number)
	CONFIG.zoom.fieldOfView = fov
end

function CameraEffects.cleanup(self: CameraEffectsInstance)
	CameraEffects.cancelTweens(self)

	self.blurEffect:Destroy()

	self.camera.FieldOfView = self.originalFOV
end

local activeInstance: CameraEffectsInstance? = nil

function CameraEffects.getInstance(): CameraEffectsInstance
	if not activeInstance then
		activeInstance = CameraEffects.new()
	end
	return activeInstance :: CameraEffectsInstance
end

return CameraEffects
