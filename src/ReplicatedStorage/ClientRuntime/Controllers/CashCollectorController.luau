--!strict
-- Staged 3D presentation for collecting earnings.
--
-- Collection is server-decided and instant: FarmEconomyService polls the Cash
-- Collector pad (and answers an explicit CollectEarnings request), zeroes
-- PendingEarnings, and fires Sold. Nothing in this file changes that, delays
-- it, or awards anything — it only stops the transaction from *looking* like a
-- number changing. Adapted from the old SellZoneController: same cash-payout
-- beats, minus the bamboo-bundle deposit beat, since nothing physical is being
-- handed over here — only banked earnings being claimed.
--
-- The show runs in two beats off one Sold packet:
--
--   process   the pad flashes and pulses, as if the earnings are being counted
--   payout    capped cash tokens burst outward, hover, then home to the player
--
-- Amount only ever changes *intensity*: token count, burst radius, and glow,
-- each between a floor and a hard cap. Nothing is ever spawned per unit
-- earned, so a huge payout costs the same frame time as a small one.
--
-- The cash tokens are presentation objects. They are not touchable, not
-- collectible, and grant nothing; the server already paid out before this file
-- heard about the sale.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Signal = Core:Get("Signal")

local ClientModules = script.Parent.Parent:WaitForChild("Modules")
local FeelBurst = require(ClientModules:WaitForChild("FeelBurst"))
local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))
local Relay = Core:GetShared("Network")

local CashCollectorController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local SELL = FeelConfig.Sell
local IDLE_BIND = "BambooCashCollectorIdle"

--[[
	Fires once per collection, after the payout visuals have reached the player.
	A later UI pass can hook this to animate the money counter in time with the
	cash arriving, instead of the counter moving the instant the server replies.
	@param amount number Earnings collected, straight from the server's Sold packet.
	@param money number The player's new balance.
]]
CashCollectorController.PayoutArrived = Signal.new()

local _effectsFolder: Folder? = nil
local _pad: BasePart? = nil
local _padBaseTransparency = 0
-- Every visual object currently alive from a collection, so a rapid run of
-- collections can never exceed the cap. Objects deregister themselves on
-- cleanup.
local _liveObjects = 0

-- ── infrastructure ───────────────────────────────────────────────────────────

local function _folder(): Folder
	local existing = _effectsFolder
	if existing and existing.Parent then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "BambooCashEffects"
	created.Parent = workspace
	_effectsFolder = created
	return created
end

-- Reserves `count` object slots, returning how many were actually granted. The
-- cap is what stops a player parked at the pad from carpeting the plot.
local function _reserve(count: number): number
	local granted = math.max(math.min(count, SELL.MaxLiveObjects - _liveObjects), 0)
	_liveObjects += granted
	return granted
end

local function _release(count: number)
	_liveObjects = math.max(_liveObjects - count, 0)
end

-- The local player's own Cash Collector pad. Resolved lazily and re-resolved
-- if the plot changes hands, because PlotService reassigns plots as players
-- come and go.
local function _resolvePad(): BasePart?
	local existing = _pad
	if existing and existing.Parent then
		local plot = existing.Parent
		if plot and plot:GetAttribute("OwnerUserId") == LOCAL_PLAYER.UserId then
			return existing
		end
	end

	_pad = nil

	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == LOCAL_PLAYER.UserId then
			local collector = plot:FindFirstChild("CashCollector")
			if collector and collector:IsA("BasePart") then
				_pad = collector
				_padBaseTransparency = collector.Transparency
				return collector
			end
		end
	end
	return nil
end

-- ── idle ─────────────────────────────────────────────────────────────────────

-- The pad breathes while it is usable. One sine on one part: the cheapest
-- possible "this is interactive" signal, and it costs nothing when the player
-- has no plot.
local function _idleUpdate()
	if not FeelConfig.Enabled.SellShow then
		return
	end
	local pad = _resolvePad()
	if not pad then
		return
	end

	local pulse = (math.sin(os.clock() * math.pi * 2 / SELL.IdlePulseSeconds) + 1) * 0.5
	pad.Transparency = _padBaseTransparency + pulse * SELL.IdlePulseTransparency
