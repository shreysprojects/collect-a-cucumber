# Research: zombie raids + defences (live snapshot 2026-09-22)

Read-only map of the live code, taken from `../live-2026-09-22/`. Line numbers match those snapshot files. They will move once `patched/` copies are edited.

| DataModel path | Snapshot file | Lines |
|---|---|---|
| ServerScriptService.ZombieRaidService (Script) | `ServerScriptService.ZombieRaidService.server.lua` | 1674 |
| ReplicatedStorage.Modules.ZombieCatalog (Module) | `ReplicatedStorage.Modules.ZombieCatalog.lua` | 239 |
| ServerScriptService.DefenceService (Script) | `ServerScriptService.DefenceService.server.lua` | 851 |
| StarterPlayer.StarterPlayerScripts.ZombieRaidClient | `StarterPlayer.StarterPlayerScripts.ZombieRaidClient.client.lua` | 244 |
| StarterPack.Bat.BatServer (Script) | `StarterPack.Bat.BatServer.server.lua` | 72 |

**Callers of `ServerStorage.ZombieAPI`:** only DefenceService and BatServer; I grepped the whole snapshot.
- GuardianService requires ZombieCatalog only to find the `ZombieRaid` remote. It fires `{Kind="Hit"}` for its knockback.
- Biome guardians are **not** in `ZombieAPI.Zombies()`.

**Listeners on `Remotes.ZombieRaid`:** ZombieRaidClient (all Kinds) and BuildMenuClient.
- BuildMenuClient, line 1212, reacts only to `"ThiefStole"`.
- Both ignore unknown Kinds, so adding a new Kind is harmless.

---

## 1. ZombieRaidService config (lines 112-152)

| Constant | Value | Notes |
|---|---|---|
| `CUTSCENE_SECONDS` | 6.5 | |
| `DOOR_FIRST` | 1.2 | |
| `DOOR_ROW_GAP` | 0.5 | |
| `DOOR_COLUMNS` | 4 | |
| `DOOR_REACH` | 5 | A carrier this close to the door escapes. |
| `WALK_OUT` | 14 | |
| `DAY_THIEF_MIN/MAX` | 50/100 s | |
| `DAY_THIEF_GRACE` | 25 | |
| `DAY_THIEF_NIGHT_GUARD` | 20 | |
| `THIEF_POOL` | `{"Rotten Shambler","Scrawny Runner","Plague Shambler","Feral Runner"}` | No grapplers, diggers or shadows are ever thieves. |
| `BASE_OFFSET` | 20 | The wave is set down 20 studs in front of the plot's front edge. |
| `BASE_SPREAD` | 4 | |
| `GRAB_RANGE` | 4 | |
| `REPATH_SECONDS` | 2 | |
| `WAYPOINT_REACH` | 3 | |
| `STUCK_SECONDS` | 1.6 | |
| `BASH_INTERVAL` | 1.0 | |
| `BASH_DAMAGE` | 25 | |
| `BASH_REACH` | 5 | |
| `CARRY_SPEED` | 0.85 | |
| `SLOW_MULT` | 0.45 | |
| `TICK` | 0.1 | Heartbeat accumulator. |
| `DEATH_FADE` | 1.1 | |
| `WANDER_SECONDS` | 4 | |
| `HIT_SOUND_GAP` | 0.08 | |
| `HIT_RANGE` | 4.5 | Hostility. |
| `HIT_CONE` | 0.5 | Hostility. |
| `HIT_COOLDOWN` | 1.4 | Hostility. |
| `HIT_PAUSE` | 0.5 | Hostility. |
| `SWING_DELAY` | 0.2 | Hostility. |
| `HIT_DAMAGE` | **0** | Knockback only. |
| `KNOCKBACK_DISTANCE` | 10 | |
| `KNOCKBACK_TIME` | 0.35 | |
| `FRONT_DIRECTION` | `(-1,0,0)` | |
| `PLACED_TAG` | `"PlacedCucumber"` | |
| `BUILD_TAG` | `"PlacedBuild"` | |
| `COLLISION_GROUP` | `"Zombies"` | |

**Clock:** every ZombieRaidService timer uses `os.clock()`. This covers `StunUntil`, `SlowUntil`, `NextHit`, `DigCooldownUntil` and the `now` passed to `Tick`. None of them uses server epoch time.

---

## 2. Data structures

### Module state (lines 210-215)
```lua
local Raids = {}    -- [player] = raid {Player, UserId, Plot, Level, Limit, Stolen, Zombies = {entry}, Alive, Over}
local DayRaids = {} -- [player] = raid with Day = true: the daytime thief (one at a time)
local Zombies = {}  -- [model] = entry
local Phase = "Idle" -- Idle | Cutscene | Raid
```
All four are **script locals**. No other script can read them. The raid tables are never exposed.

### Raid table (built by `NewRaid`, lines 1322-1334)
Fields set at creation:
- `Player`, `UserId` (= `player.UserId`), `Plot` (the plot BasePart)
- `Level` and `Score` (from `ThreatOf`)
- `Limit` = `math.huge` for a day raid, else `math.min(ZombieCatalog.STEAL_LIMIT, count)`
- `Cucumbers` = `count` of placed cucumbers at raid start
- `Stolen = 0`, `Zombies = {}` (array of entries), `Alive = 0`, `Over = false`
- `Day = isDay == true`
- `Wave`, night only: `ZombieCatalog.WaveFor(level, rng)`

Fields added later:
- `Result`: `"Survived"`, `"ZombiesWin"`, or the EndRaid reason (`"Dawn"`, `"Left"`, `"Night"`).
- `Ended = true`: set by `EndRaid`, line 1338. This is the lifecycle end, which is separate from `Over`.
- `Hostile = {[Player]=true}`: set by `DamageZombie` when a **Player** attacker hits (lines 866-868).
- `Dropped = {[cucumberModel] = {Rest = CFrame(home), Name}}`: set by `RestoreCarry` when given `dropAt` (lines 607-608).
  - Cleared per model by `Grab` (line 532).
  - Cleared wholesale by `ReturnDropped` (line 621).

Side effects of `NewRaid`:
- It publishes `plot:SetAttribute("ThreatLevel", level)` and calls `Publish(raid)`.
- This happens **for every player with a plot at nightfall, even when the raid is then discarded** because `raid.Cucumbers == 0` (lines 1441-1446).

