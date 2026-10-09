# Launcher animations -- authoring brief (RAS - Dev, 30 snowball launchers)

You author ONE launcher's animation set in Blender (headless, from a Python build script) with
`launcherlib.py`. The export plays in the Roblox game RAS - Dev on the launch pad: the player holds
the mouse to charge, releases, and the snowball must visibly **come out of the launcher** and fly
down the track. The in-game runtime is finished and tested with launcher 01 (the shovel): it plays
your clips on the character's joints, shows the snowball in the launcher's Seat while charging,
lets it go at `FireAt` from the Seat / Muzzle, and the server spawns the real ride ball exactly
there. **Your job: make the motion great, launcher-specific, readable from the game camera, and
aimed correctly at the fire moment.**

Folder: `C:\Users\shrey\OneDrive\Documents\RobloxGames\ras-dev\launcher-anims\`
- `launcherlib.py` -- the library (read its module docstring + the functions listed below). DO NOT EDIT.
- `LauncherAnims.blend` -- rig + all launcher meshes. DO NOT SAVE OVER IT (headless runs never save).
- `meta/NN.json` -- your launcher's points (Muzzle, Seat, Grip2, Tip, Bands, Back, Muzzle2) in the
  launcher's grip-pivot frame at template scale. You MAY edit YOUR OWN meta file if a point is wrong
  (e.g. move Grip2 to where the left hand really should hold). Keep `Muzzle` = where the ball exits
  and its `look` = the exit direction in launcher space. Never edit other launchers' files.
- `launchers/01/build.py` -- the REFERENCE script (structure to copy). Its poses still need polish.
- `out/inspect/meta_*.png` -- every launcher drawn alone with its meta markers (red = Muzzle + its
  look arrow, yellow short arrow = Muzzle up, white ball = Seat, green = Grip2, yellow dot = Tip,
  magenta = Bands). Columns: side view from +X (image up = launcher top, image right = forward),
  view from the top, view from the front end. Rows in order of launcher number (6 per sheet).
- `meshes/NN_Name.png` -- the launcher's texture (colours / theme).

Your files: `launchers/NN/build.py` (write it), outputs `launchers/NN/sheet_game.png`,
`sheet_front.png`, `sheet_track.png`, `launchers/NN/report.json`, and `out/NN.json` (the export).

Run (PowerShell):
```
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b "C:\Users\shrey\OneDrive\Documents\RobloxGames\ras-dev\launcher-anims\LauncherAnims.blend" --python "C:\Users\shrey\OneDrive\Documents\RobloxGames\ras-dev\launcher-anims\launchers\NN\build.py" 2>&1 | Select-String "^REPORT|Error|Traceback|line \d+"
```
About 8 seconds per run. Then Read the three sheet PNGs (look at them every iteration!) and
report.json. Iterate until the checklist at the bottom passes. Budget: up to ~12 runs.

## The stage (memorise this)

Roblox space, relative to the character's root (HumanoidRootPart), studs:
- X = character's right, Y = up, Z = character's BACK. The character faces **-Z**.
- The character stands SIDE-ON on the pad. **Down-track = (-1, 0, 0) = the character's LEFT.**
  The ball must fly that way (into the screen, away from the camera).
- The pad **camera** is behind the track at about (13, 5.75, 0) looking toward (-3, 2, 0): it sees
  the character's RIGHT side and back. Screen-right = the character's front (-Z). Screen-left = the
  character's back (+Z).
- **Visibility rule:** anything between the character and down-track (x < -0.7 with |z| < 0.8) is
  HIDDEN behind the body from the game camera. Keep the launcher and the action on the character's
  FRONT side (z around -1 to -3, screen-right), or above the head, or on the right side (x > 0.8).
  The ball can then fly off into the screen from there. Check `sheet_game.png` every run: if you
  cannot see the launcher and the ball leaving it there, fix the pose.
- Floor: y = -3.0. Standard R15 proportions (arms ~1.6 studs shoulder to wrist). The launcher is
  scaled 1.5x (as in game): a shovel is 4.6 studs long, most guns 3-4.5 studs.

Sheets: rows = Ready, ChargeLo, ChargeHi, Fire (frames at even times + the fire moment with a RED
border + any extra_times). `sheet_game` = the real pad camera (cropped); `sheet_front` = from in
front of the character; `sheet_track` = from down the track looking back (a correct shot flies
straight AT this camera). The preview ball flies from the start point along the Muzzle look after
FireAt (the real ball then goes straight down the track).

## The four clips (30 fps; loops end exactly where they start)

| clip | loops | what it is | typical length |
|---|---|---|---|
| Ready | yes | on the pad, launcher carried/ready, idle life (breathing, small weight shift) | 1.6-3 s |
| ChargeLo | yes | player HOLDING at low charge: the launcher-specific charging action, calm | 0.6-1.6 s |
| ChargeHi | yes | same action at FULL charge: bigger, deeper, more tension/shake. SAME length as ChargeLo | = Lo |
| Fire | no | release -> the shot at `FireAt` -> recoil / follow-through -> settle near Ready | 1.0-1.8 s |

Runtime blending: Ready <-> charge crossfade 0.2 s; ChargeLo/ChargeHi are blended by the live
charge, which ping-pongs 0 -> 100 % -> 0 while held (so Lo and Hi must be the SAME motion at
different intensity, same phase timing, or the blend mushes); Fire starts from whatever pose the
charge was in (0.08 s blend), so its first key should be close to the ChargeHi pose; `FireAt`
0.12-0.45 s after release (guns quick ~0.12-0.2, throws/scoops/lobs up to ~0.45). After Fire the
controller fades back to the default avatar pose over 0.25 s (the camera follows the ball ~0.5 s
after the shot), so end Fire in a relaxed hold similar to Ready.

## The API you use (all Roblox HRP-local coordinates, degrees)

```python
import launcherlib as L
L.use_launcher(LID)                      # once, at the top
L.new_clip("Ready")                      # start a clip; then pose + L.key(frame) repeatedly
L.reset_pose()                           # start every key pose from rest
L.stance(hip_drop=0.2, hip_back=0.1, hip_side=0.0, root=L.ry(20) @ L.rx(-10),
         feet={"Left": (-0.8, -0.3), "Right": (0.6, 0.4)}, foot_yaw=None)
         # legs IK with planted ankles (x, z on the floor). root = LowerTorso rotation:
         # L.ry(+a) turns the body LEFT toward the track, L.rx(-a) leans forward.
