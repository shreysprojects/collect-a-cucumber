# GrandfatherClock (package HomeOffice, 2026-09-24)

A new **Home** build: a tall wooden longcase clock that tells the game's own day/night time. It is made from
primlib parts, so no asset upload is needed.

| Key | Size (w x h x d) | Parts | Cost | Behaviour |
|---|---|---|---|---|
| `GrandfatherClock` | 2.66 x 8.5 x 1.86 (body 2.6 x 8.5 x 1.6; the hands' cap sticks out) | 70 | 1500 | pendulum, hands show `Lighting.ClockTime`, sun/moon dial, tick, hourly strikes |

## Files
* `models/build_GrandfatherClock.py` produces `models/out/GrandfatherClock.parts.json`.
* Renders: `models/renders/GrandfatherClock_front.png`, `_three.png`, `_back.png`.
* `src/behaviours/client/GrandfatherClock.lua` goes to `ReplicatedStorage.FunBehavioursClient.GrandfatherClock`.
  There is **no server half**: the clock has no prompt and no state.
* Headless test: `tests/HomeOffice/` (`py gen.py`), shared with the GamingDesk.

## Look
* **Base and trunk.** Bun feet, a panelled plinth and a long trunk. The trunk has a glass door (Glass,
  transparency 0.72) with a brass knob. Through the glass you see the brass pendulum and three brass weights on
  chains, against a dark WoodPlanks interior.
* **Hood.** Brass-capped columns stand either side of a navy dial plate with four gold corner spandrels. The dial
  has a brass bezel, a cream face with 12 hour marks (bigger at 12, 3, 6 and 9) and black spade-tipped hands.
* **Crown.** An arched crown with a brass rim holds a turning sun/moon dial (a navy disc with a Neon sun, a cream
  moon and two stars). There are three brass finials.
* The part budget is 70, the furniture limit.

## Parts and pivots the behaviour relies on (authored frame, scale 1)
* `PendulumRod`, `PendulumBob` and `PendulumBobFace` (the `Pendulum*` parts) swing about `Pivot_PendulumPivot`
  (0, 5.12, -0.22). It ships at rest, and `State_PendulumSwing` = 6 degrees.
* `HourHand` and `HourHandTip` turn about `Pivot_FaceCentre` (0, 6.25, -0.93). They ship at `State_HourAngle` = 305,
  clockwise from 12.
* `MinuteHand` and `MinuteHandTip` turn about the same pivot. They ship at `State_MinuteAngle` = 60, so the model
  shows 10:10.
* `MoonDisc`, `MoonSun`, `MoonMoon`, `MoonStarA` and `MoonStarB` turn about `Pivot_MoonCentre` (0, 7.5, -0.625).
  They ship at `State_MoonAngle` = 0, with the sun at the top, which means noon. The disc's lower half hides inside
  the hood behind the cornice.
* `Pivot_Chime` (0, 6.3, 0) is the movement inside the hood, where the tick and the strikes come from.
* All rotations are about the build's authored Z axis. A positive angle is clockwise seen from the front:
  CFrame.Angles(0, 0, rad(a)).
* Model attributes: `Cost` 1500, `DisplayName` "Grandfather Clock", and the four `State_*` angles.

## What it does (client only)
* **Pendulum.** It swings ±6 degrees with a 2 s period, phased from `Kit.Now()`, so every client swings in step. At
  each end of the swing it plays a soft tick-tock (`Sfx.ClockTick`, pitches 1.0 and 0.86, volume 0.22) while your
  character is within 22 studs.
* **Hands.** They show the game's time, read from the live `ServerScriptService.DayNightCycle` (BRIGHT NIGHT
  version, 2026-09-23):
  * **By day** they show `Lighting.ClockTime`, which runs from 11:00 to 16:00 over each 180 s day, so one in-game
    hour takes 36 s and the minute hand moves visibly, about 10 degrees a second. The day loop stops just short of
    16:00 (about 15.997).
  * **By night** (`workspace.IsNight` = true, 10 s) they show **midnight**, whatever `ClockTime` says. The bright
    night leaves `ClockTime` at the day's last value unless DayNightCycle has a `NightClockTime` attribute, so the
    clock deliberately does not read it at night. It works the same with or without `NightClockTime`.
  * The shown time only ever moves **forward**. When the time jumps, the hands whirr round at 5 hours a second with
    a fast ticking. Night falls as a whirr from about 16:00 on to midnight (8 h, 1.6 s). Day breaks as a whirr from
    midnight to 11:00 (11 h, about 2.2 s). `ClockTime` keeps running during that whirr, so the hands land at about
    11:04 and then follow the clock.
  * A small step back is held rather than run backwards.
