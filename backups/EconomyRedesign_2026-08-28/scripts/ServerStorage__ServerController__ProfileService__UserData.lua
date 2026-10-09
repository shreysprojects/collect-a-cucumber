--..Services..--


--..Modules..--


--..Variables..--


--..Functions..--

return {

    ["Stats"] = {

        ["Cucumbers"] = 0;
        ["Coins"] = 0;

        ["Radius"] = 7;

        ["DoneTutorial"] = false;
        ["TutorialStep"] = 0; -- last completed onboarding funnel step; lets a mid-tutorial quitter resume instead of restarting
        ["ClaimedGroupPet"] = false;
        ["ClaimedTutorialPet"] = false;
        ["PetShopGiftGiven"] = false; -- one-time 2,500 Coins for first walking up to a pet shop
        ["PickaxeShopGiftGiven"] = false; -- one-time 500 Coins on reaching the tutorial's "buy your next pickaxe" step

        ["Scale"] = 1;

    };
    ["TotalStats"] = {

        ["TotalCucumbers"] = 0;
        ["TotalCoins"] = 0;
        ["TotalTime"] = 0;
        ["TotalEggsOpened"] = 0;
        ["TotalBreaks"] = 0;
        ["GoldenBreaks"] = 0;

    };
    ["ToolData"] = {
        ["Equipped"] = "Wood Pickaxe";
        ["Owned"] = "Wood Pickaxe";
        ["BuyAmount"] = 1;
    };
    ["DoorData"] = "Spawn"; -- "Spawn # Spawn"

    ["Boosts"] = {
        ["2x Cucumbers"] = 0;
    };
    ["BoostTotals"] = {
        ["2x Cucumbers"] = 0;
    };

    ["UsedCodes"] = "";

    ["PetData"] = {
        Unlocked = "";
    };

    ["Chests"] = {};


    ["QuestBoard"] = {};

    ["Upgrades"] = {
        ["Vault slots"] = 0;
        ["Pet equips"] = 0;
        ["Smashes required"] = 0;
    };
	
	["EggPity"] = 0;

	["MaxEquipIncrement"] = 0;
	["MaxPetInventoryIncrement"] = 0;

	["SeasonStats"] = {
		["Season"] = 0;
		["Cucumbers"] = 0;
		["Coins"] = 0;
	};
	["ClaimedSeasonRewards"] = {};
	["GoldenChampion"] = false;

	["Streak"] = {
		["Day"] = 0; -- floor(os.time()/86400) of last claim
		["Count"] = 0;
	};
	["GoalIndex"] = 1; -- first-session goal chain progress
	["GoalProgress"] = {Index = 1; Amount = 0;}; -- action progress for the currently active goal only
	["Rebirths"] = 0;
	["VaultLoot"] = 0; -- skim of earnings sitting in your stealable vault pad
	["VaultCucumbers"] = {}; -- saved vault podium contents: {Spot, Zone, Name, Rate, Level, Rarity, Mutation, Accrued, OfflineCash} per cucumber (VaultService)
	["VaultLastSave"] = 0; -- os.time() of the last vault save; LoadVault turns the gap into offline coins (2026-08-27)
	["IndexClaimed"] = 0; -- pet index milestone rewards taken
	["ColossalShards"] = 0; -- LEGACY single pool (pre per-boss pets). BreakablesService migrates
	-- any leftover into BossShards.Spawn on the next boss kill, then leaves this at 0.
	["BossShards"] = {}; -- [zone] = shards of THAT boss; 10 forge that boss's own pet, repeatable
	["SeenShardHint"] = false; -- first boss shard points at the Shards menu once per account
	["ChosenPath"] = false; -- first-session choose-your-path starter pet
	["SeenStarterOffer"] = false; -- one-time starter pack popup shown
	["SeenGroupOffer"] = false; -- one-time "join GROUP FRENZY for 1.5x cucumbers" popup guaranteed first session
	["SeenFavoritePrompt"] = false; -- native "favourite this game?" prompt shown only on the player's first session

	["PlaytimeRewards"] = { -- claim-based playtime reward ladder (see ServerController.PlaytimeRewards)
		["Time"] = 0; -- accumulated POST-TUTORIAL seconds; counts only while in game, after tutorial
		["Claimed"] = {}; -- claimed reward indices as a set: Claimed[tostring(i)] = true (permanent)
	};

	["OfflineData"] = {
		["LastSeen"] = 0; -- os.time() heartbeat while online
		["Rate"] = 0; -- unified abuse-resistant pet-farming rate saved last session
		["Vault"] = 0; -- unclaimed offline earnings
	};
};
