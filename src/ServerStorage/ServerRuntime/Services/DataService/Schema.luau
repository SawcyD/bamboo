--!strict

export type PlayerData = {
	_version: number,
	_migrations: { string },
	Settings: { [string]: any },

	Money: number,
	-- Raw bamboo stored at the farm, waiting to be carried to the processor.
	-- Effectively unlimited capacity — harvesting never overflows it.
	BambooStock: number,
	-- Raw bamboo physically carried by the player right now, between the
	-- stockpile and the processor. No capacity limit.
	CarriedBamboo: number,
	-- Raw bamboo deposited into the processor, awaiting a batch.
	ProcessorInput: number,
	-- Money earned from sold Straw, waiting to be collected at the Cash
	-- Collector before it becomes spendable Money.
	PendingEarnings: number,
	SwingSpeedLevel: number,
	MultiHitLevel: number,
	YieldLevel: number,
	GrowthSpeedLevel: number,
	ProcessingSpeedLevel: number,
	DensityLevel: number,
	LifetimeBambooCut: number,
	LifetimeBambooCollected: number,
	HighestCombo: number,

	-- Sickle id → how many the player owns.
	OwnedSickles: { [string]: number },
	EquippedSickle: string,
	CratesOpened: number,

	-- Total luck applied to crate rolls, recomputed server-side. Replicated so
	-- the LuckBoost chip and the odds grid can read it directly.
	Luck: number,
	-- An active timed boost: how much luck it grants and when it ends
	-- (os.time seconds). Expired boosts are cleared on the next recompute.
	LuckBoost: number,
	LuckBoostExpiresAt: number,
}

local Schema = {}

Schema.DEFAULT_VERSION = 10

Schema.defaultData = {

	_version = Schema.DEFAULT_VERSION,
	_migrations = {},

	-- player preferences (audio volumes, keybinds...); managed by SettingsService
	Settings = {},

	-- Phase 1 farm progression
	Money = 0,
	BambooStock = 0,
	CarriedBamboo = 0,
	ProcessorInput = 0,
	PendingEarnings = 0,
	SwingSpeedLevel = 0,
	MultiHitLevel = 0,
	YieldLevel = 0,
	GrowthSpeedLevel = 0,
	ProcessingSpeedLevel = 0,
	DensityLevel = 0,
	LifetimeBambooCut = 0,
	LifetimeBambooCollected = 0,
	HighestCombo = 0,

	-- Crates and sickles
	OwnedSickles = { starter_sickle = 1 },
	EquippedSickle = "starter_sickle",
	CratesOpened = 0,

	Luck = 0,
	LuckBoost = 0,
	LuckBoostExpiresAt = 0,
} :: PlayerData

-- Top-level keys that are saved but NEVER replicated to the client
-- (purchase receipts, moderation flags, server-only caches...).
-- Keys starting with "_" are always private.
Schema.PrivateKeys = {
	-- "PurchaseHistory",
} :: { string }

return Schema
