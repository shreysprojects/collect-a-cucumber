--[[
	SellVendorServer
	The Cucumber Vendor NPC at the sell point (Workspace.Points.Sell.Vendor),
	ported from Build a Restaurant's Seed Shop vendor. Walk up -> "Talk"
	prompt -> dialog + sell UI (CucumberVendorClient). Selling converts all
	cucumbers (leaderstats Orbs) into Coins 1:1, exactly like the old
	walk-over sell ring did.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local Network = ControllerLoader.GetController("Network")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
local ProfileService = ServerController.GetModule("ProfileService")
local PetSellValues = require(ReplicatedStorage.Modules.PetSellValues)

local MAX_SELL_BATCH = 50   --.. bounds both the payout per click and the scan cost
local SELL_COOLDOWN = 0.5

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("VendorRemotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "VendorRemotes"
	Remotes.Parent = ReplicatedStorage
end
local function mkRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end
--.. mkRemote only makes RemoteEvents; pet selling needs a RemoteFunction so the
--.. client learns Sold/Coins/Skipped in one round trip.
local function mkFunction(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local OpenSellShop = mkRemote("OpenSellShop") -- server -> client (start dialog)
local SellAll = mkRemote("SellAll")           -- client -> server
local SellCompleted = mkRemote("SellCompleted") -- server -> client (confirmed successful sale)
local SellPets = mkFunction("SellPets")       -- client -> server, returns a result table
local SellCarried = mkFunction("SellCarried") -- client -> server: sell the cucumber on your ARM, returns {Ok, Coins}
--.. ALL of these MUST be created before this script's first yield (the
--.. Workspace:WaitForChild("Points") further down) -- that is the only reason the
--.. client's WaitForChild for them resolves reliably.

----------------------------------------------------------------------
-- Selling
----------------------------------------------------------------------
local Debounce = {}

SellAll.OnServerEvent:Connect(function(Player)
	if Debounce[Player] then return end
	Debounce[Player] = true

	local leaderstats = Player:FindFirstChild("leaderstats")
	if leaderstats then
		local Orbs = leaderstats:FindFirstChild("Cukes")
		if Orbs and Orbs.Value >= 1 then
			local SoldAmount = Orbs.Value
			Network:FireClient(Player, "SellEffect")
			CurrencyHandler.AddCurrency({Player = Player; Currency = "Coins"; HasTotal = true; Amount = SoldAmount;})
			CurrencyHandler.SetCurrency({Player = Player; Currency = "Cucumbers"; Amount = 0;})
			ServerController.GetModule("GoalService").RecordAction(Player, "SellCucumbers", SoldAmount)
			SellCompleted:FireClient(Player)
			--.. quests retired 2026-07-19
		end
	end

	task.wait(1)
	Debounce[Player] = nil
end)

--.. shared cooldown for the RemoteFunction sellers below. Declared HERE, above
--.. both closures that capture it -- a later declaration would be silently
--.. captured as a nil global (the classic Lua upvalue-ordering trap).
local SellCooldown = {}

----------------------------------------------------------------------
-- Selling the CARRIED cucumber ("I have a cucumber to sell", 2026-08-26)
--
-- Sells the cucumber on the player's arm (CarryService carry) at its vault
-- value (CarryService.ValueOf = Rate x 250 -- the green number on the vault
-- display cards). Replaced the dialog's old sell-all-Cukes option; the
-- SellAll remote above stays for the legacy sell window.
----------------------------------------------------------------------
SellCarried.OnServerInvoke = function(Player)
	local now = os.clock()
	if SellCooldown[Player] and now < SellCooldown[Player] then
		return {Ok = false; Reason = "BUSY";}
	end
	SellCooldown[Player] = now + SELL_COOLDOWN

	local CarryService = ServerController.GetModule("CarryService")
	if not CarryService.Get(Player) then
		Network:FireClient(Player, "Notif", {Message = "\u{1F952} NOTHING TO SELL!"; Type = "Error";})
		return {Ok = false; Reason = "EMPTY_HANDS";}
	end
	local record = CarryService.Take(Player)
	if not record then
		return {Ok = false; Reason = "EMPTY_HANDS";}
	end
	local value = CarryService.ValueOf(record)
	if record.Model then record.Model:Destroy() end

	--.. pcall the payout for the same reason SellPets does: AddCurrency fans
	--.. out into other services and must not report a paid sale as a failure
	pcall(CurrencyHandler.AddCurrency, {Player = Player; Currency = "Coins"; HasTotal = true; Amount = value;})
	--.. SFX pass (2026-08-26): ka-ching at the vendor NPC -- 3D so bystanders
	--.. hear the sale; big sales (>50k) ring deeper. The vendor rig is
	--.. re-resolved here: the `vendor` local further down is declared AFTER
	--.. this closure, so it is not an upvalue in this scope.
	pcall(function()
		local SoundController = ControllerLoader.GetController("SoundController")
		local npc = Workspace:FindFirstChild("Points")
		npc = npc and npc:FindFirstChild("Sell")
		npc = npc and npc:FindFirstChild("Vendor")
		local root = npc and npc:FindFirstChild("HumanoidRootPart")
		if root then
			SoundController.PlaySound("Cash Register", root, {
				Volume = 0.6; RollOff = 40;
				Speed = value > 50000 and 0.85 or 1;
			})
		end
	end)
	pcall(function() Network:FireClient(Player, "SellEffect") end)
	SellCompleted:FireClient(Player) -- confirmed-sale signal (the tutorial's sell step listens for this)
	Network:FireClient(Player, "Notif", {
		Message = ("\u{1F4B0} SOLD %s FOR %s COINS!"):format(string.upper(record.Name), tostring(value));
		Type = "Success";
	})
	return {Ok = true; Coins = value; Name = record.Name;}
end

----------------------------------------------------------------------
-- Selling pets
--
-- This is now one of only two places that remove a pet from a profile (the
-- other is EvolveService.DeletePets). PetService.DeletePet was retired
-- 2026-08-04 along with the rest of the pet delete/lock system.
--
-- ProfileService.GetUserData returns the LIVE profile.Data table, so every
-- mutation is permanent the instant it happens and SetStatToProfile is a
-- self-assignment no-op, not a commit barrier. There is no rollback. Hence the
-- shape below, which follows TradeService: cooldown, then a yield-free validate
-- pass with zero mutations, then a yield-free mutation pass that re-checks each
-- entry immediately before nilling it and derives the payout from what was
-- ACTUALLY deleted. Equipped pets are refused (never auto-unequipped: the equip
-- toggle errors when the player has no Character and can leave the multipliers
-- attached).
----------------------------------------------------------------------
SellPets.OnServerInvoke = function(Player, Ids)
	--.. cooldown BEFORE any read
	local now = os.clock()
	if SellCooldown[Player] and now < SellCooldown[Player] then
		return {Ok = false; Reason = "BUSY";}
	end
	SellCooldown[Player] = now + SELL_COOLDOWN

	if type(Ids) ~= "table" then return {Ok = false; Reason = "EMPTY";} end

	--.. resolve the dictionary FIRST: GetDictionary -> CacheDictionary -> require(),
	--.. which can yield on a cold cache. Doing it here keeps everything below strictly
	--.. yield-free. GetDictionary returns the boolean `false` when the module is
	--.. missing (ServerController:146), so `.Stats` on it would throw.
	local Dict = ServerController.GetDictionary("Pets")
	local PetStats = (type(Dict) == "table" and Dict.Stats) or {}

	--.. refuse mid-trade: selling an offered pet cancels the partner's trade
	local TradeService = ServerController.GetModule("TradeService")
	if TradeService and TradeService.IsTrading and TradeService.IsTrading(Player) then
		return {Ok = false; Reason = "IN_TRADE";}
	end

	--.. FindFirstChild, never WaitForChild: nothing below may yield.
	local PlayerData = Player:FindFirstChild("PlayerData")
	local PetsFolder = PlayerData and PlayerData:FindFirstChild("Pets")
	local Inventory = PetsFolder and PetsFolder:FindFirstChild("Inventory")
	local leaderstats = Player:FindFirstChild("leaderstats")
	local CoinsValue = leaderstats and leaderstats:FindFirstChild("Coins")
	local UserData = ProfileService.GetUserData(Player)
	local PetData = UserData and UserData.PetData

	--.. CoinsValue is checked up front so we NEVER delete pets we cannot pay for.
	if not (Inventory and CoinsValue and type(PetData) == "table") then
		return {Ok = false; Reason = "NODATA";}
	end

	--.. PASS 1 -- validate, dedupe, price. ZERO mutations. No yields.
	local approved, seen, skipped = {}, {}, 0
	for i, Id in ipairs(Ids) do
		--.. bound the SCAN, not just the result: a junk array of 50k strings would
		--.. otherwise never trip a `#approved` break.
		if i > MAX_SELL_BATCH or #approved >= MAX_SELL_BATCH then
			--.. everything past the cap is REFUSED and COUNTED, never silently dropped.
			--.. A bare break here would return {Ok=true, Sold=50, Skipped=0} for a
			--.. 100-pet request, and the window closes on success -- so the player would
			--.. never learn the rest did not sell. The client mirrors this cap in
			--.. PET_MAX_SELECT so it normally cannot be reached.
			skipped += (#Ids - i + 1)
			break
		end
		if type(Id) == "string" and Id ~= "Unlocked" and not seen[Id] then
			seen[Id] = true --.. same Id five times pays once
			local Pet = PetData[Id]
			if type(Pet) == "table" and Pet.Name and not Pet.Equipped then
				approved[#approved + 1] = Id
			else
				skipped += 1
			end
		end
	end
	if #approved == 0 then
		return {Ok = false; Reason = "NONE_VALID"; Skipped = skipped;}
	end

	--.. PASS 2 -- mutate. NO wait/task.wait/WaitForChild/EquipPet anywhere in here.
	--.. Re-read and re-check each entry immediately before nilling it, and derive the
	--.. payout from what was ACTUALLY deleted, so the amount paid can never exceed the
	--.. pets removed even if a future edit introduces a yield into pass 1 (EvolveService
	--.. unequips across a yield, so Equipped is not stable -- this recheck closes that).
	local removed, paidTotal = {}, 0
	for _, Id in ipairs(approved) do
		local Pet = PetData[Id]
		if type(Pet) == "table" and Pet.Name and not Pet.Equipped then
			paidTotal += PetSellValues.GetValue(Pet, PetStats[Pet.Name])
			PetData[Id] = nil
			removed[#removed + 1] = Id
		else
			skipped += 1
		end
	end
	if #removed == 0 then
		return {Ok = false; Reason = "NONE_VALID"; Skipped = skipped;}
	end

	--.. ABSOLUTE recompute, never `Inventory.Value -= #removed`. DeletePet is
	--.. client-reachable (ServerNetwork:128-130) and decrements across a yield
	--.. (PetService:100 read, :106 wait(), :108 decrement), so relative arithmetic can
	--.. be raced into permanent drift. Inventory.Value is EggService's hatch capacity
	--.. gate (EggService:388), so drifting low means free pet storage. Inventories are
	--.. ~30-100 entries, so this is cheap and it repairs pre-existing drift too.
	local count = 0
	for id, pet in pairs(PetData) do
		if id ~= "Unlocked" and type(pet) == "table" then count += 1 end
	end
	Inventory.Value = count

	--.. kept for consistency with AddPetToPlayer/TradeService/EvolveService.
	--.. NOTE: a self-assignment no-op, NOT a commit -- GetUserData already returned the
	--.. live profile.Data. There is no rollback; that is exactly why every check above
	--.. happens before the first nil.
	ProfileService.SetStatToProfile(Player, "PetData", nil, PetData)

	--.. `removed` ONLY, never the raw client array. ClientNetwork routes this into
	--.. UserInterfaceLoader.Pets.RemovePetFromInventory, which destroys a tile per Id it
	--.. receives -- echoing refused Ids would erase still-owned pets from the main
	--.. inventory UI until the player rejoins.
	Network:FireClient(Player, "RemovePet", removed)

	--.. pcall the payout: AddCurrency credits at CurrencyHandler:97 but then calls
	--.. SeasonService / OfflineService / VaultService at :106-119. An error in any of
	--.. those would propagate out of this plain RemoteFunction and report an
	--.. already-paid, already-deleted sale to the client as a failure.
	pcall(CurrencyHandler.AddCurrency, {
		Player = Player; Currency = "Coins"; Amount = paidTotal;
		HasTotal = true; MultipliersApplied = true;
	})
	pcall(function() Network:FireClient(Player, "SellEffect") end)

	return {Ok = true; Sold = #removed; Coins = paidTotal; Skipped = skipped;}
end

Players.PlayerRemoving:Connect(function(Player)
	Debounce[Player] = nil
	SellCooldown[Player] = nil
end)

----------------------------------------------------------------------
-- The vendor NPC
----------------------------------------------------------------------
local vendor = Workspace:WaitForChild("Points"):WaitForChild("Sell"):WaitForChild("Vendor")
local promptPart = vendor:WaitForChild("HumanoidRootPart")

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Talk"
prompt.ObjectText = "Cucumber Vendor"
prompt.MaxActivationDistance = 9
prompt.RequiresLineOfSight = false
prompt.Parent = promptPart
prompt.Triggered:Connect(function(player)
	OpenSellShop:FireClient(player)
end)

----------------------------------------------------------------------
-- Idle animation (server-side so every client sees it)
----------------------------------------------------------------------
local ANIM_ID = "rbxassetid://507766388" -- default R15 idle (Roblox-owned)

local humanoid = vendor:FindFirstChildOfClass("Humanoid")
if humanoid then
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = ANIM_ID
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
	end
end

print("[SellVendorServer] Cucumber Vendor ready.")
