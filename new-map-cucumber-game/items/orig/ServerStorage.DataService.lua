--[[
	DataService  (ModuleScript, ServerStorage)
	Player data on ProfileStore (loleris' successor to ProfileService: session
	locking, periodic auto-save, save on leave / shutdown, Studio mock when
	"Enable Studio Access to API Services" is off).

	Saved template (profile.Data):  Cash, Playtime (seconds, all sessions), Strength,
	PlotLevel, Upgrades. (Cukes was removed on 2026-09-06 -- user; the old key is dropped
	from every profile when it loads, so the store forgets it on the next save.)

	Every loaded player gets  player.Data  (a Folder, NOT leaderstats, so nothing
	shows on the playerlist) holding NumberValues Cash / Playtime / Strength that
	mirror the profile and replicate to the client for UI.

	Saving: any change to Cash / Strength (or any key except Playtime) is written to
	the DataStore straight away; further changes inside SAVE_DEBOUNCE seconds ride
	the next write (DataStore budget). Playtime rides along with those writes and
	is also auto-saved every AUTO_SAVE_PERIOD seconds and on leave.

	Use from any server Script:
		local DataService = require(game:GetService("ServerStorage"):WaitForChild("DataService"))
		DataService.Increment(player, "Cash", 25)
		DataService.Set(player, "Strength", 0)
		local cash = DataService.Get(player, "Cash")
		local data = DataService.WaitForData(player)      -- yields until the profile is in
		DataService.OnProfileLoaded(function(player, profile) ... end)
		DataService.RequestSave(player)                    -- force a (coalesced) save
		DataService.ResetProfile(player)                   -- everything back to the template (admin reset)
	Writing the value object on the server also saves:
		player.Data.Cash.Value += 25
	quiet = true (the 4th argument of Set / Increment) skips the immediate write: the change rides
	the next save (another key's write, the AUTO_SAVE_PERIOD autosave, or leaving). Use it for
	changes that come every second (the placed-cucumber income, 2026-09-12) so the DataStore does
	not see a write per tick.
	Playtime is advanced by this module once a second; don't write it elsewhere.

	ServerScriptService.DataLoader calls DataService.Start() once.
	The ProfileStore library (ProfileStore.luau) is a child ModuleScript of this module.

	Pet system hooks (2026-09-22):
	  * ServerStorage.PetDataMigration (optional sibling, pcall-required on first use) runs on every
	    loaded profile after Reconcile and BEFORE the profile is exposed (Profiles[player]), and again
	    inside ResetProfile. It gives pets / eggs / cucumbers stable Ids, fills the new pet fields and
	    the six-pet roster; it never touches Base.Version or adds/removes records. A throw is caught:
	    the load continues and GetMigrationReport(player).Failed = true (pets stay inert that session).
	  * DataService.OnBeforeClose(fn(player, profile, reason), order?) - synchronous, non-yielding
	    callbacks run once per profile (ascending order, default 50) right before its final save: on a
	    normal leave (before EndSession, reason "Leave") and from ProfileStore's OnLastSave (shutdown
	    "Shutdown" / takeover "External"), while the plot still stands. IsClosing(player) is true from
	    then on (and during a ProfileStore shutdown).
	  * GetGeneration(player) - a number that changes on every load and every ResetProfile, so stale
	    work started for older data can be dropped. OnProfileReset(fn(player, profile)) - called
	    synchronously at the end of ResetProfile.
	  * TEMPLATE Base.Version is 2 now (BaseSaveService VERSION; new profiles never trip the old
	    version-1 cucumber wipe). PetSchemaVersion / PetRoster are deliberately NOT in the template.
	  * Studio only: ServerStorage attribute PetTestProfileKey = "PetTest" makes sessions use the key
	    PetTest_<UserId> in the same store, so pet tests never touch the real Player_<UserId> profile.
]]

--..Services..--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ProfileStore = require(script:WaitForChild("ProfileStore"))

--..Config..--
local STORE_NAME = "PlayerData_v1" -- bump the suffix to reset everyone (old data stays under the old name)
local PROFILE_KEY = "Player_%d"
local USE_MOCK_IN_STUDIO = false -- true: Studio playtests never touch the live DataStore
local VALUES_FOLDER = "Data"
local PLAYTIME_TICK = 1
local SAVE_DEBOUNCE = 5 -- seconds; a change saves at once, further changes inside this window ride the next write
local AUTO_SAVE_PERIOD = 60 -- seconds; ProfileStore's periodic save (was 300)

