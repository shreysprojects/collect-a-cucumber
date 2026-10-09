--[[
	TimeSkipServer  (Script, ServerScriptService)  2026-09-23
	Serves ServerStorage.TimeSkipService's quotes to the client: Remotes.TimeSkipQuote (RemoteFunction)
	(seconds) -> {Cash, Strength, CashRate, StrengthRate, Seconds} for the shop's time-skip cards
	(ShopController refreshes them while the shop is open). Studio hook: Remotes.TimeSkipQuote attribute
	TimeSkipDev = "cash:<seconds>" | "strength:<seconds>" | "quote:<seconds>" (first player).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local TimeSkipService = require(ServerStorage:WaitForChild("TimeSkipService"))

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local Quote = Remotes:FindFirstChild("TimeSkipQuote")
if Quote and not Quote:IsA("RemoteFunction") then Quote:Destroy() Quote = nil end
if not Quote then
	Quote = Instance.new("RemoteFunction")
	Quote.Name = "TimeSkipQuote"
	Quote.Parent = Remotes
end

local LastQuote = {} -- [player] = os.clock() (a light per-player throttle: 10 quotes / s)
Quote.OnServerInvoke = function(player, seconds)
	local now = os.clock()
	if LastQuote[player] and now - LastQuote[player] < 0.1 then return nil end
	LastQuote[player] = now
	return TimeSkipService.Quote(player, seconds)
end
Players.PlayerRemoving:Connect(function(player) LastQuote[player] = nil end)

if RunService:IsStudio() then
	Quote:SetAttribute("TimeSkipDev", nil)
	Quote:GetAttributeChangedSignal("TimeSkipDev"):Connect(function()
		local cmd = Quote:GetAttribute("TimeSkipDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		Quote:SetAttribute("TimeSkipDev", nil)
		local player = Players:GetPlayers()[1]
		if not player then return end
		local kind, seconds = cmd:match("^(%a+):(%d+)$")
		seconds = tonumber(seconds) or 0
		if kind == "cash" then
			print("[TimeSkipServer] dev cash skip -> " .. tostring(TimeSkipService.GrantCash(player, seconds)))
		elseif kind == "strength" then
			print("[TimeSkipServer] dev strength skip -> " .. tostring(TimeSkipService.GrantStrength(player, seconds)))
		elseif kind == "quote" then
			local q = TimeSkipService.Quote(player, seconds)
			print(("[TimeSkipServer] dev quote %ds: cash %d (%.2f/s) strength %d (%.2f/s)"):format(seconds, q.Cash, q.CashRate, q.Strength, q.StrengthRate))
		else
			warn("[TimeSkipServer] dev: use cash:<s> / strength:<s> / quote:<s>")
		end
	end)
end

print("[TimeSkipServer] Remotes.TimeSkipQuote ready (cash = Data.CashPerSec, strength = bench rate)")