`Over` versus `Ended`:
- `Over` means the result has been decided. It is set in `CheckRaidEnd`, `Escape` (ZombiesWin) and `EndRaid`.
- `Ended` means `EndRaid` has run. A night raid that ended in "Survived" stays in `Raids[player]` with `Over = true` until dawn's `EndAll`.
- The dev hook `spawn:` can reset `Over = false` again (line 1657).

### Zombie entry (built by `Spawn`, lines 465-478)
Fields set by `Spawn`:
- `Model`, `Humanoid`, `Root` (HumanoidRootPart), `Variety` (the catalog table), `Raid` (may be nil for strays), `Runner`
- `Shadow`, `Shaded=false`, `ShadeAt`
- `Grapple`, `BaseTransparency`
- `Digger`, `Underground=false`, `DigCooldownUntil=0`
- `Swing`, `NextHit=0`, `Walk`, `Idle`
- `State="Seek"`, `Target=nil`, `Goal`, `RepathAt`, `Waypoints`, `WaypointIndex`, `Direct`
- `LastPos`, `LastMove`, `NextBash`, `SlowUntil=0`, `StunUntil=0`, `NextHitSound`, `Path`
- `Dead=false`, `Moving=false`

Fields added later:
- `Fill` and `Label`: the billboard.
- `Carry`: set by Grab.
- `Grappling = true | nil` (lines 1001/1046) and `Digging = true | nil` (lines 1064/1130).
- `Hold = true`: set during the cutscene (line 1492). The entry is not ticked while it is set.
- `Counted`, `Flashing`, `Pathing`, `MoveTarget`, `WanderGoal`, `WanderUntil`.

`entry.Target` is the cucumber Model being sought. It is **not replicated**.

### Carry table (Grab line 531)
`{Model = cucumber, Rest = restCFrame or HomeRest(raid, model), Holder = model.Parent, Parts = {[BasePart] = {Anchored, CanCollide, CanQuery, CanTouch, Massless}}, Name = CucumberName attr or model.Name}`

---

## 3. Replicated state

### On the zombie Model (`Spawn`, lines 433-458, and later)

| Attribute / property | Set where | Value |
|---|---|---|
| `Name` | 434 | The variety name, e.g. `"Titan Brute"`. It is **not unique**. |
| `ModelStreamingMode` | 435 | `Persistent` |
| `Variety` | 453 | The variety name (string). |
| `Owner` | 454 | `raid and raid.UserId or nil`: a **number UserId** of the raided or thief-targeted player. Split children inherit the raid, so they get the same Owner. |
| `Zombie` | 455 | `true` |
| Tag `"Zombie"` (`ZombieCatalog.TAG`) | 456 | |
| Parent | 458 | `workspace.Zombies` (`ZombieCatalog.FOLDER`) |
| `Shaded` | 806 (`SetShade`) | Boolean. Only ever set on Shadow varieties; nil on all others. |
| `Underground` | 1076 true / 1128 false | Boolean. Only ever set on Digger varieties; nil otherwise. |
| `State` | 1233 (`Tick`) | Mirrors `entry.State` (see section 4). It is **nil until the first Tick**, so it is nil for the whole cutscene while `Hold` is set. |
| `Dead` | 746 (`Kill`), 755 (`Despawn`) | `true`. The model stays in the folder for about 0.9-1.4 s while it fades. |
| Health | `Humanoid.MaxHealth/Health` (444-445) | There is **no Health attribute**. Read the Humanoid, which replicates. |
| BillboardGui `"ZombieTag"` on Head | 339-382 | Studs-sized name and health bar. It is destroyed by `FadeAway`. |

There is **no** `Carrying`, `Grappling` or `Digging` attribute.

### On a cucumber during raids
- `StolenBy`: set to `entry.Model.Name` (the variety name) in `Grab` (534) and cleared to nil in `RestoreCarry` (611).
  - Readers: CucumberMoveServer line 70 ("A zombie has it") and BuildMenuClient lines 549 and 947.
- The `PlacedCucumber` tag is removed in `Grab` (533) and re-added in `RestoreCarry` (613).
- `Owner`, `CucumberName`, `Zone` and the other attributes are **untouched**.
  - A carried cucumber keeps `Owner = <victim UserId>`.
  - It is the **same Instance** from grab to drop to return. Only `Escape` destroys it (line 770).
- During a grapple **pull** the cucumber is still tagged, has **no StolenBy**, and is still in `plot.Placed`.
  - The only marker is the child Attachment `"GrappleB"` on its primary part (1010-1012). Its twin `"GrappleA"` and the Beam `"GrappleRope"` sit on the zombie's RightHand.

### On the plot
`Publish(raid)`, lines 679-687, writes `RaidAlive`, `RaidStolen`, `RaidLimit` and `RaidOver`. It returns early for day raids. `ThreatLevel` is written at line 1331.

**These attributes are not a reliable "combat live" signal. Nothing reads them in the snapshot.**
- `EndRaid` (1336-1366) never calls `Publish`. After a Dawn with zombies still alive, `RaidOver=false` and `RaidAlive>0` stay stale on the plot all day.
- A player with 0 cucumbers still gets `RaidAlive=0, RaidOver=false` published at nightfall, from `NewRaid` line 1332.
- Day thieves publish nothing.

---

## 4. Entry STATE values (exact strings)

| `entry.State` | Assigned at | Meaning |
|---|---|---|
| `"Seek"` | 474 (Spawn default), 1267 (`Tick`, target found) | Walking or pathing to the target cucumber. Grappling and digging zombies also stay `"Seek"`. |
| `"Carry"` | 563 (`Grab`) | Carrying a cucumber back to the door. |
| `"Leave"` | 1283 | A **day thief** with nothing left to steal is walking back to the door. |
| `"Wander"` | 1293 | A **night** zombie with nothing left to steal is roaming the base. |

**There is no grapple, dig or stun state string.** Those conditions are entry booleans:
- `entry.Grappling` (not replicated)
- `entry.Digging` (not replicated; `Underground` attribute is replicated)
- `entry.StunUntil` / `entry.SlowUntil` (os.clock numbers, not replicated)
- `entry.Hold` (not replicated)

