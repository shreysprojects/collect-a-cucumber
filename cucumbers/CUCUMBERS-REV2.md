# Cucumber set - REVISED briefs (rev 2)

The user supplied a second, more accurate set of reference tiles for **19 models**. These
briefs **supersede** the ones for the same models in `CUCUMBERS.md`. Everything else in
`CUCUMBERS.md` still stands - space and scale, style, the palette, the whole `cucumberlib`
API reference, the hard rules and the module shape. Read that file first; read this one for
your model.

## How to read these

The briefs below are **literal descriptions of the new reference tiles** - what is actually
in the picture for each model. Build what your brief says and nothing more. Do not
generalise from one model to another, and do not carry a pattern over from a model whose
brief does not mention it: each tile is its own spec.

Where a brief differs from the rev-1 model that exists today, the brief wins.

---

## farm

### `FarmWindmillPlant` - `build_farm_windmill_plant.py` - COMPLETE REWRITE
**≈ 3.4 × 1.4 × 5.2.** It is **not** a wooden lattice tower. It is a **cucumber plant whose
flower is a pinwheel**.

- A single upright cucumber **stalk**: a standard `cuke_body` in `cuke_green` with `cuke_stud`
  speckles, but slimmer and taller than default - about `h=3.6, r=0.52`, no nub (the flower
  sits where the nub would be).
- On top, a **four-blade pinwheel flower** standing in the XZ plane facing +Y, centred about
  z 4.3. Each blade is a **rounded square** roughly 1.05 × 1.05 × 0.22, built from
  `D.prism(D.rounded_rect_pts(1.05, 1.05, 0.30, segs=3), ...)`, arranged in a `+` (up, down,
  screen-left, screen-right) with their inner corners about 0.30 from the hub centre. Blade
  face is pale `cuke_pale`; give each one a `cuke_green` **border** (a slightly larger rounded
  square just behind it, 0.10 proud on every side) so the blades read outlined, and a small
  `cuke_stud` square inset near the middle of each.
- The **hub** is wood, not green: a short `D.cyl` along Y of radius 0.34 in `farm_bark`, with
  a smaller `farm_wood` disc on its front face.
- At the base of the stalk, **three `cuke_green` leaves** (`D.leaf_blade`, length ~1.1,
  width ~0.5) splaying out low and nearly horizontal, one to each side and one forward.
- 6 parts: Stalk, Studs, BladeBorders, Blades, Hub, Leaves.
- `PIVOTS = {"FanHub": (0.0, <hub y>, 4.3)}` and `STATES = {"Spin": 90.0}` so a game can turn it.

### `FarmHayBale` - `build_farm_hay_bale.py` - COMPLETE REWRITE
**≈ 4.4 wide × 3.0 × 3.0.** It is **not** a yellow straw block. It is a **round bale-shaped
cucumber roll lying on its side**, and its flat ends are cut-cucumber faces.

- The body is a **cylinder whose axis runs along X**: `D.cyl(bm, (-1.75, 0, 1.45),
  (1.75, 0, 1.45), radius=1.45, segs=14)` in `cuke_green`. It lies on the ground, so its
  centre is at z = its radius.
- **Speckles over the curved surface** in `cuke_stud`: about 16 of them. Place each by hand -
  for a point at distance `u` along X and angle `a` round the axis, the surface point is
  `(u, cos(a)*rr, 1.45 + sin(a)*rr)` with `rr = 1.45*cos(pi/14)`, and its outward normal is
  `(0, cos(a), sin(a))`. Feed those straight to `D.stud_patch(bm, point, normal, size=0.30)`.
  Keep them on the front and top (angles roughly -30° to 200°).
- **Three tan bands** hooping the bale in `farm_crate` (or `sam_bamboo`), at x = -0.95, 0,
  +0.95: each a `D.cyl` along X of radius 1.52, about 0.26 wide, so it stands proud of the body.
- **Both flat ends are cucumber cut faces**: on each end cap a `cuke_pale` disc
  (`D.prism(D.ngon_pts(14, 1.20, phase=pi/14), ...)` standing 0.03 proud of the end) with
  **four `cuke_seed` pips** on it. Use `D.stud_patch` with the normal `(±1, 0, 0)` for the pips.
