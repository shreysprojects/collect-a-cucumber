--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local FrameworkLoader = require(ReplicatedStorage.Modules.FrameworkLoader)
--..
local PetStats = ServerController.GetDictionary("Pets").Stats
--..
local PetService
local ProfileService = ServerController.GetModule("ProfileService")
local CurrencyHandler = ServerController.GetModule("CurrencyHandler")task.wait(.5)
local Network = ControllerLoader.GetController("Network")
local FastWait = ControllerLoader.GetController("FastWait")
local ProductController = ControllerLoader.GetController("ProductController")
local SettingsController = ControllerLoader.GetController("SettingsController")

--..
local EggStats = ServerController.GetDictionary("Eggs").Stats

--..Variables..--


local EggService = {
    PlayersOpening = {};
    EggGroups = {};
    TypeData = {
        ["Single"] = {
            Amount = 1;
            Price = function(Price)
                return Price
            end,
        };
        ["Triple"] = {
            Amount = 3;
            Price = function(Price)
                return Price * 3 --.. three eggs hatched = three times the coin price
            end,
        };
        ["Instant"] = {
            Amount = 1;
            Price = function(Price)
                return Price
            end,
        };
	};
	Claimables = {};
	PendingClaims = {}; -- [RequestId] = Player, so ValidateSetting can verify the responder
}
local PlayersOpening = EggService.PlayersOpening
local TypeData = EggService.TypeData

local EGG_REQUIRED_ZONE = {
	["Basic Egg"] = "Spawn";
	["Desert Egg"] = "Desert";
	["Samurai Egg"] = "Samurai";
	["Farm Egg"] = "Farm";
	["Frozen Egg"] = "Snow";
	["Ocean Egg"] = "Underwater";
	["Lava Egg"] = "Volcano";
	["Narmek Egg"] = "Narmek";
}
local AreaNoticeAt = setmetatable({}, {__mode = "k"})

local function HasAreaUnlocked(Player, EggName)
	local RequiredZone = EGG_REQUIRED_ZONE[EggName]
	if not RequiredZone then return true end

	local Profile = ProfileService.GetUserData(Player)
	if not Profile then return false end
	for _, OwnedZone in ipairs(string.split(Profile.DoorData or "Spawn", " # ")) do
		if OwnedZone == RequiredZone then
			return true
		end
	end

	-- Auto-hatch or rapid clicks must not flood the notification rail.
	local Now = os.clock()
	if Now - (AreaNoticeAt[Player] or 0) >= 1 then
		AreaNoticeAt[Player] = Now
		Network:FireClient(Player, "Notif", {
			Message = "AREA LOCKED!";
			Type = "Error";
		})
	end
	return false
end

--..Functions..--
function EggService.GetEggFromRegionPart(Player, RegionPart)
    if EggService.EggGroups then
        for _,Egg in next, game.Workspace.Eggs:GetChildren() do
            if RegionPart:IsDescendantOf(Egg) then
                return Egg
            end
        end
    end
end

function EggService.CheckPlayerRegion(Player, Egg)
    local char = Player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end -- mid-respawn (e.g. right after a rebirth)

    local Parameters = RaycastParams.new()
    Parameters.FilterType = Enum.RaycastFilterType.Whitelist
    Parameters.FilterDescendantsInstances = EggService.EggGroups
    Parameters.IgnoreWater = true

    local raycastResult = workspace:Raycast(hrp.Position, hrp.CFrame.LookVector - Vector3.new(0,10,0), Parameters)

    if raycastResult then

        local EggModel = EggService.GetEggFromRegionPart(Player, raycastResult.Instance)
        if EggModel and EggModel.Name == Egg then
            return true
        else
            return false
        end
    else
        return false
    end
end

local PITY_LIMIT = 25

local function GetRarestPet(Pets)
	local RarestName, RarestPercent
	for Pet, t in next, Pets do
		if RarestPercent == nil or t.Percent < RarestPercent then
			RarestName = Pet
			RarestPercent = t.Percent
		end
	end
	return RarestName
end

