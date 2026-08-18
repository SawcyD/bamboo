--!strict
-- Field layout, planting, and the growth-stage rule table.
--
-- Planting is clustered rather than gridded: bamboo grows in clumps with
-- walkable channels between them, so a player sweeping through the field runs
-- one group into the next instead of crossing empty ground between evenly
-- spaced stalks.

local Field = {}

-- ── stock and regrowth ───────────────────────────────────────────────────────

-- Base field. Sized so the plot reads as a bamboo forest from the first second
-- — full coverage, thickets to sweep, lanes to run — rather than as scattered
-- stalks. Density then thickens it further rather than making it playable.
Field.MaxStalks = 180
Field.StartingStalks = 180
Field.RegrowSeconds = 40
-- A cut stalk reseeds as a Shoot right away, becomes Young after ShootSeconds,
-- and is only cuttable again once RegrowSeconds have passed.
Field.ShootSeconds = 14

-- ── planting ─────────────────────────────────────────────────────────────────

-- Bamboo fills the whole field rather than sitting in isolated patches: this is
-- a forest, not a set of islands. Density varies organically across the plot so
-- there are thickets and thinner lanes to walk, but there is bamboo everywhere.

-- Hard floor on how close two stalks may sit, whatever the density. Below this
-- they visually merge into one trunk.
Field.MinSeparationStuds = 2.1

-- How far local density is allowed to swing from the average, 0-1. This is what
-- makes thickets and lanes instead of an even scatter.
Field.DensityVariation = 0.55
-- Size of the density blobs, in studs. Roughly the width of one thicket.
Field.DensityFeatureStuds = 100

-- Fraction of the field's half-width stalks may reach, so nothing plants right
-- on the boundary.
Field.UsableExtent = 0.94

-- Dart-throwing gives up on a point after this many misses. Higher fills more
-- completely; this is enough to place a full field without a visible hole.
local PLACEMENT_ATTEMPTS = 30
-- Fraction of ideal packing random placement reliably reaches. Below the ~0.7
-- theoretical ceiling so the last few stalks still find room.
local PACKING_EFFICIENCY = 0.62

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

-- Local density multiplier at a point: >1 where the forest thickens, <1 in the
-- lanes between. Smooth noise, so thickets are contiguous rather than speckled.
local function _densityAt(x: number, z: number, seed: number): number
	local scale = 1 / Field.DensityFeatureStuds
	-- math.noise returns roughly -0.5..0.5.
	local n = math.noise(x * scale, z * scale, seed)
	return 1 + math.clamp(n * 2, -1, 1) * Field.DensityVariation
end

-- Spatial hash so the separation check stays O(1) per candidate rather than
-- scanning every placed stalk. A full field is a few hundred points.
local function _newGrid(cell: number)
	return { cell = cell, buckets = {} :: { [string]: { Vector3 } } }
end

local function _bucketKey(grid, x: number, z: number): string
	return string.format("%d:%d", math.floor(x / grid.cell), math.floor(z / grid.cell))
end

local function _insert(grid, point: Vector3)
	local key = _bucketKey(grid, point.X, point.Z)
	local bucket = grid.buckets[key]
	if not bucket then
		bucket = {}
		grid.buckets[key] = bucket
	end
	table.insert(bucket, point)
end

-- True when nothing already placed sits within `radius` of the candidate.
local function _isClear(grid, candidate: Vector3, radius: number): boolean
	local radiusSq = radius * radius
	local cx = math.floor(candidate.X / grid.cell)
	local cz = math.floor(candidate.Z / grid.cell)

	for dx = -1, 1 do
		for dz = -1, 1 do
			local bucket = grid.buckets[string.format("%d:%d", cx + dx, cz + dz)]
			if bucket then
				for _, point in bucket do
					local ox = point.X - candidate.X
					local oz = point.Z - candidate.Z
					if ox * ox + oz * oz < radiusSq then
						return false
					end
				end
			end
		end
	end
	return true
end

