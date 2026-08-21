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
	-- Client -> server: asks for the current bamboo state after the client
	-- controllers are ready. Bamboo is not replicated as Instances; this compact
	-- snapshot is the only initial visual state a client receives.
	StateRequest = Channel({
		bridge = b("StateRequest"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 2,
	}),

	-- Server -> one client: the initial state (and a complete refresh after a
	-- density change). Positions are deliberately omitted; clients rebuild the
	-- deterministic planting layout from the plot index.
	StateSnapshot = Channel({
		bridge = b("StateSnapshot"),
		kind = "fire",
		direction = "s2c",
		value = {
			plots = function(v)
				return type(v) == "table"
			end,
		},
	}),

	-- Server -> all clients: small state changes only. Growth is represented by a
	-- server timestamp, so clients do not receive a per-stalk update every frame.
	StateDelta = Channel({
		bridge = b("StateDelta"),
		kind = "fire",
		direction = "s2all",
		value = {},
	}),

	-- The client never says what it hit; the server runs the arc query itself.
	--
	-- The fastest honest rate is 1 / (BaseSwingTime / (1 + 25 * 0.08)) = 3.75/s at
	-- Swing Speed 25, so this leaves ~2.1x headroom — narrower than it looks. It
	-- was tripped in practice by a client frame hitch: the rotor banked a hitch's
	-- worth of revolutions and drained them one per frame as a packet burst. The
	-- controller now clamps its timestep so that cannot happen. Anything still
	-- reaching 8/s is not an honest client.
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
			-- Always 0: the stockpile has no capacity, so nothing is ever dropped
			-- from harvesting. Kept in the payload rather than removed, so a
			-- future overflow source (a rare event, an ability) has somewhere to
			-- report through without a channel change.
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

	-- Client → server: "I'm at my stockpile, give me bamboo to carry." The
	-- client never says how much — the server fills remaining carry capacity
	-- from BambooStock itself. No payload: intent only.
	TakeFromStockpile = Channel({
		bridge = b("TakeFromStockpile"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 4,
	}),

	-- Client → server: "I'm at my processor, take what I'm carrying." Moves all
	-- of CarriedBamboo into ProcessorInput; the amount is never client-supplied.
	DepositToProcessor = Channel({
		bridge = b("DepositToProcessor"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 4,
	}),

	-- Client → server: "collect my pending earnings." Proximity to the Cash
	-- Collector is also polled server-side (walking onto the pad is enough),
	-- so this is a redundant, explicit path for an interact prompt/tap.
	CollectEarnings = Channel({
		bridge = b("CollectEarnings"),
		kind = "fire",
		direction = "c2s",
		rateLimit = 4,
	}),

	-- Server → owner: pending earnings were collected into spendable Money, so
	-- the HUD/FX can play the payout beat at the Cash Collector.
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
