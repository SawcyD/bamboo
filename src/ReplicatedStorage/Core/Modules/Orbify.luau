--!strict
--[[
	Orbify: collectible orbs that fly from a source to a target.

	The point is tactile collection — instead of a number changing, physical
	orbs pop out, tumble, then get scooped up one at a time. Staggering the
	arrivals is what turns a single pickup into a satisfying run.

		local Orbify = Core:Get("Orbify")

		Orbify.Burst({
			Origin = stalkPosition,
			Target = character.HumanoidRootPart,
			Count = 3,
			Color = Color3.fromRGB(112, 172, 84),
			OnAbsorb = function(index, total, position)
				-- play a sound a step higher for each arrival
			end,
		})

	`Burst` spawns world orbs (BaseParts). `UIBurst` spawns screen-space orbs
	that fly into a GuiObject, for payouts landing on a HUD counter.

	Client-side only: these are cosmetic, so they are never replicated.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Orbify = {}

local DEFAULT_TUMBLE_SECONDS = 0.28
local DEFAULT_STAGGER_SECONDS = 0.07
local DEFAULT_FLIGHT_SECONDS = 0.42
local DEFAULT_ARC_HEIGHT = 6
local DEFAULT_POP_SPEED = 9
local ORB_TIMEOUT = 6

export type AbsorbCallback = (index: number, total: number, position: Vector3) -> ()

export type BurstConfig = {
	Origin: Vector3,
	-- Where the orbs end up. A BasePart is tracked live, so orbs follow a
	-- moving player instead of flying at where they used to be.
	Target: BasePart | Vector3,
	Count: number?,
	Color: Color3?,
	Size: Vector3?,
	Shape: Enum.PartType?,
	Material: Enum.Material?,
	-- Seconds orbs tumble loose before the pull starts.
	TumbleSeconds: number?,
	-- Gap between each orb starting its flight; this is what makes it a run.
	StaggerSeconds: number?,
	FlightSeconds: number?,
	ArcHeight: number?,
	-- Physical pop when the orbs first appear. Set 0 for a straight pull.
	PopSpeed: number?,
	Parent: Instance?,
	OnAbsorb: AbsorbCallback?,
}

export type UIBurstConfig = {
	From: Vector2,
	Target: GuiObject,
	Count: number?,
	Color: Color3?,
	Image: string?,
	PixelSize: number?,
	StaggerSeconds: number?,
	FlightSeconds: number?,
	Spread: number?,
	OnAbsorb: (index: number, total: number) -> ()?,
}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function _effectsParent(explicit: Instance?): Instance
	if explicit then
		return explicit
	end
	local folder = workspace:FindFirstChild("OrbifyEffects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "OrbifyEffects"
		folder.Parent = workspace
	end
	return folder
end

local function _targetPosition(target: BasePart | Vector3): Vector3?
	if typeof(target) == "Vector3" then
		return target
	end
	local part = target :: BasePart
	if not part.Parent then
		return nil
	end
	return part.Position + Vector3.new(0, 1.5, 0)
end

local function _randomHorizontal(): Vector3
	local direction = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
	if direction.Magnitude < 0.05 then
		return Vector3.xAxis
	end
	return direction.Unit
end

-- Quadratic bezier, so an orb sweeps rather than sliding along a line.
local function _bezier(start: Vector3, control: Vector3, finish: Vector3, t: number): Vector3
	return start:Lerp(control, t):Lerp(control:Lerp(finish, t), t)
end

-- ── world orbs ───────────────────────────────────────────────────────────────

-- Flies one orb home on a cubic ease-in: it hangs, then snaps in.
local function _pullOrb(orb: BasePart, config: BurstConfig, index: number, total: number)
	local flightSeconds = config.FlightSeconds or DEFAULT_FLIGHT_SECONDS
	local arcHeight = config.ArcHeight or DEFAULT_ARC_HEIGHT

	local finish = _targetPosition(config.Target)
	if not finish or not orb.Parent then
		orb:Destroy()
		return
	end

	orb.Anchored = true
	orb.CanCollide = false

	local start = orb.Position
	local startSize = orb.Size
	local control = start:Lerp(finish, 0.5) + Vector3.new(0, arcHeight, 0) + _randomHorizontal() * 3

	local elapsed = 0
	while elapsed < flightSeconds and orb.Parent do
		elapsed += RunService.RenderStepped:Wait()
		local live = _targetPosition(config.Target)
		if not live then
			break
		end

		local t = math.min(elapsed / flightSeconds, 1)
		local eased = t * t * t
		orb.Position = _bezier(start, control, live, eased)
		orb.CFrame = CFrame.new(orb.Position) * CFrame.Angles(0, eased * 18, math.rad(90) + eased * 6)
		orb.Size = startSize:Lerp(startSize * 0.25, eased)
	end

	local landed = orb.Position
	orb:Destroy()

	if config.OnAbsorb then
		config.OnAbsorb(index, total, landed)
	end
end

--[[
	Pops a burst of world orbs that tumble, then stream into the target.
	@param config BurstConfig Where the orbs come from, where they go, and how they look.
	@return { BasePart } The spawned orbs, in the order they will be collected.
]]
function Orbify.Burst(config: BurstConfig): { BasePart }
	assert(RunService:IsClient(), "Orbify is a client-side effect")

	local count = config.Count or 3
	local parent = _effectsParent(config.Parent)
	local tumble = config.TumbleSeconds or DEFAULT_TUMBLE_SECONDS
	local stagger = config.StaggerSeconds or DEFAULT_STAGGER_SECONDS
	local popSpeed = config.PopSpeed or DEFAULT_POP_SPEED

	local orbs: { BasePart } = {}

	for i = 1, count do
		local orb = Instance.new("Part")
		orb.Name = "Orb"
		orb.Shape = config.Shape or Enum.PartType.Ball
		orb.Size = config.Size or Vector3.one
		orb.Color = config.Color or Color3.fromRGB(255, 255, 255)
		orb.Material = config.Material or Enum.Material.Neon
		orb.CanCollide = popSpeed > 0
		orb.CanQuery = false
		orb.CanTouch = false
		orb.CastShadow = false
		orb.CFrame = CFrame.new(config.Origin + Vector3.new(0, 1.2 + (i - 1) * 1.8, 0))
			* CFrame.Angles(0, math.random() * math.pi * 2, math.rad(90))
		orb.Parent = parent

		if popSpeed > 0 then
			orb.AssemblyLinearVelocity = _randomHorizontal() * popSpeed + Vector3.new(0, 8 + i * 2, 0)
			orb.AssemblyAngularVelocity = Vector3.new(math.random(-9, 9), math.random(-9, 9), math.random(-9, 9))
		end

		-- Hard ceiling so a dropped target can never leak orbs into the world.
		Debris:AddItem(orb, ORB_TIMEOUT)
		table.insert(orbs, orb)

		task.delay(tumble + (i - 1) * stagger, function()
			_pullOrb(orb, config, i, count)
		end)
	end

	return orbs
end

-- ── UI orbs ──────────────────────────────────────────────────────────────────

--[[
	Flies screen-space orbs into a GuiObject, for a payout landing on a counter.
	@param config UIBurstConfig Source point, destination GuiObject, and looks.
]]
function Orbify.UIBurst(config: UIBurstConfig)
	assert(RunService:IsClient(), "Orbify is a client-side effect")

	local target = config.Target
	local screen = target:FindFirstAncestorWhichIsA("ScreenGui")
	if not screen then
		return
	end

	local count = config.Count or 6
	local pixelSize = config.PixelSize or 26
	local stagger = config.StaggerSeconds or 0.05
	local flightSeconds = config.FlightSeconds or 0.45
	local spread = config.Spread or 120

	for i = 1, count do
		local orb = Instance.new("ImageLabel")
		orb.Name = "UIOrb"
		orb.BackgroundTransparency = if config.Image then 1 else 0
		orb.BackgroundColor3 = config.Color or Color3.fromRGB(255, 226, 130)
		orb.Image = config.Image or ""
		orb.ImageColor3 = config.Color or Color3.fromRGB(255, 226, 130)
		orb.Size = UDim2.fromOffset(pixelSize, pixelSize)
		orb.AnchorPoint = Vector2.new(0.5, 0.5)
		orb.Position = UDim2.fromOffset(config.From.X, config.From.Y)
		orb.ZIndex = 50
		orb.Parent = screen

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = orb

		-- Scatter first so the orbs read as a handful, not a single stream.
		local scatter = Vector2.new(math.random() - 0.5, math.random() - 0.5) * spread

		task.delay((i - 1) * stagger, function()
			if not orb.Parent or not target.Parent then
				orb:Destroy()
				return
			end

			local scatterTween = TweenService:Create(orb, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
				Position = UDim2.fromOffset(config.From.X + scatter.X, config.From.Y + scatter.Y),
			})
			scatterTween:Play()
			scatterTween.Completed:Wait()

			if not orb.Parent or not target.Parent then
				orb:Destroy()
				return
			end

			local destination = target.AbsolutePosition + target.AbsoluteSize * 0.5
			local fly = TweenService:Create(
				orb,
				TweenInfo.new(flightSeconds, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
				{
					Position = UDim2.fromOffset(destination.X, destination.Y),
					Size = UDim2.fromOffset(pixelSize * 0.4, pixelSize * 0.4),
				}
			)
			fly:Play()
			fly.Completed:Wait()

			orb:Destroy()
			if config.OnAbsorb then
				config.OnAbsorb(i, count)
			end
		end)
	end
end

return Orbify
