--[[
	ManageConfig  (ModuleScript, ReplicatedStorage.Modules)  2026-09-23
	The numbers behind the MANAGE panel (StarterGui.CucumberMenus.ManagePanel: Pets / Cucumbers /
	Zombies tabs), shared by ServerScriptService.ManageService (the authority), the client
	ManageController (display only), CucumberCarry (the placed-cucumber cap) and PetService (the
	active-pet cap). Everything a designer would tune lives here; nothing else hard-codes a number.

	  CAPACITY  "Base upgrades increase your ... capacity": a base holds
	              CucumberCapacity(plotLevel) placed cucumbers  = 10 + 2 per plot level (10 .. 22)
	              PetCapacity(plotLevel)      active pets       = 3 + 1 per plot level, capped at
	              PetBalance.SLOTS (6): 3 / 4 / 5 / 6 / 6 / 6 / 6 for plot levels 0 .. 6.
	            The cucumber cap is enforced at placement only (CucumberCarry.Place: "base full");
	            saved bases restore in full whatever their size. The pet cap is the roster limit
	            PetService hands Core.Equip / GrantFromEgg / EquipBest; a roster that is already
	            bigger (a migrated profile, a plot downgrade) keeps its pets - nothing is ever
	            unequipped for it, new equips just wait for room. Set PET_CAPACITY.Base = 6 to get
	            the flat six slots of the 2026-09-22 pet plan back.
	  SELLING   a pet or a placed cucumber sells for SELL_SECONDS of its own cash/s income
	            (220 s = CucumberValues.EARN_VALUE_PERIOD, "one earn period"), never below the
	            *_SELL_MIN floors. Selling is final: the pet record is deleted, the cucumber model
	            destroyed. Refused during a raid / at night (CombatLocked) like every roster change.
	  OFFLINE   "Survive at this threat level to earn while you are away": once the player has
	            survived OFFLINE.RequiredDays night raids at their CURRENT threat level (the
	            level a raid would be tonight, ZombieAPI.ThreatLevel), leaving stamps that level +
	            the unboosted cucumber cash/s (IncomeService.GetThreatIncome), and the next join pays
	            rate x min(away, MaxSeconds) x Multiplier. Days survived are kept per level
	            (Data.Defense.Survived["<level>"]), so a new threat level needs its own survived
	            day, exactly as the panel says.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))

local M = {}

M.CUCUMBER_CAPACITY = {Base = 10, PerLevel = 2}
M.PET_CAPACITY = {Base = 3, PerLevel = 1, Max = 6} -- Max is raised to PetBalance.SLOTS when that module is present
M.SELL_SECONDS = CucumberValues.EARN_VALUE_PERIOD or 220
M.PET_SELL_MIN = 25
M.CUCUMBER_SELL_MIN = 5
M.OFFLINE = {RequiredDays = 1, Multiplier = 0.5, MaxSeconds = 8 * 3600, MinSeconds = 60}
M.PLOT_MAX_LEVEL = 6

M.REMOTE = "ManageRequest" -- ReplicatedStorage.Remotes.ManageRequest (RemoteFunction, client -> server)
M.STATE_REMOTE = "ManageState" -- ReplicatedStorage.Remotes.ManageState (RemoteEvent, server -> owner: "Refresh" nudges)
M.REQUEST_PER_SECOND = 2 -- per player, all actions together (burst 4)
M.REQUEST_BURST = 4

M.ERRORS = { -- server error code -> what the player reads
	NotLoaded = "Your data is still loading.",
	Closing = "Your data is saving - try again in a moment.",
	CombatLocked = "Finish defending your plot first.",
	NotOwned = "That is not in your base any more.",
	NotFound = "That is not in your base any more.",
	Unavailable = "Not available right now.",
	Busy = "A zombie has hold of that one!",
	RateLimited = "Slow down a little.",
	BadRequest = "Something went wrong.",
	NoPlot = "You need a base for that.",
}

do
	local ok, PetBalance = pcall(function() return require(Modules:WaitForChild("PetBalance", 5)) end)
	local slots = ok and type(PetBalance) == "table" and tonumber(PetBalance.SLOTS) or nil
	if slots and slots == slots and slots >= 1 then M.PET_CAPACITY.Max = math.floor(slots) end
end

local function Level(level)
	level = math.floor(tonumber(level) or 0)
	return math.clamp(level, 0, M.PLOT_MAX_LEVEL)
end

--.. placed cucumbers a base of this plot level holds
function M.CucumberCapacity(plotLevel)
	return M.CUCUMBER_CAPACITY.Base + M.CUCUMBER_CAPACITY.PerLevel * Level(plotLevel)
end

--.. active pets a base of this plot level holds (the roster limit)
function M.PetCapacity(plotLevel)
	return math.min(M.PET_CAPACITY.Max, M.PET_CAPACITY.Base + M.PET_CAPACITY.PerLevel * Level(plotLevel))
end

--.. cash a pet sells for, from its calculated cash/s (PetStats.Calculate(record).Income)
function M.PetSellValue(incomePerSec)
	local income = tonumber(incomePerSec) or 0
	if income ~= income or income < 0 or income == math.huge then income = 0 end
	return math.max(M.PET_SELL_MIN, math.floor(income * M.SELL_SECONDS))
end

--.. cash a placed cucumber sells for: its unboosted cash/s (the Zone / TypeName / Golden / Material /
--.. Mutations / SizeTier attributes CucumberCarry stamps) x SELL_SECONDS
function M.CucumberSellValue(model)
	local rate = 0
	local ok, value = pcall(CucumberValues.RateOfInstance, model)
	if ok and type(value) == "number" and value == value and value < math.huge then rate = math.max(0, value) end
	return math.max(M.CUCUMBER_SELL_MIN, math.floor(rate * M.SELL_SECONDS))
end

--.. cash for an absence: rate (cash/s) x the capped away time x the multiplier -> cash, seconds counted
function M.OfflineEarnings(ratePerSec, awaySeconds)
	local rate = tonumber(ratePerSec) or 0
	local away = tonumber(awaySeconds) or 0
	if rate ~= rate or rate <= 0 or rate == math.huge or away ~= away or away < M.OFFLINE.MinSeconds then return 0, 0 end
	local counted = math.min(away, M.OFFLINE.MaxSeconds)
	return math.floor(rate * counted * M.OFFLINE.Multiplier), counted
end

--.. 1234 -> "$1.23K" (the HUD's green-cash style, NumberAbbrev)
function M.FormatMoney(n)
	return "$" .. NumberAbbrev.Abbrev(math.floor((tonumber(n) or 0) + 0.5))
end

--.. 5400 s -> "1h 30m", 90 -> "1m 30s"
function M.FormatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then return string.format("%dh %dm", h, m) end
	if m > 0 then return string.format("%dm %ds", m, s) end
	return string.format("%ds", s)
end

return M
