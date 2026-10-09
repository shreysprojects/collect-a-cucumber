# HomeLiving package: Sofa, Armchair, CoffeeTable (2026-09-24, fix pass after review)

Three new **Home** builds, made of primlib parts (no asset upload needed), plus one behaviour module pair that
serves both couches.

| Key | Size (w x h x d) | Parts | Cost | Behaviour |
|---|---|---|---|---|
| `Sofa` | 8.0 x 3.62 x 3.53 | 64 | 800 | 3 seats, cushion squash + poof |
| `Armchair` | 4.3 x 3.73 x 3.62 | 58 | 400 | 1 seat, cushion squash + poof |
| `CoffeeTable` | 5.0 x 2.79 x 3.0 (top at 1.8) | 46 | 250 | none, decoration only |

## Files
* `models/couchlib.py`: the shared couch look, so the Sofa and Armchair match exactly
* `models/build_Sofa.py`, `models/build_Armchair.py`, `models/build_CoffeeTable.py`
* `models/out/Sofa.parts.json`, `Armchair.parts.json`, `CoffeeTable.parts.json` (for `install/install_models.lua`)
* `models/out/Sofa.fbx` + `Sofa.mesh.json`: re-exported after this fix pass (16 meshes, new pivots). The earlier
  export had the old pivots (y 2.05) and old part names, so do not upload an FBX from before 03:44 on 2026-09-24.
* renders: `models/renders/{Sofa,Armchair,CoffeeTable}_{front,three,back}.png`
* `src/behaviours/server/Sofa.lua` goes to `ServerStorage.FunBehaviours.Sofa`
* `src/behaviours/client/Sofa.lua` goes to `ReplicatedStorage.FunBehavioursClient.Sofa`
* Both halves set `B.Keys = {"Sofa", "Armchair"}`, so there is one module per side and no `Armchair` module.

## Look
Chunky rolled-arm couch in the toy palette. It has a blue Fabric body (`3264b8`), lighter cushions (`6a9ef0`) and
cream piping (`f2f0ea`) along the base, the arm scroll edges, the back roll and the back panel. The arms have
piped roll caps front and back, and there is a wooden plinth rail on turned bun feet with brass tips. The seat
cushions are a block base with an Ellipsoid puff on top. The back cushions are a boxy core with a rounded top,
a seam, and a soft puff on the face that tilts back 12 degrees. The Sofa has yellow and red square throw pillows
in the corners. The Armchair has a red-and-cream striped knitted throw with tassels folded over its back.
The CoffeeTable has a round-edged wooden top (slab, edge cylinders and corner balls) with an inlay, a dark
apron with a drawer and brass knob, turned legs with brass caps, and a lower shelf with a stack of books. On
top are a fruit bowl (orange, red apple with a stem and leaf, green apple, banana and a cucumber), a
"Cucumber Monthly" magazine on a second magazine, and a red mug of coffee on a coaster.

## Parts and pivots the behaviour relies on (authored frame, scale 1)
* `Pivot_Seat1..3` (Sofa) and `Pivot_Seat1` (Armchair) are at **y 1.912, z -0.1**, and x is each cushion's
  centre. The Sofa's cushions are at x = +2, 0 and -2, and Seat1 is on the viewer's left (+X) when standing in front.
  * y 1.912 is the **squashed** top of the seat puff: the puff runs from 1.45 to 2.11 at rest and loses 30 % of its
    height while someone sits (`couchlib.REST_SQUASH` = `SQUASH_Y` in the client, keep them equal). The server puts
    the invisible Seat's top face on the pivot and the sitter is welded to it. With the contract's measured sitting
    root (1.7 above the seat top), an R15 thigh's underside is about at seat-top height, so the thighs now rest in
    the dent. Before this fix the pivot was at the rest top (2.05) and sitters hovered about 0.08 to 0.15 above the
    squashed cushion.
  * z -0.1 (was -0.2) puts a sitter's back (root z + ~0.6) on the back-cushion puff once it has flattened.
* The server puts an invisible Seat (1.8 x 0.4 x 1.8) with its top face on the pivot, facing the build's front (-Z).
* `Cushion<i>` is the seat puff: an Ellipsoid, meaning a Block with a SpecialMesh Sphere.
* `BackCushion<i>` is the back-cushion face puff: an Ellipsoid tilted 12 degrees about X.
* The other cushion pieces are named `CushBase<i>`, `CushPipe<i>`, `BackCore<i>`, `BackTop<i>` and `BackSeam<i>`.
  They were renamed from `Cushion<i>Base` and so on so they no longer start with a Sofa.lua string literal and the
  mesh export merges them. Nothing refers to them by name.