- 5 parts: Body, Studs, Bands, Faces, Seeds.

---

## samurai

### `SamuraiToriiGate` - `build_samurai_torii_gate.py` - RECOLOUR + REDRESS
**≈ 9.5 wide × 2.0 × 9.5.** The gate is **GREEN, not red**, and it carries a rope and a
cucumber-slice medallion instead of a kanji plaque.

- **Both pillars, the nuki crossbeam and the kasagi top lintel are `cuke_green`** with
  `cuke_stud` square speckles all over them (`D.box_studs`, `grid=(1,4)` on the pillars,
  `grid=(4,1)` on the beams, size ~0.34). Keep the kasagi's upturned ends.
- The pillars stand on **grey stepped stone bases** in `sam_rock` / `sam_rock_dk` - keep those
  as they are, they are correct.
- Slung across the gate just under the kasagi, a **tan twisted rope (shimenawa)** in
  `sam_bamboo`: a `D.tube` along `D.catenary_pts((3.4, 0, 7.4), (-3.4, 0, 7.4), sag=0.55, n=9)`
  with radius about 0.20, thickest in the middle. Hang **two tassels** from it (about
  x = ±1.9): short tapered `D.cyl`s, 0.55 long, radius 0.18 → 0.10, in the same tan.
- Hanging from the middle of the rope, a **cucumber-slice medallion**: a `slice_disc` +
  `slice_face` + `slice_seeds` standing up and facing +Y (`matrix=D.slice_stand((0, 0, 6.4))`),
  radius about 0.80. This replaces the kanji plaque entirely - **remove the plaque and the
  `kanji_samurai` call.**
- Remove the `sam_gold` studs; the speckles are `cuke_stud` green now.
- 7 parts or fewer.

### `SamuraiSakuraTree` - `build_samurai_sakura_tree.py` - CROWN CHANGE
**≈ 6.8 × 5.6 × 11.8.** Keep the whole tree as it is - brown `sam_bark` trunk, pink
`sam_sakura` blossom cubes, grey rocks and grass at the base, falling petals. Two changes:

1. **Every blossom cube carries a cucumber slice on its outward face.** On the front face of
   each crown cube (the -Y face, the one the camera sees), sit a small cut-slice medallion:
   a `cuke_green` rim disc with a `cuke_pale` face and `cuke_seed` pips, radius about 0.62,
   lying flat against the cube face and standing ~0.10 proud. Build them with
   `slice_disc`/`slice_face`/`slice_seeds` and `matrix=D.slice_stand((x, y, z))` positioned on
   each cube's front face. This is the model's whole point - it is a *cucumber* sakura tree.
2. **The trunk carries `cuke_stud` green speckles** (`D.box_studs` on the trunk blocks,
   size ~0.30), not bare bark.

Replace the `sam_sakura_dk` speckles on the cubes with these slice medallions - do not have both.

---

## volcano

**All seven volcano models keep a GREEN cucumber body.** Rev 1 made them black; that is the
error being corrected. Black rock appears only on the two trees' trunks and crowns.

### `VolcanoMoltenSlice` - `build_volcano_molten_slice.py`
The standard slice arrangement (one standing, one leaning, two lying - keep the layout), but:
rims **`des_olive_dk`** (dark olive-green, a charred cucumber skin) with **`cuke_stud_dk`**
speckles; cut faces **glowing `vol_lava`** (ff6a1e, `rbx_material="Neon"`, `emit=0.85`); pips
**`vol_ember`** (e8431a, Neon, `emit=1.0`). A dark green rim around a molten orange interior.
4 parts.

### `VolcanoCharredCucumber` - `build_volcano_charred_cucumber.py`
**≈ 1.6 × 1.6 × 4.5.** A body **charred almost black but still a cucumber**: body
`vol_char_lt` (3e3833) with a green nub, **bright `cuke_stud` GREEN speckles** (the green is
what sells it - about 14 of them, `rows=6, per_row=3, size=0.28`), and a **web of orange lava
cracks** between the charred plates: `D.crack_lines` in `vol_lava` (Neon, `emit=0.9`),
width 0.12 - a long vertical spine around angle 90 from zf 0.12 to 0.88 with four branches
forking off it. **No spikes** - rev 1's spikes are wrong, remove them.
4 parts: Body, Studs, Cracks, and a `cuke_green` nub/shoulder if you want a fifth.

