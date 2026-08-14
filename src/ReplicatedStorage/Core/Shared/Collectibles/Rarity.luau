--!strict

local Rarity = {
	Common = { rank = 1, multiplier = 1, color = Color3.fromRGB(190, 190, 190) },
	Uncommon = { rank = 2, multiplier = 1.5, color = Color3.fromRGB(90, 210, 110) },
	Rare = { rank = 3, multiplier = 2.5, color = Color3.fromRGB(80, 150, 255) },
	Epic = { rank = 4, multiplier = 5, color = Color3.fromRGB(180, 90, 255) },
	Legendary = { rank = 5, multiplier = 10, color = Color3.fromRGB(255, 185, 55) },
}

function Rarity.Get(name: string): any
	return Rarity[name]
end

return Rarity
