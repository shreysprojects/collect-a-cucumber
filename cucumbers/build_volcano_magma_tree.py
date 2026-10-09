"""Volcano: the MagmaTree - a charcoal tree veined with magma, hung with green cucumbers."""
import bmesh, math

COLLECTION = "VolcanoMagmaTree"
NOTES = ("A charcoal cucumber tree lit from inside by molten veins, carrying four ordinary "
         "GREEN cucumbers.  A three-step vol_char plinth, a tapering blocky vol_char trunk "
         "forking into four square branches, and a broad canopy of six vol_char crown "
         "cubes (CrackedLava) sitting on the forks.  The rock is cracked open by orange "
         "vol_lava veins (Neon, emit 0.9): one unbroken stepped rod climbs each of the "
         "four corners of the plinth and the trunk from the ground to the fork, and a "
         "fifth rides the top edge of every branch.  The crown cubes are split by "
         "vol_lava_hot glow squares (Neon, emit 1.0, grid 2x2, size 0.50) on the faces "
         "that face the camera.  Hanging under the four branches are four normal "
         "cuke_green cucumbers (CUKE_PROFILE_STUB, h ~2.0, r ~0.36) speckled with "
         "cuke_stud squares - the green is what makes this a cucumber tree and not just "
         "a lava rock.  Footprint ~7.0 x 5.9, 11.8 tall; nothing below z = 0, centred on "
         "x=0 y=0, faces +Y.  Six parts: Trunk, Crown, Veins, CrownGlow, Cukes, "
         "CukeStuds.  Trunk and Crown share the vol_char body colour but carry different "
         "Roblox materials (Basalt vs CrackedLava), which is what keeps them separate "
         "objects.")

# ---- plinth ---------------------------------------------------------------
BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.60, 1.50, 3, 1.32
# step half-widths, widest first: 1.3935, 1.056, 0.80   (z 0-0.51, 0.5-1.01, 1.0-1.51)

# ---- trunk ----------------------------------------------------------------
TR_Z0, TR_Z1 = 1.45, 6.15
TR_W0, TR_W1, TR_BLOCKS = 1.45, 1.00, 3

# ---- forks: (end x, end y, end z, start z) --------------------------------
BR_W0, BR_W1 = 0.64, 0.44
BRANCHES = [
    (-1.95, 0.22, 8.35, 5.05),
    (2.05, -0.18, 8.60, 4.90),
    (-1.00, -1.62, 8.00, 5.50),
    (1.12, 1.50, 8.15, 5.50),
]

# ---- crown cubes: (dx, dy, dz, size mult, glow faces) around the crown centre
CROWN_CTR = (0.05, 0.0, 8.70)
CROWN_S = 2.60
CROWN = [
    (0.00, 0.00, 1.48, 1.18, ("-y", "+z", "+x")),
    (-2.22, 0.25, 0.48, 1.00, ("-y", "-x", "+z")),
    (2.20, -0.20, 0.68, 1.02, ("-y", "+x", "+z")),
    (-1.00, -1.80, 0.18, 0.92, ("-y", "+z")),
    (1.15, 1.72, 0.28, 0.94, ("+z", "+x")),
    (0.15, 0.05, -0.22, 0.86, ("-y",)),
]

# ---- hanging cucumbers: (x, y, top z, height, radius, lean degrees) -------
# each sits just under the outer third of one fork, clear of the crown cubes above it
HANGING = [
    (-1.66, 0.18, 7.50, 2.05, 0.36, 6.0),
    (1.74, -0.15, 7.68, 2.00, 0.36, -7.0),
    (-0.86, -1.38, 7.28, 1.95, 0.35, 5.0),
    (0.95, 1.28, 7.42, 1.90, 0.34, -5.0),
]

CORNERS = ((1, 1), (1, -1), (-1, 1), (-1, -1))

# one unbroken glow line per corner: (half-offset, z, width) knots, ground -> fork.
# Each knot sits just outside the step/block corner it runs past, so the rod is
# always proud of the surface and never swallowed by it.
VEIN_KNOTS = [
    (1.3935, 0.22, 0.28),      # bottom step corner
    (1.1600, 0.58, 0.26),
    (1.0560, 0.52, 0.26),      # middle step corner
    (0.8700, 1.06, 0.24),
    (0.8400, 1.02, 0.26),      # top step corner, then straight up the trunk
    (0.5780, 6.18, 0.19),
]
VEIN_RUNS = ((0, 1), (2, 3), (4, 5))


def _unit(v):
    L = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if L < 1e-9:
        return (0.0, 0.0, 1.0)
    return (v[0] / L, v[1] / L, v[2] / L)


