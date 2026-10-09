--[[
	EggShopClient  (LocalScript, StarterPlayerScripts)
	Egg shop notifications through the game-wide style (ReplicatedStorage.Modules.Notify,
	user 2026-09-07): "Not enough Cash" when an EggShopPrompt is triggered without the
	price, "Bought X Egg" when the tool arrives.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Notify = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Notify")) -- the game-wide notification style (user 2026-09-07)
local NumberAbbrev = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("NumberAbbrev")) -- 2026-09-23: egg prices reach 12B

local function Toast(text, color)
	Notify.Show(text, color)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player or not CollectionService:HasTag(prompt, "EggShopPrompt") then return end
	local price = tonumber(prompt:GetAttribute("Price")) or 0
	local data = player:FindFirstChild("Data")
	local cash = data and data:FindFirstChild("Cash") and data.Cash.Value or 0
	if cash < price then
		Toast(("Not enough Cash! You need $%s more."):format(NumberAbbrev.Abbrev(price - cash)), Notify.COLORS.Error)
	end
end)

local function WatchTools(container)
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and CollectionService:HasTag(child, "EggTool") and not child:GetAttribute("Announced") then
			child:SetAttribute("Announced", true)
			Toast(("Bought a %s!"):format(child.Name), Notify.COLORS.Success)
		end
	end)
end
WatchTools(player:WaitForChild("Backpack"))
player.CharacterAdded:Connect(WatchTools)
if player.Character then WatchTools(player.Character) end
