--!strict
--[[
	FlashPool: brief impact flashes on world models, from a fixed pool.

	Highlights are not cheap and Roblox caps how many render at once, so leaving
	one parented to every stalk is wasteful and creating one per hit churns
	instances during exactly the moments the game is busiest. This keeps a small
	pool and cycles it: the oldest flash is stolen when the pool runs dry, which
	is the right trade — during a flurry the newest hit is the one worth seeing.

		local FlashPool = Core:Get("FlashPool")

		FlashPool.Flash(stalkModel, Color3.fromRGB(255, 255, 255), 0.12)

	Client-side only. Flashes are pure feedback and are never replicated.
]]

local RunService = game:GetService("RunService")

local FlashPool = {}

local POOL_SIZE = 10
local DEFAULT_SECONDS = 0.12
-- Flashes start here and fade to invisible; 0 would blow out the silhouette.
local PEAK_FILL_TRANSPARENCY = 0.45
local PEAK_OUTLINE_TRANSPARENCY = 0.15

type Slot = {
	Highlight: Highlight,
	-- os.clock() this flash ends; 0 when the slot is free.
	EndsAt: number,
	Duration: number,
}

local _slots: { Slot } = {}
local _container: Folder? = nil
local _started = false

local function _ensureContainer(): Folder
	local existing = _container
	if existing and existing.Parent then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "FlashPool"
	folder.Parent = workspace
	_container = folder
	return folder
end

local function _newSlot(): Slot
	local highlight = Instance.new("Highlight")
	highlight.Name = "Flash"
	highlight.Enabled = false
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	-- AlwaysOnTop would punch the flash through the bamboo in front of it, which
	-- reads as a UI element rather than an impact.
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = _ensureContainer()

	return { Highlight = highlight, EndsAt = 0, Duration = DEFAULT_SECONDS }
end

-- Free slot if there is one, otherwise the one closest to finishing. Stealing
-- beats skipping: during a flurry the player should see the newest hit.
local function _acquire(): Slot
	local oldest: Slot? = nil
	for _, slot in _slots do
		if slot.EndsAt == 0 then
			return slot
		end
		if oldest == nil or slot.EndsAt < oldest.EndsAt then
			oldest = slot
		end
	end
	return oldest :: Slot
end

-- One shared frame loop drives every active flash, rather than a tween or a
-- thread per hit.
local function _onFrame()
	local now = os.clock()

	for _, slot in _slots do
		if slot.EndsAt == 0 then
			continue
		end

		local remaining = slot.EndsAt - now
		if remaining <= 0 then
			slot.EndsAt = 0
			slot.Highlight.Enabled = false
			slot.Highlight.Adornee = nil
			continue
		end

		-- Linear fade out from the peak; the flash is short enough that easing
		-- would not be visible.
		local alpha = remaining / slot.Duration
		slot.Highlight.FillTransparency = 1 - alpha * (1 - PEAK_FILL_TRANSPARENCY)
		slot.Highlight.OutlineTransparency = 1 - alpha * (1 - PEAK_OUTLINE_TRANSPARENCY)
	end
end

local function _start()
	if _started or not RunService:IsClient() then
		return
	end
	_started = true

	for _ = 1, POOL_SIZE do
		table.insert(_slots, _newSlot())
	end

	RunService:BindToRenderStep("FlashPoolUpdate", Enum.RenderPriority.Last.Value, _onFrame)
end

--[[
	Flashes a model or part for a moment.
	@param adornee Instance The model or BasePart to flash; ignored when unparented.
	@param color Color3 Flash colour, usually tinted by what was hit.
	@param seconds number? How long the flash lasts; defaults to a very short blink.
]]
function FlashPool.Flash(adornee: Instance, color: Color3, seconds: number?)
	if not RunService:IsClient() or not adornee.Parent then
		return
	end
	_start()

	local duration = seconds or DEFAULT_SECONDS
	local slot = _acquire()
	if not slot then
		return
	end

	slot.Duration = duration
	slot.EndsAt = os.clock() + duration

	local highlight = slot.Highlight
	highlight.Adornee = adornee
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = PEAK_FILL_TRANSPARENCY
	highlight.OutlineTransparency = PEAK_OUTLINE_TRANSPARENCY
	highlight.Enabled = true
end

--[[
	How many flashes the pool can run at once, for tuning against a swing's
	maximum multi-hit.
	@return number Pool size.
]]
function FlashPool.Capacity(): number
	return POOL_SIZE
end

return FlashPool
