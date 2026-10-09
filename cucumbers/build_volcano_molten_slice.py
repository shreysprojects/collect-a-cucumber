"""Volcano: Molten Slice - cucumber slices with charred green skin and molten cut faces."""
import bmesh, math

COLLECTION = "VolcanoMoltenSlice"
NOTES = ("The standard SlicedCucumber arrangement - four cut discs grouped on the ground, "
         "a big one STANDING with its cut face to +Y, a second tipped back against it, and "
         "two lying flat in front - but the insides are molten.  The slices are still "
         "CUCUMBER: the rims are dark olive-green skin (des_olive_dk), scorched but plainly "
         "cucumber, speckled with the set's darker green squares (cuke_stud_dk).  Inside "
         "that green ring the cut face is glowing orange lava (vol_lava, Neon, emit 0.85), "
         "standing proud so a band of dark green shows all the way round it, and the five "
         "ring pips plus the centre pip are hotter ember red (vol_ember, Neon, emit 1.0).  "
         "Emit stays at or below 1.0 - past that a warm hue washes out towards yellow-white "
         "and the slices read lemon instead of molten.  The read is a dark green rim around "
         "a furnace interior.  Four parts, ~3.2 x 2.4 x 1.8 studs, built with matrices so "
         "dryrun's bounding box and min_z are not meaningful here.")

# kind, (x, y, z), lean/tilt, turn/spin, radius, thickness, seed
DISCS = [
    ("stand", (0.50, -0.10, 0.86), -6.0, -12.0, 0.86, 0.44, 3),
    ("stand", (-0.66, 0.14, 0.62), 28.0, -34.0, 0.70, 0.40, 5),
    ("lay",   (-0.02, 1.02, 0.21), 0.0, 22.0, 0.74, 0.42, 9),
    ("lay",   (-1.38, 0.74, 0.19), 0.0, -38.0, 0.60, 0.38, 11),
]


def _discs(D):
    out = []
    for kind, loc, lean, turn, rad, th, seed in DISCS:
        m = (D.slice_stand(loc, lean_deg=lean, turn_deg=turn) if kind == "stand"
             else D.slice_lay(loc, tilt_deg=lean, spin_deg=turn))
        out.append((m, rad, th, seed))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _discs(D)

    # --- the skin: still cucumber, just scorched to a dark olive green -----------
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("des_olive_dk"), rbx_material="SmoothPlastic",
              roughness=0.68)

    # --- the set's speckles, a shade down so they sit on the darker skin ---------
    bm = bmesh.new()
    for m, rad, th, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=5, size=0.21, rise=0.045,
                      seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("cuke_stud_dk"), rbx_material="SmoothPlastic",
              roughness=0.68)

    # --- the cut face, molten, standing proud inside the green rim ring ----------
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.13, proud=0.025)
    D.new_obj("Faces", bm, c, D.C("vol_lava"), rbx_material="Neon", emit=0.65)

    # --- pips, the hottest thing in the model ------------------------------------
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=5, size=0.175, ring=0.42,
                      proud=0.03)
    D.new_obj("Seeds", bm, c, D.C("vol_ember"), rbx_material="Neon", emit=0.65)

    return c
