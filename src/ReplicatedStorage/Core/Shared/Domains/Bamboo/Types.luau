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

export type MutationDefinition = {
	id: string,
	-- Display prefix; empty for the unmutated default.
	name: string,
	valueMultiplier: number,
	-- Relative roll weight, not a percentage.
	weight: number,
	-- Appearance. At least two of these differ from plain bamboo for every
	-- mutation, so it is recognisable at speed on a phone.
	color: Color3,
	nodeColor: Color3,
	leafColor: Color3,
	material: Enum.Material,
	glow: number,
	-- Whether finding one is announced to the whole server.
	announce: boolean,
	-- Feel weight for the break, layered on top of the type's impactWeight.
	revealWeight: number,
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
	mutation: string,
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
