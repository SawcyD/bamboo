--!strict

export type Tier = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type Condition = "Worn" | "Used" | "Good" | "Pristine"

export type Definition = {
	id: string,
	name: string,
	category: string,
	baseValue: number,
	weight: number,
	tier: Tier,
	modelName: string?,
	outcomeType: string?,
	sets: { string }?,
}

export type Instance = {
	instanceId: string,
	definitionId: string,
	rarity: Tier,
	condition: Condition,
	value: number,
	createdAt: number,
	locked: boolean,
}

export type CollectionEntry = {
	discovered: boolean,
	count: number,
	bestRarity: Tier,
	highestValue: number,
}

return {}