Timing of the replicated `State` attribute:
- It is written at line 1233, **before** the grapple/dig early-return at 1242, and before this tick's state logic runs.
- So the attribute lags `entry.State` by one tick (≤0.1 s). For example, `Grab` inside Tick sets `"Carry"`, but the attribute updates on the next Tick.
- A Grab from the grapple task (line 1048) also shows up on the next Tick.

**Consequence for pet priority 2 ("actively grappling"):** it **cannot** be derived from replicated attributes. Priority 1 ("carrying") can only be approximated by `State=="Carry"`, lagged, or by a child Model with `StolenBy`. `ZombieAPI.GetTargetInfo` (or a batch variant) is therefore **needed**, not optional.

---

## 5. Tick flow (`Tick`, lines 1213-1312; main loop 1587-1603)

The main loop runs on Heartbeat. Every ≥0.1 s it walks `Raids` and then `DayRaids`, and runs `pcall(Tick, entry, now)` for each entry without `Hold`. `now = os.clock()`.

`Tick` does the following in order:
1. **Dead / missing model:**
   - Return if `entry.Dead`.
   - If `not entry.Model.Parent`: set `Dead`, `Carry = nil`, call `Forget` and `CheckRaidEnd`. The carried cucumber is **not** restored; it is gone with the model.
2. **Speed:** `speed = variety.Speed`.
   - While carrying: × `GRAPPLE_CARRY_SPEED` (1.15) for grapplers, else × `CARRY_SPEED` (0.85).
   - While slowed: × `SLOW_MULT`.
   - While stunned: **0**.
   - The result is written to `humanoid.WalkSpeed`.
3. **Sync the `State` attribute** (1233).
4. **Shadow phasing** (1234-1241). Carrying forces the zombie solid.
5. `if entry.Grappling or entry.Digging then return end` (1242).
6. **Hostility swat** (1244-1247). This only happens if `raid.Hostile` is set.
7. **Carry:** navigate to `DoorPoint()`. Within `DOOR_REACH` → `Escape(entry)` (1250-1257).
8. **Otherwise:**
   - Revalidate the target (it must be a child of the holder **and** tagged), else pick `NearestCucumber`. That function's score adds 8 studs per other zombie already claiming the cucumber.
   - Then, with `target` set (1266-1280):
     - `dist <= GrabReach` → **`Grab(entry, target)`** (line 1271). On false, `entry.Target = nil`. Then `return`.
     - Grapple variety and `dist <= GrappleRange` and `now >= entry.StunUntil` → `StartGrapple` (1274-1276).
     - Digger and `dist >= DIG_RANGE_MIN` and not on dig cooldown and not stunned → `StartDig` (1277-1279).
     - Otherwise `Navigate` toward the target at plot-top height.
   - With no target: a day raid goes to `"Leave"` (door, then `Despawn` + `CheckRaidEnd`); a night raid goes to `"Wander"`.
9. **Stuck check:** `Bash` a build in the way, else jump (1304-1311).

**Stun does NOT gate Grab.** Line 1270 grabs whenever the target is in reach, whatever `StunUntil` says. `StunUntil` only zeroes walk speed and gates *starting* a grapple or a dig. `GrabReach(model, entry) = 4 * max(1, Scale*0.8) + (PlotHitbox half-max-XZ or 1)` (1152-1156).

---

## 6. `Grab(entry, model, restCFrame)`: exact steps (lines 522-570)

1. `raid = entry.Raid`.
   - `primary = model.PrimaryPart or first BasePart descendant`.
   - `hitbox = model:FindFirstChild("PlotHitbox")`.
   - **Return false if no primary** (526).
2. `torso = entry.Model:FindFirstChild("UpperTorso")`. **Return false if missing** (528).
3. Compute `hbCF` and `size` (529-530) from the hitbox, or from the model if there is none.
4. Build `carry` (531). `Rest = restCFrame or HomeRest(raid, model)`. `HomeRest` (517-520) returns `raid.Dropped[model].Rest` if the cucumber lies where a carrier fell, else `model:GetPivot()`.
5. `raid.Dropped[model] = nil` (532).
6. **`CollectionService:RemoveTag(model, PLACED_TAG)`** (533). This is the first mutation. Income stops here, because LeaderstatsService counts tagged cucumbers only, and a BaseSave snapshot is queued.
7. **`model:SetAttribute("StolenBy", entry.Model.Name)`** (534).
8. For every BasePart descendant (535-546):
   - Record `Anchored`, `CanCollide`, `CanQuery`, `CanTouch` and `Massless` into `carry.Parts`.
   - Add a WeldConstraint `"CarryLink"` from primary to the part unless one exists (`IsWelded`).
9. Create a Weld `"CarryWeld"` with `Part0 = torso`, `Part1 = primary`, `C0 = CFrame.new(0, up, 0) * (hbCF:Inverse() * primary.CFrame)`, parented to primary (547-553).
10. Set every part to `Anchored=false`, `CanCollide=false`, `CanQuery=false`, `CanTouch=false`, `Massless=true` (554-560).
11. **`model.Parent = entry.Model`** (561). The cucumber is reparented into the zombie.
12. Set `entry.Carry = carry`, `entry.State = "Carry"`, `entry.Target = nil`, `RepathAt = 0`, `Waypoints = nil` (562-566).
13. Play the "Dirt Dig" sound and `Send(raid, {Kind="Grabbed", Name, Zombie})` (567-568). Return true.

**Raid counters:** `Grab` changes none of them. `raid.Stolen` increments **only** in `Escape` (772). Nothing in the file awards kills or cash; **there is no kill reward anywhere.**

`Grab` has exactly **two call sites**:
- **Line 1271:** the ordinary Tick grab. The **digger surfacing capture also goes through here**, on the Tick after it surfaces.
- **Line 1048:** the grapple final capture.

---

## 7. Drop, return, kill, escape, end

### `RestoreCarry(entry, silent, dropAt)` (575-615)
1. Set `entry.Carry = nil`. Return if there was no carry or the model is gone.
2. Holder = `carry.Holder`, else `HolderOf(raid.Plot)`.
   - If there is no holder, or the raid's player is no longer parented, the cucumber is **`model:Destroy()`**ed (586-589).
3. Destroy `"CarryWeld"` and restore every recorded part property.
   - The `"CarryLink"` WeldConstraints are **left in place**. They are harmless between anchored parts, and `IsWelded` reuses them on the next grab.