--.. rarity tiers ascending; a new player's first pet must land at Rare or above
local RARITY_ORDER = {
	Common = 1;
	Uncommon = 2;
	Rare = 3;
	Legendary = 4;
	Omega = 5;
	Mythical = 6;
	Special = 7;
}
local MIN_FIRST_PET_RARITY = RARITY_ORDER.Rare

local function IsAtLeastRare(PetName)
	local Stats = PetStats[PetName]
	local Order = Stats and RARITY_ORDER[Stats.Rarity]
	return Order ~= nil and Order >= MIN_FIRST_PET_RARITY
end

--.. weighted pick among only the Rare-or-better pets in an egg (nil if it has none)
local function SelectRareOrBetter(Pets)
	local Total = 0
	for Pet, t in next, Pets do
		if IsAtLeastRare(Pet) then
			Total = Total + t.Percent
		end
	end
	if Total <= 0 then return nil end
	local Roll = math.random() * Total
	local Counter = 0
	for Pet, t in next, Pets do
		if IsAtLeastRare(Pet) then
			Counter = Counter + t.Percent
			if Counter >= Roll then
				return Pet
			end
		end
	end
end

local function SelectPets(Player, Egg, GuaranteeRare)
    local Egg = EggStats[Egg]
    local Pets = Egg.Pets
    local totalpercent = 0

    for _,PetInEgg in next, Pets do
        totalpercent = totalpercent + PetInEgg.Percent
    end
    --.. FLOAT roll (2026-08-23): the old integer math.random(1, total) silently
    --.. broke every fractional-percent pet -- a 0.01% entry's REAL odds depended on
    --.. where its slice landed in the (arbitrary) iteration order, not on its number.
    --.. Demon Dog / Cosmo Cat / Gregory only have honest odds with a float roll.
    local randompet = math.random() * totalpercent

	--.. pick by weight
	local Chosen
	local counter = 0
	for Pet,t in next, Pets do
		counter = counter + t.Percent
		if counter >= randompet then
			Chosen = Pet
			break
		end
	end
	--.. float-edge safety: if accumulation error left Chosen nil, take any pet
	if not Chosen then
		for Pet in next, Pets do Chosen = Pet break end
	end

	--.. brand-new player's first-ever Basic Egg pet is guaranteed at least Rare
	local Guaranteed = GuaranteeRare == true
	if Guaranteed and not IsAtLeastRare(Chosen) then
		local Boosted = SelectRareOrBetter(Pets)
		if Boosted then
			Chosen = Boosted
		else
			Guaranteed = false -- egg has no rare-or-better pets to give
		end
	end

	--.. pity: the rarest pet in this egg is guaranteed within PITY_LIMIT hatches
	local Rarest = GetRarestPet(Pets)
	local profile = ProfileService.GetUserData(Player)
	if profile then
		if Chosen ~= Rarest and (profile.EggPity or 0) + 1 >= PITY_LIMIT then
			Chosen = Rarest
		end
		if Chosen == Rarest then
			profile.EggPity = 0
		else
			profile.EggPity = (profile.EggPity or 0) + 1
			local Left = PITY_LIMIT - profile.EggPity
			if Left > 0 and profile.EggPity % 5 == 0 then
				Network:FireClient(Player, "Notif", {Message = ("RAREST PET GUARANTEED IN %d HATCHES!"):format(Left); Type = "Success";})
			end
		end
	end

	--.. Announce every hatch at 10% chance or rarer in chat. The pity rules
	--.. above still care only about the single rarest pet in the egg.
	local HatchChance = Pets[Chosen] and Pets[Chosen].Percent
	--.. chase-pet paper trail (2026-08-23): sub-0.1% hatches get a named custom event
	--.. so Gregory / Demon Dog / Cosmo Cat rates are auditable against their odds
	if type(HatchChance) == "number" and HatchChance > 0 and HatchChance <= 0.1 then
		pcall(function()
			game:GetService("AnalyticsService"):LogCustomEvent(Player, "SecretHatch_" .. Chosen, 1)
		end)
	end
	if type(HatchChance) == "number" and HatchChance > 0 and HatchChance <= 10 then
		local ChosenStats = PetStats[Chosen]
		Network:FireAllClients(
			"RareHatchChat",
			Player.Name,
			Chosen,
			ChosenStats and ChosenStats.Rarity or "Rare",
			HatchChance
		)
	end

	--.. auto-delete handshake (secured: only the asked player may answer, 5s timeout)
	local GivePet = true
	local RequestId = HttpService:GenerateGUID(false)
	EggService.PendingClaims[RequestId] = Player
	Network:FireClient(Player, 'AutoDelete', RequestId)

	local WaitStart = os.clock()
	repeat task.wait() until EggService.Claimables[RequestId] ~= nil or os.clock() - WaitStart > 5
	local Claim = EggService.Claimables[RequestId]
	if Claim and not Guaranteed then
		local Rarity = PetStats[Chosen].Rarity
		if Rarity == 'Common' and Claim.AutoDeleteCommon then
			GivePet = false
		elseif Rarity == 'Uncommon' and Claim.AutoDeleteUncommon then
			GivePet = false
		elseif Rarity == 'Rare' and Claim.AutoDeleteRare then
			GivePet = false
		end
	end

	if GivePet then
		PetService.AddPetToPlayer({Player = Player; Pet = Chosen})
		--.. EQUIP BEST nudge (2026-08-23): post-tutorial hatches don't auto-equip and
		--.. players may not know. If the new pet's cucumber multi beats the current
		--.. per-pet average, tell them what to do about it. pcall: pure UX, never fatal.
		pcall(function()
			local dict = require(game:GetService("ServerStorage").ServerController.Dictionaries.Pets).Stats
			local newStats = dict[Chosen] and dict[Chosen].Stats
			local pd = Player:FindFirstChild("PlayerData")
			local pets = pd and pd:FindFirstChild("Pets")
			if not (newStats and pets) then return end
			local equipped = pets.Equipped.Value
			local avgMulti = equipped > 0 and ((pets.Multi1.Value - 1) / equipped) or 0
			if newStats.Multi1 and newStats.Multi1 > avgMulti then
				local ControllerLoader = require(game:GetService("ReplicatedStorage").Modules.ControllerLoader)
				ControllerLoader.GetController("Network"):FireClient(Player, "Notif", {
					Message = ("%s IS STRONGER \u{2014} EQUIP IT!"):format(string.upper(Chosen));
					Type = "Success";
				})
			end
		end)
	end

	EggService.Claimables[RequestId] = nil
	EggService.PendingClaims[RequestId] = nil

	return Chosen
