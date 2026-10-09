"""Neon: Neon Palm - a leaning indigo palm with glowing magenta bands and neon-tipped fronds."""
import bmesh, math

COLLECTION = "NeonPalm"
NOTES = ("An 11.5-stud neon palm, transcribed from the rev-3 reference tile.  A dark indigo "
         "12-gon puck (r 1.30, z 0-0.18, neo_night) carries a chunky 8-sided trunk of EIGHT "
         "stacked tapering segments (r 0.80 at the foot -> 0.62 at its top, z 0.10-8.60, "
         "neo_trunk), each pinched 5 % at its top so the next steps out over it and the "
         "segments read.  The trunk curves as it rises (offset grows as (z/8.6)^1.7) and "
         "puts the crown axis at (-0.80, +0.42): a ~6 deg lean toward the tile's right (-X) "
         "and the viewer (+Y).  Three glowing magenta Neon bands (0.16 tall, 0.045 proud) "
         "ring it: one at the FOOT sitting on the puck (z 0.18-0.34), then z 2.37-2.53 and "
         "4.32-4.48 over two segment seams.  A short 8-sided heart (z 8.50-9.12) caps the "
         "trunk and SEVEN folded (roof section, 18 deg), sawtooth-notched, broad fronds "
         "(~1.2 wide at 55 % of their length) spring from it at z 8.92-9.04, each rolled "
         "about its own axis so its face, not its edge, shows from the front.  As in the "
         "tile: +X side (tile LEFT) = a full cyan Neon frond arching back-left (yaw 338) and "
         "a green frond with a cyan Neon outer 45 % running out flat then hanging to z ~6.0 "
         "(yaw 8); the back two (yaw 300 / 258) are plain green and arch highest (the "
         "model's top, z 11.5); -X side (tile RIGHT) = three green fronds with magenta Neon "
         "outer 45 % (yaw 215 arching back, 175 hanging to z ~6.5, 138 plunging to z ~6.0 "
         "just outside the front-right coconut).  The front sector (yaw 8-138) is left open "
         "so the coconuts show, as in the tile.  Under the crown hang FIVE big faceted "
         "coconut pods (8-sided, bulb at the bottom, r 0.72-0.76 x 2.3-2.45 long, neck tops "
         "at z 8.78, 0.85 off the crown axis, resting against the heart with their inner "
         "sides sunk 0.03-0.3 into the trunk top, splayed 13 deg outward, bottoms at z "
         "~6.3-6.5) in a light yellow-green, each with three raised dark-green speckles on "
         "its outward facets.  Footprint ~7.4 (X, crown) x 5.0 (Y) x 11.5 tall; the base is "
         "centred on x=0/y=0, the crown axis sits at (-0.80, +0.42) so the crown overhangs "
         "toward -X, and its fronds reach further back (y -2.8) than front (y +2.2); faces +Y; "
         "nothing below z=0 (the puck's underside is the lowest point).  ~3000 tris.  SEVEN "
         "parts: Base, Trunk, Magenta (3 bands + 3 magenta frond tips, Neon emit 0.6), "
         "FrondsGreen, FrondsCyan (Neon emit 0.6), Coconuts, CoconutStuds.  DEVIATIONS from "
         "the brief, each because the tile shows it: 7 fronds, not 8 (2 green, 1 cyan, "
         "1 green-with-cyan-tip, 3 green-with-magenta-tip, not 3 green / 3 cyan / 2 "
         "magenta-tip); the lowest magenta glow is a band at the trunk foot, not a ring on "
         "the puck rim (the tile's puck is plain dark), and the upper bands sit at z 2.45 / "
         "4.40 (not 2.0 / 4.3 / 6.6); the trunk is as chunky as the tile's (r 0.80 -> 0.62, "
         "not 0.52 -> 0.34), so the puck grew to r 1.30, and its top is at z 8.6 with the "
         "crown rooted at ~9.0 (not 9.2 / 9.3) so that, as in the tile, the crown fills the "
         "top half; fronds reach 2.4-3.45 out but are 4.4-5.8 long along their curve, and "
         "are lofted with D.ribbon + D.prism teeth instead of D.palm_frond (which is one flat "
         "strip) so each can split into a green inner and a glowing outer piece and roll its "
         "face to the viewer; the "
         "coconuts are the tile's big pods (not 0.55 lumps), coloured LIGHTER and yellower "
         "than the fronds (sam_leaf, not neo_green_dk), with darker speckles "
         "(neo_green_dk); green parts are SmoothPlastic like the rest of the neon set, not "
         "LeafyGrass.  Fronds, teeth and pods are lofted / matrix-placed, so dryrun's "
         "bounding box is approximate.")

