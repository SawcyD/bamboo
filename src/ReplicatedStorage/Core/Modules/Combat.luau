--!strict
-- Server-oriented combat primitive. Higher-level rules belong to game services.

local Signal = require(script.Parent:WaitForChild("Signal"))

local Combat = {}
Combat.__index = Combat

export type Config = {
	CanDamage: ((source: Model?, target: Model, amount: number, context: any?) -> boolean)?,
	MaxDamage: number?,
}

export type CombatType = {
	Damaged: any,
	Died: any,
	Damage: (self: CombatType, source: Model?, target: Model, amount: number, context: any?) -> boolean,
	Heal: (self: CombatType, target: Model, amount: number) -> boolean,
	SetInvulnerable: (self: CombatType, target: Model, value: boolean) -> (),
	IsInvulnerable: (self: CombatType, target: Model) -> boolean,
	BindHitbox: (self: CombatType, hitbox: any, source: Model?, amount: number, context: any?) -> RBXScriptConnection,
	Destroy: (self: CombatType) -> (),
}

type CombatImpl = CombatType & {
	_config: Config,
	_invulnerable: { [Model]: boolean },
	_destroyed: boolean,
}

local function _humanoid(target: Model): Humanoid?
	return target:FindFirstChildOfClass("Humanoid")
end

function Combat.new(config: Config?): CombatType
	return setmetatable({
		_config = config or {},
		_invulnerable = {},
		_destroyed = false,
		Damaged = Signal.new(),
		Died = Signal.new(),
	}, Combat) :: CombatImpl
end

function Combat:Damage(source: Model?, target: Model, amount: number, context: any?): boolean
	if self._destroyed or amount <= 0 or amount ~= amount or amount == math.huge then
		return false
	end
	local humanoid = _humanoid(target)
	if not humanoid or humanoid.Health <= 0 or self._invulnerable[target] then
		return false
	end
	local damage = math.min(amount, self._config.MaxDamage or amount)
	if self._config.CanDamage and not self._config.CanDamage(source, target, damage, context) then
		return false
	end
	local before = humanoid.Health
	humanoid:TakeDamage(damage)
	local applied = math.max(0, before - humanoid.Health)
	if applied <= 0 then
		return false
	end
	self.Damaged:Fire(source, target, applied, context)
	if humanoid.Health <= 0 then
		self.Died:Fire(source, target, context)
	end
	return true
end

function Combat:Heal(target: Model, amount: number): boolean
	if self._destroyed or amount <= 0 then
		return false
	end
	local humanoid = _humanoid(target)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	return true
end

function Combat:SetInvulnerable(target: Model, value: boolean)
	self._invulnerable[target] = value or nil
end

function Combat:IsInvulnerable(target: Model): boolean
	return self._invulnerable[target] == true
end

function Combat:BindHitbox(hitbox: any, source: Model?, amount: number, context: any?): RBXScriptConnection
	return hitbox.Hit:Connect(function(target: Model)
		self:Damage(source, target, amount, context)
	end)
end

function Combat:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	table.clear(self._invulnerable)
	self.Damaged:Destroy()
	self.Died:Destroy()
end

return Combat