end

-- ── visual objects ───────────────────────────────────────────────────────────

local function _newCashToken(position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = "EarningsCash"
	part.Size = SELL.CashSize
	part.Color = SELL.CashColor
	part.Material = Enum.Material.Neon
	part.Anchored = true
	-- Presentation only: a cash token must never be touchable or queryable, or
	-- it starts looking like a pickup the player can chase.
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position)
	part.Parent = _folder()
	return part
end

-- Quadratic bezier, matching Orbify's arc so world motion is consistent between
-- collecting bamboo and collecting earnings.
local function _bezier(start: Vector3, control: Vector3, finish: Vector3, t: number): Vector3
	return start:Lerp(control, t):Lerp(control:Lerp(finish, t), t)
end

--[[
	Flies one anchored part along an arc, then runs `onArrive`.
]]
local function _flyArc(
	part: BasePart,
	finishAt: () -> Vector3?,
	seconds: number,
	arcHeight: number,
	spin: boolean,
	onArrive: (Vector3) -> ()
)
	local start = part.Position
	local firstTarget = finishAt()
	if not firstTarget then
		part:Destroy()
		onArrive(start)
		return
	end

	local control = start:Lerp(firstTarget, 0.5)
		+ Vector3.new(0, arcHeight, 0)
		+ Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2

	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt: number)
		if not part.Parent then
			connection:Disconnect()
			onArrive(part.Position)
			return
		end

		elapsed += dt
		local live = finishAt()
		if not live then
			-- Target gone (player died, character despawned): land where we are
			-- rather than flying at a stale point.
			connection:Disconnect()
			local landed = part.Position
			part:Destroy()
			onArrive(landed)
			return
		end

		local t = math.min(elapsed / seconds, 1)
		-- Ease in: the object hangs, then accelerates into the target, which is
		-- what makes the arrival feel like an arrival.
		local eased = t * t
		part.Position = _bezier(start, control, live, eased)
		if spin then
			part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, eased * 12, eased * 8)
		end

		if t >= 1 then
			connection:Disconnect()
			local landed = part.Position
			part:Destroy()
			onArrive(landed)
		end
	end)
end

local function _characterPosition(): Vector3?
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	return root.Position + Vector3.new(0, 1.5, 0)
end

-- ── the two beats ────────────────────────────────────────────────────────────

-- Beat 2: cash bursts outward from the pad, hovers, then homes to the player
-- and dissolves. `onAllHome` fires once, after the last token lands.
local function _payout(padPosition: Vector3, amount: number, onAllHome: () -> ())
	local big = amount >= SELL.BigPayoutThreshold
	local wanted =
		math.clamp(SELL.MinCash + math.floor(math.log(math.max(amount, 1) + 1, 2)), SELL.MinCash, SELL.MaxCash)
	local count = _reserve(wanted)
	if count <= 0 then
		onAllHome()
		return
	end

	local radius = SELL.CashBurstRadius * (if big then SELL.BigPayoutRadiusScale else 1)
	local remaining = count
	local fired = false
	local function finishOne()
		remaining -= 1
		_release(1)
		if remaining <= 0 and not fired then
			fired = true
			onAllHome()
		end
	end

	for index = 1, count do
		local token = _newCashToken(padPosition)

		-- Fan the burst evenly rather than randomly, so a payout reads as a
		-- deliberate spray instead of scattered noise.
		local angle = (index - 1) / count * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius
		local apex = padPosition + outward + Vector3.new(0, SELL.CashRiseStuds, 0)

		local burst = TweenService:Create(
			token,
			TweenInfo.new(SELL.CashSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(apex) * CFrame.Angles(0, angle, math.rad(20)) }
		)
		burst:Play()

		-- Hover, then home. Delays rather than chained Completed handlers, so a
		-- token whose tween is interrupted still gets cleaned up on its schedule.
		task.delay(SELL.CashSeconds + SELL.HoverSeconds + (index - 1) * SELL.ReturnStagger, function()
			if not token.Parent then
				finishOne()
				return
			end
			_flyArc(token, _characterPosition, SELL.ReturnSeconds, SELL.ReturnArcHeight, true, function(landed)
				FeelBurst.Emit(landed, {
					Color = SELL.CashColor,
					Count = 4,
					Size = 0.3,
					Speed = NumberRange.new(2, 5),
					Lifetime = NumberRange.new(0.1, 0.2),
					Gravity = 0,
					LightEmission = 1,
				})
				finishOne()
			end)
		end)

		-- Hard backstop: whatever happens to the tweens above, no token outlives
		-- the full show by more than a moment.
		Debris:AddItem(
			token,
			SELL.CashSeconds + SELL.HoverSeconds + SELL.ReturnSeconds + count * SELL.ReturnStagger + 2
		)
	end
