"""Narmek: Moon Slice - the SlicedCucumber group cut out of grey moon rock."""
import bmesh, math

COLLECTION = "NarmekMoonSlice"
NOTES = ("The SlicedCucumber arrangement carved from moon rock: four cut discs grouped on "
         "the ground - a big one STANDING with its cut face to +Y, a second tipped back "
         "against it, and two lying flat in front.  Dark grey rim (nar_moon_dk, Rock) "
         "speckled with lighter grey squares (nar_moon), a chalky pale cut face "
         "(nar_moon_lt, Concrete) with five square pips in a ring plus one in the middle, "
         "the pips back in the dark rim grey.  The one bright note is a single GLOWING "
         "GREEN square (nar_glow_grn, Neon) sitting on the big standing disc's front face "
         "in place of its upper-left ring pip - it is the only saturated colour in the "
         "model, so it has to stay a single square.  Five parts, ~3.2 x 2.4 x 1.8 studs. "
         "Everything is placed with matrices, so dryrun's bounding box and its min_z are "
         "not meaningful here; the real footprint is the SlicedCucumber one.")

# kind, (x, y, z), lean/tilt, turn/spin, radius, thickness, seed
DISCS = [
    ("stand", (0.50, -0.10, 0.86), -6.0, -12.0, 0.86, 0.44, 3),
    ("stand", (-0.66, 0.14, 0.62), 28.0, -34.0, 0.70, 0.40, 5),
    ("lay",   (-0.02, 1.02, 0.21), 0.0, 22.0, 0.74, 0.42, 9),
    ("lay",   (-1.38, 0.74, 0.19), 0.0, -38.0, 0.60, 0.38, 11),
]
HERO = 0            # the big standing disc - the one that carries the glow square

# pip layout, kept in step with slice_seeds' own defaults so the hand-built hero
# face matches the three discs that still go through the library call
PIP_N = 5
PIP_SIZE = 0.175
PIP_RING = 0.42
PIP_PHASE = 18.0
PIP_PROUD = 0.02
PIP_RISE = 0.024
GLOW_PIP = 4        # ring slot the green square takes over (upper LEFT of the frame:
                    # local +x is screen-left, and the hero's -12 turn swings it forward)


def _discs(D):
    out = []
    for kind, loc, lean, turn, rad, th, seed in DISCS:
        m = (D.slice_stand(loc, lean_deg=lean, turn_deg=turn) if kind == "stand"
             else D.slice_lay(loc, tilt_deg=lean, spin_deg=turn))
        out.append((m, rad, th, seed))
    return out


def _pip_xy(radius, i):
    """Where ring pip `i` sits on a disc's cut face, in the disc's own XY."""
    a = math.radians(PIP_PHASE) + 2.0 * math.pi * i / float(PIP_N)
    return math.cos(a) * radius * PIP_RING, math.sin(a) * radius * PIP_RING


def _hero_pips(D, bm, radius, thick, matrix):
    """slice_seeds for the hero disc, minus the one front pip the glow square replaces.

    Local +Z is the cut face turned toward the camera, so only that side loses a pip;
    the back face keeps its full ring."""
    vs = []
    for s in (1.0, -1.0):
        z = s * (thick / 2.0 + PIP_PROUD)
        spots = [(0.0, 0.0)]
        for i in range(PIP_N):
            if s > 0.0 and i == GLOW_PIP:
                continue
            spots.append(_pip_xy(radius, i))
        for x, y in spots:
            vs += D.stud_patch(bm, (x, y, z), (0.0, 0.0, s), size=PIP_SIZE,
                               rise=PIP_RISE, sink=0.05, bevel=0.02)
    D.xform(bm, vs, matrix)
    return vs


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _discs(D)

    # --- the skin: dead grey moon rock -------------------------------------------
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("nar_moon_dk"), rbx_material="Rock", roughness=0.82)

    # --- the set's signature speckles, lighter grey so the rim still reads -------
    bm = bmesh.new()
    for m, rad, th, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=5, size=0.21, rise=0.045,
                      seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("nar_moon"), rbx_material="Rock", roughness=0.8)

    # --- the cut faces: chalky moon dust, a clear value step above the rim -------
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.11)
    D.new_obj("Faces", bm, c, D.C("nar_moon_lt"), rbx_material="Concrete", roughness=0.86)

    # --- pips, back down in the rim grey; the hero front face is one short -------
    bm = bmesh.new()
    for i, (m, rad, th, _s) in enumerate(discs):
        if i == HERO:
            _hero_pips(D, bm, rad, th, m)
        else:
            D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=PIP_N, size=PIP_SIZE,
                          ring=PIP_RING)
    D.new_obj("Seeds", bm, c, D.C("nar_moon_dk"), rbx_material="Rock", roughness=0.82)

    # --- the one bright note: a single glowing green square on the hero's face ---
    bm = bmesh.new()
    m, rad, th, _s = discs[HERO]
    gx, gy = _pip_xy(rad, GLOW_PIP)
    vs = D.stud_patch(bm, (gx, gy, th / 2.0 + PIP_PROUD), (0.0, 0.0, 1.0), size=0.26,
                      rise=0.032, sink=0.06, bevel=0.025)
    D.xform(bm, vs, m)
    D.new_obj("GlowSquare", bm, c, D.C("nar_glow_grn"), rbx_material="Neon", emit=0.65)

    return c
