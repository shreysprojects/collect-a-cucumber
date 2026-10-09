"""Snow: Icicle Tree - a GREEN cucumber tree wearing snow, icicles under every limb."""
import bmesh, math

COLLECTION = "SnowIcicleTree"
NOTES = ("An 11.4-stud cucumber tree in winter, footprint about 6.4 x 5.2.  The tree "
         "itself is CUCUMBER, not bark: a dark-green three-step plinth, a four-block "
         "`cuke_green` trunk tapering up to a flared head at z 10.46, and FOUR square "
         "branches forking off it at z 6.2-7.5 and reaching UP and OUT at about 40 "
         "degrees - no crown cubes at all.  The trunk blocks, the head and the branches "
         "all carry the set's raised `cuke_stud` square speckles, so the whole skeleton "
         "reads as cucumber skin.  On top of that the snow: a stepped `snow_white` pile "
         "with drips on the trunk head that finishes the model at z 11.40, a snow cap "
         "on the end of every branch, a snow strip lofted along every branch's top "
         "(a flattened beveled_box rotated onto the limb's yaw and slope), and a drift "
         "on the plinth's bottom ledge.  Pale-blue `snow_ice_lt` icicles hang in a row "
         "of four under each branch and in a row of three off the front of the head "
         "cap.  Nothing below z = 0, centred on x=0 y=0, faces +Y.  "
         "Five parts: Base, Trunk (trunk + head + branches), Studs, Snow, Icicles.")

TRUNK_Z0, TRUNK_Z1 = 1.50, 9.80
TRUNK_W0, TRUNK_W1 = 1.42, 0.88
TRUNK_BLOCKS = 4

HEAD_W, HEAD_Z0, HEAD_Z1 = 1.18, 9.72, 10.46

BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.50, 1.50, 3, 1.30

# one branch per row: (start z on the trunk, end x, end y, end z, butt width, tip width)
BRANCHES = [
    (6.55, -2.75,  0.72, 9.05, 0.66, 0.42),
    (7.00,  2.78, -0.60, 9.50, 0.64, 0.40),
    (6.15, -1.12, -2.18, 8.50, 0.60, 0.38),
    (7.50,  1.26,  2.14, 9.80, 0.58, 0.36),
]

# where the speckles sit on a branch: (t along it, which way out) - 1 = +side,
# 0 = the top, -1 = -side
BRANCH_SLOTS = ((0.34, 1), (0.56, 0), (0.76, -1))


