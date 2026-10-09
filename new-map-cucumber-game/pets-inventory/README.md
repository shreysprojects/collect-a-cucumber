# Pets: no menu, inventory hotbar, click-for-info (2026-09-23)

User: "lets get rid of pets menu/pets button but make a backup of it. in pet overhead put their rarity under their
name instead of beside it. make name white but rarity color coded. make it so clicking on pet opens a frame on the
side, draggable, smaller, same kinda theme, and it just shows all the pet info along with a description of its
ability. make it so inactive pets are just in ur inventory (the inventory that is at bottom of screen)".

## What changed
| Piece | Where | What |
|---|---|---|
| Pets menu removed | `StarterGui.CucumberMenus.PetsPanel` + `PetView` + `PetController`, `StarterGui.CucumberHUDDesign.LeftMenu.Pets` (the paw) - DESTROYED | backup `backups/NewMap_PetsMenu_before-removal_2026-09-23.rbxm` (those four + the pre-change MenuController / MenuClient / BaseHUDController / PetCardClient / HotbarClient / PetBalance). MenuController / MenuClient / BaseHUDController no longer reference Pets. |
| Overhead card | `StarterPlayerScripts.PetCardClient` | row 1 name in plain white, row 2 the rarity word (RARITY_H 0.62 studs) in its rarity gradient, then cash, then the ability tag. Card = 1.9 + 0.62 (+ 0.8 tag) studs. |
| Pet info frame | `StarterPlayerScripts.PetInfoClient` (new; builds `PlayerGui.PetInfoUI`) | click a pet (screen-space bounding-box pick - pets are CanQuery false) -> a 340x500-design frame on the right, UIScale 0.62..1 by viewport height, Manage-panel look (pink stud body, red header plate, close X, green preview card, blue STATS card, orange ability card): preview, name (white), rarity (rarity gradient), owner, traits, cash/s, damage / interval / DPS, range, egg + rank + tier, ability name + `PetStats.AbilityEffect` description + chance per roll. Drag by the header strip (kept on screen). Esc / X / the pet leaving closes it. Own pets get PUT IN INVENTORY. Ignored while a menu is open, in build mode or with a tool in hand. Hook: `PetInfoUI.PetInfoDev = open:<n> | close | putaway`. |
| Inventory | `ServerScriptService.PetInventoryService` (new), `StarterPlayerScripts.PetInventoryClient` (new), `HotbarClient` patched | every owned pet that is not in the roster is a Tool in the Backpack (RequiresHandle false, tag PetTool, attrs PetId / Pet / DisplayName / Rarity / Material / Mutations / Income), reconciled every 1.5 s + on load / reset / respawn, best income first, max 40. The hotbar draws the pet model (traits applied) like an egg and a pet tooltip (rarity, $/s, traits, "Click to let it out in your base"). Clicking the tool -> `Remotes.PetInventory {Action = "Equip"}` -> `PetService.Equip` (toast, tool gone); the frame's button -> `Unequip` (toast, tool back). PetService stays the only owner of records / roster; its combat lock and the plot-level pet cap apply ("Your base is full - put a pet away first.", "Finish defending your plot first."). Hook: LocalPlayer `PetInventoryDev = equip:<n>`. |
| Texts | `ReplicatedStorage.Modules.PetBalance` | MigrationNotice / ReserveNotice no longer point at the Pets menu. |

## Files / push
`src/` new scripts, `orig/` live mirrors (2026-09-23), `patched/` = orig + the hunks in `tools/build_stage.py`
(PetCardClient 6, HotbarClient 6, MenuController 2, MenuClient 2, BaseHUDController 2, PetBalance 2).
`py tools\build_stage.py` -> `stage\`; `pets-remake\serve.ps1 -Port 8799 -Root <stage>`; apply_patches +
install_new (pets-system/INTEGRATION.md snippet). The four menu instances were destroyed in the same edit-mode
call after the push. Not saved / published.

## Verified - `tests/REPORT.md`
Solo playtest on the PetTest profile: 3 reserve pets became hotbar tools with live pictures + tooltip; the card rows
read NameRow (white) / RarityRow (gradient) / CashLine / AbilityTag; a real click on a roaming pet (camera-follow
trick) opened the frame with the right data; letting a pet out at the 5 / 5 cap toasted the cap message; PUT IN
INVENTORY put Gregory back as a tool; clicking a tool let Cucumber Deer out; menu / paw gone, no warnings.
Not done: a real drag (no mouse-move simulation), phones.

## Round 2 (2026-09-23 later, user: "make placing pet from inventory show pet preview like in the build placement system ... place pet anywhere theres space" / "in egg hatching make it just show pet - pet name/rarity and chance of getting pet, dont show all that other info")
- **Placement ghost** (`PetInventoryClient` rewritten): taking a pet tool out (hotbar click / number key = `Tool.Equipped`) shows a see-through copy of the pet (catalog model, traits applied, shrunk to PetBalance.PET.FIT like the live one) that follows the mouse over YOUR plot, clamped inside it, red (parts + Highlight, the CucumberPlacementClient recipe) where it overlaps anything in `plot.Placed` or when the mouse is off the plot. Click / tap on a green ghost -> `Remotes.PetInventory {Action = "Equip", PetId, Spot}`; `PetInventoryService.ValidateSpot` (on the plot, footprint kept in, no overlap -> `OffPlot` / `NoSpace`) then `PetService.Equip(player, id, spot)` (new third argument: `SpawnPet` spawns there, else the old saved / random spot). Putting the tool away removes the ghost. Toasts: "No room there - try another spot.", "Point at your base to place your pet.", plus the cap / lock ones. Hook: `PetInventoryDev = equip:<n> | place:<x>,<z>` (plot-local).
- **Egg reveal** (`EggHatchClient` hunk): the `PetStats` (cash/s + ability) and `PetTraits` lines added on 2026-09-22 stay hidden; the card is the pet model, PetName, PetRarity and the `[1 in N]` PetChance only.
- Pushed with `tools/build_stage.py` (ACTIVE = the round-2 hunks only: the round-1 hunks are live and two of them are additive, so they must never ride again - apply_patches would apply them twice). Verified in a solo playtest: ghost built on equip (34 parts, green at a free spot), `place:0,22` -> "No room there" over a build, put a pet away then `place:-4,-21` -> "Cucumber Deer is out in your base!", the new pet's pivot = the requested world point (dXZ 0.00), ghost + tool gone; a fake `PetHatch "Begin"` + 4 clicks -> card labels PetName / PetRarity / PetChance visible, PetStats / PetTraits hidden.
