--[[
	VaultTimeSkipService (2026-08-26)
	The SECOND Time Skip mechanic. The first (TimeSkipRateService) quotes the
	CUKES your pickaxe + pets would smash over a duration; this one quotes the
	COINS your vault keeps printing: the sum of every stored cucumber's
	upgraded coins/sec (CarryService.EffectiveRate -- the exact rate the
	collect pads accrue each second), times the skipped seconds.
	Quote applies coin multipliers ONCE (same contract as TimeSkipRateService),
	so Grant awards the quoted amount flat (WasPurchase). An empty vault
	honestly quotes 0 -- there is nothing to fast-forward.
	Wiring mirrors the first mechanic: ProductController.Products.VaultTimeSkips
	(dashboard ids; Id 0 placeholders are skipped), receipt grants in
	ProductHandler, live card quotes over ReplicatedStorage.GetVaultTimeSkipQuote
	(served by TimeSkipQuoteServer).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")

local VaultTimeSkipService = {}

--.. raw coins/sec the player's vault produces right now (0 with no stall or
--.. an empty one). Reads the SAME records the per-second accrual loop reads,
--.. so a quote can never disagree with what the pads actually earn.
function VaultTimeSkipService.CoinsPerSecond(Player)
	local total = 0
	pcall(function()
		local VaultService = ServerController.GetModule("VaultService")
		local CarryService = ServerController.GetModule("CarryService")
		local stall = VaultService.StallOfPlayer(Player)
		if not stall then return end
		for _, record in pairs(stall.Stored) do
			total += CarryService.EffectiveRate(record)
		end
	end)
	return total
end

--.. coins/sec with the same coin multipliers the collect pads' payout gets
function VaultTimeSkipService.GetRate(Player)
	local base = VaultTimeSkipService.CoinsPerSecond(Player)
	if base <= 0 then return 0 end
	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	return CurrencyHandler.GetMulipliers({
		Player = Player;
		Currency = "Coins";
		Amount = base;
	})
end

function VaultTimeSkipService.Quote(Player, seconds)
	seconds = math.max(0, tonumber(seconds) or 0)
	return math.max(0, math.floor(VaultTimeSkipService.GetRate(Player) * seconds))
end

--.. the only grant path for a Vault Time Skip. Quote already carries the
--.. coin multipliers, so the award is flat (WasPurchase) -- granting a
--.. purchase for an empty vault refunds nothing, so refuse it loudly instead.
function VaultTimeSkipService.Grant(Player, seconds)
	local amount = VaultTimeSkipService.Quote(Player, seconds)
	if amount <= 0 then
		Network:FireClient(Player, "Notif", {Message = "\u{1F3E6} VAULT IS EMPTY!"; Type = "Error";})
		return 0
	end
	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	CurrencyHandler.AddCurrency({
		Player = Player;
		Currency = "Coins";
		HasTotal = true;
		Amount = amount;
		WasPurchase = true;
	})
	Network:FireClient(Player, "Notif", {Message = ("\u{23E9} VAULT SKIP: +$%s!"):format(NumberController.SuffixNumber(amount)); Type = "Success";})
	return amount
end

function VaultTimeSkipService.Initialize()
	print("[VaultTimeSkipService] vault coin time-skip quotes ready")
end

return VaultTimeSkipService