-- Reorders points so that *any* prefix still covers the whole field.
--
-- This matters because plots pre-build slots for a fully upgraded forest and
-- then plant only the first N. Without it, a low-Density player would get every
-- stalk bunched wherever generation happened to start.
local function _spreadOrder(points: { Vector3 }): { Vector3 }
	local remaining = table.clone(points)
	local ordered: { Vector3 } = {}
	if #remaining == 0 then
		return ordered
	end

	-- Start at the point closest to the middle, so a tiny field is centred.
	local bestIndex, bestDistSq = 1, math.huge
	for index, point in remaining do
		local distSq = point.X * point.X + point.Z * point.Z
		if distSq < bestDistSq then
			bestDistSq, bestIndex = distSq, index
		end
	end
	table.insert(ordered, table.remove(remaining, bestIndex) :: Vector3)

	-- Then repeatedly take whichever remaining point is farthest from everything
	-- already taken (farthest-point traversal).
	local nearest: { number } = {}
	for index, point in remaining do
		local ox = point.X - ordered[1].X
		local oz = point.Z - ordered[1].Z
		nearest[index] = ox * ox + oz * oz
	end

	while #remaining > 0 do
		local pickIndex, pickDistSq = 1, -1
		for index = 1, #remaining do
			if nearest[index] > pickDistSq then
				pickDistSq, pickIndex = nearest[index], index
			end
		end

		local picked = remaining[pickIndex]
		table.insert(ordered, picked)
		table.remove(remaining, pickIndex)
		table.remove(nearest, pickIndex)

		for index = 1, #remaining do
			local ox = remaining[index].X - picked.X
			local oz = remaining[index].Z - picked.Z
			local distSq = ox * ox + oz * oz
			if distSq < nearest[index] then
				nearest[index] = distSq
			end
		end
	end

	return ordered
end

--[[
	Plants a field: forest offsets in the plot's local space, one per stalk.

	Stalks are spread across the entire field with organic thick and thin areas,
	then ordered so any prefix still covers the whole plot — which is what lets
	Density thicken the forest evenly instead of growing it out from one corner.

	Fully deterministic for a given `rng`, so a plot seeded from its index lays
	out the same way on every server.

	@param count number How many stalks to plant.
	@param halfExtent number Half the field's width in studs; nothing plants beyond it.
	@param rng Random Seeded stream, so the layout is reproducible.
	@return { Vector3 } Local offsets, one per stalk, in planting order.
]]
function Field.BuildSlots(count: number, halfExtent: number, rng: Random): { Vector3 }
	if count <= 0 then
		return {}
	end

	local usable = halfExtent * Field.UsableExtent
	local area = (usable * 2) ^ 2
	-- Separation that actually fits `count` stalks. Random dart-throwing tops out
	-- near 70% of ideal packing, so the separation is derived from that limit
	-- rather than from a perfect grid — with headroom, or the tail of the field
	-- never places and the forest comes out thin.
	local target = math.max(math.sqrt(PACKING_EFFICIENCY * area / count), Field.MinSeparationStuds)

	-- One noise seed per field, so two plots do not share a thicket pattern.
	local noiseSeed = rng:NextNumber(0, 1000)
	local grid = _newGrid(math.max(target, Field.MinSeparationStuds))
	local points: { Vector3 } = {}

	local attempts = 0
	local maxAttempts = count * PLACEMENT_ATTEMPTS
	while #points < count and attempts < maxAttempts do
		attempts += 1

		local x = rng:NextNumber(-usable, usable)
		local z = rng:NextNumber(-usable, usable)
		-- Dense areas want a *smaller* separation, hence the divide.
		local separation = math.max(target / _densityAt(x, z, noiseSeed), Field.MinSeparationStuds)

		local candidate = Vector3.new(x, 0, z)
		if _isClear(grid, candidate, separation) then
			_insert(grid, candidate)
			table.insert(points, candidate)
		end
	end

	return _spreadOrder(points)
end

return Field
