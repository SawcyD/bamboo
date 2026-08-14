--!strict
--[[
	MonetizationService: developer products + gamepasses done safely.

	Products (consumables — coins packs, boosts):

		local Monetization = Framework:GetService("MonetizationService")
		Monetization.RegisterProduct(123456789, function(player, receiptInfo)
			DataService.Increment(player, "Coins", 1000)
			return true -- granted; return false/error to retry later
		end)

	Gamepasses (permanent — VIP, x2 coins):

		Monetization.RegisterGamepass(987654321, function(player)
			-- runs on join when owned, and immediately after a live purchase
		end)
		Monetization.PlayerOwnsPass(player, 987654321) -- cached

	Safety properties:
	- Receipts are idempotent: granted PurchaseIds are stored in the profile
	  (private key, never replicated) so a re-fired receipt is acknowledged
	  without double-granting.
	- Receipts wait for the profile: if data isn't loaded yet, Roblox retries.
	- Handler errors → NotProcessedYet (Roblox retries; the player isn't charged
	  for nothing).

	Note: only one script may set MarketplaceService.ProcessReceipt per game —
	this service owns it; route all products through RegisterProduct.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local MonetizationService = {}
local Framework: any

local MAX_STORED_RECEIPTS = 100

type ProductHandler = (player: Player, receiptInfo: any) -> boolean?
type GamepassHandler = (player: Player) -> ()

local _products: { [number]: ProductHandler } = {}
local _gamepasses: { [number]: GamepassHandler? } = {}
local _ownershipCache: { [Player]: { [number]: boolean } } = {}

function MonetizationService.RegisterProduct(productId: number, handler: ProductHandler)
	assert(type(productId) == "number", "RegisterProduct: productId must be a number")
	assert(type(handler) == "function", "RegisterProduct: handler must be a function")
	if _products[productId] then
		warn("MonetizationService: product registered twice:", productId)
	end
	_products[productId] = handler
end

--- onOwned (optional) runs for owners on join and right after a live purchase.
function MonetizationService.RegisterGamepass(gamePassId: number, onOwned: GamepassHandler?)
	assert(type(gamePassId) == "number", "RegisterGamepass: gamePassId must be a number")
	_gamepasses[gamePassId] = onOwned or function() end
end

--- Cached ownership check (cache invalidated on purchase and on leave).
function MonetizationService.PlayerOwnsPass(player: Player, gamePassId: number): boolean
	local cache = _ownershipCache[player]
	if cache and cache[gamePassId] ~= nil then
		return cache[gamePassId]
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, gamePassId)
	if not ok then
		warn("MonetizationService: UserOwnsGamePassAsync failed for", player.Name, owns)
		return false
	end
	if not _ownershipCache[player] then
		_ownershipCache[player] = {}
	end
	_ownershipCache[player][gamePassId] = owns
	return owns
end

-- ── receipt processing ────────────────────────────────────────────────────────

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- player left; retry when they rejoin
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local DataService = Framework:GetService("DataService")
	local data = DataService.GetData(player)
	if not data then
		-- profile not loaded yet; Roblox will retry
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- idempotency: already granted on a previous (re)fire of this receipt
	if type(data._receipts) ~= "table" then
		data._receipts = {}
	end
	if table.find(data._receipts, receiptInfo.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local handler = _products[receiptInfo.ProductId]
	if not handler then
		warn("MonetizationService: no handler registered for product", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, result = pcall(handler, player, receiptInfo)
	if not ok then
		warn("MonetizationService: product handler error for", receiptInfo.ProductId, result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result == false then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- record the grant in the profile before acknowledging (private key: saved, not replicated)
	DataService.Update(player, "_receipts", function(receipts: any)
		local list = if type(receipts) == "table" then receipts else {}
		table.insert(list, receiptInfo.PurchaseId)
		while #list > MAX_STORED_RECEIPTS do
			table.remove(list, 1)
		end
		return list
	end)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService:Start(fw: any)
	Framework = fw

	MarketplaceService.ProcessReceipt = processReceipt

	-- live gamepass purchases: update cache + run the owned handler
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			if not _ownershipCache[player] then
				_ownershipCache[player] = {}
			end
			_ownershipCache[player][gamePassId] = true
			local onOwned = _gamepasses[gamePassId]
			if onOwned then
				task.spawn(onOwned, player)
			end
		end
	)

	-- run owned-gamepass handlers when the player's data is ready
	local DataService = Framework:GetService("DataService")
	DataService.ProfileLoaded:Connect(function(player: Player)
		for gamePassId, onOwned in _gamepasses do
			task.spawn(function()
				if onOwned and MonetizationService.PlayerOwnsPass(player, gamePassId) then
					onOwned(player)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		_ownershipCache[player] = nil
	end)
end

return MonetizationService