# ---- base puck ---------------------------------------------------------------
BASE_R, BASE_H = 1.30, 0.18

# ---- trunk -------------------------------------------------------------------
TRUNK_Z0, TRUNK_Z1 = 0.10, 8.60          # foot sunk 0.08 into the puck
TRUNK_R0, TRUNK_R1 = 0.80, 0.62          # chunky, like the tile
LEAN = (-0.80, 0.42)                     # crown offset: -X = the tile's right, +Y = viewer
LEAN_POW = 1.7                           # straight-ish at the foot, curving near the top
JOINTS = (0.10, 1.30, 2.45, 3.43, 4.40, 5.45, 6.50, 7.55, 8.60)
LIP = 0.95                               # each segment pinches to 95 % at its top
SEG_OVERLAP = 0.03
BANDS = (0.26, 2.45, 4.40)               # foot band on the puck, then two seam bands
BAND_H, BAND_PROUD = 0.16, 0.045
TRUNK_SEGS = 8

# the heart the fronds spring from: (z, radius), on the crown axis
HEART = ((8.50, 0.62), (8.85, 0.58), (9.12, 0.36))

# ---- fronds ------------------------------------------------------------------
# centreline in the frond's vertical plane:  x = L t,  z = a t - d t^p   (t = 0..1),
# set by the height of its apex (`rise`) and where along it the apex falls (`t_apex`):
#   d = rise / ((p - 1) t_apex^p),  a = p d t_apex^(p - 1),  tip = a - d.
# p = 4 runs out nearly flat and then hangs (the side fronds); p = 3 arches (the back).
# `roll` turns the whole leaf about its own axis (positive tips its top face toward its
# +side = (-sin yaw, cos yaw)): the side fronds are rolled so their broad face, not their
# edge, shows from the front, the way every frond in the tile does.
# (yaw deg, reach L, p, t_apex, rise, root z, roll deg, kind, width mult)   tip vs root
FRONDS = [
    (8.0,   3.45, 4, 0.44, 0.50, 8.94,  45.0, "cyan_tip", 1.05),   # -2.93  tile left
    (338.0, 3.20, 3, 0.60, 1.50, 9.00,  25.0, "cyan",     1.00),   # +0.28  tile upper left
    (300.0, 2.90, 3, 0.66, 2.40, 9.04,  20.0, "green",    0.96),   # +1.28  tile top
    (258.0, 3.00, 3, 0.60, 2.00, 9.02, -15.0, "green",    0.98),   # +0.37  back
    (215.0, 3.20, 3, 0.56, 1.35, 9.00, -25.0, "mag_tip",  1.00),   # -0.23  tile upper right
    (175.0, 3.40, 4, 0.46, 0.55, 8.96, -45.0, "mag_tip",  1.05),   # -2.50  tile right
    (138.0, 2.40, 3, 0.34, 0.35, 8.92, -20.0, "mag_tip",  0.94),   # -2.91  tile lower right
]
ROOT_OUT = 0.20            # roots sit this far out from the crown axis, inside the heart
FOLD = 18.0                # each half of a frond tips down this much from the midrib
FROND_T = 0.12             # leaf thickness
MID_OV = 0.06              # the two halves overlap this much across the midrib
SPLIT = 0.55               # green inner / glowing outer boundary (outer 45 %)
HW_ROOT, HW_MAX, HW_TIP = 0.30, 0.62, 0.08   # half-widths at t = 0, SPLIT, 1
N_IN, N_OUT = 5, 6         # loft frames per piece
TEETH_T = (0.36, 0.76)     # one sawtooth notch per edge on each piece
TOOTH = 0.18

# ---- coconut pods ------------------------------------------------------------
# a hanging pod: bulb at the BOTTOM (local z = 0), narrow neck at the top
POD_PROFILE = [
    (0.00, 0.00), (0.50, 0.00), (0.84, 0.07), (1.00, 0.22), (1.00, 0.42),
    (0.88, 0.64), (0.64, 0.84), (0.42, 1.00), (0.00, 1.00),
]
POD_TOP_Z, POD_RING, POD_TILT = 8.78, 0.85, 13.0
# (azimuth deg round the crown axis, height, radius, speckle slots (zf, facet))
# facet f faces (f + 1) * 45 deg: 0 = +45, 1 = +Y, 2 = 135, 3 = -X, 5 = -Y, 7 = +X
PODS = [
    (54.0,  2.45, 0.76, [(0.29, 0), (0.52, 1), (0.38, 7)]),
    (126.0, 2.40, 0.76, [(0.31, 2), (0.50, 1), (0.40, 3)]),
    (198.0, 2.35, 0.74, [(0.30, 3), (0.50, 4), (0.36, 2)]),
    (270.0, 2.30, 0.72, [(0.32, 5), (0.50, 6), (0.40, 4)]),
    (342.0, 2.35, 0.74, [(0.30, 7), (0.50, 6), (0.38, 0)]),
]


