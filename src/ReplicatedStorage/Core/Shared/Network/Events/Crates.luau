--!strict

local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "Crates"
local function b(key: string): string
	return NS .. "_" .. key
end

local function isShortString(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= 48
end

return {
	-- Client → server: "open this crate N times". The client never says what it
	-- won; the server rolls, charges, and grants.
	OpenCrate = Channel({
		bridge = b("OpenCrate"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 8,
		value = {
			crateId = isShortString,
			amount = function(v)
				return type(v) == "number" and v == math.floor(v) and v >= 1 and v <= 4
			end,
		},
	}),

	-- Server → owner: what the crate actually produced. `results` is a list of
	-- { sickleId, tier, isNew }, one per crate opened.
	CrateResult = Channel({
		bridge = b("CrateResult"),
		kind = "fire",
		direction = "s2c",
		value = {
			crateId = isShortString,
			results = function(v)
				return type(v) == "table" and #v >= 1
			end,
			spent = function(v)
				return type(v) == "number" and v >= 0
			end,
			-- Luck the server actually rolled with, so the client can show it.
			luck = function(v)
				return type(v) == "number" and v >= 0
			end,
		},
	}),

	-- Server → owner: the open was refused (not enough money, unknown crate).
	CrateRejected = Channel({
		bridge = b("CrateRejected"),
		kind = "fire",
		direction = "s2c",
		value = {
			crateId = isShortString,
			reason = isShortString,
		},
	}),

	-- Client → server: equip a sickle the player owns.
	EquipSickle = Channel({
		bridge = b("EquipSickle"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 10,
		value = {
			sickleId = isShortString,
		},
	}),

	-- Server → all clients: someone pulled something rare enough to announce.
	RareUnbox = Channel({
		bridge = b("RareUnbox"),
		kind = "fire",
		direction = "s2all",
		value = {
			playerName = isShortString,
			sickleId = isShortString,
			tier = isShortString,
		},
	}),
}
