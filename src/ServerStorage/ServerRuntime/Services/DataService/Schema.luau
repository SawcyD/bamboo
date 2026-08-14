--!strict

export type PlayerData = {
	_version: number,
	_migrations: { string },
	Settings: { [string]: any },
}

local Schema = {}

Schema.DEFAULT_VERSION = 1

Schema.defaultData = {

	_version = Schema.DEFAULT_VERSION,
	_migrations = {},

	-- player preferences (audio volumes, keybinds...); managed by SettingsService
	Settings = {},
} :: PlayerData

-- Top-level keys that are saved but NEVER replicated to the client
-- (purchase receipts, moderation flags, server-only caches...).
-- Keys starting with "_" are always private.
Schema.PrivateKeys = {
	-- "PurchaseHistory",
} :: { string }

return Schema