local TEMPLATE = {
	Cash = 0,
	Playtime = 0, -- seconds in game across all sessions
	Strength = 0, -- + Strength upgrade level per bench-press rep (GymService)
	GroupGiftClaimed = false, -- one-time Group Frenzy chest reward
	CucumberCollection = {Seen = {}, Families = {}, BestRequired = 0, BestSize = 0, TotalSecured = 0},
	Headbands = {Owned = {}, Equipped = ""}, -- headband shop (HeadbandService): Owned[name] = true
	PlotLevel = 0, -- plot size upgrade level 0..6 (PlotUpgradeService)
	Upgrades = {BenchPress = 1}, -- bench upgrade level (GymService; the old FasterReps key is ignored since 2026-09-06)
	Base = {Version = 2, Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}, -- what stands on the plot (BaseSaveService, 2026-09-12; Version 2 = BaseSave VERSION, 2026-09-22)
	PortalCooldowns = {}, -- [PortalDestination] = server time (unix s) the portal opens again for this player (PortalService, 2026-09-22)
	Defense = {Survived = {}, LastSeen = 0, OfflineRate = 0, Level = 1}, -- zombie defence (ManageService, 2026-09-23): night raids survived per threat level (Survived["<level>"]), last-seen time + cucumber cash/s + threat level for offline earnings
}
local VALUE_ORDER = {"Cash", "Playtime", "Strength"}
local REMOVED_KEYS = {"Cukes"} -- dropped from loaded profiles (removed from the game 2026-09-06)

--..Variables..--
ProfileStore.SetConstant("AUTO_SAVE_PERIOD", AUTO_SAVE_PERIOD)
local Store = ProfileStore.New(STORE_NAME, TEMPLATE)
if USE_MOCK_IN_STUDIO and RunService:IsStudio() then Store = Store.Mock end

local DataService = {}
DataService.Template = TEMPLATE
DataService.StoreName = STORE_NAME

local Profiles = {} -- [player] = profile
local Values = {} -- [player] = {Cash = NumberValue, Playtime = NumberValue, Strength = NumberValue}
local PlaytimeBase = {} -- [player] = {At = os.clock(), Value = saved seconds at load}
local LastSave = {} -- [player] = os.clock() of the last write this module asked for
local SavePending = {} -- [player] = true while a coalesced write is scheduled
local LoadedCallbacks = {}
local Started = false
--.. pet system hooks (2026-09-22)
local BeforeClose = {} -- {Fn, Order, Seq} sorted by Order, then Seq
local BeforeCloseSeq = 0
local ClosedProfiles = setmetatable({}, {__mode = "k"}) -- [profile] = true once its before-close callbacks ran
local Closing = {} -- [player] = true from the before-close flush on
local Generation = {} -- [player] = number (changes on every load / ResetProfile)
local GenerationCounter = 0
local MigrationReports = {} -- [player] = PetDataMigration report of the current data (Failed = true when it threw)
local ResetCallbacks = {}
local MigrationModule = nil -- PetDataMigration table once required; false when the require failed

--..Functions..--
function DataService.GetProfile(player)
	return Profiles[player]
end

function DataService.GetData(player)
	local profile = Profiles[player]
	return profile and profile.Data or nil
end

function DataService.IsLoaded(player)
	return Profiles[player] ~= nil
end

function DataService.WaitForData(player, timeout)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and Profiles[player] == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.GetData(player)
end

local function SaveNow(player)
	local profile = Profiles[player]
	if profile and profile:IsActive() then
		LastSave[player] = os.clock()
		profile:Save() -- immediate UpdateAsync in its own thread
	end
end

--.. write the profile to the DataStore now, or at the end of the current debounce window
function DataService.RequestSave(player)
	if SavePending[player] or not Profiles[player] then return end
	local elapsed = os.clock() - (LastSave[player] or 0)
	if elapsed >= SAVE_DEBOUNCE then
		SaveNow(player)
	else
		SavePending[player] = true
		task.delay(SAVE_DEBOUNCE - elapsed, function()
			SavePending[player] = nil
			SaveNow(player)
		end)
	end
end

function DataService.Get(player, key)
	local data = DataService.GetData(player)
	return data and data[key] or nil
end

