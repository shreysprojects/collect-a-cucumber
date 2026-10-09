## 2026-09-16 Click-to-lift pickup: the bar, kg weights, Blender lift clip (user: "delete the current cucumber pickup system entirely")

User: a long bar like the screenshot -- the strength icon drifts left; every click pushes it right;
all the way right = picked up, all the way left = the pickup fails; red end on the left, green on
the right; the camera frames the whole body and the cucumber; a Blender pickup animation where every
click brings the cucumber up a little; strength-based: lots of strength = 2-3 clicks, not enough =
the icon always wins whatever the clicks per second; weights in kg from 3-4 kg for the lightest
Spawn cucumber to a trillion for the lightest Neon one, shown instead of a strength requirement.

### What went (all in `ServerStorage.__LiftRebuildBackup_2026_09_16`, disabled; disk backup
`backups/NewMap_pickup_before_lift_rebuild_2026-09-16.rbxm`)
- `RS.Modules.CucumberStrength` (bands, grip budget, carry modes, recovery window, band labels)
- `StarterPlayerScripts.CollectAnimClient` (walk-up + struggle / pick-up / fall clips, speed controller)
- `StarterPlayerScripts.CucumberGripClient` (the GRIP! panel, STEADY button, carry-mode cycling)
- `RS.Assets.Animations` CucumberPickUp / CucumberStruggle / CucumberFall + their KeyframeSequences
- inside `CucumberCarry`: Heavy / Weak / Speed / Band / Ratio, Stumble, ScheduleStumble, the grip
  Heartbeat, SteadyCucumber / CucumberCarryMode / CancelCucumberPickup / CollectAnim remotes, the
  rescue-pickup shortcut, the "stumble" dev hook, Place's too-heavy refusal
- inside `CarryClient`: the per-band hints, the Stumble / Steadied cues

### What is new
- `RS.Modules.CucumberLift` (mirror `CucumberLift.lua`): WEIGHTS + THE BAR + the timeline.
  kg = `ZONE_BASE[zone]` (Spawn 3, Desert 60, Samurai 1.2K, Farm 25K, Snow 500K, Underwater 10M,
  Volcano 200M, Narmek 4B, Toyland 60B, Neon 1T) x (reward / 3) ^ 0.55 (CucumberValues.REWARDS:
  the 360-reward tree is ~14x its biome's slice, still under the next biome's slice) x Golden 2 /
  Diamond 4 x 1.5 per mutation x SizeScale ^ 1.5, two significant digits. 1 kg asks for 1 Strength:
  `ratio = Strength / kg`. `Params(ratio, trait)`: ratio >= 1 -> Gain clamp(0.065 x ratio^1.2,
  0.065, 0.36) per click, Drift 0.12 / ratio per second (x1 ~10 clicks, x2 ~5, x3.5+ two clicks);
  ratio < 1 -> Gain 0.022 x ratio, Drift 0.45 .. 1.2 per second -- MAX_CPS 20 clicks per second adds
  at most 0.44 per second, under the 0.45 drift floor, so the icon always wins. Slippery (CucumberAdventure trait) drifts x1.25.
  `Of(holder)` reads the WeightKg attribute CucumberCarry stamps on every field cucumber,
  `Format(kg)` -> "12 kg" / "1.2K kg" / "1T kg" (NumberAbbrev), `Difficulty(ratio)` -> easy (>= 3)
  / medium (>= 1.5) / hard (>= 1) / too heavy + a colour for the prompt.
- `RS.Modules.CucumberLiftPoses` (GENERATED: `assets/anims/json_to_poses_module.js` from
  `CucumberLift.json`): 22 pose samples at 15 fps, 7 numbers per joint, Motor6D.Transform values.
