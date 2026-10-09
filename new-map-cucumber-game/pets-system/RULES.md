# Pet system build - shared rules for every agent

Project root: `C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\pets-system\`
- `PLAN.md` - the user's spec (authoritative for behaviour + numbers).
- `CONTRACTS.md` - the pinned module APIs / patch points / remote shapes (authoritative for interfaces once written).
- `research/` - subsystem maps written from the live code.
- `src/` - NEW scripts, one file per script, named `<DataModel path>.<kind>.lua` (kind: `lua` = ModuleScript, `server.lua` = Script, `client.lua` = LocalScript), e.g. `ServerStorage.PetService.lua`, `StarterPlayer.StarterPlayerScripts.PetCardClient.client.lua`.
- `patched/` - full edited copies of EXISTING scripts, same file name as the snapshot copy in `../live-2026-09-22/`. Never edit the snapshot folder itself (it is the "before" side of the patch diff).
- `tests/` - Luau test chunks (return a function or run top-level, `return` a summary string) + results.

Live source snapshot (read-only, taken 2026-09-22 from Studio): `C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\live-2026-09-22\`
- 237 scripts, file name = full DataModel path with non `[A-Za-z0-9._-]` chars replaced by `_`, suffix `.lua` / `.server.lua` / `.client.lua`. `_manifest.json` maps file -> path/class. `_gui_tree.txt` = StarterGui CucumberHUDDesign / CucumberMenus / EggRevealUI trees with sizes. `_structure.txt` = RS / ServerStorage / SSS children, pet model names, script attributes, plot children. `_profile_Player_140977250_before-pets.json` = the test account's saved profile (real data shape).
- Read and grep these LOCAL files instead of calling Studio for reading. They are exact copies (LF/CRLF may differ).

## Studio access (Roblox MCP)
- The place "New Map Cucumber Game" (placeId 87967102884366) is connected to the chrrxs server as `instance_id: "instance:c9f-ksl"` - pass it on every `mcp__robloxstudio__*` call. The official `Roblox_Studio` MCP has no studio registered right now.
- Load tools with ToolSearch (`select:mcp__robloxstudio__execute_luau,...`).
- **During research / implementation phases you may use Studio ONLY for read-only work**: `execute_luau` (edit peer, default target) running `loadstring(src)` compile checks and pure-logic unit tests that create NO instances and change NOTHING in the DataModel. Never set a Source, never create/destroy/reparent instances, never start/stop a playtest unless your task explicitly says you are the integration/test agent.
- Keep each `execute_luau` under ~15 s. Studio evals are queued one at a time across all agents, so batch several checks into one call.
- To compile-check a local file: read it, embed it in a Luau long string with a level that does not occur in the source (e.g. `[=====[ ... ]=====]`), then `local f, err = loadstring(src)`. For a ModuleScript test, `local mod = f()` works only if the module's requires can be satisfied - pure modules should take dependencies as arguments or require only `game:GetService("ReplicatedStorage").Modules.X` things that already exist live (PetsCatalog, CucumberMutations, NumberAbbrev). A module NOT yet in Studio can be loaded from its source text with loadstring and injected.
- **Loopback file servers are running** (read-only, 127.0.0.1): `http://127.0.0.1:8793/<file>` serves `src\`, `:8794/<file>` serves `patched\`, `:8795/<file>` serves `tests\`, `:8796/<file>` serves `stage\`. From an edit-peer `execute_luau`: `local H = game:GetService("HttpService"); local src = H:GetAsync("http://127.0.0.1:8793/ServerStorage.PetService.lua"); local fn, err = loadstring(src)`. Use this instead of pasting big sources into the eval. Files are served flat by bare file name (no subfolders).
- The chrrxs eval VM caches `require`d modules across evals: `require(module:Clone())` busts it (but a clone has no Parent, so `script.Parent` lookups break).
- Print output is truncated at the first nil vararg; wrap values in tostring(). Return a single summary string instead of printing.

## Hard user rules (from the project memory)
- NEVER use desktop tools: no PowerShell window captures, SetForegroundWindow, SendKeys, mouse clicks. Roblox MCP only.
- Do not publish the place. Do not edit historical backup copies (anything under ServerStorage named `__*` or containing "Backup").
- Currency is **Cash** everywhere (Data.Cash, CashPerSec, Remotes named Cash*). Never introduce "Coins".
- Overhead/world UI (BillboardGuis) is sized in STUDS (scale units + scale-only children), like PlotBadges' owner badge - never fixed-pixel billboards.
- Overhead cash text = plain green "$50K/s" / "+$50K" (green 65,235,20 with a dark 12,12,12 stroke), FredokaOne, NO cash icon (see PlacedCucumberCardClient).
- ALL toasts go through `ReplicatedStorage.Modules.Notify` (Notify.Show / Success / Error / Info ...). No new toast GUIs.
- UI motion should be Heartbeat-stepped (ButtonFX.Animate style) rather than TweenService where verification matters (Studio unfocused = RenderStepped/tweens frozen).
- Two UIScales under one GuiObject do NOT stack; MenuController owns HoverScale UIScales.
- Never destroy `CucumberHUDDesign`'s TopStatus frame (shared top-centre reserve).
- Test hooks must be Studio-only (`RunService:IsStudio()`) or behind the existing admin permission check (AdminService, UserId 140977250).
- Playtests in Studio write the test account's REAL profile (USE_MOCK_IN_STUDIO = false). Destructive tests must restore state; a JSON backup of the profile exists.

## Code style
- Match the surrounding code: tabs for indentation, header comment block describing the script (the existing scripts have dated paragraphs like "(2026-09-12)"), `local X = game:GetService("X")` at top, UPPER_CASE config constants, PascalCase module functions. Keep comments at the density of the neighbouring scripts. Luau (Roblox) - `task.*`, `continue`, compound assignment, type annotations optional.
- Server modules that hold state expose `Init(deps)` + `Start()`; no side effects at require time beyond building constant tables.
- Every numeric value that came from data is validated finite (`x == x and x ~= math.huge and x ~= -math.huge`).
- No per-pet forever loops; one shared scheduler per concern.
- Date stamp for comments: 2026-09-22.
