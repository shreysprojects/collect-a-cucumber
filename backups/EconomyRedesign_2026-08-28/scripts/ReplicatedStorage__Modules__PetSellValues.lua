--[[
	PetSellValues
	Single shared source of truth for pet sell pricing. Required by BOTH the
	client (CucumberVendorClient, to display a value on each row) and the
	server (SellVendorServer, to pay). One module is what makes "coins awarded
	match what the UI showed" structurally true instead of a convention that
	two files have to independently honour.
]]

local PetSellValues = {}

--.. Coin value per rarity. NOTE: this is a new coin faucet that feeds
--.. SeasonService (CurrencyHandler:106-110) and the global TotalCoins board.
--.. Whoever flips SeasonService.SEASON_ENABLED should re-check these numbers
--.. and MAX_SELL_BATCH in SellVendorServer.
PetSellValues.Values = {
	Common    = 100;
	Uncommon  = 250;
	Rare      = 600;
	Epic      = 1500;   --.. DEFENSIVE: zero pets carry Epic today. It exists in
	                    --.. RarityController.Classes but no Rarity="Epic" appears
	                    --.. in any of the 78 assignments in Dictionaries.Pets.
	Legendary = 3500;
	Special   = 5000;
	Mythical  = 10000;
	Omega     = 25000;
}

PetSellValues.Default = 100          --.. legacy/unknown rarity strings land here
PetSellValues.GoldenMultiplier = 1.5 --.. mirrors PetDefaults' x1.5 stat bonus exactly

--.. PetTable = the saved PetData entry. Definition = the Pets-dictionary entry
--.. for PetTable.Name (may be nil).
--.. Dictionary FIRST: PetService.PlayerJoined re-syncs each owned pet's Stats but
--.. never its Rarity (PetService:257-275 assigns Multi1/Multi2/Damage only), so a
--.. saved Rarity can be stale relative to the live dictionary.
function PetSellValues.ResolveRarity(PetTable, Definition)
	return (Definition and Definition.Rarity)
		or (PetTable and PetTable.Rarity)
		or "Common"
end

--.. returns coins:number, rarity:string
--.. ALWAYS index Values with the Default fallback, never raw: PetDefaults snapshots
--.. Rarity into the save at grant time, so a live profile can hold any rarity string
--.. that EVER shipped in the dictionary, not just today's seven.
function PetSellValues.GetValue(PetTable, Definition)
	local Rarity = PetSellValues.ResolveRarity(PetTable, Definition)
	local Coins = PetSellValues.Values[Rarity] or PetSellValues.Default
	if PetTable and PetTable.Craft == "Golden" then
		Coins = math.floor(Coins * PetSellValues.GoldenMultiplier)
	end
	return Coins, Rarity
end

return PetSellValues
