# NeonSign: A OpenSign, B ArrowSign, C Marquee (package GlassCase, 2026-09-24)

Files:
- `src/behaviours/server/NeonSign.lua` goes to `ServerStorage.FunBehaviours.NeonSign`
- `src/behaviours/client/NeonSign.lua` goes to `ReplicatedStorage.FunBehavioursClient.NeonSign`

`B.Keys = {"NeonSign"}` serves NeonSign_A, NeonSign_B and NeonSign_C. The builds are scaled x1.5.

## What it does
- **Server**: state **`On`** (model attribute `Fun_On`, default `true`), remembered per placed build for the server session. Prompt **"Switch off" / "Switch on"** (E, `NeonSwitchPrompt` on `<V>_Panel`) is **owner only**. The server refuses others, and the client puts the prompt out of reach (`MaxActivationDistance 0`) for non-owners. There is a 0.3 s cooldown.
- **Client**: everything runs off `Kit.Now()`, so all clients show the same frame.
  - **A (OpenSign)**
    - `A_Text` (pink OPEN) flickers realistically. Per 5.5 s window a seeded burst happens with probability 0.55: 2 to 6 off/on stutters (some fully dark, some with residual glow), and 30% of the time a sag that climbs back. The seed comes from Owner, PlotX and PlotZ, so neighbouring signs don't flicker in unison.
    - There is a faint shimmer on top.
    - Each burst plays one very quiet `Sfx.Zap` (volume 0.07, random pitch 0.85 to 1.25, rolloff 4 to 40).
    - `A_Border` (cyan) flickers much more rarely.
    - A pink PointLight follows the text's level.
    - **Far viewers (fix pass 2026-09-24):** while the camera is beyond StepRange (200 studs) the Step sleeps. A ctx:Every(0.5) check then holds A_Text, A_Border and the light fully lit (when on), so a stutter frozen at level 0 can never leave the sign dark from far away. B and C may freeze mid-chase out there, which does no harm.
  - **B (ArrowSign)**
    - `B_Arrow` is **one merged mesh**, so the sweep toward its tip is built around it. Two runtime neon chevrons (`NeonChevron`, 2 arms each, arrow colour) sit one behind the arrow (authored x 3.49) and one past its tip (x 1.11).
    - Every 1.2 s they light cumulatively: tail chevron, then + the sign's arrow, then + the tip chevron. Then they drop back. The sign's own arrow only dims to 30% between sweeps.
    - `B_Bulbs` (**one merged mesh** of 10 bulbs) is covered by 10 runtime Neon balls (`NeonBulb`) that chase column by column toward the tip side (0.13 s per column, then a rest). The merged mesh goes dark underneath.
    - An orange PointLight pulses with the arrow.
  - **C (Marquee)**
    - `C_Bulbs` (**one merged mesh** of 12 bulbs) is covered by 12 runtime Neon balls. Every third bulb is lit, stepping clockwise as the viewer sees it every 0.2 s.
    - In the last 1.8 s of every 15 s, all bulbs flash together.
    - A warm PointLight.
  - **Off** (`Fun_On == false`): every Neon part of the sign goes **SmoothPlastic**, colour 72% toward the panel's 23262c. The overlay bulbs go to a dull unlit amber and the light goes out. **On**: a 0.48 s warm-up stutter. A `Sfx.Click` plays on each switch.
  - The PointLight is 1.6x brighter at night (`workspace.CyclePhase == "Night"`).
  - Only Material and Color of the sign's own parts are changed, never Transparency (BuildHealthService fades that). Both are restored on cleanup. Overlays are local parts in a client-only folder, `workspace.FunFX_<Key>`.
  - A nil `Fun_On` while the server restarts (move / break) is ignored.

## Parts / geometry relied on
- `A_Text`, `A_Border`; `B_Arrow`, `B_Bulbs`, `B_Text`; `C_Bulbs`, `C_Text`. The steady neon parts are found automatically: every `<V>_*` part whose Material is Neon at start.
- `<V>_Panel` hosts the prompt.
- Bulb and chevron positions come from `props/build_neon_sign.py` in `B.Layout` (authored Roblox frame = Blender (x, z, -y), lanes A +9.8, B +2.3, C -7.4):
  - B bulbs: (lane ±1.76 / ±0.59, 4.56 / 1.84), (lane ±1.76, 3.20), z -0.21, ball diameter 0.30
  - C bulbs: (lane + {±3, ±1.5, 0}, 4.70 / 3.20), (lane ±3.72, 3.95), z -0.25, ball diameter 0.32
- At start the merged mesh's real centre is compared with its authored bbox centre (`Kit.ToWorld`):
  - an offset up to 1.5 studs x Scale is absorbed
  - a larger one warns `[NeonSign] ... bulb overlays skipped`, and the whole merged mesh pulses instead

## Sounds
`FunAssets.Sfx.Zap` (A's flicker buzz, very quiet), `FunAssets.Sfx.Click` (switch). **Wish:** a real neon transformer hum loop, very quiet and short rolloff, for A. I did not add one because `HumLoop` = "Electric Buzz" may not loop cleanly.

## How to test
1. Place each variant and watch it:
   - A flickers every few seconds with a faint zap.
   - B shows `> > >` sweeping toward the viewer's right, with bulbs chasing that way.
   - C shows marquee bulbs running clockwise, with a flash-all every 15 s.
2. As the owner, press E "Switch off". Every tube goes dark plastic and the light goes out; `Fun_On` becomes false. Press E "Switch on" for the warm-up stutter. A second player sees no prompt.
3. Move or break/mend it: the on/off state is kept. After a cleanup the sign's parts are Neon with their original colours again.

## Offline checks (already run: all passed)
- `tools/glasscase_check/run_scenario.ps1` covers the A, B and C lifecycles on mocks:
  - overlay counts (B 10+4, C 12)
  - every overlay lights during 20 s of show
  - the A buzz fires
  - B's covered mesh stays dark, and B's chevron positions
  - owner gating, off/on and the warm-up
  - the nil-state guard, and cleanup restoring Material and Color
  - fix pass: A goes dark in a stutter, the camera leaves, and the letters, border and light come back fully lit (1.6 at night) and stay there
- Renders (the original prop + the overlays from the real `B.Layout`, odd groups lit):
  - `models/renders/NeonSign_B_overlays.png`
  - `NeonSign_B_overlays_side.png`
  - `NeonSign_C_overlays.png`
  - `NeonSign_C_overlays_side.png`

  The balls fully swallow the original bulbs, and the chevrons clear the arrow, the bulbs and the text.

## Known limits
- The brief allowed pulsing the merged arrow's Transparency. I used Color and Material only, because Transparency is BuildHealthService's while broken.
- The flicker schedule is deterministic per server-time window, but `Random` pitch for the zap is local.
