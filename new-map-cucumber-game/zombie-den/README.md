# Zombie Den deals + co-op nights (2026-09-24)

User request: "make zombie den stuff work - go there it opens zombie den UI - lost a cucumber? get it back by getting
3 of X cucumber and trading it in, user has 12 hours before offer expires. X cucumber is displayed in viewport and
stuff. has to be near attainable or attainable, eg. 1 biome ahead and lower. similar to other frames in game theme
(a new frame). EXTRA: at night people can help each other fight each other's zombies only if they're done their wave,
both users get boosts."

Place: New Map Cucumber Game (place 87967102884366, `instance:yy4-a6j` that session). Everything is LIVE in the
edit DataModel (not saved / published by me).

## The Zombie Den (Map.Lobby.Stations."Zombie Den ")
| Piece | What |
|---|---|
| `StarterGui.CucumberMenus.DenPanel` | the new frame, built by `build_denpanel.lua` (edit mode, idempotent): the Manage panel's Shadow / pink Body / red ribbon ("ZOMBIE DEN") / close X cloned, one scrolling list of deals, a notice bar; `Templates.DenRow` = the Manage cucumber row grown to 1044 x 150 with the LOST cucumber's viewport ("YOURS"), "Get back: <name>", zone / traits / $rate, "They want 3 x <kind> (<biome>)", "Deal ends in 11h 32m", the WANTED kind's viewport with an x3 badge + "<have> / 3 on your base", and the SELL button turned into TRADE IN ("READY!" green / "0 / 3" grey / "BY DAY" at night). Registered in MenuController as `panels.Den` (no HUD opener, like BuyShop). |
| `ReplicatedStorage.Modules.DenConfig` | numbers + pure rules: NEED 3, OFFER_SECONDS 12 h, OPEN/CLOSE radius 14 / 19 studs, `PickWant(lostZone, strength, rng, exclude, lostReward)`, `AttainableZone(strength)`, `Candidates(zone)`, `Countdown`, ERRORS texts. |
| `ServerScriptService.ZombieDenService` | the authority: deals from `Data.LostCucumbers` (ItemService.RecordLoss already writes every theft there; the Redemption Token keeps working on the same list), Remotes.DenRequest (GetState / TradeIn) + Remotes.DenState nudges, expiry sweep, `ZombieAPI.CucumberStolen` listener, dev hook `workspace.DenDev = lose[:Zone:Type] / give[:n] / expire / clear / trade`. |
| `StarterGui.CucumberMenus.DenController` | proximity open / close, rows, previews (CucumberIndexPreviews + CucumberMutations.ApplyLook), countdown ticking, two-tap TRADE IN, toasts; dev hook `DenPanel.DenDev = open / close / refresh / arm / trade:<n>`. |

### The deal rule ("near attainable")
A stolen cucumber of biome Z asks for 3 of ONE kind from biome Z+1 (50 %), Z (35 %) or Z-1 (15 %), never past
`AttainableZone(strength) + 1` (the biome whose typical 8-reward cucumber the player lifts at CucumberLift.MIN_RATIO),
never a slice (reward 3) nor the biome's landmark tree (the row's top reward); within the biome the kind whose 3-fold
base value sits closest to the lost cucumber's base value is most likely (weight 1 / (1 + biomes of difference));
a kind the player already keeps 3 of on the base is avoided while anything else is left. Mutations of the lost
cucumber never change the ask. The deal is stamped on the loss record (`Id`, `Want = {Zone, Type}`) the first time the
den sees it (theft event or profile load) and lasts 12 h of REAL time from `record.At`.

### Trade in
Daytime only, never while the player's raid is live. The wanted cucumbers count while they STAND ON THE BASE (placed,
tagged, not held by a zombie). TRADE IN: the lost cucumber sprouts FIRST at the player's feet (CucumberSpawnerAPI
.SpawnCarried Anywhere + Force, parked in workspace.Breakables.Planted like a Redemption Token's - a field cucumber to
lift home), THEN the 3 cheapest wanted cucumbers leave the plot (PetBuffService.ClearCucumber "Traded", tag off so
IncomeService settles them, destroyed) and the record leaves Data.LostCucumbers. Nothing is consumed when the spawn fails.