--.. quiet: no write of its own - the profile is updated (and the value object, whose Changed hook
--.. sees the profile already matching and stays silent) and the change rides the next save
function DataService.Set(player, key, value, quiet)
	local data = DataService.GetData(player)
	if not data then return false end
	data[key] = value
	local values = Values[player]
	local object = values and values[key]
	if object and object.Value ~= value then object.Value = value end
	if key ~= "Playtime" and not quiet then DataService.RequestSave(player) end
	return true
end

function DataService.Increment(player, key, delta, quiet)
	local current = DataService.Get(player, key)
	if current == nil then return false end
	return DataService.Set(player, key, current + (delta or 1), quiet)
end

--.. pet data migration (2026-09-22): ServerStorage.PetDataMigration is optional (staged installs).
--.. Absent -> skipped, report {Error = "NoModule"}; a require or Migrate error -> {Failed = true} + warn
--.. (the load goes on, pets stay inert for that profile). Never yields.
local function NewId()
	return HttpService:GenerateGUID(false)
end

local function GetMigration()
	if MigrationModule == nil then
		local module = script.Parent and script.Parent:FindFirstChild("PetDataMigration")
		if not module then return nil, "NoModule" end -- not installed: looked up again on the next load
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" and type(result.Migrate) == "function" then
			MigrationModule = result
		else
			MigrationModule = false
			warn("[DataService] PetDataMigration could not be loaded - pets stay inert: " .. tostring(result))
		end
	end
	if MigrationModule then return MigrationModule end
	return nil, "RequireFailed"
end

local function RunMigration(player, data, reason)
	local migration, problem = GetMigration()
	if not migration then
		return {Error = problem, Failed = problem ~= "NoModule" or nil}
	end
	local ok, report = pcall(migration.Migrate, data, {GenerateId = NewId, Now = os.time(), Scope = "All"})
	if not ok then
		warn(("[DataService] pet data migration (%s) failed for %s - pets stay inert: %s")
			:format(reason, player.Name, tostring(report)))
		return {Failed = true, Error = tostring(report)}
	end
	return type(report) == "table" and report or {Error = "NoReport"}
end

--.. before-close callbacks (2026-09-22): fn(player, profile, reason) runs once per profile right before
--.. its final save, while the plot still stands. fn must NOT yield. Ascending order (default 50), then
--.. registration order. Registering while profiles are already closing is fine (no replay).
function DataService.OnBeforeClose(fn, order)
	if type(fn) ~= "function" then return end
	if type(order) ~= "number" or order ~= order or order == math.huge or order == -math.huge then order = 50 end
	BeforeCloseSeq += 1
	table.insert(BeforeClose, {Fn = fn, Order = order, Seq = BeforeCloseSeq})
	table.sort(BeforeClose, function(a, b)
		if a.Order ~= b.Order then return a.Order < b.Order end
		return a.Seq < b.Seq
	end)
end

local function RunBeforeClose(player, profile, reason)
	if ClosedProfiles[profile] then return end -- leave + OnLastSave: only the first one runs
	ClosedProfiles[profile] = true
	Closing[player] = true
	for _, entry in ipairs(table.clone(BeforeClose)) do
		local ok, err = pcall(entry.Fn, player, profile, reason)
		if not ok then
			warn(("[DataService] before-close callback (order %s, %s) failed for %s: %s")
				:format(tostring(entry.Order), tostring(reason), player.Name, tostring(err)))
		end
	end
end

function DataService.IsClosing(player)
	return Closing[player] == true or ProfileStore.IsClosing == true
end

function DataService.GetGeneration(player)
	return Generation[player]
end

--.. fn(player, profile): called synchronously (pcall each, registration order) at the end of ResetProfile
function DataService.OnProfileReset(fn)
	if type(fn) == "function" then table.insert(ResetCallbacks, fn) end
end

--.. the PetDataMigration report of the player's current data (load, or the last ResetProfile)
function DataService.GetMigrationReport(player)
	return MigrationReports[player]
end

--.. the whole profile back to the template (admin panel "Reset data", 2026-09-12): the value objects
--.. follow, Playtime restarts from zero, and the write goes out at once. Callers empty the plot themselves.
local function DeepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = DeepCopy(v) end
	return copy
