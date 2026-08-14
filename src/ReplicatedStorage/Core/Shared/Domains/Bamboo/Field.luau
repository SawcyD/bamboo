--!strict
-- Field layout, planting, and the growth-stage rule table.
--
-- Planting is clustered rather than gridded: bamboo grows in clumps with
-- walkable channels between them, so a player sweeping through the field runs
-- one group into the next instead of crossing empty ground between evenly
-- spaced stalks.

local Field = {}

-- ── stock and regrowth ───────────────────────────────────────────────────────

-- Base field. Sized so a fresh player's rotor is almost always in range of
-- something; Density then makes it increasingly ridiculous rather than merely
-- playable.
Field.MaxStalks = 34
Field.StartingStalks = 34
Field.RegrowSeconds = 40
-- A cut stalk reseeds as a Shoot right away, becomes Young after ShootSeconds,
-- and is only cuttable again once RegrowSeconds have passed.
Field.ShootSeconds = 14

-- ── planting ─────────────────────────────────────────────────────────────────

-- Separation the planter aims for between neighbouring stalks. It is a target,
-- not a guarantee: inside a dense clump the sampler settles for the roomiest
-- spot it found rather than failing to plant, so real gaps bottom out around
-- three studs. Well under the sickle's 7-stud reach either way.
Field.MinSeparationStuds = 4.2

-- Stalks per clump. Clumps are filled in order, so buying Density extends the
-- current clump and then starts new ones — the field gains fresh patches to run
-- between rather than one growing blob.
Field.StalksPerClump = 7
-- How far a stalk may sit from its clump centre. Tuned against the sickle's
-- 7-stud reach: at this radius the average stalk has three neighbours in range,
-- which is exactly the starter sickle's multi-hit.
Field.ClumpRadiusStuds = 6.5
-- Clump centres are kept at least this far apart, which is what carves the
-- walkable channels. A clump is ~13 studs across, so this leaves a short gap
-- the rotor barely notices crossing.
Field.ClumpSeparationStuds = 18
-- Fraction of the field's half-width clump centres are allowed to reach, so
-- nothing plants right on the boundary.
Field.UsableExtent = 0.86

-- Rejection sampling gives up after this many tries and takes the best it
-- found, so a dense field can never hang the server.
local PLACEMENT_ATTEMPTS = 24

-- ── growth stages ────────────────────────────────────────────────────────────

Field.Stage = table.freeze({
	Shoot = 1,
	Young = 2,
	Mature = 3,
})

-- Visual scale applied to a stalk at each stage.
Field.StageScale = table.freeze({
	[1] = 0.25,
	[2] = 0.6,
	[3] = 1.0,
})

--[[
	Growth stage a stalk should be showing at a point in its regrowth.
	@param secondsSinceCut number Seconds elapsed since the stalk was cut.
	@return number A Field.Stage value.
]]
function Field.StageAt(secondsSinceCut: number): number
	if secondsSinceCut >= Field.RegrowSeconds then
		return Field.Stage.Mature
	elseif secondsSinceCut >= Field.ShootSeconds then
		return Field.Stage.Young
	end
	return Field.Stage.Shoot
end

-- ── planting ─────────────────────────────────────────────────────────────────

-- Squared distance to the nearest point in a list. Squared throughout so the
-- inner loop never takes a square root.
local function _nearestDistSq(points: { Vector3 }, candidate: Vector3): number
	local best = math.huge
	for _, point in points do
		local dx = point.X - candidate.X
		local dz = point.Z - candidate.Z
		local distSq = dx * dx + dz * dz
		if distSq < best then
			best = distSq
		end
	end
	return best
end

-- Scatters clump centres across the field, keeping them apart by rejection
-- sampling. Falls back to the roomiest candidate found rather than failing, so
-- a very dense field still plants every clump.
local function _placeClumpCentres(count: number, halfExtent: number, rng: Random): { Vector3 }
	local centres: { Vector3 } = {}
	local minSepSq = Field.ClumpSeparationStuds * Field.ClumpSeparationStuds

	for _ = 1, count do
		local best: Vector3? = nil
		local bestDistSq = -1

		for _ = 1, PLACEMENT_ATTEMPTS do
			local candidate =
				Vector3.new(rng:NextNumber(-halfExtent, halfExtent), 0, rng:NextNumber(-halfExtent, halfExtent))
			local distSq = if #centres == 0 then math.huge else _nearestDistSq(centres, candidate)

			if distSq >= minSepSq then
				best = candidate
				break
			end
			if distSq > bestDistSq then
				bestDistSq = distSq
				best = candidate
			end
		end

		if best then
			table.insert(centres, best)
		end
	end

	return centres
end

--[[
	Plants a field: clustered offsets in the plot's local space, one per stalk.

	Fully deterministic for a given `rng`, so a plot seeded from its index lays
	out the same way every server. Callers convert these to world CFrames.

	@param count number How many stalks to plant.
	@param halfExtent number Half the field's width in studs; nothing plants beyond it.
	@param rng Random Seeded stream, so the layout is reproducible.
	@return { Vector3 } Local offsets, one per stalk, in planting order.
]]
function Field.BuildSlots(count: number, halfExtent: number, rng: Random): { Vector3 }
	local slots: { Vector3 } = {}
	if count <= 0 then
		return slots
	end

	local usable = halfExtent * Field.UsableExtent
	local clumpCount = math.max(1, math.round(count / Field.StalksPerClump))
	local centres = _placeClumpCentres(clumpCount, usable, rng)
	if #centres == 0 then
		centres = { Vector3.zero }
	end

	local minSepSq = Field.MinSeparationStuds * Field.MinSeparationStuds

	for index = 1, count do
		-- Clumps are filled in order, not round-robin. Plots pre-build slots for a
		-- fully upgraded field and then plant only a prefix of them, so any prefix
		-- has to be a set of *complete* clumps — round-robin would spread a small
		-- field thinly across every clump and undo the clustering entirely.
		local clumpIndex = math.min(math.floor((index - 1) / Field.StalksPerClump) + 1, #centres)
		local centre = centres[clumpIndex]

		local best: Vector3? = nil
		local bestDistSq = -1

		for _ = 1, PLACEMENT_ATTEMPTS do
			-- sqrt on the radius spreads stalks evenly over the disc instead of
			-- bunching them all at the centre.
			local radius = Field.ClumpRadiusStuds * math.sqrt(rng:NextNumber())
			local angle = rng:NextNumber(0, math.pi * 2)
			local candidate = centre + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

			candidate = Vector3.new(
				math.clamp(candidate.X, -halfExtent, halfExtent),
				0,
				math.clamp(candidate.Z, -halfExtent, halfExtent)
			)

			local distSq = if #slots == 0 then math.huge else _nearestDistSq(slots, candidate)
			if distSq >= minSepSq then
				best = candidate
				break
			end
			if distSq > bestDistSq then
				bestDistSq = distSq
				best = candidate
			end
		end

		if best then
			table.insert(slots, best)
		end
	end

	return slots
end

return Field
