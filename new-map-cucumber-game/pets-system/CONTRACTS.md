# Pet system - binding interface contract (2026-09-22)

Authoritative for **interfaces** (names, signatures, payloads, attribute strings, saved fields, ordering).
`PLAN.md` stays authoritative for behaviour and numbers; where this file pins a number it is copied from
PLAN.md (section 9 below) or is an explicit OPEN DECISION (section 11). Line numbers `Lnnn` refer to the
read-only snapshot `../live-2026-09-22/`; they move once `patched/` copies are edited - match on the quoted
code, not on the number.

Every implementer: read `RULES.md` first, then section 0, your work package (section 2), the API sections of
every module you call or that calls you (sections 3-4), and sections 5-8 for data/attributes/remotes/lifecycle.

---------------------------------------------------------------------------------------------------------

## 0. Global conventions (apply to every package)

1. **Clock.** Every pet-system time that is saved, replicated or compared across scripts is **server epoch time =
   `workspace:GetServerTimeNow()`** (same clock as EggPlacement `HatchAt`). Only ZombieRaidService's own
   `os.clock()` fields (StunUntil etc.) stay os.clock. Modules take an injectable `Clock` (default
   `function() return workspace:GetServerTimeNow() end`). Saved `AcquiredAt` uses `os.time()` (integer).
2. **IDs.** `HttpService:GenerateGUID(false)` (36 chars, no braces). A valid ID is a `string` with
   `1 <= #id <= 64`. Helper name everywhere: `IsValidId(id)`. Never accept an ID from a client for anything
   except `PetRequest.PetId`, which is only ever looked up in the caller's own records.
3. **Finite numbers.** `local function Finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end`.
   Every number read from data, attributes, remotes or other modules is checked before use; invalid →
   fallback/skip + a diagnostic counter, never an error.
4. **Stateful server modules** (`PetService`, `PetBuffService`, `PetCombatService`, `IncomeService`,
   `PetEffectsBus`): no side effects at require time except building constant tables and the `Core` table.
   `Init(deps)` stores dependencies (may be called once; a second call is ignored with a warn). `Start()` is
   idempotent (`Started` flag), creates remotes/connections/loops. Each exposes `GetDiagnostics() -> table`
   (flat `{[string] = number}`), `IsStarted() -> boolean` (true once `Start` finished without error; never
   yields) and a pure `Core` table of the functions its unit tests exercise.
5. **Lazy cross-script requires.** Scripts that are not bootstrapped by PetServer (ZombieRaidService,
   CucumberCarry, BaseSaveService, LeaderstatsService, PetHatchService) resolve pet modules lazily and
   tolerate their absence (staged installs):
   ```lua
   local function Lazy(name) -- 2026-09-22: pet-system modules are optional until their stage is installed
   	local cache
   	return function()
   		if cache then return cache end
   		local module = ServerStorage:FindFirstChild(name)
   		if not module then return nil end
   		local ok, result = pcall(require, module)
   		if ok and type(result) == "table" then cache = result end
   		return cache
   	end
   end
   ```
   A module that is present but not yet `Start`ed must answer its query functions safely (return
   "not blocked"/0/false) - never error.
6. **New DataService functions are feature-checked** by callers: `if type(DataService.OnBeforeClose) == "function" then ... end`
   (same for `IsClosing`, `GetGeneration`, `OnProfileReset`, `GetMigrationReport`).
7. **Profile tables are never cached across calls.** Always re-read `DataService.GetData(player).Base.<X>`.
   BaseSave replaces `data.Base` on every snapshot; admin reset replaces everything. Exception: PetService may
   cache an index keyed by the identity of the `data.Base.Pets` array and must rebuild it when
   `data.Base.Pets ~= cached.PetsArray` or the profile generation changed.
8. **Arrays in profile data**: remove with `table.remove`, never `t[i] = nil`. No Instances/Vector3/CFrame/Color3
   in profile data.
9. **Remotes**: servers find-or-create under `ReplicatedStorage.Remotes` (folder find-or-create too); clients
   `ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name, 60)` inside `task.spawn` and `warn` + degrade
   on nil. Remote payload numbers are re-validated on receipt.
10. **Test hooks**: Studio-only (`RunService:IsStudio()`), edge-triggered workspace attribute, cleared to `nil`
    first (house pattern). Hooks listed per package.
11. **Style**: RULES.md code style; header comment with a dated `(2026-09-22)` paragraph; patches are surgical
    (unique-match hunks applied onto the live Source) - do not reformat untouched code.
12. **Diagnostics**: bounded counters only; never log per shot/tick; a `warn` for a given reason at most once per
    60 s per server (`WarnOnce(key, msg)` helper per module).
13. **Close-phase callbacks** (every `DataService.OnBeforeClose` fn: PetService.Freeze / SyncRecords,
    IncomeService.FlushOwner, ZombieRaidService PreCloseRaids, BaseSave Snapshot, and everything they call) gate
    **only** on `DataService.GetData(player) ~= nil` (no-op + return when nil). They must NOT check `IsClosing`,
    `PetService.IsReady`, `Frozen`, `player.Parent` (already nil inside PlayerRemoving under Deferred signals) or
    `BaseRestored`. Everything else (ticks, requests, hatches, grants) keeps refusing closing owners.
14. **Tag-added handlers never judge placement at add time.** Both live placement paths add `PlacedCucumber`
    BEFORE parenting (CucumberCarry `Place` L956→L957, `RestorePlaced` L1038→L1039), and the build-mode move ghost
    is a client `model:Clone()` that keeps the tag. So: server registries register every tagged Model on add and
    evaluate `IsDescendantOf(workspace)` / plot membership only at pay/grant/render time; client scripts that
    render per placed cucumber evaluate the filter lazily (re-check on `AncestryChanged`, never cache a verdict made
    while `Parent == nil`) and accept only `model.Parent.Name == "Placed"` and
    `model:IsDescendantOf(workspace.Map.Lobby.Plots)` (excludes the `"<name> Preview"` ghost).

---------------------------------------------------------------------------------------------------------

## 1. File list and ownership

Local names: new scripts under `pets-system/src/`, patched copies under `pets-system/patched/` (same file name as
the snapshot). File name = DataModel path + `.lua` (ModuleScript) / `.server.lua` (Script) / `.client.lua`
(LocalScript). Every file belongs to exactly one work package.

### 1.1 New scripts

| DataModel path | Class | Local file (src/) | WP |
|---|---|---|---|
| `ReplicatedStorage.Modules.PetBalance` | ModuleScript | `ReplicatedStorage.Modules.PetBalance.lua` | WP-STATS |
| `ReplicatedStorage.Modules.PetStats` | ModuleScript | `ReplicatedStorage.Modules.PetStats.lua` | WP-STATS |
| `ReplicatedStorage.Modules.PetMotion` | ModuleScript | `ReplicatedStorage.Modules.PetMotion.lua` | WP-STATS |
| `ServerStorage.PetDataMigration` | ModuleScript | `ServerStorage.PetDataMigration.lua` | WP-DATA |
| `ServerStorage.PetService` | ModuleScript | `ServerStorage.PetService.lua` | WP-PETSVC |
| `ServerStorage.IncomeService` | ModuleScript | `ServerStorage.IncomeService.lua` | WP-INCOME |
| `ServerStorage.PetBuffService` | ModuleScript | `ServerStorage.PetBuffService.lua` | WP-BUFF |
| `ServerStorage.PetCombatService` | ModuleScript | `ServerStorage.PetCombatService.lua` | WP-COMBAT |
| `ServerStorage.PetEffectsBus` | ModuleScript | `ServerStorage.PetEffectsBus.lua` | WP-SERVER |
| `ServerScriptService.PetServer` | Script | `ServerScriptService.PetServer.server.lua` | WP-SERVER |
| `StarterGui.CucumberMenus.PetView` | ModuleScript | `StarterGui.CucumberMenus.PetView.lua` | WP-MENU |
| `StarterGui.CucumberMenus.PetController` | ModuleScript | `StarterGui.CucumberMenus.PetController.lua` | WP-MENU |
| `StarterPlayer.StarterPlayerScripts.PetEffectsClient` | LocalScript | `StarterPlayer.StarterPlayerScripts.PetEffectsClient.client.lua` | WP-WORLDFX |
| `StarterPlayer.StarterPlayerScripts.PetCardClient` | LocalScript | `StarterPlayer.StarterPlayerScripts.PetCardClient.client.lua` | WP-WORLDFX |

