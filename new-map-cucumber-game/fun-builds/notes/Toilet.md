# Toilet - new Home build + behaviour (HomeBath package, 2026-09-24)

Files:
* model `models/build_Toilet.py` -> `models/out/Toilet.parts.json` (34 parts, 3.09 x 5.05 x 3.45 studs incl.
  the plant and the bath mat, category **Home**, `Cost = 300`), renders `models/renders/Toilet_front.png / _three.png / _back.png`
* `src/behaviours/server/Toilet.lua` -> `ServerStorage.FunBehaviours.Toilet`
* `src/behaviours/client/Toilet.lua` -> `ReplicatedStorage.FunBehavioursClient.Toilet`

Build it at **scale 1** (seat top 2.12, cistern top 3.98).

## The model
A white porcelain toilet facing the front (-Z):
* **Base**: an oval foot, a vase-like pedestal (Ellipsoids) with two bolt caps.
* **Bowl and seat**: a round bowl under a light-wood seat. The opening is painted as a grey ring around blue
  `BowlWater`. The wooden lid is raised and leans on the cistern.
* **Cistern**: a boxy cistern with a base trim and a lid with rounded edges.
* **Flush lever** (`HandleLever` + `HandleKnob` + `HandleHub` on a round `FlushPlate`) on the cistern's
  front-left (+X) corner. It points out past the side, so it shows beside the raised lid.
* **Back**: a chrome supply pipe with a stop valve.
* **Extras**: a spare toilet roll and a little potted plant on the cistern lid, and a blue oval bath mat
  under the front. Every detail part is `collide = false`.

## What it does
* **Server**
  * A **seat** (`ToiletSeat`, prompt **"Sit"** (E), distance 8, anyone). Its top face is at `Pivot_Seat`
    (0, 2.12, -0.15), facing the build's front.
  * A **"Flush"** prompt (R / ButtonY, distance 8) hangs 0.5 authored studs in front of `Pivot_Handle`
    (host `FlushPlate`). It works standing or sitting, because the sit prompt hides while the seat is taken
    but the flush prompt stays.
  * Pressing it stamps `Fun_FlushAt = Kit.Now()`, at most one flush per 3 s per toilet.
* **Client** (every client plays the flush from `Fun_FlushAt`, so they agree):
  * The `Handle*` parts dip 38 degrees about `Pivot_Handle`. They are pressed by 0.12 s, held to 0.5 s and
    back at rest by 0.95 s. The dip axis is (lever x down), so the knob end always goes down.
  * 0.15-2.3 s: a blue swirl. Three sparkle trails orbit `Pivot_Bowl` on a spiral that shrinks, sinks and
    speeds up, and flat blue rings spin and shrink into the middle. The `BowlWater` darkens while it drains.
  * A ripple ring marks the refill.
  * Sounds: `Sfx.Click` (the lever) and `Sfx.Flush`, but only for a flush under 0.8 s old. A client that
    streams in mid-flush sees the rest silently. A stamp up to 0.5 s in the FUTURE still plays: a client's
    `GetServerTimeNow` estimate can trail the server's stamp a hair (near-zero latency, e.g. Studio solo), and
    the flusher must hear it (fix pass 2026-09-24).
  * Cleanup puts the lever back at rest (relative to the Hitbox now) and restores the `BowlWater` colour.
  * The Step does nothing between flushes.

## Relies on
* Parts: `Handle*` (moving group), `FlushPlate` (prompt host; falls back to `Tank`, then the Hitbox),
  `BowlWater` (optional colour).
* Attributes: `Pivot_Seat`, `Pivot_Handle`, `Pivot_Bowl`. Both halves hold the same numbers as fallbacks.
* State: `Fun_FlushAt` (server time of the last flush, 0 = never).

## Sounds
* `Sfx.Flush` is a real, verified toilet-flush rush in `FunAssets.lua` (4.3 s, checked 2026-09-24). Keep it.
* `Sfx.Click` works for the lever. **Wish:** a heavier "clunk" would be nicer.

## How to test
1. Place a Toilet (Home). At the front: **"Sit"** (E). The avatar sits on the seat facing out. The seat's
   `Occupant` is set and the Sit prompt hides.
2. Press **R "Flush"** (standing or sitting). The lever dips and springs back, a blue swirl spins down the
   bowl, the water darkens and clears, and the flush sound plays. `Fun_FlushAt` is about
   `workspace:GetServerTimeNow()`. Pressing again within 3 s is ignored.
3. A second client sees the same flush in step. A client arriving mid-flush sees the rest silently.

## Known limits
* The bowl opening is painted (flat ellipsoid rings), not a real hole. It reads from standing height.
* The lid is fixed raised (decorative). Only the lever animates.
