--[[---------------------------------------DESCRIPTION------------------------------------------
	Copies replicated Level / XP / Coins onto vars.PlayerData and tells the HUD
	to refresh the level bar, the Coins label, and the rebirth panel.

	PurchaseConfirmed(text) is the client mode for a purchase the SERVER granted
	(a Robux product after ProcessReceipt, a server-checked pass):
	ReEvent:FireClient(player, "PurchaseConfirmed", "2x Distance unlocked!") plays
	PurchaseFX.Confirmed (success sounds, a green toast, sparkles).

--------------------------------------------------------------------------------------------]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PurchaseFX = require(ReplicatedStorage.Assets.Modules.Client.UI.PurchaseFX)

local api = {}

local ATTRS = { "Level", "XP", "XPNeeded", "Coins", "Rebirths", "Ascensions", "Multiplier", "UnlockedMountains", "UnlockedSnowballs", "UnlockedLaunchers", "EquippedSnowball", "EquippedLauncher" }

local function snapshot(player)
	return {
		Level = player:GetAttribute("Level") or 1,
		XP = player:GetAttribute("XP") or 0,
		XPNeeded = player:GetAttribute("XPNeeded") or 100,
		Coins = player:GetAttribute("Coins") or 0,
		Multiplier = player:GetAttribute("Multiplier") or 1,
	}
end

function api:SetupPlayerProgress()
	local vars = self.Variables
	local player = vars.LP
	local queued = false

	local function apply()
		queued = false
		local data = snapshot(player)
		local pd = vars.PlayerData
		pd.Level = data.Level
		pd.XP = data.XP
		pd.XPNeeded = data.XPNeeded
		pd.Coins = data.Coins
		pd.Multiplier = data.Multiplier
		self.GUIFramework:InvokeUI("HUD", "SetProgress", data)
		self.GUIFramework:InvokeUI("HUD", "RefreshMountainsPanel")
		self.GUIFramework:InvokeUI("HUD", "RefreshShopPanel")
		self.GUIFramework:InvokeUI("HUD", "RefreshRebirthPanel")
		self.GUIFramework:InvokeUI("HUD", "RefreshAscendPanel")
		self.GUIFramework:InvokeUI("HUD", "QueueAttention")
	end

	local function queue()
		if queued then
			return
		end
		queued = true
		task.defer(apply)
	end

	for _, name in ATTRS do
		player:GetAttributeChangedSignal(name):Connect(queue)
	end
	apply()
end

function api:PurchaseConfirmed(text)
	PurchaseFX.Confirmed(text)
end

return api