end

-- Beat 1: the pad reacts, then the payout starts. No deposit beat — nothing
-- physical is handed over at the Cash Collector, only banked earnings claimed.
local function _process(pad: BasePart, amount: number, money: number)
	local big = amount >= SELL.BigPayoutThreshold
	local padPosition = pad.Position + Vector3.new(0, pad.Size.Y * 0.5 + 0.5, 0)

	local punch = TweenService:Create(pad, TweenInfo.new(SELL.ProcessSeconds, Enum.EasingStyle.Quad), {
		Transparency = math.max(_padBaseTransparency - 0.3, 0),
	})
	punch:Play()

	FeelBurst.Emit(padPosition, {
		Color = SELL.CashColor,
		Count = if big then 20 else 12,
		Size = 0.5,
		Speed = NumberRange.new(6, if big then 20 else 13),
		Lifetime = NumberRange.new(0.2, 0.45),
		Gravity = -4,
		LightEmission = 1,
	})

	local ring = FeelConfig.Combo.Ring
	FeelBurst.Ring(
		pad.Position,
		SELL.CashColor,
		ring.Seconds,
		ring.StartDiameter,
		ring.EndDiameter * (if big then 1.5 else 1),
		ring.Thickness
	)

	task.delay(SELL.ProcessSeconds, function()
		_payout(padPosition, amount, function()
			-- The counter itself is untouched in this pass; this is the hook a
			-- later UI pass can use to move it in time with the cash landing.
			CashCollectorController.PayoutArrived:Fire(amount, money)
		end)

		if big then
			-- A second, smaller wave a beat later, so a large payout reads as
			-- more *sustained* rather than merely wider.
			for wave = 2, SELL.BigPayoutWaves do
				task.delay((wave - 1) * 0.18, function()
					FeelBurst.Emit(padPosition, {
						Color = SELL.CashColor,
						Count = 10,
						Size = 0.45,
						Speed = NumberRange.new(8, 16),
						Lifetime = NumberRange.new(0.2, 0.4),
						Gravity = -4,
						LightEmission = 1,
					})
				end)
			end
		end
	end)
end

local function _onSold(payload: any)
	if not FeelConfig.Enabled.SellShow then
		return
	end
	local amount = payload.amount :: number
	if amount <= 0 then
		return
	end

	local pad = _resolvePad()
	if not pad then
		return
	end
	_process(pad, amount, payload.money :: number)
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function CashCollectorController:Start(_fw: any)
	Relay.Bamboo.Sold.listen(_onSold)

	-- Idle pulse runs on the shared render step at the lowest priority. It early
	-- outs when the player has no plot, so a spectator costs nothing.
	RunService:BindToRenderStep(IDLE_BIND, Enum.RenderPriority.Last.Value, _idleUpdate)

	-- Drop every in-flight visual when the character goes, so tokens mid-hover
	-- do not hang in the air over an empty plot.
	LOCAL_PLAYER.CharacterRemoving:Connect(function()
		local folder = _effectsFolder
		if folder then
			folder:ClearAllChildren()
		end
		_liveObjects = 0
	end)
end

return CashCollectorController
