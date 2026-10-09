--[[
	PlaytimeRewards (server)
	-------------------------------------------------------------------
	SESSION-BASED playtime reward ladder. Each reward unlocks after a set
	amount of POST-TUTORIAL playtime THIS SESSION - time only accrues while
	the player is IN GAME and only AFTER they have finished (or skipped)
	the tutorial.

	NOTHING here persists: the timer AND the claim set live in a plain
	server-side table that is created fresh on join and dropped on leave,
	so every rejoin resets the clocks and the whole ladder can be earned
	again. (The old data.PlaytimeRewards profile blob is simply ignored.)

	The 9 rewards:
		1 : 30s   - 2,500 coins (flat, no multipliers)
		2 : 2m    - 1x Food Cuke Egg (hatch reveal)
		3 : 5m    - 10 minutes of the 2x Cucumbers boost
		4 : 10m   - 15 minute time skip
		5 : 18m   - 3x Food Cuke Eggs (hatch reveal)
		6 : 30m   - OP MYSTERY PET: Blazing Pickle (8x multis, 100 dmg)
		7 : 45m   - +1 FREE rebirth (no cost, no reset - RebirthService.GrantFree)
		8 : 1h    - 2 hour time skip
		9 : 1h30m - SUPER OP MYSTERY PET: King Cuke (15x multis, 300 dmg)
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")

--..Config..--
--.. Reward unlock schedule, in SECONDS of post-tutorial SESSION playtime.
local SCHEDULE = {
	30,    -- 1 : 30 seconds
	120,   -- 2 : 2 minutes
	300,   -- 3 : 5 minutes
	600,   -- 4 : 10 minutes
	1080,  -- 5 : 18 minutes
	1800,  -- 6 : 30 minutes
	2700,  -- 7 : 45 minutes
	3600,  -- 8 : 1 hour
	5400,  -- 9 : 1.5 hours
}

local FOOD_EGG = "Food Cuke Egg"

--..Variables..--
local PlaytimeRewards = {}
PlaytimeRewards.Schedule = SCHEDULE

--.. Per-player SESSION state: Sessions[Player] = {Time = 0, Claimed = {}}.
--.. In-memory only - created fresh on join, dropped on leave.
local Sessions = {}
local Debounce = {}

--..Helpers..--

local function getSession(Player)
	local state = Sessions[Player]
	if not state and Player.Parent then
		state = {Time = 0, Claimed = {}}
		Sessions[Player] = state
	end
	return state
end

local function isPostTutorial(Player)
	local pd = Player:FindFirstChild("PlayerData")
	local flag = pd and pd:FindFirstChild("DoneTutorial")
	return flag ~= nil and flag.Value == true
end

--.. Builds the state payload the client panel + reward arrow render from.
local function buildState(Player)
	local state = getSession(Player)
	if not state then return nil end

	local done = isPostTutorial(Player)
	local time = state.Time or 0

	local rewards = {}
	local anyReady = false
	for i, threshold in ipairs(SCHEDULE) do
		local claimed = state.Claimed[i] == true
		local remaining = math.max(0, threshold - time)
		local ready = (not claimed) and time >= threshold
		if ready then anyReady = true end
		rewards[i] = {
			Index = i,
			Threshold = threshold,
			Remaining = remaining,
			Claimed = claimed,
			Ready = ready,
		}
	end

	return {
		DoneTutorial = done,
		Time = time,
		Rewards = rewards,
		AnyReady = anyReady,
	}
end

--.. Opens N Food Cuke Eggs for the player, bypassing the coins/region/gamepass gates by
--.. calling the hatch roller (GenerateRandomPet) directly, and RETURNS the array of hatched
--.. pet names so the client can play the egg-hatch reveal. Synchronous (not task.spawn) so we
--.. capture the rolls; with a live client the internal auto-delete handshake resolves in a frame.
--.. Each open rolls the pool, honours global pity, and adds the pet via AddPetToPlayer
--.. (persist + client "AddPet").
local function openFoodEggs(Player, count)
	local EggService = require(ServerStorage.ServerController.PetService.EggService)
	local hatched = {}
	for _ = 1, count do
		local ok, result = pcall(EggService.GenerateRandomPet, Player, FOOD_EGG, "Single")
		if ok and type(result) == "table" then
			for _, name in ipairs(result) do
				if type(name) == "string" then table.insert(hatched, name) end
			end
		end
	end
	return hatched
end

--.. Returns { Egg, Pets, Instant? } for reveal rewards (client plays the hatch animation;
--.. Instant = true skips the egg phase and pops the pet directly - the Egg name is still
--.. required by the reveal module's guard but is never shown) or `true` when the reward
--.. showed its own feedback. Pets/currency/boost/rebirth payouts all persist through
--.. their own services - only the LADDER is session-scoped.
local function GrantReward(Player, index)
	if index == 1 then
		--.. 2,500 coins FLAT (MultipliersApplied skips the rebirth/boost scaling)
		local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
		CurrencyHandler.AddCurrency({Player = Player; Currency = "Coins"; Amount = 2500; MultipliersApplied = true;})
		Network:FireClient(Player, "Notif", {Message = "\u{1FA99} +2,500 COINS!"; Type = "Success";})
		return true

	elseif index == 2 then
		--.. one Food Cuke Egg -> hatch reveal on the client
		return { Egg = FOOD_EGG, Pets = openFoodEggs(Player, 1) }

	elseif index == 3 then
		--.. 10 minutes of the same 2x Cucumbers boost the shop sells (stacks additively)
		local BoostHandler = ServerController.GetModule("BoostHandler")
		BoostHandler.AddBoost(Player, "2x Cucumbers", 600)
		Network:FireClient(Player, "Notif", {Message = "\u{1F952} 2x CUKES \u{2014} 10 MIN!"; Type = "Success";})
		return true

	elseif index == 4 then
		--.. 15 minute time skip, granted exactly like the shop products
		local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
		local final = TimeSkipRateService.Grant(Player, 900)
		Network:FireClient(Player, "Notif", {Message = ("\u{23F1} +%s \u{2014} 15 MIN SKIP!"):format(NumberController.SuffixNumber(final)); Type = "Success";})
		return true

	elseif index == 5 then
		--.. three Food Cuke Eggs opened at once -> hatch reveal on the client
		return { Egg = FOOD_EGG, Pets = openFoodEggs(Player, 3) }

	elseif index == 6 then
		--.. OP MYSTERY PET: Blazing Pickle (reward-exclusive, not in any egg pool).
		--.. Instant = true -> the client plays the paid-instant-hatch reveal: burst
		--.. particle + reveal UI + 'Pet Reward' SFX with the pet, NO egg phase.
		local PetService = ServerController.GetModule("PetService")
		PetService.AddPetToPlayer({Player = Player; Pet = "Blazing Pickle"})
		Network:FireClient(Player, "Notif", {Message = "\u{1F525} BLAZING PICKLE UNLOCKED!"; Type = "Success";})
		Network:FireOtherClients(Player, "Notif", {Message = ("\u{1F525} %s UNLOCKED THE OP MYSTERY PET!"):format(string.upper(Player.Name)); Type = "Success";})
		return { Egg = FOOD_EGG, Pets = {"Blazing Pickle"}, Instant = true }

	elseif index == 7 then
		--.. +1 FREE rebirth: full bonus, zero cost, no reset (see RebirthService.GrantFree)
		local RebirthService = ServerController.GetModule("RebirthService")
		RebirthService.GrantFree(Player)
		return true

	elseif index == 8 then
		--.. 2 hour time skip
		local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
		local final = TimeSkipRateService.Grant(Player, 7200)
		Network:FireClient(Player, "Notif", {Message = ("\u{23F1} +%s \u{2014} 2 HR SKIP!"):format(NumberController.SuffixNumber(final)); Type = "Success";})
		return true

	elseif index == 9 then
		--.. SUPER OP MYSTERY PET: King Cuke (reward-exclusive, not in any egg pool).
		--.. Instant reveal, same as reward 6.
		local PetService = ServerController.GetModule("PetService")
		PetService.AddPetToPlayer({Player = Player; Pet = "King Cuke"})
		Network:FireClient(Player, "Notif", {Message = "\u{1F451} KING CUKE UNLOCKED!"; Type = "Success";})
		Network:FireOtherClients(Player, "Notif", {Message = ("\u{1F451} %s UNLOCKED THE SUPER OP MYSTERY PET!"):format(string.upper(Player.Name)); Type = "Success";})
		return { Egg = FOOD_EGG, Pets = {"King Cuke"}, Instant = true }
	end
	return nil
end

--.. Studio-only test hook: fast-forward THIS session's timer (never runs live).
function PlaytimeRewards.DebugAddTime(Player, seconds)
	if not game:GetService("RunService"):IsStudio() then return end
	local state = getSession(Player)
	if state then state.Time += seconds end
end

--..Lifecycle..--

function PlaytimeRewards.PlayerJoined(Player)
	--.. fresh session every join: timer at 0, nothing claimed
	Sessions[Player] = {Time = 0, Claimed = {}}
end

function PlaytimeRewards.Initialize()
	--.. Bind remotes FIRST - the accrual while-loop below never returns.
	Network:BindFunctions({
		--.. Full reward state for the client to render + tick down locally.
		GetPlaytimeState = function(Player)
			return buildState(Player)
		end,

		--.. Validated claim. The client sends only the index; the server
		--.. recomputes eligibility from the session Time / Claimed set.
		ClaimPlaytimeReward = function(Player, index)
			if Debounce[Player] then return buildState(Player) end
			Debounce[Player] = true
			task.delay(0.5, function() Debounce[Player] = nil end)

			local state = getSession(Player)
			if not state then return nil end

			index = tonumber(index)
			if not index or not SCHEDULE[index] then
				return buildState(Player)
			end

			if state.Claimed[index] then
				return buildState(Player) -- already claimed this session; no-op
			end
			if not isPostTutorial(Player) then
				Network:FireClient(Player, "Notif", {Message = "FINISH THE TUTORIAL FIRST!"; Type = "Error";})
				return buildState(Player)
			end
			if (state.Time or 0) < SCHEDULE[index] then
				Network:FireClient(Player, "Notif", {Message = "NOT READY YET!"; Type = "Error";})
				return buildState(Player)
			end

			--.. Eligible: mark claimed (this session only) + grant.
			state.Claimed[index] = true
			local granted = GrantReward(Player, index)
			local result = buildState(Player)
			if type(granted) == "table" then
				result.Reveal = granted -- client plays the egg-hatch animation for this claim
			elseif granted == nil then
				Network:FireClient(Player, "Notif", {Message = "CLAIMED!"; Type = "Success";})
			end
			-- granted == true: the reward already showed its own feedback
			return result
		end,
	})

	Players.PlayerRemoving:Connect(function(Player)
		Sessions[Player] = nil -- session state dies with the session
		Debounce[Player] = nil
	end)

	--.. Accrue POST-TUTORIAL session playtime: +1s per real second for every
	--.. online player who has finished the tutorial. In-memory only.
	while true do
		task.wait(1)
		for _, Player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(function()
				if not isPostTutorial(Player) then return end
				local state = getSession(Player)
				if state then
					state.Time += 1
				end
			end)
			if not ok then warn("[PlaytimeRewards]: " .. tostring(err)) end
		end
	end
end

return PlaytimeRewards
