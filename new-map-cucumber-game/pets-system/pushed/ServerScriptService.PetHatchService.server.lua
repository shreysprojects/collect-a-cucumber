--[[
	PetHatchService  (Script, ServerScriptService)
	Egg hatching, ported from the Zombie Cucumber Game on 2026-09-07 (the plot pets moved to
	ServerStorage.PetService on 2026-09-22).

	  * TRIGGER: a placed egg (EggPlacement, tag "PlacedEgg", attributes HatchAt / Owner / EggName)
	    whose countdown has reached zero hatches the moment its OWNER steps onto it (root inside the
	    egg's hitbox footprint + STEP_MARGIN, up to STEP_HEIGHT above its base). One hatch at a time
	    per player.
	  * ROLL: PetsCatalog.Roll = the zombie EggService float roll over the egg's pool (same eight
	    pools, same odds), once per egg. Player attribute PetsHatched counts this session's reveals.
	  * HATCH TRANSACTION (2026-09-22, pet system): the pet is OWNED before the reveal starts.
	    Hatch validates (owner in game + base restored, profile loaded and not closing,
	    PetService ready, the egg's stable EggId, no reveal / hatch already running for that
	    player), locks the egg (Locks + Hatching) and the player (HatchBusy), snapshots the base
	    (BaseSaveAPI.Snapshot, which must not yield), rolls, then PetService.GrantFromEgg removes the
	    saved egg record (by EggId) and appends the saved pet record in one synchronous block. Only
	    then is the egg marked Consumed + destroyed, a save requested and the reveal begun, so the
	    profile holds either the egg or the pet, never both and never neither. An egg whose EggId is
	    already an owned pet's SourceEggId is consumed with no second reward (Duplicate); a full
	    pet inventory keeps the egg and pauses that owner's eggs for FULL_PAUSE seconds.
	  * REVEAL: fires ReplicatedStorage.Remotes.PetHatch "Begin" to the owner with everything the
	    client needs to rebuild the egg (EggName / Scale / Material / Mutations) and show the pet
	    (Pet / display name / rarity / odds) plus Token (a GUID), PetId, Kg, Reserve,
	    AutoEquipAfterCombat and Stats (income, combat, ability). EggHatchClient plays the zombie
	    click-to-hatch reveal and answers "Opened" with that token, which only finishes THAT
	    presentation: PetService.FinishPresentation spawns the pet if it is still equipped (or
	    REVEAL_FALLBACK seconds later if the answer never comes). A token never grants, rerolls
	    or resets anything; leaving mid-reveal keeps the pet (it spawns from the roster next join).
	  * PLOT PETS / SAVING: owned records (profile Data.Base.Pets), the six-pet roster, spawning,
	    roaming and the plot.Pets folders live in ServerStorage.PetService; this script never
	    spawns or clears a model itself (PetHatchAPI is retired).
	  * Studio dev hook: workspace:SetAttribute("PetHatchDev", ...)
	      "ready"               every placed egg's countdown -> 0
	      "hatch:<EggName>"     GRANT a saved pet of that egg (Basic / Desert / ...) to the first
	                            player through the hatch commit + play the reveal (no egg consumed)
	      "hatch:<EggName>:<Pet>"  same, forcing the pet
	      "spawn:<Pet>"         same saved grant without a reveal
	      "clear"               PetService.DetachPlot for every player (runtime models only)
	      "fail:pre-grant" / "fail:post-grant" / "fail:post-destroy"  the NEXT real hatch stops at
	                            that boundary (hatch interruption tests)
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

--..Modules..--
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Catalog = require(Modules:WaitForChild("PetsCatalog"))
local DataService = require(ServerStorage:WaitForChild("DataService"))

--.. 2026-09-22: pet-system modules are optional until their stage is installed. A missing PetService
--.. leaves eggs un-hatchable (warned) - there is no fallback to the old transient grant
local function Lazy(name, parent)
	local cache
	return function()
		if cache then return cache end
		local module = (parent or ServerStorage):FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then cache = result end
		return cache
	end
end
local GetPetService = Lazy("PetService")
local GetPetBuffService = Lazy("PetBuffService")
local GetPetBalance = Lazy("PetBalance", Modules)
local GetPetStats = Lazy("PetStats", Modules)

--..Config..--
local EGG_TAG = "PlacedEgg"
local STEP_MARGIN = 1.25 -- studs beyond the egg hitbox footprint that still count as standing on it
local STEP_HEIGHT = 7 -- the root may be this far above the egg's base (standing on top of a big egg)
--.. seconds: finish the presentation even if the client never answers; longer than EggHatchClient's
--.. 95 s watchdog so the client normally acknowledges first (PetBalance.TIMING.REVEAL_FALLBACK, OD-6)
local REVEAL_FALLBACK = (function()
	local balance = GetPetBalance()
	local value = balance and type(balance.TIMING) == "table" and balance.TIMING.REVEAL_FALLBACK
	return type(value) == "number" and value == value and value > 0 and value < 3600 and value or 100
end)()
local FULL_PAUSE = 10 -- seconds a full pet inventory pauses that owner's eggs (the egg is kept; no retry spam)
local SNAPSHOT_SLOW_WARN = 0.05 -- seconds: a (synchronous) BaseSaveAPI.Snapshot call longer than this is reported as slow
local WARN_INTERVAL = 60 -- seconds between two warns of the same kind
local TRIGGER_TICK = 0.15
local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

--..Instances..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local PetHatch = Remotes:FindFirstChild("PetHatch")
if not PetHatch then
	PetHatch = Instance.new("RemoteEvent")
	PetHatch.Name = "PetHatch"
	PetHatch.Parent = Remotes
end

--..State..--
--.. 2026-09-22: a reveal is the PRESENTATION of a pet that is already owned; its token is the only
--.. thing the client's "Opened" can finish
local Presentations = {} -- [token] = {Player, PetId, Spot, Generation, Timer}
local ActiveToken = {} -- [player] = the token of the reveal on that player's screen
local Locks = setmetatable({}, {__mode = "k"}) -- [egg] = true while a hatch runs on it
local HatchBusy = {} -- [player] = true from the validation to the Begin (one hatch per player)
local FullUntil = {} -- [player] = os.clock() until which a full pet inventory pauses their eggs
local Hatched = {} -- [player] = count this session (not saved)
local Rng = Random.new()
local Fault = nil -- Studio only (PetHatchDev "fail:*"): the boundary the NEXT real hatch stops at
local FrameCount = 0 -- Heartbeat frames: a snapshot call that spans one has yielded
local Warned = {} -- [key] = os.clock() of the last warn of that kind

--..Helpers..--
local function WarnOnce(key, message)
	local now = os.clock()
	if Warned[key] and now - Warned[key] < WARN_INTERVAL then return end
	Warned[key] = now
	warn(message)
end

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function IsValidId(id)
	return type(id) == "string" and #id >= 1 and #id <= 64
end

--.. DataService functions that arrive with the pet-system patch are feature-checked
local function IsClosing(player)
	return type(DataService.IsClosing) == "function" and DataService.IsClosing(player) == true
end

local function GenerationOf(player)
	if type(DataService.GetGeneration) ~= "function" then return nil end
	return DataService.GetGeneration(player)
end

local function PetServiceReady(PetService, player)
	local ok, ready = pcall(PetService.IsReady, player)
	return ok and ready == true
end

local function PlotOf(player)
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

--..Hatching..--
--.. the reveal is done (the client's "Opened" with its token, or the REVEAL_FALLBACK timer): PetService
--.. spawns the pet if it is still equipped, attached and has no model yet. It never grants, rerolls or
--.. resets anything, and a missing / forged / repeated token does nothing (2026-09-22)
local function Presentation(player, token)
	local presentation = type(token) == "string" and Presentations[token] or nil
	if not presentation or presentation.Player ~= player then return end
	Presentations[token] = nil
	if ActiveToken[player] == token then ActiveToken[player] = nil end
	local timer = presentation.Timer
	if timer and timer ~= coroutine.running() then pcall(task.cancel, timer) end
	local PetService = GetPetService()
	if PetService then
		local ok, err = pcall(PetService.FinishPresentation, player, presentation.PetId, presentation.Spot, presentation.Generation)
		if not ok then WarnOnce("finish", "[PetHatchService] FinishPresentation: " .. tostring(err)) end
	end
	Hatched[player] = (Hatched[player] or 0) + 1
	player:SetAttribute("PetsHatched", Hatched[player])
end

--.. the reveal card's numbers, derived from the saved record (never saved themselves); nil when the
--.. stats modules are not installed (the card then hides its stat line)
local function RevealStats(record)
	local PetStats, PetBalance = GetPetStats(), GetPetBalance()
	if not (PetStats and PetBalance) then return nil end
	local ok, stats = pcall(PetStats.Calculate, record)
	if not ok or type(stats) ~= "table" or stats.Valid ~= true then return nil end
	local ability = type(stats.Ability) == "string" and stats.Ability or "None"
	local duration
	if ability == "Yield" or ability == "Haste" then
		local row = type(PetBalance.ABILITIES) == "table" and PetBalance.ABILITIES[ability]
		duration = type(row) == "table" and row.Duration or nil
	elseif ability == "Guard" then
		local buffs = GetPetBuffService()
		if buffs and type(buffs.GuardSeconds) == "function" then
			local okGuard, seconds = pcall(buffs.GuardSeconds)
			if okGuard then duration = seconds end
		end
		if not Finite(duration) then
			local okGuard, seconds = pcall(PetStats.GuardSeconds, PetBalance.DEFAULT_DAY_SECONDS, PetBalance.DEFAULT_NIGHT_SECONDS)
			duration = okGuard and seconds or nil
		end
	end
	local function Number(x) return Finite(x) and x or 0 end
	return {
		Income = Number(stats.Income), ShotDamage = Number(stats.ShotDamage), ShotInterval = Number(stats.ShotInterval),
		DPS = Number(stats.DPS), Ability = ability, AbilityChance = Number(stats.AbilityChance),
		AbilityDuration = Finite(duration) and duration or nil, Fighter = stats.Fighter == true,
	}
end

--.. CONTRACTS 8.2 step 7: an unguessable token, the fallback timer, then "Begin" with the existing
--.. fields + Token / PetId / Kg / Reserve / AutoEquipAfterCombat / Stats. The pet is already owned
local function StartReveal(player, record, info, spot, eggName, look)
	local _, key = Catalog.PoolOf(eggName)
	local pet = record.Pet
	local token = HttpService:GenerateGUID(false)
	--.. 2026-09-23: the name carries the inherited traits ("Golden VOID NEON Tabby"; PetStats.Calculate builds it)
	local displayName = Catalog.DisplayNameOf(pet)
	local PetStats = GetPetStats()
	if PetStats then
		local okStats, stats = pcall(PetStats.Calculate, record)
		if okStats and type(stats) == "table" and type(stats.DisplayName) == "string" and stats.DisplayName ~= "" then displayName = stats.DisplayName end
	end
	local presentation = {Player = player, PetId = record.Id, Spot = spot, Generation = GenerationOf(player)}
	Presentations[token] = presentation
	ActiveToken[player] = token
	presentation.Timer = task.delay(REVEAL_FALLBACK, Presentation, player, token)
	PetHatch:FireClient(player, "Begin", {
		EggName = eggName;
		EggKey = key;
		EggDisplayName = look.DisplayName or (key);
		Scale = look.Scale or 1;
		Material = look.Material;
		Mutations = look.Mutations or "";
		Pet = pet;
		PetDisplayName = displayName;
		Rarity = Catalog.RarityOf(pet);
		Percent = Catalog.PercentOf(eggName, pet);
		Chance = Catalog.ChanceText(eggName, pet);
		Token = token;
		PetId = record.Id;
		Kg = look.Kg;
		Reserve = info.Reserve == true;
		AutoEquipAfterCombat = info.AutoEquipAfterCombat == true;
		Stats = RevealStats(record);
	})
	print(("[PetHatchService] %s hatched %s (%s, %s%%) from a %s - pet %s %s"):format(player.Name, tostring(pet), Catalog.RarityOf(pet),
		tostring(Catalog.PercentOf(eggName, pet)), tostring(key), tostring(record.Id), info.Reserve == true and "in reserve" or "equipped"))
	return token
end

--.. every exit before the egg is consumed hands the egg and the player back (8.2 step 1)
local function Release(player, egg)
	HatchBusy[player] = nil
	Locks[egg] = nil
	egg:SetAttribute("Hatching", nil)
end

--.. Studio fault injection: true (once) when the armed PetHatchDev "fail:*" boundary is reached
local function TakeFault(boundary)
	if Fault ~= boundary then return false end
	Fault = nil
	print(("[PetHatchService] dev fault %s fired: this hatch stops at that boundary"):format(boundary))
	return true
end

--.. the hatch transaction (CONTRACTS 8.2): the pet is OWNED (profile record + roster) before the
--.. reveal starts, and the profile holds either the egg record or the pet record, never both
local function Hatch(player, egg)
	local PetService = GetPetService()
	if not PetService then
		WarnOnce("nopetservice", "[PetHatchService] ServerStorage.PetService is missing - eggs cannot hatch")
		return
	end
	--.. 1. validate, then lock the egg and the player
	if Locks[egg] or not egg.Parent or not CollectionService:HasTag(egg, EGG_TAG) then return end
	if egg:GetAttribute("Hatching") or egg:GetAttribute("Consumed") then return end
	if player.Parent ~= Players or egg:GetAttribute("Owner") ~= player.UserId then return end
	if ActiveToken[player] or HatchBusy[player] or (FullUntil[player] or 0) > os.clock() then return end
	if player:GetAttribute("BaseRestored") ~= true or not DataService.IsLoaded(player) or IsClosing(player) then return end
	if not PetServiceReady(PetService, player) then return end
	local plot = PlotOf(player)
	if not plot or not egg:IsDescendantOf(plot) then return end
	local eggId = egg:GetAttribute("EggId")
	if not IsValidId(eggId) then
		WarnOnce("noeggid", "[PetHatchService] a placed egg has no EggId - it cannot hatch (EggPlacement stamps one)")
		return
	end
	local eggName = egg:GetAttribute("EggName")
	if not Catalog.PoolOf(eggName) then
		WarnOnce("pool:" .. tostring(eggName), "[PetHatchService] no pet pool for egg " .. tostring(eggName))
		return
	end
	Locks[egg] = true
	HatchBusy[player] = true
	egg:SetAttribute("Hatching", true)

	--.. 2. snapshot pending world changes first (PLAN 8.3; refused before the restore - fine). The commit
	--.. never depends on it (the egg record is found by Id), but it must not yield: a Heartbeat between the
	--.. two FrameCount reads proves it did (HatchBusy keeps one hatch per player either way). The clock only
	--.. reports a slow call - os.clock keeps running through synchronous work, so time alone is no yield
	local api = ServerStorage:FindFirstChild("BaseSaveAPI")
	local snapshot = api and api:FindFirstChild("Snapshot")
	if snapshot and snapshot:IsA("BindableFunction") then
		local frame, started = FrameCount, os.clock()
		local ok, err = pcall(snapshot.Invoke, snapshot, player)
		local elapsed = os.clock() - started
		if FrameCount ~= frame then
			WarnOnce("snapshotyield", "[PetHatchService] BaseSaveAPI.Snapshot yielded during a hatch - it must be synchronous")
		elseif elapsed > SNAPSHOT_SLOW_WARN then
			WarnOnce("snapshotslow", ("[PetHatchService] BaseSaveAPI.Snapshot took %d ms during a hatch (synchronous, but slow)"):format(math.floor(elapsed * 1000 + 0.5)))
		end
		if not ok then WarnOnce("snapshot", "[PetHatchService] BaseSaveAPI.Snapshot: " .. tostring(err)) end
	end
	--.. re-validate step 1 (egg still there, lock still ours, owner still loaded). No yields from here on
	if not (Locks[egg] and egg.Parent and CollectionService:HasTag(egg, EGG_TAG) and egg:GetAttribute("Hatching") == true
		and not egg:GetAttribute("Consumed") and egg:GetAttribute("Owner") == player.UserId and egg:IsDescendantOf(plot)
		and plot:GetAttribute("Owner") == player.UserId and player.Parent == Players and DataService.IsLoaded(player)
		and not IsClosing(player) and PetServiceReady(PetService, player)) then
		Release(player, egg)
		return
	end

	--.. 3. what the pet inherits, read before the egg goes
	local kg = egg:GetAttribute("Kg")
	local material = egg:GetAttribute("Material")
	local mutations = egg:GetAttribute("Mutations")
	local scale = tonumber(egg:GetAttribute("Scale"))
	local displayName = egg:GetAttribute("DisplayName")
	local eggInfo = {
		EggId = eggId,
		EggName = eggName,
		Kg = Finite(kg) and kg or nil,
		Material = type(material) == "string" and material ~= "" and material or nil,
		Mutations = type(mutations) == "string" and mutations or "",
	}
	local look = {
		DisplayName = type(displayName) == "string" and displayName or nil;
		Scale = Finite(scale) and scale or 1;
		Material = eggInfo.Material;
		Mutations = eggInfo.Mutations;
		Kg = eggInfo.Kg;
	}
	local spot = egg:GetPivot().Position

	--.. 4. roll once, then the synchronous commit: PetService takes the egg record (by EggId) out and puts
	--.. the pet record in, back to back (a duplicate EggId returns the pet it already became)
	local petKey = Catalog.Roll(eggName, Rng)
	local ok, record, info = pcall(function()
		if TakeFault("pre-grant") then error("PetHatchDev fault pre-grant (before GrantFromEgg)", 0) end
		return PetService.GrantFromEgg(player, eggInfo, petKey)
	end)
	if not ok then
		WarnOnce("grant", "[PetHatchService] GrantFromEgg failed, the egg is kept: " .. tostring(record))
		Release(player, egg)
		return
	end
	if type(record) ~= "table" then
		if type(info) == "table" and info.Error == "InventoryFull" then FullUntil[player] = os.clock() + FULL_PAUSE end
		Release(player, egg)
		return
	end
	info = type(info) == "table" and info or {}
	if TakeFault("post-grant") then
		--.. the egg stays in the world with Hatching = true; snapshots skip it (its EggId is an owned SourceEggId)
		HatchBusy[player] = nil
		Locks[egg] = nil
		return
	end

	--.. 5. consume the egg: marked first, so no snapshot can ever re-add it
	egg:SetAttribute("Consumed", true)
	egg:Destroy()
	Locks[egg] = nil
	if TakeFault("post-destroy") then
		HatchBusy[player] = nil
		return
	end

	--.. 6. a coalesced save of the committed profile
	DataService.RequestSave(player)
	if info.Duplicate then
		HatchBusy[player] = nil
		print(("[PetHatchService] %s: egg %s already became pet %s - consumed, no second reward"):format(player.Name, eggId, tostring(record.Id)))
		return
	end

	--.. 7. the reveal presents the owned pet
	HatchBusy[player] = nil
	StartReveal(player, record, info, spot, eggName, look)
end

--.. every exit of Hatch releases HatchBusy; an unexpected error also hands back an egg that was not consumed
local function SafeHatch(player, egg)
	local ok, err = pcall(Hatch, player, egg)
	if ok then return end
	WarnOnce("hatcherror", "[PetHatchService] hatch error: " .. tostring(err))
	HatchBusy[player] = nil
	if not egg:GetAttribute("Consumed") then Release(player, egg) end
end

--.. the owner standing on a ready egg
local function CheckEgg(egg, now)
	if not egg.Parent or egg:GetAttribute("Hatching") or egg:GetAttribute("Consumed") or Locks[egg] then return end
	local hatchAt = tonumber(egg:GetAttribute("HatchAt"))
	if not hatchAt or hatchAt > now then return end
	local owner = Players:GetPlayerByUserId(tonumber(egg:GetAttribute("Owner")) or 0)
	if not owner or ActiveToken[owner] or HatchBusy[owner] then return end
	--.. 2026-09-22: only a restored base hatches, and a full pet inventory pauses its owner's eggs
	if owner:GetAttribute("BaseRestored") ~= true or (FullUntil[owner] or 0) > os.clock() then return end
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hitbox = egg.PrimaryPart
	if not root or not hitbox then return end
	local rel = hitbox.CFrame:PointToObjectSpace(root.Position)
	local half = hitbox.Size * 0.5
	if math.abs(rel.X) <= half.X + STEP_MARGIN and math.abs(rel.Z) <= half.Z + STEP_MARGIN
		and rel.Y >= -half.Y - 2 and rel.Y <= half.Y + STEP_HEIGHT then
		local PetService = GetPetService()
		if not PetService then
			WarnOnce("nopetservice", "[PetHatchService] ServerStorage.PetService is missing - eggs cannot hatch")
			return
		end
		if not PetServiceReady(PetService, owner) then return end
		SafeHatch(owner, egg)
	end
end

--..Loops..--
local triggerClock = 0
RunService.Heartbeat:Connect(function(dt)
	FrameCount += 1
	triggerClock += dt
	if triggerClock >= TRIGGER_TICK then
		triggerClock = 0
		local now = workspace:GetServerTimeNow()
		for _, egg in ipairs(CollectionService:GetTagged(EGG_TAG)) do
			CheckEgg(egg, now)
		end
	end
end)

--..Wiring..--
PetHatch.OnServerEvent:Connect(function(player, action, token)
	--.. 2026-09-22: "Opened" carries the reveal's token and finishes only that presentation
	if action == "Opened" and type(token) == "string" and #token <= 64 then Presentation(player, token) end
end)

Players.PlayerRemoving:Connect(function(player)
	--.. ownership is already committed: only the presentation state goes (the pet spawns from the roster next join)
	for token, presentation in pairs(Presentations) do
		if presentation.Player == player then
			Presentations[token] = nil
			if presentation.Timer then pcall(task.cancel, presentation.Timer) end
		end
	end
	ActiveToken[player] = nil
	HatchBusy[player] = nil
	FullUntil[player] = nil
	Hatched[player] = nil
end)

--..Studio dev hook..--
if RunService:IsStudio() then
	--.. 2026-09-22: dev grants go through the same PetService commit as a hatch = a real SAVED pet (OD-7);
	--.. no egg is consumed (EggId nil), reserve when no slot is free
	local function DevGrant(player, eggName, petKey, reveal)
		local PetService = GetPetService()
		if not PetService then print("[PetHatchService] dev: PetService unavailable") return end
		if ActiveToken[player] or HatchBusy[player] then print("[PetHatchService] dev: a reveal is still running") return end
		local plot = PlotOf(player)
		if not plot then print("[PetHatchService] dev: no plot") return end
		local ok, record, info = pcall(PetService.GrantFromEgg, player, {EggId = nil, EggName = eggName}, petKey)
		if not ok or type(record) ~= "table" then
			print(("[PetHatchService] dev: grant refused (%s)"):format(tostring(ok and type(info) == "table" and info.Error or record)))
			return
		end
		info = type(info) == "table" and info or {}
		DataService.RequestSave(player)
		local spot = Vector3.new(plot.Position.X, plot.Position.Y + plot.Size.Y * 0.5, plot.Position.Z)
		if reveal then
			StartReveal(player, record, info, spot, eggName, {})
		else
			local okFinish, err = pcall(PetService.FinishPresentation, player, record.Id, spot, GenerationOf(player))
			if not okFinish then warn("[PetHatchService] dev: FinishPresentation: " .. tostring(err)) end
		end
		print(("[PetHatchService] dev: granted a SAVED %s (pet %s, %s) to %s%s"):format(tostring(record.Pet), tostring(record.Id),
			info.Reserve == true and "reserve" or "equipped", player.Name, reveal and " + reveal" or ""))
	end

	--.. "Basic" for a Basic Egg pet (the short name eggs carry)
	local function EggOfPet(petKey)
		for key, egg in pairs(Catalog.EGGS) do
			if type(egg) == "table" and type(egg.Pets) == "table" and egg.Pets[petKey] then return (key:gsub("%s*Egg$", "")) end
		end
		return nil
	end

	workspace:GetAttributeChangedSignal("PetHatchDev"):Connect(function()
		local cmd = workspace:GetAttribute("PetHatchDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("PetHatchDev", "")
		local player = Players:GetPlayers()[1]
		if cmd == "ready" then
			local now = workspace:GetServerTimeNow()
			for _, egg in ipairs(CollectionService:GetTagged(EGG_TAG)) do egg:SetAttribute("HatchAt", now) end
			print("[PetHatchService] dev: every placed egg is ready")
		elseif cmd == "clear" then
			local PetService = GetPetService()
			if not PetService then print("[PetHatchService] dev: PetService unavailable") return end
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(PetService.DetachPlot, p, "Reload")
				if not ok then warn("[PetHatchService] dev: DetachPlot: " .. tostring(err)) end
			end
			print("[PetHatchService] dev: every plot pet despawned (runtime only; records and rosters kept)")
		elseif cmd == "fail:pre-grant" or cmd == "fail:post-grant" or cmd == "fail:post-destroy" then
			Fault = cmd:sub(6)
			print(("[PetHatchService] dev: the next real hatch stops at %s"):format(Fault))
		elseif cmd:sub(1, 6) == "hatch:" and player then
			local eggName, forced = cmd:sub(7):match("^([^:]+):?(.*)$")
			local pool = eggName and Catalog.PoolOf(eggName)
			if not pool then print("[PetHatchService] dev: no pet pool for egg " .. tostring(eggName)) return end
			local pet = forced ~= "" and pool[forced] and forced or Catalog.Roll(eggName, Rng)
			DevGrant(player, eggName, pet, true)
		elseif cmd:sub(1, 6) == "spawn:" and player then
			local pet = cmd:sub(7)
			local eggName = EggOfPet(pet)
			if not eggName then print("[PetHatchService] dev: unknown pet " .. pet) return end
			DevGrant(player, eggName, pet, false)
		end
	end)
end

print(("[PetHatchService] ready: %d egg pools, pet ownership by %s"):format((function() local n = 0 for _ in pairs(Catalog.EGGS) do n += 1 end return n end)(),
	GetPetService() and "PetService" or "NOTHING - ServerStorage.PetService is missing, eggs cannot hatch"))
