"""Snow: Snow Tree - the set's blocky cucumber tree with snow lying all over it."""
import bmesh, math

COLLECTION = "SnowSnowTree"
NOTES = ("An 11.5-stud winter cucumber tree, footprint about 6.3 x 5.5.  It is the set's "
         "standard tree - NOT a conifer: a two-step snow_bark plinth, a three-block bark "
         "trunk up to z 5.95, and four square branches forking out to z 7.7-8.2, all in "
         "brown snow_bark.  On the forks sits the normal cucumber crown: FIVE cuke_green "
         "cubes (2.45 base size, the top one 1.12x at z 9.85, four around it) carrying "
         "the set's cuke_stud square speckles on all four side faces.  Snow has settled "
         "on it: a snow_white slab 0.28 thick lies on the TOP of every crown cube, "
         "overhanging 0.11 all round with two drips spilling over its front (-y) edge, "
         "the tallest finishing the model at z 11.50; a thinner drift with drips sits on "
         "the plinth around the trunk foot, and a snow strip lies along the top of each "
         "of the two side limbs.  Three cuke_green cucumbers (CUKE_PROFILE_STUB, h ~2.0, "
         "r ~0.35, cuke_stud speckles, small stem nubs) hang under the branches between "
         "z 4.6 and 7.2, two of them toward the front.  Green body, white snow on top - "
         "most of the green stays visible.  Faces +Y, centred on x=0 / y=0, nothing "
         "below z = 0.  Six parts: Trunk, Crown, CrownStuds, Snow, Cukes, CukeStuds.  "
         "Note for dryrun: the hanging cucumbers are placed with matrix=D.place(...), "
         "which the offline bounding box cannot see, so it reports them standing at the "
         "origin and prints a slightly short/narrow box.")

# ---- trunk -----------------------------------------------------------------
BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.45, 1.28, 2, 1.36
TRUNK_Z0, TRUNK_Z1 = 1.26, 5.95
TRUNK_W0, TRUNK_W1 = 1.34, 0.98
TRUNK_BLOCKS = 3

# one fork per row: (start z on the trunk, end x, end y, end z, butt width, tip width)
BRANCHES = [
    (5.05, -1.60,  0.22, 7.95, 0.60, 0.40),
    (4.85,  1.62, -0.18, 8.15, 0.62, 0.42),
    (5.45, -0.72, -1.30, 7.70, 0.56, 0.36),
    (5.50,  0.82,  1.26, 7.80, 0.54, 0.34),
]
SNOWY_LIMBS = (0, 1)        # the two side limbs that show below the crown

# ---- crown -----------------------------------------------------------------
CTR = (0.05, 0.0, 8.30)
CROWN_SIZE = 2.45
# (dx, dy, dz, size multiplier) around the crown centre
CROWN = [
    ( 0.00,  0.00,  1.55, 1.12),     # the top cube - the one that tops out at 11.50
    (-1.82,  0.26,  0.34, 1.00),
    ( 1.78, -0.22,  0.55, 1.02),
    (-0.88, -1.52, -0.05, 0.94),     # forward, toward the camera
    ( 0.92,  1.48,  0.06, 0.92),
]
# snow slab on each cube: (thickness, overhang, drips, drip length, spill sides)
SNOW_CAPS = [
    (0.30, 0.12, 2, 0.52, ("-y", "+x")),
    (0.28, 0.11, 2, 0.48, ("-y",)),
    (0.28, 0.11, 2, 0.46, ("-y",)),
    (0.26, 0.11, 2, 0.44, ("-y",)),
    (0.26, 0.10, 1, 0.38, ("-y",)),
]

# ---- fruit: (x, y, top z, height, radius, lean degrees) ---------------------
HANGING = [
    (-1.45, -0.35, 7.15, 2.05, 0.36,  7.0),
    ( 1.35, -0.90, 6.90, 1.95, 0.35, -6.0),
    ( 0.55,  1.20, 6.70, 2.00, 0.34,  4.0),
]


def _cube_box(i):
    """(lo, hi) of crown cube `i` - shared by the cubes, their studs and their snow."""
    dx, dy, dz, k = CROWN[i]
    s = CROWN_SIZE * k
    cx, cy, cz = CTR[0] + dx, CTR[1] + dy, CTR[2] + dz
    return ((cx - s / 2, cy - s / 2, cz - s / 2), (cx + s / 2, cy + s / 2, cz + s / 2))


