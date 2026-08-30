--[[
	PickaxeShopGiftServer
	Tutorial-only gift: when the player reaches the tutorial's "Buy your next
	pickaxe!" step (they walk up to the Shopkeeper at the pickaxe shop), the server
	grants a one-time 500 Coins so they can actually afford the pickaxe.

	Deliberately a mirror of PetShopGiftServer -- all the trust lives server-side:
	the tutorial must still be running (DoneTutorial false), the gift must be
	unclaimed (persistent profile flag), and the player must really be standing
	at the pickaxe shop. The client only ever says "I got here"; it never says
	how much to pay out.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local ProfileService = require(ServerStorage.ServerController.ProfileService)

local Network = ControllerLoader.GetController("Network")

local GIFT_AMOUNT = 500
local RANGE = 25 -- server-side sanity check: must really be at the pickaxe shop

--.. plain RemoteEvent, same pattern as TutorialPetShopArrived/VendorRemotes (the
--.. Network framework rejects event names it wasn't registered with)
local remote = ReplicatedStorage:FindFirstChild("TutorialPickaxeShopArrived")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "TutorialPickaxeShopArrived"
	remote.Parent = ReplicatedStorage
end

--.. the pickaxe shopkeeper (same anchor the tutorial client points its arrow at)
local function vendorPart()
	local shopNew = workspace:FindFirstChild("ShopNew")
	local vendor = shopNew and shopNew:FindFirstChild("Vendor")
	return vendor and (vendor:FindFirstChild("Head") or vendor:FindFirstChildWhichIsA("BasePart", true))
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

		local head = vendorPart()
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp or not head then return end
		if (hrp.Position - head.Position).Magnitude > RANGE then return end

		--.. flat gift straight onto leaderstats (the source of truth; the profile
		--.. mirror persists it) so income multipliers can't inflate a fixed gift
		local leaderstats = plr:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		if not coins then return end

		local grant
		if data.Stats.PickaxeShopGiftGiven ~= true then
			grant = GIFT_AMOUNT
			ProfileService.SetStatToProfile(plr, "PickaxeShopGiftGiven", "Stats", true)
			GrantedThisSession[plr] = true
		else
			--.. tutorial REPLAY: the flag saved on an earlier run, yet DoneTutorial
			--.. is false -- the finish-line completion was lost (profile released
			--.. before it saved). These coins fund this step, so a flat "already
			--.. claimed" grind-walled the replay. Top the player back up to the
			--.. gift amount -- no further, and once per session, so idling at the
			--.. shop or rejoin-looping can't be farmed for meaningful coins.
			--.. ...but NEVER in the session that already paid the normal grant:
			--.. the client keeps retrying near the vendor until the purchase
			--.. registers, so a retry racing the buy's replication could land
			--.. here and refund the spent gift (same family as the egg gift's
			--.. "+3k coins after the tutorial" bug, fixed 2026-08-26).
			if GrantedThisSession[plr] then return end
			grant = GIFT_AMOUNT - coins.Value
			if grant <= 0 or ToppedUp[plr] then return end
			ToppedUp[plr] = true
		end

		coins.Value += grant

		Network:FireClient(plr, "Notif", {
			Message = ("\u{1F381} +%d COINS!"):format(grant);
			Type = "Success";
		})
	end)

	task.wait(1)
	Busy[plr] = nil
end)

print("[PickaxeShopGiftServer] tutorial pickaxe-shop gift ready.")