Non-script deliverable (edit-mode builder chunk, **not** under src/ because `stage.ps1` installs every src/*.lua
as a script): `pets-system/builders/build_petspanel.lua` - WP-MENU. Run only by the integration agent.

Integration-agent (IA) tools, not owned by any WP (written by the IA before S3, section 10.2):
`pets-system/tools/snapshot_profile.lua` and `pets-system/tools/restore_profile.lua` (profile backup/restore in a
running playtest, 10.4). `tools/stage.ps1` already stages `install_new.lua` and `pets-remake/apply_patches.lua`.

### 1.2 Existing scripts patched

| Snapshot / patched file name | DataModel path | WP |
|---|---|---|
| `ServerStorage.DataService.lua` | ServerStorage.DataService | WP-DATA |
| `ServerScriptService.PetHatchService.server.lua` | ServerScriptService.PetHatchService | WP-HATCH |
| `ServerScriptService.EggPlacement.server.lua` | ServerScriptService.EggPlacement | WP-HATCH |
| `StarterPlayer.StarterPlayerScripts.EggHatchClient.client.lua` | StarterPlayer.StarterPlayerScripts.EggHatchClient | WP-HATCH |
| `ServerScriptService.LeaderstatsService.server.lua` | ServerScriptService.LeaderstatsService | WP-INCOME |
| `ServerScriptService.ZombieRaidService.server.lua` | ServerScriptService.ZombieRaidService | WP-BUFF |
| `ServerScriptService.CucumberCarry.server.lua` | ServerScriptService.CucumberCarry | WP-BUFF |
| `ServerScriptService.BaseSaveService.server.lua` | ServerScriptService.BaseSaveService | WP-SERVER |
| `ServerScriptService.PlotService.server.lua` | ServerScriptService.PlotService | WP-SERVER |
| `StarterGui.CucumberMenus.MenuController.lua` | StarterGui.CucumberMenus.MenuController | WP-MENU |
| `StarterGui.CucumberMenus.MenuClient.client.lua` | StarterGui.CucumberMenus.MenuClient | WP-MENU |
| `StarterGui.CucumberHUDDesign.BaseHUDController.lua` | StarterGui.CucumberHUDDesign.BaseHUDController | WP-MENU |
| `StarterPlayer.StarterPlayerScripts.PetRoamClient.client.lua` | StarterPlayer.StarterPlayerScripts.PetRoamClient | WP-WORLDFX |
| `StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient.client.lua` | StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient | WP-WORLDFX |

### 1.3 Audited, deliberately NOT patched (regression only)
`AdminService` (reset works through BaseSaveAPI.Reset + DataService.ResetProfile hooks, see 8.6),
`CucumberMoveServer` (same instance, tag untouched, rate unchanged: no settle needed; see OD-19),
`HUDClient` (MenuController owns the paw click; ui.md C2), `EggShop`, `DefenceService`, `ZombieCatalog`,
`CucumberValues`, `CucumberMutations`, `PetsCatalog`, `BuildService`, `GuardianService`, `StrengthProgressionServer`,
`BenchServer`, `BenchBonusClient`, `SlowModeClient`, `CucumberLift*`. Never touch anything under ServerStorage named
`__*` or containing `Backup`. Never touch `CucumberMenus.ManagePanel` (unwired mock; mention in handoff).

---------------------------------------------------------------------------------------------------------

## 2. Work packages

Each package codes only against this contract (not against other packages' code). "Tests" = Luau chunks in
`pets-system/tests/<WP>_*.lua`, run read-only in Studio through the loopback servers (RULES.md). Every file a
package writes must compile (`loadstring`) - that check is implied and not repeated below.

| ID | Name | Files owned | Depends on (contract only) |
|---|---|---|---|
| WP-STATS | Balance, stats, motion | PetBalance, PetStats, PetMotion | PetsCatalog (live) |
| WP-DATA | Migration + DataService hooks | PetDataMigration; patch DataService | WP-STATS |
| WP-PETSVC | Pet ownership/runtime | PetService | STATS, DATA, INCOME, BUFF, SERVER(PetEffectsBus) |
| WP-HATCH | Hatch transaction + reveal | patch PetHatchService, EggPlacement, EggHatchClient | STATS, DATA, PETSVC, SERVER(BaseSaveAPI), MENU(builder label names) |
| WP-INCOME | Unified income | IncomeService; patch LeaderstatsService | DATA, BUFF(ModifiersOf) |
| WP-BUFF | Cucumber buffs + theft guard | PetBuffService; patch ZombieRaidService, CucumberCarry | STATS, INCOME, DATA(OnBeforeClose), SERVER(bus, BaseSaveAPI) |
| WP-COMBAT | Pet combat | PetCombatService | STATS, PETSVC, BUFF(ZombieAPI.TargetInfos), SERVER(bus) |
| WP-SERVER | Bootstrap, FX bus, base save, plot release | PetServer, PetEffectsBus; patch BaseSaveService, PlotService | all server APIs |
| WP-MENU | Pets panel + opener | PetView, PetController, builder; patch MenuController, MenuClient, BaseHUDController | STATS, remotes (7) |
| WP-WORLDFX | World presentation | PetEffectsClient, PetCardClient; patch PetRoamClient, PlacedCucumberCardClient | STATS, attributes (6), remotes (7) |

### WP-STATS
- Deliverables: the three modules exactly as section 3.1-3.3; `PetBalance` literal tables from section 9.
- Tests `tests/WP-STATS_*.lua`: catalog coverage (49 keys, each in exactly one egg, every key has an ability row,
  no extra rows, 8 egg tiers); PLAN 3.2 examples (Cat 0.5, Fox 3.75, Gregory 7.5, Chest 7.8, Cosmo Cat 15,728,640);
  Golden NEON ROYAL affix 2.475; duplicate mutation counted once; income affix cap 8 (Diamond+PRISMATIC+VOID+ROYAL
  → 8); damage affix cap 1.25; Deer 3 dmg / 2.5 s = 1.2 DPS; Cosmo Cat 24.3 dmg / 1.5 s = 16.2 DPS and 20.25 at
  max affix; fighter Bunny 5 × 1.15 = 5.75; unknown key → `Valid=false`, all numbers 0, no error; garbage records
  (nil, number, NaN fields, non-string mutations) → finite outputs; `GuardSeconds(180,45)=240`,
  `GuardSeconds(1000,1000)=600`; `RateMultiplier{Yield,Haste}=1.875`; PetMotion: before start, after end,
  midpoint, zero duration, missing From, NaN times, `ToAttributes` ends with `RoamSeq`.
  Added (critic log): a species in a fake catalog's `PETS` with no `SPECIES_ABILITY` row → `Valid=true`,
  Ability `"None"`, `Warnings` contains `"NoAbilityRow"`, and `Validate` reports it; a key absent from `PETS` →
  `Valid=false`; pool rank 9 → clamped to 6 + warning, and `Validate` flags it; `NormalizeMutations("neon, Foo")`
  → `{"NEON", "Foo"}` (unknown kept byte-for-byte, only known names upper-cased); an existing array of 20 entries
  is not truncated; text helpers (`AbilityShort/Badge/Effect`) equal strings built from the `ABILITIES` numbers
  (change `Mult` in a copied table → text follows).

### WP-DATA
- Deliverables: `PetDataMigration` (3.4); DataService patch (4.1).
- Tests: migration over a fixture copied from `_profile_Player_140977250_before-pets.json` (4 pets, 3 eggs incl. the
  two ghost eggs, 2 cucumbers, Version 2): 4 IDs, roster = 4 IDs in Income/DPS/Id order, `PetNoticePending=true`,
  3 egg IDs, 2 cucumber IDs, `PetSchemaVersion=1`, `Version` still 2, cucumber count unchanged, Pos arrays
  untouched; second run = zero changes and identical IDs; 9 legacy pets → roster 6, 9 still owned; duplicate pet
  IDs repaired (first kept); unknown species kept, excluded from roster; string mutations → array; existing traits
  preserved; `Version=1` base with cucumbers → Version and Cucumbers unchanged (no wipe triggered by migration);
  non-table Base → report error, no throw; roster repair on schema ≥1 (foreign/duplicate IDs dropped, >6 truncated);
  two egg records sharing one Id → both kept, neither re-IDed (Restore drops the later one, 4.8); `Scope = "Pets"`
  run leaves Eggs/Cucumbers byte-identical (even records without Id).
  DataService: compile only (requiring it would start a ProfileStore) plus a static review checklist in the result.

### WP-PETSVC
- Deliverables: `PetService` (3.5), moving spawn/roam code out of PetHatchService (same constants/behaviour).
- Tests (via `PetService.Core` with plain-table fakes, no instances): Equip/Unequip idempotence, slot cap, combat
  lock, unknown/unavailable refusal; EquipBest determinism + cooldown retention; GrantFromEgg (egg record removed
  by Id, SourceEggId dedupe returns existing, reserve when full/locked, record shape); ability scheduler (one roll
  per 60 active s, reset-before-roll, 30 s hitch → one roll, reserve/pending/unavailable don't tick, unequip resets);
  seeded probability sample for 1/2/4/8/12 % within ±3σ; request validation + rate limiter; state payload shape.
  Added (critic log): **hatch commit matrix** over a fake base - GrantFromEgg with (a) the egg record absent,
  (b) present with matching Id, (c) SourceEggId already owned, (d) a non-table entry in `Eggs` before the match →
  after each exactly one of egg/pet exists for that EggId and nothing threw; GrantFromEgg followed immediately by
  `HasSourceEgg` → true (index updated synchronously); `Equip` then `StepAbility(dt = 0.25)` → no roll; a restored
  record with Remaining 12 rolls only after 12 simulated s (no join roll); presentation sequences
  Pending → Detach → Attach → Finish and Pending → Unequip → Equip → Finish each end with exactly ONE spawn
  (fake Spawner counts); Equip/EquipBest while not attached → `"NoPlot"`, Unequip while not attached → ok;
  GrantFromEgg at `MAX_OWNED` → `nil, {Error = "InventoryFull"}` with no mutation; locked grant with free slots →
  reserve + `PendingAutoEquip`, unlock → equipped in grant order while slots free; Revision stays monotonic across
  a runtime rebuild; limiter survives a rebuild.

### WP-HATCH
- Deliverables: patches 4.2-4.4.
- Tests: compile; a pure chunk that copies the patched `Presentations` token logic is not required - instead list
  playtest checks in the result. EggHatchClient: compile. Must implement the `PetHatchDev` fault hooks
  `"fail:pre-grant" | "fail:post-grant" | "fail:post-destroy"` (4.2) used by the S3 interruption matrix.

### WP-INCOME
- Deliverables: `IncomeService` (3.6); LeaderstatsService patch (4.5).
- Tests (`IncomeService.Core`): $0.50/s producer pays exactly 30 over 60 simulated 1 s ticks and over irregular
  ticks (0.9/1.1/1.7 …); split at modifier expiry; Yield 15 / Haste 12.5 / both 18.75 on base 10; cap 2.0; 5 s
  catch-up clamp (+diag); producer added mid-second earns only its span; settle-then-tick never double pays; totals
  (CucumberBase excludes modifiers and pets). Added (critic log): with the owner marked closing, `FlushOwner`
  credits the ledger once and a second call credits 0; producer removed mid-second then tick → the span is paid
  exactly once; settlement for a forgotten/flushed/unloaded owner is discarded (`LateSettles` +1, no ledger
  created); after `OnProfileReset` a late removal settles 0; Owner attribute change settles to the OLD owner;
  `GetThreatIncome` returns nil before Start; `OnTotalsChanged` does not fire on a tick where no total changed.

### WP-BUFF
- Deliverables: `PetBuffService` (3.7); patches 4.6 (ZombieRaidService) and 4.7 (CucumberCarry).
- Tests (`PetBuffService.Core`): eligibility predicate on fake cucumber tables; same-kind no stack/refresh; Wild
  chooses only kinds with targets (seeded 30 000 draws, each kind within ±3σ of uniform); target choice uniform;
  TryBlock state machine (charge consumed once, grace rejects without charge, expired shield does not block, two
  attempts in one frame → one charge); Serialize/Stamp round trip dropping expired and invalid entries; guard
  duration from cycle seconds; a record whose `SourcePetId` is not owned by anyone keeps its `ExpiresAt` unchanged
  after Stamp → Serialize; `TryBlockTheft` with a caller `now` of 1e9 behaves exactly as with nil (own Clock).

### WP-COMBAT
- Deliverables: `PetCombatService` (3.8).
- Tests (`PetCombatService.Core`): owner filter; XZ range; priority Carry > Grappling > nearest; keep current target
  unless higher priority; deadline: no burst after a 3 s hitch; rejects NaN damage; fallback TargetInfos built from
  `Zombies()` + attributes; `Core.NextShot` over 100 s of 0.2 s scans at interval 2.5 with scan jitter → 40 ± 1
  shots (nominal cadence held); a 3 s hitch → exactly one shot; a new target fires on the first scan in range.

### WP-SERVER
- Deliverables: `PetServer` (3.9), `PetEffectsBus` (3.10), BaseSaveService patch (4.8), PlotService patch (4.9).
- Tests: `PetEffectsBus.Core` (Id monotonic, per-recipient cap 48 with drop counter, radius selection); compile all.
  Static review checklist in the result (BaseSave cannot be required in an eval): the cucumber shallow copy is taken
  AFTER the v1 gate (a Version = 1 base with cucumbers restores 0 cucumbers - also an S3 playtest row);
  `KeptEggs[player] = nil` before the egg loop; `BaseRestored`/`AttachPlot` sit after `Active[player] = plot`
  outside `if base`; every PetService/PetBuffService call in Collect and the heartbeat body are pcall-guarded.

### WP-MENU
- Deliverables: `PetView`, `PetController` (3.11), patches 4.10-4.12, builder `builders/build_petspanel.lua`
  (instance names in 3.11.1).
- Tests (`PetController.Core`): sort Income/Combat/Rarity/Newest with Id tie-break; filter All/Active/Reserve;
  ApplyState full/delta, revision gap → `NeedFull`; lock banner state; request id generator unique. Compile builder
  (do NOT run it).

### WP-WORLDFX
- Deliverables: `PetEffectsClient`, `PetCardClient` (3.12), patches 4.13 (PetRoamClient rewrite) and 4.14.
- Tests: pure helpers (countdown `m:ss` formatter, popup cap queue, segment cache seq gating via `PetMotion`);
  compile.

---------------------------------------------------------------------------------------------------------

## 3. New module APIs

Type notation: `name: type`; `?` = optional/nil-able. "Never" lists are hard requirements for reviewers.

### 3.1 `ReplicatedStorage.Modules.PetBalance` (WP-STATS)
Pure data (section 9 literal) plus:
- `PetBalance.Validate(catalog: PetsCatalog) -> problems: {string}` - empty when every `catalog.PETS` key has a
  `SPECIES_ABILITY` row, every row names a catalog key, every `catalog.EGGS` key has an `EGG_TIERS` and `EGG_ZONES`
  entry, every rarity used by the catalog has a `RARITY` row, every egg-pool rank (after `RANK_OVERRIDES`) is an
  integer in `1..MAX_RANK`. Never errors. Called at runtime by PetServer bootstrap step 2b (3.9), not only in tests.
- Never: requires anything, touches Instances (Color3 values allowed).

### 3.2 `ReplicatedStorage.Modules.PetStats` (WP-STATS)
Requires `PetBalance`, `PetsCatalog` (siblings). Builds at require: `SpeciesEgg[petKey] = {Egg = eggKey, Tier = n, Rank = n?}`
from `PetsCatalog.EGGS` (Rank from the pool entry; `PetBalance.RANK_OVERRIDES[key]` wins; missing → nil).
- `PetStats.IsFinite(x) -> boolean`
- `PetStats.IsValidId(id) -> boolean` (section 0.2)
- `PetStats.EggOf(petKey) -> eggKey?, tier?, rank?`
- `PetStats.EggKeyOfShortName(shortName) -> eggKey?` - `"Desert"` → `"Desert Egg"` via `PetsCatalog.EggKey`.
- `PetStats.NormalizeMaterial(value) -> string` - nil/""/non-string → `""`; otherwise the string unchanged
  (unknown strings kept for recovery).
- `PetStats.NormalizeMutations(value) -> {string}` - accepts nil, a comma/whitespace string (split on
  `[^,%s]+`), or an array; non-strings dropped. A token whose upper-case form is a known `PetBalance.MUTATIONS`
  key is stored as that canonical key; an unknown token is KEPT byte-for-byte (no case change). Distinct by stored
  value, first-seen order. From a **string** (egg/cucumber source) at most 16 tokens are read; an existing
  **array** is never truncated (PLAN 3.3 "preserve original metadata"). Maths always match on an upper-cased copy.
- `PetStats.SplitMutations(list) -> known: {string}, unknown: {string}` (known = keys of `PetBalance.MUTATIONS`,
  matched on the upper-cased copy; unknown returned as stored).
- Text helpers (the only place ability numbers become words; menu, reveal, toasts and badges call these):
  `PetStats.AbilityBadge(kind) -> string` (`("x%g"):format(Mult)` for Yield, `("+%d%%"):format((Mult-1)*100 + 0.5)`
  for Haste, `tostring(Charges)` for Guard, `""` otherwise); `PetStats.AbilityShort(kind, guardSeconds?) -> string`
  (`PetBalance.TEXT.Short[kind]` filled from `Mult`/`Duration`/`guardSeconds`: Yield `"x1.5 for 90s"`, Haste
  `"+25% for 90s"`, Guard `"blocks one theft for 240s"`; Wild/None → `""`); `PetStats.AbilityEffect(kind, guardSeconds?) -> string` (the menu's exact-effect
  line, built from `PetBalance.TEXT.Effect[kind]` templates + numbers; Wild lists its three kinds with durations).
- `PetStats.MutationString(list) -> string` - comma-joined KNOWN names (for `CucumberMutations.ApplyLook` /
  attributes), `""` when none.
- `PetStats.AffixIncome(material, mutations) -> number` - `min(INCOME_AFFIX_CAP, MaterialIncome × (1 + Σ known distinct mutation Income))`.
- `PetStats.AffixDamage(material, mutations) -> number` - `1 + min(DAMAGE_AFFIX_CAP, material Combat + Σ known Combat)`.
- `PetStats.AbilityOf(petKey) -> "Yield"|"Haste"|"Guard"|"Wild"|"None"` (unknown key or no `SPECIES_ABILITY` row → "None").
- `PetStats.Calculate(record: any) -> Stats` - never errors, never returns non-finite numbers. Reads only
  `record.Pet`, `record.Material`, `record.Mutations`. **Validity**: `Valid = false` only when `record.Pet` is not a
  key of `PetsCatalog.PETS`. A catalog species without a `SPECIES_ABILITY` row is `Valid = true`, Ability `"None"`
  (a Fighter) plus warning `"NoAbilityRow"`; without an egg pool entry → tier 1 + warning `"NoEgg"`. Rank =
  `math.clamp(math.floor(rank), 1, MAX_RANK)` with warning `"RankClamped"` when it changed. `Stats`:
  ```lua
  {
  	Valid = boolean,          -- false: not in PetsCatalog.PETS (all numbers 0, Ability "None")
  	Pet = string?, DisplayName = string, Rarity = string, RarityKnown = boolean,
  	EggKey = string?, EggTier = number, Rank = number,
  	AffixIncome = number, AffixDamage = number,
  	Income = number,          -- cash/s = BASE_INCOME * TIER_STEP^(tier-1) * rarity.Income * (1 + RANK_STEP*(rank-1)) * AffixIncome
  	ShotDamage = number,      -- rarity.Damage * (1 + BIOME_DAMAGE_STEP*(tier-1)) * AffixDamage * (Fighter and FIGHTER_MULT or 1)
  	ShotInterval = number, DPS = number, Range = number,
  	Ability = string, AbilityChance = number, -- per ABILITY_PERIOD roll (0 for "None")
  	Fighter = boolean,        -- Ability == "None"
  	UnknownMutations = {string}, UnknownMaterial = string?, Warnings = {string}, -- bounded (<= 8)
  }
  ```
  Unknown rarity → `FALLBACK_RARITY` row + `RarityKnown=false` + warning. Missing rank → rank 1 + warning (Gregory
  has an override, so no warning).
- `PetStats.Compare(a, b, mode) -> boolean` - `a, b = {Id = string, Stats = Stats}`; `mode "Income"`: Income desc,
  DPS desc, Id asc; `"Combat"`: DPS desc, Income desc, Id asc. Usable directly in `table.sort`.
- `PetStats.GuardSeconds(daySeconds, nightSeconds) -> number` - `min(GUARD.MaxSeconds, day + night + GUARD.CycleExtra)`
  with non-finite inputs → defaults `DEFAULT_DAY_SECONDS`/`DEFAULT_NIGHT_SECONDS`.
- `PetStats.RateMultiplier(kinds: {[string]: true}) -> number` - product of `ABILITIES[k].Mult` over present
  multiplicative kinds, capped `RATE_HARD_CAP`.
- Never: state, randomness, Instances (PetsCatalog.ModelOf is NOT called here).

### 3.3 `ReplicatedStorage.Modules.PetMotion` (WP-STATS)
Pure; used by PetService (server) and PetRoamClient/PetEffectsClient (client).
- Segment table `Segment = {From: Vector3?, To: Vector3, Start: number, End: number, GroundY: number, Seq: number?}`.
- `PetMotion.Sample(seg: Segment?, now: number) -> pos: Vector3?, walking: boolean, heading: Vector3?`
  - nil/invalid `To` or `GroundY` → `nil, false, nil`.
  - `From` invalid → treated as `To`. `Start`/`End` non-finite or `End <= Start` → `To` (not walking).
  - `now <= Start` → From; `now >= End` → To; else linear lerp, `walking = true`.
  - `heading` = unit XZ of `To - From` when its XZ length > 0.2, else nil. Returned `pos.Y = GroundY`.
- `PetMotion.ReadSegment(model: Instance) -> Segment?` - reads attributes `RoamFrom, RoamTo, RoamStart, RoamEnd,
  RoamGroundY, RoamSeq`; nil when `RoamTo`/`RoamGroundY` invalid.
- `PetMotion.ToAttributes(seg: Segment) -> {{string, any}}` - ordered list `RoamFrom, RoamTo, RoamStart, RoamEnd,
  RoamGroundY, RoamSeq` (**RoamSeq last**). PetService publishes in this order.
- `PetMotion.MUZZLE_HEIGHT = PetBalance.FX.MUZZLE_HEIGHT` (re-export).

### 3.4 `ServerStorage.PetDataMigration` (WP-DATA)
Requires `ReplicatedStorage.Modules.{PetBalance, PetStats, PetsCatalog}`. Pure except reading
`PetsCatalog.ModelOf` inside the default `IsSpawnable`.
- `PetDataMigration.SCHEMA_VERSION = 1`
- `PetDataMigration.IsSpawnable(petKey) -> boolean` - `PetsCatalog.PETS[petKey] ~= nil and PetsCatalog.ModelOf(petKey) ~= nil`.
- `PetDataMigration.Migrate(data: table, ctx: {GenerateId: () -> string, Now: number?, IsSpawnable: ((string) -> boolean)?, Scope: ("All" | "Pets")?}) -> Report`
  `Scope` default `"All"` (DataService load + ResetProfile). `"Pets"` (PetService.EnsureProfileState re-runs) skips
  steps 2-3 entirely: runtime re-runs never touch `Eggs`/`Cucumbers`.
  Mutates `data.Base` in place, idempotent, never errors on bad data (the caller still pcalls), **never changes
  `data.Base.Version`, never adds/removes cucumber/egg/build records, never touches keys outside `data.Base`**.
  Steps, in order:
  1. `base = data.Base`; not a table → `Report.Error = "NoBase"`, return. Missing `Pets`/`Eggs`/`Cucumbers`
     arrays → create `{}`; present but non-table → leave, warning.
  2. Eggs: each table record gets `Id` only if `not IsValidId(rec.Id)`. A **duplicate** egg Id is left alone
     (eggs are single-use: minting a new Id would turn a copy into a second hatchable egg); BaseSave Restore keeps
     the first and drops later copies (4.8). Counted `DuplicateEggIds` in the report.
  3. Cucumbers: `Id` if invalid; later duplicates of a cucumber Id get a new one (cucumbers are not consumables).
     `PetBuffs` left as is (restore filters it).
  4. Pets (each table record; non-table entries kept untouched, counted `Invalid`):
     `Id` assign if invalid; a later duplicate pet Id gets a new one (PLAN 8.1); only when the field is **missing/invalid**: `SourceEgg = PetStats.EggOf(rec.Pet)`
     (nil when unknown species), `Material = ""` (else `PetStats.NormalizeMaterial`), `Mutations = {}` or
     `NormalizeMutations(existing)` (strings → array), `AcquiredAt = 0`, `AbilityRemaining = ABILITY_PERIOD`
     (also when non-finite or outside `[0, ABILITY_PERIOD]`). Existing valid values are never overwritten.
     `Pos`, `SourceEggId`, `EggKg` and unknown fields are never touched.
  5. Roster:
     - `PetSchemaVersion` missing/`< 1` (legacy): `base.PetRoster = SelectInitialRoster(...)`;
       `base.PetNoticePending = true` if at least one legacy pet record existed.
     - otherwise repair: non-table → `{}`; keep strings that are owned IDs, first occurrence only, max `SLOTS`
       (extras simply leave the roster; they stay owned).
  6. `base.PetSchemaVersion = SCHEMA_VERSION` **last**.
  `Report = {Legacy = boolean, IdsAssigned = n, DuplicateIds = n, DuplicateEggIds = n, Invalid = n, RosterSize = n,
  EggIds = n, CucumberIds = n, UnknownTraits = n, Changed = boolean, Error = string?, Warnings = {string} (<= 20)}`.
  (`Changed` = anything was written; the save is requested by PetService.EnsureProfileState, 3.5.)
- `PetDataMigration.SelectInitialRoster(pets: {table}, isSpawnable, slots) -> {string}` - valid-ID records whose
  species is spawnable and `PetStats.Calculate(rec).Valid`; sorted `PetStats.Compare(…, "Income")`; first `slots` IDs.
- `PetDataMigration.RepairRoster(base) -> changed: boolean` (step 5 repair branch; also used by PetService).
- Never: yields, `RequestSave`, spawns, reads Workspace.

### 3.5 `ServerStorage.PetService` (WP-PETSVC)
Canonical ownership, roster, runtime models, roaming, ability countdowns, PetState payloads. Absorbs the
spawn/roam code of PetHatchService (L44-56 constants except hatch ones, L87-246 helpers/SpawnPet/ClearPlotPets,
L365-378 planner, L386-393 plot wiring) with the same numbers (`PetBalance.PET`).

**Init(deps)**:
```lua
PetService.Init({
	DataService = DataService,            -- required
	IncomeService = IncomeService,        -- optional (nil: pets earn nothing)
	PetBuffService = PetBuffService,      -- optional (nil: ability rolls are skipped, countdowns still run)
	Effects = PetEffectsBus,              -- optional
	SendState = function(player, payload) end, -- required: PetServer wraps Remotes.PetState:FireClient
	Clock = function() return workspace:GetServerTimeNow() end, -- optional
	Rng = Random.new(),                   -- optional: ability rolls + roam (separate Random objects inside if nil)
	Spawner = nil,                        -- optional test override: (player, plot, record, worldPos) -> Model?
})
```
**Start()**: creates `plot.Pets` folders for every plot under `workspace.Map.Lobby.Plots`; watches each plot's
`Owner` attribute (Owner no longer the attached player's UserId → `DetachPlot(player, "PlotLost")`) and `Size`
(replan every pet on that plot from its clamped current logical position); watches
`workspace.CyclePhase` and each player's `RaidLive` attribute for the combat lock; starts ONE Heartbeat scheduler
(roam planning every `TIMING.ROAM_PLAN`, ability countdowns every `TIMING.ABILITY_TICK`, totals push ≤ 1 Hz);
registers `DataService.OnBeforeClose(Freeze, 10)` and `DataService.OnBeforeClose(SyncRecords, 30)`;
`IncomeService.OnTotalsChanged` (→ throttled `Kind = "Totals"` message, ≤ 1 per `TIMING.TOTALS_PUSH` per player,
7.2); `DataService.OnProfileReset(OnReset)`; `Players.PlayerRemoving` (SyncRecords if data present, then
DetachPlot, then drop runtime AND the player's `Session` entry). **Late-start sweep** (last step of Start): for
every player with `BaseRestored == true` whose plot (`plot.Owner == UserId`) exists and who is not attached:
`EnsureProfileState` + `AttachPlot` (covers BaseSave Restore having run before PetService started, 4.8). The
scheduler also retries `Unavailable` roster pets every `TIMING.UNAVAILABLE_RETRY` (30 s): `ModelOf` non-nil → spawn
(OD-13).

**State owned** (module-local):
- `Session[player] = {Revision: int (monotonic for the whole player session), ClientReady: bool, LastTotalsPush,
  StateLimiter, RosterLimiter, ReplyLimiter}` - created on the first request or runtime build, **survives runtime
  rebuilds**, cleared only on PlayerRemoving.
- `Runtime[player] = {Generation, PetsArray (identity), Index = {ById, BySourceEgg}, Plot?, Attached: bool,
  Frozen: bool, Pets = {[petId] = RuntimePet}, PendingAutoEquip = {petId...} (ordered, runtime only)}`.
- `RuntimePet = {Id, Status, Model?, Segment, IdleUntil, Radius, PresentationPending: bool, PendingSpot?, Stats,
  Despawning: bool}`. `PresentationPending` is set by GrantFromEgg (equipped hatch) and cleared ONLY by
  `FinishPresentation` or a generation change; DetachPlot/AttachPlot/EnsureProfileState/Equip never clear it.
Status ∈ `"Active"` (spawned, in roster) · `"Pending"` (in roster, PresentationPending) · `"Idle"` (in roster, no
attached plot) · `"Unavailable"` (in roster, no model / spawn failed / model vanished) · `"Reserve"` (owned, not in
roster) · `"Invalid"` (unknown species / invalid record). Status is derived: PresentationPending wins over Idle.
When a rebuild happens and `Session.ClientReady` is true, push an unsolicited Full (new Generation, next Revision).

**Public API** (all non-yielding unless stated):
| Function | Semantics |
|---|---|
| `WaitReady(timeout: number?) -> boolean` | **yields** until `Start` ran (default 30 s). Only PetServer-internal / tests; BaseSave uses `IsStarted()` + `WaitReady(2)` (4.8). |
| `IsStarted() -> boolean` | section 0.4. |
| `IsReady(player) -> boolean` | profile loaded, not closing, runtime built. |
| `EnsureProfileState(player) -> ok: boolean, err: string?` | Idempotent. Needs `DataService.GetData`; if `GetMigrationReport(player).Failed == true` (the load-time pcall threw) → `false,"MigrationFailed"` (pets inert this session, records untouched; a report with only `Error = "NoModule"` is not a failure). Runs `PetDataMigration.Migrate(data, {…, Scope = "Pets"})` again (repairs roster; idempotent; never touches Eggs/Cucumbers), (re)builds Runtime when missing or generation/PetsArray changed (a rebuild first `DetachPlot`s). **Save**: on the first successful call per generation, `local r = DataService.GetMigrationReport(player); if r and r.Changed then DataService.RequestSave(player) end`, and likewise whenever its own re-run reports `Changed` (PLAN 8.2 "request a coalesced save"). Errors: `"NotLoaded"`, `"Closing"`, `"MigrationFailed"`. |
| `AttachPlot(player, plot) -> spawned: number` | Requires EnsureProfileState ok and `plot.Owner == UserId`. Sets `Runtime.Plot`, spawns every roster pet that has no model and **no `PresentationPending`** at its saved `Pos` (anchor-local → world, clamped) or plot centre, registers pet producers (`IncomeService.SetPetProducer`) only after a successful spawn. Idempotent (already-attached pets are kept). |
| `DetachPlot(player, reason: string)` | Settles + removes pet producers, destroys runtime models (sets `Despawning` first), statuses → Idle (roster) / Reserve; `PresentationPending` untouched. **Never touches records or roster.** reason ∈ `"Left" "PlotLost" "Reset" "Reload" "Rebuild"`. |
| `SyncRecords(player, anchor: CFrame?)` | For every **spawned** pet writes `record.Pos = {x, 0, z}` (anchor-local of `PetMotion.Sample` at now; anchor = BaseSave's `AnchorOf(plot)` formula when nil) and `record.AbilityRemaining`. Close-phase rule 0.13: gates only on `GetData ~= nil` (works while Frozen/closing). Silent when no data/plot. Called by BaseSave `Collect`. |
| `HasSourceEgg(player, eggId: string) -> boolean` | any owned record with `SourceEggId == eggId`. Reads `Index.BySourceEgg` when the runtime index is current, else scans `data.Base.Pets` directly (works before Start / before the runtime exists; never errors, false on no data). |
| `GrantFromEgg(player, egg: EggInfo, petKey: string) -> record?, info` | **The synchronous hatch commit** (8.2 step 4). `EggInfo = {EggId: string?, EggName: string (short), Kg: number?, Material: string?, Mutations: string?}`. Refuses (`nil, {Error=...}`) when not ready / frozen / unknown species / `#base.Pets >= PetBalance.MAX_OWNED` (`"InventoryFull"`). If `HasSourceEgg(EggId)` → removes the egg record (if still present) and returns `existingRecord, {Duplicate = true}`. **Order (pinned)**: (a) every fallible step first - `PetStats.Calculate`, `NormalizeMutations`, GUID, record table, and locating the egg index with `type(rec) == "table" and rec.Id == EggId` (not found → nil index, fine); (b) then, back to back with nothing that can throw in between: `if idx then table.remove(base.Eggs, idx) end`, `table.insert(base.Pets, record)`, roster append (only if `#roster < SLOTS and not IsCombatLocked(player) and IsSpawnable(petKey)`), `Index.ById[record.Id] = record`, `Index.BySourceEgg[EggId] = record`; (c) runtime entry (`PresentationPending = true` when equipped), delta push. When the only refusal to equip was the combat lock and slots were free, append the id to `Runtime.PendingAutoEquip` (OD-11). Returns `record, {Equipped = boolean, Reserve = boolean, AutoEquipAfterCombat = boolean}`. Does NOT RequestSave (caller does). PetDev grants use the same path (index updated identically). |
| `FinishPresentation(player, petId: string, spot: Vector3?, generation: number?) -> boolean` | Clears `PresentationPending` (idempotent). Then: if generation matches, record owned and still in roster, plot attached **and `RuntimePet.Model == nil`** → spawn at `spot` (clamped) → Active + producer; a pet that already has a model (spawned by AttachPlot/Equip meanwhile) is left as is; otherwise status recomputed. Never grants. |
| `Equip(player, petId) -> ok, err?` | Errors: `"NotLoaded" "Closing" "CombatLocked" "NoPlot" "NotOwned" "SlotsFull" "Unavailable"`. `"NoPlot"` when `not Runtime.Attached` or `Runtime.Plot.Owner ~= UserId` (PLAN 10 plot-ownership check). Already equipped → `true` (no-op). Sets `AbilityRemaining = ABILITY_PERIOD`, spawns unless `PresentationPending` or a model exists, `RequestSave`. |
| `Unequip(player, petId) -> ok, err?` | Absent → `true`. Settles+removes producer, despawns, `AbilityRemaining = ABILITY_PERIOD`, `RequestSave`. `CombatLocked` blocks it too. Allowed without a plot (roster-only change). Also removes the id from `PendingAutoEquip`. |
| `EquipBest(player, mode: "Income" or "Combat") -> ok, err?` | Same refusals as Equip (incl. `"CombatLocked"`, `"NoPlot"`). Candidates = owned, `Stats.Valid`, spawnable; sorted `PetStats.Compare(mode)`; top `SLOTS` become the roster (in that order) atomically. Members kept keep `AbilityRemaining`; new members 60; removed members 60 + despawn. Same input → same roster. Clears `PendingAutoEquip`. |
| `HandleRequest(player, request: table)` | Limiters live in `Session[player]` (never in Runtime) and are applied **before** any validation or reply, whatever the load state: GetState over its limit → dropped silently (no reply; GetState is never a blocking pending request on the client, 3.11); roster action over its limit → a `RateLimited` Result reply only while `ReplyLimiter` (1/s, burst 2) allows, else dropped silently. Then `Core.ValidateRequest`, dispatch, `SendState` (Full for GetState, Delta with `Result` otherwise). Called by PetServer. |
| `IsCombatLocked(player) -> boolean` | `workspace:GetAttribute("CyclePhase") == "Night" or player:GetAttribute("RaidLive") == true`. Mirrors to player attribute `PetCombatLocked` on change. On the locked → unlocked transition (not Frozen, attached): equip `PendingAutoEquip` ids in order while `#roster < SLOTS` and the record is still owned, not in roster and spawnable (`AbilityRemaining = 60`, spawn, producer), then clear the list, one delta, one `RequestSave` (OD-11). |
| `GetActivePets() -> {ActivePet}` | Cached read-only array, rebuilt on any status change: `ActivePet = {PetId, Player, UserId, Model, Plot, Stats}`. Callers must not mutate. |
| `GetLogicalPosition(petId, now: number?) -> Vector3?` | `PetMotion.Sample` of the server segment (ground point). |
| `GetFullState(player) -> PetStatePayload` | section 7.2 (Kind "Full"). |
| `Freeze(player)` | Rejects further roster actions (`"Closing"`), grants and presentations, stops countdowns for that player. Close-phase rule 0.13. |
| `GetDiagnostics() -> table` | `Active, Reserve, Invalid, SpawnFailures, Rolls, ProcSuccess, ProcNoTarget, DeniedRequests, Repairs, UnknownTraits` (records with unknown mutation/material names, counted once per record per runtime build), `ModelVanished, AutoEquipped, InventoryFull, OwnedMax` (largest `#Pets` seen), `ProfileBytesMax` (the scheduler
JSON-encodes each attached player's `data` once per 120 s in pcall; WarnOnce above 1 MB). |

**Spawn procedure** (the moved `SpawnPet`, now "spawn an EXISTING record", never a grant): `PetsCatalog.ModelOf(record.Pet)`
(nil → status Unavailable, `SpawnFailures` diag, warn-once) → clone, `Name = record.Pet`, shrink-only fit to
`PET.FIT`, every BasePart `Anchored/CanCollide=false/CanTouch=false/CanQuery=false/Massless`, BodyMovers destroyed,
PrimaryPart = PrimaryPart or `Root` or first BasePart (none → destroy, Unavailable), `RootToVisibleBottom`, position
clamped into the plot (`EDGE_INSET` + radius), random yaw, attributes of section 6.1 (initial idle segment
From = To = pos, Start = End = now, `RoamSeq = 1`), `model:SetAttribute("PrismaticLoop", true)` **then**
`pcall(CucumberMutations.ApplyLook, model, material or nil, MutationString)` (the pre-set attribute makes ApplyLook
skip its server `while model.Parent` colour loop - which would exit at once anyway because the model is unparented,
and would otherwise be a per-pet server loop; emitters/light are still added; PetCardClient animates PRISMATIC
colour locally, 3.12), backstop: destroy any child of `plot.Pets` whose `PetId` attribute equals this pet's id,
tag `PlotPet`, parent `plot.Pets` (last). After parenting connect `model.Destroying` once (stored on the
RuntimePet, disconnected on despawn): when it fires and `RuntimePet.Despawning` is false (PetService did not
remove it), set status `Unavailable`, `IncomeService.RemovePetProducer(petId)`, rebuild the `GetActivePets` cache,
push a delta, `ModelVanished` diag (the 30 s retry respawns it); the handler ignores a model that is not
`RuntimePet.Model` (an old orphan). Roam planning = the moved
`PlanLeg`/`PickPoint`/`Blocked` logic on the server segment; every published segment starts in the future:
`Start = now + TIMING.ROAM_LEAD` (0.3 s), `End = Start + travel` (clients receive it before it starts; the server's
`GetLogicalPosition` samples the same segment, so both still agree; `Sample` idles at From until Start). Every
publish goes through `PetMotion.ToAttributes` (RoamSeq last, +1); "no free point" publishes an idle segment at the
clamped current point. `RoamIdleUntil` is internal state (no attribute).
`PetView.Stats.AbilityDuration`: Yield/Haste `PetBalance.ABILITIES[k].Duration`; Guard `PetBuffService.GuardSeconds()`
when available else `PetStats.GuardSeconds(DEFAULT_DAY_SECONDS, DEFAULT_NIGHT_SECONDS)`; Wild → nil plus
`AbilityDurations = {Yield = n, Haste = n, Guard = n}`; None → nil. Effect/short texts come from the PetStats text
helpers (3.2), never literals.

**Ability scheduler** (every `ABILITY_TICK`, `dt = min(now - last, 5)`): for each player with `IsReady`, not Frozen,
`Attached`, `player:GetAttribute("BaseRestored") == true`, and each Active pet whose Ability ≠ "None":
`record.AbilityRemaining -= dt`; if `<= 0` → `record.AbilityRemaining = ABILITY_PERIOD` **then** one draw
`rng:NextNumber() < Stats.AbilityChance`; on success `PetBuffService.Grant(player, {PetId, DisplayName, From = logical pos}, Stats.Ability, now)`
(skipped when no PetBuffService); count diagnostics; push a delta for that pet; `DataService.RequestSave(player)`.
No backlog replay: at most one roll per pet per tick.

**Core (pure, for tests)**: `Core.ValidateRequest(req) -> ok, cleaned|errCode`; `Core.NewLimiter(ratePerSec, burst) -> limiter`
with `limiter:Take(now) -> boolean`; `Core.Equip(roster, petId, ctx) -> newRoster|nil, err`; `Core.Unequip(roster, petId) -> newRoster`;
`Core.EquipBest(pets, statsOf, isSpawnable, mode, slots) -> roster`; `Core.GrantFromEgg(base, eggInfo, petKey, ctx) -> record, info`
(ctx = `{GenerateId, Now, AllowRoster: boolean, Locked: boolean, Slots, MaxOwned, IsSpawnable, Index?}`; same pinned
order as the API row; updates `ctx.Index` when given); `Core.StepAbility(entries, dt, rng) -> rolls`
(`entries = {{Id, Remaining, Chance}}`, mutates Remaining, returns `{{Id, Success}}`); `Core.BuildPetView(record, runtimePet?, equipped) -> PetView`.

**Studio hooks**: none of its own (PetServer's `PetDev` calls the API).
**Totals push**: forwards `IncomeService.OnTotalsChanged` as a `Kind = "Totals"` message (7.2; does not advance
Revision), ≤ 1 per `TOTALS_PUSH` per ClientReady player.
**Never**: increment Cash; call `ZombieAPI`; derive ownership from `PlotPet` tags; delete/overwrite a record other
than via `GrantFromEgg`/equip fields/`SyncRecords` fields; yield inside any function above except `WaitReady`;
keep a per-pet loop/thread; spawn a pet that is not in the roster.

### 3.6 `ServerStorage.IncomeService` (WP-INCOME)
The one Cash-paying income loop (cucumbers + pets).

**Init(deps)**: `{DataService (required), ModifiersOf = function(model, now) -> {Modifier} (optional, default returns {}), Clock (optional)}`.
`Modifier = {Kind = string, Mult = number, ExpiresAt = number}`.
**Start()**: find-or-create `Remotes.CucumberIncome` and `Remotes.PetIncome` (RemoteEvents); connect
`CollectionService` `PlacedCucumber` added/removed **before** sweeping `GetTagged`; per-cucumber attribute
listeners (`Owner Zone TypeName Golden Material Mutations SizeTier` → `Refresh`; `Owner` → re-key, below), stored
on the producer and disconnected when it is unregistered (a re-tag after RestoreCarry never stacks connections);
one deadline loop (`TIMING.INCOME_TICK`); `DataService.OnBeforeClose(FlushOwner, 20)`; `DataService.OnProfileReset`
(drop that owner's ledger AND set `LastSettled = now` on every producer of that owner, so removals that arrive
late - e.g. BaseSaveAPI.Reset's deferred tag-removed signals - settle 0 into the fresh profile);
`Players.PlayerRemoving` (FlushOwner - a no-op if the pre-close flush already ran - then mark the owner Forgotten).
`Started = true` is set before the first tick is scheduled.

**Registration on tag add (rule 0.14)**: register every `PlacedCucumber`-tagged Model; never check `Parent`,
workspace membership or plot membership at add time (the tag is added before parenting). Eligibility is evaluated
at pay time only.

**Producers**: cucumber key = the Model; pet key = PetId. `Producer = {Kind = "Cucumber"|"Pet", OwnerId, Model, PetId?,
BaseRate, Mods (cached), LastSettled, PendingPopup, Conns}`. Cucumber eligibility for paying (evaluated at settle /
tick time) = tagged `PlacedCucumber`, `Owner` number, `IsDescendantOf(workspace)` (exactly today's rule, so
CucumberBase = today's CashPerSec). Pet producers pay only while `Model:IsDescendantOf(workspace)` (else settle at 0;
PetService also removes them on `Destroying`, 3.5).

**Ledgers and owner states**: ledgers are keyed by **UserId**. Owner state per UserId: `Live` → `Flushed`
(FlushOwner ran) → `Forgotten` (PlayerRemoving). A settlement for an owner that is not `Live`, or whose player
is not `DataService.IsLoaded`, is **discarded** (diag `LateSettles`), never stored - no ledger is ever re-created
for a departed or flushed owner.

**Producer removal semantics** (PLAN 7 rules 2, 5, 7):
- `PlacedCucumber` tag removed (Destroy, plot release, `ClearAllChildren`, BaseSave clears, Grab, PickUp): settle
  to now with the **cached** mods into the ledger of `Producer.OwnerId` (subject to the owner-state rule), then
  unregister (disconnect `Conns`). Settled cash is paid by the next tick; removal never undoes earned cash.
- `Owner` attribute change: settle to now into the OLD `OwnerId`, then re-key the producer to the new owner (or
  leave it unpaid while `Owner` is not a number).
- Re-parenting out of workspace: nothing special - the next tick settles that producer at 0 for the ineligible span
  (the eligibility check happens per tick, at the tick boundary).

| Function | Semantics |
|---|---|
| `Refresh(model, now?)` | Settle the cucumber producer to `now` with its **cached** mods, then recompute `BaseRate = CucumberValues.RateOfInstance(model)`, re-pull `ModifiersOf(model, now)`, stamp attributes `BaseRate` and `Rate` (= BaseRate × `min(RATE_HARD_CAP, Π live Mult)`), mark totals dirty. Registers the model if tagged and not yet registered. Callers mutate buff state FIRST, then call Refresh. |
| `SetPetProducer(player, petId, model, ratePerSec, now?)` | Add/replace; settles an existing one first. Non-finite/negative rate → 0 + diag. |
| `RemovePetProducer(petId, now?)` | Settle then drop (popup share discarded). Unknown id: no-op. |
| `SettleOwner(player, now?)` | Settle every producer of that owner into its ledger (no profile write). |
| `FlushOwner(player) -> boolean` | Settle + one `DataService.Increment(player, "Cash", pending, true)` now, no remote events. **The only path allowed to credit a closing owner**: gates only on `DataService.GetData(player) ~= nil` (rule 0.13 - no `IsClosing`, no `player.Parent`, no `IsLoaded`-via-Parent checks). Afterwards the owner state becomes `Flushed` (later settlements are discarded). Idempotent: a second call credits 0. |
| `GetTotals(player) -> Totals` | `{CucumberBase, Cucumber, Pet, Total}` (numbers, current rates, not settled cash). |
| `GetThreatIncome(player) -> number?` | `CucumberBase`; **nil before Start** (callers fall back, 4.6); 0 for a started service and an owner with no producers (truthful). |
| `GetCucumberRates(model) -> effective?, base?` | |
| `OnTotalsChanged(fn: (player, Totals) -> ()) -> disconnect: () -> ()` | Plain callback list (no Instances). Fired deferred-coalesced after producer/modifier/expiry changes, and from the tick **only for owners whose Total or CucumberBase changed** by more than a relative 1e-6 since the last fire. |
| `IsStarted() -> boolean` | section 0.4; LeaderstatsService's fallback and ZombieRaidService's IncomeOf read it. |
| `GetDiagnostics()` | `PaidCucumberCash, PaidPetCash, CatchupClamps, CreditFailures, InvalidRates, Producers, LateSettles, Flushes`. |

**Tick** (deadline `nextTick += INCOME_TICK`; if more than one tick behind, `nextTick = now + INCOME_TICK`):
per producer `elapsed = now - LastSettled`, clamped to `INCOME_MAX_CATCHUP` (clamp → diag, start = now − 5);
amount = ∫ BaseRate × mult(t) with the interval split at every cached `ExpiresAt` inside it; pet amount = rate ×
elapsed. Per owner: sum (+ ledger); owner must be `Live`, `player.Parent == Players`, `DataService.IsLoaded`, not
`IsClosing` (the regular tick and SettleOwner keep skipping closing owners; only FlushOwner may credit them);
`ok = DataService.Increment(player, "Cash", total, true)`; **only if ok** append that owner's
cucumber (Model, amount) pairs to the CucumberIncome batch and pet (Model, amount, PetId) to the PetIncome batch.
After the owner loop: `CucumberIncome:FireAllClients(models, amounts)` and
`PetIncome:FireAllClients(models, amounts, petIds)`, each only when non-empty. Expired cached mods → `Refresh` the
model after paying (restamps `Rate`). Totals: writes `player.Data.CashPerSec.Value = Total` (find-or-create the
NumberValue; unsaved) and fires OnTotalsChanged only on change (row above).

**Core**: `Core.SettleAmount(baseRate, mods, t0, t1, cap) -> amount` (with splits, cap = RATE_HARD_CAP);
`Core.EffectiveMult(mods, t, cap) -> number`; `Core.ClampElapsed(t0, t1, maxCatchup) -> start, clamped`.
**Never**: read the `Rate` attribute as an input; pay from more than one loop; fire CucumberIncome for mid-second
settlements; credit an owner whose profile is closing **except through FlushOwner**; store a settlement for a
non-`Live` owner; round amounts.

### 3.7 `ServerStorage.PetBuffService` (WP-BUFF)
Cucumber effect state (runtime truth = model attributes, section 6.2), eligibility, targeting, expiry, theft denial.

**Init(deps)**: `{IncomeService (optional), Effects (optional), Clock (optional), Rng = Random (optional),
Snapshot = function(player) end (optional; default: deferred pcall of ServerStorage.BaseSaveAPI.Snapshot:Invoke(player))}`.
**Start()**: tracks `PlacedCucumber` added/removed (a set of cucumbers carrying any `PetBuff_*`; rule 0.14: every
tagged Model is tracked on add regardless of Parent - eligibility/footprint are evaluated only at grant time), one
sweeper every `TIMING.BUFF_SWEEP` (expired → attributes removed → `IncomeService.Refresh(model)`).

| Function | Semantics |
|---|---|
| `Serialize(model, now?) -> {BuffRecord}?` | **Pure/stateless, works before Init.** Unexpired valid buffs from attributes → `PetBuffs` records (5.4); nil when none. |
| `StampFromRecord(model, petBuffs, now?)` | **Pure/stateless, works before Init.** Validates each record (known Kind, finite `ExpiresAt > now`, Guard `Charges >= 1` integer, `SourcePetId` string ≤ 64 or absent), one per Kind (first wins), writes the attributes. Invalid input → nothing written. |
| `ModifiersOf(model, now) -> {Modifier}` | Live Yield/Haste as `{Kind, Mult, ExpiresAt}` (Guard never). Injected into IncomeService. |
| `IsEligible(player, model, kind, now) -> boolean` | Rule 8.4 below. |
| `Grant(player, source: {PetId: string, DisplayName: string, From: Vector3?}, ability: string, now?) -> ok: boolean, detail` | ability ∈ Yield/Haste/Guard/Wild. Wild: kinds with ≥1 eligible target chosen uniformly, then a uniform target. No target → `false, "NoTarget"` (attempt consumed, nothing queued). Success: attributes set (Yield/Haste `ExpiresAt = now + Duration`; Guard `ExpiresAt = now + GuardSeconds()`, `Charges = 1`), `IncomeService.Refresh(model, now)`, Effects `AbilityApplied`, deferred Snapshot; returns `true, {Kind, CucumberId, Model, ExpiresAt}`. Before Start → `false, "NotReady"`. |
| `TryBlockTheft(cucumber: Model, zombie: Model?, _now: any?) -> boolean` | **Synchronous, non-yielding, never errors.** Ignores its third argument **entirely** and always uses its own Clock (server epoch; ZombieRaidService works in `os.clock()`, which must never reach this module). `true` = deny this attempt: (a) inside grace → `true`, no charge; (b) live Guard with `Charges >= 1` → consume one (clear the Guard attributes at 0), grace until `now + GUARD.GraceSeconds`, count, then `task.defer` (Effects `ShieldBlocked` + Snapshot). Else `false`. Not started → `false`. |
| `ClearCucumber(model, reason: string, now?)` | Remove every `PetBuff_*` attribute + grace, `IncomeService.Refresh(model)` if still registered, deferred Snapshot when `reason ~= "Destroyed"`. reason ∈ `"Stolen" "PickUp" "Destroyed" "Dev"`. |
| `GuardSeconds() -> number` | `PetStats.GuardSeconds(day, night)` from `ServerScriptService.DayNightCycle` attributes `DayDurationSeconds`/`NightDurationSeconds`, else the workspace mirrors, else defaults (OD-22). Computed at grant time only. |
| `GetDiagnostics()` | `Grants{Yield,Haste,Guard}, NoTarget, ShieldBlocks, GraceRejects, Expired, Cleared`. |

**Eligibility (8.4 rule, all required)**: tagged `PlacedCucumber`, `IsA("Model")`, `Owner == player.UserId`,
player's plot (`plot.Owner == UserId`) and `model.Parent == plot.Placed`, `StolenBy == nil`, valid `CucumberId`,
`player:GetAttribute("BaseRestored") == true`, pivot inside the plot footprint (|local X|,|local Z| ≤ half size +
0.5: excludes carrier-dropped cucumbers lying in the lobby), no live buff of the same kind.
**Core**: `Core.PickKind(kindsWithTargets, rng)`, `Core.PickTarget(list, rng)`, `Core.TryBlock(state, now) -> blocked, newState`
(`state = {GuardExpiresAt, Charges, GraceUntil}`), `Core.ValidateRecords(petBuffs, now) -> {BuffRecord}`.
**Never**: write `Data.Base` directly; yield in TryBlockTheft; create instances under a cucumber model; stack or
refresh a same-kind buff; choose targets by value.

### 3.8 `ServerStorage.PetCombatService` (WP-COMBAT)
**Init(deps)**: `{PetService (required), Effects (optional), Clock (optional; os.clock-based deadlines are fine internally)}`.
**Start()**: one Heartbeat accumulator scan every `TIMING.COMBAT_SCAN`. Resolves `ServerStorage.ZombieAPI` lazily
each scan when the cached folder lost its Parent (ZombieRaidService rebuilds it at start).
Per scan: `infos = ZombieAPI.TargetInfos:Invoke()` once (fallback when the bindable is missing: `Zombies:Invoke()` +
attributes `Owner`, `State`; `Carrying = State == "Carry"`, `Grappling = false`); group by `Owner`; for each
`PetService.GetActivePets()` entry: candidates = infos with `Owner == UserId`; pet position =
`PetService.GetLogicalPosition(PetId)`; range = flat XZ distance ≤ `Stats.Range`; keep the current target while
valid unless a higher-priority one is in range (priority: `Carrying` > `Grappling` > nearest). A pet with no
deadline yet (newly active) or that just acquired a target after having none gets `NextShot[PetId] = now` (fires
on the first scan with a target in range). When `now >= NextShot[PetId]` and a target exists: revalidate (still in
this scan's list and in range), `amount = Stats.ShotDamage` (finite, > 0), **first**
`NextShot[PetId] = Core.NextShot(NextShot[PetId], now, Stats.ShotInterval, TIMING.COMBAT_SCAN)` (the cooldown is
consumed before the call, so a Damage that ever yields cannot cause a second hit), **then**
`ok = ZombieAPI.Damage:Invoke(model, amount, "Pet")` (**exactly 3 arguments**), on `ok` Effects `Shot`. A
module-level `Scanning` flag makes a scan that is still running skip the next Heartbeat. Forget deadlines/targets
of pets no longer active.
**Core**: `Core.ChooseTarget(petPos: Vector3, range: number, candidates: {TargetInfo}, current: Model?) -> TargetInfo?`;
`Core.Priority(info) -> 3|2|1`; `Core.NextShot(prev, now, interval, scan) -> number` =
`math.max(prev + interval, now + interval - scan)` (holds the long-run cadence at the nominal interval despite the
0.2 s scan quantisation, at most one shot per scan, no burst after a hitch).
**GetDiagnostics()**: `Shots, Rejected, DamageDealt, Scans`.
**Never**: build candidates from anything but ZombieAPI (no Humanoid/spatial scans, no Guardians); pass a 4th
argument to Damage; touch pet models or Cash; deal damage from a client message.

### 3.9 `ServerScriptService.PetServer` (Script, WP-SERVER)
Bootstrap, in this order (each step `pcall`-isolated; a failing module is logged loudly (`warn`) and skipped).
Income never depends on this script succeeding: if `IncomeService.IsStarted()` is not true 10 s after
LeaderstatsService starts, LeaderstatsService runs its legacy pay loop instead (4.5), and ZombieRaidService's
threat falls back likewise (4.6).
1. Find-or-create `ReplicatedStorage.Remotes` and RemoteEvents `PetRequest`, `PetState`.
2. `require` (via `ServerStorage:FindFirstChild(name)` - ServerStorage content exists before any Script runs, so no
   waiting; missing → skip + print): `IncomeService`, `PetEffectsBus`, `PetBuffService`, `PetService`,
   `PetCombatService`; `DataService` (required, WaitForChild).
2b. Config check (PLAN 14 Catalog row "unknown new key warns instead of crashing"):
   `local problems = PetBalance.Validate(PetsCatalog); for i = 1, math.min(#problems, 10) do warn("[PetServer] config: " .. problems[i]) end`;
   keep `#problems` for the `PetDiag` field `ConfigProblems`. Never aborts the bootstrap.
3. Init: `PetEffectsBus.Init({})` → `IncomeService.Init({DataService, ModifiersOf = PetBuffService and PetBuffService.ModifiersOf})` →
   `PetBuffService.Init({IncomeService, Effects = PetEffectsBus})` → `PetService.Init({DataService, IncomeService,
   PetBuffService, Effects = PetEffectsBus, SendState = function(p, payload) PetState:FireClient(p, payload) end})` →
   `PetCombatService.Init({PetService, Effects = PetEffectsBus})`.
4. Start in the same order: PetEffectsBus, IncomeService, PetBuffService, PetService, PetCombatService.
5. `PetRequest.OnServerEvent(player, request)` → `PetService.HandleRequest(player, request)` in pcall; when PetService
   is absent or not started reply `PetState:FireClient(player, {Kind = "Delta", Revision = 0, BaseRevision = 0, Result = {Ok = false, Error = "Unavailable", Action = tostring(action)}, ServerTime = now})`
   (rate-limited 1/s per player; excess dropped silently).
6. Only when PetService was required AND started successfully:
   `DataService.OnProfileLoaded(function(player) local ok, err = pcall(PetService.EnsureProfileState, player) if not ok then WarnOnce("ensure", "[PetServer] EnsureProfileState: " .. tostring(err)) end end)`.
7. Every 10 s: `ServerStorage:SetAttribute("PetDiag", HttpService:JSONEncode({Pet = …, Income = …, Buff = …, Combat = …, Fx = …, ConfigProblems = n}))`.
   Each module's diagnostics are read in pcall and only when that module is present.
8. Studio hook `workspace` attribute `PetDev` (section 10.3); every branch checks the module it needs is present
   and started (prints "PetDev: <module> unavailable" otherwise), and runs in pcall.
Never: gameplay formulas, Cash writes, direct record edits.

### 3.10 `ServerStorage.PetEffectsBus` (WP-SERVER)
**Init(deps)**: `{Clock (optional), Players (optional test fake)}`. **Start()**: find-or-create `Remotes.PetEffects`
(RemoteEvent); Heartbeat flush every `TIMING.FX_FLUSH`.
- `Emit(event: table, owner: Player|number, position: Vector3)` - stamps `event.Id` (server-wide increasing int),
  `event.T` (server time if absent), `event.Owner` (UserId); queues for recipients = the owner + every player whose
  character root is within `FX.RADIUS` studs of `position`. Never yields, never errors (bad input dropped + diag).
- Flush: one `PetEffects:FireClient(player, {T = now, Events = {...}})` per recipient with events; at most
  `FX.MAX_EVENTS_PER_BATCH` per recipient per flush, oldest dropped first (`Dropped` diag). Dropping never affects
  gameplay (callers already applied damage/buffs).
- **Core**: `Core.Recipients(ownerId, position, players) -> {Player}`; `Core.Enqueue(queue, event, cap) -> dropped`.
- `GetDiagnostics()`: `Emitted, Sent, Dropped`.

### 3.11 Client menu modules (WP-MENU)
- `PetController.Start(gui: ScreenGui (PlayerGui.CucumberMenus), menus: MenuControllerApi) -> {Destroy: () -> ()}` -
  returns immediately; in `task.spawn` waits for `Remotes.PetState`/`PetRequest` (60 s; failure → view status
  "Pets unavailable"). Sends `{RequestId, Action = "GetState"}` on start and whenever `OpenPanel` becomes "Pets"
  and no state is held or a gap was detected (≤ 1/s). **GetState is fire-and-forget**: it never creates a blocking
  pending request (the server may drop an over-limit GetState silently); if no Full arrives within 5 s the next
  open/gap retries. Owns sorting/filtering (local), selection, pending **roster** request (buttons disabled until
  the reply with that RequestId arrives or 5 s), error text from `Result.Error` (section 7.2 codes → friendly
  strings), the lock banner (`CombatLocked`), footer totals (also from `Kind = "Totals"` messages, which never
  touch Revision), the one-time `Notice` (→ `Notify.Info`), `Generation` handling (a Full/Delta whose `Generation`
  differs from the held one drops the held state first; a Delta with a new Generation → `NeedFull`),
  `ContextActionService:BindAction("PetsPanel", …, false, Enum.KeyCode.P, Enum.KeyCode.ButtonL3)` → `menus.Toggle("Pets")`
  **only when** `PlayerGui.CucumberMenus.Enabled` (EggHatchClient's `HideUi` disables every layer during a reveal),
  the `CucumberHUDDesign` attributes `BuildMode` and `BenchMode` are not true (the mirrors BaseHUDController
  already writes; same inputs as its `wanted`, 4.12); otherwise the action is consumed as a no-op (`Enum.ContextActionResult.Pass`).
  Gamepad: on open, when `UserInputService.GamepadEnabled`, `GuiService.SelectedObject = SlotRow.Slot1` (or the first
  PetCard when the roster is empty); on close, clear it if it is inside PetsPanel. Studio hook: `PetsPanel`
  attribute `PetsDev` = `"open" | "select:<n>" | "equip" | "best:Income"`.
  `PetController.Core`: `Sort(pets, mode)`, `Filter(pets, mode)`, `ApplyState(state, payload) -> newState, needFull: boolean`,
  `NewRequestId() -> string`, `FormatCountdown(seconds) -> string`.
- `PetView.Start(gui) -> View` - `View.Render(model: ViewModel)`, `View.SetStatus(text?)`, `View.Destroy()`, callbacks
  set by the controller: `View.OnSelect(fn(petId))`, `OnEquip(fn(petId, equip: boolean))`, `OnBest(fn(mode))`,
  `OnSort(fn(mode))`, `OnFilter(fn(mode))`. Pools cards and ViewportFrames by PetId; hover/press via Heartbeat
  `ButtonFX.Animate` on its own UIScale (never `HoverScale`, never `FXScale` on MenuController-owned objects).
  Texts use `NumberAbbrev.Abbrev` (`"$" .. x .. "/s"`), never HUDClient's Compact.

#### 3.11.1 Instance names built by `builders/build_petspanel.lua` (idempotent, edit mode)
- `StarterGui.CucumberMenus.PetsPanel` (Frame, Size offset 1140×735, centred) › `ResponsiveScale` (UIScale),
  `Content` (CanvasGroup, `Visible=false`, `GroupTransparency=1`) › `MotionScale` (UIScale), `Shadow`, `Body`,
  `Header` (› `Title` "PETS", `Subtitle` "0 / 6 ACTIVE"), `CloseButton`, `SlotRow` (› `Slot1`..`Slot6`), `Toolbar`
  (› `SortIncome`, `SortCombat`, `SortRarity`, `SortNewest`, `FilterAll`, `FilterActive`, `FilterReserve`,
  `BestIncome`, `BestCombat`), `PetGrid` (ScrollingFrame › `UIGridLayout`, `Empty`), `Details` (› `Preview`
  ViewportFrame, `PetName`, `Rarity`, `Traits`, `CashLine`, `CombatLine`, `AbilityName`, `AbilityEffect`,
  `AbilityChance`, `NextRoll`, `EquipButton`), `Footer` (› `PetCash`, `CucumberCash`, `TotalCash`), `LockBanner`,
  `Status`; `PetsPanel.Templates` (› `PetCard`, `SlotCard`, `Chip`, all `Visible=false`). Attribute
  `FitMargin = 1` on PetsPanel (0.95 before S7, see 12.1); `Reference` attribute naming the builder;
  `Content.ClickShield` (S7, 12.1: transparent non-selectable TextButton on the Body rect, ZIndex 1).
  Template children (PetView clones and fills exactly these names):
  - `PetCard` (TextButton, `Selectable = true`, `AutoButtonColor = false`) › `Preview` (ViewportFrame), `PetName`
    (TextLabel), `RarityBar` (Frame, rarity colour), `RarityText` (TextLabel, the rarity word), `Chips` (Frame ›
    `UIListLayout` horizontal; Chip clones), `Rate` (TextLabel, green `$X/s`), `EquippedTag` (TextLabel "ACTIVE",
    hidden when not equipped), `StatusTag` (TextLabel, e.g. "Temporarily unavailable", hidden when empty).
  - `SlotCard` (TextButton, `Selectable = true`) › `Preview` (ViewportFrame), `PetName`, `Empty` (TextLabel "Empty",
    shown when the slot is free). `Slot1..Slot6` are SlotCard clones.
  - `Chip` (Frame, `AutomaticSize = X`) › `Label` (TextLabel) + `UICorner`.
  - Selection: `PetGrid` and `SlotRow` have `SelectionGroup = true`; every Toolbar/Details/Close button
    `Selectable = true`; no manual `NextSelection*` wiring (automatic gamepad navigation inside the groups).
- `StarterGui.CucumberHUDDesign.LeftMenu.Pets` (Frame, Position `(1.07,0,0,0)`, Size `(1,0,0.455,0)`,
  `UIAspectRatioConstraint "Square"` AspectRatio 1 DominantAxis Height, ZIndex 2; shell cloned from `LeftMenu.Index`
  minus `BookIcon`/`Label`/`OpenIndex`) › `PawIcon` (frame-drawn: `Pad`, `Toe1`..`Toe4`), `Label` "Pets",
  `OpenPets` (TextButton, Size 1,1, ZIndex 30, transparent). **No** `ButtonFX.Prepare` on it.
- `StarterGui.EggRevealUI.SingleTemplate.PetStats` (TextLabel, Size `(0.42,0,0.036,0)`, Position `(0.5,0,0.80,0)`,
  AnchorPoint 0.5, FredokaOne, TextScaled, RichText, white + UIStroke 2.5 px `12,12,12` Contextual, `Visible=false`)
  and `…SingleTemplate.PetTraits` (Size `(0.42,0,0.03,0)`, Position `(0.5,0,0.762,0)`, same style, `Visible=false`).

### 3.12 Client world scripts (WP-WORLDFX)
- **PetEffectsClient** (LocalScript): listens `Remotes.PetEffects` (section 7.3). Shot: pooled neon projectile (≤
  `FX.MAX_PROJECTILES` alive; excess dropped) from the local pet's muzzle (`model.PrimaryPart.Position +
  (0, MUZZLE_HEIGHT, 0)` if the model with `PetId` is streamed, else `From`) to `To` in 0.12-0.2 s, small hit
  sparkle, colour `PetsCatalog.RARITY_GLOW[Rarity]`; also writes the local attributes `FxAimAt`, `FxAimUntil`
  (`T + 0.6`), `FxShotAt` (`T`) on that pet model for PetRoamClient. AbilityApplied: 0.25-0.4 s arc pet→cucumber,
  target pulse; when `Owner == LocalPlayer.UserId`: `Notify.Show(PetBalance.TEXT.ProcToast:format(PetName,
  ABILITIES[Ability].DisplayName, PetStats.AbilityShort(Ability, math.floor(ExpiresAt - T + 0.5))), ability colour)`.
  ShieldBlocked: shard ring burst + one `PlayFXAt` sound with `Key`/`MinInterval`; owner toast
  `PetBalance.TEXT.ShieldToast`. Shield shells: for every streamed `PlacedCucumber` with a live `PetBuff_Guard`,
  a green `SelectionBox` (LineThickness ~0.04, Transparency ~0.4) adorned to `PlotHitbox`, **parented to a local
  folder `workspace.CurrentCamera.PetFxLocal`** (never under the cucumber model: the move ghost clones children).
  Only models passing the rule-0.14 filter (`Parent.Name == "Placed"` inside `workspace.Map.Lobby.Plots`; the
  `"<name> Preview"` ghost is parented to workspace and carries the cloned tag + `PetBuff_*` attributes) get a
  shell, re-evaluated lazily. Streaming: a shell whose `PlotHitbox` streams out is removed and rebuilt when a
  `PlotHitbox` BasePart re-appears under the still-tagged model (`DescendantAdded` watcher); the `PetId → model`
  index drops entries on `AncestryChanged` to nil and re-adds on the `PlotPet` added signal / `DescendantAdded`.
  Heartbeat stepping only; cull events whose endpoints are > `FX.RADIUS` from the camera.
- **PetCardClient** (LocalScript): tag `PlotPet`; BillboardGui `PetCard` parented to the pet's PrimaryPart (studs
  sizing: scale units only, `CARD_W 5.2 × CARD_H 1.9` studs, `AlwaysOnTop=false`, `LightInfluence=0`,
  `MaxDistance 60`): row 1 `DisplayName` in the rarity gradient colour (FredokaOne, stroke) followed by the rarity
  word (RichText, e.g. `Cosmo Cat <font size="…">· Legendary</font>` at ~70 % of the name size, same colour - a
  non-colour rarity cue; the card stays within its stud size), row 2 green
  `"$" .. NumberAbbrev.Abbrev(Rate) .. "/s"` (65,235,20 + stroke 12,12,12) plus a small ability glyph when
  `Ability ~= "None"`; re-render on `Rate` changes. `Remotes.PetIncome` popups `"+$X"` rising from the card top
  (same recipe as PlacedCucumberCardClient Popup), iterate `for i = 1, #amounts`, skip non-Instance models, global
  cap `FX.MAX_POPUPS` live popups. One Heartbeat stepper, which also cycles the colour of every streamed pet whose
  `Mutations` attribute contains `PRISMATIC` (client-local `Color` writes on its BaseParts, the ApplyLook recipe:
  `Color3.fromHSV((t * 0.12) % 1, 0.65, 1)` every 0.15 s; the server never runs that loop for pets, 3.5).
  Streaming: cards are keyed by model; when the card's PrimaryPart streams out (card `AncestryChanged` to nil or
  PrimaryPart nil) keep a `model.DescendantAdded` watcher and rebuild the card when the PrimaryPart (or a BasePart
  named `Root`) arrives while the `PlotPet` tag is present (same rule as PetRoamClient 4.13).
- Both read `PetBalance` for colours/texts; never compute rewards.

---------------------------------------------------------------------------------------------------------

## 4. Patches to existing scripts (anchors quoted from the snapshot)

### 4.1 `ServerStorage.DataService` (WP-DATA)
Change:
1. Header: dated paragraph describing migration, before-close hooks, generation, reset hook, template Version 2.
2. L66 `Base = {Version = 1, Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}},` → `Version = 2`. **Do not add
   `PetSchemaVersion` or `PetRoster` to TEMPLATE** (Reconcile would mark legacy profiles migrated).
3. Add `local HttpService = game:GetService("HttpService")` and
   `local PetDataMigration = script.Parent:FindFirstChild("PetDataMigration")` resolved with pcall(require) at first use
   (module may be absent in early stages → migration skipped, report `{Error = "NoModule"}`).
4. New state: `BeforeClose = {}` (`{Fn, Order, Seq}`), `ClosedProfiles = setmetatable({}, {__mode = "k"})`,
   `Closing = {}`, `Generation = {}`, `GenerationCounter = 0`, `MigrationReports = {}`, `ResetCallbacks = {}`.
5. New API:
   - `DataService.OnBeforeClose(fn: (player, profile, reason: string) -> (), order: number?)` - sorted ascending by
     `order` (default 50), then registration order. **fn must not yield.** Registration after profiles are closing
     is fine (no replay).
   - `DataService.IsClosing(player) -> boolean`
   - `DataService.GetGeneration(player) -> number?`
   - `DataService.OnProfileReset(fn: (player, profile) -> ())` - called synchronously (pcall each) at the end of
     `ResetProfile`, in registration order.
   - `DataService.GetMigrationReport(player) -> Report?` (the load-time report; `Failed = true` when pcall errored).
6. `local function RunBeforeClose(player, profile, reason)` - guard `ClosedProfiles[profile]`; set it and
   `Closing[player] = true`; call every callback in order inside `pcall` (warn on error).
7. In `OnPlayerAdded`, after L229-231 (REMOVED_KEYS loop) and **before** L232 `profile.OnSessionEnd:Connect`:
   pcall the migration `PetDataMigration.Migrate(profile.Data, {GenerateId = function() return HttpService:GenerateGUID(false) end, Now = os.time(), Scope = "All"})`,
   store the report (`Failed = true` + warn on error; the load continues). Keep L232-237 (`OnSessionEnd`) and the
   L238-241 early exit (`if player.Parent ~= Players then profile:EndSession() return end`) unchanged, so a player
   who left during `StartSessionAsync` never runs the close callbacks for a profile that was never exposed. **After**
   that early exit and before L242 `Profiles[player] = profile`: connect
   `profile.OnLastSave:Connect(function(reason) RunBeforeClose(player, profile, reason) end)`, then
   `GenerationCounter += 1; Generation[player] = GenerationCounter`. (Every OnBeforeClose callback additionally
   no-ops when `GetData(player)` is nil - rule 0.13.)
8. `OnPlayerRemoving` (L251-255) becomes:
   ```lua
   local function OnPlayerRemoving(player)
   	local profile = Profiles[player]
   	if profile then
   		RunBeforeClose(player, profile, "Leave") -- 2026-09-22: flush pets / income / base while the plot still stands
   		profile:EndSession() -- final save
   	end
   	Forget(player)
   end
   ```
9. `Forget` (L211-217) also clears `Closing`, `Generation`, `MigrationReports`.
10. `ResetProfile` (L166-179): after L171 (template deep copy) run the same pcall'd migration on `data`; then
    `GenerationCounter += 1; Generation[player] = GenerationCounter`; after `RequestSave` (L177) call every
    `ResetCallbacks` fn in pcall. Return value unchanged.
11. **(Orchestrator amendment, 2026-09-22) Studio-only isolated test profile.** Where `StartSessionAsync` builds the
    key (`PROFILE_KEY:format(player.UserId)`), use a helper:
    ```lua
    local function ProfileKey(player) -- 2026-09-22: Studio tests can run on an isolated key (ServerStorage attr PetTestProfileKey)
    	if RunService:IsStudio() then
    		local prefix = ServerStorage:GetAttribute("PetTestProfileKey")
    		if type(prefix) == "string" and prefix:match("^[%w_]+$") and #prefix <= 40 then
    			warn(("[DataService] STUDIO TEST PROFILE: using key %s_%d (not the real profile)"):format(prefix, player.UserId))
    			return ("%s_%d"):format(prefix, player.UserId)
    		end
    	end
    	return PROFILE_KEY:format(player.UserId)
    end
    ```
    (`ServerStorage`/`RunService` services resolved at the top if not already.) Same store, different key, so the
    real `Player_140977250` profile is never touched while the attribute is set; live servers ignore it.
    Expose `DataService.ProfileKeyOf = ProfileKey` for the integration agent's reports. PROFILE_KEY itself is
    unchanged.
Must NOT change: STORE_NAME, PROFILE_KEY, USE_MOCK_IN_STUDIO, AUTO_SAVE_PERIOD, SAVE_DEBOUNCE, VALUE_ORDER,
REMOVED_KEYS, `Set/Increment/Get/RequestSave` semantics, the kick messages, `Start`, Playtime loop, and the fact
that `Profiles[player]` is set only after migration. No new yields anywhere in `OnPlayerAdded` after
`StartSessionAsync`.

### 4.2 `ServerScriptService.PetHatchService` (WP-HATCH)
Keeps: trigger (`CheckEgg`, `TRIGGER_TICK`, `STEP_MARGIN`, `STEP_HEIGHT`), the roll (`Catalog.Roll(eggName, Rng)`),
the `PetHatch` remote creation (L59-70), `Hatched`/`PetsHatched`, dev `"ready"`.
Removes (moved to PetService): L45 `PET_TAG`, L49-54 roam/fit constants, L71 `PetsAssets` (keep only for the ready
print or drop the print's count), L87-246 (`PetsFolderOf` … `ClearPlotPets`), **L248-268 `PetHatchAPI` (retired,
OD-8)**, the planner half of the Heartbeat (L357, L365-378), L386-393 plot wiring, dev `"spawn:"`/`"clear"`
(re-implemented below).
New/changed:
- Requires: `ServerStorage.PetService` (FindFirstChild + pcall require; installed in the same stage - if missing,
  warn and leave eggs un-hatchable rather than fall back to the old transient grant), `ServerStorage.DataService`,
  `ReplicatedStorage.Modules.PetStats`, `PetBalance`; `HttpService`.
- `REVEAL_FALLBACK = PetBalance.TIMING.REVEAL_FALLBACK` (100, OD-6).
- State: `Presentations[token] = {Player, PetId, Spot, Generation, Timer}`, `ActiveToken[player] = token`
  (replaces `Pending`), `Locks[egg] = true`, `HatchBusy[player] = true` (set at 8.2 step 1, cleared on every exit
  path of `Hatch`: refusal, error, duplicate, after step 7).
- `CheckEgg` (L335-351): additionally skip when `egg:GetAttribute("Consumed")`, when `ActiveToken[owner]` or
  `HatchBusy[owner]`, and when `owner:GetAttribute("BaseRestored") ~= true` or `not PetService.IsReady(owner)`.
- `Hatch(player, egg)` implements 8.2 exactly (snapshot → re-validate → `PetService.GrantFromEgg` → consume egg →
  `DataService.RequestSave` → Begin). The Begin payload is 7.4. Duplicate (`info.Duplicate`) → no reveal, egg
  consumed, print. `GrantFromEgg` is called inside `pcall`: on error → warn once, `egg:SetAttribute("Hatching", nil)`,
  `Locks[egg] = nil`, `HatchBusy[player] = nil`, egg NOT destroyed; `nil, {Error = "InventoryFull"}` → same release
  and `FullUntil[player] = os.clock() + 10` (CheckEgg skips that owner until then; no retry spam); the egg stays
  un-hatchable until space exists (PetService itself pushes a Delta with
  `Result = {Ok = false, Action = "Hatch", Error = "InventoryFull"}` at most once per 60 s per player; PetController
  shows it with `Notify.Error` even while the panel is closed). The step-2 Snapshot
  invoke must be non-yielding (BaseSave's Snapshot is synchronous); assert it by comparing `os.clock()` before/after
  and warn once if a yield is ever observed (the per-player `HatchBusy` lock keeps "one hatch per player" either way).
- `Finish(player, token)` (L271-282) → `Presentation(token)`: look up `Presentations[token]`; must belong to `player`;
  remove it (and `ActiveToken`) first (idempotent); `PetService.FinishPresentation(player, petId, spot, generation)`;
  `Hatched` counter. A missing/forged/duplicate token does nothing.
- `PetHatch.OnServerEvent` (L382-384): `if action == "Opened" and type(token) == "string" and #token <= 64 then Presentation(player, token) end`.
- `PlayerRemoving` (L395-398): clear `ActiveToken[player]` and that player's `Presentations` (ownership already
  committed; the pet spawns from the roster on next join).
- Studio hook `PetHatchDev` keeps its name and `""` reset: `"ready"` unchanged; `"clear"` → `PetService.DetachPlot`
  for every player (runtime only); `"hatch:<EggName>[:<Pet>]"` → a real **grant** through `GrantFromEgg` with
  `EggInfo{EggId = nil, EggName = eggName}` + a reveal (states in its print that it grants a saved pet);
  `"spawn:<Pet>"` → same grant without a reveal (`FinishPresentation` immediately); fault injection for the S3
  interruption matrix - `"fail:pre-grant"`, `"fail:post-grant"`, `"fail:post-destroy"` arm a one-shot flag that
  makes the NEXT real `Hatch` stop at that boundary (`pre-grant`: error before `GrantFromEgg` → lock released, egg
  intact; `post-grant`: return right after `GrantFromEgg`, egg left in the world with `Hatching = true`, no
  Consumed/Destroy/RequestSave/Begin; `post-destroy`: return after `egg:Destroy()`, no RequestSave/Begin) and print
  which boundary fired. `HatchBusy`/`Locks` are still cleared on the fault path.
- Header: rewrite the SAVE/PLOT PETS bullets (ownership in PetService, stale "Nothing is saved yet" removed).
Must NOT change: odds/roll, trigger geometry, the Begin fields that already exist (7.4), one hatch at a time per
player.

### 4.3 `ServerScriptService.EggPlacement` (WP-HATCH)
- Services: add `local HttpService = game:GetService("HttpService")`.
- `Place` (L204-222): before `CollectionService:AddTag(placed, "PlacedEgg")` add
  `placed:SetAttribute("EggId", HttpService:GenerateGUID(false)) -- 2026-09-22: stable id (hatch transaction / saves)`.
- `RestoreEgg` (L243-256): before its `AddTag`, `EggId` = `record.Id` when valid (string, 1..64) else a fresh GUID.
  (Duplicate/consumed filtering is BaseSave's job - OD-18.)
- Header L29-30 stale "nothing happens when it reaches zero yet" → points to PetHatchService; L217 comment likewise.
Must NOT change: hatch times, placement rules, look attributes, the Owner-nil `ClearAllChildren` (ordering is fixed
by the PlotService defer, 4.9), `EggPlacementAPI` names/signatures.

### 4.4 `StarterPlayer.StarterPlayerScripts.EggHatchClient` (WP-HATCH)
- `PetHatch.OnClientEvent` (L511-539): read `local token = type(info.Token) == "string" and info.Token or nil`;
  every acknowledgment becomes `PetHatch:FireServer("Opened", token)`: busy path (L515), watchdog (L527),
  normal finish (L537). In the watchdog branch also `Token += 1` after `Busy = false` so the late pcall path cannot
  send a second ack.
- `BuildPet(petName, cf)` (L366-383) gains `material, mutations` params; after building:
  `pcall(CucumberMutations.ApplyLook, pet, material, mutations)`; `Reveal` passes `info.Material, info.Mutations`.
  (Add the CucumberMutations require if missing.)
- `BuildCard(info)` (L385-415): fill `PetStats`/`PetTraits` if the template has them (FindFirstChild; hide when the
  payload lacks `Stats`): PetStats = `<font color="#41EB14">$X/s</font>  ·  <ability line>` using `PetBalance.TEXT`
  and `NumberAbbrev.Abbrev`; PetTraits = material/mutation words via `CucumberMutations.Font` colours; hidden when
  normal with no mutations.
- After `Restore` of a successful reveal: if `info.AutoEquipAfterCombat` → `Notify.Info(PetBalance.TEXT.LockedHatchNotice)`,
  elseif `info.Reserve` → `Notify.Info(PetBalance.TEXT.ReserveNotice)` (outside the Busy window so the toast is visible).
Must NOT change: camera/HUD hide+restore (`HideUi`, `RestoreUi`, `Restore`), click stages, `WATCHDOG=95`,
`DevClick` hook, sounds.

### 4.5 `ServerScriptService.LeaderstatsService` (WP-INCOME)
The legacy pay code becomes a **dormant fallback**, never concurrent with IncomeService (critic log I09/I39):
- Keep (renamed with a `Legacy` prefix, bodies unchanged): L39-44 remote find-or-create (both scripts
  find-or-create `CucumberIncome`), L46-66 (`LegacyStampRate`, `LegacyEarningFor`, `LegacyIncomeOf`), L92-113
  (`LegacyPayIncome`). Remove: L82-90 `RefreshAllIncome` and L156-171 (tag + plot wiring) - the fallback computes
  rates on demand inside `LegacyEarningFor` (`StampRate` when the `Rate` attribute is missing).
- Mode latch: `local incomeMode = "Waiting"`. The L115-121 loop becomes: every `INCOME_TICK`: if `incomeMode ~= "Service"`
  and the lazy `IncomeService` (section 0.5) reports `IsStarted()` → `incomeMode = "Service"` **permanently** (the
  loop exits; print once). Else if `incomeMode == "Waiting"` and 10 s have passed since script start →
  `incomeMode = "Legacy"` + `warn("[LeaderstatsService] IncomeService not started - legacy income loop running")`.
  While `"Legacy"`, each tick checks `IsStarted()` FIRST (synchronously) and only then runs `pcall(LegacyPayIncome)`
  and writes `CashPerSec`/`Cash/s` via `LegacyIncomeOf`. Because the check precedes the payment in the same
  synchronous step and IncomeService's producers only earn from their registration time, the two can never pay the
  same span. The legacy branch is the only code that may write the cucumber `Rate` attribute, and only in Legacy mode.
- Add: `RefreshIncome(player)` sets `s.Rate.Value = NumberAbbrev.Abbrev(totals.Total)` from
  `IncomeService.GetTotals(player)` in Service mode; `CashPerSec` NumberValue is still created in `Setup`
  (L129-134) but written by IncomeService only (Service mode). Subscribe once (retry every 2 s until the module
  exists) `IncomeService.OnTotalsChanged(function(player, totals) ... end)`.
- Header: income paragraph now points to IncomeService and describes the fallback (2026-09-22).
Must NOT change: `Setup` order (folder parented last), `Strength` column, `Cash/s` StringValue name, NumberAbbrev use,
`OnProfileLoaded(Setup)`, `PlayerRemoving` cleanup. The patched LeaderstatsService is installed in the same stage as
IncomeService + PetServer (S2).

### 4.6 `ServerScriptService.ZombieRaidService` (WP-BUFF)
1. Header: dated paragraph (pet shields, threat income source, RaidLive, TargetInfos).
2. After the whole Modules block (L107-109), i.e. right after the L109 line
   `local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))`:
   `Lazy("PetBuffService")`, `Lazy("IncomeService")`, `Lazy("DataService")` helpers (section 0.5).
3. L194 `local DamageAPI, ZombiesAPI, IsZombieAPI, SlowAPI, StunAPI = …` → also `TargetInfosAPI = Bindable("TargetInfos")`
   (created before `API.Parent = ServerStorage`). `TargetInfosAPI.OnInvoke` next to `ZombiesAPI.OnInvoke` (L877):
   returns an array of `TargetInfo` (section 7.5) for entries `not Dead, not Shaded, not Underground, not Hold,
   model.Parent`.
4. `IncomeOf` (L268-272) → `local income = Lazy IncomeService; local v = income and income.IsStarted and income.IsStarted() and income.GetThreatIncome(player)`;
   `if type(v) == "number" and v == v then return v end`, then the old CashPerSec read as fallback (in that case
   LeaderstatsService's legacy loop is the CashPerSec writer, 4.5). Name/signature unchanged.
5. `TheftBlocked(entry, model)` helper placed before `Grab`:
   ```lua
   local function TheftBlocked(entry, model) -- 2026-09-22: a pet Leaf Shield (or its grace) denies this attempt
   	local buffs = PetBuffs()
   	if not buffs then return false end
   	local ok, blocked = pcall(buffs.TryBlockTheft, model, entry.Model) -- never pass os.clock() (different clock)
   	if ok and blocked then
   		entry.Target = nil
   		entry.StunUntil = math.max(entry.StunUntil, os.clock() + PetBalance.GUARD.StunSeconds) -- 0.8
   		entry.BlockedUntil = os.clock() + PetBalance.GUARD.StunSeconds -- no grab of ANY cucumber meanwhile
   		entry.AvoidModel, entry.AvoidUntil = model, os.clock() + PetBalance.GUARD.AvoidSeconds -- OD-10
   		return true
   	end
   	return false
   end
   ```
   (`PetBalance` required from ReplicatedStorage.Modules with a pcall fallback to literals 0.8 / 4.)
   The "recoil" of PLAN 4.4 is exactly this: the zombie stops (StunUntil zeroes its speed, L1230), drops its target,
   cannot grab for 0.8 s and avoids that cucumber for 4 s; no physics push. In `Tick`, the ordinary grab (L1271
   `if not Grab(entry, target) then entry.Target = nil end`) becomes
   `if os.clock() >= (entry.BlockedUntil or 0) then if not Grab(entry, target) then entry.Target = nil end end`
   (keep the following `return`). Bat stuns never set `BlockedUntil`, so their semantics are unchanged (OD-1).
6. `Grab` (L522-570): after L527-528 (`local torso …; if not torso then return false end`) insert
   `if TheftBlocked(entry, model) then return false end` and then
   `local buffs = PetBuffs(); if buffs then pcall(buffs.ClearCucumber, model, "Stolen") end` - both **before** the
   `carry` table (L531) and `RemoveTag` (L533). Covers ordinary (L1271), grapple final (L1048) and digger surfacing.
7. `StartGrapple` task (L1026-1050): at L1027 capture `local home = HomeRest(entry.Raid, target)` next to
   `local rest = target:GetPivot()`; L1029 becomes
   `local ok = not entry.Dead and target.Parent and CollectionService:HasTag(target, PLACED_TAG) and not TheftBlocked(entry, target)`;
   L1048 passes `home` instead of `HomeRest(entry.Raid, target)` (fixes the pulled-pose bug).
8. `NearestCucumber` (L1145-1148): skip `model == entry.AvoidModel and os.clock() < (entry.AvoidUntil or 0)`.
9. `RaidLive`: forward-declare `local SyncRaidLive` near the state block; define after `HasLiveThief` (L1535):
   `player:SetAttribute("RaidLive", (Raids[player] ~= nil and not Raids[player].Over) or HasLiveThief(player) or nil)`
   (nil, not false, when idle). **`CheckRaidEnd` has two early returns** (L691 `if raid.Over then return end` and
   the day branch L692-698 `... DayRaids[raid.Player] = nil end end return end`), so it is wrapped instead of
   appended to: rename the live body `local function CheckRaidEnd(raid)` (L689) to `local function CheckRaidEndBody(raid)`
   unchanged, and add right after it
   ```lua
   local function CheckRaidEnd(raid) -- 2026-09-22: every exit syncs RaidLive (pet combat lock)
   	CheckRaidEndBody(raid)
   	if raid.Player then SyncRaidLive(raid.Player) end
   end
   ```
   (all existing callers - Kill L747, Tick's Leave branch L1287, others - keep calling `CheckRaidEnd`). Also call
   `SyncRaidLive(player)`: after `Raids[player] = raid` (L1444 and the dev spawn L1655); after the dev spawn's
   reopen block (`raid.Over = false ... raid.Limit = ...`, L1656-1661); after `DayRaids[player] = raid` in
   `SpawnThief` (L1549) and after its `local entry = Spawn(variety, CFrame.new(ground), raid)` (both the nil-return
   and the success path); at the end of `EndRaid` (after the `Raids[raid.Player] = nil` / `DayRaids` clear) and of
   `Escape` (after the `raid.Over = true` ZombiesWin block, L785); in the dev `"end"`/`"kill"` branches.
   `SyncRaidLive` itself guards `player and player.Parent` (a leaving player just keeps nil).
10. **Pre-close raid settle** (critic log I57): register (feature-checked, via the lazy DataService)
    `DataService.OnBeforeClose(PreCloseRaids, 35)` - after PetService/IncomeService (10-30), before BaseSave's
    snapshot (40). `PreCloseRaids(player)` (rule 0.13; non-yielding; pcall per raid) for `Raids[player]` and
    `DayRaids[player]`: for each entry `not Dead` with `entry.Carry` → `RestoreCarry(entry, true, nil, true)`; then
    `ReturnDropped(raid, true)`. New optional params, defaults keep today's behaviour exactly:
    `RestoreCarry(entry, silent, dropAt, force)` - `force == true` skips the `raid.Player.Parent` destroy branch
    (L586-588) and uses `holder = HolderOf(raid.Plot)` when the carry holder is gone; `ReturnDropped(raid, noSnapshot)`
    - `noSnapshot == true` skips its BaseSaveAPI.Snapshot nudge (the order-40 snapshot follows). `EndRaid(raid, "Left")`
    also passes `force = true` to its `RestoreCarry` so a carried cucumber goes home whichever PlayerRemoving handler
    runs first. Result: the leave snapshot never saves a cucumber lying in the lobby or loses one held by a carrier.
Must NOT change: AI, damage numbers, `Damage/Zombies/IsZombie/Slow/Stun` semantics, raid counts/threat formula
(`ZombieCatalog.ThreatOf` input list), remote Kinds, cutscene, `ZombieDev` hook behaviour. Never yield inside
`Grab`/`TheftBlocked`.

### 4.7 `ServerScriptService.CucumberCarry` (WP-BUFF)
- Services (L64-69): add `HttpService`; add `Lazy("PetBuffService")`.
- `Place` (L944-956): before L956 `CollectionService:AddTag(taken, "PlacedCucumber")`:
  `taken:SetAttribute("CucumberId", HttpService:GenerateGUID(false))`. Nothing that can error after `Take()`.
- `RestorePlaced` (L1026-1038): before L1038 AddTag: `CucumberId` = `record.Id` if valid else a new GUID (do NOT
  write `record.Id` here - BaseSave/migration own record repair); then, if the module resolves,
  `pcall(buffs.StampFromRecord, model, record.PetBuffs)`.
- `PickUp` (L1107-1108): before `CollectionService:RemoveTag(placed, "PlacedCucumber")`:
  `pcall(buffs.ClearCucumber, placed, "PickUp")` (when resolvable) and `placed:SetAttribute("CucumberId", nil)`.
Must NOT change: lift/carry/drop logic, placement validation, the attribute order before the tag, `CucumberCarryAPI`.

### 4.8 `ServerScriptService.BaseSaveService` (WP-SERVER)
- Header: SAVE/RESTORE/LEAVE bullets updated (canonical pets, ids, buffs, readiness, flush).
- Requires: `PetService` (`ServerStorage:FindFirstChild("PetService")`, pcall require; nil → pets are neither
  collected nor attached but **`Pets`/`PetRoster` are still copied through**), `Lazy("PetBuffService")`,
  `HttpService`.
- L52-53: drop `spawnPet`/`clearPets` bindables (PetHatchAPI retired).
- New state: `KeptEggs[player]` (failed egg records, like `Kept`).
- `Collect(player, plot)` (L92-131):
  - `local old = data.Base` (pass `data` in); `base = {}`; copy every key of `old` except `Version, SavedAt,
    Cucumbers, Builds, Eggs` **by reference** (this carries `Pets`, `PetRoster`, `PetSchemaVersion`,
    `PetNoticePending`, unknown keys); then `base.Version = VERSION; base.SavedAt = os.time()`; fresh `Cucumbers`,
    `Builds`, `Eggs`; `base.Pets = old.Pets or {}`.
  - First: `PetService.SyncRecords(player, anchor)` (pcall).
  - Consumed-egg set: BaseSave builds `ownedSource[SourceEggId] = true` itself by scanning `old.Pets` (table records
    with a string `SourceEggId`) - no PetService call, so it works in every stage and before PetService starts.
  - Eggs: skip `egg:GetAttribute("Consumed") == true` and eggs whose `EggId` is in `ownedSource`; add
    `Id = egg:GetAttribute("EggId")`; keep a per-Collect
    `emittedEgg[Id]` set. Then append `KeptEggs[player]` records **except** those whose `Id` is already emitted (a
    live world egg), is in `ownedSource`, or repeats an earlier kept record.
  - Cucumbers: add `Id = model:GetAttribute("CucumberId")` and, when non-nil,
    `PetBuffs = PetBuffService.Serialize(model)` (pcall; on error save the cucumber without `PetBuffs` + WarnOnce).
  - Pets: **no longer collected from `PlotPet` tags** (L125-129 removed).
  - **Must: `Collect` never throws** - every cross-module call inside it is pcall-guarded.
- `Snapshot` (L133-141): unchanged guards; passes `data` to `Collect`.
- Heartbeat (L273-280): the per-player body becomes `local ok, err = pcall(Snapshot, player, true)` + WarnOnce on
  error, so one bad player/attribute can never kill the loop for the rest of the server.
- `Restore(player)` (L162-242):
  - **No waiting on PetService before the world restore.** After `WaitForData` nothing pet-related runs until the
    cucumbers are done (a pet-system failure must never delay the core base by 30 s).
  - Eggs: `KeptEggs[player] = nil` **before** the egg loop (mirrors `Kept[player] = nil` before the cucumbers, so a
    Reload never doubles failed egg records). Iterate a shallow copy of `base.Eggs` (a hatch may mutate the live
    array). Per-restore `seenEgg[Id]`: a record whose `Id` was already seen → `table.remove` it from the live
    `base.Eggs` by identity (printed repair, not restored - eggs are single-use, never re-IDed); a record whose `Id`
    is in `ownedSource` (built from `base.Pets` as in Collect) → removed likewise; a record with a missing/invalid Id (only possible
    when migration did not run) → `rec.Id = GUID` (printed) before invoking; failure → `KeptEggs`.
  - Builds: unchanged.
  - Cucumbers: the v1 gate (L204-214) **byte-for-byte unchanged**; the cucumber shallow copy is taken **after** the
    gate, from the post-gate `base.Cucumbers`, right where the L216 loop starts (the gate replaces the array with
    `{}`, so a copy taken earlier would replay version-1 records). Per-restore Id dedupe (assign a GUID to the later
    duplicate, printed) before invoking.
  - Delete the pets loop (L230-236) entirely. **After** the existing L238 `Active[player] = plot` - outside the
    `if base then … end` block, so a profile whose `Base` is not a table still gets them - add
    `player:SetAttribute("BaseRestored", true)` and then
    `if PetService and PetService.WaitReady(2) then pcall(PetService.EnsureProfileState, player); pcall(PetService.AttachPlot, player, plot) end`
    (counts in the print). When PetService is not ready within 2 s nothing else is done: PetService.Start's
    late-start sweep attaches every player whose `BaseRestored` is true (3.5). Keep the final
    `if failed == 0 then Snapshot(player, true) end`.
- Registration: `DataService.OnBeforeClose(function(player) Snapshot(player, true) end, 40)` (feature-checked).
- Leave handler (L261-271): first `if plot then Snapshot(player, true) end` (quiet: the final save follows), then
  `player:SetAttribute("BaseRestored", nil)`, existing clears, `KeptEggs[player] = nil`, and
  `PetService.DetachPlot(player, "Left")` (pcall).
- `BaseSaveAPI.Reset` (L294-311): `player:SetAttribute("BaseRestored", nil)`; replace `clearPets` with
  `PetService.DetachPlot(player, "Reset")`; `KeptEggs = nil`; new Base =
  `{Version = VERSION, SavedAt = os.time(), Cucumbers = {}, Builds = {}, Pets = {}, Eggs = {}, PetRoster = {}, PetSchemaVersion = 1}`.
- `Resume` (L312-316): after `Active` is set: `player:SetAttribute("BaseRestored", true)` and, only when
  `PetService and PetService.IsStarted()`, `PetService.EnsureProfileState(player)` + `PetService.AttachPlot(player, Active[player])` (pcall each; never waits).
- Every `PetService.*` call in this script is pcall-guarded and skipped when `PetService` is nil or not started
  (except `DetachPlot`, which is safe on a not-started module and still pcall'd).
- `Reload` (L318-332): `BaseRestored = nil`, `PetService.DetachPlot(player, "Reload")` instead of `clearPets`;
  rest unchanged (Restore re-attaches).
- New bindable `BaseSaveAPI.IsRestored(player) -> boolean` (`Active[player] ~= nil and not Paused[player]`).
Must NOT change: VERSION = 2, AnchorOf, Pack/Unpack formats, debounce/heartbeat numbers, the v1 cucumber wipe gate,
`Kept` cucumber semantics, the other bindables' names/signatures, tag-signal snapshot triggers (the PlotPet tag may
stay in the trigger list: harmless).

### 4.9 `ServerScriptService.PlotService` (WP-SERVER)
- L198 `Players.PlayerRemoving:Connect(Release)` →
  `Players.PlayerRemoving:Connect(function(player) task.defer(Release, player) end) -- 2026-09-22: let the pre-close flush (DataService) snapshot the plot before it is released`.
- Header: one dated line. Nothing else.

### 4.10 `StarterGui.CucumberMenus.MenuController` (WP-MENU)
Per ui.md 8.2 (4-space indentation, no header comment in this file - add only the dated comment lines):
1. After `local Controller = {}`: `OPENERS = {Shop = {"LeftMenu","Shop","OpenShop"}, Index = {"LeftMenu","Index","OpenIndex"}, Pets = {"LeftMenu","Pets","OpenPets"}}`,
   `OPTIONAL = {Pets = true}`, `CLOSE_ON_BASE = {Shop = true, Index = true}`.
2. L6 keep Shop/Index; add Pets when `gui:FindFirstChild("PetsPanel")` has a `Content`.
3. Opener loop (L88-98): resolve the path from `hud`; OPTIONAL panels resolve with `WaitForChild(part, 10)` inside
   `task.spawn` (explicit `if OPTIONAL[name] then … else … end`, never `a and b or c`), warn + skip on nil;
   `connect(opener.Activated, toggle)` and `hover(opener, opener.Parent)` unchanged.
4. L102-104: close on BaseMode only when `activeName and CLOSE_ON_BASE[activeName]`.
5. `fit()` L29: margin `tonumber(panel.Parent:GetAttribute("FitMargin")) or 0.86`.
6. Close whatever is open when the `hud` attribute `BuildMode` becomes true.
Must NOT change: show/transition tweens, dimmer, Escape, OpenRequest parsing, api shape.

### 4.11 `StarterGui.CucumberMenus.MenuClient` (WP-MENU)
Start PetController **last**, guarded (ui.md 8.3) so that a require-time error is also caught:
```lua
local okPets,pets=pcall(function() return require(script.Parent.PetController).Start(script.Parent,menus) end)
if not okPets then warn("[MenuClient] Pets menu unavailable: "..tostring(pets)) pets=nil end
script.Destroying:Connect(function() if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)
```
(the last line replaces L6; keep the compact style of L3-5).

### 4.12 `StarterGui.CucumberHUDDesign.BaseHUDController` (WP-MENU)
- L47 `SLOTS` gains `Pets = 3` (own slot id: never waits on another occupant).
- L130-141: resolve `Pets` with `menu:FindFirstChild("Pets")` (skip the state when absent); the original five keep
  `WaitForChild`.
- `wanted` (L155-161): `Pets = not building and not onBench`.
- Header: dated paragraph (note: hatch visibility is inherited - EggHatchClient's `HideUi` disables every PlayerGui
  layer during a reveal, and PetController ignores the P/ButtonL3 key while `CucumberMenus.Enabled == false`, 3.11).
  Do not add Pets to `HOVERED`.

### 4.13 `StarterPlayer.StarterPlayerScripts.PetRoamClient` (WP-WORLDFX, rewrite)
Keeps: tag `PlotPet`, PartCount streaming wait, `RootToVisibleBottom` (+ local collision strip), step bounce
(`WALK_STEP_RATE 9`, `WALK_BOUNCE_HEIGHT 0.7`), yaw smoothing (`TURN_RATE 8`), Heartbeat stepping, the only
`PivotTo` owner of pet models.
Changes:
- Segment cache per pet updated only when `RoamSeq` changes and `PetMotion.ReadSegment` returns a complete segment;
  otherwise keep the last complete one.
- Position = `PetMotion.Sample(seg, workspace:GetServerTimeNow())` directly - **remove the `SETTLE_RATE` low-pass**.
  Heading from the sample; while `FxAimUntil > now`, face `FxAimAt` instead; a 0.15 s squash (scale Y 0.85 →
  1 via pivot offset only, no ScaleTo) after `FxShotAt`.
- Streaming fix: when a tagged model's Root streams out (Detach) keep a watcher (`model.DescendantAdded`) and
  re-Attach when the Root/parts come back while the tag is present.
- Header rewritten (2026-09-22).

### 4.14 `StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient` (WP-WORLDFX)
- Constants: `BADGE_FRAC`/badge row; the card grows by `BADGE_H = 0.8` studs **only while at least one buff is live**
  (fractions renormalised so existing text sizes stay the same); `card.Top` is recomputed on every resize so income
  popups still start at the card's top edge.
- Badges are built only for models passing the rule-0.14 filter (`Parent.Name == "Placed"` inside
  `workspace.Map.Lobby.Plots`, re-checked on `AncestryChanged`), so the build-mode move ghost (a client clone that
  keeps the tag and `PetBuff_*` attributes, parented to workspace) never shows badges or countdowns.
- Row `Buffs` (LayoutOrder 4, horizontal): up to three badges `Yield` (`PetStats.AbilityBadge("Yield")`, gold),
  `Haste` (`PetStats.AbilityBadge("Haste")`, cyan), `Guard` (shield glyph + charges), each with an `m:ss` countdown from the attribute expiry vs
  `workspace:GetServerTimeNow()`, updated every 0.25 s by one shared accumulator; listens to
  `PetBuff_*` attribute changes (section 6.2). Colours from `PetBalance.ABILITIES[k].Color`.
- Keep: `Rate` text (effective rate), `CucumberIncome` handler contract (switch its loop to `for i = 1, #amounts`).
Must NOT change: card size/fonts for unbuffed cucumbers, popups, MaxDistance rules.

---------------------------------------------------------------------------------------------------------

## 5. Saved data (profile.Data.Base)

### 5.1 Base
```lua
Data.Base = {
	Version = 2,               -- unchanged meaning; template now 2; never written by pet code except BaseSave
	SavedAt = <os.time()>,
	Cucumbers = {CucumberRecord...},
	Builds = {…unchanged…},
	Eggs = {EggRecord...},
	Pets = {PetRecord...},      -- CANONICAL owned pets (active + reserve), never rebuilt from the world; at most
	                            -- PetBalance.MAX_OWNED (1000, ~300 KB) new grants (legacy/over-cap records are never dropped)
	PetRoster = {"<pet id>", ...}, -- ordered active selection, 0..6 ids, all owned
	PetSchemaVersion = 1,       -- written last by PetDataMigration; NOT in the DataService template
	PetNoticePending = true?,   -- one-time "six active pets" notice; removed after it is sent
	-- unknown keys: preserved by BaseSave Collect
}
```
### 5.2 PetRecord
```lua
{
	Id = "<GUID>",              -- required, unique within Pets
	Pet = "Chest",              -- internal PetsCatalog key (never the display name)
	SourceEgg = "Desert Egg",   -- PetsCatalog egg key (EggKey of the short name); nil for unknown legacy species
	SourceEggId = "<GUID>"?,    -- the consumed egg's EggId; nil for legacy / dev grants
	Material = "",              -- "" normal, "Golden", "Diamond" (unknown strings kept, ignored in maths)
	Mutations = {"NEON"},       -- ARRAY, distinct, egg order; known names canonical upper-case, unknown kept byte-for-byte, ignored in maths
	EggKg = 123?,               -- egg Kg attribute, provenance only
	AcquiredAt = 1790000000,    -- os.time() at grant; 0 for legacy
	Pos = {x, y, z},            -- back-edge anchor-local (BaseSave AnchorOf); y written as 0; legacy values kept
	AbilityRemaining = 60,      -- active-online seconds to the next chance roll (0..60)
	-- unknown fields preserved
}
```
Conversions: egg `Mutations` comma string → `PetStats.NormalizeMutations`; egg `Material` nil/"" → `""`. Pet model
attribute `Mutations` = `PetStats.MutationString(record.Mutations)` (known only). Rarity/rates/damage/chance are
never saved.
### 5.3 EggRecord (existing + `Id`)
`{Id = "<GUID>", EggName = "Basic", Kg, Scale, Material?, Mutations = "<comma string>", DisplayName, HatchSeconds, PlacedAt, HatchAt, Pivot = {12}}`
### 5.4 CucumberRecord (existing + `Id`, `PetBuffs`)
`{Id = "<GUID>", Zone, Type, Golden, Material?, Mutations = "<comma string>", SizeTier?, Name, Pivot, Box, Size, PetBuffs = {BuffRecord...}?}`
`BuffRecord = {Kind = "Yield"|"Haste"|"Guard", ExpiresAt = <server epoch>, SourcePetId = "<pet id>"?, Charges = 1?}`
(Charges only on Guard). Mutations stay strings on cucumbers and eggs - never convert them.
### 5.5 Migration rules
Section 3.4. Runs in DataService after Reconcile and before exposure, again in `ResetProfile`, and (idempotently)
from `PetService.EnsureProfileState`. Never initiates or broadens the v1 cucumber wipe (it never touches
`Version` or cucumber records beyond `Id`).

---------------------------------------------------------------------------------------------------------

## 6. Runtime attributes

### 6.1 Pet model (Model tagged `PlotPet` in `plot.Pets`, written by PetService only; all set before parenting)
| Attribute | Type | Notes |
|---|---|---|
| `PetId` | string | record Id |
| `PetName` | string | internal key |
| `DisplayName`, `Rarity` | string | from PetsCatalog |
| `Owner` | number | UserId |
| `OwnerName` | string | `player.Name` (live PetHatchService L230) |
| `Plot` | string | `plot.Name` (live L231) |
| `PrismaticLoop` | boolean | always `true`, set before `ApplyLook` so the server colour loop never starts (3.5) |
| `PartCount` | number | streaming guard |
| `Material` | string? | nil when normal |
| `Mutations` | string | known names, comma-joined |
| `Rate` | number | pet cash/s (Stats.Income) |
| `Ability` | string | Yield/Haste/Guard/Wild/None |
| `ShotDamage`, `ShotInterval`, `Range` | number | display snapshot |
| `RoamRadius`, `RoamPhase` | number | |
| `RoamFrom`, `RoamTo` | Vector3 | plot-top points |
| `RoamStart`, `RoamEnd`, `RoamGroundY` | number | server epoch / Y |
| `RoamSeq` | number (int) | **written last**, +1 per published segment |
Client-local (written by PetEffectsClient on its own copy, never replicated): `FxAimAt` (Vector3), `FxAimUntil`,
`FxShotAt` (numbers, server epoch). Server never reads them.
### 6.2 Placed cucumber (existing attrs unchanged)
| Attribute | Writer | Type |
|---|---|---|
| `CucumberId` | CucumberCarry (Place/RestorePlaced); cleared on PickUp | string |
| `BaseRate` | IncomeService | number |
| `Rate` | IncomeService (only writer; effective rate) | number |
| `PetBuff_Yield`, `PetBuff_Haste`, `PetBuff_Guard` | PetBuffService / RestorePlaced stamp | number (ExpiresAt, server epoch) |
| `PetBuff_YieldSrc`, `PetBuff_HasteSrc`, `PetBuff_GuardSrc` | same | string (PetId) |
| `PetBuff_GuardCharges` | same | number (int ≥ 1) |
Grace is internal to PetBuffService (not an attribute).
### 6.3 Placed egg: `EggId` (string, EggPlacement), `Consumed` (true, PetHatchService, set right before Destroy),
`Hatching` (existing, per-egg lock).
### 6.4 Player: `BaseRestored` (true/nil, BaseSaveService), `RaidLive` (true/nil, ZombieRaidService),
`PetCombatLocked` (boolean, PetService), `PetsHatched` (existing).
### 6.5 Diagnostics: `ServerStorage` attribute `PetDiag` (JSON string, PetServer, every 10 s). No workspace attributes.

---------------------------------------------------------------------------------------------------------

## 7. Remotes (all under `ReplicatedStorage.Remotes`)

| Remote | Class | Creator (when) | Direction |
|---|---|---|---|
| `PetRequest` | RemoteEvent | PetServer (script start, step 1) | client → server |
| `PetState` | RemoteEvent | PetServer (step 1) | server → owner |
| `PetEffects` | RemoteEvent | PetEffectsBus.Start | server → owner + nearby |
| `PetIncome` | RemoteEvent | IncomeService.Start | server → all |
| `CucumberIncome` | RemoteEvent | IncomeService.Start (find-or-create; LeaderstatsService no longer creates it) | server → all |
| `PetHatch` | RemoteEvent | PetHatchService (unchanged) | both |

### 7.1 PetRequest (client → server)
`{RequestId = string (1..40), Action = "GetState"|"Equip"|"Unequip"|"EquipBest", PetId = string?, SortMode = "Income"|"Combat"?}`
Validation: table; `RequestId` string ≤ 40; Action known; `PetId` required for Equip/Unequip (string ≤ 64); `SortMode`
required for EquipBest. Limits per player (limiters in `Session[player]`, applied before validation, whatever the
load state): GetState 1/s burst 2 (excess dropped silently - GetState is exempt from the "every request is
acknowledged" rule and is never a blocking request on the client); roster actions 2/s burst 4 (excess →
`Result.Error = "RateLimited"` while the reply limiter (1/s, burst 2) allows, else dropped silently, so spam can
never cause unbounded replies). Every roster request inside its limit gets exactly one reply carrying its
`RequestId` and the current Revision. No other fields are read.
### 7.2 PetState (server → owner only, `FireClient`)
```lua
-- Full (reply to GetState; also after a gap)
{Kind = "Full", Revision = n, Generation = g, RequestId = string?, Result = Result?, Slots = 6, EquippedIds = {id...},
 Pets = {PetView...}, Totals = Totals, CombatLocked = boolean, Notice = string?, ServerTime = number}
-- Delta (roster changes, hatch, status changes, rolls, lock changes, request results)
{Kind = "Delta", Revision = n, BaseRevision = n - 1, Generation = g, RequestId = string?, Result = Result?,
 EquippedIds = {id...}?, Upserts = {PetView...}?, Removed = {id...}?, Totals = Totals?, CombatLocked = boolean?,
 ServerTime = number}
-- Totals (<= 1 per TIMING.TOTALS_PUSH, only on change; NOT revisioned: never advances Revision, never causes a gap)
{Kind = "Totals", Totals = Totals, ServerTime = number}
Result  = {Ok = boolean, Action = string, Error = string?}
-- Error ∈ "NotLoaded" "Closing" "CombatLocked" "NotOwned" "SlotsFull" "Unavailable" "RateLimited" "BadRequest" "NoPlot" "MigrationFailed" "InventoryFull"
-- Revision is monotonic per player session (Session table, survives runtime rebuilds); Generation =
-- DataService.GetGeneration(player) (changes on admin reset). A rebuild while ClientReady pushes an unsolicited Full.
Totals  = {Pet = number, Cucumber = number, CucumberBase = number, Total = number}
PetView = {Id, Pet, DisplayName, Rarity, SourceEgg?, Material = string, Mutations = {known names},
           AcquiredAt = number, Equipped = boolean, Status = "Active"|"Pending"|"Idle"|"Unavailable"|"Reserve"|"Invalid",
           AbilityRemaining = number, -- as of ServerTime; counts down client-side only while Status == "Active"
           Stats = {Income, ShotDamage, ShotInterval, DPS, Range, Ability, AbilityChance, AbilityDuration?,
                    AbilityDurations = {Yield, Haste, Guard}? (Wild only), Fighter}}
```
Deltas and Totals are only pushed after that player's first GetState (`Session.ClientReady`, per player session). Client: Full replaces; Delta applies only when
`BaseRevision == local Revision`, otherwise request a Full (≤ 1/s). `Notice` = `PetBalance.TEXT.MigrationNotice`
when `Base.PetNoticePending` (then removed from the Base).
### 7.3 PetEffects (server → owner + players within FX.RADIUS; `FireClient` per recipient)
`{T = serverTime, Events = {Event...}}`; every event has `Id` (int), `Kind`, `T`, `Owner` (UserId):
- `Shot`: `PetId, From: Vector3, To: Vector3, Zombie: Model?, Rarity: string, Damage: number`
- `AbilityApplied`: `PetId, PetName (display), Ability ("Yield"|"Haste"|"Guard"), Source ("Yield"|"Haste"|"Guard"|"Wild"),
  CucumberId, Cucumber: Model?, From: Vector3, To: Vector3, ExpiresAt: number, Charges: number?`
- `ShieldBlocked`: `CucumberId, Cucumber: Model?, At: Vector3`
No client → server handler exists for PetEffects.
### 7.4 PetHatch (extended, positional as today)
Server → client `FireClient(player, "Begin", payload)`; payload keeps every existing field (`EggName, EggKey,
EggDisplayName, Scale, Material, Mutations (comma string), Pet, PetDisplayName, Rarity, Percent, Chance`) and adds
`Token = "<GUID>"`, `PetId`, `Kg`, `Reserve = boolean`, `AutoEquipAfterCombat = boolean` (reserve only because of the
combat lock; it equips itself when the fight ends if a slot is still free, OD-11),
`Stats = {Income, ShotDamage, ShotInterval, DPS, Ability, AbilityChance, AbilityDuration?, Fighter}`.
Client → server `FireServer("Opened", token)`. A token finishes only its own presentation, once.
### 7.5 ZombieAPI.TargetInfos (BindableFunction, server only)
`TargetInfos:Invoke() -> {TargetInfo}`; `TargetInfo = {Model = Model, Owner = number?, State = string?, Carrying = boolean,
Grappling = boolean, Digging = boolean, Day = boolean, Health = number, MaxHealth = number, Position = Vector3}`
(primitives + the Model reference; never raid tables).
### 7.6 PetIncome / CucumberIncome
`CucumberIncome:FireAllClients(models: {Model}, amounts: {number})` (unchanged shape, credited amounts only).
`PetIncome:FireAllClients(models: {Model}, amounts: {number}, petIds: {string})`, same tick, same rules. All-clients
is a deliberate deviation from PLAN 10/12 ("owner/nearby") - see OD-15; list it in the handoff.

---------------------------------------------------------------------------------------------------------

## 8. Lifecycle sequences

### 8.1 Join
1. PlotService `Assign` (PlayerAdded) → `plot.Owner`.
2. DataService `OnPlayerAdded`: StartSessionAsync → Reconcile → REMOVED_KEYS → **PetDataMigration (pcall, Scope
   "All")** → OnSessionEnd hook → left-during-load early exit (unchanged) → OnLastSave hook → generation →
   `Profiles[player]` → value objects → loaded callbacks (spawned).
3. Callbacks (any order): PetServer → `PetService.EnsureProfileState` (requests a save when the migration report says
   `Changed`); LeaderstatsService `Setup`; BaseSave `Restore`.
4. BaseSave Restore: WaitForData → plot → PlotLevel wait → eggs (`KeptEggs` reset, duplicate-Id and
   owned-SourceEggId drops, KeptEggs on failure) → builds → v1 gate (unchanged) → cucumbers (shallow copy taken after
   the gate, Id dedupe, `RestorePlaced` stamps `CucumberId` + buffs before the tag; IncomeService registers on tag
   add, rule 0.14) → `Active = plot` → `BaseRestored = true` → if `PetService.WaitReady(2)`: `EnsureProfileState` +
   `AttachPlot` (roster pets spawn, producers registered), otherwise PetService.Start's late-start sweep attaches
   later → quiet snapshot if nothing failed. No step waits on the pet system before the world is restored.
5. PetService scheduler starts counting that player's ability pets (BaseRestored + attached; the first roll comes
   only after a full `AbilityRemaining` of active time - no join roll); PetCombatService picks the pets up from
   `GetActivePets()`.
6. Client: PetController sends GetState → Full (+ Notice once).

### 8.2 Hatch transaction (PetHatchService.Hatch)
1. Validate: egg parented + tagged, no `Hatching`/`Consumed`, owner in game, `BaseRestored`, `PetService.IsReady`,
   `DataService.IsLoaded` and not `IsClosing`, plot owned, no `ActiveToken[owner]`, no `HatchBusy[owner]`, no
   `FullUntil[owner]`. Lock: `Locks[egg] = true`, `HatchBusy[owner] = true`, `egg:SetAttribute("Hatching", true)`.
   Every exit path below releases `HatchBusy` (and `Locks`/`Hatching` unless the egg was consumed).
2. `pcall(BaseSaveAPI.Snapshot.Invoke, …, player)` (may be refused before restore - fine; must not yield, asserted).
   Re-validate step 1 afterwards (egg still there, lock still ours). From here to step 6 **no yields**.
3. Build `EggInfo` from the egg attributes (`EggId`, `EggName`, `Kg`, `Material`, `Mutations`).
4. `petKey = Catalog.Roll(eggName, Rng)` (once). `ok, record, info = pcall(PetService.GrantFromEgg, player, EggInfo, petKey)`
   (pinned internal order, 3.5: all fallible work first, then egg-record removal + pet insert + roster + index back
   to back). `not ok` → warn once, release, egg kept. `record == nil` → release (`InventoryFull` also sets
   `FullUntil`), return. `info.Duplicate` → consume the egg (step 5), no reveal.
5. `egg:SetAttribute("Consumed", true)`; `egg:Destroy()`; `Locks[egg] = nil`.
6. `DataService.RequestSave(player)`.
7. `token = GUID`; `Presentations[token] = {Player, PetId, Spot = egg pivot position, Generation = DataService.GetGeneration(player)}`;
   `ActiveToken[player] = token`; `HatchBusy[player] = nil`; `task.delay(REVEAL_FALLBACK, Presentation, player, token)`;
   fire Begin (7.4).
8. `Opened(token)` / fallback → `Presentation` → `PetService.FinishPresentation` (clears `PresentationPending`; spawns
   only if still equipped, attached and no model exists yet). The reveal never grants, never rerolls, never resets
   cooldowns.
Failure boundaries: before step 4 → egg intact, nothing granted; step 4's mutation block is synchronous and cannot
throw half-way (profile holds either the egg record or the pet record, never both); a stop after step 4 but before
step 5 leaves the world egg, which `Collect` then skips because its `EggId` is an owned SourceEggId (a later hatch
of it takes the Duplicate path); after step 6 → pet owned; a crash before the next DataStore write rolls back to the
previous saved state (egg intact). Leaving mid-reveal keeps the pet (roster/reserve) - it spawns on next join. The
`PetHatchDev fail:*` hooks (4.2) exercise each boundary in S3.

### 8.3 Leave / pre-close flush (normal leave)
PlayerRemoving handlers run in any order; PlotService's `Release` is deferred (4.9), so the plot is intact during:
- DataService `OnPlayerRemoving` → `RunBeforeClose(player, profile, "Leave")` (close-phase callbacks gate only on
  `GetData ~= nil`, rule 0.13):
  order 10 `PetService.Freeze` → 20 `IncomeService.FlushOwner` (credits the closing owner; owner → Flushed) →
  30 `PetService.SyncRecords` → 35 ZombieRaidService `PreCloseRaids` (carried cucumbers home, lobby-dropped
  cucumbers back to their rest pose, 4.6 step 10) → 40 BaseSave `Snapshot(player, true)` → then
  `profile:EndSession()` (OnLastSave → no-op guard) → Forget.
- BaseSave's own PlayerRemoving: snapshot (if still Active & owned - refused once Forget ran) → clear flags →
  ClearPlaced/ClearBuilds → `PetService.DetachPlot(player, "Left")`. PetService's own PlayerRemoving: SyncRecords
  (if data) → DetachPlot → drop runtime + Session. IncomeService's: FlushOwner (no-op when already Flushed or no
  data) → owner Forgotten; every later settlement for that owner (tag removals from ClearPlaced/Release,
  DetachPlot) is discarded, never stored. ZombieRaidService's: `EndRaid(…, "Left")` (RestoreCarry with `force`).
  Whichever snapshot runs second is refused or idempotent - both are non-yielding.
- Deferred: PlotService `Release` → `Owner = nil` → EggPlacement clears `plot.Placed`; PetService despawns anything
  left on that plot (runtime only).

### 8.4 Shutdown / external takeover
- **With DataStore access** (live servers; Studio only with API access on and `USE_MOCK_IN_STUDIO = false`):
  ProfileStore's BindToClose (L2208-2239) saves every active profile with reason `"Shutdown"` → `OnLastSave(reason)`
  → `RunBeforeClose` (same order 10/20/30/35/40, plot still intact) → OnSessionEnd → Forget. Nothing may be written
  to `profile.Data` after `RunBeforeClose` returns.
- **Without access / mock** (L2197-2206): BindToClose only sets `IsClosing` and waits one frame - no profile is
  ended, so `OnLastSave`/`RunBeforeClose` never fire on a Studio Stop. Lifecycle tests exercise the flush with a
  normal leave (PlayerRemoving), not a Studio Stop; the Stop check in S3 only verifies nothing breaks/duplicates.
- **Lost ownership** (another server took the session, ProfileStore L911-920): only `OnSessionEnd` fires (no
  `OnLastSave`), so no pre-close flush runs - correct, since this server may no longer write that profile. The
  existing OnSessionEnd handler calls `Forget` (which also clears `Closing`/`Generation`/`MigrationReports`,
  4.1 item 9); every pet module then sees `GetData == nil` and goes inert for that player.

### 8.5 Admin reset (AdminService.ResetData, unchanged script)
1. `BaseSaveAPI.Reset`: Paused, `BaseRestored = nil`, clear cucumbers/builds/eggs, `PetService.DetachPlot(player, "Reset")`,
   new empty Base (5.1 keys incl. `PetRoster = {}`, `PetSchemaVersion = 1`), RequestSave.
2. `DataService.ResetProfile`: template copy (Base Version 2) → migration → generation +1 → RequestSave →
   `OnProfileReset` callbacks: PetService rebuilds runtime from the empty data (old presentations become stale by
   generation; `Session.Revision` keeps counting and a Full with the new `Generation` is pushed if ClientReady);
   IncomeService drops the owner's ledger and sets `LastSettled = now` on that owner's producers, so the deferred
   tag-removed signals of the cucumbers Reset destroyed settle 0 into the fresh profile.
3. Owner bounce → PetService `DetachPlot(…, "PlotLost")` (no-op), PlotUpgrade resize, EggPlacement clear.
4. `BaseSaveAPI.Resume` → `Active`, `BaseRestored = true`, `EnsureProfileState` + `AttachPlot` (nothing to spawn).
5. PetHatchService: a reveal started before the reset finishes with a stale generation → `FinishPresentation`
   refuses; nothing is re-granted.

### 8.6 BaseSaveAPI.Reload
Paused, Active nil, `BaseRestored = nil`, clear kinds, `PetService.DetachPlot(player, "Reload")`, wait 0.6 s,
`Restore` (8.1 step 4) → same records, same IDs, same buffs (absolute expiries). `KeptEggs` is reset at the start of
the egg loop, so repeated Reloads never multiply failed egg records. A reveal in flight keeps `PresentationPending`
through the Detach/Attach, so the later `FinishPresentation` never spawns a second model (3.5).

### 8.7 Plot resize (PlotUpgradeService Resize)
PetService (plot `Size` changed): for each pet on the plot: `from = clamp(PetMotion.Sample(seg, now))`, publish an
idle segment at `from` (new RoamSeq), replan next tick. Buff eligibility re-evaluates on use (footprint check).

### 8.8 Raid start/end (combat lock)
ZombieRaidService sets `RaidLive` on raid/thief start and clears it on Survived/ZombiesWin/Dawn/Left/thief gone.
PetService: `PetCombatLocked = CyclePhase == "Night" or RaidLive`; pushes `CombatLocked` delta on change. Roster
actions → `"CombatLocked"`; hatches during lock go to reserve and, when a slot was free at hatch time, are queued in
the runtime `PendingAutoEquip` list and equipped (in grant order, while slots are free) on the lock → unlocked
transition (OD-11). `RaidLive` is synced at every raid exit, including both early returns of `CheckRaidEnd` (4.6 step 9).

### 8.9 Death / respawn
Nothing happens to pets, producers or countdowns (no character dependency anywhere in pet code).

### 8.10 Plot loss mid-session (Owner cleared/changed without leave)
PetService `DetachPlot(player, "PlotLost")`; income stops for pets (producers removed) and for cucumbers (destroyed
by EggPlacement). Records untouched. A new tenant's services never see the old owner's producers (keys are cached
per producer owner; PetBuffService eligibility checks model Owner AND plot Owner).

---------------------------------------------------------------------------------------------------------

## 9. Constants - `ReplicatedStorage.Modules.PetBalance` (literal; copy exactly)

```lua
local PetBalance = {}

PetBalance.SLOTS = 6
PetBalance.MAX_OWNED = 1000           -- safety cap on new grants (profile size); OD-28, user to confirm
PetBalance.BASE_INCOME = 0.5          -- Basic tier cash/s before rarity/rank/traits
PetBalance.TIER_STEP = 8              -- x8 per egg tier
PetBalance.RANK_STEP = 0.10           -- +10 % per rank above 1
PetBalance.MAX_RANK = 6
PetBalance.RANK_OVERRIDES = {Gregory = 6} -- rankless secret pet
PetBalance.BIOME_DAMAGE_STEP = 0.05   -- +5 % shot damage per egg tier above 1
PetBalance.FIGHTER_MULT = 1.15        -- species with Ability "None"
PetBalance.INCOME_AFFIX_CAP = 8
PetBalance.DAMAGE_AFFIX_CAP = 0.25    -- AffixDamage <= 1.25
PetBalance.RATE_HARD_CAP = 2.0        -- cucumber temporary multiplier cap (Yield x Haste = 1.875)
PetBalance.FALLBACK_RARITY = "Common"

PetBalance.RARITY = {
	Common    = {Income = 1.0,  Damage = 3,  Interval = 2.50, Range = 26, Chance = 0.01},
	Uncommon  = {Income = 1.5,  Damage = 5,  Interval = 2.25, Range = 29, Chance = 0.02},
	Rare      = {Income = 2.5,  Damage = 8,  Interval = 2.00, Range = 32, Chance = 0.04},
	Legendary = {Income = 5.0,  Damage = 12, Interval = 1.75, Range = 35, Chance = 0.08},
	Mythical  = {Income = 10.0, Damage = 18, Interval = 1.50, Range = 38, Chance = 0.12},
}

PetBalance.EGG_TIERS = {["Basic Egg"] = 1, ["Desert Egg"] = 2, ["Samurai Egg"] = 3, ["Farm Egg"] = 4,
	["Frozen Egg"] = 5, ["Ocean Egg"] = 6, ["Lava Egg"] = 7, ["Narmek Egg"] = 8}
PetBalance.EGG_ZONES = {["Basic Egg"] = "Spawn", ["Desert Egg"] = "Desert", ["Samurai Egg"] = "Samurai",
	["Farm Egg"] = "Farm", ["Frozen Egg"] = "Snow", ["Ocean Egg"] = "Underwater", ["Lava Egg"] = "Volcano",
	["Narmek Egg"] = "Narmek"}

PetBalance.MATERIALS = {
	Golden  = {Income = 1.5, Combat = 0.05},
	Diamond = {Income = 2.0, Combat = 0.10},
}
PetBalance.MUTATIONS = {
	NEON = {Income = 0.15, Combat = 0.02}, SHADOW = {Income = 0.20, Combat = 0.03},
	FROZEN = {Income = 0.25, Combat = 0.03}, RADIOACTIVE = {Income = 0.30, Combat = 0.04},
	MOLTEN = {Income = 0.30, Combat = 0.04}, ROYAL = {Income = 0.50, Combat = 0.05},
	VOID = {Income = 1.00, Combat = 0.08}, PRISMATIC = {Income = 2.00, Combat = 0.12},
}

PetBalance.ABILITIES = { -- numbers live ONLY here; every text is built by the PetStats text helpers (3.2)
	Yield = {DisplayName = "Lucky Harvest", Mult = 1.5, Duration = 90, Color = Color3.fromRGB(255, 205, 40)},
	Haste = {DisplayName = "Quick Grow", Mult = 1.25, Duration = 90, Color = Color3.fromRGB(60, 220, 255)},
	Guard = {DisplayName = "Leaf Shield", Charges = 1, Color = Color3.fromRGB(90, 230, 110)},
	Wild  = {DisplayName = "Wild Card", Kinds = {"Yield", "Haste", "Guard"}, Color = Color3.fromRGB(255, 120, 230)},
	None  = {DisplayName = "Fighter", Color = Color3.fromRGB(255, 90, 70)},
}
PetBalance.GUARD = {CycleExtra = 15, MaxSeconds = 600, GraceSeconds = 1.5, StunSeconds = 0.8, AvoidSeconds = 4}
PetBalance.DEFAULT_DAY_SECONDS = 180
PetBalance.DEFAULT_NIGHT_SECONDS = 10 -- DayNightCycle's own fallback (the live attribute is 45)

PetBalance.TIMING = {
	ABILITY_PERIOD = 60, ABILITY_TICK = 0.25,
	INCOME_TICK = 1, INCOME_MAX_CATCHUP = 5,
	COMBAT_SCAN = 0.2, ROAM_PLAN = 0.2, BUFF_SWEEP = 0.25,
	FX_FLUSH = 0.1, TOTALS_PUSH = 1,
	REVEAL_FALLBACK = 100, -- > EggHatchClient WATCHDOG (95)
	ROAM_LEAD = 0.3,       -- roam segments start this far in the future (replication lead, 3.5)
	UNAVAILABLE_RETRY = 30, -- respawn attempt for Unavailable roster pets (OD-13)
}
PetBalance.PET = {FIT = 5, EDGE_INSET = 2, SPEED_MIN = 5, SPEED_MAX = 8, IDLE_MIN = 1.5, IDLE_MAX = 4.5, LEG_MIN = 8, LEG_MAX = 26}
PetBalance.REQUESTS = {STATE_PER_SECOND = 1, STATE_BURST = 2, ROSTER_PER_SECOND = 2, ROSTER_BURST = 4,
	MAX_ID_LENGTH = 64, MAX_REQUEST_ID_LENGTH = 40}
PetBalance.FX = {MAX_PROJECTILES = 64, MAX_POPUPS = 32, RADIUS = 180, MAX_EVENTS_PER_BATCH = 48,
	SHOT_TRAVEL_MIN = 0.12, SHOT_TRAVEL_MAX = 0.2, ARC_TIME = 0.32, MUZZLE_HEIGHT = 1.5}

PetBalance.TEXT = {
	MigrationNotice = "You can now choose six active pets. Your other pets are safe in Pets.",
	ProcToast = "%s gave %s to your cucumber - %s", -- (pet display name, ability display name, PetStats.AbilityShort)
	-- templates only; numbers are filled from ABILITIES / GuardSeconds by PetStats.AbilityShort/Effect
	Short = {Yield = "x%g for %ds", Haste = "+%d%% for %ds", Guard = "blocks one theft for %ds"},
	Effect = {Yield = "One cucumber earns x%g cash/sec for %ds", Haste = "One cucumber produces %d%% faster for %ds",
		Guard = "Blocks %d zombie theft on one cucumber for up to %ds", Wild = "%s, %s or %s",
		None = "Fighter: +%d%% damage"}, -- None filled from FIGHTER_MULT
	ShieldToast = "Leaf Shield blocked a thief!",
	ReserveNotice = "Your new pet is in reserve - open Pets to equip it.",
	LockedHatchNotice = "Your new pet joins your team when the fight is over.",
	InventoryFull = "Your pet inventory is full.",
	LockBanner = "Finish defending your plot to change pets.",
	Unavailable = "Temporarily unavailable",
	NextRoll = "Next chance roll in %s",
}

-- internal key -> ability (PLAN section 5; all 49)
PetBalance.SPECIES_ABILITY = {
	-- Basic
	Cat = "Yield", Dog = "Guard", Bunny = "None", Wolf = "Haste", Tabby = "None", Fox = "Yield", Gregory = "Wild",
	-- Desert
	Barrel = "None", ["Treasure Gem"] = "Yield", Cannon = "None", Chest = "Guard", ["Desert Overlord"] = "None", Cactus = "Haste",
	-- Samurai
	["Dog Ninja"] = "None", ["Good Ninja"] = "Guard", ["Evil Ninja"] = "None", ["Good Samurai"] = "Yield",
	["Evil Samurai"] = "None", Sensei = "Haste",
	-- Farm
	Hay = "None", Bird = "Haste", Panda = "None", Cow = "Guard", Pig = "None", Farmer = "Yield",
	-- Frozen
	["Red Snowman"] = "None", ["Blue Snowman"] = "Haste", ["Frozen Dragon"] = "None", ["Frozen Hydra"] = "Guard",
	["Frozen Ice Shock"] = "None", ["Frozen Gem"] = "Yield",
	-- Ocean
	["Oceanic Dog"] = "None", ["Oceanic Kitty"] = "Guard", ["Oceanic Bunny"] = "None", ["Oceanic Bear"] = "Yield",
	["Ocean Dragon"] = "None", ["Atlantic Hydra"] = "Haste",
	-- Lava
	["Lava Plume"] = "None", ["Lava Golem"] = "Haste", ["Lava Veltal"] = "None", ["Lava Trio"] = "Yield",
	["Lava Dragon"] = "None", ["Demon Dog"] = "Guard",
	-- Narmek
	["Moon Bunny"] = "None", ["Satellite Pup"] = "Guard", ["Alien Slime"] = "None", ["Meteor Moth"] = "Haste",
	["Nebula Fox"] = "None", ["Cosmo Cat"] = "Yield",
}

function PetBalance.Validate(catalog) --[[ section 3.1 ]] end
return PetBalance
```
Where each constant is consumed: SLOTS/RANK/INCOME/DAMAGE → PetStats; TIMING.ABILITY_* → PetService; INCOME_* →
IncomeService; GUARD/ABILITIES → PetBuffService (+ ZombieRaidService StunSeconds/AvoidSeconds); COMBAT_SCAN →
PetCombatService; FX → PetEffectsBus + clients; PET, MAX_OWNED, TIMING.ROAM_LEAD/UNAVAILABLE_RETRY → PetService;
REQUESTS → PetService.Core; MAX_RANK → PetStats.Calculate + Validate; TEXT.Short/Effect → PetStats text helpers only;
other TEXT/Color → clients.

---------------------------------------------------------------------------------------------------------

## 10. Test plan and integration order

### 10.1 Unit tests (per package; read-only Studio evals, loopback-loaded sources, no instances parented)
Listed in section 2 per package. Conventions: each test chunk returns a summary string
`"<WP> <name>: PASS n / FAIL m: <first failures>"`; load modules under test with
`loadstring(HttpService:GetAsync("http://127.0.0.1:8793/<file>"))()` and inject fakes (require of a not-yet-installed
sibling → pass it in, or `package.loaded`-style shim via a local `require` override in the chunk). Probability tests
use `Random.new(seed)` and assert within ±3σ. Keep each eval < 15 s.

### 10.2 Integration stages (each leaves the place runnable). Backup first:
`export_rbxm` of every script touched in the stage into `backups/NewMap_pets-<stage>_before_2026-09-22.rbxm`; before
any stage that runs a playtest, `tools/snapshot_profile.lua` saves the current profile (10.4). Install via
`tools/stage.ps1` (stages `install_new.lua` and `pets-remake/apply_patches.lua`).
Destructive tests (admin reset, forced hatches/fault hooks, > 6 dev grants, buff/steal tests) run on the real test
profile (USE_MOCK_IN_STUDIO = false, PLAN 14 isolation is not available without changing DataService) and are
**always followed by `tools/restore_profile.lua`** from the stage's dated snapshot, then a rejoin check. The
integration agent must not skip the restore; the restore result string goes into `tests/`.
Lifecycle flush checks use a normal leave (PlayerRemoving), never a Studio Stop (8.4).

| Stage | Installs | Playtest checks (PLAN §14 rows) |
|---|---|---|
| S0 baseline | - (before any install) | the S8 load scenario on the unmodified place: `multiplayer_playtest` with the max test clients, heavy plots, a `ZombieDev raid`; `capture_script_profiler` + `capture_micro_profiler` + network stats (remote events/s) saved as `tests/S0_baseline_*.json`; also note the current `Cash/s` (40.2K on the test plot) and `ZombieDev raid` threat level (5) (Load, Income, Raid balance) |
| S1 inert | PetBalance, PetStats, PetMotion, PetDataMigration | Studio eval: `PetBalance.Validate(PetsCatalog)` empty; stats samples (Catalog, Stats) |
| S2 income | IncomeService, PetEffectsBus, PetServer, LeaderstatsService, ZombieRaidService | CashPerSec/`Cash/s` equal the S0 value on the test plot (40.2K); +X popups still fire once/s; `ZombieDev raid` threat level unchanged (5) (Income, Raid balance); fallback: set the edit-mode workspace attribute `PetServerSkipIncome = true` (10.3), playtest → the legacy loop warns once after 10 s and pays the same `Cash/s`, threat level unchanged; clear the attribute afterwards (Income); `RaidLive` set/cleared for a night raid, a killed daytime thief and a thief that walks off (Roster/lock precondition); leave → rejoin, cash kept (Lifecycle). **No pet-data checks here**: DataService (migration) is not installed until S3, because the unpatched BaseSave `Collect` rebuilds `data.Base` from six keys and would erase migrated fields every snapshot. |
| S3 ownership + hatch | DataService, PetService, BaseSaveService, PlotService, PetHatchService, EggPlacement, EggHatchClient, CucumberCarry | 4 legacy pets migrate once, IDs stable across 2 rejoins + `BaseSaveAPI.Reload`, >6 pets stay owned (grant via PetDev) (Legacy saves, Roster); v2 cucumbers/builds/eggs untouched, ghost eggs kept; a Version = 1 base with cucumbers (set via eval, then Reload) restores 0 cucumbers; `PlotUpgradeDev` resize keeps saved pet Pos mapping and local-coordinate placement (Existing base); **hatch interruption matrix**: for each `PetHatchDev fail:pre-grant / fail:post-grant / fail:post-destroy`, trigger a ready egg, then `BaseSaveAPI.Reload` and a rejoin → `data.Base` holds the egg XOR the pet for that EggId and no usable duplicate appears; plus leave mid-reveal, watchdog, busy, forged/duplicate token, reset mid-reveal, Reload mid-reveal (one model only), open Pets with P mid-reveal (ignored) (Hatch transaction, Reveal); repeated Reload with a failing egg restore → `#Eggs` does not grow; golden/mutated egg → pet traits survive save/rejoin (Mutation inheritance); $0.50/s pet earns ~30 in 60 s, reserve earns 0 (Income); character reset → no duplicate pet models, countdowns unchanged; admin reset + resume; normal leave → rejoin keeps cash/pets/positions; Studio Stop → rejoin (nothing breaks, see 8.4) (Lifecycle). Restore the profile afterwards (10.4). |
| S4 presentation | PetRoamClient, PetCardClient, PetEffectsClient, PlacedCucumberCardClient | two-client multiplayer_playtest: same roam positions (no leg-start jump), stream out/in re-attach of models AND cards, plot upgrade clamp (Motion); pet cards with rarity word, PRISMATIC colour cycle, `+$` popups, caps; build-mode move ghost shows no buff badges/shells (UI) |
| S5 buffs | PetBuffService | PetDev `buff:*` + `proc:*`: $10 base → 15 / 12.5 / 18.75, expiry back to 10 (Buff math); rolls once per 60 s, no roll on join/equip/re-equip, hitch no burst (Timing); seeded sample eval (Probability); move keeps Id/buffs, grab clears, Reload keeps absolute expiry, leave 60 s → rejoin earns no offline cash, unequipping the source pet keeps the expiry (Buff saves); shield: ordinary grab, grappler pre-pull, shield mid-pull, digger surface, two zombies same frame, expired shield, blocked zombie grabs nothing for 0.8 s (Shield); `ZombieDev raid` threat level with 6 pets equipped and Yield+Haste live equals the S0 value (Raid balance). Restore the profile afterwards. |
| S6 combat | PetCombatService | own raid only, neighbour raid untouched, no `Hostile` from pets, shaded/underground skipped, carrier priority, splitter children (Combat ownership, Zombie states); measured shot cadence ≈ nominal interval (Cadence); towers unchanged; threat level with pets active still equals S0 (Raid balance) |
| S7 menu | builder run, PetView, PetController, MenuController, MenuClient, BaseHUDController | open/close/Escape/outside click, BaseMode no longer closes Pets, bench/build tuck, P ignored during a reveal / build / bench, open during a reveal-free hatch countdown, open with own pets streamed out, phone preset 844×390, gamepad focus (Slot1 selected on open), lock banner at night, EquipBest atomic, spam (UI, Roster); Slow Mode 25, bench circles, green cash (Existing systems) |
| S8 regression + load | - | full matrix rerun; the S0 scenario repeated with 6 pets per player: `PetDiag`, script profiler, micro profiler, network rate → deltas vs `tests/S0_baseline_*` in `tests/S8_load.md`; no growing connection counts (Load) |
| S9 balance + handoff | - (PetBalance tweaks only, re-staged as S1 files) | Balance review (PLAN 14 "Balance review"): for starter (Basic/Desert team), midgame (Farm/Frozen) and max (Narmek, Cosmo Cat ×6) teams, each with and without towers: pet cash as % of same-biome cucumber cash (`PetDiag.Income.PaidPetCash` vs `PaidCucumberCash` over 5 min, per biome plot); time to afford the next egg/plot upgrade; full-team zombie kill times (`ZombieDev raid` at levels 1 / 5 / max; Cosmo Cat ×6 vs Deer-tier ×6); thefts prevented per night (`PetDiag.Buff.ShieldBlocks`); actual proc frequency (`ProcSuccess / Rolls` vs expected chance). Gregory's low income vs its rarity reviewed explicitly. Only `PetBalance` may change ("adjust only PetBalance first"). **Handoff** `pets-system/HANDOFF.md`: changed DataModel paths, every test result file in `tests/`, screenshots (Roblox MCP `capture_screenshot` only - no desktop tools) of the menu, active pets and buff badges, final numbers, the deliberate PLAN deviations (OD-11, OD-13, OD-15, OD-28, PLAN 14 Slow Mode 16 vs live 25), pre-existing bugs found (EggPlacement PRISMATIC egg loop never runs), and open issues. Not published. |

### 10.3 Studio test hooks (all `RunService:IsStudio()`, workspace attributes, cleared to nil first; "first player" = `Players:GetPlayers()[1]`)
- `PetDev` (PetServer): `"grant:<PetKey>[:<Material>[:<MUT,MUT>]]"` (saved dev grant, reserve unless a slot is free
  and unlocked), `"equip:<PetId>"`, `"unequip:<PetId>"`, `"best:Income|Combat"`, `"roll:<PetId>"` (AbilityRemaining →
  0.1), `"proc:<PetId>"` (next roll forced success), `"buff:<Yield|Haste|Guard>"` (grant on a random eligible
  cucumber, source "Dev"), `"clearbuffs"`, `"state"` (print diagnostics), `"reload"` (BaseSaveAPI.Reload).
- `PetHatchDev` (PetHatchService): `ready`, `clear`, `hatch:<Egg>[:<Pet>]`, `spawn:<Pet>`, `fail:pre-grant`,
  `fail:post-grant`, `fail:post-destroy` (4.2).
- `PetServerSkipIncome` (PetServer, read once at bootstrap, Studio only, set in edit mode before the playtest): when
  true PetServer does not Init/Start IncomeService and passes `nil` as the IncomeService dep to its dependents
  (tests LeaderstatsService's legacy fallback, 4.5).
- `PetsDev` on `PlayerGui.CucumberMenus.PetsPanel` (PetController).
- Existing: `ZombieDev`, `CarryDev`, `EggShopDev`, `PlotUpgradeDev`, `DevClick`.

### 10.4 Test-profile backup / restore (integration agent; PLAN 14 isolation substitute)
- `tools/snapshot_profile.lua` (server eval in a running playtest, `eval_server_runtime`): `DataService.GetData(player)`
  → `HttpService:JSONEncode` → POSTed to the loopback receiver (the project's `receive-b64.ps1` pattern, a private
  879x port) → `pets-system/tests/profile_<stage>_<hhmm>.json`. Run before every destructive stage run.
- `tools/restore_profile.lua` (same VM): fetches a named JSON via `HttpService:GetAsync` from the loopback file
  server, validates it decodes to a table with `Base` and `Cash`, then - in one non-yielding block, so no BaseSave
  heartbeat can snapshot the old world over it - replaces every top-level key of `DataService.GetData(player)` with
  the decoded value (deletes keys absent from the JSON; value-object keys like `Cash` go through
  `DataService.Set(player, key, v, true)` so the value objects follow), then `DataService.RequestSave(player)` and
  `BaseSaveAPI.Reload:Invoke(player)` (Reload pauses the base synchronously before it clears, then rebuilds the
  world from the restored Base; PetService rebuilds its runtime because the `Pets` array identity changed), and re-read `GetData` to verify (`Cash`, `#Base.Pets`, `#Base.Eggs`,
  `#Base.Cucumbers` equal the JSON). Returns one summary string. The first restore source is
  `live-2026-09-22/_profile_Player_140977250_before-pets.json` (served via the stage server) only when the user's
  data should go back to its pre-pet state; otherwise the stage's own snapshot.
- Never run either script against a player other than UserId 140977250.
- **(S0a, 2026-09-22) HOW TO RUN THEM: see 12.1** - the server VM has no HTTP and no loadstring, so both tools are
  two-step (edit peer + pasted server-VM eval) and carry the JSON through the DataStore entry
  `PetTestTransfer/<Snapshot|Restore>_140977250`; usage is in each file's header and in `tests/S0a_report.md`.
- **(Orchestrator amendment, 2026-09-22) Isolation first.** From S3 on (once the DataService patch with
  `ProfileKey`, 4.1 item 11, is installed) every playtest runs with the edit-mode attribute
  `ServerStorage.PetTestProfileKey = "PetTest"` → the session uses the DataStore key `PetTest_140977250`, never the
  real profile. The first S3 playtest seeds it: the key starts as a fresh template profile, then
  `restore_profile.lua` loads `_profile_Player_140977250_before-pets.json` (real legacy data: 4 pets, 3 eggs,
  2 cucumbers, 51 builds) into it and Reloads - the migration is then exercised by a leave → rejoin (migration runs
  on load) and by `DataService.ResetProfile`-free paths only. Destructive tests still restore their snapshot
  afterwards (so later tests start from known data), but a mistake can no longer damage the user's real profile.
  S2 (before DataService is patched) must avoid destructive tests entirely. Only the final S8 check runs once on the
  REAL key (attribute cleared) to confirm the real legacy profile migrates, with the JSON backup
  `backups/PlayerData/NewMap_PlayerData_v1_Player_140977250_before-pets_2026-09-22.json` on hand. The attribute is
  removed again at the end of every session (it lives in the place file).

---------------------------------------------------------------------------------------------------------

## 11. Open decisions (made here; each with the reason)

- **OD-1 Live code over PLAN §2.** Adopted research corrections: PetsCatalog stores no models (`ModelOf` looks up
  `Assets.Pets`); `Data.CashPerSec` is LeaderstatsService's unsaved NumberValue and its only reader is
  ZombieRaidService (threat + daytime thieves); `CucumberIncome` goes to all clients; there is no pet discovery
  (Gregory "hidden" = never listed in an unowned list); PlotService.Release + EggPlacement's `ClearAllChildren` are
  the main leave-time world destroyers; ProfileStore ends sessions itself on shutdown (hooked via `OnLastSave`);
  Slow Mode speed is **25** (tests expect 25, not 16); there is no player-facing cucumber pickup (PickUp is a dev hook);
  CucumberHUDDesign has no TopStatus frame; stun does not stop `Grab` (Bat stuns stay that way; a Leaf Shield block
  adds a separate `BlockedUntil` grab gate, 4.6 step 5).
- **OD-2 Pet record encoding.** `Material` is `""` for normal (PLAN says "empty"); `Mutations` is an array (PLAN) while
  eggs/cucumbers keep comma strings (live). Unknown names are kept in the array and ignored in maths.
- **OD-3 Template.** `TEMPLATE.Base.Version = 2`; no `PetSchemaVersion`/`PetRoster` in the template (Reconcile would
  mark legacy profiles as migrated).
- **OD-4 Migration placement.** Before `Profiles[player] = profile` (not merely before callbacks) and pcall'd; failure →
  pets inert this session, records untouched. Also re-run in `ResetProfile` and `EnsureProfileState` (idempotent).
- **OD-5 Hatch snapshot.** PLAN 8.3 step 2 kept (BaseSaveAPI.Snapshot before the commit) but the commit does not depend
  on it succeeding: the egg record is found by `Id` in whatever `data.Base` holds; ownership consistency comes from the
  synchronous grant+egg-removal and `Consumed`/SourceEggId filtering. Hatching waits for `BaseRestored` (removes the
  restore-window race).
- **OD-6 REVEAL_FALLBACK 80 → 100 s** so the client watchdog (95 s) normally acknowledges first; the busy path becomes
  rare. The client watchdog also bumps `Token` to stop double acks.
- **OD-7 Dev hooks grant.** `PetHatchDev hatch:/spawn:` and `PetDev grant:` create real saved pets (documented in
  their prints); there is no display-only spawn any more.
- **OD-8 PetHatchAPI retired.** Its only caller (BaseSave) now uses PetService directly; no adapters are published.
- **OD-9 Combat range = flat XZ distance** from the pet's logical ground point (pets stand on the plot, zombie roots
  are ~3 studs up); shots emit an effect only when `Damage` returns true (cooldown is consumed either way).
- **OD-10 Guard avoidance.** After a block the zombie ignores that cucumber for `GUARD.AvoidSeconds = 4` (new
  `entry.AvoidModel/AvoidUntil` in `NearestCucumber`); without it the blocked zombie re-grabs the same cucumber the
  moment the 1.5 s grace ends, so a shield would only buy 1.5 s. Protected cucumbers still count for threat/raid size.
- **OD-11 Hatch during lock → reserve until combat ends** (PLAN 1): if a slot was free at hatch time the pet is
  queued in the runtime-only `PendingAutoEquip` and equipped at the lock → unlocked transition while slots are still
  free (grant order); if the player filled the slots meanwhile, or left before the fight ended, it simply stays in
  reserve. A hatch into a FULL roster → reserve and stays there (the player equips). Unequip-first flow on a full
  roster (PLAN 11 v1). Reveal toast: `LockedHatchNotice` vs `ReserveNotice`.
- **OD-12 Buffs cleared at capture (`Grab`)**, not only at the final escape: a grabbed cucumber is untagged and missing
  from saves anyway; clearing at Grab guarantees no shield/Yield returns from a theft. A kill-drop therefore loses
  Yield/Haste.
- **OD-13 Unavailable roster pets keep their slot** (status "Unavailable", no income/fire/rolls, UI shows
  "Temporarily unavailable" and allows Unequip); PetService retries them every `TIMING.UNAVAILABLE_RETRY` (30 s) and
  on every attach, so they reconcile automatically mid-session when the asset appears. Deviation from PLAN 6
  ("stays owned in reserve"): moving them to reserve at runtime would let the saved roster exceed six once the asset
  returns; keeping the slot is simpler and the player can unequip. Listed in the handoff.
  Unknown species can never be equipped (migration excludes them; Equip/EquipBest refuse).
- **OD-14 Combat lock** = `CyclePhase == "Night"` OR player attribute `RaidLive` (new, ZombieRaidService). The plot
  `Raid*` attributes are stale and not used. `PreparingDay` is unlocked (raids end then).
- **OD-15 PetIncome** uses the CucumberIncome shape plus a third `petIds` array, fired to **all clients** from the
  same settlement; no event when the credit fails. Deliberate deviation from PLAN 10/12 ("owner/nearby"): it mirrors
  the live CucumberIncome (all clients, H19), the payload is tiny (≤ 6 entries per player per second), clients
  already skip streamed-out models, and per-recipient routing would need player positions inside IncomeService.
  Revisit only if S8 shows PetIncome as a meaningful share of the network rate. Listed in the handoff.
- **OD-16 Leave ordering.** PlotService `Release` is `task.defer`red so every PlayerRemoving handler (and the
  DataService pre-close flush) sees an intact plot. ZombieRaidService's order-35 `PreCloseRaids` returns carried
  and lobby-dropped cucumbers home before the flush snapshot, and `EndRaid(…, "Left")` uses `force`, so a leave
  during a raid no longer loses a carried cucumber or saves one lying in the lobby.
- **OD-17 Migration notice** is shown once when at least one legacy pet existed (flag `PetNoticePending`), delivered
  in the first Full PetState.
- **OD-18 Consumed-egg filtering lives in BaseSave** (Collect + Restore), not in EggPlacement.RestoreEgg (BaseSave is its
  only caller); EggPlacement only stamps/restores `EggId`.
- **OD-19 CucumberMoveServer unpatched**: a move keeps the instance, tag, CucumberId, buffs and rate; there is no
  server "moving" state to settle.
- **OD-20 AdminService unpatched**: reset correctness comes from BaseSaveAPI.Reset/Resume + DataService.ResetProfile
  hooks + profile generations.
- **OD-21 IncomeService is started by PetServer** (pcall-isolated, first in order); LeaderstatsService subscribes
  and keeps the legacy pay loop as a latched, never-concurrent fallback that runs only if IncomeService has not
  started 10 s after LeaderstatsService starts (4.5); ZombieRaidService's threat falls back to CashPerSec when
  `GetThreatIncome` returns nil (not started). A pet-system failure can therefore never stop cucumber income.
- **OD-22 Guard duration** = `min(600, Day + Night + 15)` from DayNightCycle script attributes, then the workspace
  mirrors, then defaults 180/10 (the cycle's own fallbacks) → 240 s live.
- **OD-23 Pet look** is applied on the server with `CucumberMutations.ApplyLook` (material, colours, emitters,
  light - replicated to every client) with `PrismaticLoop = true` pre-set, so the server's per-model PRISMATIC colour
  loop never runs for pets (it would exit at once on an unparented model and is a per-pet forever loop, against
  RULES). PetCardClient's single Heartbeat cycles PRISMATIC pet colours locally (3.12). The same latent bug exists
  for PRISMATIC eggs in EggPlacement (ApplyLook L216 before parenting L223): pre-existing, not changed, noted in the
  handoff.
- **OD-24 Buff eligibility excludes carrier-dropped cucumbers lying in the lobby** (footprint check), though they keep
  earning exactly as today.
- **OD-25 Pets opener lives in `LeftMenu` top row** (to the right of Shop/Build), animated by BaseHUDController slot 3,
  hidden in build mode and on the bench; MenuController owns its click + hover; HUDClient untouched; `ManagePanel` left
  alone. Pets panel does not close on entering the base.
- **OD-26 Owner toasts** (proc, shield, reserve) are sent even while the owner is in a portal (Notify is screen UI);
  world effects simply do not render for streamed-out targets.
- **OD-27 Diagnostics** live on `ServerStorage` attribute `PetDiag` (server-only, JSON), not on workspace.
- **OD-28 Inventory cap** `PetBalance.MAX_OWNED = 1000` new grants (≈ 300 KB of profile, far below the 4 MB
  DataStore limit; a Full PetState of that size is still sent in one message). At the cap hatching pauses (egg kept,
  `InventoryFull` toast). Existing over-cap records are never dropped. v1 has no pet release/delete (PLAN 8.3), so
  this is a safety valve, not a gameplay limit. **User to confirm** the number (and whether a release feature is
  wanted later).
- **OD-29 Duplicate egg Ids are never re-minted**: an egg is a single-use consumable, so a later record with an
  already-seen Id is dropped at Restore (printed) rather than given a fresh GUID (which would duplicate a hatch).
  Cucumber and pet duplicate Ids still get new Ids (PLAN 8.1 "distinct recoverable later record").
- **OD-30 GetState is not acknowledged when rate-limited** (dropped silently) and the client never blocks on it;
  roster requests inside their limit are always acknowledged with RequestId + Revision; over-limit roster replies are
  themselves rate-limited. Keeps spam from producing unbounded replies (PLAN 10 validation rule is met for every
  request the server accepts).
- **OD-31 Plot ownership check**: Equip/EquipBest require an attached plot owned by the player (`"NoPlot"`);
  Unequip does not (roster-only, lets a player free slots during a reload/reset window).
- **OD-32 Totals push is unrevisioned** (`Kind = "Totals"`) and fires only on change, so the 1 Hz totals stream can
  never create revision gaps or Full-request churn.
- **OD-33 Roam lead**: segments start `ROAM_LEAD = 0.3 s` in the future so clients receive them before they begin;
  server and client still sample the identical segment (no position smoothing added back).

---------------------------------------------------------------------------------------------------------

## 12. CRITIC ISSUE LOG (2026-09-22 review round; every issue verified against the live snapshot / PLAN.md)

Ids follow the order of the critic list (I01 = first issue). "fixed" = this file was changed; "rejected" = the
contract was kept as it was, with the reason.

| Id | Issue | Verdict | Reason / where fixed |
|---|---|---|---|
| I01 | SyncRaidLive skipped by CheckRaidEnd's early returns | fixed | Verified L689-698, L747, L1283-1289, L1655-1661. CheckRaidEnd is wrapped (body renamed), plus Escape/dev-spawn/SpawnThief call sites pinned (4.6 step 9). |
| I02 | Cucumber shallow copy taken before the v1 gate | fixed | Verified L210-216 replaces the array. Copy pinned after the gate + Version=1 test row (4.8, WP-SERVER, S3). |
| I03 | DataService migration in S2 erased by unpatched BaseSave | fixed | Verified L95/L138/L273-280. DataService moved to S3; S2 has no pet-data checks (10.2). |
| I04 | ApplyLook PRISMATIC loop dies before parenting / per-pet loop | fixed | Verified CucumberMutations L379-388, EggPlacement L216/L223. `PrismaticLoop` pre-set, client colour cycle in PetCardClient; OD-23 reworded; egg bug noted for the handoff (3.5, 3.12, 6.1). |
| I05 | OnLastSave hook connected before the left-during-load exit | fixed | Verified DataService L232-241. Hook moved after the early exit; callbacks no-op on nil data (rule 0.13); lost-ownership path documented (4.1 item 7, 8.4). |
| I06 | Shutdown flush only runs with DataStore access | fixed | Verified ProfileStore L2197-2206 vs L2208-2239. 8.4 + 10.2 say lifecycle tests use a normal leave. |
| I07 | Tag added before parenting breaks registration filters | fixed | Verified CucumberCarry L956-957, L1038-1039. Rule 0.14; 3.6/3.7 register every tagged model, eligibility at pay/grant time. |
| I08 | Build-mode move ghost keeps the tag and buff attributes | fixed | Verified BuildMenuClient L966-982, ghost parented to workspace (L556/L618). Plot/`Placed` filter for PetEffectsClient and 4.14 badges (rule 0.14). |
| I09 | Income stops entirely if PetServer/IncomeService fails | fixed | Verified L92-121 is the only payer. Latched legacy fallback in LeaderstatsService + `IsStarted()` (4.5, 3.9, OD-21) and a `PetServerSkipIncome` test hook. |
| I10 | IncomeOf reads 0 from a present-but-unstarted IncomeService | fixed | `GetThreatIncome` returns nil before Start; IncomeOf checks `IsStarted()` and falls back (3.6, 4.6 step 4). |
| I11 | BaseRestored/AttachPlot could land inside `if base` | fixed | Verified L181/L184-237/L238. Pinned right after L238, outside the block (4.8). |
| I12 | MenuClient `pcall(require(...).Start)` does not catch require errors | fixed | Verified MenuClient L3-6. Exact pcall-closure code pinned (4.11). |
| I13 | Anchor L107-108 splits the Modules block | fixed | Verified L107-109. Anchored after the L109 SoundController line (4.6 step 2). |
| I14 | OwnerName row said plot.Name | fixed | Verified PetHatchService L230-231. Row split (6.1). |
| I15 | No balance review / handoff stage | fixed | S9 added with each PLAN metric, how to measure it, the PetBalance-only rule and HANDOFF.md deliverables (10.2). |
| I16 | Hatch interruption matrix not planned | fixed | PetHatchDev `fail:*` hooks (4.2, 10.3), Core commit-matrix tests (WP-PETSVC), S3 matrix row with Reload/rejoin. |
| I17 | No profile restore procedure for destructive tests | fixed | snapshot/restore tools specified (1.1, 10.4) and mandatory after destructive runs (10.2). Sub-claim "apply_patches.lua absent" rejected: stage.ps1 copies it from pets-remake/. |
| I18 | FlushOwner contradicts the closing Never-rule | fixed | FlushOwner is the only closing-owner credit path, gates only on data, owner -> Flushed (3.6, rule 0.13). |
| I19 | Producer removal semantics undefined | fixed | Tag-removed / Owner-change / re-parent rules + late-settle discard + `LateSettles` diag + test (3.6, WP-INCOME). |
| I20 | Catalog not validated at runtime; no-ability-row species unspecified | fixed | PetServer step 2b + `ConfigProblems`; Valid/NoAbilityRow semantics pinned; tests (3.1, 3.2, 3.9, WP-STATS). |
| I21 | 0.2 s scan quantisation makes shots late (DPS 4-7 % low) | fixed | `Core.NextShot(prev, now, interval, scan) = max(prev+interval, now+interval-scan)`; first shot = now; tests (3.8, WP-COMBAT). |
| I22 | PetIncome to all clients vs PLAN "owner/nearby" | fixed | Kept all-clients as a recorded deliberate deviation with reasons, listed for the handoff (OD-15, 7.6). |
| I23 | Unavailable pets keep the slot, reconcile only on attach | fixed | Kept the slot (reason in OD-13) but added a 30 s scheduler retry = automatic mid-session reconcile; deviation listed for the handoff. |
| I24 | OD-11 never auto-equips after combat | fixed | Runtime `PendingAutoEquip` equips at unlock when slots are free (PLAN 1 wording); reveal notice + payload flag (3.5, 4.4, 7.4, OD-11). |
| I25 | Rate-limited GetState never acknowledged | fixed | GetState declared fire-and-forget on both sides (never a blocking request); OD-30 (3.5, 3.11, 7.1). |
| I26 | No save requested after migration | fixed | EnsureProfileState requests a save when the report says Changed (3.5). |
| I27 | TryBlockTheft `now` ambiguity; blocked zombie can grab another cucumber | fixed | Third arg ignored entirely; `BlockedUntil` gate on the L1271 grab; "recoil" defined as the stop (3.7, 4.6 step 5). |
| I28 | Balance numbers duplicated as text literals | fixed | Badge/Effect/ProcShort literals removed; PetStats text helpers build them from ABILITIES; Wild durations; test (3.2, 3.5, 9). |
| I29 | Rank not clamped; unknown traits altered / no diag | fixed | Rank clamp + Validate check, unknown mutation names kept byte-for-byte, arrays never truncated, `UnknownTraits` diag (3.1, 3.2, 3.4, 3.5). |
| I30 | No "before" performance baseline | fixed | S0 baseline stage; S8 reports deltas (10.2). |
| I31 | Several PLAN 14 cases unassigned | fixed | Added to WP-PETSVC/WP-BUFF tests and S3/S5/S6/S7 rows (no join/equip roll, offline cash, missing source pet, Stop, respawn, resize, threat with buffs, P mid-reveal, streamed-out open). |
| I32 | S2 migration check proves nothing durable | fixed | Same fix as I03. |
| I33 | `NoPlot` in the enum but never produced | fixed | Equip/EquipBest return NoPlot when not attached/owned; Unequip allowed; tests (3.5, OD-31). |
| I34 | Template children / gamepad unspecified | fixed | Template child names + Selectable/SelectionGroup + SelectedObject on open (3.11, 3.11.1). |
| I35 | Card shows rarity only as colour | fixed | Rarity word added to row 1 within the stud size (3.12). |
| I36 | P key opens the panel during a reveal | fixed | Keybind ignored while CucumberMenus is disabled or the BuildMode/BenchMode HUD attributes are set; S7 row (3.11, 4.12). |
| I37 | FinishPresentation can spawn a second model | fixed | `PresentationPending` flag never cleared by Detach/Attach/Equip; Finish spawns only when no model; PetId backstop; tests (3.5). |
| I38 | Close-phase callbacks may refuse because of the closing gate | fixed | Rule 0.13 + explicit gates on Freeze/FlushOwner/SyncRecords + test (0, 3.5, 3.6). |
| I39 | Routine income depends on PetServer bootstrap | fixed | Same fix as I09/I10. |
| I40 | KeptEggs doubles on Reload; duplicate egg Ids re-minted | fixed | Verified the Kept reset at L215 has no egg twin. KeptEggs reset, Collect de-dups kept eggs, duplicate egg Ids dropped not re-IDed, `Scope="Pets"` re-runs never touch eggs (3.4, 4.8, OD-29). |
| I41 | Collect cross-module calls can kill the heartbeat | fixed | Verified L273-280 unguarded. All calls pcall'd, heartbeat per-player pcall, consumed-egg set computed inside BaseSave from `old.Pets` (4.8). |
| I42 | GrantFromEgg not atomic if the egg search throws | fixed | Pinned order (fallible work first, then back-to-back mutation), pcall in PetHatchService with full release (3.5, 4.2, 8.2). |
| I43 | Revision/ClientReady lost on runtime rebuild | fixed | Per-player `Session` table survives rebuilds; `Generation` in payloads; unsolicited Full on rebuild (3.5, 7.2). |
| I44 | One-hatch-per-player relies on a non-yielding snapshot | fixed | `HatchBusy[player]` lock + yield assertion (4.2, 8.2). |
| I45 | ApplyLook PRISMATIC (lifecycle lens) | fixed | Same fix as I04. |
| I46 | PetCardClient never re-attaches after streaming | fixed | Re-attach watcher for cards; same for PetEffectsClient shells/index (3.12). |
| I47 | Segments reach clients late -> jump at each leg start | fixed | `TIMING.ROAM_LEAD = 0.3` future start; OD-33 (3.5, 9). |
| I48 | Vanished pet model keeps earning/fighting | fixed | `Destroying` watcher -> Unavailable + producer removed; IncomeService pays pet producers only in workspace (3.5, 3.6). |
| I49 | Ledger re-created/credited after owner gone or reset; stacked connections | fixed | UserId ledgers, Live/Flushed/Forgotten states, reset sets LastSettled=now, Conns disconnected on unregister (3.6, 8.5). |
| I50 | Restore waits 30 s on a failed PetService | fixed | No pet wait before the world restore; `WaitReady(2)` only before AttachPlot; late-start sweep in PetService.Start (3.5, 4.8, 8.1). |
| I51 | PetServer step 6 throws in S2 without PetService | fixed | Step 6 registered only when PetService started, callback pcall'd; PetDev branches guarded (3.9). |
| I52 | S2 migration (lifecycle lens) | fixed | Same fix as I03. |
| I53 | Index cache misses fresh grants | fixed | GrantFromEgg/PetDev update ById/BySourceEgg in the same block; test (3.5). |
| I54 | Totals every tick bump Revision and cause gaps | fixed | OnTotalsChanged only on change; unrevisioned `Kind="Totals"` message (3.5, 3.6, 7.2, OD-32). |
| I55 | Limiter lives in Runtime | fixed | Limiters in `Session`, applied before validation in every load state; over-limit replies rate-limited (3.5, 7.1). |
| I56 | NextShot written after a possibly-yielding Damage | fixed | Deadline consumed before the Invoke + `Scanning` re-entrancy flag (3.8). |
| I57 | Raid state at flush time loses/misplaces cucumbers | fixed | Verified L586-588, L631-633, L1617-1622. Order-35 `PreCloseRaids` + `force`/`noSnapshot` params; EndRaid "Left" uses force (4.6 step 10, 8.3, OD-16). |
| I58 | Unbounded canonical inventory | fixed | `MAX_OWNED = 1000` safety cap with InventoryFull, profile-size diag; Full payload left unpaged at that size (OD-28, user to confirm). |

Totals: 58 issues, 58 fixed (4 are duplicates resolved by the same change: I32/I52 -> I03, I39 -> I09, I45 -> I04),
0 rejected outright; one sub-claim of I17 (apply_patches.lua missing) was rejected as factually wrong.

### 12.1 INTEGRATION AMENDMENTS (integration agents, dated; each with the reason)
- **S0a, 2026-09-22 - profile tools transport (amends 10.4).** The playtest SERVER VM (`eval_server_runtime`) runs in
  game context: `HttpService:GetAsync/PostAsync` fail with "HTTP requests are not enabled" (HttpEnabled is off and
  must stay off), `loadstring` is unavailable and the eval code cannot use `...`. So `tools/snapshot_profile.lua` and
  `tools/restore_profile.lua` move the JSON through a scratch DataStore entry (store `PetTestTransfer`, keys
  `Snapshot_140977250` / `Restore_140977250`) instead of the loopback servers. The same file runs in both VMs:
  restore = step 1 in the EDIT peer (`loadstring("local PROFILE_TOOL_OPTS = ...\n" .. src)({Name = ...})`, stages
  tests/<Name> and returns a Nonce) then step 2 pasted into `eval_server_runtime` behind one line
  `local PROFILE_TOOL_OPTS = {Name = ..., Nonce = ...}`; snapshot = step 1 pasted into the server VM, step 2 in the
  edit peer (POSTs to receive.ps1 :8797 → tests/). Restore also resizes the plot first (PlotUpgradeDev Studio hook)
  when the saved PlotLevel differs, waits out the join-time BaseSave restore, and refuses the REAL key unless
  `AllowRealKey = true`. stage.ps1 now copies both tools into stage/ (served at :8796).
- **S0a, 2026-09-22 - a Studio Stop IS a normal leave (amends 8.4 / 10.2 "never a Studio Stop").** With API access on,
  Stop fires `PlayerRemoving` before ProfileStore's BindToClose: a probe `OnBeforeClose` callback ran with reason
  `"Leave"`, `GetData ~= nil`, `IsClosing = true`, `player.Parent == nil`, and the value it wrote landed in the final
  saved DataStore value (Cash in the probe == saved Cash); the session was released (`ActiveSession` nil). Lifecycle
  flush checks may therefore use Stop → start as the leave → rejoin (a server-side Kick is not needed).
- **S0b, 2026-09-22 - the S0/S8 load scenario, pinned (amends the 10.2 S0 and S8 rows).** A `multiplayer_playtest`
  gives Player1..N (UserIds -1..-N) on fresh `PetTest_-N` keys: no cucumbers, so a raid skips them ("nobody has
  cucumbers placed"), and they are never UserId 140977250, so the "heavy plot" cannot be loaded from a profile. The
  baseline is therefore two parts, and S8 must repeat both with the same tool parameters:
  (a) **solo** playtest on `PetTest_140977250` (Plot 5, level 2, 51 builds, 2 cucumbers) → Cash/s, threat level, and
  the profilers during a `ZombieDev raid` fired at dawn; (b) **multiplayer, 2 clients**, each plot seeded with the
  fixture's 2 cucumber records by pasting `tests/S0_mp_seed.lua` into the server VM (CucumberCarryAPI.RestorePlaced,
  negative UserIds only), then `ZombieDev raid` at dawn. Profiler parameters: `capture_script_profiler` 10 s at 1000 Hz
  on the server during the raid; `capture_micro_profiler` 5 s with the default `max_events` (every capture is partial
  at that limit, so only like-for-like captures compare); 1 Hz Heartbeat/Stats samplers + OnClientEvent/OnServerEvent
  counters as in `tests/S0b_report.md`. Numbers: `tests/S0_baseline_summary.json`.
- **S2, 2026-09-22 - LeaderstatsService "Waiting" writes CashPerSec (amends 4.5).** 4.5 left `CashPerSec` unwritten
  while the latch is `"Waiting"`, so with IncomeService not started (the `PetServerSkipIncome` fallback, or a failed
  PetServer) CashPerSec read 0 for the first `LEGACY_AFTER` = 10 s after the server started. ZombieRaidService's
  threat fallback reads CashPerSec, and a night raid that began 4 s after the server started came at **level 4
  instead of 5** (log `survived (level 4, stolen 0/2)`; score 23.33 instead of 41.74). Fix: while Waiting and
  `IncomeService.IsStarted()` is false, `RefreshIncome` (Setup + every latch tick) writes `CashPerSec` / `Cash/s`
  from the placed cucumbers' sum (`WaitingIncomeOf`: read-only, no `Rate` stamp, nothing paid). It never runs once
  IncomeService has started, so there is still exactly one CashPerSec writer at a time. Remaining gap (fallback
  only): the legacy/Waiting CashPerSec follows cucumber changes at the next 1 s tick, not on the tag signal (the
  contract removed the tag wiring), so a raid starting < 1 s after a restore can still read the stale value. In
  Service mode the threat reads `GetThreatIncome` and is immediate (verified: a raid fired 3.7 s into a session,
  right after the restore, was level 5).
- **S2, 2026-09-22 - until S3, the leave flush credits nothing (expected, fixed by 4.8/4.9).** With the unpatched
  PlotService (`Release` on PlayerRemoving) and BaseSave (`ClearPlaced` on PlayerRemoving) the plot is already
  released (Owner nil, 0 owned cucumbers left) when DataService's `RunBeforeClose` runs, so
  `IncomeService.FlushOwner` (order 20) settles the producers at 0 (not in the workspace) and the last partial
  second is not paid, as in the pre-pet legacy loop. S3 must re-check that FlushOwner credits the partial second
  once the teardown is deferred (probe recipe in `tests/S2_report.md`).
- **S3, 2026-09-22 - seeding a LEGACY profile for the load-time migration (amends 10.4 "Isolation first").** With S3
  installed, an in-session `restore_profile.lua` of a legacy JSON migrates at once: its `BaseSaveAPI.Reload` ends in
  `PetService.EnsureProfileState`, which runs `Migrate(Scope = "Pets")` (legacy roster, `PetSchemaVersion = 1`) and
  the next save stores the migrated shape, so a later rejoin never exercises the load-time `Scope = "All"` path.
  To test the load-time migration, write the legacy Data straight into the test key from the EDIT peer while no
  session is active: `UpdateAsync("PetTest_140977250", fn)` that keeps the ProfileStore envelope/MetaData and
  `keyInfo:GetUserIds()` / `GetMetadata()` and swaps only `.Data` (refuse when `MetaData.ActiveSession ~= nil`).
  S3 did this with the before-pets fixture; the first playtest then logged the migration report `Legacy = true`.
- **S3, 2026-09-22 - leave flush order (amends the S2 probe recipe).** PlayerRemoving handlers run in any order, and
  IncomeService's own handler calls `FlushOwner` as well. In S3 it ran BEFORE DataService's `RunBeforeClose`, so
  probes at orders 15/25 both saw `Flushes = 1` and equal Cash. The partial second is still paid: at order 15 the
  plot was intact (Owner set, both cucumbers in the workspace, which is the effect of the 4.8/4.9 deferral), and the
  saved Cash covers income up to the leave (2.47 s of income from the last reading, 0.47 s of it after the last
  tick). Check the flush by comparing the saved Cash with the last tick, not with a before/after pair of probes.
- **S4, 2026-09-22 - pet models stream Atomic (amends 3.5 DefaultSpawn and 4.13's streaming rule).** Pets are
  anchored server models in the Default streaming mode, so each part streams on its own, and PetRoamClient moves the
  model on the client only. A client-side test that took one Bunny part out and brought it back at its server (spawn)
  pose left it **37 studs** from the Root for the rest of the session: 4.13's watcher re-attaches only when the Root
  returns (review defect 6). Fix: `DefaultSpawn` sets `pet.ModelStreamingMode = Enum.ModelStreamingMode.Atomic`
  before parenting, so the engine sends and removes the model with all of its parts at once. The client then sees tag
  removed → tag added with every part at the server pose, and Attach re-measures the whole model. The Root watcher in
  PetRoamClient / PetCardClient stays as a safety net. Studio did not stream anything out in this map (a client
  1,450 studs away kept every pet part for 17 s and was even sent a newly spawned pet), so the stream-out/in checks
  in S4 are client-side simulations (tests/S4_report.md).
- **Fixer "income", 2026-09-22 - a profile reset HOLDS the pre-reset producers (amends 3.6 `OnProfileReset`, 8.5
  step 2; closes S3 open issue 1).** Setting `LastSettled = now` was not enough: BaseSaveAPI.Reset's deferred
  `TagRemoved` runs a fraction of a second after `ProfileReset` and settled that gap into the fresh profile (S3:
  Cash 12.26 after the reset at 40.2K/s; unit repro 12.06 for 0.3 ms). `E.ProfileReset` now also sets
  `Producer.Held = true` on every producer of that owner. A held producer's settlements are **discarded** (diag
  `LateSettles`, no ledger, no popup) in Store (Refresh / TagRemoved / OwnerChanged / SetPetProducer /
  RemovePetProducer / SettleOwner), in the tick and in `FlushOwner`. The hold ends when a tick finds the producer
  eligible (it earns from that tick on; at most one tick of a surviving producer is dropped), when an `Owner`
  change re-keys it, or when `SetPetProducer` re-sets it. Producers registered after the reset are never held.
  GetDiagnostics keys unchanged. Tests: `WP-INCOME_engine` section 19 (20 checks).
- **Fixer "petsvc", 2026-09-22 - after-combat hatches and EquipBest churn (amends 3.5 GrantFromEgg / RuntimePet /
  HandleRequest / Core, 7.1, OD-11; review defects 8, 9, 5).** (a) **#8:** "slots were free" for the OD-11 queue
  now counts the hatches already queued this lock: `AutoEquipAfterCombat = locked and spawnable and
  #roster + queued < SLOTS`, where `queued` = the `PendingAutoEquip` ids still owned and not in the roster. A
  hatch past that point is a plain reserve pet (`AutoEquipAfterCombat = false`), so the reveal shows
  `ReserveNotice` and no promise is broken. `Core.GrantFromEgg` ctx gains an optional `Pending` (number; non-finite
  or negative = 0). It only affects the after-combat flag, never a direct (unlocked) equip. (b) **#9:** GrantFromEgg
  sets `PresentationPending = true` for an `AutoEquipAfterCombat` grant as well as an equipped one. An unlock during
  the reveal still equips it (status `Pending`, no model or producer), and `FinishPresentation` spawns it at the egg
  spot. A reveal that ends while still locked clears the flag, and the unlock then spawns it as before (saved Pos or
  plot centre). EggHatchClient still picks `LockedHatchNotice` from the Begin payload: after a mid-reveal dawn the
  text is stale but not false (the pet joins when the fight is over). (c) **#5:** a client's `EquipBest`
  (HandleRequest only) spends one token per model it would spawn or despawn from a new `Session.ChurnLimiter`
  (`MODEL_CHURN_BURST` = 2 x SLOTS = 12 at once, then `MODEL_CHURN_PER_SECOND` = 2/s; optional
  `PetBalance.REQUESTS` keys of those names override). Over budget it answers `Result.Error = "RateLimited"`
  before anything changes (roster, queue, models). A swap that changes no model costs nothing. The
  `PetService.EquipBest` API (PetDev, server callers) is never throttled. `Limiter:Take(now, count?)` spends
  `count` tokens (default 1), all or none. Tests: WP-PETSVC core (Pending, counted limiter), roster G / G2
  (queue promise, mid-reveal dawn) / D2 (churn budget).
- **Fixer "raid", 2026-09-22 - grapple home and the rope's lifetime (amends 4.6 items 7 / 10 and its "Must NOT change:
  AI" line; review defects 3, 4).** (a) **#3:** `SettleGrapple` is forward-declared (`local SettleGrapple` next to
  `SyncRaidLive`) and `Forget` calls it, so a grappler that dies or leaves (Kill, Despawn, destroyed from outside) lets
  go at once, before `CheckRaidEnd` → `ReturnDropped`. The grapple task reads `settled = entry.GrappleTarget ~= target`
  before its own clear and never pivots a settled cucumber. An unsettled failure pivots to `home` once
  `raid.Over or raid.Ended` (ReturnDropped has already run, so nothing else would send it home), else to `rest` as
  before. (b) **#4:** the task stores `entry.GrappleHome = home` next to GrappleTarget/GrappleRest (read only while
  GrappleTarget is set; never cleared). `HookedBy(raid, model)` = the raid entry whose GrappleTarget is that model.
  `HomeRest` returns `HookedBy(...).GrappleHome` first, so a zombie that grabs a cucumber mid-pull carries (and a
  later drop / ReturnDropped / RestoreCarry / PreCloseRaids uses) the real home, never the dragged pose. Right after
  it computes that rest, `Grab` also takes the cucumber off the rope: `HookedBy(raid, model)` → that entry's
  `GrappleTarget` / `GrappleRest` = nil (after the TryBlockTheft guard, so a shield-blocked grab changes nothing; the
  grappler's own final Grab has already cleared its rope). Before this, a rope went stale when another zombie grabbed
  during the 0.85 s hook: the carrier's `RestoreCarry` sent the cucumber home at a raid end (EndRaid, the ZombiesWin
  loop, PreCloseRaids), then the stale rope's `SettleGrapple` put it back at the pre-hook lobby pose whenever the
  carrier came first in `raid.Zombies` (checker follow-up). A stale rope also no longer re-pulls a cucumber the
  carrier dropped mid-hook from the grappler's old rest pose: its task sees the rope settled and ends without moving it.
  **AI change:** one rope per cucumber. `StartGrapple` returns false when `HookedBy` finds a rope on the target, and
  Tick then walks the second grappler in as before (dig check, Navigate, ordinary grab). Two ropes used to fight over
  PivotTo every frame, and SettleGrapple's list order picked the last pose. Leaf Shield / TryBlockTheft guards are
  unchanged. Tests: `WP-BUFF_grapple` (72 checks: stepped-scheduler simulation of the real functions, including the
  real Grab / RestoreCarry / Despawn / EndRaid / PreCloseRaids; T13-T17 cover the stale rope in both list orders)
  and `WP-BUFF_patches` (SettleGrapple checks follow the forward declaration).
- **Fixer "world", 2026-09-22: the pet card's ability tag (amends 3.12 PetCardClient row 2 "plus a small ability
  glyph", and PLAN 11 "small ability icon").** S4 open issue 1: the glyph was a round chip 0.8 of the cash row (0.73
  studs) with the emoji at 78 % of it (about 0.57 studs), on a chip of the ability's own colour. So the gold ✨ on gold
  read as a plain gold dot at normal viewing distance. The cash row now holds only the green `$X/s`. Pets whose
  `Ability` is Yield / Haste / Guard / Wild get a third row `AbilityTag` (LayoutOrder 3, `TAG_H = 0.8` studs, the
  cucumber card's BADGE_H). It has a TextLabel `Glyph` (the emoji in a square as tall as the row: 0.8 studs, about
  1.4x the old one) and a TextLabel `Ability` = `PetBalance.ABILITIES[k].DisplayName` (for example `Lucky Harvest`) in
  the ability colour with the dark 12,12,12 stroke. Its width comes from the character count (CHAR_W, like the rarity
  word) and is capped at the room the glyph leaves, so every word is at least about 0.55 studs tall. Sizes stay in
  studs: an ability pet's card is 5.2 x 2.7 studs. The name and cash rows keep their stud heights (fractions
  renormalised), the bottom edge stays GAP_ABOVE over the pet, and `+$` popups start at the new top edge. Fighters
  (`Ability` None, or an unknown ability) keep the old 5.2 x 1.9 card with no tag. The `AbilityGlyph` chip is gone.
  Pure helpers `Core.AbilityTag` / `CardRows` / `TagWidths` are covered by 27 new checks in `WP-WORLDFX_cards`. The
  next integration stage must re-check S4 check 5 on the live card: the tag text, and the 2.7-stud card height for
  ability pets.
- **Fixer "world", 2026-09-22: review defect 6, client side (no contract change).** PetRoamClient and PetCardClient
  stay as S4 pushed them. With `ModelStreamingMode = Atomic` every stream-out and stream-in moves the whole model: it
  either leaves and re-enters the DataModel (tag removed, then tag added: a fresh Attach at the server pose), or keeps
  the tagged instance while all its parts are replaced together (the Heartbeat Root check detaches, and the
  DescendantAdded / initial Watch check re-attaches). Either way the parts are coherent when Attach measures them.
  DefaultSpawn is the only live spawn path, and nothing adds BaseParts to a pet after it is parented (ApplyLook adds
  only emitters and lights before parenting). So no partial-part case is left. `tests/WP-WORLDFX_stream.lua` (new, 32
  checks) runs the whole PetRoamClient on plain-table fakes through these scenarios: same instance back, new instance
  back, a Heartbeat before the tag signal, parts replaced while the model stays, parts replaced within one frame, and
  a stream-out during Attach's PartCount wait. Mutations prove its checks can fail.
- **Fixer "menu", 2026-09-22 - phone layout, incremental grid, width-fitted chips, non-fighters (amends 3.11 and
  3.11.1; review defects 2, 7, 10, 11).** (a) 3.11.1 gains three instances, hidden in the wide layout:
  `Toolbar.SortCycle` and `Toolbar.FilterCycle` (the toolbar button shape: TextButton > `Label`, `Gradient`) and
  `Details.BackButton` (same shape). `PetCard.Chips` has `ClipsDescendants = true`. PetsPanel gets the attribute
  `CompactBelow = 0.55` from the builder, and PetView writes the runtime mirror `Compact` (boolean). Every instance
  whose phone value differs carries `Compact_<Property>` attributes (UDim2 / number / boolean / EnumItem). Text caps
  are set on the instance's `UITextSizeConstraint`, or on its `Label`'s for buttons. PetView applies them while
  `PetsPanel.ResponsiveScale.Scale < CompactBelow` (the 844x390 landscape fit is 0.372) and puts the authored values
  back above that, and again on `Destroy`. The compact layout keeps the 1140x735 canvas. It hides the slot row and the
  7 sort/filter tabs. The two cycle buttons and the two Best buttons form one 110-tall row. The grid has 2 columns of
  525x196 cards. Details becomes a page over the grid and toolbar: a card tap opens it and BackButton closes it. The
  CloseButton hit area grows to 118x118 and its art stays centred. Every compact text is >= 30 design px (about 11
  real px) for its longest realistic string, and every button is >= 110 design px (about 41 real px);
  `tests/WP-MENU_compact.lua` measures this. For `Details.Traits` the longest realistic string is a material plus all
  eight known mutations (about 1065 px at 30): in compact it is the last line of the text column (PetName 8, Rarity 60,
  CashLine 100, Traits 146), 560x90, `TextWrapped`, top-aligned, so it wraps to up to three lines at 30. Only a list
  with long unknown mutation names (PetStats keeps them verbatim) can shrink it, toward the SizeCap floor of 20.
  MenuController and MenuClient are unchanged: PetView watches the scale itself, so `fit()` stays as in 4.10.
  (b) 3.11 PetView API additions: `view.SetFooter(footer)`, `view.ShowDetails(open)` (compact page, a no-op when
  wide), and the pure `View.FitChips(chips, widthOf, maxWidth, gap)`. Cards are created in display order: 24 on the
  first render, then 18 per 0.15 s scan while the grid is scrolled near the last card. Positions past that prefix
  stay hidden and pooled. A re-render writes only cards whose texts, selection or order changed. PetController:
  `Core.CardOf(...).Chips` now carries every material/mutation chip, and PetView folds what does not fit the row's
  width into `"+N"` (was a count cap of 3). New `Core.FooterOf(totals, env)`. A `Kind = "Totals"` message only calls
  `view.SetFooter`, and only while the panel is open with no render queued, so it never re-sorts or re-renders. A
  switch between the wide and compact layouts re-draws PetView's held view model without its footer, so totals from
  a later `SetFooter` stay on screen (checker round, 2026-09-22). The `PetsDev` hook gains `"back"`, and `"select:<n>"` also opens the compact page. (c) `Core.DetailsOf`: when the ability
  is `"None"` and `Stats.Fighter ~= true` or `Status == "Invalid"`, the details show `AbilityName = "No ability"`
  (`AbilityKind = "NoAbility"`, which has no ABILITIES row, so white) and no effect, chance or roll lines. An Invalid
  pet's combat line reads "Does not fight". Only real fighters show "Fighter: +15% damage" (PLAN 11).
- **S7, 2026-09-22 - menu install: text caps, phone fit, click-through (amends 3.11.1 and the fixer "menu"
  amendment (a)).** Three defects found only in the live playtest; each fixed, unit-tested and re-verified live.
  (a) **UITextSizeConstraint MaxTextSize / MinTextSize are SCREEN px** (they apply after the panel's
  ResponsiveScale UIScale; measured: a SizeCap Max 10 gave 10 px text at scale 0.36, Min 20 forced 20 px text
  into 13-18 px boxes). The builder authors them, and `Compact_MaxTextSize` / `Compact_MinTextSize`, in DESIGN
  px, so on the iPhone 13 preset every compact line was forced to 20 px and overflowed (footer wrapped under
  the panel, details lines ran into each other). PetView now keeps each cap's design values in the attributes
  `DesignMaxTextSize` / `DesignMinTextSize` (written once on the runtime copy) and writes design x
  `ResponsiveScale.Scale` (rounded, >= 1; the compact or wide design value) whenever the scale or the layout
  changes; `Destroy` writes the design values back. Caps are no longer part of `CollectLayout`/`ApplyLayout`.
  The design-px rules of amendment (a) (compact text >= 30, buttons >= 110) now hold on screen.
  (b) **`FitMargin` = 1 (was 0.95).** Studio's iPhone 13 preset gives a 749 x 310 GUI area (notch / home-bar
  safe area + the 58 px top bar), not the 844 x 332 assumed, so 0.95 fitted 0.344 (compact text 10.3 px,
  buttons 37.8 px). At 1 the fit is 0.362: text >= 11 px (30 design px, rounded caps), buttons 39.8 px, close
  42.7 px, cards 70.9 px tall. `MenuController.fit` still keeps 16 / 22 px of screen around the panel; at
  1920 x 1080 the panel is 1140 x 735 (scale 1), at a 1301 x 611 window 0.6925. `WP-MENU_compact` now fits
  the 749 x 310 case (floors = 30 / 110 design px x fit) and checks the old 844 x 332 case strictly (11 / 40).
  (c) **`PetsPanel.Content.ClickShield`** (builder): a transparent, non-selectable TextButton, ZIndex 1, on the
  Body's rect. MenuController closes a panel on its full-screen `Dimmer` button, and a click on non-button
  art/text falls through to it (`Active` on a Frame or the CanvasGroup does not stop that), so a tap on the
  details text, footer, header or panel body closed the Pets panel. Now only a click outside the body closes
  it. The same fall-through exists on ShopPanel / IndexPanel (pre-existing, measured on the Index body; not
  changed - handoff). MenuController itself is unchanged apart from a comment.
- **S8, 2026-09-22 - the multiplayer load run needs a long start timeout (amends the S0b amendment's recipe).** With
  three Studio places open, Studio took about 90 s to spawn the test processes of a 2-client `multiplayer_playtest`.
  A `start` with `timeout` 90 gave up two seconds before they appeared (`multiplayer_start_not_detected`), the MCP
  dropped the group, the new peers never registered, and the orphaned session then blocked every later playtest
  ("a previous one is still in progress") until someone presses Stop / End Test in Studio (no MCP call can end it:
  `StudioTestService:EndTest` works only in the test's server DataModel). Use `timeout` 240 or more for the load run,
  and never start another playtest after a `multiplayer_start_not_detected` without checking `get_connected_instances`.
