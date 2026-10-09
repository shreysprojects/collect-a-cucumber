# GamingDesk (package HomeOffice, 2026-09-24)

A new **Home** build: a battle station with its gaming chair included. It is made from primlib parts, so no asset
upload is needed.

| Key | Size (w x h x d) | Parts | Cost | Behaviour |
|---|---|---|---|---|
| `GamingDesk` | 7.2 x 5.35 x 6.77 (desk 7.2 x 3.1 x 3.4, chair in front) | 89 | 2000 | chair seat "Game" opens a PLAYABLE runner (CUKE RUN), the monitor mirrors the real run, RGB, a chair that swivels |

**2026-09-24 update (user: "make the gaming desk make u play the actual game instead of just show a video (the cuke
run thing)").** CUKE RUN is now a real endless runner. The person in the chair plays it in a GUI. Every other
player's monitor re-simulates that exact run from the inputs the server relays. The auto-playing version survives
only as the attract loop (nobody seated). The sections "What it does", "How to test" and "Known limits" below
describe the new version.

## Files
* `models/build_GamingDesk.py` produces `models/out/GamingDesk.parts.json`.
* Renders: `models/renders/GamingDesk_front.png`, `_three.png`, `_back.png`.
* `src/behaviours/server/GamingDesk.lua` goes to `ServerStorage.FunBehaviours.GamingDesk`.
* `src/behaviours/client/GamingDesk.lua` goes to `ReplicatedStorage.FunBehavioursClient.GamingDesk`.
* Headless test: `tests/HomeOffice/` (`py gen.py`), shared with the GrandfatherClock. Since the fix pass
  (2026-09-24) the desk has its own file, `tests/HomeOffice/gamingdesk.luau`, run in a second Luau process. It
  replaced the stale block of `tests.luau` that expected the self-playing desk (`server.Score`). See "How to test".

## Look
The desk is black with a red-trimmed grey desk mat, on black Z-frame legs with red side stripes. An RGB strip runs
under the front edge.

On the desk:
* **Monitor.** A big, curved-ish monitor made of a 16:9 centre panel and two wings turned 20 degrees toward the
  player. It has a V-foot and a grey neck, and the back housing carries an RGB ring.
* **Keyboard and mouse.** The keyboard has three key rows and RGB underglow. The mouse has an RGB stripe.
* **Other items.** Two speakers (woofer and tweeter) and a green can of cucumber soda.
* **Tower PC.** It sits at the viewer's right end. It has a glass side panel that shows the GPU with an RGB edge,
  an RGB cooler ring, RGB RAM and a navy motherboard. The front has two RGB fan rings and an RGB light strip.

In front of the desk is a racing-style chair on a five-star base. It is black with red bolsters, wings and lumbar
pillow, a black headrest, and a green cucumber logo on the back of the backrest. It ships turned 32 degrees, as if
someone just got up.

The part budget is 89, just under the 90 allowed for "big appliances". It counts as one build even though it is a
desk, a PC and a chair.

## Parts and pivots the behaviour relies on (authored frame, scale 1)
* `Pivot_Seat` (0, 2.12, -1.92) is the chair's cushion top in the **sitting** pose. The server puts its Seat here,
  facing authored **+Z** (the desk).
* `Pivot_ChairSwivel` (0, 0, -2) is the vertical swivel axis.
* The `Swivel*` parts (lift, mechanism, pan, seat, bolsters, back, wings, headrest, lumbar, logo, armrests) turn
  together. They ship at `State_ChairIdleYaw` = 32, applied as CFrame.Angles(0, rad(yaw), 0) about the axis.
  The sitting pose is `State_ChairSitYaw` = 0. `ChairBase`, `ChairLeg1..5`, `ChairWheel1..5` and `ChairSleeve`
  never move.
* **Collision (fix pass 2026-09-24).** Every `Swivel*` part is `CanCollide = false`. The client swings these
  anchored parts through the space the gamer has just left: the spin-out is 392 degrees in 1.6 s, peaking near
  490 degrees a second. A collidable backrest would shove or fling that player's own client-simulated character.
  This also makes server and clients agree on the chair's collision, since the swivel is client-only.
  The five-star base, legs, wheels and sleeve (up to 1.2 studs) stay solid, so the chair still blocks feet but
  you can walk through the seat and back. The Seat from `ctx:Seat` never collides. The headless test checks both.