L.waist(L.ry(10) @ L.rx(-15))            # UpperTorso relative to LowerTorso (twist / bend)
L.hold(at, yaw, elev, roll=0, anchor="Pivot"|"Muzzle"|"Seat"|"Tip", elbow_away=(x,y,z), max_wrist=65)
         # puts the launcher's ANCHOR at `at`, its look axis along direction(yaw, elev):
         #   yaw 0 = down-track (-X), +90 = character front (-Z), -90 = back, 180 = toward camera
         #   elev + = up.  anchor "Pivot" = the grip in the right hand (look = launcher forward).
         # Solves the right arm; returns errors: arm_overreach > 0 = out of reach -> move it closer.
L.place_launcher(at, forward, up, anchor=...)   # same with explicit vectors
L.left_hand_to(key="Grip2", elbow_away=(0.3, 1.0, 0.1), palm_toward=None, offset=(0,0,0))
         # or L.left_hand_to(point=(x, y, z)) for a free point (e.g. drawing a slingshot band)
L.arm_to("Left"|"Right", wrist_point, elbow_away, hand_rot=None)    # raw arm IK
L.head_look(target=(x, y, z)) / L.head_look(yaw=.., pitch=..)
L.set_rot(bone, quat) / L.get_rot(bone) / L.set_loc(bone, xyz)       # raw FK (bone names = R15 parts, + "Launcher")
L.joint(bone), L.launcher_point(meta_pos), L.pivot_cf(), L.hand_cf("Left")   # measure
L.key(frame)                             # keys ALL bones at a frame (30 fps)
L.make_cyclic(kind)                      # call after keying a loop (first pose re-keyed on the last frame)
L.set_interpolation(kind, 'BEZIER'|'LINEAR', 'AUTO_CLAMPED'|'AUTO', frames=None)
L.snapshot() / L.restore(s) / L.blend_snapshots(a, b, t)  # reuse / mix whole poses
L.direction(yaw, elev), L.up_for(forward, roll), L.rx/ry/rz(deg), L.DOWN_TRACK, L.FLOOR_Y
L.finish(SPEC, OUT, extra_times=[...])   # check + export out/NN.json + 3 sheets + report.json
```
IK order inside a key pose: stance -> waist -> hold (right arm + launcher) -> left_hand_to -> head_look.

**Elbows (IMPORTANT, corrected):** `elbow_away` is the direction the elbow bends AWAY from. An
UP-ish vector such as (0, 1, 0) or (-0.3, 1, 0.1) for the right arm and (0.3, 1, 0.1) for the left
arm gives natural elbows that hang down and out. A DOWN-ish vector (0, -1, ..) rolls the upper
arm INTO the chest; the library now mirrors such poles automatically (the "elbow guard"), so
your poses may have shifted a little since the first round. Add a little +Z to the pole to push
the elbow forward, -Z to push it back. Keep IK targets at least ~0.15 studs INSIDE full reach
(the arm length is ~1.66 studs shoulder to wrist): a target that crosses full reach from frame to
frame makes the elbow flip between straight and bent (an "elbow flip").
"Launcher" bone = the launcher turning in the right hand (place_launcher puts wrist overflow there).
Some constant turn vs Ready is fine; big changes during a clip read as the launcher sliding in
the hand -- the report warns above 60 deg (vs the Ready pose). Prefer moving the body / arm.

SPEC (top of the script):
```python
SPEC = {
    "Ready": 2.0, "ChargeLo": 1.0, "ChargeHi": 1.0, "Fire": 1.4,   # lengths in seconds
    "FireAt": 0.30,                              # seconds into Fire when the ball leaves
    "Ball": {"show": "Never"|"Charge"|"Always"|"Fire", "start": "Seat"|"Muzzle", "grow": 1.0,
             "hand": "Left", "offset": [0, -0.45, 0]},   # hand/offset only for a ball held in the left hand
    "BallAppearAt": 0.1,                         # only with show "Fire": when it appears in the Seat
    "Fx": {"Style": "snow"|"smoke"|"spark"|"fire"|"steam"|"toxic", "Color": [r, g, b],
           "Charge": None|"spark"|"snow"|"steam"|"fire"|"toxic", "ChargeColor": [r, g, b]},
    "TwoHanded": True,                           # False = no left-hand-on-Grip2 check
    "AllowFootLift": False,                      # True if a step / hop is intended
    "Notes": "one line: the concept",
}
```
- `Ball.show`: "Charge" = the ball appears in the Seat when the player starts holding (open
  launchers: scoops, cups, pouches, rails); "Never" = hidden until it pops out of the Muzzle
  (barrels); "Always" = sits there even in Ready; "Fire" = appears at BallAppearAt in Fire.
  `start` "Seat" = it flies from where it sat; "Muzzle" = it comes out of the muzzle.
  `grow` < 1 = it packs/grows from that fraction to full size over the first 0.5 s of holding.
- `Fx.Style` = the burst at the muzzle when it fires (barrels default "smoke", open ones "snow").
  `Fx.Charge` = a small looping effect at the muzzle while holding (energy/elemental launchers).
- Slingshots: ball held in the LEFT hand (`"hand": "Left"`, start "Seat"); the runtime draws two
  elastic bands from meta Bands (fork tips) to the ball; at FireAt the ball flies from the hand
  through the fork along the Muzzle look.

## The motion audit (in report.json, per clip: `<Clip>_audit`)
Every build now replays the exported frames on realistic avatar proportions (torso 1.7 x 1.6 x
0.95, arms ~0.5 thick) and reports:
- `flips` -> a PROBLEM: an elbow bend jumping > 25 deg and straight back within 2 frames (IK popping).
- `snaps` -> warning: a joint turning > 30 deg in one frame while its neighbours barely move.
- `arm_in_body` (studs, where) -> warning above 0.25: an arm part sunk into the torso / head.
- `launcher_in_body` (studs, where) -> warning above 0.2: the launcher mesh inside the torso / head.
Targets for a finished launcher: no flips, no snaps you did not intend, arm_in_body <= 0.2,
launcher_in_body <= 0.15 (a crossbow stock touching the shoulder or a railgun at the cheek may
touch, never sink in).

## Hard requirements (report.json "problems" must be empty)
1. At `FireAt` the Muzzle look points down-track: `fire_yaw_off_track_deg` <= 20 (aim for < 10),
   `fire_elevation_deg` -15..55 (flat-ish for guns 0-15, throws 10-35, lobs/mortars 30-50).
2. The ball's start point is outside the body (`ball_body_clearance` >= -0.35, better > 0) and its
   first 4 studs of flight don't cross the body (`flight_clearance` >= -0.2).
3. Loops close (seam < 1 deg); ChargeLo and ChargeHi have the same length.
4. The launcher does not sink more than 0.25 studs into the floor (a shovel/scoop may TOUCH it).
5. `arm_overreach` ~0 in your key poses (print the returned dicts while tuning); two-handed
   launchers keep `*_left_hand_gap` small (< 0.35, ideally < 0.15) whenever the left hand is meant
   to be on the launcher. Warnings are judgment calls; fix the ones that look wrong.

## Quality bar (a reviewer will judge your sheets against these)
- **Launcher-specific**: the motion sells what THIS launcher is (see your concept below): a pump
  gun pumps, a sling whirls, a slingshot draws, a mortar thumps and lobs, a railgun is precise.
- **Readable from `sheet_game.png`**: the launcher and the charging action are clearly visible;
  at the red-bordered fire frame you can see the ball at the launcher's Seat/Muzzle.
- **Ball comes out of the launcher**: the fire frame puts the Seat/Muzzle ahead of the body, the
  launcher pointing down the track; in `sheet_track.png` the ball flies toward the camera from it.
- **Weight and timing**: anticipation before the shot, a clear release, recoil / follow-through
  proportional to the launcher (light scoop vs heavy cannon), settle. No robotic stillness in
  loops (breathing / sway), no jitter, no limbs through the body, feet planted unless a step is
  intended, the head looks where the action is (usually down-track or at the launcher).
- ChargeHi reads as MORE than ChargeLo (deeper crouch, bigger swing, faster shaking).
- Two-handed things are held with both hands; one-handed ones have a natural free left arm.

## Final answer (return JSON only)
{"launcher": NN, "concept": "...", "fire_at": x, "runs": n, "problems": [...remaining...],
 "warnings": [...remaining...], "self_review": "2-4 sentences on what the sheets show",
 "meta_changed": true/false}