* Model attributes: `Cost`, `Seats` (3 or 1, informational only) and `Notes`.

## What the behaviour does
* **Server:** for each `Pivot_Seat<i>` it calls `ctx:Seat(...)`, which gives the framework's "Sit" prompt
  (distance 8, OnePerButton, so on the Sofa only the nearest cushion shows it). Anyone may sit. State
  `Fun_Seat<i>` holds the sitter's UserId, 0 when the seat is empty, or -1 for a humanoid that is not a player.
* **Client:** while `Fun_Seat<i>` is not 0, `Cushion<i>` stays squashed: 30 % lower with its bottom held still,
  and 5 % wider. `BackCushion<i>` flattens 30 % of its depth toward the back and spreads 4.5 % on its other two
  axes. A damped spring drives the squash (k 170, c 11). Sitting down plops the cushion to about 1.25x the rest
  squash (Scale.Y 0.63) and it wobbles back in about 1 s. Getting up over-puffs it to 1.07x its height. A real
  change also emits 9 wisps on sit or 4 on stand (the built-in `smoke_main.dds` texture tinted from the cushion
  colour, burst only, Rate 0) and plays a muffled poof.
* **Parts route** (Block + SpecialMesh): the squash only changes the SpecialMesh `Scale` and `Offset`. The part
  never moves or resizes, so collisions, the placement overlap test and BuildHealthService's broken fade are
  unaffected.
