--!strict
-- Target validation and selection strategies for Brain decision trees.

local Targeting = {}

export type Options = {
	Origin: Vector3?,
	MaxDistance: number?,
	Ignore: Model?,
	IsValid: ((target: Model) -> boolean)?,
	GetThreat: ((target: Model) -> number)?,
}

local function _rootPosition(target: Model): Vector3?
	local root = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

function Targeting.IsValid(target: Model, options: Options?): boolean
	if not target:IsA("Model") then
		return false
	end
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false
	end
	local config = options or {}
	if config.Ignore == target or config.IsValid and not config.IsValid(target) then
		return false
	end
	if config.Origin and config.MaxDistance then
		local position = _rootPosition(target)
		if not position or (position - config.Origin).Magnitude > config.MaxDistance then
			return false
		end
	end
	return true
end

function Targeting.Select(candidates: { Model }, mode: string, options: Options?): Model?
	local config = options or {}
	local valid = {}
	for _, candidate in candidates do
		if Targeting.IsValid(candidate, config) then
			table.insert(valid, candidate)
		end
	end
	if #valid == 0 then
		return nil
	end
	if mode == "Random" then
		return valid[math.random(1, #valid)]
	end

	local selected: Model?
	local selectedScore = if mode == "LowestHealth" then math.huge else -math.huge
	for _, candidate in valid do
		local score: number
		if mode == "LowestHealth" then
			local humanoid = candidate:FindFirstChildOfClass("Humanoid")
			score = humanoid and humanoid.Health or math.huge
		elseif mode == "HighestThreat" then
			score = config.GetThreat and config.GetThreat(candidate) or 0
		else
			local position = _rootPosition(candidate)
			score = if position and config.Origin then -(position - config.Origin).Magnitude else 0
		end
		if score > selectedScore or not selected then
			selected = candidate
			selectedScore = score
		end
	end
	return selected
end

return Targeting
