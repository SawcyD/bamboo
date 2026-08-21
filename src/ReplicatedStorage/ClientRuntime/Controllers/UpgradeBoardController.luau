--!strict
-- Upgrade boards. Each board shows its own level/effect/cost on a billboard and
-- only becomes buyable when the player is standing next to it — Phase 1 has no
-- upgrade menu.
--
-- The cost is a real button so touch and mouse players can tap it directly; [E]
-- does the same thing for keyboard and gamepad. Both paths ripple.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Bamboo = Core:GetDomain("Bamboo")
local FormatUtil = Core:GetUtil("FormatUtil")
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")
local UI = require(ReplicatedStorage:WaitForChild("UI"))
local Ripple = UI:GetModule("Ripple")

local ClientModules = script.Parent.Parent:WaitForChild("Modules")
local FeelBurst = require(ClientModules:WaitForChild("FeelBurst"))
local FeelConfig = require(script.Parent.Parent:WaitForChild("Configs"):WaitForChild("FeelConfig"))
local Spring = Core:GetPackage("Spring")

local UpgradeBoardController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local BOARD_TAG = "BambooUpgradeBoard"
local BUY_ACTION = "BambooBuyUpgrade"
local PROXIMITY_STUDS = 14
local REFRESH_BIND = "BambooBoardRefresh"

local BOARD = FeelConfig.Board
local FEEL_BIND = "BambooBoardFeel"
-- Boards further than this from the camera are settled and skipped. A plot is
-- 160 studs and plots sit 220 apart, so this keeps the player's own six boards
-- and a neighbouring plot's live while dropping the other ten plots.
local BOARD_VISIBLE_SQ = 180 * 180

type BoardView = {
	Part: BasePart,
	UpgradeId: string,
	TitleLabel: TextLabel,
	StatLabel: TextLabel,
	CostButton: TextButton,
	PromptLabel: TextLabel,

	-- Rest pose, captured once at attach. Every lean and punch is expressed as an
	-- offset from this, so repeated purchases cannot walk the board off its base.
	BaseCFrame: CFrame,
	BaseSize: Vector3,
	-- Lean toward the player when selected; 0 at rest, 1 fully leaned.
	Lean: any,
	-- Purchase punch, decaying to 0.
	Punch: any,
	-- Set while the board is affordable, which drives the idle glow.
	Affordable: boolean,
	Light: PointLight?,
	-- True once a distance-culled board has been returned to its rest pose, so
	-- the loop stops writing to it every frame.
	Settled: boolean,
}

local _boards: { BoardView } = {}
local _nearest: BoardView? = nil
-- Forward-declared: the board UI binds to it before it is defined below.
local _requestUpgrade: (view: BoardView) -> ()

-- ── board UI ─────────────────────────────────────────────────────────────────

local function _newText(parent: Instance, order: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = parent
	return label
end

local function _newButton(parent: Instance, order: number, size: number, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, size)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.TextColor3 = color
	button.TextStrokeTransparency = 0.4
	button.Text = ""
	button.Parent = parent
	return button
end

local function _attachBoard(part: BasePart): BoardView?
	local upgradeId = part:GetAttribute("UpgradeId") :: string?
	local def = upgradeId and Bamboo.Upgrades.Get(upgradeId)
	if not def then
		return nil
	end

	-- Mounted flush on the board's front face rather than floating above it, so
	-- the board reads as a real sign the player walks up to, not a HUD element
	-- that happens to hover near one.
	local surface = Instance.new("SurfaceGui")
	surface.Name = "BoardUI"
	-- PlotService builds each board already rotated to face the walk-up, so
	-- Front is the face pointing at the player. If a future authored board
	-- model uses a different local orientation, flip this to Back.
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(360, 240)
	surface.LightInfluence = 0
	surface.AlwaysOnTop = true
	surface.MaxDistance = 60
	surface.Parent = part

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = surface

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 6)
	list.Parent = surface

	-- One light per board, off at rest. Boards are static and few (six per plot),
	-- so a light each is affordable where a per-stalk light would not be.
	local light = Instance.new("PointLight")
	light.Name = "BoardGlow"
	light.Color = Color3.fromRGB(255, 226, 130)
	light.Brightness = 0
	light.Range = BOARD.PurchaseLightRange
	light.Shadows = false
	light.Parent = part

	local view: BoardView = {
		Part = part,
		UpgradeId = def.id,
		TitleLabel = _newText(surface, 1, 40, Color3.fromRGB(255, 255, 255)),
		StatLabel = _newText(surface, 2, 30, Color3.fromRGB(196, 232, 190)),
		CostButton = _newButton(surface, 3, 54, Color3.fromRGB(255, 226, 130)),
		PromptLabel = _newText(surface, 4, 24, Color3.fromRGB(200, 200, 210)),
		BaseCFrame = part.CFrame,
		BaseSize = part.Size,
		Lean = Spring.new(0, BOARD.SelectSmoothTime),
		Punch = Spring.new(0, BOARD.SelectSmoothTime),
		Affordable = false,
		Light = light,
		Settled = false,
	}
	view.TitleLabel.Text = def.name

	-- A real button, not just clickable text: filled background and rounded
	-- corners so it reads as "press me" even before the player is close enough
	-- to read the cost on it.
	view.CostButton.AutoButtonColor = false
	view.CostButton.BackgroundTransparency = 0
	view.CostButton.BackgroundColor3 = Color3.fromRGB(58, 46, 30)
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = view.CostButton
	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(255, 226, 130)
	buttonStroke.Transparency = 0.3
	buttonStroke.Thickness = 2
	buttonStroke.Parent = view.CostButton

	Ripple.Bind(view.CostButton, { Color = Color3.fromRGB(255, 240, 190) })
	view.CostButton.Activated:Connect(function()
		_requestUpgrade(view)
	end)

	return view