def _limb(row):
    """(origin, delta, length, yaw_deg, slope_deg) for one fork."""
    z0, bx, by, bz, _w0, _w1 = row
    dx, dy, dz = bx, by, bz - z0
    flat = math.hypot(dx, dy)
    return ((0.0, 0.0, z0), (dx, dy, dz), math.hypot(flat, dz),
            math.degrees(math.atan2(dy, dx)), math.degrees(math.atan2(dz, flat)))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- brown bark: plinth, trunk, four forks -----------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.08)
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08)
    for row in BRANCHES:
        a, d, _L, _yaw, _slope = _limb(row)
        b = (a[0] + d[0], a[1] + d[1], a[2] + d[2])
        D.branch_box(bm, a, b, row[4], row[5], bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("snow_bark"), rbx_material="Wood", roughness=0.70)

    # ---- the green cucumber crown ------------------------------------------
    bm = bmesh.new()
    D.crown_cluster(bm, CTR, CROWN_SIZE, CROWN, bevel=0.14)
    D.new_obj("Crown", bm, c, D.C("cuke_green"), rbx_material="Grass")

    # ---- the set's square speckles on every cube ---------------------------
    bm = bmesh.new()
    for i in range(len(CROWN)):
        lo, hi = _cube_box(i)
        # bevel=0 on the crown speckles: a chamfer on 80 little squares costs ~3k tris
        # and reads identically at any distance a player sees this from
        D.box_studs(bm, lo, hi, faces=("-y", "+x", "-x", "+y"), grid=(2, 2), size=0.46,
                    rise=0.07, seed=20 + i, margin=0.34, bevel=0.0)
    D.new_obj("CrownStuds", bm, c, D.C("cuke_stud"), rbx_material="Grass")

    # ---- the snow: a slab on every cube, a strip on the limbs, a base drift --
    bm = bmesh.new()
    for i in range(len(CROWN)):
        lo, hi = _cube_box(i)
        thick, over, drips, dlen, sides = SNOW_CAPS[i]
        D.snow_slab(bm, lo, hi, thick=thick, overhang=over, drips=drips,
                    drip_len=dlen, seed=40 + i, bevel=0.08, sides=sides)

    for i in SNOWY_LIMBS:
        row = BRANCHES[i]
        a, d, L, yaw, slope = _limb(row)
        w0, w1 = row[4], row[5]
        t = 0.58
        wt = w0 + (w1 - w0) * t
        px, py = a[0] + d[0] * t, a[1] + d[1] * t
        pz = a[2] + d[2] * t + wt / 2.0 + 0.10
        ls, ws, th = L * 0.72, (w0 + w1) * 0.74, 0.24
        D.beveled_box(bm, (px - ls / 2, py - ws / 2, pz - th / 2),
                      (px + ls / 2, py + ws / 2, pz + th / 2), bevel=0.08,
                      rot=D.rot_euler(0.0, -slope, yaw))

    bw = BASE_TOP_W / 2.0
    D.snow_slab(bm, (-bw, -bw, BASE_H / BASE_STEPS), (bw, bw, BASE_H + 0.012),
                thick=0.20, overhang=0.12, drips=2, drip_len=0.50, seed=9, bevel=0.07,
                sides=("-y",))
    D.new_obj("Snow", bm, c, D.C("snow_white"), rbx_material="Snow", roughness=0.46)

    # ---- three green cucumbers hanging under the branches -------------------
    bm = bmesh.new()
    bm2 = bmesh.new()
    for i, (x, y, ztop, hh, rr, lean) in enumerate(HANGING):
        m = D.place((x, y, ztop - hh), D.rot_euler(lean, 0.0, 24.0 * i))
        D.cuke_body(bm, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, nub=(0.17, 0.16),
                    matrix=m)
        D.cuke_studs(bm2, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, rows=3, per_row=2,
                     z0=0.22, z1=0.80, size=0.17, rise=0.04, seed=30 + i, matrix=m)
    D.new_obj("Cukes", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")
    D.new_obj("CukeStuds", bm2, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