* The screen panels are `ScreenC`, `ScreenL` and `ScreenR`: Neon Blocks whose front face points at the player.
* `ScreenArt*` is the static preview picture on the panels: green ground strips, a cucumber hero and a coin. The
  client's local screens cover it. It still shows in the build menu and while the build is Broken.
* The `RGB*` Neon parts are recoloured by the client: `RGBDeskFront`, `RGBMonitorBack`, `RGBKeyboard`, `RGBMouse`,
  `RGBGpu`, `RGBCooler`, `RGBRam`, `RGBFan1/2` and `RGBTowerStrip`.
* `Pivot_RGBGlow` (under the desk) is where the rainbow PointLight sits. `Pivot_Keys` is where keyboard clacks
  come from. `Pivot_Monitor` is the centre of the centre screen.
* Model attributes: `Cost` 2000, `DisplayName` "Gaming Desk", and the two `State_Chair*` angles.

## What it does
### Server (`src/behaviours/server/GamingDesk.lua`)
`ctx:Seat` puts one invisible Seat named **`GamingDeskSeat`** (1.8 x 0.4 x 1.8) on `Pivot_Seat`, facing the desk.
Its prompt is **"Game"** (object "Gaming Desk", distance 8). Anyone may play.

**State:**
| Attribute | Meaning |
|---|---|
| `Fun_Player` | The gamer's UserId. 0 means nobody; -1 means a humanoid that is not a player, which gets no run. |
| `Fun_Seed` | The course seed of the current or last run (0 = none yet). |
| `Fun_Since` | `Kit.Now()` when that run started. Sim time 0 is `Since + READY` (1.6 s). |
| `Fun_Ended` | `Kit.Now()` when the last run ended. A run is **live** while `Since > Ended`. |
| `Fun_EndTick` | The ended run's last sim tick, taken from the gamer's `Over` (0 = not known, e.g. the run ended by the leave grace or by going quiet). The monitors' replays stop exactly there. `Ended - Since` is later, because it includes the network delay. Reset to 0 when a run starts. |
| `Fun_Final` | That run's score. 0 means no score, or one that failed the checks. |
| `Fun_Best` | The desk's best. It now survives a move, break or mend of the same build (a weak table keyed by the model), but not a server restart. |

**Runs.** A run starts (new seed and `Since`) when a player sits down, and again on the client's "Again" action.
**Actions** (`B.ActionRange` = 200 so onlookers can send "Sync"; everything else checks that the sender is the gamer):
* `Input` `{s, t, k}` or `{s, e = {{t, k}, ...}}`. `k` is `jump`, `jumpUp`, `duck` or `duckUp`; `t` is the sim time
  (a whole number of ticks / 120). Each event is checked: the gamer, this seed, a known kind, ticks in order, not
  ahead of the server's clock (+2 s), at most 24 per message. Accepted events are stored as codes `tick * 4 + kind`
  (up to 6000 per run) and relayed to everyone with `ctx:Fire("Input", {s, c, n})`, where `n` is the stored count
  after this batch (-1 once the list is full).
* `Over` `{s, score, seconds}`. Sent at the crash, or when the gamer leaves mid-run (the run so far counts). The
  score counts only if **seconds >= 2**, seconds <= the server-measured run time + 2 s, and
  **score <= seconds x 80 + 150**. Distance gives at most 72 / 3 = 24 points a second. Coins give at most one 50 per
  obstacle gap, and a gap is at least 0.95 s of running, so about 53 a second. The bot below peaks at 35 a second.
  A valid score sets `Final`, `Best` and `Ended` as before (the monitor still shows NEW HI-SCORE!). Anything else
  ends the run with Final 0. Whenever the time itself is possible (0 < seconds <= run time + 2 s), `EndTick` is set
  to seconds x 120, even if the score does not count (for example an EXIT in the first 2 s).