end

-- What each upgrade's stat is measured in, for the board's level line.
local STAT_FORMAT: { [string]: string } = {
	SwingSpeed = "%.2fs swing",
	MultiHit = "%d targets",
	Yield = "%d per stalk",
	GrowthSpeed = "%.0fs regrow",
	ProcessingSpeed = "%.2f bamboo/s",
	Density = "%d in field",
}

-- Formats the stat line for one upgrade at its current level.
local function _statText(upgradeId: string, level: number): string
	local value = Bamboo.Value.StatAtLevel(upgradeId, level)
	local format = STAT_FORMAT[upgradeId] or "%d"
	return string.format("Level %d  •  " .. format, level, value)
end

local function _refreshBoards()
	local replica = Replica.Player
	local data = replica and replica.Data
	if not data then
		return
	end

	local money = data.Money or 0

	for _, view in _boards do
		local def = Bamboo.Upgrades.Get(view.UpgradeId)
		local level = data[def.dataKey] or 0

		view.StatLabel.Text = _statText(view.UpgradeId, level)

		if level >= def.maxLevel then
			view.CostButton.Text = "MAXED"
			view.CostButton.TextColor3 = Color3.fromRGB(180, 200, 255)
			view.PromptLabel.Text = ""
			-- A maxed board has nothing to offer, so it stops glowing.
			view.Affordable = false
			continue
		end

		local cost = Bamboo.Value.UpgradeCost(view.UpgradeId, level)
		view.CostButton.Text = "UPGRADE — $" .. FormatUtil.Number(cost)
		-- Drives the idle glow: only boards the player can actually afford invite
		-- attention, so six boards never all shout at once.
		view.Affordable = money >= cost
		view.CostButton.TextColor3 = if money >= cost
			then Color3.fromRGB(150, 255, 160)
			else Color3.fromRGB(255, 140, 140)
		view.CostButton.Active = view == _nearest
		view.PromptLabel.Text = if view == _nearest then def.effectText .. "  •  [E]" else def.effectText
	end
end

-- ── proximity ────────────────────────────────────────────────────────────────

