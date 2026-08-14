--!strict
-- Shapes used across the Bamboo domain. No player state lives here.

export type Stage = number

export type RarityDefinition = {
	id: string,
	name: string,
	chance: number, -- percent; the roll order must total 100
	rewardMultiplier: number,
	health: number,
	heightScale: number,
	thicknessScale: number,
	color: Color3,
	-- Feel weight: scales particles, camera shake, and break sound choice.
	impactWeight: number,
}

export type UpgradeDefinition = {
	id: string,
	name: string,
	dataKey: string,
	baseCost: number,
	costGrowth: number,
	maxLevel: number,
	-- One-line effect text for the upgrade board.
	effectText: string,
}

-- One stalk's rolled look. Instances of this belong to the world, not the domain.
export type StalkVisual = {
	rarity: string,
	heightScale: number,
	thicknessScale: number,
	tiltDegrees: number,
	tiltAngle: number,
	leafCount: number,
	color: Color3,
}

-- A player's upgrade levels, as the value formulas consume them.
export type UpgradeLevels = {
	SwingSpeedLevel: number,
	MultiHitLevel: number,
	YieldLevel: number,
}

return {}
