# DefenceFX: defence hit effects and idle effects (2026-09-24)

User request: "effects from defenses like freeze tower when hitting stuff can have blue particles on each enemy hit".

## Files
| File | Installs as | What it is |
|---|---|---|
| `FB\patched\DefenceService.server.lua` | `ServerScriptService.DefenceService` | A copy of `live\` with surgical edits (the diff is below). Every gameplay number and behaviour is unchanged. |
| `FB\src\DefenceFXClient.client.lua` | `StarterPlayer.StarterPlayerScripts.DefenceFXClient` (LocalScript) | Draws the hit effects and the idle effects. It needs `ReplicatedStorage.Modules.FunBuildKit`. |
| `FB\tools\defencefx_harness\` | not installed | Offline tests. Run `run.ps1`: 114 client checks and 122 server checks. |

## Review fixes (fix pass, 2026-09-24)
| Finding | Outcome |
|---|---|
| CRITICAL: one pooled attachment per style, moved to every hit of a batch. `Emit()` takes the position at render time, so every burst of a batch landed on the last zombie. | **Fixed.** Each style has a pool of up to `SLOT_MAX = 24` emission points (Attachment + its own emitters, made on demand). A point moves again only 2 Heartbeats (at least one render) after its last `Emit`. Past 24 hits of one style in one frame, the rest are skipped (counted in `BurstsSkipped`). The shatter IceBursts of several blocks in one frame use the same pool. The tests fire batches (3 frost, 3 mortar, 12 shatters, 30 tesla), and a whole-run check proves no point is ever moved before a render. With the guard switched off, 9 checks fail. |
| Part budget: crystals shared the full 60 parts with no cap. From 9 slowed zombies up they starved all debris; from 12 up they blocked the ice blocks. | **Fixed.** Crystals have their own cap (`CRYSTAL_MAX = 20`). Blocks may use the whole 60. Debris and the block's decorative spikes stop at 48 (`BLOCK_RESERVE = 12`). Crystals also stop at 40 total (`DEBRIS_MIN = 8`). A pulse calls `Encase` first and pops that zombie's crystals; no crystals grow inside a block. Crystals are grown after each batch, nearest zombie first. The first 3 zombies get all 5, later ones 2. A zombie 15+ studs nearer than the farthest holder takes that holder's crystals. When the debris budget is full, the oldest landed debris (older than 0.45 s) makes way, so every new hit still throws its shards. Test: 12 slowed zombies keep crystals at or under 20, spawn every shard on every tick, give crystals to the nearest zombies, and a pulse then makes 12 blocks. |
| Server: one global queue, `FireAllClients`, a shared 40 cap. Every client downloaded every raided base's hits, and other bases could push out your own. | **Fixed, needs orchestrator approval** (the brief said `FireAllClients`). Only `FlushFX` changed: each player gets the hits within `FX_RANGE = 280` studs of their HumanoidRootPart, at most 40 per player per tick, via `FireClient`. Players with nothing near, or no character, get nothing. The server-wide queue cap is now `FX_QUEUE_MAX = 400`. `HitFX` also ignores a non-Vector3 position. The call sites are unchanged. Tests: two players at two ends of the test raid each get only their own hits, a far player and a characterless player get nothing, and while a 60-zombie freeze floods one player at 40 per tick, the other still gets their hits in those same ticks. |
| Shadow zombies: a zombie chilled just before phasing out (`Shaded = true`) kept its Highlight, crystals or block for about 1 s. | **Fixed.** `StepZombies` releases the state of a `Shaded` zombie the same frame, as for a dead one: tint off, block shatters, crystals drop. `Play` gives a shaded zombie particles only, no new state. |
| `LASER_HOLD = 0.35` shorter than the real 0.27-0.33 s event gap plus jitter. The Highlight was re-made several times a second. | **Fixed.** `LASER_HOLD = 0.5`. The test sends laser hits 0.4 s apart and checks the same Highlight instance lasts the whole stay. At 0.35 that check fails. |

No finding was rejected.

## Server diff (live -> patched)
1. **Header:** a `HIT EFFECTS` paragraph. The FreezeTower line now says "ice effects on the zombie (DefenceFX client)".
2. **Services:** `local Players = game:GetService("Players")`.
3. **Config** (after `RANGES`): `FX_REMOTE = "DefenceFX"`, `FX_CAP = 40` (per player per flush), `FX_RANGE = 280`, `FX_QUEUE_MAX = 400`, `FX_MINIGUN_EVERY = 0.15`, `FX_LASER_EVERY = 0.25`, `FX_SLOW = {slow = true}`.
4. **Instances** (after `Sources`): find-or-create `ReplicatedStorage.Remotes` and the RemoteEvent `Remotes.DefenceFX`. This is the same pattern as ZombieRaidService and BuildService.
5. **Helpers** (after `puff`): the section `--..Hit effects (2026-09-24, DefenceFX)..--`.
   * `HitFX(kind, zombie, position, extra)` queues `{k, z, p, x}`. It drops the event once the queue holds `FX_QUEUE_MAX` events or when `position` is not a Vector3.
   * `HitFXEvery(...)` is a per-kind, per-zombie throttle with weak keys.
   * `FlushFX()`: for each player with a character, it collects the queued hits within `FX_RANGE` of their root, stops at `FX_CAP`, and calls `FireClient(player, list)` when the list is not empty.
6. **Damage sites.** Each one gets one added line:

   | Site | Call |
   |---|---|
   | Turret | `HitFX("Turret", target, to, {from = from})` |
   | Spikes | `HitFX("Spikes", zombie, <plate top under the zombie>)` |
   | `Splash()` (Catapult and Mortar, every zombie in the splash) | `HitFX(source, zombie, root.Position, {c = position})` |
   | Tesla, each hop | `HitFX("Tesla", current, to, {hop = hop})` |
   | Minigun, each shot | `HitFXEvery("Minigun", target, to, {from = from}, 0.15)` |
   | Laser, each tick | `HitFXEvery("Laser", zombie, root.Position, nil, 0.25)` |

7. **Frost:** the two per-zombie `puff()` calls and the `math.random() < 0.35` branch are gone.
   * The call is now `HitFX("Frost", zombie, root.Position, pulse and {slow = true, pulse = true, stun = FROST.PulseStun} or FX_SLOW)`.
   * One event carries both the slow and the pulse.
   * `StunAPI` and the orb-burst puff and sound are unchanged.
8. **Laser:** the `puff()` on the zombie is gone. The neon `LaserSpark`, its light and the buzz stay.
9. **Main loop:** `if next(Defences) == nil then FlushFX() return end`. This covers a shell or boulder still in the air when the last defence is sold.
10. **Main loop:** `FlushFX()` after the per-defence loop, so there is one flush per 0.05 s tick.

Tracers, bolts, boulder and shell flights, bursts and all sounds are untouched.

**Proven offline.** The harness runs the live and the patched script against the same 11 s raid, with every kind and a freeze pulse. The Damage, Slow and Stun calls are identical: every time, target, amount and source matches.

**Bandwidth.** An event is about 40-60 bytes. A player now gets only their own neighbourhood's hits. A busy base (16 zombies in a freeze field, plus a minigun and a laser) is about 50-100 events/s, so 3-5 KB/s for the players standing there, whatever the other bases are doing. The hard cap is 40 events per player per 0.05 s tick.

## Client: hit effects
The client plays each effect on the zombie's torso, at the place this client draws it. If `z` is nil (streaming, or already destroyed), it plays at `p`. Nothing plays more than 250 studs from the camera. No parts are made more than 140 studs from the camera; beyond that, the effect uses particles only, at half the count. A `Shaded` (phased-out) shadow zombie gets particles only.

| Kind | Effect |
|---|---|
| Frost (every 0.5 s chill tick) | Snowflake sparkles and small falling flakes, a mist puff, and 2 Ice WedgePart shards that fly, bounce and melt. A Highlight (fill 170,220,255 at 0.6, white outline) stays full until 0.8 s after the last hit, then fades over 0.5 s. Ice crystals are welded to the Head, both UpperArms, a second Head spot and the UpperTorso back, in that order: all 5 on the nearest zombies, 2 on the rest, at most 20 in all. They grow in, then fall off and melt 1.0 s after the last chill. |
| Frost pulse (`x.pulse`) | A translucent Ice block (the zombie's bounding box + 0.8/0.5/0.8, with 2 ice spikes) is welded to the root for `x.stun` s, then a big ice burst and 6 big shards. The block pops the zombie's crystals, and none grow while it is inside. At the end the block shatters into 8 flying shards and a burst. A zombie that dies or phases out while frozen shatters too. |
| Tesla | Cyan spark streaks, a glow sprite and a white flash Highlight for 0.15 s on every hop. |
| Laser | Red embers rise, with burn sparks and a smoke wisp. A red flickering Highlight stays while the hits keep coming (0.5 s hold). |
| Turret | Cyan impact sparks thrown back toward the gun (`x.from`) and a flash sprite. |
| Minigun | Small yellow sparks toward the gun and a dust puff (at most one event per 0.15 s per zombie). |
| Mortar | Each burst (`x.c`, drawn once however many zombies it hit) gets an expanding shockwave ring and a dust ring flat on the ground, plus dirt spray and 5 flying Slate chunks. Each zombie hit gets orange sparks, a glow and an orange flash Highlight for 0.35 s. |
| Catapult | Dust and chips at the zombie's feet, plus 3 flying Slate rock chips. |
| Spikes | Small red sparks and dust at the plate under the zombie. |

**Particles, one emission point per hit.** `Emit()` spawns particles where the emitter is when the frame renders. So each style keeps a pool of emission points in `workspace.Terrain`, each an Attachment named `DefenceFX_<Style>` with its own emitters. A pool grows on demand to 24 points. A point is reused only 2 Heartbeats after its last `Emit`, and particles are world-space (`LockedToPart` off), so particles already out never move.

**Part budget (60 parts in all):**
* **Ice blocks** may use all 60. The last 12 are kept for them.
* **Flying debris and the block spikes** stop at 48 total. When full, the oldest landed debris (older than 0.45 s) is removed to make room for a new hit's.
* **Crystals** have their own cap of 20 and stop at 40 total, which leaves debris at least 8 parts.
* **Highlights:** at most 12 of its own, because Roblox draws only 31 per client and build mode uses 2.
* Everything is Debris'd. Crystals and Highlights have a 30 s safety life and are rebuilt if they are still needed.
* The parts live in the local folder `workspace.DefenceFXLocal`, and one Heartbeat loop runs everything (frame count, debris, tints, idle).

## Client: idle effects on placed Defences builds
A placed Defences build is one with tag `PlacedBuild` and either attribute `Category == "Defences"` or a template in `ReplicatedStorage.PlaceableBuilds.Defences`. Idle effects run within 200 studs of the camera:
* **`Glow*` parts:** they pulse Transparency from base to base + 0.35 as a wave along the parts.
  * FreezeTower pulses over 2.8 s, TeslaCoil over 1.5 s, LaserGate over 1.2 s, and other builds over 2.4 s.
  * The base is the template twin's Transparency.
  * On sell, stream-out or move, a part gets its base back, but only if the value is still the one the client wrote.
* **`Pivot_Mist1..n` (FreezeTower):** a cold mist creeps outward from the tower at 1.6 particles/s per point.
* **`Pivot_Spark1..n`:** 2-4 tiny spark streaks every 0.25-0.8 s at a random point (one emitter per build, moved at most once per 0.25 s).
  * TeslaCoil sparks are cyan and LaserGate sparks are red.
  * An old model without Spark pivots uses `Pivot_ProngTip*` (TeslaCoil) or `Pivot_BeamLeft/Right` (LaserGate).
* **Broken:** everything stops the moment `Broken` becomes true.
  * A Transparency the server wrote (the 0.65 broken fade) is never pulsed over or "restored".
  * The effects restart 0.3 s after the build mends, moves, or a late Glow part streams in.

**Relies on these names and pivots:**
* **FreezeTower (rebuilt):** `Glow*` (31 parts) and `Pivot_Mist1..4`. The DefFreezeTower agent's notes confirm them.
* **LaserGate (rebuilt):** `Glow*` (20 parts) and `Pivot_Spark1..8`.
* **TeslaCoil:** any `Glow*` and `Pivot_Spark*`, with the ProngTip fallback.

The old MeshPart FreezeTower has no Glow parts or Mist pivots, so it gets no idle effects. Its hit effects work anyway.

## How to test (integrator)
1. Install the three pieces: the patched server source, the LocalScript, and FunBuildKit (already part of the framework).
2. Start a raid with `workspace:SetAttribute("ZombieDev", "raid:3")` next to a FreezeTower, a TeslaCoil and a LaserGate. Set `FreezePulse = true` on a placed FreezeTower to see the ice block (the pulse comes 10 s after it registers). **Stand at your base:** hits only reach players within 280 studs.
3. **Quick check without a raid, on the client:** `workspace:SetAttribute("DefenceFXTest", "Frost:pulse")`. The kinds are Frost, Frost:pulse, Tesla, Laser, Turret, Minigun, Mortar, Catapult and Spikes. It plays on the nearest zombie, or 14 studs in front of the camera. This hook sends one event, so for the per-hit points, watch a real raid with several zombies in a freeze field: each zombie must get its own blue burst.
4. **Numeric check:** the LocalScript's attributes update twice a second:
   * `LiveParts` (at most 60) and `Crystals` (at most 20)
   * `Highlights` (at most 12), `Tinted` and `IdleBuilds`
   * `Events`
   * `EmitPoints`: the pooled attachments made, at most 24 per style used.
   * `BurstsSkipped`: should stay 0 in a normal raid.
5. **Server check:** `ReplicatedStorage.Remotes.DefenceFX` exists, and the output has no `[DefenceService]` warnings.

## Sounds
None added: the server already plays Zap, Magic Shimmer, Big Thud and others. One optional wish: a short ice-shatter or glass-break sound for the ice block breaking.

## Known limits and open points
* **Orchestrator approval:** the server now uses `FireClient` per player (within 280 studs), not the brief's `FireAllClients`. Reverting means only `FlushFX` changes.
* **Hits at the range edge.** A player whose camera is zoomed far from their character can miss the rim of the range. The client draws up to 250 studs from the camera; the server sends up to 280 studs from the character.
* **Welded parts.** The crystals and the ice block are client-local, massless, non-colliding parts welded (WeldConstraint) to the server-owned zombie. They should ride the walk animation exactly.
  * The playtest has to confirm this. If they lag or drop, switch `StickTo` to anchored parts that the Heartbeat loop moves to `body.CFrame * offset`.
* **Engine behaviour taken from the review.** The render-time `Emit()` position comes from the reviewer's two DevForum threads, and the design also assumes one render per client Heartbeat. Neither was seen in Studio.
* **Highlight cap.** With more than 12 zombies tinted at once, the extra zombies get particles only and no Highlight.
* **Crystal counts.** A zombie that got 2 crystals while the scene was busy keeps 2 until its slow ends; it is not topped up to 5.
* **Two towers, one zombie.** When two FreezeTowers chill the same zombie in the same tick, the zombie gets one burst.
* **Merged pulse event.** A pulse is one event with `slow`, `pulse` and `stun`, not a second event. The contract allowed either.
* **Mortar ring needs a hit.** The shockwave ring is drawn from the hit events, so a shell that hits nobody shows only the server's own burst.
* **Harness limits.** The harness mocks the Roblox API, so it checks logic and numbers, not visuals.
  * Nothing was run in Studio (this package was files-only).
  * The first playtest should look at the particle sizes, colours and the ring orientation. The ring and dust ring use `VelocityPerpendicular` with a tiny upward speed so they lie flat.
