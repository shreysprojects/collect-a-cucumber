# GlassCase: trophy display (package GlassCase, 2026-09-24)

Files:
- `src/behaviours/server/GlassCase.lua` goes to `ServerStorage.FunBehaviours.GlassCase`
- `src/behaviours/client/GlassCase.lua` goes to `ReplicatedStorage.FunBehavioursClient.GlassCase`

The build is scaled x1.25 (`BuildCatalog.SCALE.GlassCase`).

## What it does
- **Server**
  - `GlassPanes` and `LightBeam` get `CanCollide = false` at start. Their original values come back on cleanup, except while the build is `Broken`: then BuildHealthService owns collisions and keeps what it recorded.
  - State **`Design`** (model attribute `Fun_Design`, values 1 to 5):
    1. Golden Cucumber
    2. Royal Crown
    3. Gold Star
    4. Champion Cup
    5. Diamond

    The value is remembered per placed build for the server session (a weak table), so a move or a break/mend keeps the owner's pick.
  - Prompt **"Admire"** (E, everyone, `AdmirePrompt` on `Plinth`) runs `ctx:Fire("Admire", {At = server time, By = UserId})`. Its cooldown is 1.2 s per case. ObjectText is the current design's name.
  - Prompt **"Change trophy"** (F / ButtonY, `ChangeTrophyPrompt` on `Plinth`, `UIOffset (0, 72)` so it sits under Admire) is **owner only**. The server refuses anyone else. ObjectText shows `Next: <design>`.
  - **Nameplate**: a brass helper part `TrophyNameplate` in the runtime folder. It sits over the plinth's TROPHY plate at authored `(0, 0.53, -1.48)`, size `2.5 x 0.52 x 0.1`, and hides the engraved letters. It has a SurfaceGui (Front, 120 px/stud, FredokaOne, ink 2f3640, engraved border) reading `"<OwnerName>'s Trophy"`, or `"James' Trophy"` for names ending in s. The name comes from `Players:GetNameFromUserIdAsync` (pcall, cached); an online owner is read from `Players` first.
- **Client**
  - The trophy is built from Parts in code (`B.TrophySpecs(d)`, plain data):

    | Design | Parts | Height (authored) |
    |---|---|---|
    | Golden cucumber on a marble plinth (curved, warts, stem, leaf) | 22 | 1.31 |
    | Crown with points, jewels and velvet cap, on a tasselled cushion | 33 | 1.23 |
    | Star on a stem with a ruby heart | 17 | 1.32 |
    | Two-handled cup | 23 | 1.20 |
    | Brilliant-cut diamond on its point | 49 | 1.22 |

    Heights are multiplied by the Scale. Triangles are two WedgeParts each.
  - The trophy floats 0.08 to 0.14 studs (authored) above `Pivot_DisplayPoint`, spins once per 9 s and bobs. Both come from `Kit.Now()`, so every client matches. It has a sparkle ParticleEmitter (engine texture `sparkles_main.dds`, Rate 7, idles beyond 150 studs), a soft SpotLight under the downlight lens, and a faint gold PointLight (2 lights).
  - A **design change** pops the old trophy out (0.18 s) and the new one in with a back-ease (0.42 s), with Whoosh and a sparkle burst.
  - **Far viewers (fix pass 2026-09-24):** at most two trophies ever exist (the one on show + one popping out); a change that lands while an old trophy is still popping out removes that one at once. While the camera is beyond StepRange (140 studs, the Step sleeps) a change swaps instantly at full size, with no pop or whoosh. The existing 1 s check (ctx:Every(1), also the emitter idle) then finishes any pop, shine or light flash that was running when the camera left, so no trophy is left stuck small, white or Neon. Trophy parts are owned by the client FX folder, not ctx:Add, so a swapped-out trophy leaves nothing in the ctx list.
  - On **Admire**, a shine band sweeps up the trophy: parts ease toward white and flip to Neon inside the band. There is also a sparkle burst, a PointLight flash, one extra eased twirl, and the Sparkle sound. Events more than 1.5 s old are skipped.
  - `GlassPanes` are drawn as **SmoothPlastic** (Reflectance at least 0.12) while running, because Roblox Glass hides every transparent thing behind it: the sparkles, the diamond and the LightBeam. Material and Reflectance are restored on cleanup. Transparency is never touched.
  - Non-owners get `MaxActivationDistance = 0` on `ChangeTrophyPrompt`. Build mode's Enabled toggling does not undo that.
  - While the server behaviour restarts (`Fun_Design` goes nil for a moment), the trophy on show is kept, so no spurious swap happens.

## Parts / pivots relied on
`Plinth` (prompt host; falls back to the Hitbox), `GlassPanes`, `LightBeam`, `Pivot_DisplayPoint`. Fallback for the pivot is authored `(0, 3.05, 0)`. Authored geometry comes from `props/build_glass_case.py`:
- display volume y 3.05 to 4.35
- downlight collar down to 4.39, with its ring and lens around 4.53 to 4.6, 0.18 back from centre
- TROPHY plate at x ±1.24, y 0.28 to 0.78, face z -1.44

## Sounds
`FunAssets.Sfx.Sparkle` (admire, volume 0.7), `FunAssets.Sfx.Whoosh` (swap, 0.3). **Wish:** a proper "ta-da / chime glint" one-shot for Admire; `Sparkle` is "Magic Shimmer" today.

## How to test
1. Place a Glass Case. `Fun_Design` should be 1 and the golden cucumber should float and spin in the case. The nameplate should read `<you>'s Trophy`.
2. As the owner, press F on "Change trophy" 5 times. It cycles through the five designs with a pop and whoosh and wraps back to 1. A second player sees only "Admire".
3. Press E on "Admire". You should see the shine sweep, sparkles, flash, twirl and sound. Spamming does nothing for 1.2 s.
4. Move the build: the design is kept. Break it (`BuildHealthDev` "break"): everything goes away and the panes stay non-colliding. Heal it and it comes back with the same design.

## Offline checks (already run: all passed)
- `tools/glasscase_check/run_scenario.ps1` runs the four real modules on mock Instances/ctx (shim + runtime + scenario). It covers:
  - server and client start, prompts, owner gating, the nameplate text and position
  - the float height, the shine turning Neon then restoring, the admire cooldown
  - all 5 designs with part counts, the nil-state guard, and cleanup restores (Glass material, CanCollide)
  - fix pass: the mock ctx now sleeps the Step past StepRange. It checks that 60 changes while the camera is far leave exactly one full-size trophy, that 3 rapid changes nearby keep 2 trophies, and that leaving the camera mid-pop or mid-shine settles to one full-size trophy with its normal looks and glow
- `tools/glasscase_check/dump_geometry.ps1` then `preview.py` (headless Blender: `blender -b --factory-startup --python preview.py -- trophies|case|neon`) renders the real `TrophySpecs` output.
- Renders:
  - `models/renders/GlassCase_trophies.png`
  - `GlassCase_trophies_top.png`
  - `GlassCase_case_1..5.png`: each trophy inside the original case at the bob peak, plus the nameplate block. The diamond is drawn opaque there because EEVEE drops transparent-behind-transparent.

## Known limits
- The Blender glass case renders dim because of its alpha 0.5 tint. In game the SpotLight lights the trophy.
- The trophy is local to each client. Pose, shine and state are synced by server time and state, but pop animations run on each client's own clock.
- The nameplate shows the Roblox **username** (as briefed), not the DisplayName.
