"""Volcano: Flame Cucumber - an ordinary green cucumber wrapped in a spiral of fire."""
import bmesh, math

COLLECTION = "VolcanoFlameCucumber"
NOTES = ("A standard 4-stud GREEN cucumber - `cuke_green` body, stem nub, 21 `cuke_stud` "
         "speckles - with a broad orange flame ribbon spiralling 2 full turns up it, wide "
         "and lazy at the foot and narrow and quick at the head, so most of the green skin "
         "still shows between the coils.  A second, much narrower `vol_lava_hot` band runs "
         "down the middle of that ribbon standing 0.025 proud of it, the flame's hot core.  "
         "Four `vol_lava_core` flame licks flick off the ribbon's upper edge as it climbs "
         "- at z 2.5 (front-left), 3.2 (front-right), 3.7 (behind) and one off the very end "
         "of the ribbon that curls up and forward over the stem nub to z 4.78.  Footprint "
         "about 2.2 x 2.1, 4.8 tall.  Faces +Y.  Five parts: Body, Studs, FlameRibbon, "
         "FlameCore, FlameLicks - the three fire parts are Neon and glow.")

# ---- the flame ribbon (the rev-2 brief's numbers; z0 lifted 0.06 -> 0.09 so the band's
#      tapered lower EDGE clears the ground plane instead of dipping to z = -0.03)
Z0, Z1 = 0.09, 0.95
TURNS = 2.0
PHASE = -50.0
WIDTH, THICK, OFFSET = 0.52, 0.14, 0.05
TAPER = (1.15, 0.60)
NFRAMES = 32

# the hot core: the same spiral, half as wide, riding 0.025 proud of the ribbon's face so
# it reads as a bright stripe down the middle of the flame instead of being buried in it
CORE_WIDTH, CORE_THICK, CORE_OFFSET = 0.26, 0.12, 0.085

# flame licks torn off the ribbon's UPPER edge as it climbs.  Each is described relative
# to its root: how far the tip swings on round the spiral, how far it pushes out from the
# axis, and how far it rises.  The last one roots at the very top of the ribbon and curls
# forward over the stem nub.
#   (path t, sweep deg, out, rise, root radius)
LICKS = [
    (0.597, 33.0, 0.52, 0.74, 0.165),
    (0.792, 18.0, 0.50, 0.78, 0.170),
    (0.944, 22.0, 0.50, 0.80, 0.160),
    (1.000, 85.0, -0.30, 0.90, 0.185),
]


# ---------------------------------------------------------------- tuple maths
def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _norm(a):
    L = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    return (0.0, 0.0, 1.0) if L < 1e-9 else (a[0] / L, a[1] / L, a[2] / L)


def _cyl(ang_deg, rad, z):
    """A point in cylindrical coordinates about the body's axis (+Y = 90 deg)."""
    a = math.radians(ang_deg)
    return (math.cos(a) * rad, math.sin(a) * rad, z)


# ---------------------------------------------------------------- the flame path
def _zf(t):
    return Z0 + (Z1 - Z0) * t


def _ang(t):
    return PHASE + 360.0 * TURNS * t


def _half_width(t):
    return 0.5 * WIDTH * (TAPER[0] + (TAPER[1] - TAPER[0]) * t)


def _path(D, h, r, t, offset):
    return D.cuke_point(h=h, r=r, zf=_zf(t), angle_deg=_ang(t), offset=offset)


def _edge_up(D, h, r, t, offset):
    """Unit vector along the ribbon's UPPER edge at `t` - the frame `D.ribbon` lofts on,
    rebuilt here so the licks root exactly where the band's top edge is."""
    dt = 0.012
    a = _path(D, h, r, max(0.0, t - dt), offset)
    b = _path(D, h, r, min(1.0, t + dt), offset)
    return _norm(_mul(_cross(_norm(_sub(b, a)), D.cuke_normal(_ang(t))), -1.0))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- the cucumber, plain and green -------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- its speckles, the set's signature ---------------------------------
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=7, per_row=3, z0=0.11, z1=0.90,
                 size=0.28, rise=0.055, seed=7)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the flame wrapping it ---------------------------------------------
    bm = bmesh.new()
    D.wrap_ribbon(bm, h=H, r=R, z0=Z0, z1=Z1, turns=TURNS, width=WIDTH, thick=THICK,
                  n=NFRAMES, phase_deg=PHASE, offset=OFFSET, taper=TAPER)
    D.new_obj("FlameRibbon", bm, c, D.C("vol_lava"), rbx_material="Neon", emit=0.65)

    # ---- the hot core running down the middle of it ------------------------
    bm = bmesh.new()
    D.wrap_ribbon(bm, h=H, r=R, z0=Z0, z1=Z1, turns=TURNS, width=CORE_WIDTH,
                  thick=CORE_THICK, n=NFRAMES, phase_deg=PHASE, offset=CORE_OFFSET,
                  taper=TAPER)
    D.new_obj("FlameCore", bm, c, D.C("vol_lava_hot"), rbx_material="Neon", emit=0.65)

    # ---- tongues of flame flicking off the top of the ribbon ---------------
    bm = bmesh.new()
    for (t, sweep, out, rise, r0) in LICKS:
        root = _add(_path(D, H, R, t, OFFSET + 0.02),
                    _mul(_edge_up(D, H, R, t, OFFSET), _half_width(t) * 0.55))
        a0 = math.degrees(math.atan2(root[1], root[0]))
        rad0 = math.sqrt(root[0] * root[0] + root[1] * root[1])
        mid = _cyl(a0 + sweep * 0.45, rad0 + out * 0.58, root[2] + rise * 0.44)
        tip = _cyl(a0 + sweep, rad0 + out, root[2] + rise)
        D.tube(bm, [root, mid, tip], [r0, r0 * 0.55, 0.035], segs=5)
    D.new_obj("FlameLicks", bm, c, D.C("vol_lava_core"), rbx_material="Neon", emit=0.65)

    return c
