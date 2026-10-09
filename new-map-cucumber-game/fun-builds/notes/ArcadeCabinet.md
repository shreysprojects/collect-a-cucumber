# ArcadeCabinet - "CUCUMBER CATCH" (behaviour package, 2026-09-24)

Files
* `src/behaviours/server/ArcadeCabinet.lua` -> `ServerStorage.FunBehaviours.ArcadeCabinet`
* `src/behaviours/client/ArcadeCabinet.lua` -> `ReplicatedStorage.FunBehavioursClient.ArcadeCabinet`
* No model changes (behaviour only; the existing build at x1.25 is used as is).

## What it does
* **Prompt** "Play" (hold 0, E / ButtonX, 9 studs) anchored 1 authored stud above `Pivot_JoystickPivot`,
  parented to the Hitbox via an attachment. The server opens a session and sends `ctx:FireTo(player, "Open")`.
* **Game (client ScreenGui `PlayerGui.CucumberCatch`)**: a cabinet-styled panel (blue body, orange T-molding
  stroke, pink marquee title, red X). 3-2-1-GO, then items fall: 🥒 +1, a drawn golden cucumber +5 (at most one per
  3.5 s), 🧟 zombie heads (sideways wobble after ~15 s) and drawn rotten cucumbers (buzzing fly, fall faster) cost a
  life (3 lives, 0.9 s invulnerable blink). Difficulty ramps over 60 s (drop interval 1.0 -> 0.42 s, fall speed
  0.30 -> 0.78 field heights/s, hazards 18 -> 42 %), then the fall speed keeps creeping up (+0.6 %/s). "SPEED UP!" banner
  every 12 s, "STREAK x10!" every 10 catches in a row (display only, no multiplier). Pixel sparks + "+1/+5/OUCH!" pop
  text, basket squash, screen shake + red flash on hits. RenderStepped loop, dt clamped to 1/20 s.
  Controls: A/D, arrows, gamepad stick/d-pad, the two big side rails (hold; touch or mouse), or drag on the playfield.
  While open: PlayerModule controls are disabled (`GetControls():Disable()`), and the movement/jump/camera keys
  are sunk through ContextActionService at High+100, so the avatar stays put and the arrow keys don't turn the camera.
  GAME OVER card: score, personal best (per client session), cabinet HI, PLAY AGAIN (Space/Enter/pad A) and
  EXIT (Backspace/pad B). It closes on EXIT/X, when the player is > 20 studs away (`ctx:Near(20)`), on death, or
  when the build's behaviour stops (sold/moved/broken/streamed out).
* **Score**: client `ctx:Send("Score", {Score, Seconds})` at every game over (Seconds = game time). Server: Seconds is
  first capped by the server clock since the session opened / the last report (+3 s slack), so a replayed report
  claims ~0 s and is dropped. Then it is accepted only if Seconds >= 5 and Score <= Seconds*3 + 10. A new cabinet best
  sets state `HiScore` / `HiName` (display name, upper case, max 12 chars) and fires `NewHigh` {Score, Name, UserId}.
  By design, a perfect player scores <= ~1.9/s (a 400-seed simulation of 15-minute runs never gets closer than ~12
  points to the limit), so honest scores never fail the check.
