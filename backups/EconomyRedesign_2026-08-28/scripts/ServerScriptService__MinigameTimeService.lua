-- MinigameTimeService
-- Server-authoritative run timer + persistent best time for every minigame, plus the
-- "home" teleport used by the minigame HUD's home button.
--
-- START of a run  = one of the In<Minigame> attributes flips true (the portal Services
--                   own those, set server-side when the player is teleported in).
-- FINISH of a run = the player COMPLETES it. Every portal Service bumps the shared
--                   MinigameCompletionToken attribute to a fresh value right before it
--                   fires MinigameEffects.Completed, so we detect completion centrally
--                   by watching that attribute -- no edits to the 5 Services needed.
-- Leaving via the home button does NOT complete, so no best time is recorded.
--
-- Times are kept in seconds. Per-minigame best times persist in the same real DataStore
-- in Studio and production, merge by shortest time, and are published as player
-- attributes as soon as the player's saved record loads:
--   MinigameKey        -> which minigame the player is currently in (or nil)
--   MinigameRunStart   -> workspace:GetServerTimeNow() when the run began
--   BestTime_<key>     -> best seconds for that minigame (nil = none yet)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")

local MINIGAMES = {
	{ attr = "InStarterObby",   key = "StarterObby" },
	{ attr = "InSnowAvalanche", key = "SnowAvalanche" },
	{ attr = "InLavaRun",       key = "LavaRun" },
	{ attr = "InDesertHunt",    key = "DesertHunt" },
	{ attr = "InVoidBloxout",   key = "VoidBloxout" },
}
local MINIGAME_NAMES = {
	StarterObby = "Classic Obby";
	SnowAvalanche = "Avalanche";
	LavaRun = "Lava Run";
	DesertHunt = "Wild West Rat Hunt";
	VoidBloxout = "Bloxout Incorporated";
}
local MAX_REASONABLE = 3600  -- ignore absurd elapsed values (afk / clock glitch)

local spawnLocation = Workspace:WaitForChild("SpawnLocation")

--== remotes ================================================================
local remotes = ReplicatedStorage:FindFirstChild("MinigameHudRemotes") or Instance.new("Folder")
remotes.Name = "MinigameHudRemotes"
remotes.Parent = ReplicatedStorage
local goHome = remotes:FindFirstChild("GoHome") or Instance.new("RemoteEvent")
goHome.Name = "GoHome"
goHome.Parent = remotes

local cancelRun = ServerStorage:FindFirstChild("MinigameSessionCancel") or Instance.new("BindableEvent")
cancelRun.Name = "MinigameSessionCancel"
cancelRun.Parent = ServerStorage

--== best-time persistence ===================================================
local store = DataStoreService:GetDataStore("MinigameBestTimes_v1")
local bestCache = {} -- [userId] = { [key] = shortest seconds }

local function dsKey(player)
	return "Player_" .. player.UserId
end

local function mergeShortest(target, source)
	target = type(target) == "table" and target or {}
	if type(source) ~= "table" then return target end
	for _, m in ipairs(MINIGAMES) do
		local candidate = tonumber(source[m.key])
		if candidate and candidate > 0 and candidate <= MAX_REASONABLE then
			local current = tonumber(target[m.key])
			if not current or candidate < current then
				target[m.key] = candidate
			end
		end
	end
	return target
end

local function publishBest(player)
	if not player.Parent then return end
	local t = bestCache[player.UserId] or {}
	for _, m in ipairs(MINIGAMES) do
		player:SetAttribute("BestTime_" .. m.key, t[m.key])
	end
end

local function loadBest(player)
	local ok, value = false, nil
	for attempt = 1, 3 do
		ok, value = pcall(function() return store:GetAsync(dsKey(player)) end)
		if ok then break end
		task.wait(attempt * 0.5)
	end
	if not ok then
		warn("[MinigameTimeService] load best failed after retries for", player, value)
		value = {}
	end
	-- A very fast completion may occur while the initial read is in flight. Preserve
	-- the shortest value from both sources rather than letting the read overwrite it.
	bestCache[player.UserId] = mergeShortest(bestCache[player.UserId] or {}, value)
	publishBest(player)
end

local function saveBest(player)
	local source = bestCache[player.UserId]
	if not source then return false end
	local snapshot = mergeShortest({}, source)
	local ok, stored = false, nil
	for attempt = 1, 3 do
		ok, stored = pcall(function()
			return store:UpdateAsync(dsKey(player), function(current)
				return mergeShortest(type(current) == "table" and current or {}, snapshot)
			end)
		end)
		if ok then break end
		task.wait(attempt * 0.5)
	end
	if not ok then
		warn("[MinigameTimeService] save best failed after retries for", player, stored)
		return false
	end
	bestCache[player.UserId] = mergeShortest(bestCache[player.UserId] or {}, stored)
	publishBest(player)
	return true
end

--== live run timing =========================================================
local runByUser = {}  -- [userId] = { key = ..., start = serverTime }

local function startRun(player, key)
	local now = Workspace:GetServerTimeNow()
	runByUser[player.UserId] = { key = key, start = now }
	player:SetAttribute("MinigameKey", key)
	player:SetAttribute("MinigameRunStart", now)
end

local function clearRun(player)
	runByUser[player.UserId] = nil
	player:SetAttribute("MinigameKey", nil)
	player:SetAttribute("MinigameRunStart", nil)
end

local function activeKey(player)
	for _, m in ipairs(MINIGAMES) do
		if player:GetAttribute(m.attr) then return m.key end
	end
	return nil
end

local function recordCompletion(player)
	local run = runByUser[player.UserId]
	if not run then return end
	local elapsed = Workspace:GetServerTimeNow() - run.start
	if elapsed <= 0 or elapsed > MAX_REASONABLE then return end

	-- The same server-authoritative completion that records the time announces
	-- the result once to every player's chat.
	Network:FireAllClients(
		"MinigameCompleteChat",
		player.DisplayName,
		MINIGAME_NAMES[run.key] or run.key,
		elapsed
	)

	local t = bestCache[player.UserId] or {}
	bestCache[player.UserId] = t
	if not t[run.key] or elapsed < t[run.key] then
		t[run.key] = elapsed
		player:SetAttribute("BestTime_" .. run.key, elapsed)
		saveBest(player)
	end
end

--== home button =============================================================
goHome.OnServerEvent:Connect(function(player)
	local key = activeKey(player)
	if not key then return end  -- only from inside a minigame
	cancelRun:Fire(player, key, "Home")
	for _, m in ipairs(MINIGAMES) do
		player:SetAttribute(m.attr, false)
	end
	clearRun(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		character:PivotTo(spawnLocation.CFrame * CFrame.new(0, 3, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end)

--== wire up players =========================================================
local function watch(player)
	for _, m in ipairs(MINIGAMES) do
		player:GetAttributeChangedSignal(m.attr):Connect(function()
			if player:GetAttribute(m.attr) then
				startRun(player, m.key)
			else
				local run = runByUser[player.UserId]
				if run and run.key == m.key then
					clearRun(player)
				end
			end
		end)
	end
	--.. every Service bumps this to a fresh token the instant the run is completed
	player:GetAttributeChangedSignal("MinigameCompletionToken"):Connect(function()
		local token = player:GetAttribute("MinigameCompletionToken")
		if token ~= nil and token ~= "" then
			recordCompletion(player)
		end
	end)
	task.spawn(loadBest, player)
end

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player)
	saveBest(player)
	bestCache[player.UserId] = nil
	runByUser[player.UserId] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveBest(player)
	end
end)

print("[MinigameTimeService] run timer + best time + home teleport ready.")