### `VolcanoMoltenCucumber` - `build_volcano_molten_cucumber.py`
**≈ 1.8 × 1.8 × 4.7.** A **normal green cucumber with molten lava pouring down it from the
top.** Body `cuke_green` + `cuke_stud` speckles, standard size and nub.
Over its head, a **lava cap**: a `D.lathe` in `vol_lava` (Neon, `emit=0.95`) sitting on the
top from zf 0.86 upward, spreading to about 1.1× the body radius, with a `vol_lava_hot` hotter
lip. From it, **five or six drips run down the sides** - each a `D.tube` of 3-4 points
following the skin from the cap down to zf 0.30-0.60, radius 0.15 → 0.05, in `vol_lava`.
The drips must hug the body (use `D.cuke_point(..., offset=0.04)` for their path).
Most of the green must still show. 4 parts: Body, Studs, LavaCap, Drips.

### `VolcanoFlameCucumber` - `build_volcano_flame_cucumber.py`
**≈ 2.2 × 2.2 × 4.8.** A **green cucumber wrapped in flame.** Body `cuke_green` + `cuke_stud`
speckles, standard size. Around it a flame ribbon spiralling up:
`D.wrap_ribbon(turns=2.0, z0=0.06, z1=0.95, width=0.52, thick=0.14, phase_deg=-50,
offset=0.05, taper=(1.15, 0.6))` in `vol_lava` (Neon, `emit=1.0`), and a second narrower one
just inside it in `vol_lava_hot` (Neon, `emit=1.2`) as the hot core. Finish with 3-4
`vol_lava_core` flame licks flicking off the top. 5 parts.

### `VolcanoVolcanoCucumber` - `build_volcano_volcano_cucumber.py` - COMPLETE REWRITE
**≈ 3.6 × 3.6 × 4.8.** It is **not** a cucumber with a lava hat. It is an actual **VOLCANO
CONE made of cucumber**: a broad green mountain with lava running down it and lava erupting
off the top.

- The cone: a `D.lathe` in `cuke_green`, 8 or 10 segments, base radius about 1.75 at z 0,
  narrowing to about 0.55 at z 3.5, with a **crater** at the top - run the profile up the
  outside, over the rim, and back DOWN into a shallow bowl so the summit is hollow.
- **`cuke_stud` speckles over the cone's flanks** - place them by hand on the sloped surface
  (about 12), or use `D.stud_patch` with a normal that leans outward and up to match the slope.
- **Lava filling the crater and running down the flanks** in `vol_lava` (Neon, `emit=0.95`):
  a small disc in the crater mouth, plus **four or five flows** spilling over the rim and down
  the outside as `D.tube`s of 4 points, radius 0.22 → 0.08, reaching down to z 0.6-1.6.
- **Three small lava cubes erupting above the crater**, floating at z 4.0-4.7, each a
  `beveled_box` about 0.34 across in `vol_lava_hot` (Neon, `emit=1.2`), at different heights
  and offsets so they read as thrown.
- 5 parts: Cone, Studs, Crater, Flows, Ejecta.

### `VolcanoObsidianTree` - `build_volcano_obsidian_tree.py` - REWORK
**≈ 6.8 × 5.6 × 11.4.** A **black obsidian tree with GREEN CUCUMBERS hanging from it.**
- Trunk and branches: `vol_obsidian` (`"Basalt"`), `stepped_base` + `blocky_trunk` + 3-4
  `branch_box` forks, exactly as now.
- The **crown is angular obsidian ROCK, not cubes**: 5 or 6 chunks built with
  `D.rock(radius 1.1-1.5, seed=…, jitter=0.22, subdiv=1)` in `vol_obsidian`, clustered on the
  forks so the crown reads as a pile of shattered black glass.
- **Orange glowing cracks across the rocks and up the trunk**: thin `beveled_box` strips or
  short `D.tube`s in `vol_lava` (Neon, `emit=0.9`) - enough to read, not a net.
