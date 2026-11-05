--!strict
-- Game Passes and Developer Products.
-- ProcessReceipt only says "granted" after the purchase is saved, so players
-- never pay without getting their item (Roblox retries until we confirm).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Data = require(script.Parent.Data)
local Net = require(script.Parent.Net)
local Progress = require(script.Parent.Progress)

local Shop = {}

type Grant = { unchain: number?, smash: number?, skip: number?, coins: number?, trail: string? }
local onGranted: ((player: Player, grant: Grant) -> ())? = nil

local productById: { [number]: string } = {}
for key, product in Config.Products do
	if product.id ~= 0 then
		productById[product.id] = key
	end
end

local passById: { [number]: string } = {}
for key, pass in Config.GamePasses do
	if pass.id ~= 0 then
		passById[pass.id] = key
	end
end

local function applyGrant(player: Player, productKey: string)
	local p = Data.get(player) :: Data.Profile
	local product = Config.Products[productKey]
	local grant: Grant = product.grant
	if grant.unchain then
		p.unchain += grant.unchain
	end
	if grant.smash then
		p.smash += grant.smash
	end
	if grant.skip then
		p.skip += grant.skip
	end
	if grant.coins then
		p.coins += grant.coins
	end
	if grant.trail and not p.trails[grant.trail] then
		p.trails[grant.trail] = true
		p.equipped = grant.trail
	end
	if product.oncePerPlayer then
		p.starterBought = true
	end
	Data.markDirty(player)
	Progress.applyCosmetics(player)
	Net.send(player, "toast", { key = "purchaseThanks", args = { "p_" .. productKey }, good = true })
	if onGranted then
		task.spawn(onGranted, player, grant)
	end
end

local function grantPass(player: Player, passKey: string)
	local p = Data.get(player)
	if not p or p.passes[passKey] then
		return
	end
	p.passes[passKey] = true
	if passKey == "VIP" then
		-- give today's VIP bonus right away
		p.freeUnchain += Config.Daily.vipBonusUnchain
		p.freeSmash += Config.Daily.vipBonusSmash
	end
	for _, trail in Config.Trails do
		if trail.pass == passKey then
			p.trails[trail.id] = true
			p.equipped = trail.id
		end
	end
	Data.markDirty(player)
	Progress.applyCosmetics(player)
end

function Shop.checkPasses(player: Player)
	for key, pass in Config.GamePasses do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns then
				grantPass(player, key)
			end
		end
	end
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local key = productById[receipt.ProductId]
	if not player or not key then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = Data.get(player)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if not table.find(p.receipts, purchaseId) then
		applyGrant(player, key)
		table.insert(p.receipts, purchaseId)
		while #p.receipts > 100 do
			table.remove(p.receipts, 1)
		end
	end
	if Data.save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local key = passById[passId]
	if purchased and key then
		grantPass(player, key)
		Net.send(player, "toast", { key = "purchaseThanks", args = { "g_" .. key }, good = true })
		Data.save(player)
	end
end)

-- In Studio, buttons for products without an ID yet grant the item for free so
-- you can test everything before publishing.
Net.on("studioBuy", function(player, payload)
	if not RunService:IsStudio() or type(payload) ~= "table" then
		return
	end
	if payload.kind == "product" and Config.Products[payload.key] and Config.Products[payload.key].id == 0 then
		applyGrant(player, payload.key)
	elseif payload.kind == "pass" and Config.GamePasses[payload.key] and Config.GamePasses[payload.key].id == 0 then
		grantPass(player, payload.key)
	end
end)

function Shop.init(callback: (player: Player, grant: Grant) -> ())
	onGranted = callback
end

return Shop