* `Again` (the seated gamer, run not live, 0.5 s after it ended) starts a new run.
* `Sync` `{s}` answers that one client with the whole list, `ctx:FireTo(player, "Events", {s, c, n})`. At most one
  answer per player per second.
* `Leave` destroys the seat's `SeatWeld` if the sender is the occupant (EXIT stands them up).

**Ending a run.** Getting up ends a live run after 0.75 s without a score; the client's `Over` normally arrives
first. A live run with no input for 12 s also ends without a score. A real run needs a press every few seconds, so
this only catches a client that stopped talking. There is still no economy impact: the score is only drawn.

### Client: the game (`CukeRun` ScreenGui, the gamer only)
* **Opening.** The GUI opens when `Fun_Player` is the local player **and** `Humanoid.SeatPart` is the
  `GamingDeskSeat`. It opens once per sitting.
* **Look.** It uses the arcade's style: a dark desk-coloured panel with red trim and a title plate whose edge runs
  through the rainbow like the RGB. It has FredokaOne white text with dark strokes, green / red HUD buttons, a red X,
  and a UIScale fit to the viewport. It is a ScreenGui with `IgnoreGuiInset` and `ResetOnSpawn = false`.
* **Game view.** 880 x 360 design px, 88 x 36 art px at 10 px each. It shows the monitor's own pixel scene, built
  by the same `NewScene` and drawn by the same `DrawWorld` function. Over it sit a HUD strip (SCORE, coins, HI), a
  READY? / GO! countdown with a hint, and a transparent `TapArea` button covering the whole view. Below the view are
  big **DUCK** and **JUMP** buttons and the key help.
* **Controls:**
  * **Jump:** Space / W / Up / pad A / DPadUp, a click or tap on the game view, or the JUMP button. Hold for a
    higher jump: a tap peaks at 8 px, a full hold at about 15 px (the hero is 10 tall).
  * **Duck:** S / Down / pad B / DPadDown / left stick down, or the DUCK button. It passes under the flying drones.
    In the air it makes the hero fall fast.
  * **Game over card:** PLAY AGAIN (Space / Enter / pad A) or EXIT (pad B).
  * **Exit:** Backspace, the X or the EXIT button.
  * **How keys are captured.** All movement, jump, confirm and pad keys are bound with
    `ContextActionService:BindActionAtPriority` at `High + 100` and return Sink. The PlayerModule controls are
    disabled, which also hides the touch jump button and thumbstick. So nothing can make the avatar leave the
    chair, and everything is restored on close.
* **Closing.** The GUI closes on EXIT (the client jumps out, sends `Leave`, and sends `Over` if mid-run), on the
  seat being lost for 0.6 s, on walking more than 20 studs away, on death, or when the behaviour stops.
* **Gameplay.**
  * The run speed ramps from 34 to 72 px/s over 4000 px. Distance scores 1 point per 3 px; a coin is +50.
  * Obstacles: crates, spike blocks and slimes; drones from 500 px (duck!); double crates from 1500 px (v >= 48).
  * The gap between two obstacles is always at least a full jump's airtime plus a reaction time (0.95 s of running
    at the current speed), plus up to 0.9 s more at random.
  * The hit boxes are a little smaller than the sprites.
  * A jump pressed up to 0.1 s before landing jumps on landing.
  * A crash shows a thump, a shake, a red flash and dizzy X eyes. After 0.8 s the card shows the score, BEST (this
    session), a "NEW DESK RECORD!" / "NEW BEST!" tag and DESK HI.
