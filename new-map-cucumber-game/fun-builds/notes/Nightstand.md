# Nightstand - new Home build + behaviour (HomeBedroom, 2026-09-24)

Files: `models/build_Nightstand.py` -> `models/out/Nightstand.parts.json` (install with
`install/install_models.lua`, key `"Nightstand"`, category Home), `src/behaviours/server/Nightstand.lua` ->
`ServerStorage.FunBehaviours.Nightstand`, `src/behaviours/client/Nightstand.lua` ->
`ReplicatedStorage.FunBehavioursClient.Nightstand`.
Renders: `models/renders/Nightstand_front.png`, `_three.png`, `_back.png`.

## The model
47 parts, cabinet 2.44 wide x 2.6 tall x 2.0 deep (lamp finial at 4.73; knob pokes to z -1.35), `Cost = 300`.
Wooden carcass on brass-capped legs, rounded front lip on the top, a blue drawer (matches the Bed's quilt) with a
light-blue raised panel and a brass knob, an open shelf with three standing books and two lying ones. On top: a
table lamp (brass foot, red ceramic ball base, brass stem, cream drum shade with yellow trims, inner discs at
the shade's open ends, a finial, a pull cord with a bead) and a blue twin-bell alarm clock (brass bells and
rim, cream face, dark hands, red centre pin).

## What it does
* **Server**: a Custom prompt **"Lamp on/off"** (object = DisplayName or "Nightstand", distance 8,
  name `LampPrompt`) on `LampShade`; anyone may flip it, 0.3 s cooldown. State `Fun_On` (bool, starts false).
* **Client**:
  * `Fun_On = true`: a warm PointLight `LampLight` in `LampShade` (colour 255,196,128, Brightness 1.4,
    Range 16, no shadows) comes up over 0.18 s, `ShadeInnerTop` / `ShadeInnerBottom` turn Neon warm yellow,
    the shade fabric warms in colour; a Click (pitched up on, down off). No click on stream-in.
  * the alarm clock's `ClockHour` / `ClockMinute` turn about `Pivot_ClockCentre` (build's local Z axis) to
    `Lighting.ClockTime` (hour hand = ClockTime mod 12, minute hand = fraction of the hour), updated every
    0.2 s while the camera is within 110 studs.
  Cleanup restores the shade colour, the inner discs and the hands (at 12).

## Relies on
* Parts `LampShade`, `ShadeInnerTop`, `ShadeInnerBottom` (prefix `ShadeInner`), `ClockHour`, `ClockMinute`.
* Attribute `Pivot_ClockCentre` (no hands animation without it); `Pivot_Lamp` (informational).

## Sounds
* `Sfx.Click` for the switch - fine. (Wish, optional: a real lamp pull-chain click.)

## How to test
1. Install `Nightstand`, place it, walk up: prompt "Lamp on/off" at the lamp.
2. Trigger: server `Fun_On = true`; client: `LampShade.LampLight` enabled, Brightness 1.4, the shade ends glow.
   Trigger again: off. Spamming E toggles at most ~3 times a second.
3. Watch the clock: set `Lighting.ClockTime = 3.5` -> hour hand at half past 3, minute hand at 6.
4. Move / sell / break it: light gone, parts back at rest; after a move the lamp starts off.

## Known limits
* The lamp state is not saved: it starts off whenever the behaviour (re)starts (placed, moved, rejoined, mended).
* The clock follows the in-game day/night clock, so its minute hand moves quickly (a game hour is short).
