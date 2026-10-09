# Research: world lifecycle + misc services (2026-09-22)

Source: the local snapshot `new-map-cucumber-game/live-2026-09-22/` (file names below are snapshot
files; `L123` = line in that file). Nothing was read from Studio for this note.

---

## 0. Key numbers at a glance

| Thing | Value | Where |
|---|---|---|
| Day length | **180 s** (script attribute `DayDurationSeconds` on `ServerScriptService.DayNightCycle`) | `_structure.txt` L593 / L662 |
| Night length | **45 s** (script attribute `NightDurationSeconds`) | `_structure.txt` L593 / L662 |
| Full cycle | **225 s** (180 + 45) | computed |
| Leaf Shield (`Guard`) duration | **min(600, 225 + 15) = 240 s** | PLAN §4.1 formula; matches PLAN's "240 seconds" |
| Code fallback if the attributes vanish | Day 180, **Night 10** (not 45) | `DayNightCycle` L56-57, `EggShop` L68 |
| Shared calendar epoch | `CYCLE_EPOCH = 1788652800` (2026-09-06 00:00 UTC) | `DayNightCycle` L45, `EggShop` L67 |
| Night barrier travel | `travel = math.min(1, NightSeconds * .25)` = 1 s | `DayNightCycle` L305 |
| Portal close before night | 60 s (`BLOCK_BEFORE_NIGHT`), warning at 30 s, trip home starts 2 s early | `PortalService` L38-40 |
| Day-thief quiet window before night | 20 s (`DAY_THIEF_NIGHT_GUARD`) | `ZombieRaidService` L123 |
| Build heal time | 0.8 x DayDurationSeconds = 144 s from 0 to full | `BuildHealthService` L46, L76-80 |
| Slow Mode walk speed | **25** (was 16) | `StrengthProgressionServer` L25-26 |
| Admin | UserId `140977250` only | `AdminService` L26, `AdminPanelClient` L15 |
| StreamingEnabled | `true` | `_structure.txt` L677 |

---

## 1. `ServerScriptService.DayNightCycle` (`ServerScriptService.DayNightCycle.server.lua`, 336 lines)

### 1.1 Script attributes (config, server-only: SSS does not replicate)
Live values (`_structure.txt` L593): `DayClockEnd=16, DayClockStart=11, DayDurationSeconds=180,
NightAmbient=rgb(60,66,98), NightBrightness=1, NightClockTime=0, NightDurationSeconds=45,
NightOutdoorAmbient=rgb(78,85,122)`.

Read through `seconds(attribute, default)` (L49-52):
```lua
local value = script:GetAttribute(attribute)
return typeof(value) == "number" and math.max(1, value) or default
```
`schedule(now)` (L55-69) calls `seconds("DayDurationSeconds", 180)` and `seconds("NightDurationSeconds", 10)`
on EVERY loop iteration, so an attribute edit takes effect at the next cycle boundary and
"renumbers the days everywhere at once" (header L5-6).

Stale comments (do not trust): header L5 "nights NightDurationSeconds (10)", L238 "(10 s) night".
ZombieRaidService L46 has the correct note ("NightDurationSeconds on DayNightCycle is 45 (2026-09-11; was 10, then 90)").
The old backup copies under `ServerStorage.__CollectAnimBackup_2026_09_06.DayNightCycle` (Night 5) and
`__CarryAndEggLabelsBackup.DayNightCycle` (Night 10) carry OLD attributes - never read those (`_structure.txt` L222, L249).

### 1.2 Workspace attributes it writes (replicated; the only cycle data clients can see)

| Attribute | Type | Written | Notes |
|---|---|---|---|
| `CyclePhase` | string | L217 (`setPhase`), L249 (`"PreparingDay"`) | values: nil (boot), `"PreparingDay"`, `"Day"`, `"Night"` |
| `IsNight` | bool | L218, L250 | |
| `PhaseStartedAt` | number (server time) | L219 | |
| `PhaseEndsAt` | number (server time) | L220; also L270 (forced night sets it to `now` while phase is still "Day") | |
| `DayNumber` | number | L259 (only in `runDay`) | nil on a server that booted mid-night until the first dawn |
| `DayDurationSeconds` | number | L260 (only in `runDay`) | mirror of the clamped value in use |
| `NightDurationSeconds` | number | L261 (only in `runDay`) | mirror; nil until the first dawn on a mid-night boot |
| `LobbyReturnCFrame` | CFrame | L152 (`refreshLobbyReturn`, called L154 and at every night L284) | PortalService/PlotService use it |

Also: `NightBarrier` attrs `LoweredPivot` / `RaisedPivot` (L117-118); player attr `BiomeIndex = 1` on a
night return (L182). Lighting ClockTime/Brightness/Ambient are driven here (L239-245, L253-256, L295-304).