- `StarterPlayerScripts.CucumberLiftClient` (mirror `CucumberLiftClient.client.lua`): the whole
  client side. Own lift: walk-up (Humanoid:Move per frame, APPROACH 0.6 s), face it, freeze
  (WalkSpeed 0 held on Stepped, no jump, no AutoRotate, PlayerModule controls off when present),
  camera swings (Scriptable, 0.35 s quad-out) to the cucumber's far side looking back at the
  player -- distance from the vertical / horizontal FOV so the whole body and the cucumber fit,
  eye 0.28 x distance above the focus, pulled in when a wall is in the way -- and THE BAR appears:
  `PlayerGui.CucumberLiftBar` = full-screen click Catcher (every click / tap anywhere counts,
  nothing under it gets them) + Root (78 % wide, 15 % tall, capped 1400 x 100 px, bottom at 87 %)
  with Title (name, coloured by CucumberMutations, + kg), Hint ("CLICK! CLICK! CLICK!" / TAP,
  pulsing), Track (grey, 30 % translucent, 8 px corners, 4 px dark outline), RedZone / GreenZone
  (5 % of the track each), Icon (the HUD's strength image rbxassetid://15403007921, 1.55 x the
  track height, pops on every click, tilts and trembles when the drift is winning). Gamepad A /
  R2 click too; X / B cancel. Heartbeat: p -= Drift x dt, click: p += Gain; p >= 1 -> "done" to the
  server + the hoist (clip 1.0 -> 1.4 s over HOIST_LEN 0.4), p <= 0 or MAX_TIME 12 s -> "fail":
  "Too heavy" (Notify), Big Thud, the pose and the cucumber sink back over FAIL_RELAX 0.45 s.
  Progress goes to the server at 8 Hz for the other clients.
  THE POSE (every client): the CucumberLift clip is scrubbed by progress and written straight into
  the R15 Motor6D.Transform values on RunService.Stepped (weight-blended in / out over 0.15 s,
  translations scaled by HumanoidRootPart.Size.Y / 2 for the physique-scaled bodies), so it needs
  NO Animation asset -- it plays on a live server whoever owns the place (the old clips were
  group-owned and only ran in Studio). The cucumber rides the hands' midpoint up (giants only
  1 / SizeScale of the way), smoothed.
- `CucumberCarry` (mirror `CucumberCarry.server.lua`): `Collect` locks the cucumber
  (CollectingBy, prompt off, Busy), unequips tools (the bat would swing on every click), computes
  kg / ratio / Params for THIS player and fires {Kind = "Start", Player, Holder, Token, Name, Kg,
  Start, Gain, Drift} to everyone. `attempt.Finish(result)`: "done" is believed only when
  strength >= kg and the claim comes at least APPROACH / 2 + MinClicks / MAX_CPS seconds after the
  press (else it is turned into a cancel and logged) -> {Kind = "Hoist"} to all, HOIST_LEN later
  `Grab` (alive / reach / hands re-checked) swaps the field cucumber for the shoulder copy;
  "fail" -> {Kind = "Fail"}; "cancel" / no answer for APPROACH + MAX_TIME + 2 s -> {Kind =
  "Cancel"}. Progress ticks are relayed to the OTHER clients (12 Hz cap). Every field cucumber
  gets WeightKg; placed / restored copies carry it too. Carry entries keep Kg (player attribute
  CarryingCucumberKg; `Required` = kg for CucumberAdventure's "heaviest secured" records). The
  lobby watch only marks CucumberCarrySafe + the LobbyReached cue now. DropForNight / TakeCarried
  cancel a running bar first. Dev hook: `CarryDev` = "collect:<Name>" | "win:<Name>" |
  "lose:<Name>" | "drop:<Name>" | "pickup:<Name>".
- `CucumberPromptClient`: name, "Lift", and the weight row "12 kg" in the Difficulty colour
  (prefixed by the CucumberAdventure trait when it has one). `CarryClient`: a kg line under the
  name on the shoulder billboard; hints / cues of the old system gone.

### The clip (Blender, headless: `blender -b CucumberAnims.blend --python build_cucumber_lift.py`)
The Blender MCP addon was not running, so the same r15animlib pipeline ran in background mode
(`assets/anims/build_cucumber_lift.py`). CucumberLift 1.4 s: 0.00 deep squat grip (hip drop 0.45,
hips back 0.38, root -14, waist -54, hands closed on the cucumber), 0.33 rising with the load at
the knees (arms straight down), 0.60 nearly upright with the load at the thighs (the screenshot),
1.00 upright, elbows bent, the load hugged at the chest, 1.40 the carry pose (left hand steadying
the shoulder load). The bar scrubs 0..1.0, the hoist plays 1.0..1.4 once. Arm reach errors 0 except
the grip pose (0.18, the same as the old struggle grip). Exports: CucumberLift.json / .fbx,
preview_CucumberLift_{000,033,060,100,140}.png, the action saved in CucumberAnims.blend.

### Strength economy note
The kg ladder is what was asked for (Spawn slice 3 kg .. Neon slice 1T kg). Today's strength
sources (bench 2^(level-1) per rep up to 128 x headband up to 13, shop packs up to 50K) reach the
first three or four biomes; the Snow .. Neon weights assume the strength economy grows (rebirths,
multipliers) -- `CucumberLift.ZONE_BASE` is the one table to retune.
