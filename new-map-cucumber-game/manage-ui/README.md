# Manage panel (2026-09-23)

The designed `StarterGui.CucumberMenus.ManagePanel` ("MANAGE - Everything in your base, in one place":
Pets / Cucumbers / Zombies tabs, SELL rows, threat level, days survived, offline earnings) is now live.
User request: "script the manage ui - make manage button open it, then look at every aspect of manage ui
and implement whatever is there".

## What it does
| Tab | Shows | Does |
|---|---|---|
| Pets | `Pets N / cap` - the ACTIVE roster (what roams the base): preview, name, `<Rarity> - traits - $X/s`, SELL $value | SELL (two taps: `SURE?` for 3 s) -> `PetService.Sell` deletes the record, pays `ManageConfig.PetSellValue(Income)` = 220 s of its cash/s |
| Cucumbers | `Cucumbers N / cap` - every placed cucumber, best value first | SELL -> the model is destroyed, pays 220 s of its cash/s |
| Zombies | CURRENT THREAT LEVEL (what a raid would be right now), DAYS SURVIVED at that level, OFFLINE EARNINGS locked / unlocked with the `d / 1 DAY` bar | nothing to press: survive a night (raid ends "Survived") at your current level to unlock; leaving stamps level + cucumber cash/s, the next join pays rate x min(away, 8 h) x 50 % and toasts it |

Capacities ("Base upgrades increase your ... capacity"): cucumbers `10 + 2 x PlotLevel` (placement refused
"base full" -> "Your base is full. Upgrade your plot or sell a cucumber in Manage."; restores never count),
active pets `3 + PlotLevel`, capped at `PetBalance.SLOTS` (6) - the roster limit PetService hands its Core
(Equip -> `SlotsFull`, GrantFromEgg reserve, EquipBest, auto-equip). A roster already over the cap (a migrated
profile, a plot downgrade) keeps every pet; the Pets panel header reads e.g. `6 / 5 ACTIVE` and shows them all.
Every number is in `ReplicatedStorage.Modules.ManageConfig` (`PET_CAPACITY.Base = 6` = the old flat six slots).

Opening: the left menu's Manage button (inside the base; BaseHUDController keeps its hover pop), `Esc`, the X,
the dimmer, leaving the base (new `CLOSE_OUTSIDE` in MenuController) or `OpenRequest = "Manage#n"`.

## Files
- `src/` new scripts (whole files): `ReplicatedStorage.Modules.ManageConfig`, `ServerScriptService.ManageService`
  (Remotes.ManageRequest RemoteFunction: GetState / SellPet / SellCucumber; Remotes.ManageState refresh nudges;
  Data.Defense record; ZombieAPI.RaidResult listener; offline pay on load + 60 s stamps + OnBeforeClose order 15),
  `StarterGui.CucumberMenus.ManageController` (fills the panel; dev hook `ManagePanel.ManageDev = open | close |
  tab:<Page> | refresh | sell:<n>`).
- `patched/` = `orig/` (live mirrors pulled 2026-09-23) + the hunks in `tools/build_stage.py`:
  PetService (`SlotsOf(player)`, `PetService.Sell`, Delta `Removed`), PetController (over-capacity rosters shown
  whole), MenuController (Manage opener/panel, CLOSE_OUTSIDE, NO_HOVER), MenuClient (starts ManageController,
  guarded), CucumberCarry (capacity check in Place), CucumberPlacementClient ("base full" toast), DataService
  (`Defense` template key), ZombieRaidService (`ZombieAPI.ThreatLevel` BindableFunction, `ZombieAPI.RaidResult`
  BindableEvent fired Survived / ZombiesWin / Dawn).
- Push: `py tools\build_stage.py` -> `stage\`, `pets-remake\serve.ps1 -Port 8799 -Root <stage>`, then the
  apply_patches / install_new snippet from `pets-system/INTEGRATION.md` (dry run first). Backup before the push:
  `backups/NewMap_manage-ui_before_2026-09-23.rbxm` (PetService, DataService, CucumberCarry, ZombieRaidService,
  the whole CucumberMenus GUI, CucumberPlacementClient).
- Server dev hook: `workspace.ManageDev = survive[:level] | reset | offline:<seconds>`.

## Verified (solo playtest, test profile `PetTest_140977250`, 2026-09-23) - `tests/REPORT.md`
Real Manage-button clicks toggle the panel; rows render with previews; SELL of a cucumber ($470) and a pet
($121) credited Cash, removed the model / record (roster 6 -> 5, Base.Pets 9 -> 8, Delta `Removed`); Equip over
capacity -> `SlotsFull`; placement over the cap -> `"base full"`; a real night survived counted a day (twice);
`offline:3600` paid exactly `40215/s x 3600 x 0.5 = $72,387,490` and toasted; Zombies tab shows UNLOCKED at
level 5, `1 / 1 DAY`; leaving the base closes the panel; a real SELL click arms `SURE?` and reverts after 3 s.
Not done: a phone-preset layout pass (the panel uses the same 1140x735 / 0.86 fit as Shop / Index).
