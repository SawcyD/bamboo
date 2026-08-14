--!strict

local Channel = require(script.Parent.Parent:WaitForChild("Channel"))

local NS = "Bamboo"
local function b(key: string): string
	return NS .. "_" .. key
end

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isUnitish(v: any): boolean
	return typeof(v) == "Vector3" and v.Magnitude > 0.01 and v.Magnitude < 100
end

return {
	-- Client → server: "I swung here, facing this way."
	-- The client never says what it hit; the server runs the arc query itself.
	-- Rate limit is well above the fastest reachable swing rate (~2/s at level 25)
	-- so honest clients never trip it, but a spammer is still capped.
	Swing = Channel({
		bridge = b("Swing"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 8,
		value = {
			origin = function(v)
				return typeof(v) == "Vector3" and isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)
			end,
			look = isUnitish,
		},
	}),

	-- Server → owner: the resolved outcome of one swing. Drives all cutting feel.
	-- `hits` is a list of { id, position, rarity, broke, health }.
	SwingResult = Channel({
		bridge = b("SwingResult"),
		kind = "fire",
		direction = "s2c",
		value = {
			hits = function(v)
				return type(v) == "table"
			end,
			breaks = function(v)
				return type(v) == "number" and v >= 0
			end,
			combo = function(v)
				return type(v) == "number" and v >= 0
			end,
			collected = function(v)
				return type(v) == "number" and v >= 0
			end,
			-- Bamboo the bag couldn't hold, which landed on the ground instead.
			dropped = function(v)
				return type(v) == "number" and v >= 0
			end,
			-- Extra stalks felled by the sickle's Chain Cut ability.
			chained = function(v)
				return type(v) == "number" and v >= 0
			end,
		},
	}),

	-- Server → owner: ground drops were vacuumed up. Batched per pickup tick so
	-- running through a pile of drops is one packet, not one per drop.
	DropsCollected = Channel({
		bridge = b("DropsCollected"),
		kind = "fire",
		direction = "s2c",
		value = {
			drops = function(v)
				return type(v) == "table"
			end,
			total = function(v)
				return type(v) == "number" and v > 0
			end,
		},
	}),

	-- Server → owner: the authoritative combo changed.
	--
	-- Sent only when the number actually moves (a break, a milestone, or the
	-- streak ending) — never per frame. The client counts the window down itself
	-- from `windowSeconds` rather than being told the remaining time each tick.
	ComboState = Channel({
		bridge = b("ComboState"),
		kind = "fire",
		direction = "s2c",
		value = {
			combo = function(v)
				return type(v) == "number" and v >= 0
			end,
			-- Full length of the grace period, restarted by this packet.
			windowSeconds = function(v)
				return type(v) == "number" and v >= 0
			end,
			-- The milestone just crossed, or 0 when none was.
			milestone = function(v)
				return type(v) == "number" and v >= 0
			end,
		},
	}),

	-- Client → server: request to buy one level of an upgrade.
	BuyUpgrade = Channel({
		bridge = b("BuyUpgrade"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 6,
		value = {
			upgradeId = function(v)
				return type(v) == "string" and #v > 0 and #v <= 24
			end,
		},
	}),

	-- Server → owner: the result of a sell, so the HUD can play the payout beat.
	Sold = Channel({
		bridge = b("Sold"),
		kind = "fire",
		direction = "s2c",
		value = {
			amount = function(v)
				return type(v) == "number" and v >= 0
			end,
			money = function(v)
				return type(v) == "number" and v >= 0
			end,
		},
	}),

	-- Server → owner: an upgrade purchase succeeded or was rejected.
	UpgradeResult = Channel({
		bridge = b("UpgradeResult"),
		kind = "fire",
		direction = "s2c",
		value = {
			upgradeId = function(v)
				return type(v) == "string"
			end,
			ok = function(v)
				return type(v) == "boolean"
			end,
			level = function(v)
				return type(v) == "number" and v >= 0
			end,
		},
	}),
}
