--!strict
-- Shapes for the sickle domain. Definitions describe a *kind* of sickle;
-- ownership of a particular one lives in player data.

export type TierDefinition = {
	id: string,
	name: string,
	-- Relative roll weight inside a crate; crates scale these per crate.
	color: Color3,
	glow: number,
	-- Feel weight for the crate reveal: shake, particles, sound.
	revealWeight: number,
}

export type AbilityDefinition = {
	id: string,
	name: string,
	-- One line for the sickle card. Written for a player, not a designer.
	description: string,
}

export type SickleDefinition = {
	id: string,
	name: string,
	tier: string,
	-- The three stats §17 assigns to the tool. Upgrades stack on top of these.
	damage: number,
	range: number,
	baseMultiHit: number,
	-- Blade look, so the rotor reads differently per sickle.
	bladeColor: Color3,
	trailColor: Color3,
	ability: string?,
	abilityPotency: number?,
}

export type CrateDefinition = {
	id: string,
	name: string,
	cost: number,
	-- Sickle id → roll weight. Weights are relative within one crate.
	contents: { [string]: number },
	color: Color3,
}

-- A player's owned sickles: definition id → how many they have.
export type Inventory = { [string]: number }

-- The stats a swing actually resolves with, after sickle and upgrades.
export type EffectiveStats = {
	damage: number,
	range: number,
	multiHit: number,
	swingTime: number,
	ability: string?,
	abilityPotency: number,
}

return {}
