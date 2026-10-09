# Piano (package HomePiano), 2026-09-24

A new Home build: a glossy black **grand piano with a matching bench**. The lid is propped open, and it has a gold
harp plate, strings, dampers, a music desk with sheet music, 3 gold pedals and a red tufted bench. It costs 2500.
Sit on the bench to play it. A two-octave piano GUI opens at the bottom of the screen. Everyone nearby hears your
notes, and coloured music notes float up out of the case.

## Files
| file | what |
|---|---|
| `models/build_Piano.py` | primlib model (run `run_one.py -- Piano`) |
| `models/out/Piano.parts.json` | 90 parts, 6.10 x 7.13 x 10.73 studs (lid up; the case top is 3.85; the bench is part of the build) |
| `models/renders/Piano_front.png / _three.png / _back.png` | review renders |
| `src/behaviours/server/Piano.lua` | ServerStorage.FunBehaviours.Piano |
| `src/behaviours/client/Piano.lua` | ReplicatedStorage.FunBehavioursClient.Piano |
| `tests/Piano/build_test.py`, `test.luau` | offline scenario test (uses `tests/DJBooth/mock.luau` read-only) |

## Model (authored frame, scale 1, keyboard faces -Z)
* The case outline has 5 pieces: `CaseFront`, `CaseBass`, and two vertical round columns, `CaseCurve` (bentside,
  centre (0, 1.5), r 3) and `CaseTail` (centre (1.5, 4), r 1.5). `CaseBridge` joins the two columns along their
  common tangent. The lid (`LidFront/LidBass/LidCurve/LidTail/LidBridge`) is the same outline, hinged along x = +3
  and opened 32 degrees. `LidStick` props it up.
* From the keyboard, the straight bass side is on the pianist's LEFT (+X) and the lid opens to their right (-X).
  This matches a real piano.
* Keyboard: `WhiteKeys` (one part, top y 3.23), 15 `BlackKey01..15` (3 octaves), `KeySlip`, `Keybed`,
  `CheekL/R` + `CheekLNose/RNose`, `Nameboard` + gold `NameLogo`.
* Bench: `BenchTop`, `BenchApron`, `BenchCushion` (red Leather, top at 2.2), `BenchTuft1..3`, `BenchLeg1..4` and
  gold `BenchFoot1..4`.
* Gloss: every black case part has Reflectance 0.12. Gold is `d9a93b` Metal.
* Gold band round the case bottom: `BandTreble` (straight, x = -3), `BandBass` (straight, x = +3), `BandCurve`,
  `BandTail`, `BandBridge`. There is no front band because the keybed covers the case front.
* Harp plate: `PlateFront`, `PlateBass`, `PlateCurve`, `PlateTail`, `PlateBridge` overlap, so their tops are
  staggered 0.02 apart to stop the textured Metal z-fighting. Front and bass are at 3.93, bridge 3.91, tail 3.89 and
  curve 3.87, which is still 0.02 above the case top. `PlateHole1/2` are dark discs through the plate that finish 0.02
  above the piece they sit on.
* **Pivots:** `Pivot_Bench` (0, 2.2, -4.5) is the cushion top, where the seat goes. `Pivot_Keys` (0, 3.23, -2.06) is
  the keyboard centre (not used by code). `Pivot_Sound` (-0.3, 3.85, 1.6) is where other players' notes sound from.
  `Pivot_Notes` (-0.7, 4.2, 1.9) is where the floating notes start. Attributes: `Cost` 2500, `Notes`.
* **Part count 90.** That is the "big appliance" cap. It is over the 70-part furniture budget because the piano and
  its bench are one build. 47 small details have collide off.
* **Suggested `BuildCatalog.SCALE` = 1.0.** It is already sized for the 6-stud avatar: the keys are at table height
  and the bench is at seat height.

## Behaviour
**Server**
* One `ctx:Seat` named `PianoBench` (2.2 x 0.4 x 1.2) sits on Pivot_Bench, turned to face authored +Z (the keys).
  Its prompt reads **"Play piano"** / object "Piano", distance 8. Anyone may play.
* State `Fun_Player` is the pianist's UserId. It is 0 when the bench is empty and -1 for a non-player humanoid.
* Action `Note`: the payload is a MIDI number, or a chord `{n, ...}` (the first 6 notes are kept).
  * Only the humanoid sitting on this piano's seat is accepted.
  * Limits per player per piano: 12 sends/s and 30 notes/s. Notes must be whole numbers from 24 to 108.
  * Accepted notes go out as `ctx:Fire("Note", {n | {n, ...}, userId})`.

