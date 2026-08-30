--[[
	SmashEventService
	CUCUMBER SMASH: a biome event in the standard rotation (declared in
	BiomeEventRegistry with MinPlayersInBiome = 2, Duration = 90 and
	EffectModule = "SmashEventService"). BreakablesService owns the whole
	lifecycle — selector, admin StartEvent/StopEvent, meter attributes, the
	biome travel popup and the auto-expiry — and toggles this module through
	SetZoneEventActive(zoneName, enabled). Several biomes can run their own
	smash at once; each keeps an independent scoreboard.

	While a zone's smash runs, every cucumber broken IN THAT ZONE gives +1
	smash to every damager (mirrors TotalBreaks; hooked in
	BreakablesService.Break via RecordBreak(plr, data.Zone)). The boss bar
	renders the custom display (time left + YOUR smashes) straight from the
	zone's meter attributes plus a per-zone local score attribute
	("SmashScore_<zone>") that SmashEventClient maintains from the
	SmashEventZoneState / SmashEventScore network events.

	When a zone's event ends (expiry or admin stop), that zone's top 3 (plus
	each player's own rank/score) go to every client for the
	StarterGui.SmashLeaderboard podium, and podium rewards pay out:
	  1st  = the portal-minigame reward spinner (MinigameCompletionToken +
	         MinigameEffects.Completed; MinigameCompletionService grants).
	  2nd/3rd = RUNNERUP_SECONDS of their own production as plain cucumbers
	         via TimeSkipRateService.Quote (the message names only the amount).

	Dev hooks: workspace StartEventDev = "Biome:CucumberSmash" starts one for
	real (BreakablesService); workspace SmashEventDemo = true (Studio) pushes
	a fake podium to preview the leaderboard UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")

local SmashEventService = {}

local ZoneEvents = {} -- [zoneName] = {Scores = {[player] = smashes}}

function SmashEventService.RecordBreak(Player, Zone)
	local zoneEvent = ZoneEvents[Zone]
	if not zoneEvent then return end
	if not Player or Player.Parent ~= Players then return end
	local n = (zoneEvent.Scores[Player] or 0) + 1
	zoneEvent.Scores[Player] = n
	Network:FireClient(Player, "SmashEventScore", Zone, n)
end

--.. Runner-up prize: this many seconds of the player's own production, quoted
--.. by TimeSkipRateService exactly like the reward spinner's cucumber cards.
--.. The notification deliberately names only the amount, never the mechanism.
local RUNNERUP_SECONDS = 5 * 60
local WINNER_SPINNER_DELAY = 4 -- seconds of podium screen before the confetti/spinner takes over

local function GrantProductionCucumbers(plr, seconds, prefix)
	local ok, err = pcall(function()
		local ServerController = require(ServerStorage.ServerController)
		local TimeSkipRateService = ServerController.GetModule("TimeSkipRateService")
		local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
		local NumberController = ControllerLoader.GetController("NumberController")
		--.. WasPurchase mirrors the spinner's cucumber grant: the quote is already
		--.. fully multiplier-adjusted, so no further boosts may re-apply
		local amount = math.max(1, math.floor(TimeSkipRateService.Quote(plr, seconds)))
		CurrencyHandler.AddCurrency({
			Player = plr; Currency = "Cucumbers"; HasTotal = true;
			Amount = amount; WasPurchase = true;
		})
		Network:FireClient(plr, "Notif", {
			Message = ("%s +%s CUCUMBERS!"):format(prefix, NumberController.SuffixNumber(amount));
			Type = "Success";
		})
	end)
	if not ok then
		warn("[SmashEventService] podium cucumber grant failed:", err)
	end
end

local function GrantPodiumRewards(ranked)
	--.. 1st place: the exact portal-minigame celebration -- confetti, then the
	--.. reward spinner. Same token contract as StarterPortalService: arm
	--.. MinigameCompletionToken and fire MinigameEffects.Completed; the existing
	--.. MinigameCompletionClient + MinigameCompletionService do all the rest.
	local winner = ranked[1] and ranked[1].Player
	if winner and winner.Parent == Players then
		task.spawn(function()
			task.wait(WINNER_SPINNER_DELAY) -- let the podium land before the confetti
			--.. never overwrite a spinner already mid-flight from a portal run
			--.. (or a smash that ended moments earlier in another biome): that
			--.. would orphan its secured reward. Wait for it to finish first.
			local deadline = os.clock() + 30
			while winner.Parent == Players and os.clock() < deadline
				and winner:GetAttribute("MinigameCompletionToken") ~= nil do
				task.wait(1)
			end
			if winner.Parent ~= Players then return end
			local effects = ReplicatedStorage:FindFirstChild("MinigameEffects")
			local completed = effects and effects:FindFirstChild("Completed")
			if completed and winner:GetAttribute("MinigameCompletionToken") == nil then
				local token = HttpService:GenerateGUID(false)
				winner:SetAttribute("MinigameCompletionFinished", nil)
				winner:SetAttribute("MinigameCompletionToken", token)
				completed:FireClient(winner, token)
			else
				--.. spinner unavailable (still busy / remote missing): pay double
				--.. the runner-up quote so first never trails second
				GrantProductionCucumbers(winner, RUNNERUP_SECONDS * 2, "\u{1F3C6} 1ST PLACE!")
			end
		end)
	end

	for place = 2, 3 do
		local plr = ranked[place] and ranked[place].Player
		if plr and plr.Parent == Players then
			GrantProductionCucumbers(plr, RUNNERUP_SECONDS,
				place == 2 and "\u{1F948} 2ND PLACE!" or "\u{1F949} 3RD PLACE!")
		end
	end
end

local function FinishZoneEvent(zoneName, zoneEvent)
	local ranked = {}
	for plr, score in pairs(zoneEvent.Scores) do
		if score > 0 and plr.Parent == Players then
			table.insert(ranked, {Player = plr; Score = score;})
		end
	end
	table.sort(ranked, function(a, b) return a.Score > b.Score end)

	local top = {}
	for i = 1, math.min(3, #ranked) do
		top[i] = {
			Name = ranked[i].Player.Name;
			DisplayName = ranked[i].Player.DisplayName;
			Score = ranked[i].Score;
		}
	end
	local rankOf = {}
	for i, entry in ipairs(ranked) do
		rankOf[entry.Player] = i
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		Network:FireClient(plr, "SmashEventResults", {
			Zone = zoneName;
			Top = top;
			You = {Rank = rankOf[plr]; Score = zoneEvent.Scores[plr] or 0;};
			Participants = #ranked;
		})
	end

	if top[1] then
		Network:FireAllClients("Notif", {
			Message = ("\u{1F3C6} %s WON CUCUMBER SMASH!"):format(
				top[1].Name, zoneName:upper(), top[1].Score);
			Type = "Success";
		})
	end

	GrantPodiumRewards(ranked)
end

--.. BreakablesService.SetEventEffect calls this on every start/end path
--.. (goal-fill start, admin start, expiry, admin stop, admin overwrite).
function SmashEventService.SetZoneEventActive(zoneName, enabled)
	if enabled then
		ZoneEvents[zoneName] = {Scores = {}}
		Network:FireAllClients("SmashEventZoneState", zoneName, true)
	else
		local zoneEvent = ZoneEvents[zoneName]
		ZoneEvents[zoneName] = nil
		Network:FireAllClients("SmashEventZoneState", zoneName, false)
		if zoneEvent then
			FinishZoneEvent(zoneName, zoneEvent)
		end
	end
end

local function SendDemoResults()
	--.. Studio-only UI preview: fabricated podium + a mid-table "you"
	Network:FireAllClients("SmashEventResults", {
		Zone = "Spawn";
		Top = {
			{Name = "CucumberKing"; DisplayName = "CucumberKing"; Score = 842;};
			{Name = "PickleRick"; DisplayName = "PickleRick"; Score = 617;};
			{Name = "VineVandal"; DisplayName = "VineVandal"; Score = 409;};
		};
		You = {Rank = 7; Score = 128;};
		Participants = 12;
	})
end

function SmashEventService.Initialize()
	Players.PlayerRemoving:Connect(function(Player)
		for _, zoneEvent in pairs(ZoneEvents) do
			zoneEvent.Scores[Player] = nil
		end
	end)

	workspace:GetAttributeChangedSignal("SmashEventDemo"):Connect(function()
		if workspace:GetAttribute("SmashEventDemo") and RunService:IsStudio() then
			workspace:SetAttribute("SmashEventDemo", nil)
			SendDemoResults()
		end
	end)
end

return SmashEventService
