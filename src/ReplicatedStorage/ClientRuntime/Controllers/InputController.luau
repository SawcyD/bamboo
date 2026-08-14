--!strict
--[[
	InputController: named actions over ContextActionService, with rebinding and
	platform detection.

		local Input = ClientRuntime:GetController("InputController")

		Input:BindAction("Dash", function(state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then dash() end
		end, { Enum.KeyCode.Q, Enum.KeyCode.ButtonX })

		Input:SetBinding("Dash", { Enum.KeyCode.E })  -- rebind at runtime (persists
		                                              -- when SettingsService registers "Keybind_Dash")
		Input:GetBinding("Dash")                      -- current inputs
		Input:UnbindAction("Dash")

		Input:GetPlatform()        -- "Keyboard" | "Gamepad" | "Touch"
		Input.PlatformChanged:Connect(function(platform) ... end)
]]

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Relay = Core:GetShared("Network")

local InputController = {}
InputController.PlatformChanged = Relay.Signal.new()

export type Platform = "Keyboard" | "Gamepad" | "Touch"
export type ActionCallback = (state: Enum.UserInputState, inputObject: InputObject) -> ()
type InputCode = Enum.KeyCode | Enum.UserInputType

type ActionEntry = {
	callback: ActionCallback,
	inputs: { InputCode },
	touchButton: boolean,
}

local _actions: { [string]: ActionEntry } = {}
local _platform: Platform = "Keyboard"

-- ── platform detection ────────────────────────────────────────────────────────

local function platformFromInputType(inputType: Enum.UserInputType): Platform?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	if inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	end
	if
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseMovement
	then
		return "Keyboard"
	end
	return nil
end

function InputController:GetPlatform(): Platform
	return _platform
end

-- ── actions ───────────────────────────────────────────────────────────────────

local function bindToCAS(name: string, entry: ActionEntry)
	ContextActionService:BindAction(name, function(_actionName, state, inputObject)
		entry.callback(state, inputObject)
		return Enum.ContextActionResult.Pass
	end, entry.touchButton, table.unpack(entry.inputs :: { any }))
end

--- Binds `callback` to a named action. `opts.touchButton = true` adds the CAS
--- on-screen button for touch players.
function InputController:BindAction(
	name: string,
	callback: ActionCallback,
	inputs: { InputCode },
	opts: { touchButton: boolean? }?
)
	if _actions[name] then
		ContextActionService:UnbindAction(name)
	end
	local entry: ActionEntry = {
		callback = callback,
		inputs = inputs,
		touchButton = (opts and opts.touchButton) == true,
	}
	_actions[name] = entry
	bindToCAS(name, entry)
end

function InputController:UnbindAction(name: string)
	if _actions[name] then
		_actions[name] = nil
		ContextActionService:UnbindAction(name)
	end
end

--- Swaps the inputs for an existing action (rebinding UI). If SettingsController
--- has a registered "Keybind_<name>" setting, the choice persists across sessions.
function InputController:SetBinding(name: string, inputs: { InputCode })
	local entry = _actions[name]
	if not entry then
		warn("InputController.SetBinding: unknown action:", name)
		return
	end
	ContextActionService:UnbindAction(name)
	entry.inputs = inputs
	bindToCAS(name, entry)

	-- persist when the setting is registered (KeyCode names only)
	local names: { string } = {}
	for _, input in inputs do
		table.insert(names, input.Name)
	end
	local ClientRuntime = require(script.Parent.Parent) :: any
	local ok, settings = pcall(function()
		return ClientRuntime:GetController("SettingsController")
	end)
	if ok and settings then
		settings:Set("Keybind_" .. name, names)
	end
end

function InputController:GetBinding(name: string): { InputCode }?
	local entry = _actions[name]
	return entry and entry.inputs or nil
end

-- ── lifecycle ─────────────────────────────────────────────────────────────────

function InputController:Start(_fw: any)
	-- initial platform guess
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		_platform = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		_platform = "Gamepad"
	else
		_platform = "Keyboard"
	end

	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local detected = platformFromInputType(inputType)
		if detected and detected ~= _platform then
			_platform = detected
			InputController.PlatformChanged:Fire(detected)
		end
	end)
end

return InputController
