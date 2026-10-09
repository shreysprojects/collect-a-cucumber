--[[
	ShopProductsServer  (Script, ServerScriptService)  2026-09-10
	Grants the Robux products sold by StarterGui.CucumberMenus.ShopPanel. Every card there carries
	attributes  ProductId  (the Developer Product id; 0 = not created yet, shown as "SOON") and
	StrengthAmount  or  CashAmount. Each id > 0 is registered with GymService.RegisterProduct
	(GymService owns MarketplaceService.ProcessReceipt) and the handler adds the amount to the
	player's profile through DataService, so the HUD counters update at once.
	Boost pills (attribute DurationTitle) have no effect yet: a boost id > 0 is reported, not granted.
	To sell a pack: create the Developer Product on the Creator Dashboard, paste its id into the
	card's ProductId attribute (StarterGui, no code change), publish.
]]
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local GymService = require(ServerStorage:WaitForChild("GymService"))

local shop = StarterGui:WaitForChild("CucumberMenus"):WaitForChild("ShopPanel")

local registered, pending = 0, 0
for _, item in ipairs(shop:GetDescendants()) do
	if not item:IsA("GuiObject") then continue end
	local id = tonumber(item:GetAttribute("ProductId")) or 0
	if id <= 0 then continue end
	local strength = tonumber(item:GetAttribute("StrengthAmount"))
	local cash = tonumber(item:GetAttribute("CashAmount"))
	if strength or cash then
		GymService.RegisterProduct(id, function(player)
			if not DataService.IsLoaded(player) then return false end -- NotProcessedYet: Roblox retries
			if strength then DataService.Increment(player, "Strength", strength) end
			if cash then DataService.Increment(player, "Cash", cash) end
			print(("[ShopProductsServer] %s bought product %d (+%s strength, +%s cash)"):format(player.Name, id, tostring(strength or 0), tostring(cash or 0)))
			return true
		end)
		registered += 1
	else
		pending += 1
		warn(("[ShopProductsServer] %s has ProductId %d but no StrengthAmount / CashAmount (boosts are not granted yet)"):format(item:GetFullName(), id))
	end
end
print(("[ShopProductsServer] %d shop product(s) registered, %d without a handler"):format(registered, pending))