* **Simulation.**
  * It is deterministic and runs at a fixed 120 ticks a second. The course comes from `Random.new(Fun_Seed)`,
    generated lazily in one fixed order. The hero only needs + - * / and comparisons, so every client computes the
    same bits.
  * **The clock is the server's (fix pass 2026-09-24).** The gamer's run steps up to
    `Kit.Now() - Fun_Since - READY`, the same clock every monitor replays against. A hitch on the gamer's client
    therefore skips time: the ticks it missed run at once on the next frame (at most 400 a frame), with no sounds.
    It used to pause the run instead (at most 0.1 s of each frame counted). That put the gamer permanently behind
    the spectators, so after one big hitch every later input reached them too late: rollbacks and false GAME OVERs
    for the rest of the run. A GUI that opens after READY has run out also starts mid-run now, for the same reason.
  * Presses and releases are stamped with the tick running **now** on that clock (never before the sim's next
    tick or the previous event) and played at once. Stamping with the sim's next tick would put a press made
    during a hitch in the past.
  * The client sends them batched: at most one message every 0.15 s, 24 events each. That keeps it well inside
    the framework's 12 actions a second.
  * `Over` is resent every 1.5 s, up to 4 times, while the server still has the run live.

### Client: the monitor (every client)
* **Scene.** The pixel scene is the same as before, now with drones, double crates, a ducking pose and dizzy eyes.
  It is drawn with `DrawWorld`, shared with the GUI.
* **Attract** (nobody playing): the old self-playing loop, still a pure function of `Kit.Now()`, with the title,
  SIT TO PLAY and HI.
* **Ready:** READY? / GO!.
* **Run:** the actual run, with SCORE, P1 name and COINS.
* **Over:** the crash frozen, GAME OVER, the score and NEW HI-SCORE!.
  * While the gamer stays seated it alternates with "PLAY AGAIN?".
  * After they get up it lasts 4 s past `Ended`.
* **Whose simulation it draws:**
  * The gamer's own monitor draws the GUI's simulation directly.
  * Every other client replays it. The first time it sees the run's seed, it creates the replay from the course
    seed. It appends the relayed codes; the count `n` detects a gap, which triggers a `Sync`. A client that did not
    see the run start (streamed in, joined late) asks for `Sync`, and draws nothing new until the list arrives.
  * The replay runs **0.3 s behind** real time, so inputs normally arrive before they are needed. It checkpoints
    every 60 ticks and keeps 40 checkpoints. An event that arrives late rolls back to the checkpoint before it and
    re-simulates.
  * It advances at most 400 ticks per drawn frame. A late joiner therefore fast-forwards about 100 s of run a
    second.
  * **An ended run** is replayed up to `Fun_EndTick`. If the replay already ran past it (the inputs stopped and
    the end had not arrived yet, which happens when the round trip is over 0.3 s), it rolls back to that tick. So
    no monitor shows a crash or coins after an EXIT that the gamer never had. Without an EndTick the old limit,
    `Ended - Since - READY`, is used.
  * When the GUI closes, its run is handed to the monitor with its full list.
* **Sounds** (3D, within 45 studs): a keyboard clack (`Sfx.Click`) for **every real press** (the random clacks are
  gone), `Sfx.Coin` on pickups, `Sfx.Thump` at the crash, `Sfx.ArcadeBlip` on GO, and win / lose stings. The gamer's
  client skips the world stings because the GUI plays them in 2D.
* **Screen light:** the centre screen's SurfaceLight is 0.55 idle and 1.1 during ready / run. The screens redraw at
  30 fps within 150 studs.

### Client: RGB and chair
Unchanged. The RGB and the rocking use "playing" = seated, run live, and past READY.

**Cleanup** closes the GUI (unbinds, controls back on), puts the chair back as shipped relative to where the
Hitbox is now, and restores the RGB colours.

## Sounds
Only existing `FunAssets.Sfx` entries are used.

| Where | Sound |
|---|---|
| GUI (2D) | Jump = `ArcadeBlip` at 1.9x, duck = `Whoosh` quiet, `Coin`, crash = `Thump`, `ArcadeLose` / `ArcadeWin` on the card, `Click` + `ArcadeBlip` for READY? / GO! |
| World (3D) | `Click`, `Coin`, `Thump`, `ArcadeBlip`, `ArcadeWin`, `ArcadeLose` |

Wishes:
* `Sfx.KeyClack`: a short mechanical-keyboard click. Today it is `Click` pitched 1.3 to 1.9.
* `Sfx.Jump8bit`: a short 8-bit jump. Today it is `ArcadeBlip` pitched up.