4. With a `dropAt` Vector3:
   - `rest = CFrame.new(dropAt.X, GroundY(...) + (carry.Rest.Y - plotTop), dropAt.Z) * carry.Rest.Rotation`.
   - `raid.Dropped[model] = {Rest = carry.Rest, Name}`, which keeps the home pose.
5. `PivotTo(rest)`, then `StolenBy = nil`, then `Parent = holder`, then **`AddTag(PLACED_TAG)`** last.
   - With `silent` false, send `{Kind="Saved"}`.

A dropped cucumber is back in `plot.Placed` and tagged, so it **earns income and is targetable** even while it physically lies in the lobby. It is also a descendant of the plot, so BaseSave's periodic snapshot would record its lobby pose.

### `ReturnDropped(raid)` (618-636)
- Every `raid.Dropped` model still in the holder is pivoted to `info.Rest`.
- If any moved, `BaseSaveAPI.Snapshot` is invoked.
- It is called from `CheckRaidEnd` (Survived / day end), from `Escape` (ZombiesWin) and from `EndRaid`.

### `Kill(entry, source)` (710-748)
Wired to `Humanoid.Died` (485) and to `DamageZombie` (873) when Health ≤ 0. `source` is unused.

Steps:
1. Guard on `entry.Dead`, then set `Dead = true`.
2. **`RestoreCarry(entry, false, entry.Root.Position)`** (713). The cucumber drops where the zombie fell and the owner is told "Saved".
3. `Forget(entry)` (639-646): `Zombies[model] = nil`; `raid.Alive -= 1` once, guarded by `Counted`.
4. **Split** (716-742). If the variety has `Split` and `raid` exists and `not raid.Ended`:
   - Spawn `Split.Count` children of `Split.Variety` in a ring 2.4 studs out.
   - They join **the same raid** (`Spawn(child, ..., raid)`), so they get Owner, `Alive += 1` and registration in `Zombies`, and appear in `ZombieAPI.Zombies()` immediately.
   - `kid.Target = entry.Target`. The children are unanchored with **no Hold**, so they tick at once.
   - `Send {Kind="Split"}`.
   - This all happens before the raid-end check.
5. Play a sound, poof, `FadeAway(entry, 1.1, 2.5)`, set the `Dead` attribute, then `CheckRaidEnd(raid)`.

### `Despawn(entry, effect)` (751-763)
Used for escape, dawn and call-off. Sets `Dead`, calls `Forget`, sets the `Dead` attribute, then fades. It does **not** call `CheckRaidEnd`; callers do that.

### `Escape(entry)` (765-800): the actual steal
1. `entry.Carry = nil`. **`carry.Model:Destroy()`** (770).
2. `raid.Stolen += 1`.
3. Send `"ThiefStole"` for day raids, `"Stolen"` for night raids, then `Despawn`.
4. For a night raid: if `Stolen >= Limit` → `Over`, `Result="ZombiesWin"`, `Send ZombiesWin`.
   - Every other live zombie: `RestoreCarry(other, true)` (straight home, no dropAt), then `Despawn`.
   - Then `ReturnDropped` and `Publish`.
5. Otherwise `CheckRaidEnd`.

**Line 770 is the only "successful steal" point.** This is where pet buffs must be cleared on a steal (PLAN 4.3).

### `CheckRaidEnd(raid)` (689-708)
1. `Publish`, then return if `Over`.
2. **Day raid:** when `Alive <= 0` → `Over`, `ReturnDropped`, `DayRaids[player] = nil`.
3. **Night raid:** when `Alive <= 0` → `Over`, `Result = "Survived"`, `ReturnDropped`, `Publish`, `Send {Kind="Survived"}`.

### `EndRaid(raid, reason)` (1336-1366): dawn, call-off, leave
Guarded by `Ended`.

1. For each live entry, call `RestoreCarry(entry, reason ~= "Left")` with **no dropAt**, which returns the load to `carry.Rest`.
   - With reason `"Left"`: `Model:Destroy()`, `Forget`, `Dead`.
   - Otherwise: `Despawn`, burning at dawn.
2. Call `ReturnDropped`.
3. If not already `Over`: set it. If this is a night raid ending at Dawn, `Send "Survived"` when `Stolen == 0`, else `"Dawn"`.
4. Remove the raid from `DayRaids` or `Raids`.

**Triggers:**
- `OnPhase` (1606-1614): any `CyclePhase ~= "Night"`, i.e. `"PreparingDay"` or `"Day"`, while `Phase ~= "Idle"` → `EndAll("Dawn")`.
- `StartRaids` → `EndDayRaids("Night")` (1453). This runs only when at least one night raid starts.
- `Players.PlayerRemoving` (1617-1622) → `EndRaid(..., "Left")` for both tables.
- The dev hook `end`.

**Leave-ordering note:**
- On `"Left"`, `RestoreCarry` puts carried loads back into the holder while `player.Parent` is still Players.
- BaseSaveService's own `PlayerRemoving` calls `ClearPlaced` (BaseSave lines 261-270), and PlotService calls `Release`.
- Handler order is arbitrary. If BaseSave clears first, the restored cucumber is left tagged in a released plot. This is the same leave-ordering hazard as PLAN issue 11.

---

## 8. `StartGrapple(entry, target)` timeline (997-1054)

Triggered from Tick at 1274-1276 when `entry.Grapple and dist <= (variety.GrappleRange or 24) and now >= entry.StunUntil`.

1. `primary` = cucumber PrimaryPart or first BasePart. **Return false if missing** (1000).
2. `entry.Grappling = true`. `StunUntil = max(StunUntil, now + GRAPPLE_HOOK 0.25 + GRAPPLE_PULL 0.6 + 0.2)`, i.e. about 1.05 s (1001-1002).
3. Stop (`MoveTo(root.Position)`) and face the target (1003-1005).
4. Create the rope (1006-1023):
   - Attachment `"GrappleA"` on `RightHand` (or root).
   - Attachment `"GrappleB"` on the **cucumber primary**.
   - Beam `"GrappleRope"`, parented to the hand.