* **Sun/moon dial.** It turns once every 24 hours of shown time. The sun is at the top at noon and the moon at the
  top at midnight, so the moon is up all night. The sun rises on the left and sets on the right.
* **Strikes.** Every in-game hour the clock strikes the hour: 1 to 12 strikes of `Sfx.ClockChime`, 1.1 s apart, on
  two alternating Sounds so each ring carries under the next.
  * A whirr that lands on an hour, or up to 0.25 h past it because the clock kept running, strikes that hour too.
  * Hours are queued. Midnight's twelve strikes (13 s) outlast the 10 s night, so daybreak's eleven follow them
    after a 1.1 s pause instead of cutting them off. At most 2 hours wait, and a wake clears the queue.
  * In a normal 190 s cycle you hear: **12 at midnight**, starting about 1.6 s into the night as the zombies come;
    **11 at daybreak**, right after midnight's last strike; **12 at noon**; then **1, 2 and 3**. That is 41 strikes.
    16:00 is never struck, because the day ends just before it.
  * Strikes start only within 120 studs of the camera. `MAX_STRIKES` in the config caps the count; set it to 1 for a
    single chime per hour.
* **Performance.** Poses are relative to the Hitbox. The pendulum is posed every frame (3 parts). The hands and the
  moon dial are posed only when they move. The single `ctx:Step` sleeps beyond 160 studs. A wake snaps the time
  with no sounds.
* **Cleanup** puts every rigged part back as shipped, relative to where the Hitbox is now.

## Sounds
* `Sfx.ClockTick` is a single small metal tick (0.36 s) and `Sfx.ClockChime` is a single low bell strike (1.5 s).
  Both are already in `FunAssets.lua`, so there are **no sound wishes**.
* The code only reads those two names, so it picks up any later change to the ids automatically.

## BuildCatalog suggestions
* `DEFAULT_CATEGORY.GrandfatherClock = "Home"`. The parts.json category is already "Home".
* `DEFAULT_COST.GrandfatherClock = 1500`. This is also on the `Cost` attribute.
* `SCALE`: leave it at 1. At 8.5 studs it stands well above the 6-stud avatar. It was tested at 1.0 and 1.25.
* The footprint is 2.7 x 1.9 and needs a 4 x 4 cell or smaller. It is meant to stand against a wall, facing into the
  room.

## How to test (Studio)
1. Install: `install_models.lua` with `{"GrandfatherClock"}`, then add the client module.
2. Place the clock by day.
   * The pendulum swings, and you hear tick-tock when you stand next to it.
   * The hands show the time: at `Lighting.ClockTime` 13.5 the minute hand is at 6 and the hour hand halfway
     between 1 and 2.
   * Every 36 s the clock strikes the hour.
3. Force night with `ServerStorage.DayNightAPI.Force:Fire("Night")`, or wait for it. `workspace.IsNight` turns
   true while `Lighting.ClockTime` stays at about 15.997. The hands whirr forward from about 4:00 to 12:00 in
   about 1.6 s, the moon comes up in the arch, and the clock starts striking twelve.
4. When day breaks (after 10 s), the hands whirr round to 11:00, landing at about 11:04. After midnight's last
   strike and a short pause, the clock strikes eleven.
5. Break it or move it: the parts snap back to the shipped 10:10 pose (Broken) or re-pose at the new spot.

## Headless test (`tests/HomeOffice`, `py gen.py`)
The clock part plays the live cycle. The day ends at 15.9972 with no strike. The night then sets `IsNight` with
`ClockTime` held at 15.9972; the x1.25 run tweens it to 0 instead, as a `NightClockTime` setup would. Checks:
* The hands are mid-whirr 0.5 s in, reach 12:00 and stay there, and the moon comes up.
* 7 to 12 strikes fall inside the 10 s night.
* At daybreak `ClockTime` keeps advancing at 5/180 h/s during the whirr. Once it lands, the hour hand follows it.
* Night plus daybreak strike exactly 23 (12 + 11), and noon then strikes exactly 12.

The same tests run against the old code fail. The old ClockTime-only target gives 0 strikes at night and no
midnight. The old 0.02 h landing rule gives only 12 strikes, because daybreak's eleven never come.

## Known limits / open questions
* In-game, 16:00 is never struck, because the day ends just before it and the hands whirr on to midnight.
* It is client only. By day it follows `Lighting.ClockTime` (so `DayClockStart` / `DayClockEnd` on DayNightCycle
  are respected). By night it relies on `workspace.IsNight`. If DayNightCycle stops setting `IsNight`, the hands
  would stay at the day's last time all night.
* So far only the headless mock and the Blender renders have been checked. Nothing has run in Studio yet.