# ------------------------------------------------------------------ helpers
def _off(z):
    """Horizontal offset of the trunk centreline at height z."""
    f = max(0.0, min(1.0, z / TRUNK_Z1)) ** LEAN_POW
    return (LEAN[0] * f, LEAN[1] * f)


def _ctr(z):
    ox, oy = _off(z)
    return (ox, oy, z)


def _rad(z):
    return TRUNK_R0 + (TRUNK_R1 - TRUNK_R0) * (z - TRUNK_Z0) / (TRUNK_Z1 - TRUNK_Z0)


def _hw(t):
    """Half-width of a frond at parameter t: widest at SPLIT, linear either side."""
    if t <= SPLIT:
        return HW_ROOT + (HW_MAX - HW_ROOT) * (t / SPLIT)
    return HW_MAX + (HW_TIP - HW_MAX) * ((t - SPLIT) / (1.0 - SPLIT))


def _curve(p, t_apex, rise):
    """(a, d) of the frond centreline z = a t - d t^p with its apex `rise` up at t_apex."""
    d = rise / ((p - 1) * t_apex ** p)
    return p * d * t_apex ** (p - 1), d


def _frame(root, yaw, L, a, d, p, t):
    """Point, tangent, up-normal, side vector and slope (deg) of a frond at t."""
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    p_ = (root[0] + cy * L * t, root[1] + sy * L * t, root[2] + a * t - d * t ** p)
    s = a - p * d * t ** (p - 1)                     # dz/dt
    n = math.hypot(L, s)
    T = (cy * L / n, sy * L / n, s / n)
    N = (-cy * s / n, -sy * s / n, L / n)            # in the frond's vertical plane, up
    W = (-sy, cy, 0.0)                               # horizontal, across the frond
    return p_, T, N, W, math.degrees(math.atan2(s, L))


def _half(D, bm, root, yaw, L, a, d, pw, roll, t0, t1, n, side, wm):
    """One half of a folded frond between t0 and t1: a strip from just past the midrib
    out to the edge, tipped FOLD degrees down so the frond has a roof-shaped section.
    The leaf's across (W) and up (N) axes are first rolled by `roll` about its tangent."""
    cf, sf = math.cos(math.radians(FOLD)), math.sin(math.radians(FOLD))
    cr, sr = math.cos(math.radians(roll)), math.sin(math.radians(roll))
    frames = []
    for i in range(n):
        t = t0 + (t1 - t0) * i / float(n - 1)
        p, T, N, W, _ = _frame(root, yaw, L, a, d, pw, t)
        Wr = tuple(W[k] * cr - N[k] * sr for k in range(3))
        Nr = tuple(N[k] * cr + W[k] * sr for k in range(3))
        e = tuple(side * Wr[k] * cf - Nr[k] * sf for k in range(3))    # midrib -> edge
        nrm = tuple(Nr[k] * cf + side * Wr[k] * sf for k in range(3))  # this half's up
        off = (_hw(t) * wm - MID_OV) / 2.0
        frames.append((tuple(p[k] + e[k] * off for k in range(3)), nrm))
    D.ribbon(bm, frames, 1.0, FROND_T,
             taper=(_hw(t0) * wm + MID_OV, _hw(t1) * wm + MID_OV))


def _tooth(D, bm, root, yaw, L, a, d, pw, roll, t, side, wm):
    """A sawtooth notch on one edge: a flat triangle in that half's plane, swept toward
    the tip.  rot_euler(-roll - side*FOLD, -slope, yaw) = Rz(yaw) Ry(-slope) Rx(...)
    takes local X onto the frond tangent, local Y onto side * this half's outward edge
    direction and local Z onto this half's normal (roll and fold are both turns about
    the tangent, so they simply add)."""
    p, T, N, W, slope = _frame(root, yaw, L, a, d, pw, t)
    hw = _hw(t) * wm
    y0, y1 = side * (hw - 0.07), side * (hw + TOOTH)
    m = D.place(p, D.rot_euler(-roll - side * FOLD, -slope, yaw))
    D.prism(bm, [(-0.17, y0), (0.15, y0), (0.30, y1)], -FROND_T / 2.0, FROND_T / 2.0,
            matrix=m)