`setPhase` order (L216-221): `CyclePhase` -> `IsNight` -> `PhaseStartedAt` -> `PhaseEndsAt`. A
`CyclePhase` changed-handler that reads `PhaseEndsAt` synchronously can see the PREVIOUS phase's end
time under immediate signal behaviour (the place's `Workspace.SignalBehavior` is not in the snapshot).
Read `PhaseEndsAt` lazily / in a `task.defer`, or also listen to `PhaseEndsAt`.

### 1.3 Phase sequence
Boot: waits `Map.Lobby.LayoutReady` (L47), `ServerStorage.CucumberSpawnerAPI` (+ `BeginDay`, `BeginNight`)
(L22-24) and `CucumberCarryAPI.DropForNight` (L25) before the first phase is set, so `CyclePhase` is nil for
the first moments of a server.

Main loop (L327-336): `s = pending or schedule(now)`; `runDay(s)` only if `now < s.NightStart`, then
`runNight(s)`.
- `runDay` (L248-278): `CyclePhase="PreparingDay"` + `IsNight=false` (L249-250) -> `beginDay:Invoke(s.Day)` (pcall, L257;
  this reseeds the wild cucumbers and can take a while) -> `DayNumber`/`DayDurationSeconds`/`NightDurationSeconds`
  (L259-261) -> `setPhase("Day", DayStart, NightStart)` (L262) -> 0.1 s loop until `NightStart` or a forced night.
- `runNight` (L281-325): `setPhase("Night", NightStart, NextDayStart)` (L283) -> players in the biome lane are
  returned (L286-290, `returnPlayer` L156-183 calls `CucumberCarryAPI.DropForNight` first) -> `beginNight:Invoke()`
  (L291) -> barrier up over `travel` s -> `nightWait(NextDayStart - travel)` (keeps returning lane intruders
  every 0.1 s, L224-233) -> barrier down -> `nightWait(NextDayStart)`.
- A server booted mid-night skips `runDay`: `CyclePhase` goes nil -> `"Night"` directly, and `DayNumber`,
  `DayDurationSeconds`, `NightDurationSeconds` stay nil until the next dawn.

So "daytime" has TWO non-night values. `CyclePhase == "Day"` excludes `PreparingDay`; `CyclePhase ~= "Night"`
includes it (and nil). Existing readers use both styles (see 1.5). ZombieRaidService `OnPhase` (L1606-1615)
ends raids on ANY non-"Night" value (`EndAll("Dawn")`, i.e. already at `PreparingDay`).

### 1.4 `ServerStorage.DayNightAPI` (admin force)
L27-43: Folder `DayNightAPI` + BindableEvent `Force`; `Force:Fire("Night" | "Day")`.
- Forced night (L266-272): `NightStart = now`, `NextDayStart = now + NightSeconds`, `PhaseEndsAt = now` (still "Day"), then a full night.
- Forced day (L314-319, L332-335): the wall lowers over `travel`, then a `pending` schedule = a FULL day from now,
  off the shared clock; the shared calendar resumes at the next `schedule()` call. During the forced-day
  lowering `PhaseEndsAt` is NOT updated (it keeps the original night end).
- Attributes are never changed by a force, so a cycle-length read stays 225 s.
- Only caller: `AdminService.ForcePhase` (L60-69).

### 1.5 Every reader of the cycle attributes (grep, snapshot)
Server:
- `AdminService` L61-67 (`DayNightAPI`, `CyclePhase`).
- `BuildHealthService` L60 (`cycleScript = ServerScriptService:FindFirstChild("DayNightCycle")`), L76-80 (`HealSeconds`:
  script attr, else workspace attr, else 180), L293 (heal only when `CyclePhase == "Day"`), L310-319 (full heal on "Night").
- `BuildPromptServer` L84 and `CucumberMoveServer` L62: refuse at `CyclePhase == "Night"` ("You can't build at night").
- `CucumberCarry` L538, L582, L716 (`~= "Day"` refusals), L814 (`PhaseEndsAt` Debris lifetime).
- `EggShop` L143-147 (`CurrentDay`: `DayNumber`, else script attrs with fallbacks 180 / **10**), L414 (`DayNumber` changed -> restock).
- `GuardianService` L823, L1076, L1229-1239 (heat reset on "Day", sleep on "Night").
- `PlotService` L134-137 (respawn at `LobbyReturnCFrame` at night).
- `ZombieRaidService` L1564-1568 (`SecondsToNight` from `PhaseEndsAt`), L1574 (thieves only when `"Day"`), L1606-1615 (`OnPhase`).
- `CucumberAdventure` L145-146; `PortalService` L47-67, L174.
Client: `HUDClient` L160-182 (night timer; shows "dawn..." for `PreparingDay`, "soon" for nil), `BuildMenuClient`
L1137, L1202-1203, `CucumberAdventureClient` L39-41, `PortalHudClient` L146-149.

### 1.6 Cycle length for the Guard shield (PLAN §4.1)
- Live: 180 + 45 = **225 s**; Guard = `math.min(600, 225 + 15)` = **240 s**.
- Server-side read order that matches existing precedent (`BuildHealthService` L76-79, `EggShop` L145-147) AND the
  clamp the cycle itself uses:
```lua
local cycleScript = game:GetService("ServerScriptService"):FindFirstChild("DayNightCycle")
local function CycleSeconds(name, default)
	local v = cycleScript and cycleScript:GetAttribute(name)
	if typeof(v) ~= "number" then v = workspace:GetAttribute(name) end
	if typeof(v) ~= "number" or v ~= v or v == math.huge then return default end
	return math.max(1, v)
end
local cycle = CycleSeconds("DayDurationSeconds", 180) + CycleSeconds("NightDurationSeconds", 10) -- 10 = DayNightCycle's own fallback
local guardSeconds = math.min(600, cycle + 15)
```
  (If a design prefers 45 as the night fallback, note it then disagrees with the running cycle's own fallback.)
- Clients cannot read the script attributes (SSS is server-only). A client must use the server-sent absolute
  `ExpiresAt`, not recompute; the workspace mirrors are nil on a mid-night boot until dawn.
- Absolute times: every existing expiry uses `workspace:GetServerTimeNow()` (EggPlacement `HatchAt` compared in
  `PetHatchService` L337-338; `Data.PortalCooldowns` saved as server time, `PortalService` L95-104, L107-118;
  `SpeedBoostUntil`, `StrengthProgressionServer` L27-30). Use the same clock for `ExpiresAt` so client countdowns
  compare against `workspace:GetServerTimeNow()` directly.

---

## 2. Portals: `PortalLoader` -> `ServerStorage.PortalService`

### 2.1 Bootstrap
`ServerScriptService.PortalLoader.server.lua` is ONE line with no header or newline:
`require(game:GetService("ServerStorage"):WaitForChild("PortalService")).Start()`.
`PortalService.Start()` (L417-482) is idempotent (`started` flag L27, L418-419). It creates:
- `workspace.PortalInstances` (Folder, L420-422) - live per-player map clones.
- `ReplicatedStorage.MinigameHudRemotes` (Folder, L423-429; NOT under `Remotes`) with attributes
  `BlockBeforeNight` / `WarnBeforeNight` / `ReturnLead`; children `GoHome` (RE, L432-434),
  `StateChanged` (RE, L435-437), `Transition` + `TransitionReady` (RE, `PortalTransitionService.Start` L8-20),
  `DesertFire` + `DesertShot` (RE, `DesertHuntService.Start` L179-185).
- Hooks every portal model under `workspace.Map.Biomes` with a `PortalDestination` attribute in `definitions`
  (L16-22: `StarterObby`, `DesertHunt`, `SnowAvalanche`, `LavaRun`, `VoidBloxout`), adds an invisible
  `PortalEntryTrigger` part and a `PortalSign` anchor (tag `PortalSign`, L131-146, L365-388).

### 2.2 How a player enters (`PortalService.Enter`, L288-363)
Touch of `PortalEntryTrigger` (L383-387) or the 0.1 s Heartbeat proximity check (L470-476). Refusals in order:
night rules (`ClosedReason`, L62-67), per-portal cooldown (`PortalReadyAt_<key>`, 1 h), `StrengthRequired`.
Then the template is cloned from `ServerStorage.PortalMaps`, `ModelStreamingMode = PersistentPerPlayer` (L325),
`map:AddPersistentPlayer(player)` (L342), pivoted to `Vector3.new((slot - 1) * 5000, 2000, 10000)` (L330),
parented to `workspace.PortalInstances` as `<Template>_<UserId>` (L324), scripts stripped (L333-336),
and the player is iris-teleported (`PortalTransitionService.Teleport`, L343).

### 2.3 How to tell a player is in a portal run (server or client)
There is NO public query function; `sessions` is module-private (L24). Use player attributes:

| Player attribute | Meaning | Set / cleared |
|---|---|---|
| `InPortalMinigame` | `true` only once the teleport into the map has finished | set true L349; set **false** (not nil) in `clearSession` L187; nil before a first run |
| `PortalTransitioning` | `true` during an iris transition (in or out; root is anchored) | `PortalTransitionService` L30 / L49 (nil) |
| `MinigameKey` / `MinigameName` / `MinigameRunStart` | destination key / title / server-time start | L346-348; cleared L188-190 |
| `PortalPendingHome` | a failed trip home will be retried on respawn | L208, L409-411 |
| `PortalReadyAt_<destination>` | cooldown end (server time) | L97, L113 |

Recommended test: `player:GetAttribute("InPortalMinigame") == true or player:GetAttribute("PortalTransitioning") == true`.
Between the session reservation (L318, `Busy = true`) and L349 neither attribute is true yet (the entry
transition sets only `PortalTransitioning`).

### 2.4 Night rules and lifecycle
- `nightReturnDue()` (L55-59): `CyclePhase == "Night"` or `<= RETURN_LEAD` (2 s) of day left -> Heartbeat
  (L449-480) sends every session home (`ReturnHome(player, "Night")`), so nobody is in a portal at night.
- `ReturnHome` (L200-215) teleports to `homeCFrame()` = `LobbyReturnCFrame + (0,1,0)` (L173-182), sets `BiomeIndex = 1`.
- Respawn during a run (L390-415): back to the map spawn, or ends the run if the night return is due.
- `PlayerRemoving` (L442-446) -> `clearSession` (destroys the map clone).

### 2.5 Consequences for pets
- Pets never follow the player anywhere (PetRoamClient header L14; PetHatchService L17-24 roams the plot only),
  so "do not follow into portals" needs no code. Nothing in PortalService touches plots, pets or income.
- ZombieRaidService does NOT check portal state: day thieves still walk to a portal-goer's base
  (`SpawnThief` L1544-1562, candidate loop L1576-1581). Pets defending the plot while the owner is away is
  consistent with PLAN §1.
- While in a portal the owner's character is ~10 000 studs away at Y 2000, so the owner's own plot, pets and
  cucumbers are streamed OUT on their client: pet world cards/popups/effects for the owner will not render and
  `Instance` references in remote payloads arrive as nil for them. A pet-proc owner toast still works (Notify is
  screen UI) - decide whether to suppress it while `InPortalMinigame == true`.

---

## 3. `ServerScriptService.GuardianService` - guardians must never be pet targets

- Live guardians: `workspace.Guardians` (Folder, `GuardianCatalog.FOLDER = "Guardians"`, catalog L15; created in
  `Spawn` L447-452). One per biome, cloned from `ServerStorage.Assets.Guardians/<name>` (L433-435).
- They are R15 Humanoid rigs (`hum.RigType = R15`, L495), unanchored, every part in collision group
  `"Guardians"` (L461, L467-469, L480). Seat props `<name>_Seat` sit in the same folder (L474-485).
- Identify by model attributes `Guardian = <name>`, `Zone`, `State` (L527-529; `"Asleep"`, `"Waking"`,
  `"Chasing"`, `"Resting"`, `"Lurking"`, `"Reclaiming"`, ...), `Awake` (L330), `BaseHipHeight` (L499),
  `Behaviour` (L772), `Reason` (L710). They carry **no CollectionService tag** and no `Zombie`/`Owner` attributes.
- `ServerStorage.GuardianAPI` (L1204-1222): `Guardians:Invoke()` -> awake guardian models;
  `Damage:Invoke(...)` -> always `false` (`DamageGuardian` L1064-1066, stun system retired 2026-09-18).
  The Bat ignores guardians (`BatServer` L31-32).
- They are NOT in `ZombieAPI.Zombies()` (ZombieRaidService only lists its own `Zombies` registry, L877-883),
  and `ZombieAPI.IsZombie(guardian)` is false (L884-887).
- Guardians sleep at night (L1233-1238) and break off a chase at the lobby walls (header L18-20), so they
  should never be inside plot range - but range is not the guarantee; the source list is.

Rule for PetCombatService: candidates come ONLY from `ServerStorage.ZombieAPI.Zombies:Invoke()`, filtered by
`model:GetAttribute("Owner") == ownerUserId`. Never build a candidate list from Humanoids, spatial queries
(`GetPartBoundsInRadius`), `workspace.Guardians`, or the `Guardians` collision group.
Other non-target Humanoids: the Desert Hunt "Rat" enemies inside portal maps (`ServerStorage.PortalHuntAssets.Rat`,
`DesertHuntService`) and player characters.

Collision groups registered in this place: `"NightBarrier"` + `"Guardians"` (not collidable with each other;
`DayNightCycle` L95-102, `GuardianService` L70-76), `"Zombies"` (not self-collidable; `ZombieRaidService` L197-198).
Pets use no collision group (every part `CanCollide/CanTouch/CanQuery = false`, `PetHatchService` L204-210).

---

## 4. `ServerScriptService.BuildHealthService` (345 lines)

- Tracks tag `"PlacedBuild"` (L43, L322-324), skips `IsFloor` / `IsStairs` models (L227).
- Model attributes: `Health`, `MaxHealth` (L233, L183), `Broken` (true at 0, nil when mended; L200, L217).
  Broken parts fade to 0.65 and stop colliding (L189-205); DefenceService skips Broken models.
- `ServerStorage.BuildAPI` (L62-73, L277-283): BindableFunctions `Damage(model, amount, source) -> health, broken`,
  `IsBroken(model)`, `Heal(model|nil)`. The folder is DESTROYED and rebuilt at script start (L63-64).
  Only `ZombieRaidService.Bash` damages builds.
- Heals every `HEAL_TICK` 1 s while `CyclePhase == "Day"` (L286-307; `PreparingDay` and nil do not heal),
  `HealSeconds()` = `max(10, 0.8 x DayDurationSeconds)` = 144 s (L76-80). Everything to 100 % the moment
  `CyclePhase` becomes `"Night"` (L310-319).
- Sounds (server-side PlayFXAt): `"Rock Crumble"` (L203), `"Magic Shimmer"` (L219).
- Dev hook `workspace.BuildHealthDev` = `"damage:<n>" | "break" | "heal"` (L327-342) - NOT Studio-gated.
- Pet relevance: pets never damage or heal builds; PLAN §6 says builds do not block pet shots. No coupling needed.

---

## 5. `ServerScriptService.StrengthProgressionServer` (128 lines)

- The ONLY writer of `Humanoid.WalkSpeed` for normal movement (L49-50, L58, L81). Speed =
  `(SlowMode and SLOW_MODE_SPEED or Progression.GetWalkSpeed(strength) * carryMult) * boostMult`.
- `SLOW_MODE_SPEED = 25` (L26, changed from 16 on 2026-09-22), `BOOST_MULT = 2` while
  `SpeedBoostUntil > workspace:GetServerTimeNow()` (L24, L27-30).
- Remote: `Remotes.SetSlowMode` (RemoteEvent, find-or-create L7-13; `ReplicatedStorage:WaitForChild("Remotes")` L7),
  validates `typeof(enabled) == "boolean"` (L15).
- Player attributes written: `SlowMode` (L16, L35), `StrengthWalkSpeed` (L41), `UnlockedPhysiqueStage` (L42),
  `PhysiqueStage` / `PhysiqueName` / `PhysiqueHeight` (L59-61). Listens to `CarryingCucumber`,
  `CarryingCucumberKg`, `SlowMode`, `SpeedBoostUntil` (L99-107) and `player.Data.Strength` (L109-116).
- Pet relevance: pets must not write WalkSpeed or any of these attributes (no pet speed boost in this release).

---

## 6. `ServerScriptService.SpawnAtBaseServer` (88 lines) + `PlotService` (201 lines)

SpawnAtBaseServer:
- Waits up to `PLOT_WAIT = 10` s for player attribute `Plot` (plot NAME, `PlotOf` L31-34), then at most two
  looks (`SECOND_TRY = 0.6` s apart) and only while `GRACE_SECONDS = 4` has not passed, the humanoid is not
  walking, and the root is outside the plot + `MARGIN = 6` (L48-80). Pivots to `PlotSpawn.CFrame * (0, ROOT_UP=2.6, 0)` (L41-46).
- No attributes of its own, no remotes.

PlotService (lifecycle-relevant):
- Plot = BasePart child of `workspace.Map.Lobby.Plots` ("Plot 1".."Plot 6", attr `PlotIndex`).
- `Assign` (L144-161): `plot.Owner = UserId`, `plot.OwnerName`, `player.Plot = plot.Name`, `RespawnLocation = PlotSpawn`.
- `Release` on `Players.PlayerRemoving` (L163-171, L198): clears `Owner`, `OwnerName`, `player.Plot`.
  That Owner -> nil fires `PetHatchService` L389-391 `ClearPlotPets` (and EggPlacement's equivalent) from an
  independent PlayerRemoving handler - see §15 ordering.
- `FRONT_DIRECTION = (-1,0,0)` (L32). `PlotSpawn` (SpawnLocation, disabled, invisible) is rebuilt whenever the
  plot's `Size`/`CFrame` changes (plot upgrades, L90-118).
- Runtime plot children: `PlotSpawn`, `Pets` (Folder, `PetHatchService` L87-95), `Placed` (shared holder for
  cucumbers/builds/eggs: `CucumberCarry` L859, `BuildService` L194, `EggPlacement` L147), `GrassTiles` (`BuildService` L278).

---

## 7. `ReplicatedStorage.Modules.SoundController` + sound names

API (L1-13):
- Server: `SoundController.PlaySound(name, parent?, {Volume, Speed, Pitch, RollOff, RollOffMin, MaxLife})` (L54-71).
- Client: `PlayFX(name, opts)` (L78-131; opts `Volume, Speed, Pitch, Parent, Key, MinInterval, MaxConcurrent,
  Variants, RollOff, RollOffMin, Looped, MaxLife`), `PlayFXAt(name, position, opts)` (L134-147), `PlayerSoundClient` (L150-152).
- SFX gate: `SetSFXEnabled(bool)` or LocalPlayer attribute `SFXEnabled == false` (L39-48).
- Throttle: per-name `ActiveCount` capped by `MaxConcurrent` (default `DEFAULT_MAX_CONCURRENT = 3`, L30) and
  per-key `MinInterval`.
- Templates: `ReplicatedStorage.Assets.Sounds` (L22; 52 children per `_structure.txt` L25-26; the README says 47
  were ported plus later additions). The full child list is NOT in the snapshot.

GOTCHA: `PlayFXAt` is documented "Client Use Only" but the server calls it everywhere
(`BuildHealthService` L203/L219, `DefenceService` L397-798, `ZombieRaidService` L567-1558, `BatServer` L47).
On the server `Players.LocalPlayer` is nil, so the SFX gate always passes, the sound replicates to everyone
(ignoring each player's `SFXEnabled`), and the `ActiveCount` cap (3 per name) is SERVER-WIDE and shared with the
towers. Pet shot/impact/proc sounds belong in `PetEffectsClient` via `PlayFX`/`PlayFXAt` with a `Key` +
`MinInterval`. `ZombieAPI.Damage` already plays `"Hit Crunch"` per hit (rate-limited `HIT_SOUND_GAP = 0.08` s per
zombie, `ZombieRaidService` L857-861), so a pet hit needs no extra impact sound.

Sound names referenced by scripts (so they exist or are expected to):
`"Air Slice"`, `"Alarm Bell"`, `"Big Break"`, `"Big Thud"`, `"Bottle Pop"`, `"Bottle Pop 2"`, `"Button Pop"`,
`"Cash Register"`, `"Click Sound"`, `"Collect"`, `"Dirt Dig"`, `"Drama Sting"`, `"EggClick"` (EggHatchClient L81),
`"Electric Buzz"`, `"Error"`, `"Hit Crunch"`, `"Magic Shimmer"`, `"Magic Zoom"`, `"Metal Heavy"`, `"Pet Reward"`
(EggHatchClient L488), `"Riser"`, `"Rock Crumble"`, `"Sad Trombone"`, `"Slide Whistle"`, `"Success"`, `"Thunder"`,
`"Victory Sting"`, `"Wet Crunch"`, `"Whoosh"`, `"Zap"`. README also names `"EggPop"`, `"Cucumber Break"`,
`"Water Splash"`, `"Water Splash 2"` (the `"Water Gulp"` templates were removed).
ButtonFX presets (`ButtonFX` L30-32): `PRESS_SOUND = {"Button Pop", 0.3}`, `SUCCESS_SOUNDS = {{"Cash Register", 1.5}, {"Magic Shimmer", 1.2}}`,
`FAIL_SOUND = {"Error", 1.2}`; `ButtonFX.Sound(entry)` (L43-46).
Plausible pet re-use: `"Pet Reward"` (hatch), `"Zap"`/`"Air Slice"`/`"Whoosh"` (shot), `"Magic Shimmer"`/`"Magic Zoom"`
(ability arc), `"Rock Crumble"` or `"Big Break"` (shield break, one restrained sound), `"Collect"` (income tick, rate-limited).
Enumerating all 52 names needs one read-only Studio query later.

Toasts: `ReplicatedStorage.Modules.Notify` is LocalScript-only (header L2); `Notify.Show(text, color?, seconds?)`
(L175), `Error/Warn/Success/Info(text, seconds?)` (L212-215). A server-decided owner toast must travel over a
remote (e.g. `PetState`/`PetEffects`) and be shown client-side.

---

## 8. `ReplicatedStorage.Remotes` - who creates it, how scripts wait

- The folder EXISTS in the saved (edit-time) place, holding `GymBoardState` + `GymBoardAction`
  (`_structure.txt` L36-38) - probably left by a GymService require during an edit-mode eval (GymService creates
  its remotes at require time, L64-78). HeadbandService L74's comment "ReplicatedStorage.Remotes does not exist at
  edit time" is stale. Do not rely on either: servers find-or-create, clients WaitForChild.
- Server find-or-create (`FindFirstChild("Remotes")` + `Instance.new("Folder")`): BenchServer L76-80, BuildPromptServer
  L34-38, BuildService L62-66, CucumberCarry L89-93, CucumberSpawner L87-88, EggPlacement L58-62, GuardianService L79-84,
  HeadbandService L75-79, PetHatchService L59-64, PlotUpgradeService L56-60, ZombieRaidService L166-171, GymService L64-68.
- Server `WaitForChild("Remotes")` (relies on someone else): AdminService L23, CucumberMoveServer L34,
  LeaderstatsService L29, StrengthProgressionServer L7, CucumberAdventure L8.
- Helper idiom (CucumberCarry L95-102, HeadbandService L81-88, GymService L70-77):
```lua
local function remote(className, name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new(className); r.Name = name; r.Parent = Remotes end
	return r
end
```
- Clients: `ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("<Name>")` (usually no timeout); the robust
  form is PlacedCucumberCardClient L254-255: `WaitForChild(INCOME_REMOTE, 60)` then `if not remote then warn(...) return end`.

Existing names under `Remotes` (avoid collisions; RE = RemoteEvent, RF = RemoteFunction):
`AdminAction` RF (AdminService L30-35) · `BenchBonusPopup` RE, `StrengthPopup` RE (BenchServer L84-106) ·
`BuildModeEnter` RE (BuildPromptServer L42-44) · `requestBuildPlacement` / `requestBuildMove` / `requestBuildSell` RF
(BuildService via `BuildCatalog.REMOTE/MOVE_REMOTE/SELL_REMOTE`, BuildCatalog L44-46) · `DropCucumber` RE,
`requestCucumberPlacement` RF, `CarryFX` RE, `CucumberLift` RE (CucumberCarry L102-105) · `requestCucumberMove` RF
(CucumberMoveServer L37-39) · `MutationAnnounce` RE (CucumberSpawner L89-90) · `requestPlacement` RF (EggPlacement
L66-68) · `Guardian` RE (GuardianService L85-90) · `HeadbandAction` RF, `OpenShopDialog` RE (HeadbandService L88-89) ·
`CucumberIncome` RE (LeaderstatsService L35-44) · `PetHatch` RE (PetHatchService L65-70) · `PlotUpgradeAction` RF
(PlotUpgradeService L64-66) · `SetSlowMode` RE (StrengthProgressionServer L8-13) · `ZombieRaid` RE (ZombieRaidService
L172-177) · `CucumberAdventure` RE, `CucumberCollectionBook` RF, `EquipCucumberCollection` RE (CucumberAdventure
L14-16) · `GymBoardState` RE, `GymBoardAction` RF (GymService L77-78).
Outside `Remotes`: `ReplicatedStorage.MinigameHudRemotes/*` (§2.1), `ReplicatedStorage.GroupGift.Claim` RF (authored),
`ReplicatedStorage.PlaceableBuilds` (BuildService templates). PLAN's new names `PetRequest`, `PetState`,
`PetEffects`, `PetIncome` do not collide.

---

## 9. ServerStorage modules and their bootstrapping

| Loader Script (SSS) | Does | Module guard |
|---|---|---|
| `DataLoader` (4 lines) | `require(ServerStorage:WaitForChild("DataService")).Start()` | `Started` flag, `DataService` L257-259 |
| `GymLoader` (4 lines) | `require(ServerStorage:WaitForChild("GymService")).Start()` | `started`, `GymService` L253-256 |
| `PortalLoader` (1 line, no newline/header) | `require(...:WaitForChild("PortalService")).Start()` | `started`, `PortalService` L27, L418-419 |
| `LobbyLayoutServer` (13 lines) | `pcall(require(LobbyLayout).Apply)` then `Map.Lobby:SetAttribute("LayoutReady", true)` | - |

Other ServerStorage modules are plain requires: `CharacterPhysique` (StrengthProgressionServer L4), `CucumberAdventure`
(CucumberCarry L108, CucumberSpawner L92; it requires `script.Parent.DataService` L6 and creates 3 remotes at
REQUIRE time L8-16), `DesertHuntService` + `PortalTransitionService` (started by `PortalService.Start` L430-431; no
guards of their own), `HeadbandFitter` (HeadbandService L52), `GroupGiftReward` (GroupGiftServer L6).
`GymService` is required by BenchServer L47, HeadbandService L53, ShopProductsServer L16 as well; its `Start` assigns
`MarketplaceService.ProcessReceipt` (GymService L268) - any new product must use `GymService.RegisterProduct`, never
overwrite ProcessReceipt.
No existing module exposes `Init(deps)`; the RULES' `Init`/`Start` split is new. A `ServerScriptService.PetServer`
loader in the DataLoader/GymLoader style (header comment + one require + Start) matches the house pattern.

Runtime ServerStorage API folders (BindableFunctions/Events) - the inter-script contract style:
`CucumberSpawnerAPI` (CucumberSpawner L803-806; `BeginDay`, `BeginNight`, `SpawnCarried`, `InField`, ...; sets
`API:SetAttribute("Ready", true)` last, L1080), `CucumberCarryAPI` (CucumberCarry L789-790; `DropForNight`,
`TakeCarried`, `DropAtFeet`, `RestorePlaced`, `ClearPlaced`, ...), `DayNightAPI` (§1.4), `BuildAPI` (§4),
`BuildServiceAPI` (BuildService L635-636), `ZombieAPI` (ZombieRaidService L184-195: `Damage`, `Zombies`, `IsZombie`,
`Slow`, `Stun`; destroyed + rebuilt at start, L185), `GuardianAPI` (§3), `PetHatchAPI` (PetHatchService L249-268:
`SpawnPet`, `ClearPets`), `EggPlacementAPI` (EggPlacement L276-277), `BaseSaveAPI` (BaseSaveService L284-285; `Reset`,
`Resume`, ...). Consumers `WaitForChild` with a timeout inside `task.spawn` (BatServer L27-29 `WaitForChild("ZombieAPI", 120)`,
DefenceService L80 `WaitForChild(ZombieCatalog.API, 60)`, GuardianService L104-114).

---

## 10. CollectionService tags in use

| Tag | Added by (file Lnn) | Read by |
|---|---|---|
| `PlacedCucumber` | CucumberCarry L956, L1038; ZombieRaidService L613 (drop re-tag). Removed: CucumberCarry L1049, L1108; ZombieRaidService L533 (grab) | LeaderstatsService (L31 const), BaseSaveService (L33), CucumberMoveServer (L30), ZombieRaidService (L150), BuildMenuClient (L105), PlacedCucumberCardClient (L33) |
| `PlacedBuild` (`BuildCatalog.PLACED_TAG`, L43) | BuildService L536, L615 | BuildHealthService, DefenceService, BoostPadService, BaseSaveService, ZombieRaidService, BuildMenuClient |
| `PlotPet` | PetHatchService L238 (`PET_TAG` L45) | BaseSaveService (L33 `TAG_PET`), PetRoamClient (L19) |
| `PlacedEgg` | EggPlacement L222, L256 | PetHatchService (L44), BaseSaveService, EggTimerClient (L4) |
| `Zombie` (`ZombieCatalog.TAG`, catalog L53) | ZombieRaidService L456 | (attribute `Zombie = true` too, L455) |
| `Breakable` | CucumberSpawner L211 (wild field holders); removed CucumberCarry L328-330 | CucumberCarry |
| `CucumberPrompt` | CucumberCarry L707 | CucumberPromptClient |
| `EggTool`, `EggShopPrompt` | EggShop L289, L374 | EggPlacement, HotbarClient, PlacementClient, CucumberPlacementClient, EggShopClient |
| `BoostPadPrompt` | BoostPadService L66 | BoostPadClient |
| `BuildPrompt` | BuildPromptServer L127 | BuildBarrierClient |
| `ShopBoothPrompt` | HeadbandService L350 | ShopDialogClient |
| `PlotUpgradeBoard`, `PlotBench` | PlotUpgradeService L177-178 | BuildPromptServer, PlotUpgradeClient, BenchTierClient, SlowModeClient |
| `Barbell` | BenchServer L190 | BarbellClient, PlotUpgradeService |
| `BarFollower` | BenchTierClient L196 (client-local) | BarbellClient |
| `PortalSign` | PortalService L141 | PortalSignClient |
| `GymBoard`, `LieSeat`, `BenchUpgradeBoard` | authored in the place (no AddTag in code; `GymBoard` removed at PlotUpgradeService L212) | GymBoardsClient, BenchServer, BenchBoardClient |

Guardians have NO tag. New pet tags must not reuse these names (reusing `PlotPet` for the pet models is expected;
BaseSaveService currently snapshots pets FROM that tag, which PLAN §8.4 says to stop).

---

## 11. StreamingEnabled implications (`workspace.StreamingEnabled = true`)

- Persistent models: zombies (`ModelStreamingMode.Persistent`, ZombieRaidService L435) - always present on every
  client, so a client-side projectile can always find its zombie target model; the Breakables container
  (CucumberSpawner L131-143); portal maps are `PersistentPerPlayer` + `AddPersistentPlayer` (PortalService L325, L342).
- NOT persistent: plot pets (PetHatchService sets no mode), placed cucumbers, builds, eggs, guardians - they
  stream in/out with distance. `CollectionService` added/removed signals fire on stream in/out.
- Client patterns to copy:
  - Tag-driven attach/detach, never a cached path: PetRoamClient L95-97, PlacedCucumberCardClient L265-267,
    ShopDialogClient header L20-26 ("The tag is watched, never a path: StreamingEnabled can take the booth out and back").
  - Completeness wait: PetRoamClient L63-89 reserves `pets[model] = false`, waits for `PartCount` BaseParts (server
    stamps `PartCount`, PetHatchService L232) up to 5 s, re-checks `model.Parent` and the reservation before building state.
  - Child wait with timeout + re-check: PlacedCucumberCardClient L117-123 `model:WaitForChild("PlotHitbox", 5)` then
    `if Cards[model] ~= card or not model:IsDescendantOf(workspace) then return end`; GymBoardsClient L57-63
    (30 s waits); HeadbandService `STREAM_WAIT = 30` (L66).
  - Per-frame loops drop dead entries: PetRoamClient L109-111 (`not model.Parent or not s.Root.Parent` -> Detach).
- Remote payloads: an `Instance` argument arrives as nil on a client that has not streamed it.
  PlacedCucumberCardClient L256-261 guards `typeof(model) == "Instance"` per entry. PetEffects/PetIncome batches
  should carry PetId/CucumberId strings + world positions so an unstreamed target degrades to "skip" or
  "use the server origin" (PLAN §6), not an error.
- Server-side pre-teleport streaming: `player:RequestStreamAroundAsync(pos, t)` (PortalTransitionService L40,
  ZombieRaidService L1463).

---

## 12. Dev / test hook conventions

House pattern (PetHatchService L400-431, CucumberCarry L1191-1227, EggShop L420-433, HeadbandService L507-511,
CucumberSpawner L1041-1079, GymService L292-306, PlotUpgradeService L319-338):
```lua
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("XxxDev"):Connect(function()
		local cmd = workspace:GetAttribute("XxxDev")
		if type(cmd) ~= "string" or cmd == "" then return end
		workspace:SetAttribute("XxxDev", nil) -- edge-triggered, cleared first
		local verb, arg = cmd:match("^(%w+):?(.*)$")
		local player = Players:GetPlayers()[1] -- "the first player"
		...
	end)
end
```
Variants: PetHatchService clears with `""` not nil (L405); PlotUpgradeService clears only after success (L336);
GuardianService puts the verb/target parse in `Dev(command)` (L1150-1193) and `task.spawn`s it; two writes in one
frame collapse (GuardianService header L36).
Existing workspace hook names (do not reuse): `PetHatchDev`, `CarryDev`, `EggShopDev`, `HeadbandDev`, `PlotUpgradeDev`,
`GymDev`, `MutationDev`, `GiantDev`, `BiomeBannerDev` (client), `ShopDialogDev` (client), and the UNGATED
`ZombieDev` (ZombieRaidService L1625-1672), `BuildHealthDev` (BuildHealthService L327-342), `GuardianDev`
(GuardianService L1241-1244). Also script attribute `ForceGiant` (CucumberSpawner L987, Studio-gated).
Client-side hooks live on GUI/PlayerGui attributes: `LiftDevCPS`/`LiftDevState` (CucumberLiftClient L842-859, gated),
`DevPress`/`DevHover` (HotbarClient L501-512, gated), `DevClick` on RevealUi (EggHatchClient L226-230, gated),
ungated `AdminDev` (AdminPanelClient L128-139, admin-only GUI), `BuildDev` (BuildMenuClient L1246), `BaseDev`/`HoverDev`
(BaseHUDController L191, L250-255), `HUDDev` (HUDClient L203-209), `ShopDev` (ShopController L217).
A client cannot set a workspace attribute that replicates to the server, so the ungated server hooks are not
exploitable, but RULES require every NEW hook to be `RunService:IsStudio()`-gated or behind the admin check.
Test randomness/clock should be injected into modules instead (PLAN §12).

---

## 13. Admin permission check + reset flow

- `AdminService` (server): `local ADMINS = {[140977250] = "awesomeotheraccount"}` (L26), `COOLDOWN = 0.3` (L27),
  `MAX_VALUE = 1e300` (L28). Remote `Remotes.AdminAction` RF (L30-35). Gate is the first line of the handler:
  `if not ADMINS[player.UserId] then return false, "Not an admin" end` (L111), then a per-player cooldown
  (`"Too fast"`, L112-114), then a `pcall`-wrapped dispatch on a string action (L115-124) returning `(ok, message)`
  (L130). Numbers go through `Number(value)` (L52-57: strips `,_%s`, rejects NaN/inf, floors, clamps 0..1e300).
  `SetValue`/`ResetData` refuse until `DataService.IsLoaded(player)` (L74, L80).
- Client copy: `AdminPanelClient` L15 `local ADMINS = {[140977250] = true} -- (keep in step with AdminService)`;
  the ScreenGui destroys itself for non-admins (L22-25). There is NO shared admin module - a third copy would drift.
- `ResetData` (L79-108): `BaseSaveAPI.Reset(player)` -> `DataService.ResetProfile(player)` -> bounce the plot's
  `Owner`/`OwnerName` to nil and back after one `task.wait()` (L91-98) so PlotUpgradeService/GymService/EggPlacement/
  PetHatchService/badges re-sync -> wait up to 5 s for `PlotLevel == 0` (L99-100) -> `BaseSaveAPI.Resume(player)` ->
  deferred `player:LoadCharacter()` (L103-105). The Owner bounce fires PetHatchService `ClearPlotPets` (L389-391).
  Studio uses the live profile too (header L13-14; `DataService` L53 `USE_MOCK_IN_STUDIO = false`).

---

## 14. Leave / shutdown handlers (ordering inputs for PLAN §8.4)

`Players.PlayerRemoving` is connected independently by: AdminService L133, BaseSaveService L261, BenchServer L155/L491,
BoostPadService L81, BuildPromptServer L52, BuildService L672, CucumberCarry L1183, CucumberMoveServer L121,
CucumberSpawner L1024, EggPlacement L326, EggShop L418, GroupGiftServer L59, GuardianService L1226, HeadbandService L496,
LeaderstatsService L154, PetHatchService L395 (drops `Pending` = an in-flight reveal is lost), **PlotService L198
(`Release` -> `plot.Owner = nil` -> PetHatchService/EggPlacement clear the plot)**, PlotUpgradeService L317,
StrengthProgressionServer L118, ZombieRaidService L1617 (`EndRaid(raid, "Left")`), CucumberAdventure L214,
**DataService L251-254/L261 (`profile:EndSession()` = final save, then `Forget`)**, DesertHuntService L185,
PortalService L442, PortalTransitionService L19. Connection order across Scripts is not defined, so none of these
may assume another has or has not run.
Shutdown: the only `game:BindToClose` is inside ProfileStore (L2199-2203 mock, L2208-2238 live): it saves every
active profile in parallel immediately. PlayerRemoving handlers also run during shutdown, concurrently. A pet flush
that must be in the saved data therefore has to be written into `profile.Data` BEFORE close (continuously / on
change), not in a BindToClose that races ProfileStore's.

---

## 15. PLAN.md §2 vs the live code (this area)

- §2 issue 10 (cycle attributes 180 / 45 vs a 10 s comment): CONFIRMED (`_structure.txt` L593; header L5 and L238
  say 10). Extra nuance the plan misses: the code's own FALLBACK night length is still 10 (`DayNightCycle` L57,
  `EggShop` L68), and the workspace mirrors `DayDurationSeconds`/`NightDurationSeconds`/`DayNumber` are nil on a
  server that booted mid-night until the first dawn.
- §4.1 "180/45 cycle -> at most 240 s": CONFIRMED (225 + 15 = 240 < 600).
- §2 issue 11 (DataService ends the session in its leave handler; BaseSave cleans up in its own): CONFIRMED
  (DataService L251-254). Also `PlotService.Release` (L163-171) clears `plot.Owner` from yet another PlayerRemoving
  handler, and `PetHatchService` L389-391 destroys the plot pets on that change - a third independent cleanup path.
- §6 "Dead, Shaded, and Underground zombies cannot be hit; the API already filters/rejects": CONFIRMED
  (`ZombiesAPI` L877-883 excludes them; `DamageZombie` L852-853 refuses). Consequence: `ZombieAPI.Zombies()` is NOT a
  complete "live raid" list (shaded shadows / diggers underground are missing), so a combat lock must not be built
  from it alone - see hazards.
- §6 "`Owner` attribute is set to the raid owner's UserId": CONFIRMED (`ZombieRaidService` L454
  `raid and raid.UserId or nil`); day thieves have a raid too (`SpawnThief` L1548-1549), so they carry `Owner`.
- §1 "Pets do not follow into portals / attack guardians": no conflict; guardians are outside ZombieAPI (§3).
- §14 "Existing systems ... Slow Mode still sets WalkSpeed 16": CONTRADICTED. `SLOW_MODE_SPEED = 25` since 2026-09-22
  (`StrengthProgressionServer` L25-26; CucumberLiftClient restores the same number), and it is doubled by an active
  boost pad (`BOOST_MULT`, L24/L49). Regression tests must expect 25 (50 while boosted).
- §14 "AdminService warns that Studio can still use live profiles": CONFIRMED (AdminService L13-14, DataService L53).
- §12 "Test hooks ... behind the existing server admin permission checks": there is no reusable check - only the
  local `ADMINS` tables in AdminService L26 and AdminPanelClient L15.
