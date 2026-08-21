--!strict
-- Presentation and ProximityPrompt for the farm stockpile: BambooStock ->
-- CarriedBamboo, by request only.
--
-- The client never decides the amount taken — it only asks, via the prompt's
-- Triggered event. Carrying has no capacity limit, so a take always empties
-- the whole stockpile. BambooStock and CarriedBamboo are ordinary top-level
-- PlayerData keys, exactly like Money, so this controller reacts to the
-- replica for its live readout; the prompt itself is only a trust signal —
-- StockpileService still validates ownership and distance server-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local FormatUtil = Core:GetUtil("FormatUtil")
local Relay = Core:GetShared("Network")
local Replica = Core:Get("Replica")

local ClientModules = script.Parent.Parent:WaitForChild("Modules")
local FeelBurst = require(ClientModules:WaitForChild("FeelBurst"))

local StockpileController = {}

local LOCAL_PLAYER = Players.LocalPlayer

local _stockpile: BasePart? = nil
local _prompt: ProximityPrompt? = nil
local _statusLabel: TextLabel? = nil
local _lastStock = 0
local _lastCarried = 0

-- ── resolve ──────────────────────────────────────────────────────────────────

local function _updateStatus()
	local label = _statusLabel
	if not label then
		return
	end
	label.Text = if _lastStock <= 0 then "Empty" else string.format("%s bamboo", FormatUtil.Number(_lastStock))

	local prompt = _prompt
	if prompt then
		prompt.Enabled = _lastStock > 0
		prompt.ObjectText = string.format("%s bamboo", FormatUtil.Number(_lastStock))
	end
end

local function _resolveStockpile(): BasePart?
	local existing = _stockpile
	if existing and existing.Parent then
		local plot = existing.Parent
		if plot and plot:GetAttribute("OwnerUserId") == LOCAL_PLAYER.UserId then
			return existing
		end
	end

	_stockpile = nil
	_statusLabel = nil
	_prompt = nil

	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") ~= LOCAL_PLAYER.UserId then
			continue
		end
		local body = plot:FindFirstChild("Stockpile") :: BasePart?
		if not body then
			return nil
		end
		_stockpile = body
		local label = body:FindFirstChild("StockpileLabel")
		_statusLabel = label and (label:FindFirstChild("Status") :: TextLabel?)
		local prompt = body:FindFirstChild("TakePrompt") :: ProximityPrompt?
		if prompt then
			_prompt = prompt
			prompt.Triggered:Connect(function(player: Player)
				if player == LOCAL_PLAYER then
					Relay.Bamboo.TakeFromStockpile.send({})
				end
			end)
		end
		_updateStatus()
		return body
	end
	return nil
end

-- ── replica reactions ────────────────────────────────────────────────────────

local function _onCarriedChanged(carried: number)
	-- A jump in CarriedBamboo means the take succeeded: a small burst at the
	-- pad sells the moment without a bespoke result event.
	local grew = carried > _lastCarried
	_lastCarried = carried

	if grew then
		local body = _stockpile
		if body then
			FeelBurst.Emit(body.Position + Vector3.new(0, body.Size.Y * 0.5 + 1, 0), {
				Color = Color3.fromRGB(112, 172, 84),
				Count = 10,
				Size = 0.35,
				Speed = NumberRange.new(4, 9),
				Lifetime = NumberRange.new(0.2, 0.4),
				Gravity = -6,
			})
		end
	end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function StockpileController:Start(_fw: any)
	Replica:WaitForData("Player"):andThen(function(replica: any)
		_lastStock = replica.Data.BambooStock or 0
		_lastCarried = replica.Data.CarriedBamboo or 0
		_resolveStockpile()
		_updateStatus()

		replica:ListenToChange({ "BambooStock" }, function()
			_lastStock = replica.Data.BambooStock or 0
			_updateStatus()
		end)
		replica:ListenToChange({ "CarriedBamboo" }, function()
			_onCarriedChanged(replica.Data.CarriedBamboo or 0)
		end)
	end)

	-- The stockpile's prompt is bound once resolved above; plots can still be
	-- (re)assigned after the replica lands, so a periodic re-resolve keeps the
	-- prompt connection valid without a dedicated PlotOwnerChanged listener.
	task.spawn(function()
		while true do
			_resolveStockpile()
			task.wait(1)
		end
	end)
end

return StockpileController
