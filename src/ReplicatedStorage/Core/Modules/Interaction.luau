--!strict
-- Validated ProximityPrompt interaction template.

local Signal = require(script.Parent:WaitForChild("Signal"))

local Interaction = {}
Interaction.__index = Interaction

export type Config = {
	ActionText: string?,
	ObjectText: string?,
	HoldDuration: number?,
	MaxActivationDistance: number?,
	RequiresLineOfSight: boolean?,
	KeyboardKeyCode: Enum.KeyCode?,
	CanInteract: ((player: Player) -> boolean)?,
	OnInteract: ((player: Player) -> ())?,
}

export type InteractionType = {
	Triggered: any,
	Prompt: ProximityPrompt,
	SetEnabled: (self: InteractionType, enabled: boolean) -> (),
	IsEnabled: (self: InteractionType) -> boolean,
	Destroy: (self: InteractionType) -> (),
}

type InteractionImpl = InteractionType & {
	_config: Config,
	_connection: RBXScriptConnection,
	_destroyed: boolean,
}

function Interaction.new(parent: Instance, config: Config?): InteractionType
	local options = config or {}
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = options.ActionText or "Interact"
	prompt.ObjectText = options.ObjectText or parent.Name
	prompt.HoldDuration = options.HoldDuration or 0
	prompt.MaxActivationDistance = options.MaxActivationDistance or 10
	prompt.RequiresLineOfSight = options.RequiresLineOfSight ~= false
	prompt.KeyboardKeyCode = options.KeyboardKeyCode or Enum.KeyCode.E
	prompt.Parent = parent

	local interaction = setmetatable({
		_config = options,
		Prompt = prompt,
		_destroyed = false,
		Triggered = Signal.new(),
	}, Interaction) :: InteractionImpl
	interaction._connection = prompt.Triggered:Connect(function(player)
		if interaction._destroyed then
			return
		end
		if options.CanInteract and not options.CanInteract(player) then
			return
		end
		interaction.Triggered:Fire(player)
		if options.OnInteract then
			options.OnInteract(player)
		end
	end)
	return interaction
end

function Interaction:SetEnabled(enabled: boolean)
	if not self._destroyed then
		self.Prompt.Enabled = enabled
	end
end

function Interaction:IsEnabled(): boolean
	return not self._destroyed and self.Prompt.Enabled
end

function Interaction:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._connection:Disconnect()
	self.Triggered:Destroy()
	self.Prompt:Destroy()
end

return Interaction
