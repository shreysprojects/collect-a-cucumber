--[[
	ShopProductsServer  (Script, ServerScriptService)  2026-09-10, time skips 2026-09-23
	Grants the Robux products sold by StarterGui.CucumberMenus.ShopPanel. Every card there carries
	attributes  ProductId  (the Developer Product id; 0 = not created yet, shown as "SOON") and either
	  * StrengthAmount / CashAmount        a flat pack: the amount is added to the profile, or
	  * TimeSkipSeconds + TimeSkipCurrency  a TIME SKIP (2026-09-23): the player's own production over
	    that many seconds, quoted and granted by ServerStorage.TimeSkipService ("Cash" = Data.CashPerSec
	    x seconds, "Strength" = the bench-press rate x seconds) - the same quote the card shows.
	Each id > 0 is registered with GymService.RegisterProduct (GymService owns
	MarketplaceService.ProcessReceipt) and the handler adds the amount to the player's profile through
	DataService, so the HUD counters update at once.
	Boost pills (attribute DurationTitle) have no effect yet: a boost id > 0 is reported, not granted.
	To sell a card: create the Developer Product on the Creator Dashboard, paste its id into the
	card's ProductId attribute (StarterGui, no code change), publish.
]]
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local GymService = require(ServerStorage:WaitForChild("GymService"))
local TimeSkipService = require(ServerStorage:WaitForChild("TimeSkipService"))

local shop = StarterGui:WaitForChild("CucumberMenus"):WaitForChild("ShopPanel")

local registered, pending = 0, 0
for _, item in ipairs(shop:GetDescendants()) do
	if not item:IsA("GuiObject") then continue end
	local id = tonumber(item:GetAttribute("ProductId")) or 0
	if id <= 0 then continue end
	local strength = tonumber(item:GetAttribute("StrengthAmount"))
	local cash = tonumber(item:GetAttribute("CashAmount"))
	local skipSeconds = tonumber(item:GetAttribute("TimeSkipSeconds"))
	local skipCurrency = item:GetAttribute("TimeSkipCurrency")
	if skipSeconds and skipSeconds > 0 then
		GymService.RegisterProduct(id, function(player)
			if not DataService.IsLoaded(player) then return false end -- NotProcessedYet: Roblox retries
			--.. a 0 quote (nothing placed) still counts as granted: Roblox would otherwise retry forever;
			--.. the player was told why by the toast
			local amount = TimeSkipService.Grant(player, skipCurrency == "Strength" and "Strength" or "Cash", skipSeconds)
			print(("[ShopProductsServer] %s bought product %d (%s time skip %d s -> +%s)"):format(player.Name, id, tostring(skipCurrency), skipSeconds, tostring(amount)))
			return true
		end)
		registered += 1
	elseif strength or cash then
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
		warn(("[ShopProductsServer] %s has ProductId %d but no StrengthAmount / CashAmount / TimeSkipSeconds (boosts are not granted yet)"):format(item:GetFullName(), id))
	end
end
print(("[ShopProductsServer] %d shop product(s) registered, %d without a handler"):format(registered, pending))
