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
]]

--..Services..--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
	Base = {Version = 1, Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}}, -- what stands on the plot (BaseSaveService, 2026-09-12)
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
	PlaytimeBase[player] = {At = os.clock(), Value = 0}
	local values = Values[player]
	if values then
		for key, object in pairs(values) do object.Value = data[key] or 0 end
	end
	DataService.RequestSave(player)
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
end

local function OnPlayerAdded(player)
	local profile = Store:StartSessionAsync(PROFILE_KEY:format(player.UserId), {
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
	if profile then profile:EndSession() end -- final save
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
