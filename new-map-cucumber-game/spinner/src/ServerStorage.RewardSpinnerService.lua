--[[
	RewardSpinnerService  (ModuleScript, ServerStorage)  2026-09-23
	The PORTAL REWARD SPINNER of the New Map, ported from the Zombie Cucumber Game's
	MinigameCompletionService (server-authoritative pool + locked payouts) and driven by the imported
	StarterGui.SelectingReward reel (SelectingRewardClient). User: "portal rewards spinner system - holds all
	rewards from this game including time skips (it doesn't say time skips direct though, it just says the
	cash value / strength value given outright)".

	  POOL   weighted reward ids:
	           cash_<d>      the player's CASH production over the duration (TimeSkipService.CashRate x seconds),
	                         shown as its value ("+$2.5M") never as a time skip
	           strength_<d>  the bench-press strength over the duration (TimeSkipService.StrengthRate x s)
	           item_<Key>    one drop item (ItemsCatalog: potions, pearl, holy water, seeds, token, zombie egg)
	         A cash prize picked while the player earns nothing (no cucumber placed) swaps to the same-duration
	         strength prize, so nobody wins "+$0".
	  FLOW   Award(player, source) -> picks + LOCKS the reward (amount quoted now, attributes PendingSpinReward /
	         PendingSpinAmount / SpinToken) -> Remotes.RewardSpinner:FireClient {Kind = "Spin", Token, Selection =
	         {id, cashAmounts, strengthAmounts, items}} -> the client plays confetti + the reel (SelectingReward.Play)
	         -> Remotes.RewardSpinnerFinished:FireServer(token) -> the grant (once per token) + a "Granted" message
	         for the toast. A client that never answers is granted after GRANT_TIMEOUT seconds anyway (the
	         reward was already the player's the moment it was locked).
	  HOOK   RewardSpinnerServer wraps PortalService.ReturnHome: reason "Finished" = a completed minigame
	         (Classic Obby chest, Avalanche / Lava Run / Bloxout completion, the Wild West hunt).
	  STUDIO Remotes.RewardSpinner attribute RewardSpinnerDev = "spin[:<id>]" (first player)
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Items = require(Modules:WaitForChild("ItemsCatalog"))
local TimeSkipService = require(ServerStorage:WaitForChild("TimeSkipService"))
local DataService = require(ServerStorage:WaitForChild("DataService"))

local M = {}

M.POOL = {
	{Id = "cash_1m", Weight = 16}, {Id = "cash_2m", Weight = 14}, {Id = "cash_5m", Weight = 11},
	{Id = "cash_10m", Weight = 8}, {Id = "cash_15m", Weight = 6}, {Id = "cash_30m", Weight = 4}, {Id = "cash_1h", Weight = 2},
	{Id = "strength_1m", Weight = 14}, {Id = "strength_2m", Weight = 12}, {Id = "strength_5m", Weight = 9},
	{Id = "strength_10m", Weight = 6}, {Id = "strength_15m", Weight = 4}, {Id = "strength_30m", Weight = 2},
	{Id = "item_SpeedPotion", Weight = 9}, {Id = "item_StrengthPotion", Weight = 8}, {Id = "item_CashPotion", Weight = 8},
	{Id = "item_WarpPearl", Weight = 6}, {Id = "item_HolyWater", Weight = 5}, {Id = "item_RedemptionToken", Weight = 3},
	{Id = "item_GoldenSeed", Weight = 3}, {Id = "item_ZombieEgg", Weight = 1.5}, {Id = "item_VoidSeed", Weight = 0.5},
}
M.DURATIONS = {["1m"] = 60, ["2m"] = 120, ["5m"] = 300, ["10m"] = 600, ["15m"] = 900, ["30m"] = 1800, ["1h"] = 3600}
M.RARITY_BY_SECONDS = {{3600, "Epic"}, {1800, "Epic"}, {600, "Rare"}, {300, "Uncommon"}, {0, "Common"}}
M.GRANT_TIMEOUT = 30 -- s: a locked reward is paid even when the client never reports the reel finished
M.SPIN_DELAY = 1.4 -- s after ReturnHome before the client is told to spin (the iris transition home)

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local function Remote(class, name)
	local r = Remotes:FindFirstChild(name)
	if r and not r:IsA(class) then r:Destroy() r = nil end
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
local SpinRemote = Remote("RemoteEvent", "RewardSpinner")
local FinishedRemote = Remote("RemoteEvent", "RewardSpinnerFinished")

local rng = Random.new()
local Pending = {} -- [player] = {Token, Id, Amount, Item, DueAt, Source}
local TotalWeight = 0
for _, entry in ipairs(M.POOL) do TotalWeight += entry.Weight end

local function Parse(id)
	local kind, rest = tostring(id):match("^(%a+)_(.+)$")
	if kind == "cash" or kind == "strength" then
		local seconds = M.DURATIONS[rest]
		if seconds then return kind, seconds end
	elseif kind == "item" and Items.Get(rest) then
		return kind, rest
	end
	return nil
end
M.Parse = Parse

function M.RarityOf(id)
	local kind, arg = Parse(id)
	if kind == "item" then return Items.Get(arg).Rarity or "Common" end
	if kind then
		for _, row in ipairs(M.RARITY_BY_SECONDS) do
			if arg >= row[1] then return row[2] end
		end
	end
	return "Common"
end

local function Pick()
	local roll = rng:NextNumber() * TotalWeight
	local acc = 0
	for _, entry in ipairs(M.POOL) do
		acc += entry.Weight
		if roll <= acc then return entry.Id end
	end
	return M.POOL[1].Id
end

local function ItemApi(name)
	local api = ServerStorage:FindFirstChild("ItemAPI")
	local fn = api and api:FindFirstChild(name)
	return fn and fn:IsA("BindableFunction") and fn or nil
end

--.. the amount a rate reward pays, quoted NOW and locked
local function QuoteFor(player, id)
	local kind, seconds = Parse(id)
	if kind == "cash" then return TimeSkipService.Quote(player, seconds).Cash end
	if kind == "strength" then return TimeSkipService.Quote(player, seconds).Strength end
	return nil
end

--.. everything the reel needs to draw every tile: amounts per duration + item names / rarities
local function Payload(player, pending)
	local cashAmounts, strengthAmounts = {}, {}
	for suffix, seconds in pairs(M.DURATIONS) do
		local q = TimeSkipService.Quote(player, seconds)
		if q.Cash >= 1 then cashAmounts["cash_" .. suffix] = q.Cash end
		if q.Strength >= 1 then strengthAmounts["strength_" .. suffix] = q.Strength end
	end
	local kind = Parse(pending.Id)
	if kind == "cash" then cashAmounts[pending.Id] = pending.Amount end
	if kind == "strength" then strengthAmounts[pending.Id] = pending.Amount end
	local items = {}
	for _, def in ipairs(Items.ITEMS) do
		items["item_" .. def.Key] = {Name = def.Name, Rarity = def.Rarity, Key = def.Key}
	end
	return {id = pending.Id, cashAmounts = cashAmounts, strengthAmounts = strengthAmounts, items = items}
end

local function Grant(player, pending)
	local kind, arg = Parse(pending.Id)
	local text
	if kind == "cash" then
		local amount = math.max(0, math.floor(tonumber(pending.Amount) or 0))
		if amount > 0 and DataService.IsLoaded(player) then
			DataService.Increment(player, "Cash", amount)
			DataService.RequestSave(player)
		end
		text = ("+%s CASH!"):format(TimeSkipService.FormatCash(amount))
	elseif kind == "strength" then
		local amount = math.max(0, math.floor(tonumber(pending.Amount) or 0))
		if amount > 0 and DataService.IsLoaded(player) then
			DataService.Increment(player, "Strength", amount)
			DataService.RequestSave(player)
		end
		text = ("+%s STRENGTH!"):format(TimeSkipService.FormatStrength(amount))
	elseif kind == "item" then
		local give = ItemApi("Give")
		local def = Items.Get(arg)
		local ok = give and pcall(give.Invoke, give, player, arg, 1)
		text = ok and ("+1 %s!"):format(def and def.Name or arg) or ("The %s could not be handed over"):format(def and def.Name or arg)
	else
		text = "REWARD!"
	end
	print(("[RewardSpinnerService] %s won %s (%s) from %s"):format(player.Name, pending.Id, tostring(pending.Amount or 1), tostring(pending.Source)))
	if player.Parent == Players then SpinRemote:FireClient(player, {Kind = "Granted", Token = pending.Token, Id = pending.Id, Text = text}) end
end

local function Settle(player, token)
	local pending = Pending[player]
	if not pending or (token and pending.Token ~= token) then return false end
	Pending[player] = nil
	player:SetAttribute("PendingSpinReward", nil)
	player:SetAttribute("PendingSpinAmount", nil)
	player:SetAttribute("SpinToken", nil)
	Grant(player, pending)
	return true
end

--.. pick + lock + tell the client; forced = a reward id to use instead of rolling (dev hook)
function M.Award(player, source, forced)
	if not (player and player.Parent == Players) then return nil end
	if Pending[player] then Settle(player) end -- an unanswered previous spin pays out first
	local id = forced and Parse(forced) and forced or Pick()
	local kind, seconds = Parse(id)
	if kind == "cash" then
		local amount = QuoteFor(player, id)
		if not amount or amount < 1 then -- nothing placed: the same-duration strength prize instead
			for suffix, s in pairs(M.DURATIONS) do
				if s == seconds and M.DURATIONS[suffix] and Parse("strength_" .. suffix) then id = "strength_" .. suffix break end
			end
			if not Parse(id) then id = "strength_5m" end
		end
	end
	local pending = {Token = HttpService:GenerateGUID(false), Id = id, Amount = QuoteFor(player, id), DueAt = os.clock() + M.GRANT_TIMEOUT, Source = source}
	Pending[player] = pending
	player:SetAttribute("PendingSpinReward", id)
	player:SetAttribute("PendingSpinAmount", pending.Amount)
	player:SetAttribute("SpinToken", pending.Token)
	local payload = Payload(player, pending)
	task.delay(M.SPIN_DELAY, function()
		if Pending[player] == pending and player.Parent == Players then
			SpinRemote:FireClient(player, {Kind = "Spin", Token = pending.Token, Selection = payload, Source = source})
		end
	end)
	print(("[RewardSpinnerService] %s: %s locked for %s (%s)"):format(player.Name, id, tostring(pending.Amount or 1), tostring(source)))
	return id, pending.Amount
end

local started = false
function M.Start()
	if started then return M end
	started = true
	FinishedRemote.OnServerEvent:Connect(function(player, token)
		if type(token) ~= "string" or #token > 64 then return end
		Settle(player, token)
	end)
	Players.PlayerRemoving:Connect(function(player)
		if Pending[player] then Settle(player) end
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			local now = os.clock()
			for player, pending in pairs(Pending) do
				if now >= pending.DueAt then Settle(player) end
			end
		end
	end)
	if RunService:IsStudio() then
		SpinRemote:SetAttribute("RewardSpinnerDev", nil)
		SpinRemote:GetAttributeChangedSignal("RewardSpinnerDev"):Connect(function()
			local cmd = SpinRemote:GetAttribute("RewardSpinnerDev")
			if type(cmd) ~= "string" or cmd == "" then return end
			SpinRemote:SetAttribute("RewardSpinnerDev", nil)
			local player = Players:GetPlayers()[1]
			if not player then return end
			local forced = cmd:match("^spin:(.+)$")
			if cmd == "spin" or forced then
				M.Award(player, "Dev", forced)
			else
				warn("[RewardSpinnerService] dev: use spin[:<id>]")
			end
		end)
	end
	print(("[RewardSpinnerService] %d rewards in the pool (Remotes.RewardSpinner / RewardSpinnerFinished)"):format(#M.POOL))
	return M
end

return M