5. Play "Whoosh" and `Send {Kind="Grappled"}` (1024-1025). Return **true** synchronously (1053).
6. `task.spawn` (1026-1052):
   - `local rest = target:GetPivot()` (1027). This is the pre-pull pose, captured before the first yield.
   - `task.wait(GRAPPLE_HOOK)` (1028).
   - **`local ok = not entry.Dead and target.Parent and CollectionService:HasTag(target, PLACED_TAG)`** (1029).
   - Pull loop (1033-1041) on Heartbeat over 0.6 s. It aborts (`ok=false`) if the zombie dies or the cucumber is untagged or unparented. The cucumber is `PivotTo`'d toward `root + LookVector*2.5` at `rest.Y`. **It stays tagged, in the holder and earning during the pull.**
   - Cleanup (1043-1046): `rope`, `a0` and `a1` destroyed; `entry.Grappling = nil`.
   - `if ok and not entry.Dead then if not Grab(entry, target, HomeRest(entry.Raid, target)) then target:PivotTo(rest) end` (1047-1048).
   - `elseif` still tagged → `target:PivotTo(rest)` (1049-1050).

**Live bug at line 1048.** The header (lines 62-64) says the grapple Grabs "with its ORIGINAL rest pose", but `HomeRest(entry.Raid, target)` is evaluated **after** the pull.
- For a cucumber that was never dropped, that returns `model:GetPivot()`, which is the **pulled** pose about 2.5 studs in front of the zombie (up to 24 or 32 studs from home, possibly off the plot).
- So `carry.Rest` becomes the pulled pose, and a later kill, dawn or ZombiesWin sends the cucumber "home" to the pull spot.
- Previously dropped cucumbers are fine, because `raid.Dropped` still holds their home.
- Fix while patching: capture `local home = HomeRest(entry.Raid, target)` next to `rest` at line 1027 and pass `home` at line 1048.

---

## 9. `StartDig(entry, target)` timeline (1061-1136)

Triggered at 1277-1279 when `entry.Digger and dist >= DIG_RANGE_MIN (12) and now >= DigCooldownUntil and now >= StunUntil`.

1. `Digging = true`, `DigCooldownUntil = now + 8`, stop, `Send {Kind="Digging"}`. Return true.
2. `task.spawn`:
   - Anchor the root. Set `entry.Underground = true` and **`SetAttribute("Underground", true)`** (1074-1076).
   - Sink `DIG_DEPTH` 6 studs over `DIG_DIVE` 0.6 s.
3. The goal is **re-read after the sink**: `target:GetPivot()` (1086). The emerge point is `reach = GrabReach - 1` from the cucumber, on the side the digger came from (1089-1092).
4. Travel underground at `DIG_SPEED` 18 studs/s, with mound puffs every 0.45 s. Breaks on `entry.Dead`.
5. Rise over 0.6 s (1113-1126). **Still Underground and immune until line 1127.**
6. `Underground = false` (attribute too), `Unanchor`, `Digging = nil`, `RepathAt = 0` (1127-1133).

**There is no separate surfacing capture.** On the next Tick (≤0.1 s later) the digger is 1 stud inside `GrabReach`, and line 1271 calls `Grab`. The target is still `entry.Target` unless it became invalid (1261). A digger is therefore damage-immune from line 1075 until 1127, and has at most about one tick exposed before it grabs.

---

## 10. Threat and income source

- **`IncomeOf(player)` (268-272)** returns `player.Data.CashPerSec.Value`:
  ```lua
  local function IncomeOf(player)
  	local data = player:FindFirstChild("Data")
  	local raw = data and data:FindFirstChild("CashPerSec")
  	return raw and raw.Value or 0
  end
  ```
  `CashPerSec` is a NumberValue that LeaderstatsService creates and writes (LeaderstatsService 129-134, 74-80).
  - Its value is the sum of the `Rate` attribute of every `PlacedCucumber`-tagged model with `Owner == UserId` that is a descendant of workspace.
  - That set includes dropped cucumbers in the lobby.
  - It is the **only** `CashPerSec` reader besides LeaderstatsService.
- **`ThreatOf(player, plot)` (1315-1320):**
  - `cucumbers = CucumbersOf(plot, UserId)` (256-266): tagged Models in `plot.Placed` with a matching Owner.
  - `score = ZombieCatalog.ThreatOf(cucumbers, income)`.
  - Returns `LevelOf(score), score, #cucumbers`.
- **`ZombieCatalog.ThreatOf` (180-185):**
  - `Σ CucumberThreat(c) + INCOME_WEIGHT(4) * log10(1 + income)`.
  - `CucumberThreat` reads **only** the `Zone`, `Mutations` (comma string), `Material`, `Golden` and `SizeTier` attributes. It is unaffected by `Rate`/`BaseRate`.
- **`LevelOf`:** `clamp(1 + floor(3.2 * log10(1 + score/2)), 1, 10)`.
- **`CountFor(level)`:** `clamp(round(2 + 0.7*level), 3, 9)`. That gives L1 3, L2 3, L3 4, L4 5, L5 6, L6 6, L7 7, L8 8, L9 8, L10 9, plus split children.
- **When threat is sampled:** at nightfall (`StartRaids` → `NewRaid`) and at every thief spawn (`SpawnThief` → `NewRaid(..., true)` → `ThiefVariety(level)`).
- **PLAN change:** point `IncomeOf` at the unboosted `CucumberBaseCashPerSec`, keeping a 0 fallback. **Do not** keep reading `Data.CashPerSec` once it includes pet income or buffed Rates.

---

## 11. `ServerStorage.ZombieAPI` (Folder of BindableFunctions)

Created at lines 184-195. Any existing `ZombieAPI` is **destroyed and recreated** when the script starts. The Folder is parented before the `OnInvoke`s are assigned at 876-897, but there are no yields in between.

| Bindable | Signature | Semantics |
|---|---|---|
| `Damage` | `(model, amount, source, attacker) -> ok:boolean, healthLeft:number` | See `DamageZombie` below. |
| `Zombies` | `() -> {Model}` | Returns a new array of every entry with `not Dead and not Shaded and not Underground and model.Parent`. **No owner filter**, and it covers night and day raids server-wide. **It includes `Hold` cutscene zombies** at the door. |
| `IsZombie` | `(model) -> boolean` | `entry ~= nil and not entry.Dead`. True for Shaded and Underground zombies too. |
| `Slow` | `(model, seconds) -> boolean` | `SlowUntil = max(SlowUntil, os.clock() + (tonumber(seconds) or 0.5))`. Walk speed × 0.45. |
| `Stun` | `(model, seconds) -> boolean` | `StunUntil = max(StunUntil, os.clock() + (tonumber(seconds) or 0.3))`. Walk speed 0; blocks *starting* a grapple or dig. **Does not block Grab.** |

