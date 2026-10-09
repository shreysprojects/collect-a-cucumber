# Research: income + rates (live snapshot 2026-09-22)

Source: `live-2026-09-22\` local mirrors (237 scripts). All line numbers below refer to those files.
Files deep-read: `ServerScriptService.LeaderstatsService.server.lua` (174 lines), `ReplicatedStorage.Modules.CucumberValues.lua` (98),
`ReplicatedStorage.Modules.CucumberMutations.lua` (394), `StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient.client.lua` (268),
`StarterGui.CucumberHUDDesign.HUDClient.client.lua` (218), `ServerStorage.DataService.lua` (280), `ReplicatedStorage.Modules.ZombieCatalog.lua` (threat part),
`ReplicatedStorage.Modules.NumberAbbrev.lua`, plus the income-relevant parts of ZombieRaidService, CucumberCarry, CucumberMoveServer, BaseSaveService, AdminService, PlotService.
Grepped all 237 files for: `CashPerSec`, `"Rate"` / `RATE_ATTRIBUTE` / `GetAttribute("Rate")` / `SetAttribute("Rate")`, `CucumberIncome`, `Increment(`, `"Cash"` / `.Cash`, `leaderstats` / `Cash/s` / `RawRate`, `RateOf` / `ValueOf`, `PlacedCucumber`.

Environment facts that matter for income: `StreamingEnabled=true` (`_structure.txt:677`); signals are **Deferred** (BaseSaveService:328, BuildService:222, CucumberCarry:473 comment on it); `Remotes.CucumberIncome` is NOT an authored instance (edit-mode `ReplicatedStorage.Remotes` holds only `GymBoardState` / `GymBoardAction`, `_structure.txt:36-38`) - LeaderstatsService creates it at run time.

---

## 1. The pay loop (ServerScriptService.LeaderstatsService, Script)

Constants (lines 31-35):
```lua
local PLACED_TAG = "PlacedCucumber"
local RATE_ATTRIBUTE = "Rate"
local CASH_KEY = "Cash" -- the DataService key the income lands in
local INCOME_TICK = 1 -- seconds between payouts (a Rate is cash per second)
local INCOME_REMOTE = "CucumberIncome" -- RemoteEvent -> all clients: (models, amounts) each tick
```
`Stats` (line 37) = `[player] = {Strength = StringValue, Rate = StringValue, RawRate = NumberValue, StrengthValue = NumberValue}` - a player is only paid once they have a `Stats` entry (set in `Setup`, line 143).

Remote (lines 39-44): `Remotes:FindFirstChild("CucumberIncome")` or `Instance.new("RemoteEvent")` named `CucumberIncome`, parented to `ReplicatedStorage.Remotes` at script start.

### Which cucumbers count - `EarningFor(player, callback)` (lines 54-60)
```lua
for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do
    if model:GetAttribute("Owner") == player.UserId and model:IsDescendantOf(workspace) then
        callback(model, tonumber(model:GetAttribute(RATE_ATTRIBUTE)) or StampRate(model))
    end
end
```
- Eligibility = tag `PlacedCucumber` + attribute `Owner == player.UserId` + `IsDescendantOf(workspace)`. **No plot check** (the model's Owner is trusted, the plot's `Owner` is not consulted) and no `StolenBy` check (a stolen cucumber has already lost the tag, see 5).
- Rate used for PAYMENT = the replicated `Rate` attribute (trusted as-is), lazily stamped if missing/non-numeric.
- Cost: for each player in `Stats` it scans every tagged cucumber in the server -> O(players x all placed cucumbers) per tick.

### `PayIncome()` (lines 94-113) and the loop (115-121)
```lua
for player in pairs(Stats) do
    if player.Parent == Players and DataService.IsLoaded(player) then
        local total = 0
        EarningFor(player, function(model, rate)
            local amount = rate * INCOME_TICK
            if amount > 0 then total += amount; table.insert(paidModels, model); table.insert(paidAmounts, amount) end
        end)
        if total > 0 then DataService.Increment(player, CASH_KEY, total, true) end
    end
end
if #paidModels > 0 then incomeRemote:FireAllClients(paidModels, paidAmounts) end
```
```lua
task.spawn(function()
    while true do
        task.wait(INCOME_TICK)
        local ok, err = pcall(PayIncome)
        if not ok then warn("[LeaderstatsService] income tick: " .. tostring(err)) end
    end
end)
```
Facts:
- Tick = `task.wait(1)`; payment is the **nominal** `rate * 1`, never the measured elapsed time. `task.wait(1)` always resumes >= 1 s later, so real income drifts slightly BELOW the displayed rate (~1-3 % per tick); a server hitch loses time rather than catching up.
- A cucumber placed 0.1 s before a tick earns a full second; one removed 0.1 s before earns nothing for that partial second.
- Owner check: `player.Parent == Players and DataService.IsLoaded(player)`.
- Workspace check: `model:IsDescendantOf(workspace)` (in `EarningFor`).
- One `DataService.Increment(player, "Cash", total, true)` per owner per tick - `quiet = true`.
- The return value of `Increment` is **ignored**: the model/amount pairs are appended before the credit, so the remote fires even if the credit failed.
- Fractional cash is already preserved end to end: the real test profile has `"Cash":2154397399.1093738` (`_profile_Player_140977250_before-pets.json`).

### Quiet flag (ServerStorage.DataService)
- `DataService.Increment(player, key, delta, quiet)` (152-156) = `Get` + `Set(player, key, current + (delta or 1), quiet)`; returns `false` when `Get` is nil (profile not loaded / key missing).
- `DataService.Set` (141-150): writes `profile.Data[key]`, mirrors `player.Data.<key>.Value` if a value object exists; `if key ~= "Playtime" and not quiet then DataService.RequestSave(player) end`. The value object's `Changed` hook (BuildValues 199-205) sees the profile already matching and does not request a save either.
- So quiet income rides the next save: ProfileStore autosave `AUTO_SAVE_PERIOD = 60` (line 55), any non-quiet Set / RequestSave (purchases, BaseSave snapshots), or `EndSession` on leave (251-255). A crash loses <= ~60 s of income.
- After `OnPlayerRemoving` -> `profile:EndSession()` + `Forget(player)`, `IsLoaded` is false and `Increment` returns false.

### `CucumberIncome` payload shape and receivers
- Server: `incomeRemote:FireAllClients(paidModels, paidAmounts)` - **two positional, parallel arrays**; `paidModels[i]` = a PlacedCucumber `Model` instance, `paidAmounts[i]` = number > 0 (cash actually credited for that model that tick). ALL clients, ALL owners' cucumbers in one event per tick. Fired only if at least one model paid.
- Only receiver in the place: `PlacedCucumberCardClient` lines 253-263:
```lua
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(INCOME_REMOTE, 60)
remote.OnClientEvent:Connect(function(models, amounts)
    if type(models) ~= "table" or type(amounts) ~= "table" then return end
    for i, model in ipairs(models) do
        local amount = tonumber(amounts[i])
        if typeof(model) == "Instance" and amount and amount > 0 and amount < math.huge then Popup(model, amount) end
    end
end)
```
  (grep: no other script references `CucumberIncome`.) Note `ipairs(models)`: a model not replicated to that client (StreamingEnabled; placed cucumbers live under the plot Part and stream with it) arrives as nil, and `ipairs` stops at the first nil, silently skipping later popups. Cosmetic only, but a new PetIncome receiver should iterate `for i = 1, #amounts`.

## 2. Rate computation

`StampRate(model)` (LeaderstatsService 47-51):
```lua
local rate = CucumberValues.RateOfInstance(model)
if model:GetAttribute(RATE_ATTRIBUTE) ~= rate then model:SetAttribute(RATE_ATTRIBUTE, rate) end
return rate
```
`CucumberValues.RateOfInstance(inst)` (80-82):
```lua
return CucumberValues.RateOf(inst:GetAttribute("Zone") or "Spawn", inst:GetAttribute("TypeName") or inst.Name,
    inst:GetAttribute("Golden") == true, inst:GetAttribute("Material"), inst:GetAttribute("Mutations"), inst:GetAttribute("SizeTier"))
```
`RateOf(zone, typeName, golden, material, mutations, size)` (73-77) = `max(0.01, ValueOf(...) / EARN_VALUE_PERIOD)`, then `+ FIRST_ZONE_BONUS` (0.5) when `TierOf(zone) == 1` (Spawn).
`ValueOf` (66-70) = `RewardOf(zone, typeName) * ZONE_VALUE_STEP ^ (TierOf(zone) - 1) * CucumberMutations.TotalMult(material, mutations, size)`; a bare `golden` flag with no material means `material = "Golden"`.
Constants (22-27): `ZONES = {"Spawn","Desert","Samurai","Farm","Snow","Underwater","Volcano","Narmek","Toyland","Neon"}`, `EARN_VALUE_PERIOD = 220`, `ZONE_VALUE_STEP = 8`, `GOLDEN_MULT = 12` (unused by the math; the material table is authoritative), `FIRST_ZONE_BONUS = 0.5`, `DEFAULT_REWARD = 8`. `RewardOf` (59-63): biome table, else `GENERIC[typeName]`, else 8. `TierOf` unknown zone -> 1.

`CucumberMutations.TotalMult(material, mutations, size)` (147-153) = `min(MaterialMultOf(material) * prod(MultOf(name) for name in Parse(mutations)), STACK_CAP=5000) * SizeMultOf(size)` - size is OUTSIDE the cap.
- Canonical mutation names (`M.MUTATIONS`, 36-45, in this order): `NEON` x15, `SHADOW` x15, `FROZEN` x20, `RADIOACTIVE` x25, `MOLTEN` x25, `ROYAL` x40, `VOID` x150, `PRISMATIC` x750.
- Materials (`M.MATERIALS`, 46-49): `Golden` x12 (Foil), `Diamond` x50 (Glass). Unknown/nil/"" material -> x1 (`MaterialMultOf`, 89-92).
- Sizes (`M.SIZES`, 65-69): `HUGE` x3, `MASSIVE` x6, `COLOSSAL` x12 (Scale 2/3/4).
- `M.Parse(str|table)` (94-104): splits on `[^,%s]+`, **drops unknown names, does NOT de-duplicate** (so "NEON,NEON" would multiply x15 twice). `M.Join(list)` (106-108) = `table.concat(Parse(list), ",")`. `M.Get(name)` (80-82) returns the row.
- `M.ApplyLook(model, material, mutations, opts)` (320-391), `opts.ParticleScale`: recolours every BasePart except ones named `Shadow`/`Hitbox`/`Handle` to the material colour (or the first mutation's colour when no material), adds `DiamondSparkle` + `DiamondLight` for Diamond, one `Mutation_<NAME>` emitter per mutation, a `MutationLight`; for PRISMATIC it sets attribute `PrismaticLoop` and starts a **per-model `task.spawn` loop** (`while model.Parent ... task.wait(0.15)`).

Worked example (the test profile, 2 saved cucumbers): Spawn "Cucumber Tree" = 360/220 + 0.5 = **2.136/s**; Snow "Frozen Tree" MASSIVE = 360 x 8^4 x 6 / 220 = **40,215.27/s**; CashPerSec = 40,217.4 -> leaderstat "40.2K".

## 3. When `Rate` is stamped / recomputed (signals)

Only LeaderstatsService writes `Rate` (grep: the only `SetAttribute(RATE_ATTRIBUTE...)` is line 49). Stamped:
1. Script start: `for _, model in ipairs(CollectionService:GetTagged(PLACED_TAG)) do StampRate(model) end` (156).
2. `CollectionService:GetInstanceAddedSignal(PLACED_TAG)` -> `StampRate(model)` + `RefreshAllIncome()` (157-160).
3. Lazily inside `EarningFor` when the attribute is missing/non-numeric (57).

**Never recomputed** on changes to `Zone` / `TypeName` / `Golden` / `Material` / `Mutations` / `SizeTier` / `Owner` of an already-tagged model (no attribute-changed hooks). Today that is safe only because every writer sets all attributes before tagging:
- `CucumberCarry.Place` sets Owner/CucumberName/Zone/TypeName/Golden/Material/Mutations/SizeTier/SizeScale/WeightKg/ShownKg (945-955) then `AddTag(taken, "PlacedCucumber")` (956, comment "attributes first: LeaderstatsService stamps Rate off this") then `taken.Parent = holder` (957).
- `CucumberCarry.RestorePlaced` (BaseSave restore): same attributes 1027-1037, `AddTag` 1038, parent 1039.
- `ZombieRaidService.RestoreCarry` (kill drop / raid over / "Saved"): `model:SetAttribute("StolenBy", nil)` 611, parent 612, `AddTag(model, PLACED_TAG)` 613 -> re-stamped.
- Tag-added signals fire only once the instance is inside the DataModel and are deferred, so the stamp happens after parenting.

Tag removals (income stops): `ZombieRaidService.Grab` (`RemoveTag` 533, then `StolenBy` 534, reparent to the zombie 561); `CucumberCarry.ClearPlaced` (1049 + Destroy; BaseSave leave/reset); `CucumberCarry.PickUp` (1108, then `Owner = nil` 1109, `Parent = nil` 1111) - **PickUp is reachable only through the Studio `CarryDev` "pickup" hook** (header 1068, gated by `RunService:IsStudio()` at 1192; dev loop 1221-1224). `Escape` destroys the carried (already untagged) model (770).
Not a removal: `CucumberMoveServer` only `PivotTo`s (101) + snapshot (108) - tag, instance and income untouched. The grapple pull (ZombieRaidService ~1026-1050) slides the still-tagged cucumber (it keeps earning) until `Grab`.
A stale `Rate` stays on a picked-up model (PickUp never clears it); a re-tag re-stamps it.

## 4. How `CashPerSec` is set (player.Data.CashPerSec)

- Created by LeaderstatsService `Setup` (129-134) as a `NumberValue` named `CashPerSec` under `player.Data` (DataService's folder). NOT in `DataService.TEMPLATE` (57-68) nor `VALUE_ORDER = {"Cash", "Playtime", "Strength"}` (69) -> no profile mirror/Changed hook -> **derived, never saved** (header line 7). Player children replicate, so every client can read it (none does).
- Written only by `RefreshIncome(player)` (74-80): `s.RawRate.Value = IncomeOf(player)` (sum of the same `EarningFor` set) and `s.Rate.Value = NumberAbbrev.Abbrev(income)`.
- `RefreshIncome` runs: in `Setup` (148); via `RefreshAllIncome()` (82-90, `task.defer`-coalesced, refreshes every player in `Stats`) on tag added (159), tag removed (161), and any plot's `Owner` attribute change (163-171, `workspace.Map.Lobby.Plots`).
- It is **not** refreshed per tick, nor on any Rate/attribute change. It is "the rate at the last tag/plot event".
- `DataService.ResetProfile` does not touch it (it only walks the `Values` map); the admin reset's plot clear re-triggers it via tag removal.

## 5. leaderstats values

`Setup(player)` (124-150), run from `DataService.OnProfileLoaded(function(player) Setup(player) end)` (153):
- `player.leaderstats` Folder with two **StringValues**: `Strength` = `NumberAbbrev.Abbrev(Data.Strength.Value)` (refreshed on `strengthValue.Changed`, 144-146) and `Cash/s` = `NumberAbbrev.Abbrev(income)` (no "$"). Folder parented last (149) so the playerlist shows both columns in order.
- `Players.PlayerRemoving` -> `Stats[player] = nil` (154).
- No script reads `leaderstats` / `Cash/s` (only the core playerlist).

## 6. EVERY reader of CashPerSec

| Reader | Line | Use |
|---|---|---|
| `ServerScriptService.LeaderstatsService` | 129-134, 78 | creator + only writer |
| `ServerScriptService.ZombieRaidService.IncomeOf(player)` | 268-272 | `player.Data.CashPerSec.Value` or 0 -> threat input |

That is all. No client script, shop, bench, gym, plot-upgrade, portal, index or HUD script reads `CashPerSec` (the HUD shows only `Data.Cash`). The "shop/progression readers" PLAN 7.8 warns about do not exist; shop/progression code reads the **balance** `Data.Cash` only (list in 8).

### ZombieRaidService threat path (the one consumer)
```lua
local function IncomeOf(player)                          -- 268-272
    local data = player:FindFirstChild("Data")
    local raw = data and data:FindFirstChild("CashPerSec")
    return raw and raw.Value or 0
end
local function ThreatOf(player, plot)                    -- 1315-1320
    local cucumbers = CucumbersOf(plot, player.UserId)   -- 256-266: plot.Placed children, tagged + Owner
    local income = IncomeOf(player)
    local score = ZombieCatalog.ThreatOf(cucumbers, income)
    return ZombieCatalog.LevelOf(score), score, #cucumbers
end
```
- `NewRaid(player, plot, forcedLevel, isDay)` (1322-1334) calls it for: night raids (`StartRaids` 1442; a raid only if `raid.Cucumbers > 0`, 1443), **daytime thieves** (`SpawnThief` 1548 -> `ThiefVariety(raid.Level)` 1550), and the Studio `ZombieDev "spawn:"` hook (1654). The level also goes to `plot:SetAttribute("ThreatLevel", level)` (1331; no reader anywhere) and `raid.Score`.
- `ZombieCatalog.ThreatOf(cucumbers, income)` (180-185) = sum of `CucumberThreat(entry)` + `INCOME_WEIGHT (4) * log10(1 + max(0, income))`. `CucumberThreat` (168-178) reads the cucumber attributes `Zone`, `Mutations` (token count), `Material`, `Golden`, `SizeTier` - **not `Rate`** - so buffing `Rate` cannot change the per-cucumber part; only the `income` argument leaks economy into threat.
- `LevelOf(score)` (187-190) = `clamp(1 + floor(3.2 * log10(1 + score/2)), 1, 10)`.
- Test profile: cucumber threat 1 + 5^1.6 x 1.7 = 23.3; income term 4 x log10(40,218) = 18.4; score 41.7 -> level 5. A late pet team (e.g. +15.7M/s Cosmo Cat) would raise the income term to ~28.8 (+10 score) - small per log step, but real, so isolation is required.

## 7. EVERY reader of the `Rate` attribute

| Reader | Line | Use |
|---|---|---|
| `LeaderstatsService.EarningFor` | 57 | **payment amount** + CashPerSec sum (trusts the attribute) |
| `PlacedCucumberCardClient.RateText` | 109 | card text `"$" .. NumberAbbrev.Abbrev(rate) .. "/s"`, fallback `CucumberValues.RateOfInstance(model)` |
| `PlacedCucumberCardClient` Build | 168 | `model:GetAttributeChangedSignal("Rate")` -> re-render the cash line |

Nothing else (BaseSaveService does not save `Rate`, its cucumber record is `{Zone, Type, Golden, Material, Mutations, SizeTier, Name, Pivot, Box, Size}` 107-113; other `.Rate` hits are ParticleEmitter/Trail properties and CucumberLiftClient's rig table). `BaseRate` does not exist yet.

## 8. Other Cash readers/writers (unchanged by the refactor, listed for completeness)

Writers (`DataService.Increment/Set` on "Cash", all non-quiet): BuildService 529 (charge) / 580 (sell refund); EggShop 340-344; HeadbandService 208-214 (buy) / 551 (dev); PlotUpgradeService 281-285; ShopProductsServer 30-31 (dev products, also Strength); GymService 203-204 (Strength 182); AdminService 119 (`SetValue(player, "Cash", value)` -> `DataService.Set`) and ResetData 79-108 (ResetProfile).
Client readers of `player.Data.Cash` (all re-render on EVERY `Changed`, i.e. every income tick): HUDClient `Bind("Cash", cashLabel)` 152 (text + `Pop(label)`), BenchBoardClient 185-187 (`RenderAll`), PlotUpgradeClient 160-162 (`RenderAll`), BuildMenuClient `Cash()` 154-156 / 882, EggShopClient 23-25, GymBoardsClient 44 (`state.Cash` from the GymBoardState push).
Legacy: the real profile still carries an unused `Coins` key (not in TEMPLATE, not in REMOVED_KEYS, read by nothing) - never read or revive it.

## 9. HUDClient cash display (StarterGui.CucumberHUDDesign.HUDClient)

- `Counters.CashValue` (TextLabel, `_gui_tree.txt:139`, with `UIStroke TextOutline` + `UIScale PopScale`) and `Counters.CashIcon` (ImageLabel `rbxassetid://15402858705`, 138). No Cash/s element exists in the HUD.
- `Bind("Cash", cashLabel)` (130-152): `label.Text = Compact(value.Value)`; on `Changed` -> new text + `Pop(label)` (Heartbeat-stepped `ButtonFX.Animate(0.28, Back, Out)` scaling PopScale 1.18 -> 1, 58-69).
- `Compact(n)` (41-54): below 1000 `math.floor(n)` (fractions hidden: $0.50/s shows as +1 every 2 s); from 1000 up one FLOORED decimal + `NumberAbbrev.SUFFIXES` ("200.1M").
- Every Cash write = one Pop. Two Increments per tick would pop twice; keep one Cash change per owner per tick.

## 10. PlacedCucumberCardClient card layout (reuse recipe for buff badges / PetCardClient)

Constants (33-52):
```lua
local TAG = "PlacedCucumber"; local INCOME_REMOTE = "CucumberIncome"; local FONT = Enum.Font.FredokaOne
local CARD_W, CARD_H = 6, 2.64 -- studs (scale = studs on a BillboardGui)
local BIOME_FRAC, NAME_FRAC, RATE_FRAC = 0.30, 0.37, 0.33
local GAP_ABOVE = 0.8; local MAX_DISTANCE = 60
local CASH_GREEN = Color3.fromRGB(65, 235, 20); local CASH_STROKE = Color3.fromRGB(12, 12, 12)
local WHITE = Color3.fromRGB(255, 255, 255); local DARK_STROKE = Color3.fromRGB(25, 20, 35); local STROKE = 2.4
local POPUP_W, POPUP_H = 4.4, 1.05; local POPUP_RISE = 2.6; local POPUP_TIME = 1.0; local POPUP_POP = 0.16
local POPUP_FADE_FROM = 0.5; local POPUP_MAX_DISTANCE = 70
```
State: `Cards = {}` `[model] = {Gui, Conns, Adornee, Top, Grow, HalfUp}` (54); `animations = {}` list of step closures (55).

Card (`Build`, 118-172):
- Reserves `Cards[model] = card` synchronously, then `task.spawn`: `model:WaitForChild("PlotHitbox", 5)`; bails if `Cards[model] ~= card` or the model left the workspace (race guard).
- Adornee = `PlotHitbox` (halfUp = `hitbox.Size.Y * 0.5`) else PrimaryPart / first BasePart with halfUp from `model:GetBoundingBox()`.
- `BillboardGui` "CucumberCard": `grow = sqrt(max(SizeScale or 1, 1))`; `Size = UDim2.fromScale(6*grow, 2.64*grow)` (studs); `StudsOffsetWorldSpace = (0, halfUp + GAP_ABOVE*grow + cardH*0.5, 0)` (billboard is centred, so lift by half its height); `AlwaysOnTop = false`; `MaxDistance = 60 + halfUp*2`; `LightInfluence = 0`; parented to the adornee (a local instance).
- Vertical `UIListLayout` (centre, LayoutOrder). Rows: `Line(gui, zone, 0.30, ZoneTextColors...)` "Biome" (1); `Line(..., NameText, 0.37, WHITE, DARK_STROKE, 2)` "CucumberName", `RichText = true` (`CucumberMutations.ColorizeName(CucumberName)`); `CashLine(gui, 0.33, 3)` row "CashLine" (horizontal UIListLayout, centred) holding TextLabel **"Rate"** (`AutomaticSize = X`, `Size = fromScale(0, 1)`, `TextScaled`, CASH_GREEN, UIStroke CASH_STROKE 2.4).
- `Line(parent, text, frac, color, strokeColor, order)` (57-72): TextLabel `Size = fromScale(1, frac)`, FredokaOne, `TextScaled`, UIStroke `Thickness = 2.4`. No pixel sizes anywhere.
- `card.Top = halfUp + GAP_ABOVE*grow + cardH` (studs above the adornee centre) = where popups start.
- Live update: `model:GetAttributeChangedSignal("Rate")` -> `rateLabel.Text = RateText(model)` (168-170).
- `Remove(model)` (174-180): disconnect `Conns`, destroy `Gui`. Wiring 265-267: build for `GetTagged`, `GetInstanceAddedSignal(TAG):Connect(Build)`, `GetInstanceRemovedSignal(TAG):Connect(Remove)` (streaming the plot out removes the tag on that client -> card removed; stream-in rebuilds).

Income popup (`Popup(model, amount)`, 183-239):
- Needs `Cards[model].Adornee` alive and `card.Top`; skipped if camera distance to the adornee `> POPUP_MAX_DISTANCE + HalfUp*2` (creation-time check only).
- `BillboardGui` "IncomePopup": Adornee = card adornee, `Size = fromScale(4.4*grow, 1.05*grow)`, `AlwaysOnTop = false`, `LightInfluence = 0`, `MaxDistance = card.Gui.MaxDistance`, start `StudsOffsetWorldSpace = (0, card.Top + h*0.5, 0)` (bottom edge on the card's top edge).
- Inner Frame (anchor 0.5, full size) + `UIScale` starting 0.3 + `CashLine(frame, 1, 1)` label "Amount", text `"+$" .. NumberAbbrev.Abbrev(amount)`.
- Step closure (215-238): life `POPUP_TIME` 1.0 s; rise `POPUP_RISE*grow` with quad-out `1-(1-k)^2`; scale pop 0.3 -> 1.12 at 70 % of 0.16 s -> 1.0; `TextTransparency`/stroke `Transparency` fade from k = 0.5 to 1; destroys itself when done or when the adornee/gui lose their parent.
Shared stepper (241-251): ONE `RunService.Heartbeat` connection, early-out when `#animations == 0`, `now = os.clock()`, iterate backwards, swap-remove finished closures. Heartbeat (not RenderStepped) so it runs in an unfocused Studio.
Culling summary: cards = `BillboardGui.MaxDistance` only (no per-frame loop); popups = creation-time camera distance only; **no global popup cap** (PLAN 12 wants ~32/client); no offscreen check.

Reuse guidance:
- Buff badges: to keep the existing text sizes, grow the card instead of re-splitting it: add a 4th row (LayoutOrder 4, under the cash line) and set `CARD_H' = 2.64 + badgeH` with each existing frac scaled by `2.64 / CARD_H'`, or add a separate small BillboardGui. If badges go ABOVE the card, move `card.Top` up by the badge height or popups will start on top of the badges. Countdown text: update at 0.2-0.25 s (HUDClient's `TIMER_STEP` accumulator pattern) from a replicated absolute expiry vs `workspace:GetServerTimeNow()`, not every frame.
- PetCardClient: same `Line`/`CashLine`/`Popup` recipe and constants; adornee = the pet's `PrimaryPart` (PetRoamClient `PivotTo`s the anchored model locally, so a billboard parented to the root follows it); halfUp from the model bounding box at build time (pets are capped to `PET_FIT`); tag `PlotPet`, folder `plot.Pets`. Pet attributes available today: `PetName`, `DisplayName`, `Rarity`, `Owner`, `OwnerName`, `Plot`, `Roam*` (PetHatchService 226-237). Rate text `"$" .. NumberAbbrev.Abbrev(rate) .. "/s"` ("$0.5/s": NumberAbbrev trims trailing zeros, max 2 decimals below 1000).
- Both clients each own one Heartbeat stepper; if a shared popup cap is wanted, extract the CashLine/Popup/stepper into one ReplicatedStorage module used by both rather than letting two scripts each cap at 32.

## 11. Contradictions / corrections to PLAN.md section 2 (and related section 7 claims)

1. **"Data.CashPerSec = TotalCashPerSec -- existing HUD/player list" (PLAN 7):** the HUD does not display cash/sec at all (HUDClient binds only `Strength` and `Cash`). The per-second number is shown only by the playerlist StringValue `leaderstats["Cash/s"]` (NumberAbbrev, no "$"); `Data.CashPerSec` itself is read only by ZombieRaidService.
2. **LeaderstatsService row "Calculates cucumber rates ... sets Data.CashPerSec":** true, but rates are stamped once per tag-add (never recomputed on attribute changes), payment trusts the `Rate` attribute, and CashPerSec is refreshed only on tag add/remove, plot Owner change and profile load - not per tick. CashPerSec is created by LeaderstatsService, not DataService, and is never saved.
3. **"Emit the existing CucumberIncome(models, amounts) with actual paid amounts" (PLAN 7.6):** today's amounts are nominal `Rate x 1` regardless of real elapsed time; the event goes to **all clients** (every owner's cucumbers in one batch); and it fires even if `Increment` failed (return value ignored). The remote is created at run time by LeaderstatsService (not authored), so the new owner of the loop must create it.
4. **"do not silently reinterpret unrelated shop/progression readers" (PLAN 7.8):** there are none - the only CashPerSec reader is `ZombieRaidService.IncomeOf`. Its consumers are night raids, **daytime thieves** (`SpawnThief` -> `ThiefVariety(raid.Level)`) and the dev spawn hook; the new threat source affects thieves too.
5. **Income eligibility is looser than PLAN 4.3's buff eligibility:** a cucumber dropped by a killed carrier stands in the LOBBY (still tagged, still `Owner`, still parented to `plot.Placed`, `raid.Dropped` is internal and there is no attribute marking it) and keeps earning until `ReturnDropped`; a grappled cucumber keeps earning during the pull. "Under the owner's current plot" is only true hierarchically for these.
6. **"Pickup ... clears its pet buffs" (PLAN 4.3 / 9):** plot -> shoulder pickup (`CucumberCarry.PickUp`) is Studio-dev-hook-only; the player-facing exits from income are zombie `Grab` (ordinary + grapple final), `ClearPlaced` (leave / admin reset) and destruction. Moving (`CucumberMoveServer`) never touches the tag.
7. **CucumberMutations row (x12 / x50 / 5,000 cap before size):** accurate. But `Parse` does not de-duplicate, so pet code must dedupe mutation names itself (PLAN 3.3 "distinct"); ZombieCatalog's `mutationCount` counts raw tokens (unknown and duplicate names included), unlike `Parse`.
8. **CucumberValues row:** accurate; add the details the income layer must not duplicate: `/220`, `max(0.01, ...)`, `+0.5` flat in Spawn, unknown type -> GENERIC -> 8, unknown zone -> tier 1.
9. **PLAN 7.1 "Preserve fractional cash":** already true (profile Cash is fractional); the gap is only elapsed-time accuracy and per-state-change settlement, not rounding.

## 12. Recommendation: `ServerStorage.IncomeService` (ModuleScript)

Goal: one ledger that pays cucumbers + pets on one cadence, keeps `Rate` as the effective displayed number, keeps `CucumberIncome(models, amounts)` byte-compatible, and isolates raid threat.

```lua
-- lifecycle (RULES: Init(deps) + Start(), no side effects at require)
IncomeService.Init({DataService = DataService, Clock = function() return workspace:GetServerTimeNow() end})
IncomeService.Start()                       -- idempotent (DataService.Start style guard): creates/finds Remotes.CucumberIncome
                                            -- (+ PetIncome), wires the PlacedCucumber tag, starts the ONE scheduler
-- cucumber producers (auto from the tag; explicit hooks for the rest)
IncomeService.Refresh(model)                -- settle, recompute BaseRate from CucumberValues.RateOfInstance, restamp
IncomeService.SetCucumberModifiers(model, list, now?)  -- PetBuffService: {{Kind, Mult, ExpiresAt}}; settles first
IncomeService.GetCucumberRates(model) -> effective, base
-- pet producers (PetService only; register AFTER a successful spawn)
IncomeService.SetPetProducer(player, petId, model, ratePerSec, now?)  -- add or change; settles first
IncomeService.RemovePetProducer(petId, now?)                         -- unequip / despawn / unavailable; settles first
-- settlement / lifecycle
IncomeService.SettleOwner(player, now?)     -- into the owner's pending ledger (no profile write, no event)
IncomeService.FlushOwner(player)            -- pre-close hook: settle + Increment now, no popups; returns ok
-- totals (all derived, unsaved)
IncomeService.GetTotals(player) -> {CucumberBase = n, Cucumber = n, Pet = n, Total = n}
IncomeService.GetThreatIncome(player) -> CucumberBase
IncomeService.TotalsChanged                 -- BindableEvent/Signal (player, totals): LeaderstatsService + PetState footer
-- tests (Studio / admin only): IncomeService._Step(now) runs one settlement pass with an injected clock, no loop
```
Internals:
- Registry: `Producers[key] = {Kind = "Cucumber"|"Pet", OwnerId, Model, PetId, BaseRate, Mods, Rate, LastSettled}`, `ByOwner[userId] = {[key] = true}`. Cache `OwnerId` at registration - with Deferred signals `PickUp` has already cleared `Owner` by the time the removed handler runs.
- Cucumber registration: `GetInstanceAddedSignal("PlacedCucumber")` -> register (BaseRate = `CucumberValues.RateOfInstance(model)`, LastSettled = now), connect `GetAttributeChangedSignal` for `Owner`, `Zone`, `TypeName`, `Golden`, `Material`, `Mutations`, `SizeTier` -> `Refresh`; `GetInstanceRemovedSignal` -> settle to now with the cached owner, drop. Connect the signals before the initial `GetTagged` sweep and make registration idempotent. Keep today's eligibility (tag + Owner + in workspace) so CucumberBase equals today's CashPerSec exactly; buff targeting uses its own stricter rule.
- Attributes it owns on cucumbers: `Rate` = effective (BaseRate x min(2.0, product of live modifier mults)) and new `BaseRate`. It is the ONLY writer of both; it never reads `Rate` back as an input (pay from the cached producer, not the attribute).
- Scheduler: one loop with a deadline (`nextTick += 1`, not `task.wait(1)` drift); per producer elapsed `= min(now - LastSettled, 5)` (+ a diagnostic counter when clamped), split at every modifier `ExpiresAt` inside the interval; per-owner sum -> **one** `DataService.Increment(player, "Cash", total, true)`; only if it returns true append that owner's cucumber models/amounts to the CucumberIncome batch and pet models/amounts to the PetIncome batch.
- State-change settlement (buff add/expire, equip/unequip, steal, removal, re-rate) goes into a per-owner pending ledger that the next tick flushes with its one Increment (one HUD pop per tick); a removed model keeps its cash but its popup share is dropped. `FlushOwner` (pre-close) credits immediately.
- Emission, unchanged contract: `CucumberIncome:FireAllClients(models, amounts)` - parallel arrays, PlacedCucumber Models, amounts > 0 finite, only credited amounts, once per tick. Do NOT fire extra CucumberIncome events for mid-second settlements (overlapping 1 s popups). PetIncome: same `(models, amounts)` shape with PlotPet models (or add a 3rd `petIds` array), fired from the same pass.
- Totals: recompute per owner on registry change (deferred-coalesced like `RefreshAllIncome`) and on each modifier expiry; write `player.Data.CashPerSec` (Total; create it if missing, unsaved) and fire `TotalsChanged`.
- Validate every rate/amount finite and >= 0 (`x == x and x ~= math.huge and x ~= -math.huge`), skip + count otherwise.

Patches this implies:
- **LeaderstatsService:** keep `Setup` (leaderstats Folder, `Strength`, `Cash/s`) and the Strength refresh; delete `StampRate`/`EarningFor`/`IncomeOf`/`RefreshIncome`/`RefreshAllIncome`/`PayIncome`, the loop (115-121), the remote creation (39-44) and the tag/plot wiring (156-171); require IncomeService and set `Cash/s` from `TotalsChanged` / `GetTotals(player).Total`. Start IncomeService from exactly one place (LeaderstatsService or PetServer), guarded against double start.
- **ZombieRaidService.IncomeOf** (268-272): `return IncomeService.GetThreatIncome(player)` (unboosted cucumber income, pets and buffs excluded). Keep the function name/signature so `ThreatOf`/`NewRaid`/`SpawnThief` are untouched.
- **PlacedCucumberCardClient:** no change needed for income (still reads `Rate`, still handles `CucumberIncome`); only the badge row is new.
- Stage order: the old `PayIncome` loop must be removed in the same change that starts IncomeService, and IncomeService must land before PetBuffService writes a boosted `Rate` (the old loop pays whatever `Rate` says).
