--!strict

export type PlayerData = {
	_version: number,
	_migrations: { string },
	Settings: { [string]: any },

	Money: number,
	Bag: number,
	SwingSpeedLevel: number,
	MultiHitLevel: number,
	YieldLevel: number,
	StorageLevel: number,
	GrowthSpeedLevel: number,
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

Schema.DEFAULT_VERSION = 6

Schema.defaultData = {

	_version = Schema.DEFAULT_VERSION,
	_migrations = {},

	-- player preferences (audio volumes, keybinds...); managed by SettingsService
	Settings = {},

	-- Phase 1 farm progression
	Money = 0,
	Bag = 0,
	SwingSpeedLevel = 0,
	MultiHitLevel = 0,
	YieldLevel = 0,
	StorageLevel = 0,
	GrowthSpeedLevel = 0,
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
