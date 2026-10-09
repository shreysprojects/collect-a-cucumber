--[[
	TutorialProgressServer
	Onboarding funnel analytics + mid-tutorial resume.

	The tutorial client reports each completed step over the TutorialProgress
	RemoteEvent. This script:
	  1) logs it to the Roblox onboarding funnel (Creator dashboard shows the
	     step-by-step drop-off chart for free),
	  2) persists Stats.TutorialStep so a player who quits mid-tutorial resumes
	     from where they left off instead of restarting,
	  3) mirrors the saved step onto a "TutorialStep" player attribute the
	     client reads on join.

	All trust lives server-side, same as the gift servers: steps only count
	while the tutorial is actually running (DoneTutorial false), must arrive
	in increasing order, and are logged at most once per player.

	Funnel steps (LogOnboardingFunnelStepEvent):
	  1 TutorialStarted   2 CaughtCucumber   3 SoldCucumbers   4 BoughtPickaxe
	  5 HatchedEgg        6 EquippedPet   7 StoredInVault   8 LockedVault
	  9 TutorialCompleted (ServerNetwork)
	Skips are logged as custom event "TutorialSkippedAtStep" with the step the
	player was on when they pressed SKIP.

	Also handles "wantcarry" (2026-08-26, bank arc): arms a guaranteed
	cucumber catch on the player's next break by setting the
	TutorialCarryPending attribute, which CarryService.TryAwardFromBreak
	consumes. Server-validated: tutorial running + empty hands.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local AnalyticsService = game:GetService("AnalyticsService")

local ProfileService = require(ServerStorage.ServerController.ProfileService)
local ServerController = require(ServerStorage.ServerController)

local STEP_NAMES = {
	[1] = "TutorialStarted";
	[2] = "CaughtCucumber"; -- was HitCucumber; step 1 now ends on an arm catch (2026-08-26)
	[3] = "SoldCucumbers";
	[4] = "BoughtPickaxe";
	[5] = "HatchedEgg";
	[6] = "EquippedPet";
	[7] = "StoredInVault";
	[8] = "UpgradedCucumber"; -- 2026-08-26: upgrade-your-cucumber step joined the bank arc
	[9] = "LockedVault";
	[10] = "ReturnedHome"; -- 2026-08-27: TP-back-to-spawn-biome step before the outro
}
local MAX_CLIENT_STEP = 10 -- step 11 (completed) is logged by ServerNetwork's Tutorial handler only

--.. plain RemoteEvent, same pattern as the tutorial gift servers (the Network
--.. framework rejects event names it wasn't registered with)
local remote = ReplicatedStorage:FindFirstChild("TutorialProgress")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "TutorialProgress"
	remote.Parent = ReplicatedStorage
end

local LastLogged = {} -- [player] = highest funnel step logged this session
local SkipLogged = {} -- [player] = true once their skip has been recorded
Players.PlayerRemoving:Connect(function(plr)
	LastLogged[plr] = nil
	SkipLogged[plr] = nil
end)

local function tutorialRunning(plr)
	local pd = plr:FindFirstChild("PlayerData")
	local done = pd and pd:FindFirstChild("DoneTutorial")
	if not done then return false end
	return done.Value == false or plr:GetAttribute("ForceTutorialOnJoin") == true
end

--.. mirror the saved step onto an attribute as soon as the profile is up
--.. (InstanceValues creates PlayerData once the profile has loaded)
local function publishSavedStep(plr)
	task.spawn(function()
		local pd = plr:WaitForChild("PlayerData", 60)
		if not pd then return end
		local ok, step = pcall(function()
			local data = ProfileService.GetUserData(plr)
			return data and data.Stats and tonumber(data.Stats.TutorialStep)
		end)
		plr:SetAttribute("TutorialStep", (ok and step) or 0)
	end)
end
Players.PlayerAdded:Connect(publishSavedStep)
for _, plr in ipairs(Players:GetPlayers()) do publishSavedStep(plr) end

remote.OnServerEvent:Connect(function(plr, kind, value)
	if not tutorialRunning(plr) then return end
	local step = tonumber(value)
	if not step or step ~= math.floor(step) then return end

	if kind == "step" then
		if step < 1 or step > MAX_CLIENT_STEP then return end
		--.. monotonic and once-only: replays/spam can never rewrite the funnel
		if step <= (LastLogged[plr] or 0) then return end
		LastLogged[plr] = step

		pcall(function()
			AnalyticsService:LogOnboardingFunnelStepEvent(plr, step, STEP_NAMES[step])
		end)

		--.. persist for resume -- but never during a forced replay of an
		--.. already-completed tutorial (that run is session-only by design)
		local pd = plr:FindFirstChild("PlayerData")
		local done = pd and pd:FindFirstChild("DoneTutorial")
		if done and done.Value == false then
			pcall(function()
				local data = ProfileService.GetUserData(plr)
				if data and data.Stats and step > (tonumber(data.Stats.TutorialStep) or 0) then
					data.Stats.TutorialStep = step
				end
			end)
		end
		plr:SetAttribute("TutorialStep", math.max(step, plr:GetAttribute("TutorialStep") or 0))

	elseif kind == "wantcarry" then
		--.. bank arc: guarantee the player's next break lands on their arm.
		--.. Mid-tutorial breaks are normally carry-excluded, so without this
		--.. the vault steps could never start. Empty hands only -- a player
		--.. already carrying needs no re-arm.
		local CarryService = ServerController.GetModule("CarryService")
		if not CarryService.Get(plr) then
			plr:SetAttribute("TutorialCarryPending", true)
		end

	elseif kind == "wantupgradecukes" then
		--.. upgrade step (2026-08-26): a fresh player usually can't afford
		--.. their first vault upgrade, so top them up to the cheapest stored
		--.. cucumber's cost ONCE. Validated: tutorial running (gate above),
		--.. stall has a stored upgradable cucumber, one-shot per player.
		if plr:GetAttribute("TutorialUpgradeCukesGranted") then return end
		local VaultService = ServerController.GetModule("VaultService")
		local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
		local cost = VaultService.CheapestUpgradeCost and VaultService.CheapestUpgradeCost(plr)
		if not cost then return end -- nothing stored/upgradable yet; client retries
		plr:SetAttribute("TutorialUpgradeCukesGranted", true)
		local affordable = false
		pcall(function()
			affordable = CurrencyHandler.CheckIfEnough({Player = plr; Currency = "Cucumbers"; Amount = cost;})
		end)
		if not affordable then
			pcall(function()
				CurrencyHandler.AddCurrency({
					Player = plr; Currency = "Cucumbers"; HasTotal = true;
					Amount = cost; WasPurchase = true;
				})
				local Network = require(ReplicatedStorage.Modules.ControllerLoader).GetController("Network")
				Network:FireClient(plr, "Notif", {Message = ("\u{1F381} +%d CUKES!"):format(cost); Type = "Success";})
			end)
		end

	elseif kind == "skip" then
		if SkipLogged[plr] then return end
		SkipLogged[plr] = true
		local at = math.clamp(step, 1, MAX_CLIENT_STEP + 1)
		pcall(function()
			AnalyticsService:LogCustomEvent(plr, "TutorialSkippedAtStep", at)
		end)
	end
end)

print("[TutorialProgressServer] onboarding funnel + resume ready.")