local function _updateNearest()
	local character = LOCAL_PLAYER.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local previous = _nearest
	_nearest = nil

	if root then
		local bestDistance = PROXIMITY_STUDS
		for _, view in _boards do
			local distance = (view.Part.Position - root.Position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
				_nearest = view
			end
		end
	end

	if _nearest ~= previous then
		_refreshBoards()
	end
end

-- ── board feel ───────────────────────────────────────────────────────────────

-- One shared loop for every board on every plot. Binding per board would mean up
-- to 72 frame connections in a full twelve-plot server just for an idle glow.
--
-- Even with one loop, 72 boards x (spring + CFrame + Size + light) every frame is
-- real work on a phone for something the player cannot see, so boards are culled
-- by distance and skipped entirely once they have settled back to rest.
local function _updateBoardFeel(dt: number)
	if not FeelConfig.Enabled.BoardFeel then
		return
	end

	local camera = workspace.CurrentCamera
	local observer = if camera then camera.CFrame.Position else nil
	local pulse = (math.sin(os.clock() * math.pi * 2 / BOARD.IdlePulseSeconds) + 1) * 0.5

	for _, view in _boards do
		local part = view.Part
		if not part.Parent then
			continue
		end

		local selected = view == _nearest

		if observer and not selected then
			local offset = part.Position - observer
			local distanceSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
			if distanceSq > BOARD_VISIBLE_SQ then
				-- Out of sight. Settle it once and stop paying for it: another
				-- player's plot across the map must not cost this client frames.
				if view.Settled ~= true then
					view.Settled = true
					view.Lean:Reset(0)
					view.Punch:Reset(0)
					part.CFrame = view.BaseCFrame
					part.Size = view.BaseSize
					if view.Light then
						view.Light.Brightness = 0
					end
				end
				continue
			end
		end
		view.Settled = false
		view.Lean.Target = if selected then 1 else 0
		local lean = view.Lean:Update(dt)
		local punch = view.Punch:Update(dt)

		-- Lean is toward the player, which for a board angled into the plot means
		-- tipping back about its own local X and lifting slightly.
		local offset = CFrame.new(0, BOARD.SelectRaiseStuds * lean, 0)
			* CFrame.Angles(-BOARD.SelectLeanRadians * lean, 0, 0)
			-- The purchase punch shares the lean axis so the two compose instead
			-- of fighting for the board's orientation.
			* CFrame.Angles(BOARD.PurchaseShakeRadians * punch, 0, 0)
		part.CFrame = view.BaseCFrame * offset
		part.Size = view.BaseSize * (1 + (BOARD.PurchasePunchScale - 1) * math.max(punch, 0))

		local light = view.Light
		if light then
			-- Idle glow only for affordable boards, stronger for the one the
			-- player is standing at, plus whatever the purchase punch adds.
			local idle = if view.Affordable
				then (if selected then BOARD.NearestGlow else BOARD.AffordableGlow) * (0.6 + pulse * 0.4)
				else 0
			light.Brightness = idle + BOARD.PurchaseLightBrightness * math.max(punch, 0)
		end
	end
end

-- Physical answer to a purchase. Success punches the board and throws a burst;
-- a rejection shudders it the other way, so "I can't afford this" is something
-- the world says rather than only a red number.
local function _onUpgradeResult(payload: any)
	_refreshBoards()
	if not FeelConfig.Enabled.BoardFeel then
		return
	end

	local upgradeId = payload.upgradeId :: string
	for _, view in _boards do
		if view.UpgradeId ~= upgradeId then
			continue
		end

		if payload.ok then
			view.Punch:Impulse(1)
			FeelBurst.Emit(view.Part.Position + Vector3.new(0, view.BaseSize.Y * 0.5, 0), {
				Color = Color3.fromRGB(255, 226, 130),
				Count = 16,
				Size = 0.4,
				Speed = NumberRange.new(8, 16),
				Lifetime = NumberRange.new(0.25, 0.5),
				Gravity = -12,
				LightEmission = 1,
			})
		else
			-- Negative impulse: the board rocks the opposite way, which reads as a
			-- refusal rather than a weaker success.
			view.Punch:Impulse(-BOARD.RejectShakeRadians / BOARD.PurchaseShakeRadians)
		end
		break
	end
end

-- Single path for both input routes, so the prompt and the button can never
-- disagree about which board is buyable.
function _requestUpgrade(view: BoardView)
	if view ~= _nearest then
		return
	end
	Relay.Bamboo.BuyUpgrade.send({ upgradeId = view.UpgradeId })
end

local function _onBuyAction(_actionName: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local view = _nearest
	if not view then
		return Enum.ContextActionResult.Pass
	end
	Ripple.Play(view.CostButton, nil, { Color = Color3.fromRGB(255, 240, 190) })
	_requestUpgrade(view)
	return Enum.ContextActionResult.Sink
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function UpgradeBoardController:Start(_fw: any)
	local function bind(instance: Instance)
		if not instance:IsA("BasePart") then
			return
		end
		local view = _attachBoard(instance)
		if view then
			table.insert(_boards, view)
			_refreshBoards()
		end
	end

	for _, instance in CollectionService:GetTagged(BOARD_TAG) do
		bind(instance)
	end
	CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(bind)
	CollectionService:GetInstanceRemovedSignal(BOARD_TAG):Connect(function(instance: Instance)
		for index, view in _boards do
			if view.Part == instance then
				-- An untagged board is not necessarily a destroyed one, so the
				-- light this controller added has to be taken back explicitly.
				if view.Light then
					view.Light:Destroy()
					view.Light = nil
				end
				if view == _nearest then
					_nearest = nil
				end
				table.remove(_boards, index)
				break
			end
		end
	end)

	Replica:WaitForData("Player"):andThen(function(replica: any)
		_refreshBoards()
		for _, upgradeId in Bamboo.Upgrades.Order do
			replica:ListenToChange({ Bamboo.Upgrades.Get(upgradeId).dataKey }, _refreshBoards)
		end
		replica:ListenToChange({ "Money" }, _refreshBoards)
	end)

	Relay.Bamboo.UpgradeResult.listen(_onUpgradeResult)

	ContextActionService:BindAction(BUY_ACTION, _onBuyAction, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(BUY_ACTION, "Upgrade")

	local accumulator = 0
	RunService:BindToRenderStep(REFRESH_BIND, Enum.RenderPriority.Last.Value, function(dt: number)
		accumulator += dt
		if accumulator >= 0.2 then
			accumulator = 0
			-- Proximity only needs checking a few times a second; the springs
			-- below still run every frame so the lean stays smooth.
			_updateNearest()
		end
	end)

	RunService:BindToRenderStep(FEEL_BIND, Enum.RenderPriority.Last.Value - 1, _updateBoardFeel)
end

return UpgradeBoardController
