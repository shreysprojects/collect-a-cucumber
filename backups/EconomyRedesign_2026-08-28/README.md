# Economy Redesign Backup — 2026-08-28

Complete pre-redesign backup of **"collect cucumber game 8/25"** (dev place `135680492327917`, the canonical dev copy of live place `116126086405931`), taken BEFORE the full economy redesign of 2026-08-28. **Do not delete or overwrite this folder.**

## What's here

### `rbxm/` — full restorable binary backups
| File | Contents |
|---|---|
| `ServerController_full.rbxm` | The entire `ServerStorage.ServerController` module tree (all game services + Dictionaries) |
| `Services_SSS_RS_SG_SP_RF_Sound.rbxm` | Six staged folders: `__ExportTmp_SSS` (all ServerScriptService children), `__ExportTmp_RS` (all ReplicatedStorage children), `__ExportTmp_SG` (all StarterGui children), `__ExportTmp_SP` (StarterPlayerScripts + StarterCharacterScripts children in subfolders), `__ExportTmp_RF` (ReplicatedFirst), `__ExportTmp_Sound` (SoundService) |
| `ServerStorage_rest.rbxm` | Every ServerStorage child EXCEPT ServerController (assets, minigames, prior backups) |
| `Workspace_full.rbxm` | All Workspace children except Terrain/Camera (full map geometry) |

**Restore:** right-click in Studio Explorer → Insert from File → pick the rbxm → move the restored instances back to their original locations (folder names encode the service; `Prefix__` / `__ExportTmp_<SVC>` wrappers must be unwrapped).

### `scripts/` — plain-text `.lua` dumps
Every economy-relevant script (ServerController tree, sell/shop/portal/quest servers, egg/pet UI modules, client-side economy mirrors). Filenames = full instance path with `__` separators. These are the diff-friendly reference for what every script looked like pre-redesign.

### `values/` — baseline economy snapshot
`baseline-values.json` + `baseline-report.md`: every number in the pre-redesign economy (areas/doors, pickaxes, cucumber types per zone with HP/value/weights, golden/mutation odds and multipliers, pets, eggs + hatch odds, upgrades, rebirth bonuses, sell/multiplier systems, offline/playtime/quest/minigame rewards).

## In-Studio backup
`ServerStorage.EconomyBackup_PreRedesign_2026_08_28` — clones of all 33 economy scripts (+ README_REVERT StringValue with instructions). Fastest revert path for individual scripts.

## Full revert options (any of these)
1. **Per-script:** copy the pre-redesign source back from `scripts/*.lua` (or the in-Studio clone folder) over the live script.
2. **Bulk:** Insert `rbxm/ServerController_full.rbxm`, delete live `ServerStorage.ServerController`, move the restored one in place; same per-service for the other rbxm files.
3. **Nuclear:** Roblox cloud version history for place 135680492327917 (File → Publish history / version restore) — the place was last published before 2026-08-28's redesign edits.

## Player-data safety
The redesign was value-only where possible; any save-format change ships with backwards-compatible migration (see the redesign report in the project root). DataStores are NOT touched by reverting scripts — old saves remain readable by the pre-redesign code by design.
