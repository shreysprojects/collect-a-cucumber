--[[
	QuestBoardService (2026-08-27, user request; claim flow + dual reward same day)
	Per-player daily-style quests on the physical workspace.QuestBoard:
	  1. Smash 30-40 cucumbers (any breakable destroy, PortalCucumberDestroyed)
	  2. Collect 3-5 chests (ChestHandler.CollectChest fires QuestChestCollected)
	  3. Catch one specific cucumber type, weight-rolled from a random biome the
	     player has UNLOCKED (UserData.DoorData; Spawn always counts)
	A finished quest arms its card's green CLAIM button (Network "QuestClaim",
	fired by QuestBoardClient): claiming pays a TIME SKIP of BOTH -- the
	duration is rolled per quest from REWARD_CHOICES (1/3/5/10 min) --
	cucumbers (TimeSkipRateService.Grant) and vault coins
	(VaultTimeSkipService.Quote, floored at REWARD_MIN). All three CLAIMED ->
	ResetAt = now + 6h; new random quests roll when it expires.
	The catch target's display model is published to
	ReplicatedStorage.QuestTargetModels[<type name>] so the client's card
	viewport can render it (built once per type via CarryService.BuildFromTemplate).
	State lives in UserData.QuestBoard {Quests, ResetAt} (profile-persisted) and
	replicates as the JSON player attribute "QuestState".
	DEV HOOK (Studio only), workspace attribute "QuestBoardDev":
	  "reroll:Name" | "bump:Name:<questIdx>:<amount>" | "expire:Name" | "claim:Name:<questIdx>"
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ServerController = require(ServerStorage:WaitForChild("ServerController"))
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local ProfileService = ServerController.GetModule("ProfileService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local VaultTimeSkipService = ServerController.GetModule("VaultTimeSkipService")
local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
local BreakablesService = ServerController.GetModule("BreakablesService")
local CarryService = ServerController.GetModule("CarryService")
local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")

local RESET_SECONDS = 6 * 60 * 60
local REWARD_SECONDS = 5 * 60 -- legacy default for quests saved before durations rolled
local REWARD_CHOICES = {60, 180, 300, 600} -- 1 / 3 / 5 / 10 minutes, one rolled per quest
local REWARD_MIN = 500
local SMASH_MIN, SMASH_MAX = 30, 40
local CHEST_MIN, CHEST_MAX = 3, 5
local ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek"}

local chestCollected = ServerStorage:FindFirstChild("QuestChestCollected")
if not chestCollected then
	chestCollected = Instance.new("BindableEvent")
	chestCollected.Name = "QuestChestCollected"
	chestCollected.Parent = ServerStorage
end

local targetModels = ReplicatedStorage:FindFirstChild("QuestTargetModels")
if not targetModels then
	targetModels = Instance.new("Folder")
	targetModels.Name = "QuestTargetModels"
	targetModels.Parent = ReplicatedStorage
end

local LastClaim = {} -- [player] = os.clock() debounce
Players.PlayerRemoving:Connect(function(plr) LastClaim[plr] = nil end)

local function boardOf(plr)
	local ud = ProfileService.GetUserData(plr)
	if not ud then return nil end
	if type(ud.QuestBoard) ~= "table" then ud.QuestBoard = {} end
	return ud.QuestBoard, ud
end

local function unlockedZones(ud)
	local owned = type(ud.DoorData) == "string" and ud.DoorData or ""
	local list = {"Spawn"}
	for _, z in ipairs(ZONES) do
		if z ~= "Spawn" and owned:find(z, 1, true) then list[#list + 1] = z end
	end
	return list
end

local function push(plr, qb)
	plr:SetAttribute("QuestState", HttpService:JSONEncode({Quests = qb.Quests or {}, ResetAt = qb.ResetAt}))
end

--.. one shared display model per type for the client card viewports
local function ensureTargetModel(zone, typeName)
	if not (zone and typeName) or targetModels:FindFirstChild(typeName) then return end
	local ok = pcall(function()
		local typeDef = BreakablesService.FindType(zone, typeName)
		if not typeDef then return end
		local model = CarryService.BuildFromTemplate(typeDef)
		if not model then return end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored = true
			elseif d:IsA("BaseScript") or d:IsA("Sound") then d:Destroy() end
		end
		model.Name = typeName
		model:PivotTo(CFrame.new())
		model.Parent = targetModels
	end)
	if not ok then warn("[QuestBoardService] could not build target model for " .. tostring(typeName)) end
end

local function rollQuests(plr)
	local qb, ud = boardOf(plr)
	if not qb then return end
	local zones = unlockedZones(ud)
	local zone = zones[math.random(#zones)]
	local target = "Cucumber"
	local ok, pool = pcall(BreakablesService.TypeNamesFor, zone)
	if ok and pool and #pool > 0 then
		local total = 0
		for _, t in ipairs(pool) do total += math.max(t.Weight or 1, 0.01) end
		local roll = math.random() * total
		for _, t in ipairs(pool) do
			roll -= math.max(t.Weight or 1, 0.01)
			if roll <= 0 then target = t.Name break end
		end
	end
	qb.Quests = {
		{Type = "Smash"; Need = math.random(SMASH_MIN, SMASH_MAX); Have = 0; Done = false; Claimed = false; Reward = REWARD_CHOICES[math.random(#REWARD_CHOICES)];};
		{Type = "Chests"; Need = math.random(CHEST_MIN, CHEST_MAX); Have = 0; Done = false; Claimed = false; Reward = REWARD_CHOICES[math.random(#REWARD_CHOICES)];};
		{Type = "Catch"; Need = 1; Have = 0; Done = false; Claimed = false; Target = target; Zone = zone; Reward = REWARD_CHOICES[math.random(#REWARD_CHOICES)];};
	}
	qb.ResetAt = nil
	ensureTargetModel(zone, target)
	push(plr, qb)
end

local function grantClaim(plr, seconds)
	seconds = seconds or REWARD_SECONDS
	local cukes = 0
	pcall(function() cukes = TimeSkipRateService.Grant(plr, seconds) end)
	local coins = REWARD_MIN
	pcall(function() coins = math.max(VaultTimeSkipService.Quote(plr, seconds), REWARD_MIN) end)
	CurrencyHandler.AddCurrency({Player = plr; Currency = "Coins"; HasTotal = true; Amount = coins; WasPurchase = true;})
	Network:FireClient(plr, "Notif", {Message = ("\u{23F1} TIME SKIP! +%s CUKES & +$%s!"):format(
		NumberController.SuffixNumber(cukes), NumberController.SuffixNumber(coins)); Type = "Success";})
end

local function maybeArmReset(plr, qb)
	for _, q in ipairs(qb.Quests or {}) do
		if not (q.Done and q.Claimed) then return end
	end
	if not qb.ResetAt then
		qb.ResetAt = os.time() + RESET_SECONDS
		Network:FireClient(plr, "Notif", {Message = "\u{1F3C6} ALL QUESTS DONE! NEW QUESTS IN 6 HOURS!"; Type = "Success";})
	end
end

local function addProgress(plr, questType, amount)
	local qb = boardOf(plr)
	if not (qb and qb.Quests) then return end
	local changed = false
	for _, q in ipairs(qb.Quests) do
		if q.Type == questType and not q.Done then
			q.Have = math.min((q.Have or 0) + amount, q.Need or 1)
			changed = true
			if q.Have >= (q.Need or 1) then
				q.Done = true
				q.Claimed = false
			end
		end
	end
	if changed then push(plr, qb) end
end

local function tryCatch(plr, value)
	if type(value) ~= "string" or value == "" then return end
	local qb = boardOf(plr)
	if not (qb and qb.Quests) then return end
	for _, q in ipairs(qb.Quests) do
		if q.Type == "Catch" and not q.Done and q.Target then
			--.. attr is "<Mutation> <Name>" or plain "<Name>": suffix match.
			--.. A PRISMATIC catch (2026-08-27) is a wildcard: completes the
			--.. quest whatever the rolled target is.
			if value == q.Target or value:sub(-#q.Target - 1) == (" " .. q.Target)
				or value:sub(1, 10) == "PRISMATIC " then
				q.Have = q.Need or 1
				q.Done = true
				q.Claimed = false
				push(plr, qb)
			end
		end
	end
end

local function claim(plr, idx)
	idx = tonumber(idx)
	if not idx then return end
	local now = os.clock()
	if now - (LastClaim[plr] or 0) < 0.3 then return end
	LastClaim[plr] = now
	local qb = boardOf(plr)
	local q = qb and qb.Quests and qb.Quests[idx]
	if not (q and q.Done and not q.Claimed) then return end
	q.Claimed = true
	grantClaim(plr, q.Reward)
	maybeArmReset(plr, qb)
	push(plr, qb)
end

Network:BindEvents({
	QuestClaim = function(plr, idx)
		claim(plr, idx)
	end,
})

local function ensureQuests(plr)
	task.spawn(function()
		local deadline = os.clock() + 60
		while not ProfileService.GetUserData(plr) and plr.Parent and os.clock() < deadline do task.wait(0.5) end
		if not plr.Parent then return end
		local qb = boardOf(plr)
		if not qb then return end
		if type(qb.Quests) ~= "table" or #qb.Quests ~= 3 or (qb.ResetAt and os.time() >= qb.ResetAt) then
			rollQuests(plr)
		else
			for _, q in ipairs(qb.Quests) do
				if q.Type == "Catch" then ensureTargetModel(q.Zone, q.Target) end
			end
			push(plr, qb)
		end
		plr:GetAttributeChangedSignal("CarryingCucumber"):Connect(function()
			tryCatch(plr, plr:GetAttribute("CarryingCucumber"))
		end)
	end)
end

Players.PlayerAdded:Connect(ensureQuests)
for _, plr in ipairs(Players:GetPlayers()) do ensureQuests(plr) end

task.spawn(function()
	local smashEvt = ServerStorage:WaitForChild("PortalCucumberDestroyed", 60)
	if smashEvt then
		smashEvt.Event:Connect(function(plr)
			if typeof(plr) == "Instance" and plr:IsA("Player") and plr.Parent then
				addProgress(plr, "Smash", 1)
			end
		end)
	else
		warn("[QuestBoardService] PortalCucumberDestroyed missing; smash quest inert.")
	end
end)

chestCollected.Event:Connect(function(plr)
	if typeof(plr) == "Instance" and plr:IsA("Player") and plr.Parent then
		addProgress(plr, "Chests", 1)
	end
end)

--.. in-session expiry: reroll the board the moment the 6h window lapses
task.spawn(function()
	while true do
		task.wait(15)
		for _, plr in ipairs(Players:GetPlayers()) do
			local qb = boardOf(plr)
			if qb and qb.ResetAt and os.time() >= qb.ResetAt then
				rollQuests(plr)
				Network:FireClient(plr, "Notif", {Message = "\u{1F4CB} NEW QUESTS ARE UP!"; Type = "Success";})
			end
		end
	end
end)

if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("QuestBoardDev"):Connect(function()
		local v = workspace:GetAttribute("QuestBoardDev")
		if type(v) ~= "string" or v == "" then return end
		workspace:SetAttribute("QuestBoardDev", nil)
		local cmd, name, x, y = string.match(v, "^(%w+):([%w_]+):?(%d*):?(%d*)$")
		local plr = name and Players:FindFirstChild(name)
		if not plr then return end
		if cmd == "reroll" then
			rollQuests(plr)
		elseif cmd == "bump" then
			local qb = boardOf(plr)
			local q = qb and qb.Quests and qb.Quests[tonumber(x) or 0]
			if q then addProgress(plr, q.Type, tonumber(y) or 1) end
		elseif cmd == "claim" then
			LastClaim[plr] = nil
			claim(plr, tonumber(x))
		elseif cmd == "expire" then
			local qb = boardOf(plr)
			if qb and qb.ResetAt then
				qb.ResetAt = os.time() - 1
				push(plr, qb)
			end
		end
		print("[QuestBoardDev] " .. v)
	end)
end

print("[QuestBoardService] quest board ready (3 quests, claimable dual time-skip rewards, 6h reset).")
