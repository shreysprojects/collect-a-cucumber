"""Snow: Frozen Slice - the standard green cut-cucumber slices with snow settled on them."""
import bmesh, math, random

COLLECTION = "SnowFrozenSlice"
NOTES = ("The standard SlicedCucumber arrangement in its normal GREEN colours, with white "
         "snow lying on top of it.  Four cut discs grouped on the ground: a big one "
         "STANDING with its cut face to +Y, a second tipped back against it, and two lying "
         "flat in front.  Dark-green cuke_dark rims speckled with cuke_stud squares, pale "
         "cuke_pale cut faces, cuke_seed pips - the cucumber is NOT recoloured, the snow is "
         "an overlay.  Each STANDING disc wears a snow_white (Roblox material Snow) cap "
         "over its upper rim: a curved crescent slab following the top arc, ~0.22 thick at "
         "its middle, tapering to nothing at both ends and standing a little proud of both "
         "cut faces so it spills over them.  Each LYING disc carries a smaller two-lump "
         "snow drift on its upward face.  Five parts, ~3.3 x 2.4 x 2.0 studs.  Every disc "
         "is placed with a matrix, so dryrun's bounding box and min_z are not meaningful "
         "here; the lying discs rest exactly on z = 0 (centre height = half thickness).")

# kind, (x, y, z), lean/tilt, turn/spin, radius, thickness, seed
DISCS = [
    ("stand", (0.50, -0.10, 0.86), -6.0, -12.0, 0.86, 0.44, 3),
    ("stand", (-0.66, 0.14, 0.62), 28.0, -34.0, 0.70, 0.40, 5),
    ("lay",   (-0.02, 1.02, 0.21), 0.0, 22.0, 0.74, 0.42, 9),
    ("lay",   (-1.38, 0.74, 0.19), 0.0, -38.0, 0.60, 0.38, 11),
]


def _discs(D):
    """(kind, matrix, radius, thickness, seed) for each disc, in the SlicedCucumber layout."""
    out = []
    for kind, loc, lean, turn, rad, th, seed in DISCS:
        m = (D.slice_stand(loc, lean_deg=lean, turn_deg=turn) if kind == "stand"
             else D.slice_lay(loc, tilt_deg=lean, spin_deg=turn))
        out.append((kind, m, rad, th, seed))
    return out


# ------------------------------------------------------------------ the snow
# A disc is built in LOCAL space with its axis on local +Z.  `slice_stand` swings local
# +Z onto +Y (the cut face meets the camera), which puts world UP on local -Y - so the
# top arc of a standing disc lives around local angle -90 degrees.
def _rim_cap(D, bm, m, rad, th, seed, thick=0.22, spill=0.06, span=(-172.0, -8.0), n=9):
    """A crescent of snow lying along a standing disc's upper rim, thickest in the
    middle, tapering away at both ends, a little proud of BOTH cut faces."""
    rng = random.Random(seed)
    outer, inner = [], []
    for i in range(n):
        t = i / float(n - 1)
        a = math.radians(span[0] + (span[1] - span[0]) * t)
        s = math.sin(math.pi * t) ** 0.55                    # 0 at the ends, 1 in the middle
        bulge = thick * (0.26 + 0.74 * s) * (1.0 + rng.uniform(-0.09, 0.09))
        ir = rad * (0.85 + 0.14 * (1.0 - s))                 # bites into the drum in the middle
        outer.append((math.cos(a) * (rad + bulge), math.sin(a) * (rad + bulge)))
        inner.append((math.cos(a) * ir, math.sin(a) * ir))
    half = th / 2.0 + spill
    return D.prism(bm, outer + list(reversed(inner)), -half, half, matrix=m)


def _face_drift(D, bm, m, rad, th, seed):
    """A small settled drift on the upward face of a disc lying flat: two chunky lumps."""
    rng = random.Random(seed)
    top = th / 2.0
    vs = []
    for k, (rr, dz, hh, ox, oy) in enumerate(((0.62, 0.012, 0.115, 0.10, -0.08),
                                              (0.37, 0.100, 0.100, -0.07, 0.05))):
        pts = []
        for i in range(7):
            a = 2.0 * math.pi * i / 7.0 + 0.42 * k
            r2 = rad * rr * (1.0 + rng.uniform(-0.15, 0.15))
            pts.append((rad * ox + math.cos(a) * r2, rad * oy + math.sin(a) * r2))
        vs += D.prism(bm, pts, top + dz, top + dz + hh, matrix=m)
    return vs


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _discs(D)

    # --- the skin: ordinary dark cucumber green -----------------------------------
    bm = bmesh.new()
    for _k, m, rad, th, _s in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("cuke_dark"), rbx_material="SmoothPlastic")

    # --- the set's signature speckle on the rims ----------------------------------
    bm = bmesh.new()
    for _k, m, rad, th, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=5, size=0.21, rise=0.045,
                      seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # --- the pale cut faces --------------------------------------------------------
    bm = bmesh.new()
    for _k, m, rad, th, _s in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.11)
    D.new_obj("Faces", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    # --- the pips ------------------------------------------------------------------
    bm = bmesh.new()
    for _k, m, rad, th, _s in discs:
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=5, size=0.175, ring=0.42)
    D.new_obj("Seeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    # --- snow settled on top of them ----------------------------------------------
    bm = bmesh.new()
    for kind, m, rad, th, seed in discs:
        if kind == "stand":
            _rim_cap(D, bm, m, rad, th, seed, thick=0.22 * (rad / 0.86))
        else:
            _face_drift(D, bm, m, rad, th, seed)
    D.new_obj("Snow", bm, c, D.C("snow_white"), rbx_material="Snow", roughness=0.85)

    return c
