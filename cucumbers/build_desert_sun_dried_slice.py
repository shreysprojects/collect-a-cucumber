"""Desert: Sun-Dried Slice - the SlicedCucumber group, dried out and recoloured."""
import bmesh, math

COLLECTION = "DesertSunDriedSlice"
NOTES = ("The SlicedCucumber arrangement gone sun-dried: four cut discs on the ground - a "
         "big one STANDING with its cut face to +Y, a second tipped back against it, and "
         "two lying flat in front.  Dark olive rim with lighter olive speckles, pale sand "
         "cut face (Roblox material Sand) with five square pips in a ring plus one in the "
         "middle, in baked khaki.  Every disc is 0.9x the normal thickness - they have "
         "dried out and shrunk.  Four parts, ~3.2 x 2.4 x 1.8 studs.")

DRY = 0.90          # dried-out discs are a touch thinner than the grass ones

# kind, (x, y), stand z, lean/tilt, turn/spin, radius, thickness, seed
DISCS = [
    ("stand", (0.50, -0.10), 0.86, -6.0, -12.0, 0.86, 0.44, 3),
    ("stand", (-0.66, 0.14), 0.62, 28.0, -34.0, 0.70, 0.40, 5),
    ("lay",   (-0.02, 1.02), None, 0.0, 22.0, 0.74, 0.42, 9),
    ("lay",   (-1.38, 0.74), None, 0.0, -38.0, 0.60, 0.38, 11),
]


def _discs(D):
    """(matrix, radius, thickness, seed) for each disc, thinned by DRY.

    A lying disc rests ON the ground, so its centre height follows its thickness."""
    out = []
    for kind, (x, y), z, lean, turn, rad, th, seed in DISCS:
        th = th * DRY
        if kind == "stand":
            m = D.slice_stand((x, y, z), lean_deg=lean, turn_deg=turn)
        else:
            m = D.slice_lay((x, y, th / 2.0), tilt_deg=lean, spin_deg=turn)
        out.append((m, rad, th, seed))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _discs(D)

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("des_olive_dk"), rbx_material="SmoothPlastic",
              roughness=0.72)

    bm = bmesh.new()
    for m, rad, th, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=5, size=0.21, rise=0.045,
                      seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("des_olive"), rbx_material="SmoothPlastic",
              roughness=0.72)

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.11)
    D.new_obj("Faces", bm, c, D.C("des_sand"), rbx_material="Sand", roughness=0.85)

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=5, size=0.175, ring=0.42)
    D.new_obj("Seeds", bm, c, D.C("des_baked"), rbx_material="SmoothPlastic",
              roughness=0.78)

    return c
