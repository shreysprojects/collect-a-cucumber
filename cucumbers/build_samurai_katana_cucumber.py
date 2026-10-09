"""Samurai: Katana Cucumber - a katana driven straight down into the cucumber's head."""
import bmesh, math

COLLECTION = "SamuraiKatanaCucumber"
NOTES = ("The standard 4-stud cucumber in cuke_green with standard cuke_stud speckles, "
         "with a KATANA driven vertically into its head and leaning back 8 degrees: a "
         "short steel blade stub rising out of the flat head, an octagonal gold tsuba "
         "(r 0.26, 0.10 thick) at z 4.55, a gold fuchi collar, a black wrapped tsuka "
         "0.21 square and 1.52 long carrying eight gold diamond wraps (four down the "
         "front, two on each side), and a black kashira pommel cap topping out at "
         "z 6.43.  A red sash is wrapped once round the body at zf 0.55; its dark knot "
         "hides the seam and sits on the FRONT-LEFT (+X, +Y, i.e. screen-left) with two "
         "tails hanging down off it, and a small sam_ink tag with a gold diamond hangs "
         "from the sash on a short cord just to the front of them.  Body speckles are "
         "skipped in the band the sash covers, and the stem nub is omitted - the katana "
         "takes its place.  Footprint about 1.8 x 1.7 studs, 6.43 tall, nothing below "
         "z = 0.  Eight parts: Body, Studs, Blade, Fittings, Handle, Sash, Knot, Tag.")

# ---------------------------------------------------------------- the katana axis
LEAN = 8.0                              # degrees: the top tips BACK, away from +Y
AXIS_BASE = (0.0, 0.18, 3.40)           # where the blade axis crosses z = 3.40
_SL = math.sin(math.radians(LEAN))
_CL = math.cos(math.radians(LEAN))
FRONT = (0.0, _CL, _SL)                 # outward normal of the tsuka's +Y face

# spans along the axis, measured from AXIS_BASE
T_BLADE = (0.00, 1.20)                  # buried at 3.40, out of the head at 4.00
T_GUARD = (1.11, 1.21)                  # the tsuba, centred on z 4.55
T_FUCHI = (1.19, 1.36)                  # gold collar at the foot of the grip
T_GRIP = (1.34, 2.86)                   # tsuka, 1.52 long -> z 4.73 .. 6.23
T_POMMEL = (2.82, 3.06)                 # kashira, tops out at z 6.43
GRIP_W0, GRIP_W1 = 0.215, 0.190

# the four diamond wraps: (distance up the axis, which side gets the second diamond)
DIAMONDS = [(1.62, 1.0), (1.98, -1.0), (2.34, 1.0), (2.70, -1.0)]

# ---------------------------------------------------------------- the sash
KNOT_ANG = 40.0                         # front-LEFT of the body (+X reads screen-left)
TAG_ANG = 78.0
TAG_C = (0.22, 0.865, 1.57)             # centre of the hanging ink tag

TAIL_A = [(0.60, 0.49, 2.12), (0.74, 0.55, 1.78), (0.86, 0.53, 1.44), (0.96, 0.44, 1.12)]
TAIL_B = [(0.50, 0.56, 2.10), (0.56, 0.66, 1.80), (0.54, 0.74, 1.52), (0.46, 0.76, 1.28)]


def _axis(t):
    """A point `t` studs up the leaning katana axis."""
    x, y, z = AXIS_BASE
    return (x, y - _SL * t, z + _CL * t)


def _grip_half(t):
    """Half-width of the tapering tsuka at `t`."""
    f = (t - T_GRIP[0]) / (T_GRIP[1] - T_GRIP[0])
    f = max(0.0, min(1.0, f))
    return (GRIP_W0 + (GRIP_W1 - GRIP_W0) * f) / 2.0


