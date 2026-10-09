--[[
	PetShopGiftServer
	Tutorial-only gift: during the tutorial's "Hatch an egg at the Pet Shop!"
	step, TutorialClient reports arrival at a pet shop and the server grants
	a one-time 2,500 Coins so the player can afford their first hatch.

	All the trust lives server-side: the tutorial must still be running
	(DoneTutorial false), the gift must be unclaimed (profile flag), and the
	player must actually be standing at an egg stand.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local ProfileService = require(ServerStorage.ServerController.ProfileService)

local Network = ControllerLoader.GetController("Network")

local GIFT_AMOUNT = 2500
local RANGE = 20 -- server-side sanity check: must really be at an egg stand

--.. plain RemoteEvent, same pattern as VendorRemotes/GroupJoinRemote (the
--.. Network framework rejects event names it wasn't registered with)
local remote = ReplicatedStorage:FindFirstChild("TutorialPetShopArrived")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "TutorialPetShopArrived"
	remote.Parent = ReplicatedStorage
end

--.. egg stand anchor parts (models in Workspace.Eggs; late additions tracked)
local eggParts = {}
local function trackEgg(model)
	local part = model:FindFirstChild("RegionPart") or (model:IsA("Model") and model.PrimaryPart) or model:FindFirstChildWhichIsA("BasePart", true)
	if part then table.insert(eggParts, part) end
end
local Eggs = workspace:WaitForChild("Eggs")
for _, m in ipairs(Eggs:GetChildren()) do trackEgg(m) end
Eggs.ChildAdded:Connect(trackEgg)

local function nearAnyEgg(hrp)
	for _, part in ipairs(eggParts) do
		if part.Parent and (hrp.Position - part.Position).Magnitude <= RANGE then
			return true
		end
	end
	return false
end

local Busy = {}
local ToppedUp = {} --.. one replay top-up per session (see below)
local GrantedThisSession = {} --.. normal grant already paid this session
Players.PlayerRemoving:Connect(function(plr) Busy[plr] = nil; ToppedUp[plr] = nil; GrantedThisSession[plr] = nil end)

remote.OnServerEvent:Connect(function(plr)
	if Busy[plr] then return end
	Busy[plr] = true

	pcall(function()
		--.. only DURING the tutorial (the flag flips true on finish/skip)
		local pd = plr:FindFirstChild("PlayerData")
		local done = pd and pd:FindFirstChild("DoneTutorial")
		if not done or done.Value then return end

		local data = ProfileService.GetUserData(plr)
		if type(data) ~= "table" or type(data.Stats) ~= "table" then return end

		--.. Position gate REMOVED (2026-08-23): the funnel showed 45% churn at the
		--.. hatch step. The gift only landed after walking to an egg stand, so players
		--.. comparing their ~300 coins to the 2,500 price BEFORE walking concluded
		--.. "can't afford" and quit -- the gift was a secret. It is still gated on
		--.. tutorial-running + one-time profile flag, which is the real anti-abuse.

		--.. flat gift straight onto leaderstats (the source of truth; the
		--.. profile mirror persists it) so multipliers can't inflate it
		local leaderstats = plr:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		if not coins then return end

		local grant
		if data.Stats.PetShopGiftGiven ~= true then
			grant = GIFT_AMOUNT
			ProfileService.SetStatToProfile(plr, "PetShopGiftGiven", "Stats", true)
			GrantedThisSession[plr] = true
		else
			--.. tutorial REPLAY: the flag saved on an earlier run, yet DoneTutorial
			--.. is false -- the finish-line completion was lost (profile released
			--.. before it saved). These coins fund this step, so a flat "already
			--.. claimed" grind-walled the replay. Top the player back up to the
			--.. gift amount -- no further, and once per session, so idling at the
			--.. stand or rejoin-looping can't be farmed for meaningful coins.
			--.. ...but NEVER in the session that already paid the normal grant:
			--.. the client's 3s retry loop runs until the hatch reveal ends, so
			--.. the retry right after the player SPENDS the gift on the egg used
			--.. to land here and refund the purchase (the "+3k coins after the
			--.. tutorial" bug, fixed 2026-08-26). Spending the gift is not loss.
			if GrantedThisSession[plr] then return end
			grant = GIFT_AMOUNT - coins.Value
			if grant <= 0 or ToppedUp[plr] then return end
			ToppedUp[plr] = true
		end

		coins.Value += grant
		--.. measures the egg-wall fix's reach: compare this count to the HatchedEgg
		--.. funnel step to see if gifted players actually hatch (2026-08-23)
		pcall(function()
			game:GetService("AnalyticsService"):LogCustomEvent(plr, "TutorialEggGiftGiven", 1)
		end)

		Network:FireClient(plr, "Notif", {
			Message = ("🎁 +%s FREE COINS! 🥚"):format(grant == GIFT_AMOUNT and "2,500" or tostring(grant));
			Type = "Success";
		})
	end)

	task.wait(1)
	Busy[plr] = nil
end)

print("[PetShopGiftServer] tutorial pet-shop gift ready.")