## BuildCatalog suggestions
* `DEFAULT_CATEGORY.GamingDesk = "Home"`. The parts.json category is already "Home".
* `DEFAULT_COST.GamingDesk = 2000`. This is also on the `Cost` attribute.
* `SCALE`: leave it at 1. It is authored for the 6-stud avatar: seat top 2.12, desk top 3.1, monitor centre 4.4.
  Any scale works, because pivots go through `Kit.Pivot` and the screen resolution follows the panel size. This was
  tested at 1.0 and 1.3.
* The footprint is 7.2 x 6.8, which fits an 8 x 8 cell.

## How to test (Studio)
1. **Install.** Put the two `GamingDesk.lua` modules in place: server to `ServerStorage.FunBehaviours`, client to
   `ReplicatedStorage.FunBehavioursClient`. The model itself is unchanged.
2. **Place the desk.** `workspace.FunBuildLocal` gets the `GamingDeskScreenL/C/R` parts. The monitor shows the
   attract loop (CUKE RUN, SIT TO PLAY) and the RGB parts cycle.
3. **Sit down** with the prompt **"Game"**.
   * Server: `Fun_Player` is your UserId, and `Fun_Seed` (non-zero) and `Fun_Since` are set.
   * Client: `PlayerGui.CukeRun` appears and shows READY? then GO!.
   * Press Space during READY: nothing happens and you stay seated. That is the sink.
4. **Play.**
   * Space / W / Up / click / tap jumps; hold for higher. S / Down ducks under the purple drones.
   * The HUD SCORE and coin count rise.
   * A second client (Studio's multi-client test) sees the same run on the monitor, about 0.3 s behind. It shows the
     same obstacles, jumps, ducks, coins and crash, and a clack for every press.
5. **Crash.**
   * GUI: after 0.8 s the card shows the score, "NEW DESK RECORD!" on the first run, and DESK HI.
   * Server: `Fun_Final` = the score, `Fun_Best` updates, `Fun_EndTick` = the crash tick (> 0), and
     `Fun_Ended` > `Fun_Since`.
   * Monitor: GAME OVER alternating with PLAY AGAIN?.
6. **PLAY AGAIN** (the button, Space or Enter). A new `Fun_Seed` and a new course start, and `Fun_EndTick` goes
   back to 0.
7. **EXIT mid-run** (Backspace, X or EXIT).
   * You stand up, the GUI goes and the keys work again.
   * `Fun_Final` = the score so far (if the run lasted at least 2 s), `Fun_EndTick` = the tick you left at, and
     `Fun_Player` = 0.
   * The monitor shows GAME OVER for 4 s, with the hero frozen where you left (no crash, same COINS), then attract
     with HI. The chair spins back out.
8. **Late joiner.** Join, or walk into streaming range, mid-run. The client sends one `Sync` and the monitor
   fast-forwards to the live run.
9. **Break or move it while someone plays.** The GUI closes, the seat is recreated and the run ends when the
   occupant is unseated.
10. **Hitch (two clients).** While playing, make the gamer's client stall for about a second (for example drag
    its window). Afterwards the other client's monitor must still match the run: no GAME OVER that the gamer did
    not have, and no hero popping back into place on each jump. The gamer's hero keeps running through the stall.
