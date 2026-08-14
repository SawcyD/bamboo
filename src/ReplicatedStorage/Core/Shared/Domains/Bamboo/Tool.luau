--!strict
-- Starter sickle stats and the rotor geometry it is carried with.
--
-- The sickle owns damage, reach, and base multi-hit. How fast it swings, how
-- many stalks it may hit, and how much each stalk gives are upgrade concerns,
-- so they live in Upgrades/Value instead.

local Tool = {}

Tool.Damage = 1
Tool.BaseSwingTime = 0.8
Tool.Range = 7
Tool.BaseMultiHit = 3

-- The sickle orbits the player like a rotor, so a swing sweeps the full circle.
-- Any value >= 360 disables the directional cone test on client and server.
Tool.SwingArcDegrees = 360

-- Rotor geometry: how far out and how high the blade rides at full speed.
Tool.OrbitRadius = 5.5
Tool.OrbitHeight = 1.6
-- The rotor never stops: away from bamboo it coasts at this fraction of full
-- speed instead of parking, so entering a patch costs no spin-up.
Tool.IdleSpinFraction = 0.3
-- Approximate seconds for the spin spring to reach its target.
Tool.SpinSmoothTime = 0.28

-- Server rejects swings arriving faster than the player's swing time minus this
-- slack, which absorbs normal ping jitter.
Tool.SwingToleranceSeconds = 0.08

--[[
	Whether the swing hits in every direction rather than a cone in front.
	@return boolean True while the tool is configured as a full-circle rotor.
]]
function Tool.SweepsFullCircle(): boolean
	return Tool.SwingArcDegrees >= 360
end

return Tool