* **World (every client)**:
  * Screen: a local part laid in the raked CRT opening (authored plane from `props/build_arcade_cabinet.py`: centre
    line y 3.84 / z -0.30, rake 11.6 deg, 1.50 x 1.12, face at d = -0.15 = in front of the neon pixels, inside the bezel),
    with a SurfaceGui (Font Arcade): ATTRACT (bouncing 🥒, blinking "PRESS E TO PLAY" or "TAP TO PLAY" on touch,
    "HI <score> <name>"), PLAYING (the local player's own score and hearts), NOW PLAYING <name> (someone else). Animated
    from `Kit.Now()` at 30 Hz.
  * Marquee: a local SurfaceGui panel inside the white MarqueePanel border at `Pivot_MarqueeCentre` (chase bulbs,
    "CUCUMBER CATCH", "HI-SCORE n NAME"). The neon **MarqueeText** ("ARCADE") is hidden locally
    (LocalTransparencyModifier = 1) while the behaviour runs, and comes back when it stops or the build is broken.
  * NewHigh: confetti out of the marquee (4 ParticleEmitters, `rbxasset://textures/particles/SquareParticle.png`,
    14 each), `Sfx.Cheer` at the marquee, "NEW HIGH SCORE!" flashing for 5 s. The scorer's game-over card shows
    the banner + `Sfx.ArcadeWin` + in-GUI confetti.
  * Joystick: the stick ball is merged into **RedControls** (with the 3 front buttons) and the shaft into **Metalwork**
    (with the coin door and return lip). So while someone plays (local game open, or state `Player` set), both parts
    are hidden locally and replaced by look-alike Parts built from the Blender source numbers (colour and material
    copied from the originals): ball, shaft, washer, plate, 3 front buttons, coin door, return lip. The ball and shaft
    tilt ±22 deg about `Pivot_JoystickPivot` (the local input, or state `Stick` for onlookers). Front buttons dip on
    catches (1), golden catches (2) and hits (3). The originals come back when nobody plays.
  * BuildMenuClient resets LocalTransparencyModifier to 0 after a cancelled move, so hidden parts are re-hidden
    every 0.5 s (a 0.85 ghost during a move is left alone).

## Parts / pivots relied on
`Pivot_JoystickPivot`, `Pivot_MarqueeCentre` (both have authored fallbacks), parts `MarqueeText`, `RedControls`,
`Metalwork` (each optional: a missing part just skips that feature). Screen plane constants are authored (no pivot
exists for it) and were checked against the dump (Screen part centre (0, 3.79, -0.05) = computed (0, 3.788, -0.045)).

## State / events (for testing)
* Model attributes: `Fun_HiScore`, `Fun_HiName`, `Fun_Player` (arcade name of the first open session, nil = idle),
  `Fun_Stick` (-1/0/1).
* Actions (client -> server): `Score` {Score, Seconds}, `Stick` (number), `Alive` (every 4 s while open), `Close`.
  A session also ends when the player leaves, dies, is > 26 studs away or goes quiet for 15 s.
* Test: place an ArcadeCabinet, walk up, press E on "Play". Play a round of at least 5 s and lose all 3 lives.
  Check `Fun_HiScore` / `Fun_HiName` on the model, the confetti from the marquee and the HI on the marquee + screen.
  A second client should see "NOW PLAYING <name>" on the screen and the stick tilting while the first one moves.
  To check the plausibility guard, fire `Score` {Score = 999, Seconds = 10} from a client: it must be ignored.
* The cabinet's best survives a move / break / mend of the same build (weak table keyed by the model) but not a
  server restart or a rejoin (BaseSave clones a fresh template). There is no DataStore on purpose (toy high score).

## Sounds used (FunAssets.Sfx)
ArcadeBlip (catch, pitch rises with the streak), Coin (golden), Zap (hit), ArcadeLose (game over), ArcadeWin (new
personal best / new cabinet high), Click (countdown ticks, play again), Whoosh (GO!, speed up), Cheer (NewHigh, 3D at
the marquee). Wishes: a short 8-bit "catch" blip and an 8-bit "hurt" sound would suit better than Beep/Zap.

## Known limits / questions for the integrator
* `SquareParticle.png` is a built-in Studio/player texture (checked in the local Studio content folder). If it ever
  fails to show, swap `CONFETTI_TEXTURE` to `rbxasset://textures/particles/sparkles_main.dds`.
* Emoji used: 🥒 U+1F952, 🧟 U+1F9DF, ❤️, 🖤, ✨, 🎉 (written as `\u{...}` escapes). The golden/rotten cucumbers and
  the fly are drawn with Frames, so they don't depend on emoji support.
* The replacement joystick uses smooth Roblox Ball/Cylinder parts, while the originals are low-poly meshes. The
  swap only happens while someone is playing, so idle cabinets keep the authored look.
* Several players may play the same cabinet at once (each has their own GUI). The world screen and the stick
  follow the first player (the "driver").
* The SurfaceGuis use `MaxDistance` 150 (set in pcall) and update only while the camera is within 140 studs
  (`B.StepRange`).
* The client disables PlayerModule controls while the game is open and re-enables them on close. If another
  system disabled controls at the same time (a cutscene), closing the game re-enables them.
* Not playtested (files-only package): the integrator should check the GUI scale on phone landscape (UIScale floor
  0.35), that the side rails work with touch, and that the replacement joystick lines up with the originals.