11. **Headless test:** `py tests/HomeOffice/gen.py` (the GrandfatherClock's `tests.luau`, then
    `gamingdesk.luau`). The mock (`tests/HomeOffice/mock.luau`) now also has GUI buttons, ScreenGui, a seeded
    Random and Humanoid signals; `gamingdesk.luau` brings its own ContextActionService, `task`, `os.clock` and a
    mock network.
    * It printed **461 checks, 0 failed** (and the clock 4736, 0 failed). Pictures go to
      `tests/HomeOffice/screens/`: `desk_attract / ready / run / over / night` (the monitor) and
      `gui_ready / run / duck / over` (the gamer's panel).
    * **1. Simulation:** a planning bot survived 24 different courses of 150 s each (492 drones, 235 double
      crates). A replay fed late, bunched events rolls back to bit-identical results. The best rate is 35.2
      points/s, far inside the server's 80/s.
    * **2. End to end:** a server, the gamer's GUI driven by the bot through the bound keys, a spectator and a late
      joiner, with 80 ms latency each way and the framework's 12/s budget.
      * The spectator matched the gamer on every sampled tick (2587 of 2587).
      * **Two hitches on the gamer's client only** (0.6 s and 1.0 s: its GUI, Step and bot frozen while the server
        and the spectators run on). Afterwards: 885 of 885 ticks matched, 0 rollbacks, 0 false-crash frames, and
        the gamer's sim is on the server clock. The same test on the pre-fix client gave 18 rollbacks and 441
        false-crash frames.
      * The crash tick and score are identical on all three, and `Fun_EndTick` is the crash tick.
      * **EXIT with a slow network** (0.45 s each way): the replays ran 16 to 18 ticks past the exit before the end
        arrived, then went back to `Fun_EndTick` (not dead, COINS as at the exit). The same test on the pre-fix
        server left them 56 ticks past the exit.
      * Final / Best / record tag, PLAY AGAIN, a mouse click and touch DUCK, the forfeit score, death mid-run and
        cleanup were all covered. No actions were dropped and there were no warnings.
    * **3. The desk itself**, at x1 yaw 37 and x1.3 yaw -120: the seat (prompt, facing, on `Pivot_Seat`), the
      three screen slices (order, offsets, in front of the art), the attract hero never touching an obstacle,
      RGB cycling, the chair (faces the desk seated, spins out, settles on the shipped pose, `Swivel*` never
      collides, the base does), a sitter with no client (the replay crashes at the first obstacle; the leave grace
      ends the run with no score and no EndTick), night, a move while seated, and cleanup.
    * **Measured timing windows** (press times that clear one obstacle):

      | Speed | Crate (tap / held) | Spike (tap / held) | Slime (tap / held) | Double crate (held) | Drone (0.4 s duck) |
      |---|---|---|---|---|---|
      | v34 | 58 / 192 ms | 50 / 200 ms | 67 / 217 ms | - | 167 ms |
      | v50 | 117 / 250 ms | 108 / 258 ms | 133 / 283 ms | 150 ms | 242 ms |
      | v72 | 158 / 292 ms | 158 / 308 ms | 175 / 325 ms | 225 ms | 292 ms |

## Known limits / open questions
* **Not run in Studio yet.** It has only been run headless, with mocks for the Roblox classes.
* **The client decides the crash.** The server only checks that the score is plausible; it does not re-simulate the
  run. A cheater could post up to 80 points a second of fake score, but only onto this desk's HI display (no
  economy impact). The score is fully reproducible from the stored event list, so an exact server check (requiring
  the client module on the server and replaying the list) is possible later.
* **Late events can make the monitor pop.** If an input reaches a spectator after its replay passed that tick
  (the round trip plus up to 0.15 s of batching over 0.3 s), the monitor rolls back and the hero pops to the right
  place. The GUI itself never waits on the network. Hitches no longer cause this (see the next point).
* **Hitches are not forgiven.** The run follows the server clock, so a stall on the gamer's client does not pause
  it: the hero keeps running, and a long stall right before an obstacle can crash them. This is the price of every
  monitor staying in step (pausing made them drift for the rest of the run). A stall of 3.3 s or more is caught up
  over several frames.
* **Event cap.** Past 6000 stored events (about 50 minutes of hard play) inputs are still relayed but not stored.
  A client that joins after that cannot follow the run.
* **Best score.** `Fun_Best` is per build instance (it survives a move or break) and is lost on a server restart.
  `PersonalBest` on the card is per client session.
* **NPC.** An NPC in the chair (-1) gets no run; the monitor stays on attract.
* **Tap height.** Taps at the very start are low (8 px). The windows are fine for a normal press (80-120 ms, a
  medium jump), and the hint says to hold for higher.
* **Chair collision.** The chair's swivel is local on each client. Because no `Swivel*` part collides, that causes
  no collision mismatch. The cost is that players can walk through the upper chair; only its base blocks them.
