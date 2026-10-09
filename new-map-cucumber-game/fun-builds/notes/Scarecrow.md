# Scarecrow - functional behaviour (2026-09-24, package GardenLife)

Files: `src/behaviours/server/Scarecrow.lua` -> `ServerStorage.FunBehaviours.Scarecrow` and
`src/behaviours/client/Scarecrow.lua` -> `ReplicatedStorage.FunBehavioursClient.Scarecrow`. The Scarecrow is x1.35.

## What it does
* **The crow** is built from parts at runtime (8 local `ctx:Part`s in a Model `FunCrow` under the camera):
  - body, head, tail and two oval wings (SpecialMesh Sphere)
  - a yellow wedge beak (SpecialMesh Wedge)
  - two white eye glints

  It is about 1.3 studs long in game. It sits on `Pivot_CrowPerch`, which is the body centre of the authored crow,
  facing out along the arm like the authored one. The authored `Crow` / `CrowBeak` meshes get Transparency 1 on
  each client while this runs.

  Review render: `models/renders/_CrowPreview_front.png` and `_three.png`. `models/build__CrowPreview.py` mirrors
  the Luau numbers. The poses shown are perched, wings up, flying, and head turned. It is not shipped.
* **Perched**: the crow breathes (a small bob). Every 2.4 s slot it picks one action: idle, look round (a caw 45% of
  the time), peck twice, flap its wings (Whoosh), or hop. A hop moves it between 2 spots 0.2 authored studs apart on
  the sleeve and turns it to one of 4 headings. The slot comes from the server clock plus a per-build seed and an
  integer hash, so every client shows the same bird doing the same thing.
* **Scared** (server decides, clients animate):
  - A player whose root comes within **8 studs** of the perch (flat, and within 14 studs vertically) scares a crow
    that has been perched for at least 1 s.
  - The server sets `Fun_CrowLeft` (server time), `Fun_CrowBack` (now + 20-40 s) and `Fun_CrowDir`. `Fun_CrowDir`
    is the world heading in radians, pointing away from the player with +/-0.45 of jitter.
  - Clients fly the crow off on a climbing, curving arc: 2.6 s, about 53 studs out and 20 up, fading out over the
    last 28%. Take-off plays Whoosh + Caw.
  - 3.3 s before `Fun_CrowBack` the server checks again. If a player is still within 8 studs, it pushes the return
    back 6-12 s. Tested: 3 pushes while a player stood there, then the crow landed after they left.
  - The flight home takes 2.8 s and comes in from about the same side: flapping, then a glide, then a nose-up flare
    with wings folded onto spot 0. Landing plays Whoosh.
  - Simulated flight: at most 0.71 studs per frame at 60 fps, with no pops at the phase changes.

## Relies on
* `Pivot_CrowPerch`. If it's missing, the behaviour uses the position of the authored `Crow` part.
* The parts `Crow` and `CrowBeak` (hidden), and `Frame` or `Burlap`. The crow copies that part's
  LocalTransparencyModifier, so it fades with the build-mode move ghost.
* State (server -> clients): `Fun_CrowLeft`, `Fun_CrowBack`, `Fun_CrowDir`. All three are 0 = perched from the
  start. The client's `RETURN_T` (2.8) must stay equal to the server's `RETURN_T`.

## Sounds - wishes
* **`FunAssets.Sfx.Caw` is wanted**: a crow caw one-shot, about 0.5 s. FunAssets has nothing like it, so the code
  reads `FunAssets.Sfx.Caw` and stays silent while it is nil. Adding the entry is all it takes; no code change.
* Flap / take-off / landing use `FunAssets.Sfx.Whoosh`, as the brief asked.
* Every sound respects the player attribute `SFXEnabled == false` and plays only with the camera within 80 studs.

## How to test
1. Place a Scarecrow and watch from about 15 studs. The crow bobs, looks round, pecks, flaps and hops on the sleeve.
   The authored crow is gone on the client.
2. Walk up to it. When you're within 8 studs it flies off away from you. Server check: the model attributes
   `Fun_CrowLeft` / `Fun_CrowBack` / `Fun_CrowDir` change.
3. Stand there. `Fun_CrowBack` keeps getting pushed later. Walk away and it lands 6-12 s later.
4. Sell it or break it: on cleanup the authored crow comes back, unless the broken fade changed its Transparency.

## Known limits
* The authored crow's collision box stays on the server. It is invisible and tiny.
* A second client joining mid-trip picks up from the replicated state, so the phase is correct. The take-off pose of
  a trip that began before it joined may differ by a hop spot. That is cosmetic only.