### `DamageZombie(model, amount, source, attacker)` (849-875)
1. `entry = Zombies[model]` and `amount = tonumber(amount) or 0`.
2. **Refusals:**
   - No entry, `entry.Dead`, or `amount <= 0` → `false, 0`.
   - `entry.Shaded or entry.Underground` → `false, Humanoid.Health`.
   - Nothing checks the owner, `Hold`, the source, or the type of the attacker, beyond the hostility check below.
3. `Humanoid:TakeDamage(amount)`, `UpdateBar`, then `Flash`: every visible part turns red for 0.1 s.
4. Play "Hit Crunch" as a server `PlayFXAt`, at most once per zombie per 0.08 s.
5. `source == "Bat"` → `StunUntil += 0.3` (max).
6. **Hostility side effect** (865-872): when `typeof(attacker)=="Instance" and attacker:IsA("Player") and raid and not raid.Ended`:
   - `raid.Hostile[attacker] = true`.
   - The first time, `FireClient(attacker, {Kind="Hostile"})`.
   - From then on, every zombie in **that** raid swats that player out of the way.
   - This applies to *any* raid. The bat is not owner-filtered, so hitting a neighbour's zombie makes that neighbour's raid hostile to you.
7. If `Health <= 0` → `Kill(entry, source)`, which drops the carried load, splits, and runs the raid-end check. Return `true, Health`.

**The amount must be validated by the caller.** `NaN` passes the `amount <= 0` check because the comparison is false. `math.huge` kills outright. Fractional amounts are fine; the laser deals 2.5 per tick.

Source strings in use:
- ZombieRaidService: `"Barbed"` (line 947).
- DefenceService: `"Turret"`, `"Spikes"`, `"Catapult"`, `"Mortar"`, `"Tesla"`, `"Frost"`, `"Minigun"`, `"Laser"`.
- BatServer: `"Bat"`, passing the attacker as the fourth argument.
- The dev kill calls `Kill(entry, "Dev")` directly.
- Pets should call `Damage:Invoke(zombie, dmg, "Pet")` with **no fourth argument**.

### BatServer (StarterPack.Bat, 72 lines)
- `COOLDOWN 0.55`, `HIT_DELAY 0.18`, `RANGE 8` (+ root size), `CONE 65°`, `DAMAGE 35`.
- Sweeps `api.Zombies:Invoke()` and calls `damageFn:Invoke(target, DAMAGE, "Bat", attacker)` (line 64). **No owner filter.**
- Lazily `WaitForChild("ZombieAPI", 120)` (28) and caches `api`. After a ZombieRaidService restart that reference is stale.

---

## 12. Querying "combat is live" for a player

Nothing public exists today.

| Candidate | Verdict |
|---|---|
| `Raids[player]` / `DayRaids[player]` | Script locals; not reachable from other scripts. |
| Plot attributes (`RaidAlive`/`RaidOver`) | Unreliable; see section 3. |
| Zombie `Owner` attributes in `workspace.Zombies` | Missing during the first 1.2 s of the cutscene. Dying models linger with `Dead=true`. |
| `HasLiveThief(player)` (1535-1542) | Correct for thieves, but local. |

Recommended read-only addition in ZombieRaidService, created in the same block as line 194:
```lua
-- CombatState(userId) -> raidLive:boolean, thiefLive:boolean   (read-only, primitives)
local function CombatLive(player)
	local r = Raids[player]
	local raidLive = r ~= nil and not r.Ended and not r.Over
	return raidLive, HasLiveThief(player)
end
```
- Optionally mirror it as a Player attribute (for example `Defending`) so PetService and the client can subscribe without polling.
- Set the attribute where a raid is stored: `Raids[player] = raid` (1444, dev 1655) and `DayRaids[player] = raid` (1549).
- Clear it at `EndRaid` (1361-1365), at the day branch of `CheckRaidEnd` (696), and where `raid.Over` becomes true (701, 785).
- PetService should additionally lock whenever `workspace.CyclePhase ~= "Day"`. The phases are `"Day"`, `"Night"` and `"PreparingDay"`.

**`GetTargetInfo` is needed for PetCombatService.** Suggest a batch call made once per 0.2 s scan instead of N invokes:
```lua
-- TargetInfos(ownerUserId?) -> { {Model=, Owner=, State=, Carrying=bool, Grappling=bool, Digging=bool, Day=bool, Health=, MaxHealth=, Position=Vector3}, ... }
```
- Filter it like `Zombies()`: not Dead, not Shaded, not Underground, parented.
- Return primitives only. Bindable returns are deep-copied; Instances pass by reference.

---

## 13. DefenceService

- **Loop:** Heartbeat with an accumulator, `TICK = 0.05` (65, 811-841).
  - `now = os.clock()`.
  - Calls **`ZombiesAPI:Invoke()` once per tick**, only when at least one defence is registered.
  - Each defence runs inside a `pcall`.
  - Broken defences (`Broken` attribute) idle.
  - Splash projectiles call `ZombiesAPI:Invoke()` again at impact (473, 577).
- **Registration:** tag `"PlacedBuild"` with `BuildKey` in `KINDS` (94, 207-342, 844-848). `def.Owner = model:GetAttribute("Owner")` is stored at line 214 and **never used**.
- **No owner filtering:** every tower shoots the nearest zombie from any raid in range, including a neighbour's raid near the plot border. **Pets must not copy `nearestZombie` as-is.**
- **Range:** `nearestZombie(zombies, from, range, minRange, skip)` (107-117) uses **3D** `(root.Position - from).Magnitude`. `alive(zombie)` (119-122) checks Parent, `Humanoid.Health > 0` and the `Dead` attribute (Minigun only). The Frost check uses flat XZ distance.
- **Damage calls:**
  - All use `DamageAPI:Invoke(target, dmg, "<Source>")` with **3 arguments, no attacker**. For example the Turret at line 398, the Tesla at 674 with rounded damage, and splash via `math.floor(dmg*(1-0.5d/r)+0.5)`.
  - Deadlines are `def.NextFire = now + Interval`, set when the shot fires and not accumulated. The effective period is therefore Interval + up to 0.05 s, with no catch-up.