* **Merged-mesh route** (a MeshPart, no SpecialMesh): the part is resized on this client, and its CFrame is always
  set as `Hitbox.CFrame * rel * shift`, where `rel` is its offset from the Hitbox taken when the behaviour starts.
  The Hitbox is placed by the server and never changed by this client, so a move while someone sits cannot leave
  the cushion off by the old squash. (The first version nudged the part from its own CFrame. After a move the
  server's true CFrame replaced the nudge, and the restore then subtracted it a second time.) Which face stays put
  is looked up per part from the authored direction (down for the seat puff, back for the back cushion). A
  MeshPart that the importer turned 180 degrees still flattens toward the back.
* A state found on stream-in, or a change while the camera is more than 140 studs away, snaps to the pose
  with no poof. At most one `ctx:Step` runs per build, and it only does work while a spring is settling.
  The wisp holders are local `ctx:Part`s (one per cushion), and each has one Sound. The cleanup restores everything.
* An offline Luau run of the client module against mocks (Parts route, MeshPart route, MeshPart turned 180 degrees,
  moved while seated, moved in the middle of the plop) checked all 33 cases. It confirmed that the squashed top
  lands exactly on `Pivot_Seat1.Y` (1.912), the bottom stays at 1.45, the back face of the back cushion stays still,
  and the cushion is back in its true place with its true size after a move and the cleanup.

## Merged-mesh export (models/export_mesh.py)
* `export_mesh.literals_for(key)` used to read only `src/behaviours/*/<Key>.lua`. There is no `Armchair.lua`,
  so an Armchair export would have merged `Cushion1` and `BackCushion1` into `_m` meshes. The client would then
  find no `Cushion1` and return early, with no error. **Fixed in this pass:** `literals_for` now also reads every
  behaviour module whose `B.Keys` lists the key or one of its variants (the new `serves()` helper). This only adds
  literals, so other builds export exactly as before. Checked with a scratch export: the Armchair keeps `Cushion1` and
  `BackCushion1` (10 meshes) and the Sofa keeps `Cushion1..3` and `BackCushion1..3` (16 meshes, down from 30
  because of the renames above).
* **If that change to export_mesh.py is ever reverted:** export the Armchair with the Sofa.lua literals, or keep
  the Armchair on the Parts route. Otherwise its squash silently stops working.

## Sounds
* The poof uses `FunAssets.Sfx.CushionPoof` if it exists, otherwise `FunAssets.Sfx.Whoosh`. It plays at
  PlaybackSpeed 0.6 on sit and 0.8 on stand, Volume 0.4, RollOffMax 60.
* **Wish:** add `Sfx.CushionPoof` to FunAssets: a soft fabric thump or pillow "pomf", short (under 0.5 s). The
  client picks it up automatically.

## BuildCatalog suggestions
* `DEFAULT_CATEGORY`: `Sofa = "Home", Armchair = "Home", CoffeeTable = "Home"`. The parts.json category is already "Home".
* `DEFAULT_COST`: `Sofa = 800, Armchair = 400, CoffeeTable = 250`. The Cost attribute already carries these.
* `SCALE`: leave all three at 1. They are authored for the 6-stud avatar: seat 1.9 to 2.1, back 3.6, table top 1.8.
  The behaviour copes with any scale because the pivots go through `Kit.Pivot` and the particles use `ctx.Scale`.

## How to test
1. Install: `install_models.lua` with `{"Sofa", "Armchair", "CoffeeTable"}` (or the mesh route: re-export first),
   then add the two Sofa.lua modules to FunBehaviours and FunBehavioursClient.
2. Place a Sofa. Walk up to it and a "Sit" prompt ("Sofa") appears at the nearest cushion. Press E.
   * Server check: `model:GetAttribute("Fun_Seat1..3")` shows the UserId on the taken seat and 0 on the others.
   * Client check (Parts route): that cushion's `SpecialMesh.Scale` settles at (1.05, 0.7, 1.05), with Offset.Y
     about -0.099. A burst of pale-blue wisps and a poof play. Jump off, and Scale returns to (1, 1, 1) after a
     brief over-puff.
   * **Seat contact check (new):** while seated, the bottom of the sitter's `LeftUpperLeg` / `RightUpperLeg` should
     touch the squashed `Cushion<i>`: `UpperLeg.Position.Y - UpperLeg.Size.Y / 2` within about 0.1 of
     `Kit.Pivot(model, "Seat<i>").Y`. The back of the `UpperTorso` should touch the back cushion. If there is a
     gap or an overlap, change `SEAT_Y` / `SEAT_Z` in `models/couchlib.py` (one place for both couches) and rebuild.
   * **Also look at (the R15 sit pose was not measured, only the root height):** with the knees about 1.1 in front
     of the root, the shins may partly sink into the couch's front face, and hanging arms may dip into the
     armrests. The seat is about 0.4 deeper than an R15 back-to-knee, so moving the seat forward only trades a
     back gap for less shin clipping. If it looks bad, the fix is a shallower seat in couchlib (thicker back
     cushions).
3. Move the sofa with a player seated: the seats are recreated at the new spot, the occupant is unseated and
   the squash resets, and every cushion sits exactly where it belongs (also on the mesh route). Break it
   (`Broken = true`): the seats disappear and the meshes return to (1, 1, 1).
4. Armchair: same, with `Fun_Seat1` only.

## Z-fighting (contract: no near-coplanar faces)
* The review found the Armchair throw stripes were only 0.003 to 0.015 off the tilted throw panel. They are now
  placed in the panel's own tilted frame, sunk 0.02 into it and standing 0.04 proud, and 0.03 past each side.
  `ThrowStripeTop` stands 0.035 above `ThrowTop`. The fold rolls run 0.02 past the throw's sides. The tassels hang in
  the panel's tilt, with their back faces 0.02 proud.
* A scan of every same-facing face pair within 0.02 of each other found a few more, which are fixed:
  * `Plinth` is now 3.30 deep, 0.02 or more proud of the arms and base.
  * `BackRoll` runs 0.02 past the back panel's sides, so its end caps no longer sit on the panel's side faces.
  * `BackPiping` and `BackTop<i>` / `BackSeam<i>` are shortened so their caps sit 0.02 or more inside the faces next to them.
  * CoffeeTable: `TopInlay` now stands 0.02 proud of the top. `Coaster` is 0.02 above the magazine it overlaps.
    `MugCoffee` is 0.02 above the rim. The handle bars are 0.02 inside the grip's faces. The leg tops go into the slab.
* The pairs still reported are all hidden inside other parts, or are faces of the same colour and material that
  something else covers (such as the arm-roll ends under the piped back caps).

## Known limits / open questions
* The Sofa's throw pillows sit in the back corners. A sitter on Seat1 or Seat3 leans on one: the pillow is mostly
  inside the torso, with some of it showing between the back and the back cushion. The pillows are CanCollide false.
* Seat size does not scale with `Scale`, which is fine for 1.0 to 1.5.
* No lying down on the Sofa. Adding a `ctx:Seat{Lie = true}` "Nap" prompt would be easy if wanted.
* Checked with headless Blender renders, a seated R15-proportioned blockout render with the cushions squashed,
  and an offline Luau run of the client module. Nothing has been run in Studio yet.