end
function DataService.ResetProfile(player)
	local profile = Profiles[player]
	if not profile then return false end
	local data = profile.Data
	for key in pairs(data) do data[key] = nil end
	for key, value in pairs(TEMPLATE) do data[key] = DeepCopy(value) end
	MigrationReports[player] = RunMigration(player, data, "reset") -- 2026-09-22: fresh ids/roster fields
	GenerationCounter += 1
	Generation[player] = GenerationCounter
	PlaytimeBase[player] = {At = os.clock(), Value = 0}
	local values = Values[player]
	if values then
		for key, object in pairs(values) do object.Value = data[key] or 0 end
	end
	DataService.RequestSave(player)
	for _, fn in ipairs(table.clone(ResetCallbacks)) do -- 2026-09-22: pets / income drop their old state
		local ok, err = pcall(fn, player, profile)
		if not ok then warn(("[DataService] reset callback failed for %s: %s"):format(player.Name, tostring(err))) end
	end
	return true
end

function DataService.OnProfileLoaded(callback)
	table.insert(LoadedCallbacks, callback)
	for player, profile in pairs(Profiles) do
		task.spawn(callback, player, profile)
	end
end

local function BuildValues(player, data)
	local folder = Instance.new("Folder")
	folder.Name = VALUES_FOLDER
	local map = {}
	for _, key in ipairs(VALUE_ORDER) do
		local object = Instance.new("NumberValue")
		object.Name = key
		object.Value = data[key] or 0
		object.Parent = folder
		map[key] = object
		--.. server-side writes to the value object are the same as DataService.Set
		object.Changed:Connect(function(newValue)
			local live = DataService.GetData(player)
			if live and live[key] ~= newValue then
				live[key] = newValue
				if key ~= "Playtime" then DataService.RequestSave(player) end
			end
		end)
	end
	Values[player] = map
	folder.Parent = player
end

local function Forget(player)
	Profiles[player] = nil
	Values[player] = nil
	PlaytimeBase[player] = nil
	LastSave[player] = nil
	SavePending[player] = nil
	Closing[player] = nil
	Generation[player] = nil
	MigrationReports[player] = nil
end

local function ProfileKey(player) -- 2026-09-22: Studio tests can run on an isolated key (ServerStorage attr PetTestProfileKey)
	if RunService:IsStudio() then
		local prefix = ServerStorage:GetAttribute("PetTestProfileKey")
		if type(prefix) == "string" and prefix:match("^[%w_]+$") and #prefix <= 40 then
			warn(("[DataService] STUDIO TEST PROFILE: using key %s_%d (not the real profile)"):format(prefix, player.UserId))
			return ("%s_%d"):format(prefix, player.UserId)
		end
	end
	return PROFILE_KEY:format(player.UserId)
end
DataService.ProfileKeyOf = ProfileKey

local function OnPlayerAdded(player)
	local profile = Store:StartSessionAsync(ProfileKey(player), {
		Cancel = function() return player.Parent ~= Players end,
	})
	if profile == nil then
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	for _, key in ipairs(REMOVED_KEYS) do
		if profile.Data[key] ~= nil then profile.Data[key] = nil end
	end
	MigrationReports[player] = RunMigration(player, profile.Data, "load") -- 2026-09-22: before exposure; never yields
	profile.OnSessionEnd:Connect(function()
		Forget(player)
		if player.Parent == Players then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	--.. 2026-09-22: shutdown ("Shutdown") / takeover ("External") final saves flush like a leave does
	profile.OnLastSave:Connect(function(reason) RunBeforeClose(player, profile, reason) end)
	GenerationCounter += 1
	Generation[player] = GenerationCounter
	Profiles[player] = profile
	LastSave[player] = os.clock()
	PlaytimeBase[player] = {At = os.clock(), Value = profile.Data.Playtime or 0}
	BuildValues(player, profile.Data)
	for _, callback in ipairs(LoadedCallbacks) do
		task.spawn(callback, player, profile)
	end
end

local function OnPlayerRemoving(player)
	local profile = Profiles[player]
	if profile then
		RunBeforeClose(player, profile, "Leave") -- 2026-09-22: flush pets / income / base while the plot still stands
		profile:EndSession() -- final save
	end
	Forget(player)
end

function DataService.Start()
	if Started then return DataService end
	Started = true
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(OnPlayerAdded, player)
	end
	--.. Playtime: exact elapsed seconds since load on top of the saved total
	task.spawn(function()
		while true do
			task.wait(PLAYTIME_TICK)
			for player, base in pairs(PlaytimeBase) do
				if Profiles[player] then
					DataService.Set(player, "Playtime", base.Value + math.floor(os.clock() - base.At))
				end
			end
		end
	end)
	return DataService
end

return DataService
