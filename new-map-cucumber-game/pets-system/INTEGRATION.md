# Integration procedure (orchestrator, 2026-09-22) - read with CONTRACTS.md section 10

You are the INTEGRATION AGENT for one stage. Unlike the implementers you MAY write to Studio (edit DataModel)
and run playtests - but only in the ways described here. Read RULES.md, then this file, then CONTRACTS.md
sections 0, 8, 10 (+ the API sections of the files your stage installs), then the previous stage reports
`tests/S*_report.md`.

## Revised stage order (supersedes the table in CONTRACTS 10.2 where they differ)
The DataService patch goes in FIRST so every playtest runs on the isolated test profile, and
`PetDataMigration` moves to S3 (DataService finds it lazily: while it is absent, migration is skipped with
report `{Error = "NoModule"}`, so no pet-schema fields exist before BaseSave is patched).

| Stage | Installs (src/ new, patched/ existing) | Checks |
|---|---|---|
| S0a isolate | patched: `ServerStorage.DataService.lua` | set edit-mode `ServerStorage` attribute `PetTestProfileKey = "PetTest"`; playtest → Output shows the `STUDIO TEST PROFILE` warn with key `PetTest_140977250`; profile is a fresh template; seed it with `tools/restore_profile.lua` from `live-2026-09-22/_profile_Player_140977250_before-pets.json` (Cash, 4 pets, 3 eggs, 2 cucumbers, 51 builds come back via the legacy BaseSaveAPI.Reload); stop; playtest again → seeded data persisted on the test key; edit-mode `DataStoreService:GetDataStore("PlayerData_v1"):GetAsync("Player_140977250")` still matches the backup JSON (Cash, #Base.Pets, #Base.Builds, Playtime unchanged except by nothing). Also: normal leave path (a client-side `Players.LocalPlayer:Kick()` is NOT available in Studio as a leave for ProfileStore purposes? - use Stop, and note it). |
| S0b baseline | - | CONTRACTS S0 row on the test key: script profiler + micro profiler + remote-event rate for a `multiplayer_playtest` (2 clients is enough if more fail) with a `ZombieDev = "raid"`; record Cash/s and the raid threat level; save `tests/S0_baseline_*.json`/`.md`. Keep it under ~15 min; if a profiler tool fails, record what you could and move on. |
| S1 inert | src: PetBalance, PetStats, PetMotion | CONTRACTS S1 row. |
| S2 income | src: IncomeService, PetEffectsBus, PetServer; patched: LeaderstatsService, ZombieRaidService | CONTRACTS S2 row (the test key makes the fallback/raid checks safe). |
| S3 ownership + hatch | src: PetDataMigration, PetService; patched: BaseSaveService, PlotService, PetHatchService, EggPlacement, EggHatchClient, CucumberCarry | CONTRACTS S3 row. The migration is exercised by re-seeding the test key from the before-pets JSON (restore_profile writes the legacy shape; then a leave → rejoin runs the migration on load). |
| S4 presentation | src: PetEffectsClient, PetCardClient; patched: PetRoamClient, PlacedCucumberCardClient | CONTRACTS S4 row. |
| S5 buffs | src: PetBuffService | CONTRACTS S5 row. |
| S6 combat | src: PetCombatService | CONTRACTS S6 row. |
| S7 menu | run `builders/build_petspanel.lua` (edit mode); src: PetView, PetController; patched: MenuController, MenuClient, BaseHUDController | CONTRACTS S7 row + `capture_screenshot` of the open panel. |
| S8 regression + load | - | CONTRACTS S8 row; then ONE playtest on the REAL key (attribute cleared) to confirm the user's legacy profile migrates (4 pets owned, roster 4, eggs/cucumbers/builds intact) - backup JSON on hand; restore from it if anything is wrong. |

## Mechanics
1. **Backup** before writing: `mcp__robloxstudio__export_rbxm` of every EXISTING script the stage patches (and any
   existing instance a new file would replace) into
   `C:/Users/shrey/OneDrive/Documents/RobloxGames/backups/NewMap_pets-<stage>_before_2026-09-22.rbxm`.
2. **Stage** (PowerShell): `& "<root>\tools\stage.ps1" -Src @("a.lua","b.lua") -Patched @("c.server.lua")`
   - an omitted/empty list means NONE (verified 2026-09-22: `-Patched @("ServerStorage.DataService.lua")` →
   11 edits, dry run all `applied`). stage.ps1 wipes and rebuilds `stage\` each call, so stage everything the
   push needs in ONE call. Check `stage\_install.json` and `stage\patches.json` before pushing. The stage
   folder is served at `http://127.0.0.1:8796/`. patches.json hunks for a file are computed against
   `pushed\<file>` (the version last pushed live) or, before its first push, the 2026-09-22 snapshot. **After
   every successful, verified push of patched files run `& "<root>\tools\mark_pushed.ps1" -Patched @(...)`** so a
   later fix to the same file diffs against what is actually live. (New src files are replaced whole by
   install_new.lua and need no marking.)
3. **Dry run, then apply** (edit peer `execute_luau`, instance_id `instance:c9f-ksl`):
   ```lua
   local H = game:GetService("HttpService")
   local BASE = "http://127.0.0.1:8796/"
   local ap = loadstring(H:GetAsync(BASE .. "apply_patches.lua"))()
   local inst = loadstring(H:GetAsync(BASE .. "install_new.lua"))()
   local DRY = true
   return ap(BASE, DRY) .. "\n---\n" .. inst(BASE, DRY)
   ```
   Every patch hunk must say `applied` (or `already`); every new file `create`/`update`. Any `FAIL`/`BLOCKED` →
   the live script changed since the 2026-09-22 snapshot (another session): read the live Source, rebase the
   patched copy (keep their change), re-stage, retry. Then run with `DRY = false`.
4. **Verify the write**: for every touched script compare the live Source with the intended file (normalise CRLF →
   LF; compare lengths and a hash computed in Luau vs PowerShell, or post the live Source back through
   `pets-remake/receive.ps1 -Port 8797 -Root <root>\live-after` and diff it). Record mismatches.
5. **Playtest**: `solo_playtest status` first. If a playtest is running that you did not start, the user allows
   stopping it (USER RULE) - stop it. A running play DM keeps the OLD sources: always stop + start after a push.
   Use `solo_playtest start mode=play`, `eval_server_runtime` (live server VM, real require cache),
   `eval_client_runtime` (client-1), `get_runtime_logs` (filter by a bracketed tag like "[PetServer]", small
   `tail`). Keep every eval < 15 s; for timed checks use the persistent-sampler pattern (task.spawn a sampler that
   writes a summary into an attribute, read it in a later eval). ALWAYS stop the playtest you started before you
   finish, and confirm `status` says not running.
6. **Test profile**: from S0a on every playtest must run with `ServerStorage.PetTestProfileKey = "PetTest"`
   (check it at the start of your stage; set it if missing). Snapshot before destructive checks
   (`tools/snapshot_profile.lua`), restore after (`tools/restore_profile.lua`) - both written by the S0a agent per
   CONTRACTS 10.4 (loopback receiver: `pets-remake/receive.ps1 -Port 8797 -Root <root>\tests` in the background,
   GET `/__stop` when done; the stage/tests servers 8795/8796 serve JSON back for restores).
7. **Fixes**: if a check fails, find the root cause. You may now edit ANY file in `src/` / `patched/` (keep changes
   minimal and contract-consistent; if a contract rule itself is wrong, fix the code and add a line to
   `CONTRACTS.md` section 12 "INTEGRATION AMENDMENTS" with the reason). Re-compile via loopback, re-run that
   package's `tests/<WP>_*.lua`, re-stage only the changed files, push, retest.
8. **Report**: write `tests/S<stage>_report.md`: installed files (with live Source byte lengths), backup path,
   every check (PASS/FAIL + evidence numbers/log lines), fixes made (file + what + why), deviations, open issues,
   and the final state (playtest stopped, attributes set). Return the structured summary.
9. **Never**: publish; touch `__*`/Backup instances; use desktop tools; leave test instances, dev attributes (other
   than PetTestProfileKey) or a running playtest behind; run snapshot/restore against anyone but UserId 140977250
   (in multi-client tests the extra clients have their own test keys - leave them).
10. If Studio becomes unreachable (`get_connected_instances` shows no `instance:c9f-ksl` edit peer) or a playtest
    will not start ("previous test still in progress"), stop, write the report with what you have, and return
    `blocked = true` with the reason - do not try desktop workarounds.