def _vein_up(d):
    """Unit vector perpendicular to unit `d`, in the vertical plane through it,
    pointing up - i.e. the direction of a beam's TOP edge."""
    return _unit((-d[2] * d[0], -d[2] * d[1], 1.0 - d[2] * d[2]))


def _cube_box(spot):
    """(lo, hi) of one crown cube."""
    s = CROWN_S * spot[3]
    cx = CROWN_CTR[0] + spot[0]
    cy = CROWN_CTR[1] + spot[1]
    cz = CROWN_CTR[2] + spot[2]
    return ((cx - s / 2, cy - s / 2, cz - s / 2), (cx + s / 2, cy + s / 2, cz + s / 2))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ------------------------------- plinth, trunk and the forks: one rock
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.09)
    D.blocky_trunk(bm, TR_Z0, TR_Z1, TR_W0, TR_W1, blocks=TR_BLOCKS, bevel=0.09)
    for (bx, by, bz, z0) in BRANCHES:
        D.branch_box(bm, (0.0, 0.0, z0), (bx, by, bz), BR_W0, BR_W1, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("vol_char"), rbx_material="Basalt", roughness=0.82)

    # -------------------------------------------------------- crown cubes
    bm = bmesh.new()
    for spot in CROWN:
        lo, hi = _cube_box(spot)
        D.beveled_box(bm, lo, hi, bevel=0.15)
    D.new_obj("Crown", bm, c, D.C("vol_char"), rbx_material="CrackedLava", roughness=0.78)

    # --------------------------------------------------------- glow veins
    bm = bmesh.new()
    for (sx, sy) in CORNERS:
        for i0, i1 in VEIN_RUNS:
            o0, z0, w0 = VEIN_KNOTS[i0]
            o1, z1, w1 = VEIN_KNOTS[i1]
            D.branch_box(bm, (sx * o0, sy * o0, z0), (sx * o1, sy * o1, z1),
                         w0, w1, bevel=0.04)

    for (bx, by, bz, z0) in BRANCHES:
        vx, vy, vz = bx, by, bz - z0
        L = math.sqrt(vx * vx + vy * vy + vz * vz)
        d = _unit((vx, vy, vz))
        up = _vein_up(d)
        # the beam's square section is rolled by the fork's yaw, so its half-extent
        # along `up` is half_width * (|cos yaw| + |sin yaw|) - clear that, not the flat.
        yaw = math.atan2(by, bx)
        f = abs(math.cos(yaw)) + abs(math.sin(yaw))
        s0 = 0.20                                   # leave the trunk first
        h0 = (BR_W0 + (BR_W1 - BR_W0) * s0) / 2.0
        h1 = BR_W1 / 2.0
        o0, o1 = h0 * f + 0.02, h1 * f + 0.02
        a = (d[0] * L * s0 + up[0] * o0,
             d[1] * L * s0 + up[1] * o0,
             z0 + d[2] * L * s0 + up[2] * o0)
        b = (bx + d[0] * 0.06 + up[0] * o1,
             by + d[1] * 0.06 + up[1] * o1,
             bz + d[2] * 0.06 + up[2] * o1)
        D.branch_box(bm, a, b, 0.20, 0.14, bevel=0.035)
    D.new_obj("Veins", bm, c, D.C("vol_lava"), rbx_material="Neon", emit=0.65)

    # ------------------------------------------------ the crown cracks open
    # bevel=0 on the glow squares: a chamfer on 56 little boxes costs ~1.8k tris
    # and reads identically to a crisp square at any distance a player sees this from
    bm = bmesh.new()
    for i, spot in enumerate(CROWN):
        lo, hi = _cube_box(spot)
        D.box_studs(bm, lo, hi, faces=spot[4], grid=(2, 2), size=0.50, rise=0.07,
                    seed=40 + i, margin=0.34, bevel=0.0)
    D.new_obj("CrownGlow", bm, c, D.C("vol_lava_hot"), rbx_material="Neon", emit=0.65)

    # ---------------------------- four ordinary green cucumbers, hanging
    bm = bmesh.new()
    bm2 = bmesh.new()
    for i, (x, y, ztop, hh, rr, lean) in enumerate(HANGING):
        m = D.place((x, y, ztop - hh), D.rot_euler(lean, 0.0, 22.0 * i))
        D.cuke_body(bm, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, nub=(0.17, 0.16),
                    matrix=m)
        D.cuke_studs(bm2, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, rows=3, per_row=2,
                     z0=0.20, z1=0.82, size=0.16, rise=0.04, seed=60 + i, bevel=0.0,
                     matrix=m)
    D.new_obj("Cukes", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")
    D.new_obj("CukeStuds", bm2, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