end

function EggService.GenerateRandomPet(Player, Egg, Type)
    local PetTable = {};

    --.. a player's very first pet ever (from the Basic Egg) is guaranteed at least Rare
    local FirstEverPet = (Egg == "Basic Egg") and (Player.PlayerData.Pets.Unlocked.Value == "")

    if Type == "Single" or Type == "Instant" then
        PetTable = {SelectPets(Player, Egg, FirstEverPet)}
    elseif Type == "Triple" then
        for i=1,3 do
            table.insert(PetTable, SelectPets(Player, Egg, FirstEverPet and i == 1))
        end

    end

    local Unlocked = Player.PlayerData.Pets.Unlocked

    local UnlockedSet = {}
    for _,Name in ipairs(string.split(Unlocked.Value, "|")) do
        UnlockedSet[Name] = true
    end

    for _,Pet in next, PetTable do
        if not UnlockedSet[Pet] then
            UnlockedSet[Pet] = true
            if Unlocked.Value ~= "" then
                Unlocked.Value = Unlocked.Value.. "|".. Pet
            else
                Unlocked.Value = Pet
            end
        end
    end

    ProfileService.SetStatToProfile(Player, "Unlocked", "PetData", Unlocked.Value)

    return PetTable
end

function EggService.OpenEgg(Player, Egg, Type)
    do
        local EggTable = EggStats[Egg]

        local Price = TypeData[Type].Price(EggTable.Price)

        --.. debounce BEFORE charging, so spam clicks can never double-charge
        if PlayersOpening[Player] ~= nil then
            return {Result = false;}
        end
        PlayersOpening[Player] = {Egg = Egg; Type = Type; Opening = true;}

		if CurrencyHandler.CheckIfEnough({Player = Player; Currency = "Coins"; Amount = Price}) then else
			PlayersOpening[Player] = nil
			--.. (removed) no longer force-opens the coin shop when the player can't afford it
            Network:FireClient(Player, "Notif", {Message = "NOT ENOUGH COINS!"; Type = "Error";})
            return {Result = false;}
        end
        CurrencyHandler.RemoveCurrency(Player, "Coins", Price, "Egg:" .. Egg)
        --.. EggProgression one-time funnel (2026-08-22): the pet-axis twin of
        --.. ZoneProgression -- shows which egg tier players stall at
        pcall(function()
            local TIER = {["Basic Egg"] = 1, ["Desert Egg"] = 2, ["Samurai Egg"] = 3, ["Farm Egg"] = 4, ["Ocean Egg"] = 5, ["Frozen Egg"] = 6, ["Lava Egg"] = 7, ["Narmek Egg"] = 8}
            local s = TIER[Egg]
            if s then
                game:GetService("AnalyticsService"):LogFunnelStepEvent(Player, "EggProgression", nil, s, Egg)
            end
        end)

        --.. success chime only AFTER the debounce + affordability checks: it
        --.. used to fire first, so broke players heard SUCCESS immediately
        --.. followed by the NOT ENOUGH COINS error on every attempt
        Network:FireClient(Player, 'PlaySound', 'Success')

        --.. total progress only counts once you actually paid
        local HatchAmount = TypeData[Type].Amount
        ProfileService.AddStatToProfile(Player, "TotalEggsOpened", "TotalStats", HatchAmount)
        ServerController.GetModule("GoalService").RecordAction(Player, "Hatch", HatchAmount)

        local GeneratedPets = EggService.GenerateRandomPet(Player, Egg, Type)
        PlayersOpening[Player] = nil
        return {Result = true; Pets = GeneratedPets}
    end
