--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
local Network = ControllerLoader.GetController("Network")

--..Config..--
local FIRST_TIER_SECONDS = 6 * 60 * 60
local FIRST_TIER_PERCENT = 0.50
local SECOND_TIER_PERCENT = 0.30
local MAX_EQUIVALENT_INCOME_SECONDS = 6 * 60 * 60
-- Was 12 full-rate hours (2026-08-22): with mid-game time-to-next-door around 1-7h,
-- one overnight absence banked up to ~10x the next door's price -- sleeping skipped
-- entire zones. Six pet-rate hours keeps overnight returns exciting without
-- outpacing active play. Six hours at 50% banks three; 30% banks the rest.
local SECOND_TIER_SECONDS = math.ceil(
	(MAX_EQUIVALENT_INCOME_SECONDS - FIRST_TIER_SECONDS * FIRST_TIER_PERCENT) / SECOND_TIER_PERCENT
)
local MAX_OFFLINE = FIRST_TIER_SECONDS + SECOND_TIER_SECONDS
local MIN_OFFLINE = 120 -- ignore absences shorter than this (rejoins, crashes)
local MIN_SESSION_FOR_RATE = 60 -- seconds of play before we trust the session rate
local HEARTBEAT = 30 -- how often we checkpoint rate + LastSeen into the profile

--..Variables..--
local OfflineService = {}

local SessionStart = {} -- [Player] = os.time() when the trusted-rate session began

--..Functions..--

-- Kept for CurrencyHandler compatibility. Offline rates no longer consume raw grants:
-- the unified TimeSkipRateService already filters passive-pet farming and rejects windfalls.
function OfflineService.NoteEarnings()
	return
end

-- Converts actual time away into full-rate-equivalent seconds:
-- 50% for the first six hours, then 30% until twelve hours of income is banked.
function OfflineService.CalculateEarnings(rate, away)
	away = math.clamp(tonumber(away) or 0, 0, MAX_OFFLINE)
	local firstTier = math.min(away, FIRST_TIER_SECONDS)
	local secondTier = math.max(0, away - FIRST_TIER_SECONDS)
	local equivalentSeconds = firstTier * FIRST_TIER_PERCENT + secondTier * SECOND_TIER_PERCENT
	return TimeSkipRateService.QuoteStoredRate(rate, equivalentSeconds, 1)
end

local function Checkpoint(Player)
	local profile = ProfileService.GetUserData(Player)
	if not profile or not profile.OfflineData then return end
	local data = profile.OfflineData

	local start = SessionStart[Player]
	if start then
		local elapsed = os.time() - start
		if elapsed >= MIN_SESSION_FOR_RATE then
			-- PET-ONLY rate (2026-08-22): the vault popup credits your pets, so the
			-- pickaxe clicking rate no longer earns while offline. Same authoritative
			-- model as Time Skips otherwise: highest unlocked zone plus multipliers.
			data.Rate = TimeSkipRateService.GetPetRate(Player)
		end
	end
	data.LastSeen = os.time()
end

--.. Returns the current unclaimed vault amount (client pulls this after loading)
function OfflineService.GetVault(Player)
	local profile = ProfileService.GetUserData(Player)
	if not profile or not profile.OfflineData then return 0 end
	return math.floor(profile.OfflineData.Vault or 0)
end

--.. Banks the vault into real cucumbers. Returns amount granted.
function OfflineService.ClaimVault(Player)
	local profile = ProfileService.GetUserData(Player)
	if not profile or not profile.OfflineData then return 0 end

	local amount = math.floor(profile.OfflineData.Vault or 0)
	if amount < 1 then return 0 end
	profile.OfflineData.Vault = 0

	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	-- WasPurchase skips multipliers (the rate already included them) and season accrual
	CurrencyHandler.AddCurrency({Player = Player; Currency = "Cucumbers"; Amount = amount; WasPurchase = true; HasTotal = true;})

	return amount
end

function OfflineService.PlayerJoined(Player)
	local profile
	for i = 1, 30 do
		profile = ProfileService.GetUserData(Player)
		if profile then break end
		task.wait(1)
	end
	if not profile or not profile.OfflineData then return end
	local data = profile.OfflineData

	--.. Turn time away into vault cucumbers
	if data.LastSeen > 0 and data.Rate > 0 then
		local away = os.time() - data.LastSeen
		if away >= MIN_OFFLINE then
			local earned = OfflineService.CalculateEarnings(data.Rate, away)
			if earned >= 1 then
				data.Vault += earned
			end
		end
	end

	--.. Begin the trusted-rate session. The unified service tracks its own filtered samples.
	SessionStart[Player] = os.time()
	data.LastSeen = os.time()
end

function OfflineService.Initialize()
	Players.PlayerRemoving:Connect(function(Player)
		Checkpoint(Player) -- best effort; heartbeat already got within 30s if profile is gone
		SessionStart[Player] = nil
	end)

	while true do
		task.wait(HEARTBEAT)
		for _,Player in ipairs(Players:GetPlayers()) do
			if SessionStart[Player] then
				Checkpoint(Player)
			end
		end
	end
end

return OfflineService