- **FX:**
  - Everything is **server-created, replicated instances**. `Tracer(from, to, color, thickness, life)` (362-367) builds a `neonPart("Tracer", Vector3(th, th, len), CFrame.lookAt(mid, to), color, life or 0.07)` with a `PointLight(range 8, brightness 3)`. `neonPart` (171-186) is Neon, Anchored, no collide, query or touch, no shadow, parented to workspace, and Debris-removed.
  - The Turret colour is `BarrelMuzzleGlow.Color`, falling back to `(77,210,255)`. The muzzle alternates `def.Side * 0.5` studs.
  - `Bolt(...)` (622-640) is a jagged chain of Tracers.
  - Sounds go through `SoundController.PlayFXAt`, e.g. `"Zap"` at Volume 0.45 and RollOff 50.
  - **There is no FX remote to reuse.** The new `PetEffects` remote is genuinely new. Copy the Tracer and Zap look client-side.
- **`PlayFXAt` on the server:** its doc says "Client Use Only", but on the server it creates a replicated Attachment and Sound in Terrain. It is throttled by a **server-wide `MaxConcurrent = 3` per sound name**. Pet sounds should be client-side via `PetEffects`, or they will compete with turret "Zap" and zombie "Hit Crunch".
- **Constants (lines 66-76):**

| Defence | Range | Interval | Damage | Other |
|---|---|---|---|---|
| TURRET | 45 | **0.45** | **12** (≈26.7 DPS) | TurnRate 540°/s, Cone 8°, pitch -25°..45°, RestAfter 2 |
| TRAP | 8×8 plate, Height 6 | 0.4 | 7 | Slow 0.6 s |
| CATAPULT | 60 (min 8) | 4.5 | 45 | Radius 9, Flight 1.3 |
| MORTAR | 75 (min 12) | 3.6 | 60 | Radius 10, Flight 1.7, TurnRate 240°/s |
| TESLA | 28 | 1.5 | 18 | Chain 3 hops, ChainRange 12, falloff 0.75 |
| FROST | Radius 24 (flat) | Tick 0.5 | Chill 2 | Slow 0.8; FreezePulse stun 1.5 s every 10 s when the attribute is set; ShowAura false |
| MINIGUN | 42 | 0.08 | 4 (50 DPS) | Spin-up 1.2 s, Cone 6° |
| LASER | gate volume | Tick 0.1 | DPS 25 | |

The PLAN's "Turret baseline 12 damage / 0.45 s" is **confirmed**.

---

## 14. Zombie varieties (ZombieCatalog 93-143)

| Variety | MinLevel | Health | Speed | Scale | Flags |
|---|---|---|---|---|---|
| Rotten Shambler | 1 | 60 | 8 | 1 | thief |
| Scrawny Runner | 2 | 45 | 13 | 0.9 | thief |
| Plague Shambler | 3 | 110 | 9 | 1.05 | thief |
| Blitz Runner | 3 | **1** | 26 | 0.8 | |
| Bloated Brute | 3 | 200 | 7 | 1.35 | |
| Feral Runner | 4 | 80 | 15 | 0.95 | thief |
| Shadow Stalker | 4 | 90 | 11 | 1 | Shadow |
| Mole Digger | 4 | 100 | 9 | 0.95 | Digger |
| Iron Brute | 5 | 350 | 7.5 | 1.4 | |
| Hook Lurker | 5 | 120 | 12 | 1.05 | Grapple, range 24 |
| Bloated Splitter | 5 | 240 | 6.5 | 1.35 | Split → 3 Spawnling |
| Toxic Shambler | 6 | 180 | 10 | 1.1 | |
| Blood Runner | 7 | 130 | 17 | 1 | |
| Lava Brute | 8 | 550 | 8 | 1.5 | |
| Lightning Runner | 8 | **1** | 32 | 0.8 | |
| Void Wraith | 8 | 200 | 12 | 1.1 | Shadow |
| Tunnel Fiend | 8 | 220 | 11 | 1.05 | Digger |
| Void Shambler | 9 | 300 | 11 | 1.15 | |
| Chain Reaper | 9 | 300 | 13 | 1.3 | Grapple, range 32 |
| Gorged Splitter | 9 | 450 | 7 | 1.5 | Split → 3 Goreling |
| Neon Runner | 10 | 220 | 19 | 1 | |
| **Titan Brute** | 10 | **900** | 8.5 | 1.7 | always in a level-10 wave (hardest unlocked) |
| Spawnling (child) | 99 | 20 | 18 | 0.6 | |
| Goreling (child) | 99 | 35 | 20 | 0.65 | |

Catalog timing constants:
- Shadow phasing: `SHADOW_VISIBLE 2.5`, `SHADOW_HIDDEN 5`, `SHADOW_TRANSPARENCY 0.7`. While a Shadow is shaded, pets cannot hit it; it is invisible to the API about 67 % of the time unless it is carrying.
- Grapple: `GRAPPLE_RANGE 24`, `HOOK 0.25`, `PULL 0.6`, `CARRY_SPEED 1.15`.
- Digger: `DIG_RANGE_MIN 12`, `DEPTH 6`, `SPEED 18`, `DIVE 0.6`, `COOLDOWN 8`.
- Raid: `STEAL_LIMIT 3`, `MAX_LEVEL 10`.

---

## 15. Where TryBlockTheft goes (PLAN 4.4)

Assumes `PetBuffService` is a ServerStorage ModuleScript. ZombieRaidService is a Script in the same server VM, so it can `require` the module and share its state. Resolve it **lazily with a pcall**, because start order between Scripts is arbitrary, and treat "not available" as "not blocked".

`TryBlockTheft` must use PetBuffService's own clock for expiry and grace. **Do not pass Tick's `now`**, which is `os.clock()`, if PetBuffService keeps absolute `os.time()` or `GetServerTimeNow()` expiries.

Suggested helper, placed near `Grab`:
```lua
-- returns true when a pet shield (or its 1.5 s grace) denies this theft attempt
local function TheftBlocked(entry, model)
	local ok, blocked = pcall(PetBuffTryBlock, model, entry.Model) -- sync, non-yielding
	if ok and blocked then
		entry.Target = nil
		entry.StunUntil = math.max(entry.StunUntil, os.clock() + 0.8)
		return true
	end
	return false
end
```