**Client**
* **GUI (`PlayerGui.FunPianoGui`)** opens while `Fun_Player` is the local player.
  * Layout: bottom-centre above the hotbar, with a UIScale from the viewport. Touch-only devices get the biggest size
    that fits.
  * Keys: 24 keys, C4..B5 at octave 0, drawn as white and black keys with a red key-felt strip. C keys are labelled
    (C4, C5...). The keyboard letters show when a keyboard is present.
  * Input: every key has hit areas that don't overlap (white keys get two: the lower part plus the part between the
    black keys). Multi-touch and mouse-drag glissando work.
  * Keyboard: `A S D F G H J K L ; '` play white keys and `W E T Y U O P` play black keys. These cover the first 18
    keys. They are bound with CAS at High priority and sunk, so WASD does not reach the controls. Z / X shift the
    octave from -2 to +1 (C2..B6 overall). A new key press is ignored while a TextBox (chat) has focus.
  * Held keys turn green and sink 3 px. On release they tween back.
  * Header: "♫ PIANO", octave -/+ buttons (Z / X hints), a range label, and a red X. The X makes the player stand up
    (Sit = false, Jump = true). If they are still seated 1 s later, the GUI reopens.
  * It closes when the player stands up, dies, is more than 20 studs away, or the build is moved, broken or sold.
* **Sound**
  * Local notes play at once from a 2D pool of 10 in SoundService.
  * Other players' notes play from a 3D pool of 8 on an attachment at Pivot_Sound: InverseTapered, 10..80 studs,
    and skipped entirely when the camera is more than 95 studs away.
  * Pitch: `PlaybackSpeed = 2^((n - root)/12)`, where root is the MIDI number of `FunAssets.PianoRootHz`
    (261.63 Hz = 60).
  * Keys pressed within 0.1 s go out together in one send, so chords stay under the rate limits.
* **Floating notes**
  * A pool of 10 BillboardGuis (♪ / ♫) on a local helper part at Pivot_Notes. They use the palette colours: yellow,
    blue, red, lime and pink.
  * Each one rises 4.6 studs over 1.9 s, sways and fades. At most one spawns every 0.07 s, and the oldest is reused
    first.
  * These are billboards, not a ParticleEmitter, because a ♪ particle would need an uploaded texture.
* **Pianist pose**
  * On every client, while someone sits at the bench, the R15 joint Transforms are written after the Animator
    (RunService.Stepped, like the framework's lying seats; works with Motor6D or AnimationConstraint).
  * Pose: Waist -8, Neck -14, Shoulder 40 (arms forward), Elbow 38, Wrist -20 degrees.
  * Each note swings the hand that plays it toward its key: the low half uses the left hand, yaw ±22 / 6. The hand
    dips on the press.
  * Tune it in `POSE`, or set `POSE_ENABLED = false` to turn it off.
* **Per-frame work:** one Stepped connection per piano runs the floats, the pose and the open-GUI watchdog. It sleeps
  when the camera is more than 160 studs away. No ctx:Step is used.

## Sounds wished for
None outstanding. `FunAssets.Sfx.PianoNote` is already the verified sustained piano C4 sample
(`rbxassetid://78413131279275`, 6 s), and `FunAssets.PianoRootHz` = 261.63 was measured on it, so the root MIDI
number is 60 and C4 plays at PlaybackSpeed 1. (`Sfx.ArcadeBlip` is only a code fallback in case `PianoNote` is ever
removed from FunAssets.)

## How to test (integrator)
1. Install the model from `models/out/Piano.parts.json` into `ServerStorage.Builds/Home/Piano`, then the two
   behaviour modules.
2. Place it and sit with the bench prompt "Play piano". Check that `Fun_Player` equals your UserId and that
   `PlayerGui.FunPianoGui` appears.
3. Press A..' / W..P / Z / X, click the keys and drag across them.
4. With a second client within 80 studs, check that it hears the notes from the case, sees the notes float up, and
   sees the pianist lean in.
5. Stand up with Space or the X and check that the GUI closes.
6. Move, break or sell the piano while playing and check that the GUI closes and nothing is left in
   `workspace.FunBuildRuntime` / `workspace.FunBuildLocal`.
7. Studio: `workspace:SetAttribute("FunBuildDev", "list")`.

**Offline test:** `py tests/Piano/build_test.py`, then run
`luau.exe tests/Piano/run_test.luau`. Result: 64 checks pass, 0 runtime errors. It covers:
* seat placement and facing
* opening the GUI; key, chord, octave, touch and glissando input
* the 2D and 3D pools and pitches
* floats and the pose
* server validation and rate limits
* the close button, walking away, a second pianist, and selling the piano

Mock note: the shared mock's `Seat:Sit` method shadows `Humanoid.Sit`, so the framework's seat prompt handler bails
out in the mock. The test seats the humanoid with `seat:Sit` directly.

## Known limits
* The pose angles are estimates, not measured on the game's physique-scaled avatars. If hands float above the keys
  or clip into them, adjust `POSE.Shoulder` / `POSE.Elbow` / `POSE.Wrist`.
* The ♪ / ♫ glyphs rely on Roblox's font fallback, since FredokaOne has no music symbols. If they show as boxes,
  change `FLOAT_GLYPHS` and the title.
* Notes ring out: there is no key-up damping and no sustain pedal. Remote players never get key-ups. Voices beyond
  the pool cut the oldest note.
* Touch dragging does not glissando; tapping and multi-touch do work.
* The keyboard shortcuts cover the first 18 of the 24 keys. The top 6 are mouse or touch only.
* The back of the case shows a flat facet where the bentside bridge joins the two round columns. It is visible from
  behind the piano only.