end

function EggService.CheckEgg(Player, Egg, Type)
    do
        if Player and Egg and Type then
			if not HasAreaUnlocked(Player, Egg) then
				return {Result = false;}
			end
            local PlayerData = Player:WaitForChild("PlayerData")
            local PetsFolder = PlayerData:WaitForChild("Pets")
            local Inventory = PetsFolder:WaitForChild("Inventory")
            local MaxInventory = PetsFolder:WaitForChild("MaxInventory")
            local InstantReveal = false

            local IsInRegion = EggService.CheckPlayerRegion(Player, Egg)

            if IsInRegion then else return {Result = false;} end

            if Type == "Triple" then
                if ProductController.CheckGamepass(Player, "Triple Egg Hatch", true) then
                    InstantReveal = ProductController.CheckGamepass(Player, "Instant Egg Hatch", false) == true
                else
                    return {Result = false;}
                end

            elseif Type == "Instant" then
                if ProductController.CheckGamepass(Player, "Instant Egg Hatch", true) then else
                    return {Result = false;}
                end

            elseif Type == "Auto" then
                if ProductController.CheckGamepass(Player, "Auto Egg Hatch", true) then
                    InstantReveal = ProductController.CheckGamepass(Player, "Instant Egg Hatch", false) == true
                    if ProductController.CheckGamepass(Player, "Triple Egg Hatch", false) then
                        Type = "Triple"
                    else
                        Type = "Single"
                    end
                else
                    return {Result = false;}
                end

            end

            if Inventory.Value + TypeData[Type].Amount <= MaxInventory.Value then else 
                Network:FireClient(Player, "Notif", {Message = "MAX PET STORAGE"; Type = "Error";})
                return {Result = false;} end

            local Result = EggService.OpenEgg(Player, Egg, Type)
            if type(Result) == "table" and Result.Result and InstantReveal then
                Result.Instant = true
            end
            return Result
        end
    end
    return {Result = false;} -- never return nil: the client indexes .Result
end

function EggService.Initialize()
    coroutine.wrap(function()
        for _,v in next, game.Workspace:FindFirstChild("Eggs"):GetDescendants() do
            if v.Name == "RegionPart" then
                table.insert(EggService.EggGroups, v)
            end
        end
    end)()

    PetService = ServerController.GetModule("PetService")
end

return EggService