### Point 1: ordinary Grab
The guard goes **inside `Grab`**, after the validity returns and before any mutation. This one guard covers both call sites (1271 and 1048), and therefore the digger surfacing too.
```lua
522 local function Grab(entry, model, restCFrame)
...
527 	local torso = entry.Model:FindFirstChild("UpperTorso")
528 	if not torso then return false end
    -->> insert: if TheftBlocked(entry, model) then return false end
529 	local hbCF = hitbox and hitbox.CFrame or model:GetPivot()
531 	local carry = {Model = model, Rest = restCFrame or HomeRest(raid, model), ...
532 	if raid and raid.Dropped then raid.Dropped[model] = nil end
533 	CollectionService:RemoveTag(model, PLACED_TAG)
534 	model:SetAttribute("StolenBy", entry.Model.Name)
```
Placing it after 526-528 means a Grab that would fail anyway never consumes a charge. On `false`, Tick line 1271 already sets `entry.Target = nil` and returns.

### Point 2: before the grapple pull
There are two valid anchors. **The post-hook anchor is preferred** because it reuses the existing cleanup.
- **(a) Post-hook, preferred.** Line 1029 reads:
  ```lua
  1029 		local ok = not entry.Dead and target.Parent and CollectionService:HasTag(target, PLACED_TAG)
  ```
  Change it to `... and not TheftBlocked(entry, target)`.
  - With `ok=false`, the pull never starts.
  - Lines 1043-1046 destroy `GrappleRope`, `GrappleA` and `GrappleB` and clear `Grappling`.
  - Lines 1049-1050 `PivotTo(rest)`, which is a no-op because nothing moved.
  - The whole attempt ends; the hook visibly flies, then the shield pops.
- **(b) Pre-side-effect.** After `if not primary then return false end` (1000) and before `entry.Grappling = true` (1001).
  - If blocked, **return true**, meaning the tick is handled. Returning false would let Tick fall through to `Navigate`/`StartDig` in the same tick.
  - No rope is created at all.

### Point 3: final grapple capture (shield applied mid-pull)
This is covered automatically by the Point 1 guard inside `Grab` at line 1048:
```lua
1047 		if ok and not entry.Dead then
1048 			if not Grab(entry, target, HomeRest(entry.Raid, target)) then target:PivotTo(rest) end
```
- On denial the existing `target:PivotTo(rest)` restores the **pre-pull** pose.
- The beam and anchors were already destroyed at 1043-1045.
- `TheftBlocked` clears `entry.Target`. Without that the grappler keeps the target and re-hooks after about 0.2 s, once its 1.05 s stun lapses.
- Also fix the `HomeRest`-after-pull bug from section 8 here.

### Point 4: digger surfacing
There is no dedicated capture. The digger surfaces (1127-1133) and the next Tick hits line 1271 → `Grab` → the Point 1 guard. **Do not guard `StartDig`.** Burrowing toward a cucumber is not an attempt (PLAN 4.4 item 5).

### Behavioural caveat of the live AI
- After a block, `NearestCucumber` re-picks the same, nearest cucumber on the next tick. `Grab` ignores `StunUntil`.
- So the blocked zombie retries every 0.1 s. During the 1.5 s grace each retry is rejected without consuming a charge, and **once grace ends it grabs**, unless another charge exists or the zombie died.
- In effect, a Guard buys about 1.5 s of pet and tower fire against an adjacent zombie.
- If a longer deterrent is wanted, add a per-entry ignore to `NearestCucumber`, for example `entry.AvoidModel`/`entry.AvoidUntil`. That goes beyond the PLAN and is an orchestrator decision.

### Buff clearing on an actual steal
Clear buffs at `Escape`, before `carry.Model:Destroy()` (line 770). Also consider the `RestoreCarry` destroy branch at 586-589.

Do **not** clear on tag removal. `Grab` removes the tag at 533, but a Kill → `RestoreCarry` re-adds it at 613 on the same Instance. Deciding whether Yield or Haste survive grab → save is a CONTRACTS decision; the absolute expiry keeps ticking.

---

## 16. PLAN section 2 claims versus the live code

- **Confirmed:**
  - ZombieRaidService owns targets, theft, grapple, dig, damage, drops and lifecycle, and exposes `ServerStorage.ZombieAPI`.
  - DefenceService uses `ZombieAPI.Zombies` and `Damage` (plus `Slow`/`Stun`).
  - Turret is 12 damage / 0.45 s.
  - Issue 6: `IncomeOf` reads `Data.CashPerSec`, which feeds `ZombieCatalog.ThreatOf`.
  - Issue 7: the 4th argument, only when it is a `Player` Instance, makes the raid hostile.
  - Issue 8: grapplers `PivotTo` the cucumber before the final `Grab`.
  - Issue 10: nights are 45 s by attribute. The DayNightCycle header (line 5) and its default (line 57) still say 10. ZombieRaidService's header (line 46) correctly says 45.
  - Section 6: zombie `Owner` equals the raid owner's UserId, a number; day thieves carry the targeted player's UserId.
  - Titan Brute has 900 HP.
  - Dead, Shaded and Underground zombies are filtered by `Zombies()` and refused by `Damage`.
- **Missing or contradicted:**
  - (a) PLAN 6: "reuse current state names" - there is **no grappling state name** (`State` stays `"Seek"`), so `GetTargetInfo`/`TargetInfos` is **required**.
  - (b) PLAN 4.4: "recoils/stuns for 0.8 seconds through the existing API" - `ZombieAPI.Stun` exists but **does not stop `Grab`**, and there is no knockback or recoil API for zombies.
  - (c) PLAN 4.4 item 3: "restore the cucumber to the correct recorded rest pose" - the live code already restores `rest` on a failed final Grab, but **the grapple's `carry.Rest` is the pulled pose** (the line-1048 bug).
  - (d) Towers do **not** filter by owner (`def.Owner` unused), and the bat is not owner-filtered either. That differs from the pet rule "only the owner's raid".
  - (e) The ZombieCatalog header (line 55) lists only "Damage / Zombies / IsZombie"; `Slow` and `Stun` also exist.
  - (f) PLAN 4.4 item 6 mentions a "kill reward"; **no kill reward exists** in the live code.
  - (g) There is no existing combat-lock query. The plot `Raid*` attributes are stale after Dawn and are published even for players with no cucumbers.
  - (h) `ZombieAPI.Zombies()` includes cutscene (`Hold`) zombies at the lobby door. They are harmless to pets only because of the range check.