def _trunk_blocks():
    """The same boxes `blocky_trunk` stacks, so the speckles land on their faces."""
    out = []
    sh = (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    for i in range(TRUNK_BLOCKS):
        t = (i + 0.5) / float(TRUNK_BLOCKS)
        w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * t
        z = TRUNK_Z0 + i * sh
        out.append((((-w / 2), (-w / 2), z), ((w / 2), (w / 2), z + sh)))
    return out


def _limb(row):
    """(origin, delta, length, yaw_deg, slope_deg, side_unit, up_unit) for one branch.

    `side` is horizontal and square to the limb, `up` is square to both - together they
    give the limb's own frame, so speckles sit flat on its flanks and the icicles hang
    off its true underside rather than off a z-offset guess."""
    z0, bx, by, bz, _w0, _w1 = row
    a = (0.0, 0.0, z0)
    d = (bx, by, bz - z0)
    flat = math.hypot(d[0], d[1])
    L = math.hypot(flat, d[2])
    ux, uy, uz = d[0] / L, d[1] / L, d[2] / L
    sl = math.hypot(uy, ux) or 1.0                      # cross(u, +Z) = (uy, -ux, 0)
    s = (uy / sl, -ux / sl, 0.0)
    n = (s[1] * uz - s[2] * uy, s[2] * ux - s[0] * uz, s[0] * uy - s[1] * ux)
    return (a, d, L, math.degrees(math.atan2(d[1], d[0])),
            math.degrees(math.atan2(d[2], flat)), s, n)


def _at(a, d, t):
    return (a[0] + d[0] * t, a[1] + d[1] * t, a[2] + d[2] * t)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    limbs = [_limb(row) for row in BRANCHES]

    # ---- the plinth: a darker green so the trunk reads against it -----------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.09)
    D.new_obj("Base", bm, c, D.C("cuke_deep"), rbx_material="Grass")

    # ---- the tree itself, all cucumber green: trunk, head, four branches ----
    bm = bmesh.new()
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1,
                   blocks=TRUNK_BLOCKS, bevel=0.09)
    D.beveled_box(bm, (-HEAD_W / 2, -HEAD_W / 2, HEAD_Z0),
                  (HEAD_W / 2, HEAD_W / 2, HEAD_Z1), bevel=0.13)
    for row in BRANCHES:
        a, d, _L, _yaw, _sl, _s, _n = _limb(row)
        b = (a[0] + d[0], a[1] + d[1], a[2] + d[2])
        D.branch_box(bm, a, b, row[4], row[5], bevel=0.06)
    D.new_obj("Trunk", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the set's signature speckles, over every green surface ------------
    bm = bmesh.new()
    for i, (lo, hi) in enumerate(_trunk_blocks()):
        D.box_studs(bm, lo, hi, faces=("-y", "+x", "-x"), per_face=2, size=0.28,
                    rise=0.05, seed=11 + i, margin=0.34)
    D.box_studs(bm, (-HEAD_W / 2, -HEAD_W / 2, HEAD_Z0),
                (HEAD_W / 2, HEAD_W / 2, HEAD_Z1), faces=("-y", "+x", "-x"),
                per_face=1, size=0.28, rise=0.05, seed=19, margin=0.38)
    for i, row in enumerate(BRANCHES):
        a, d, _L, _yaw, _sl, s, n = limbs[i]
        w0, w1 = row[4], row[5]
        for t, side in BRANCH_SLOTS:
            w = w0 + (w1 - w0) * t
            dir_ = n if side == 0 else (s[0] * side, s[1] * side, s[2] * side)
            p = _at(a, d, t)
            D.stud_patch(bm, (p[0] + dir_[0] * w / 2.0, p[1] + dir_[1] * w / 2.0,
                              p[2] + dir_[2] * w / 2.0), dir_, size=0.24, rise=0.05)
    bw = BASE_TOP_W * (BASE_GROW ** (BASE_STEPS - 1)) / 2.0
    mw = BASE_TOP_W * (BASE_GROW ** (BASE_STEPS - 2)) / 2.0
    sh = BASE_H / BASE_STEPS
    D.box_studs(bm, (-bw, -bw, 0.0), (bw, bw, sh), faces=("-y",), per_face=2,
                size=0.30, rise=0.05, seed=27, margin=0.36)
    D.box_studs(bm, (-mw, -mw, sh), (mw, mw, sh * 2.0), faces=("-y",), per_face=2,
                size=0.28, rise=0.05, seed=31, margin=0.38)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- snow: along every limb, on every tip, piled on the head -----------
    bm = bmesh.new()
    for i, row in enumerate(BRANCHES):
        a, d, L, yaw, slope, _s, n = limbs[i]
        w0, w1 = row[4], row[5]
        t = 0.52
        wt = w0 + (w1 - w0) * t
        p = _at(a, d, t)
        off = wt / 2.0 + 0.09
        px, py, pz = (p[0] + n[0] * off, p[1] + n[1] * off, p[2] + n[2] * off)
        ls, ws, th = L * 0.54, (w0 + w1) * 0.72, 0.24
        D.beveled_box(bm, (px - ls / 2, py - ws / 2, pz - th / 2),
                      (px + ls / 2, py + ws / 2, pz + th / 2), bevel=0.08,
                      rot=D.rot_euler(0.0, -slope, yaw))
        bx, by, bz = a[0] + d[0], a[1] + d[1], a[2] + d[2]
        D.snow_slab(bm, (bx - 0.34, by - 0.34, bz - 0.10),
                    (bx + 0.34, by + 0.34, bz + 0.16), thick=0.30, overhang=0.08,
                    drips=2, drip_len=0.28, seed=51 + i, bevel=0.07, sides=("-y",))

    D.snow_slab(bm, (-HEAD_W / 2, -HEAD_W / 2, HEAD_Z0),
                (HEAD_W / 2, HEAD_W / 2, HEAD_Z1), thick=0.46, overhang=0.17,
                drips=3, drip_len=0.60, seed=5, bevel=0.09, sides=("-y", "+x"))
    D.beveled_box(bm, (-0.38, -0.38, 10.86), (0.38, 0.38, 11.18), bevel=0.12)
    D.beveled_box(bm, (-0.19, -0.19, 11.12), (0.19, 0.19, 11.40), bevel=0.07)
    D.snow_slab(bm, (-bw, -bw, 0.0), (bw, bw, sh + 0.012), thick=0.16, overhang=0.10,
                drips=2, drip_len=0.28, seed=9, bevel=0.06, sides=("-y",))
    D.new_obj("Snow", bm, c, D.C("snow_white"), rbx_material="Snow")

    # ---- icicles under every branch and off the front of the head cap ------
    bm = bmesh.new()
    for i, row in enumerate(BRANCHES):
        a, d, _L, _yaw, _sl, _s, n = limbs[i]
        w0, w1 = row[4], row[5]
        t0, t1 = 0.32, 0.95
        wa = (w0 + (w1 - w0) * t0) / 2.0 - 0.03
        wb = (w0 + (w1 - w0) * t1) / 2.0 - 0.03
        pa, pb = _at(a, d, t0), _at(a, d, t1)
        p = (pa[0] - n[0] * wa, pa[1] - n[1] * wa, pa[2] - n[2] * wa)
        q = (pb[0] - n[0] * wb, pb[1] - n[1] * wb, pb[2] - n[2] * wb)
        D.icicle_row(bm, p, q, count=4, length=0.70, radius=0.11, seed=40 + i)
    D.icicle_row(bm, (-0.66, -0.72, 10.46), (0.66, -0.72, 10.46), count=3,
                 length=0.60, radius=0.10, seed=47)
    D.new_obj("Icicles", bm, c, D.C("snow_ice_lt"), rbx_material="Ice",
              transparency=0.18)

    return c
