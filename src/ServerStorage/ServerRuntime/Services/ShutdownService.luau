--!strict
--[[
	ShutdownService: soft shutdown for game updates.

	Without this, shipping an update hard-kicks every live server. With it:
	when a server shuts down, players are teleported to a reserved server of the
	same place; that temporary server immediately teleports them back into a
	fresh (updated) public server. Players see a hop, not a disconnect.

	No setup needed — the service detects which role it's running in:
	- Reserved "transit" server: bounce everyone back to a public server.
	- Normal server: on BindToClose, reserve a transit server and send players there.

	Does nothing in Studio.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local ShutdownService = {}

-- reserved servers we create have PrivateServerOwnerId == 0
local _isTransitServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

local function teleportBack(player: Player)
	local ok, err = pcall(function()
		TeleportService:Teleport(game.PlaceId, player)
	end)
	if not ok then
		warn("ShutdownService: return teleport failed for", player.Name, err)
		-- retry once after a beat; player can also rejoin manually
		task.delay(2, function()
			if player.Parent then
				pcall(function()
					TeleportService:Teleport(game.PlaceId, player)
				end)
			end
		end)
	end
end

function ShutdownService:Start(_fw: any)
	if RunService:IsStudio() then
		return
	end

	if _isTransitServer then
		-- we're the temporary bounce server: send everyone straight back
		Players.PlayerAdded:Connect(function(player: Player)
			task.wait(1) -- let the join settle before teleporting again
			teleportBack(player)
		end)
		for _, player in Players:GetPlayers() do
			task.spawn(teleportBack, player)
		end
		return
	end

	game:BindToClose(function()
		local players = Players:GetPlayers()
		if #players == 0 then
			return
		end

		local ok, reservedCode = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)
		if not ok then
			warn("ShutdownService: ReserveServer failed; players will disconnect normally:", reservedCode)
			return
		end

		pcall(function()
			TeleportService:TeleportToPrivateServer(game.PlaceId, reservedCode :: string, players)
		end)

		-- hold the server open while teleports go out (BindToClose allows up to 30s)
		local deadline = os.clock() + 25
		while os.clock() < deadline and #Players:GetPlayers() > 0 do
			task.wait(0.5)
		end
	end)
end

return ShutdownService