def _dir(ang_deg):
    a = math.radians(ang_deg)
    return (math.cos(a), math.sin(a), 0.0)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- body -----------------------------------------------------------
    # no stem nub: the blade goes in where it would have been
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=None)
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- speckles (standard 7 x 3, minus the band the sash covers) -------
    slots = [s for s in D.cuke_stud_slots(rows=7, per_row=3, z0=0.11, z1=0.90, seed=7)
             if not (0.46 < s[0] < 0.61)]
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, slots=slots, size=0.28, rise=0.055)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- blade stub ------------------------------------------------------
    mid = _axis((T_BLADE[0] + T_BLADE[1]) / 2.0)
    half = (T_BLADE[1] - T_BLADE[0]) / 2.0
    bm = bmesh.new()
    D.beveled_box(bm, (mid[0] - 0.105, mid[1] - 0.038, mid[2] - half),
                  (mid[0] + 0.105, mid[1] + 0.038, mid[2] + half),
                  bevel=0.026, rot=D.rot_euler(LEAN, 0, 0))
    D.new_obj("Blade", bm, c, D.C("sam_steel"), rbx_material="Metal")

    # ---- gold fittings: tsuba, fuchi, grip diamonds, tag diamond ---------
    bm = bmesh.new()
    # the tsuba - an 8-sided flat guard, 0.52 across and 0.10 thick, on the axis
    D.cyl(bm, _axis(T_GUARD[0]), _axis(T_GUARD[1]), 0.26, segs=8)
    D.branch_box(bm, _axis(T_FUCHI[0]), _axis(T_FUCHI[1]), 0.25, 0.235, bevel=0.04)
    for t, side in DIAMONDS:
        w = _grip_half(t)
        p = _axis(t)
        D.stud_patch(bm, (p[0] + FRONT[0] * w, p[1] + FRONT[1] * w, p[2] + FRONT[2] * w),
                     FRONT, size=0.15, rise=0.035, bevel=0.022, spin=45.0)
        D.stud_patch(bm, (p[0] + side * w, p[1], p[2]), (side, 0.0, 0.0),
                     size=0.15, rise=0.035, bevel=0.022, spin=45.0)
    # the gold diamond stamped on the hanging tag - same colour, same object
    tn = _dir(TAG_ANG)
    D.stud_patch(bm, (TAG_C[0] + tn[0] * 0.05, TAG_C[1] + tn[1] * 0.05, TAG_C[2]),
                 tn, size=0.15, rise=0.03, bevel=0.02, spin=45.0)
    D.new_obj("Fittings", bm, c, D.C("sam_gold"), rbx_material="Metal")

    # ---- tsuka + kashira --------------------------------------------------
    bm = bmesh.new()
    D.branch_box(bm, _axis(T_GRIP[0]), _axis(T_GRIP[1]), GRIP_W0, GRIP_W1, bevel=0.035)
    D.branch_box(bm, _axis(T_POMMEL[0]), _axis(T_POMMEL[1]), 0.235, 0.215, bevel=0.05)
    D.new_obj("Handle", bm, c, D.C("sam_hilt"), rbx_material="Leather")

    # ---- red sash + its two hanging tails ---------------------------------
    bm = bmesh.new()
    D.wrap_ribbon(bm, h=H, r=R, z0=0.52, z1=0.59, turns=1.0, width=0.30, thick=0.10,
                  n=20, phase_deg=KNOT_ANG, offset=0.05)
    for pts, ang in ((TAIL_A, 40.0), (TAIL_B, 62.0)):
        n = _dir(ang)
        D.ribbon(bm, [(p, n) for p in pts], 0.24, 0.08, taper=(1.0, 0.72))
    D.new_obj("Sash", bm, c, D.C("sam_ribbon"), rbx_material="Fabric")

    # ---- the knot over the sash's seam, and the tag cord ------------------
    k = D.cuke_point(h=H, r=R, zf=0.555, angle_deg=KNOT_ANG, offset=0.11)
    bm = bmesh.new()
    D.beveled_box(bm, (k[0] - 0.15, k[1] - 0.12, k[2] - 0.13),
                  (k[0] + 0.15, k[1] + 0.12, k[2] + 0.13),
                  bevel=0.05, rot=D.rot_euler(0, 0, KNOT_ANG - 90.0))
    th = D.cuke_point(h=H, r=R, zf=0.575, angle_deg=TAG_ANG, offset=0.09)
    D.tube(bm, [th, (0.20, 0.79, 2.02), (TAG_C[0], TAG_C[1] - 0.02, TAG_C[2] + 0.21)],
           [0.045, 0.040, 0.035], segs=5)
    D.new_obj("Knot", bm, c, D.C("sam_ribbon_dk"), rbx_material="Fabric")

    # ---- the ink tag ------------------------------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, (TAG_C[0] - 0.15, TAG_C[1] - 0.04, TAG_C[2] - 0.19),
                  (TAG_C[0] + 0.15, TAG_C[1] + 0.04, TAG_C[2] + 0.19),
                  bevel=0.035, rot=D.rot_euler(0, 0, TAG_ANG - 90.0))
    D.new_obj("Tag", bm, c, D.C("sam_ink"), rbx_material="Wood")

    return c
