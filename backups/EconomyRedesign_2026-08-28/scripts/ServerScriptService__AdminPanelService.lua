--[[
	AdminPanelService
	Backend for the developer admin panel (StarterGui.AdminPanel + its AdminPanelClient).
	GATE: Group Frenzy (14583228) rank >= MIN_RANK — 254 = Developer (Owner 255 passes).
	Lower MIN_RANK to 253 to let Admins in too. Studio playtests ALWAYS pass so the
	panel is testable without touching group ranks.
	SECURITY: the client button is cosmetic; every invoke re-checks the server-set
	IsGameAdmin attribute (clients cannot replicate attribute writes, so it's safe).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local ServerController = require(ServerStorage:WaitForChild("ServerController"))

local GROUP_ID = 14583228
local MIN_RANK = 254 -- Developer

local ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek"}
local ZONE_SET = {}
for _, z in ipairs(ZONES) do ZONE_SET[z] = true end

--.. plain RemoteFunction on purpose (MinigameCompletionService precedent): the
--.. Network framework is for gameplay traffic; this stays self-contained.
local remote = ReplicatedStorage:FindFirstChild("AdminPanelRemote") or Instance.new("RemoteFunction")
remote.Name = "AdminPanelRemote"
remote.Parent = ReplicatedStorage

local function markIfAdmin(plr)
	local isAdmin = RunService:IsStudio()
	if not isAdmin then
		local ok, rank = pcall(plr.GetRankInGroup, plr, GROUP_ID)
		isAdmin = ok and rank >= MIN_RANK
	end
	if isAdmin then
		plr:SetAttribute("IsGameAdmin", true)
	end
end
Players.PlayerAdded:Connect(markIfAdmin)
for _, plr in ipairs(Players:GetPlayers()) do markIfAdmin(plr) end

--.. session playtime = wall clock since this server saw the player join.
--.. (Players already here when the script starts — Studio hot-reload only —
--.. count from script start.) All-time lives in profile TotalStats.TotalTime,
--.. which CurrencyHandler ticks +1 every online second, current session included.
local joinedAt = {}
Players.PlayerAdded:Connect(function(plr) joinedAt[plr] = os.clock() end)
Players.PlayerRemoving:Connect(function(plr) joinedAt[plr] = nil end)
for _, plr in ipairs(Players:GetPlayers()) do joinedAt[plr] = os.clock() end

local function findTarget(adminPlr, name)
	if type(name) ~= "string" or name:gsub("%s", "") == "" then return adminPlr end
	name = name:gsub("%s", ""):lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower() == name or p.DisplayName:lower() == name then return p end
	end
	return nil
end

--.. Roblox-wide username -> userId. Distinguishes "no such user" from transient
--.. web failures (HTTP 429 etc.) so admins don't misread a rate limit as a typo.
local function resolveUserId(name)
	local ok, res = pcall(Players.GetUserIdFromNameAsync, Players, name)
	if ok and res then return res end
	local err = tostring(res)
	if err:lower():find("unknown user") then
		return nil, ("NO ROBLOX USER NAMED '%s'"):format(name:upper())
	end
	return nil, ("USERNAME LOOKUP FAILED (%s) — TRY AGAIN IN A MINUTE"):format(err)
end

local function bossFolderAndName(zone)
	local meters = ReplicatedStorage:FindFirstChild("BossProgress")
	local meter = meters and meters:FindFirstChild(zone)
	local bossName = meter and meter:GetAttribute("BossName")
	local folder = workspace:FindFirstChild("Breakables")
	folder = folder and folder:FindFirstChild(zone)
	return folder, bossName
end

remote.OnServerInvoke = function(plr, payload)
	if plr:GetAttribute("IsGameAdmin") ~= true then return "NOT AUTHORIZED" end
	if type(payload) ~= "table" or type(payload.Action) ~= "string" then return "BAD REQUEST" end
	local action = payload.Action

	if action == "SetCurrency" or action == "SetRebirths" then
		local amount = tonumber(payload.Amount)
		if not amount or amount ~= amount or amount == math.huge then return "ENTER A VALID AMOUNT FIRST" end
		amount = math.max(0, math.floor(amount))
		local currency = payload.Currency
		if action == "SetCurrency" and currency ~= "Cucumbers" and currency ~= "Coins" then return "BAD CURRENCY" end

		local target = findTarget(plr, payload.Target)
		if target then
			if action == "SetRebirths" then
				local ProfileService = ServerController.GetModule("ProfileService")
				local profile = ProfileService.GetUserData(target)
				if not profile then return "TARGET PROFILE NOT LOADED" end
				--.. same two writes TryRebirth/GrantFree do, plus the overhead tag refresh
				profile.Rebirths = amount
				local stats = target:FindFirstChild("leaderstats")
				local stat = stats and stats:FindFirstChild("Rebirths")
				if stat then stat.Value = amount end
				local RebirthService = ServerController.GetModule("RebirthService")
				pcall(function() RebirthService.UpdateTag(target) end)
				print(("[AdminPanel] %s set %s's Rebirths to %d"):format(plr.Name, target.Name, amount))
				return ("SET %s'S REBIRTHS TO %d"):format(target.Name:upper(), amount)
			end

			local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
			--.. leaderstats is the source of truth; InstanceValues mirrors to the profile
			CurrencyHandler.SetCurrency({Player = target; Currency = currency; Amount = amount;})
			print(("[AdminPanel] %s set %s's %s to %d"):format(plr.Name, target.Name, currency, amount))
			return ("SET %s'S %s TO %d"):format(target.Name:upper(), currency == "Cucumbers" and "CUKES" or "COINS", amount)
		end

		--.. not in this server: write the stat straight into the DataStore
		--.. profile (same pattern as the offline GivePets path below)
		local raw = tostring(payload.Target or ""):gsub("%s", "")
		if raw == "" then return "TYPE A TARGET USERNAME FIRST" end
		local userId, resolveErr = resolveUserId(raw)
		if not userId then return resolveErr end
		local ProfileService = ServerController.GetModule("ProfileService")
		local ok, err = ProfileService.AdminEditOfflineAsync(userId, function(data)
			if action == "SetRebirths" then
				data.Rebirths = amount
			else
				--.. CurrencyHandler's profile mirror lands in Stats[Currency]; same field here
				data.Stats = data.Stats or {}
				data.Stats[currency] = amount
			end
		end)
		local statLabel = action == "SetRebirths" and "REBIRTHS" or (currency == "Cucumbers" and "CUKES" or "COINS")
		print(("[AdminPanel] %s set offline userId %s's %s to %d via DataStore: %s"):format(plr.Name, tostring(userId), statLabel, amount, tostring(ok)))
		return ok and ("SET OFFLINE USER %s'S %s TO %d (SAVED TO DATASTORE)"):format(raw:upper(), statLabel, amount)
			or ("OFFLINE SET FAILED: %s"):format(tostring(err))
	end

	if action == "GetPlaytime" then
		local ProfileService = ServerController.GetModule("ProfileService")
		local function fmtHMS(seconds)
			seconds = math.floor(seconds)
			return ("%dH %02dM %02dS"):format(
				math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
		end
		local function line(target)
			local session = joinedAt[target] and fmtHMS(os.clock() - joinedAt[target]) or "?"
			local userData = ProfileService.GetUserData(target)
			local total = userData and userData.TotalStats and tonumber(userData.TotalStats.TotalTime)
			return ("%s — SESSION %s | ALL-TIME %s"):format(
				target.Name:upper(), session, total and fmtHMS(total) or "PROFILE NOT LOADED")
		end
		--.. blank target = report on everyone in the server, one line each
		local raw = payload.Target
		if type(raw) ~= "string" or raw:gsub("%s", "") == "" then
			local lines = {}
			for _, p in ipairs(Players:GetPlayers()) do
				table.insert(lines, line(p))
			end
			return table.concat(lines, string.char(10))
		end
		local target = findTarget(plr, raw)
		if target then return line(target) end

		--.. not in this server: read-only DataStore snapshot (no session lock,
		--.. so this never kicks the user from a server they're playing in)
		local cleaned = raw:gsub("%s", "")
		local userId, resolveErr = resolveUserId(cleaned)
		if not userId then return resolveErr end
		local data, viewErr = ProfileService.AdminViewOfflineAsync(userId)
		if not data then return viewErr end
		local total = data.TotalStats and tonumber(data.TotalStats.TotalTime)
		local lastSeen = data.OfflineData and tonumber(data.OfflineData.LastSeen)
		local seen = (lastSeen and lastSeen > 0)
			and ("LAST SEEN %s AGO"):format(fmtHMS(math.max(0, os.time() - lastSeen)))
			or "LAST SEEN UNKNOWN"
		return ("%s — OFFLINE (%s) | ALL-TIME %s (FROM DATASTORE)"):format(
			cleaned:upper(), seen, total and fmtHMS(total) or "?")
	end

	if action == "ListPets" then
		--.. roster for the pet-giver list: every Assets.Pets model with a Stats
		--.. entry (= actually givable), plus its live display name and rarity
		local PetStats = ServerController.GetDictionary("Pets").Stats
		local DisplayNames = require(ReplicatedStorage.Modules.PetDisplayNames)
		local list = {}
		for _, model in ipairs(ReplicatedStorage.Assets.Pets:GetChildren()) do
			local stats = PetStats[model.Name]
			if stats then
				table.insert(list, {Name = model.Name; Display = DisplayNames.Get(model.Name); Rarity = stats.Rarity;})
			end
		end
		return list
	end

	if action == "GivePets" then
		local names = payload.Pets
		if type(names) ~= "table" or #names == 0 then return "SELECT AT LEAST ONE PET" end
		if #names > 200 then return "TOO MANY PETS SELECTED" end
		local PetStats = ServerController.GetDictionary("Pets").Stats
		local valid = {}
		for _, name in ipairs(names) do
			if type(name) == "string" and PetStats[name] then table.insert(valid, name) end
		end
		if #valid == 0 then return "NO VALID PETS IN SELECTION" end

		local target = findTarget(plr, payload.Target)
		if target then
			--.. in this server: normal live-profile path (instant + client "AddPet" reveal)
			local PetService = ServerController.GetModule("PetService")
			local given = 0
			for _, name in ipairs(valid) do
				if PetService.AddPetToPlayer({Player = target; Pet = name}) then given += 1 end
			end
			print(("[AdminPanel] %s gave %d pet(s) to %s"):format(plr.Name, given, target.Name))
			return ("GAVE %d PET%s TO %s"):format(given, given == 1 and "" or "S", target.Name:upper())
		end

		--.. not in this server: write the pets straight into the DataStore profile
		local raw = tostring(payload.Target or ""):gsub("%s", "")
		if raw == "" then return "TYPE A TARGET USERNAME FIRST" end
		local userId, resolveErr = resolveUserId(raw)
		if not userId then return resolveErr end
		local ProfileService = ServerController.GetModule("ProfileService")
		local PetDefaults = require(ServerStorage.ServerController.PetService.PetDefaults)
		local ok, err = ProfileService.AdminEditOfflineAsync(userId, function(data)
			--.. mirrors AddPetToPlayer + MarkDiscovered, but on raw profile data
			data.PetData = data.PetData or {}
			local unlocked = type(data.PetData.Unlocked) == "string" and data.PetData.Unlocked or ""
			local unlockedSet = {}
			for token in unlocked:gmatch("[^|]+") do unlockedSet[token] = true end
			for _, name in ipairs(valid) do
				local id, tbl = PetDefaults.SetDefaults({Name = name; Stats = PetStats[name];})
				if id and tbl then
					data.PetData[id] = tbl
					if not unlockedSet[name] then
						unlockedSet[name] = true
						unlocked = (unlocked ~= "" and unlocked .. "|" or "") .. name
					end
				end
			end
			data.PetData.Unlocked = unlocked
		end)
		print(("[AdminPanel] %s gave %d pet(s) via DataStore to offline userId %s: %s"):format(plr.Name, #valid, tostring(userId), tostring(ok)))
		return ok and ("GAVE %d PET%s TO OFFLINE USER %s (SAVED TO DATASTORE)"):format(#valid, #valid == 1 and "" or "S", raw:upper())
			or ("OFFLINE GIVE FAILED: %s"):format(tostring(err))
	end

	if action == "ResetData" then
		local raw = tostring(payload.Username or ""):gsub("%s", "")
		if raw == "" then return "TYPE THE EXACT USERNAME TO RESET" end
		--.. in-server match first (also covers display names), else Roblox-wide lookup
		local target = findTarget(plr, raw)
		local userId = target and target.UserId
		if not userId then
			local id, resolveErr = resolveUserId(raw)
			if not id then return resolveErr end
			userId = id
		end
		local ProfileService = ServerController.GetModule("ProfileService")
		--.. direct DataStore wipe (kicks + releases first if they're in this server)
		local wiped = ProfileService.AdminWipeUserAsync(userId)
		warn(("[AdminPanel] %s WIPED ALL DATA for %s (userId %s): %s"):format(plr.Name, raw, tostring(userId), tostring(wiped)))
		return wiped and ("WIPED ALL DATA FOR %s%s"):format(raw:upper(), target and " (KICKED FROM THIS SERVER)" or "")
			or ("WIPE FAILED FOR %s (DATASTORE ERROR — TRY AGAIN)"):format(raw:upper())
	end

	if action == "UnlockVault" then
		local target = findTarget(plr, payload.Target)
		if not target then return "TARGET NOT FOUND" end
		local VaultService = ServerController.GetModule("VaultService")
		local ok, unlocked = pcall(function() return VaultService.AdminUnlock(target) end)
		print(("[AdminPanel] %s force-unlocked %s's vault: %s"):format(plr.Name, target.Name, tostring(ok and unlocked == true)))
		return (ok and unlocked == true) and ("%s'S VAULT UNLOCKED \u{1F513}"):format(target.Name:upper())
			or ("%s HAS NO STALL"):format(target.Name:upper())
	end

	local BreakablesService = ServerController.GetModule("BreakablesService")
	local zone = payload.Zone
	if not ZONE_SET[zone] then return "PICK A BIOME FIRST" end
	if action == "SpawnMutated" then
		local mutName = type(payload.Mutation) == "string" and payload.Mutation or "TODAY"
		local landed, mutUsed = BreakablesService.SpawnMutatedDev(zone, mutName)
		print(("[AdminPanel] %s spawned a %s cucumber in %s: %s"):format(plr.Name, tostring(mutUsed or mutName), zone, tostring(landed)))
		return landed and ("\u{2604} %s CUCUMBER SPAWNED IN %s"):format(tostring(mutUsed):upper(), zone:upper())
			or ("COULD NOT SPAWN IN %s \u{2014} TRY AGAIN"):format(zone:upper())
	end
	if action == "StartEvent" then
		local eventId = payload.Event
		--.. any registry event is startable per-biome (CUCUMBER SMASH included;
		--.. MinPlayersInBiome only gates the automatic rotation, never admins)
		local BiomeEventRegistry = require(ServerStorage.ServerController.BiomeEventRegistry)
		if type(eventId) ~= "string" or not BiomeEventRegistry.Get(eventId) then
			return "PICK A VALID EVENT"
		end
		local started, eventName = BreakablesService.StartEvent(eventId, zone)
		print(("[AdminPanel] %s started %s in %s: %s"):format(plr.Name, tostring(eventId), zone, tostring(started)))
		return started and ("STARTED %s IN %s"):format(eventName, zone:upper())
			or tostring(eventName)
	elseif action == "StopEvent" then
		local stopped, eventName = BreakablesService.StopEvent(zone)
		print(("[AdminPanel] %s stopped event in %s: %s"):format(plr.Name, zone, tostring(stopped)))
		return stopped and ("STOPPED %s IN %s"):format(eventName or "EVENT", zone:upper())
			or ("NO EVENT ACTIVE IN %s"):format(zone:upper())
	end

	if action == "SpawnBoss" then
		local folder, bossName = bossFolderAndName(zone)
		if folder and bossName and folder:FindFirstChild(bossName) then
			return ("%s ALREADY HAS A LIVE BOSS"):format(zone:upper())
		end
		BreakablesService.SpawnBoss(zone) -- has its own one-per-zone guard
		local spawned = folder and bossName and folder:FindFirstChild(bossName) ~= nil
		print(("[AdminPanel] %s spawned the %s boss: %s"):format(plr.Name, zone, tostring(spawned)))
		return spawned and ("BOSS SUMMONED IN %s"):format(zone:upper())
			or ("COULD NOT SUMMON IN %s"):format(zone:upper())
	elseif action == "KillBoss" then
		local killed = BreakablesService.KillBoss(zone, plr)
		print(("[AdminPanel] %s force-killed the %s boss: %s"):format(plr.Name, zone, tostring(killed)))
		return killed and ("BOSS IN %s DESTROYED"):format(zone:upper())
			or ("NO LIVE BOSS IN %s"):format(zone:upper())
	elseif action == "Lightning" then
		local struck = BreakablesService.LightningStrike(zone)
		print(("[AdminPanel] %s called lightning in %s: %s"):format(plr.Name, zone, tostring(struck)))
		return struck and ("\u{26A1} LIGHTNING STRUCK IN %s"):format(zone:upper())
			or ("NO CUCUMBER TO STRIKE IN %s"):format(zone:upper())
	end

	return "UNKNOWN ACTION"
end

print(("[AdminPanelService] ready (Group Frenzy rank %d+, Studio always allowed)."):format(MIN_RANK))