- **Three green cucumbers hang below the branches** - `cuke_body` with `D.CUKE_PROFILE_STUB`,
  h ≈ 2.0, r ≈ 0.36, in `cuke_green` with `cuke_stud` speckles. These are essential; they are
  what makes it a cucumber tree.
- 6 parts: Trunk, Rocks, Cracks, Cukes, CukeStuds (+ Base if separate).

### `VolcanoMagmaTree` - `build_volcano_magma_tree.py` - REWORK
**≈ 7.0 × 5.9 × 11.8.** Same family as the obsidian tree but a **broader canopy of black
cubes veined with magma, and four hanging cucumbers.**
- Trunk, base and branches `vol_char` (`"Basalt"`) with `vol_lava` (Neon, `emit=0.9`) veins
  running up the trunk corners and along the branch tops - keep the veins you have but they
  must be **orange, not yellow**.
- Crown: 5-6 `crown_cube`s in `vol_char` with **`vol_lava_hot` glowing square studs**
  (Neon, `emit=1.0`, `grid=(2,2)`, `size=0.5`) - black cubes cracking open.
- **Four green cucumbers hanging** below the branches, `CUKE_PROFILE_STUB`, h ≈ 2.0,
  r ≈ 0.36, `cuke_green` + `cuke_stud`.
- 6 parts.

---

## snow

**All eight snow models keep a GREEN cucumber.** Rev 1 made the bodies blue ice; that is the
error being corrected. Ice and snow are additions.

### `SnowFrozenSlice` - `build_snow_frozen_slice.py`
The standard slice arrangement and **the standard GREEN slice colours** - `cuke_dark` rims,
`cuke_stud` rim speckles, `cuke_pale` faces, `cuke_seed` pips - with **white snow lying on
top of them**. On the standing disc, a `snow_white` (`"Snow"`) cap over its upper rim
(a curved slab following the top arc, ~0.22 thick, spilling a little over both faces); on each
lying disc, a smaller snow patch on its upward face. 5 parts.

### `SnowSnowcapCucumber` - `build_snow_snowcap_cucumber.py`
**≈ 1.9 × 1.9 × 4.8.** A **normal green cucumber wearing a snow cap.** Body `cuke_green` +
`cuke_stud` speckles, standard size and nub. On top,
`D.cuke_snow_cap(thick=0.34, drips=4, drip_len=0.6, top_zf=0.84)` in `snow_white` (`"Snow"`).
Add **three or four small snow patches** clinging to the body lower down - `D.stud_patch` in
`snow_white` at `size` 0.35-0.5 on facet points around zf 0.35-0.65, so snow has settled on
its shoulders. **No spikes** - rev 1's white spikes are wrong, remove them. 4 parts.

### `SnowSnowballSlice` - `build_snow_snowball_slice.py` - COMPLETE REWRITE
**≈ 2.6 × 2.6 × 2.6.** It is **not** three stacked balls. It is **ONE big snowball with a
cucumber slice set into its face.**
- A single `D.uvsphere(loc=(0, 0, 1.25), radius=1.25, segs=14, rings=10)` in `snow_white`
  (`"Snow"`), sitting on the ground.
- Set into its **front (-Y) face**, a cut-cucumber slice looking straight at the camera: a
  `cuke_green` rim disc of radius ~0.72 with a `cuke_pale` face and five `cuke_seed` pips,
  placed with `matrix=D.slice_stand((0, -1.08, 1.30))` so it is flush with and slightly proud
  of the snowball's surface.
- **Six or seven `cuke_stud` green squares** scattered over the rest of the snowball
  (`D.stud_patch` at points on the sphere, normal = the outward radial direction).
- 4 parts: Ball, Rim, Face, Seeds (+ Studs).

### `SnowCrystalCucumber` - `build_snow_crystal_cucumber.py` - REWRITE
**≈ 2.8 × 2.6 × 5.0.** It is **not** a bare crystal cluster. It is a **green cucumber with ice
crystals growing up around it.**
- A standard `cuke_body` in `cuke_green` with `cuke_stud` speckles at the centre, standard
  size and nub - it must be clearly visible.