def _frond(D, bm_in, bm_out, root, yaw, L, a, d, pw, roll, wm):
    """Both halves, inner piece into bm_in and outer piece into bm_out, with teeth."""
    for side in (1.0, -1.0):
        _half(D, bm_in, root, yaw, L, a, d, pw, roll, 0.0, SPLIT, N_IN, side, wm)
        _half(D, bm_out, root, yaw, L, a, d, pw, roll, SPLIT, 1.0, N_OUT, side, wm)
        _tooth(D, bm_in, root, yaw, L, a, d, pw, roll, TEETH_T[0], side, wm)
        _tooth(D, bm_out, root, yaw, L, a, d, pw, roll, TEETH_T[1], side, wm)


# ------------------------------------------------------------------ build
def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    hx, hy = LEAN                      # the crown axis (vertical above the trunk top)

    # ---- the dark puck -----------------------------------------------------
    bm = bmesh.new()
    D.lathe(bm, [(0.0, 0.0), (BASE_R, 0.0), (BASE_R, BASE_H - 0.07),
                 (BASE_R - 0.07, BASE_H), (0.0, BASE_H)],
            segs=12, phase=math.pi / 12.0)
    D.new_obj("Base", bm, c, D.C("neo_night"), rbx_material="SmoothPlastic")

    # ---- the segmented, curving trunk + the heart ----------------------------
    bm = bmesh.new()
    for i in range(len(JOINTS) - 1):
        z0, z1 = JOINTS[i], JOINTS[i + 1]
        zs = z0 - (SEG_OVERLAP if i > 0 else 0.0)
        D.tube(bm, [_ctr(zs), _ctr(z1)], [_rad(z0), _rad(z1) * LIP], segs=TRUNK_SEGS)
    (zh0, rh0), (zh1, rh1), (zh2, rh2) = HEART
    D.tube(bm, [_ctr(zh0), (hx, hy, zh1), (hx, hy, zh2)], [rh0, rh1, rh2],
           segs=TRUNK_SEGS)
    D.new_obj("Trunk", bm, c, D.C("neo_trunk"), rbx_material="SmoothPlastic")

    # ---- fronds ------------------------------------------------------------
    bm_green, bm_cyan, bm_mag = bmesh.new(), bmesh.new(), bmesh.new()
    for (yaw, L, pw, t_apex, rise, rz, roll, kind, wm) in FRONDS:
        a, d = _curve(pw, t_apex, rise)
        ya = math.radians(yaw)
        root = (hx + ROOT_OUT * math.cos(ya), hy + ROOT_OUT * math.sin(ya), rz)
        inner = bm_cyan if kind == "cyan" else bm_green
        outer = {"green": bm_green, "cyan": bm_cyan, "cyan_tip": bm_cyan,
                 "mag_tip": bm_mag}[kind]
        _frond(D, inner, outer, root, yaw, L, a, d, pw, roll, wm)

    # ---- the magenta bands join the magenta tips in one Neon part -----------
    for zc in BANDS:
        za, zb = zc - BAND_H / 2.0, zc + BAND_H / 2.0
        rr = max(_rad(za), _rad(zb)) + BAND_PROUD
        D.tube(bm_mag, [_ctr(za), _ctr(zb)], [rr, rr], segs=TRUNK_SEGS)

    D.new_obj("Magenta", bm_mag, c, D.C("neo_magenta"), rbx_material="Neon", emit=0.6)
    D.new_obj("FrondsGreen", bm_green, c, D.C("neo_green"), rbx_material="SmoothPlastic")
    D.new_obj("FrondsCyan", bm_cyan, c, D.C("neo_cyan"), rbx_material="Neon", emit=0.6)

    # ---- the coconut pods under the crown ------------------------------------
    bm, bm2 = bmesh.new(), bmesh.new()
    sb = math.sin(math.radians(POD_TILT))
    for (az, h, r, slots) in PODS:
        dx, dy = math.cos(math.radians(az)), math.sin(math.radians(az))
        top = (hx + POD_RING * dx, hy + POD_RING * dy, POD_TOP_Z)
        up = (-dx * sb, -dy * sb, math.cos(math.radians(POD_TILT)))   # bulb swings out
        bot = (top[0] - h * up[0], top[1] - h * up[1], top[2] - h * up[2])
        rx = math.degrees(math.asin(dy * sb))
        ry = math.degrees(math.asin(-dx * sb / math.cos(math.radians(rx))))
        m = D.place(bot, D.rot_euler(rx, ry, 0.0))      # local +Z -> `up`
        D.cuke_body(bm, h=h, r=r, profile=POD_PROFILE, segs=8, matrix=m)
        D.cuke_studs(bm2, h=h, r=r, profile=POD_PROFILE, slots=slots, size=0.27,
                     rise=0.06, matrix=m)
    D.new_obj("Coconuts", bm, c, D.C("sam_leaf"), rbx_material="SmoothPlastic")
    D.new_obj("CoconutStuds", bm2, c, D.C("neo_green_dk"), rbx_material="SmoothPlastic")

    return c