## Co-op nights (ZombieRaidService + ZombieRaidClient patches)
`DamageZombie(model, amount, source, attacker)`: a Player's blow on ANOTHER player's night raid lands only while the
attacker's own raid is over (`Raids[attacker] == nil or .Over`) - otherwise it is refused and the attacker hears
"HelpBlocked" ("Finish your own wave before helping others!", one toast per 3 s). Landed blows register the helper on
the raid (`raid.Helpers[player] = {Hits, Damage}`; "HelperJoined" to the owner, "Helping" to the helper on the first
one). When the raid is WON (every zombie dead, or dawn with nothing stolen) `RewardHelpers`: the owner and every helper
with >= HELP_MIN_HITS (3) blows get TEAM_BOOST_SECONDS (300) of the potion boosts (CashBoostUntil + StrengthBoostUntil
extended from now / the current timer, never stacked: IncomeService x2 cash, GymService x2 strength per rep, ItemClient
shows the chips) and a "Teamwork" toast + Victory Sting. Hostility unchanged (a helped raid's zombies shove the helper
too). Pets / defences (no attacker argument) are never gated. `ZombieAPI.CucumberStolen` (BindableEvent) fires after
every escape's RecordLoss.

## Files
- `src/` new scripts (whole files), `patched/` = `orig/` (live mirrors pulled 2026-09-23 23:42 through receive.ps1 on
  port 8791) + the hunks in `tools/build_stage.py` (ZombieRaidService 8, ZombieRaidClient 2, MenuController 1,
  MenuClient 1), `stage/` = what serve.ps1 (port 8792) served: patches.json + _install.json + apply_patches.lua +
  install_new.lua + build_denpanel.lua.
- Push recipe: `py tools\build_stage.py`, `pets-remake\serve.ps1 -Port 8792 -Root <stage>`, then in the edit DM
  `apply_patches` + `install_new` (dry run first) + `loadstring(build_denpanel.lua)()`.
- Backup before the push: `backups/NewMap_zombie-den_before_2026-09-24.rbxm` (ZombieRaidService, ZombieRaidClient,
  the whole CucumberMenus GUI).

## Verified (2026-09-24, test profile `PetTest_140977250`, PetTestProfileKey = "PetTest" was already set)
Solo playtest: boot "[ZombieDen] ready", 9 old loss records got deals on load; walking (client PivotTo) to 6 studs from
the ring opened the panel (9 rows, both previews per row, countdowns); `DenDev = give` stood 3 Wrapped Cucumbers on the
plot -> row flipped to "3 / 3 on your base" + READY!; a night in between teleported the player home, the panel closed
itself and showed "BY DAY" grey; back at the den by day `DenDev = trade:1` -> "Your Prickly Cucumber is back! Pick it up
at the den.", a Prickly Cucumber (Desert, Planted / PlantedBy) with a lift prompt 4.6 studs from the player, the 3
Wrapped ones gone (28 -> 25 placed), LostCucumbers 9 -> 8; `DenDev = expire` dropped a row; a simulated theft through
ZombieAPI.CucumberStolen made a new deal (Golden Lantern Cucumber -> 3 x Katana Cucumber) that appeared first in the list.
Multiplayer playtest (2 clients, level-1 dev raids by day): Player2's blow on Player1's zombie while Player2's wave was
live -> refused (health 60 -> 60, "HelpBlocked" on Player2's client); Player2's wave killed -> RaidLive nil; 3 help
blows landed + the wave killed by Player2 -> "Player2 is helping Player1", "teamwork ... 300 s", Player1 heard
HelperJoined + Teamwork, Player2 heard Helping + Teamwork, both showed the "2x Strength 4:48" / "2x Cash 4:48" chips.
Not verified live: the "Offer" toast right after a real theft (same Notify path as the verified "Traded" toast); a phone
layout pass (the panel uses Manage's 1140 x 735 / 0.86 fit).