- Around its base and lower two thirds, **six to eight pale-blue ice spires** growing upward
  and leaning outward: `D.crystal_spire` in `snow_crystal` (`"Ice"`, `transparency=0.18`),
  heights 1.2-3.4, radii 0.22-0.42, each at a different angle around the body
  (`rot=D.rot_euler(lean, 0, yaw)` with lean 8-22°). They should hug the cucumber, hiding a
  little of it, never swallowing it.
- Two or three smaller crystals near the top as well.
- `snow_white` speckles on the crystals.
- 4 parts: Body, Studs, Crystals, CrystalStuds.

### `SnowFrozenCucumber` - `build_snow_frozen_cucumber.py` - REWRITE
**≈ 2.4 × 2.2 × 5.0.** A **green cucumber frozen inside a block of ice, with snow on top.**
- A standard `cuke_body` in `cuke_green` with `cuke_stud` speckles.
- Around it, a **chunky faceted ice mass** in `snow_ice_lt` (`"Ice"`, `transparency=0.42` so
  the cucumber reads through it): build it as a `D.lathe` of 6-8 segments hugging the body from
  z 0 to about z 3.6, radius about 1.05 at the bottom tapering to 0.80, plus three or four
  angular `D.crystal_spire`s or `gem`s jutting off its sides so it is not a smooth sleeve.
  The cucumber's head and nub must stick out of the top.
- **A `snow_white` snow cap on top of the ice** (`D.cuke_snow_cap` or a `D.lathe` slab),
  thick and settled.
- 4 parts: Body, Studs, Ice, Snow.

### `SnowSnowTree` - `build_snow_snow_tree.py` - REWRITE
**≈ 6.2 × 5.4 × 11.5.** It is **not** a conifer. It is the set's standard **blocky tree with
snow on it and cucumbers hanging.**
- `stepped_base` + `blocky_trunk` + 3-4 `branch_box` forks in `snow_bark` (brown).
- Crown of **five green `crown_cube`s** in `cuke_green` with `cuke_stud` `box_studs` - the
  normal cucumber-tree crown.
- **A `snow_white` snow slab on top of every crown cube** (`D.snow_slab` on each cube's top,
  thick ~0.28, with a couple of drips over the front edge).
- **Three green cucumbers hanging** below the branches (`CUKE_PROFILE_STUB`, h ≈ 2.0,
  r ≈ 0.36, `cuke_green` + `cuke_stud`).
- 6 parts.

### `SnowIcicleTree` - `build_snow_icicle_tree.py` - REWRITE
**≈ 6.4 × 5.2 × 11.4.** The trunk and branches are **GREEN cucumber**, not brown bark - it
reads like a cucumber cactus-tree wearing snow.
- `stepped_base` + `blocky_trunk` + four `branch_box` forks reaching up and out, **all in
  `cuke_green` with `cuke_stud` speckles** (`D.box_studs` on the trunk blocks and the branches).
- **A `snow_white` snow cap on the trunk head and on the end of every branch**
  (`D.snow_slab` over each, or flattened `beveled_box`es).
- **Pale-blue icicles hanging under every branch**: `D.icicle_row(a, b, count=4, length=0.7,
  radius=0.11)` in `snow_ice_lt` (`"Ice"`, `transparency=0.18`).
- No crown cubes.
- 5 parts: Trunk, Studs, Snow, Icicles (+ Base if separate).

### `SnowFrozenTree` - `build_snow_frozen_tree.py` - REWRITE
**≈ 6.2 × 5.0 × 11.4.** A brown tree whose **foliage is cut-cucumber slices**, with icicles
hanging under them.
- `stepped_base` + `blocky_trunk` in `snow_bark` (brown), with `cuke_stud` green speckles on
  the trunk blocks, and **two or three `cuke_green` branches** reaching up and out.
- At the end of each branch, a **big cut-slice disc standing up and facing +Y** - a
  `cuke_green` rim, a `cuke_pale` face, `cuke_seed` pips - radius about 1.5, built with
  `slice_disc`/`slice_face`/`slice_seeds` and `matrix=D.slice_stand((x, y, z))`. Two large
  ones read best: one high and central, one lower to the side.
- **A `snow_white` snow cap on top of each disc** and on the trunk head.
- **`snow_ice_lt` icicles hanging beneath each disc** (`D.icicle_row`, `"Ice"`,
  `transparency=0.18`).
- 6 parts.
