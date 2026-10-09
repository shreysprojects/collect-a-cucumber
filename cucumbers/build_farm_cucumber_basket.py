"""Farm: a round woven basket with a cane handle, three cucumbers fanned out of it."""
import bmesh, math

COLLECTION = "FarmCucumberBasket"
NOTES = ("A round 12-sided woven basket ~3.4 studs across and 1.9 tall sitting on z = 0, "
         "with a cane handle arching over to z 3.9 and three stubby cucumbers leaning "
         "out of its mouth.  The basket is ONE hollow lathe - up the outside to r 1.50 "
         "at the rim, over the rim and back down the inside to a floor at z 0.32 - with "
         "the handle merged into the same object.  Over it the dark weave: ten leaning "
         "vertical staves, three horizontal bands and a chunky rim collar that caps the "
         "stave ends.  Two leather binds lash the handle to the rim just above it.  The "
         "three cucumbers use CUKE_PROFILE_STUB at h 2.6-2.9 and r 0.46 - big enough to "
         "be the first thing you see.  Each sits low in the bowl with its MIDPOINT level "
         "with the rim, so half its length stands proud, and they splay out 19-27 deg "
         "front-right, front-left and back, clear of the wall and of the handle arch.  "
         "Faces +Y.  "
         "Six parts: Basket (body + handle), Weave, Binds, Cukes, CukeStuds, Stems.")

# ---------------------------------------------------------------- basket shell
R_FOOT, R_BASE, R_RIM = 1.12, 1.25, 1.50
Z_TAPER, Z_WALL, Z_TOP = 0.15, 1.58, 1.74
Z_IN = 0.32                      # the inside floor the cucumbers stand on

SEGS = 12
PHASE = math.pi / SEGS           # puts a flat facet square on +Y

# (radius, z): out over the foot, up the wall, over the rim, back down the inside
BASKET = [
    (0.00, 0.00),
    (R_FOOT, 0.00),
    (R_BASE, Z_TAPER),
    (R_RIM, Z_WALL),
    (R_RIM, Z_TOP),
    (1.30, Z_TOP),
    (1.28, 1.44),
    (1.06, 0.44),
    (0.94, Z_IN),
    (0.00, Z_IN),
]

# ---------------------------------------------------------------- the weave
STAVES = 10
STAVE_Z0, STAVE_Z1 = 0.10, 1.62
BANDS = (0.40, 0.94, 1.46)       # centre height of each horizontal weaver
COLLAR = [(1.24, 1.58), (1.68, 1.62), (1.68, 1.84), (1.24, 1.88), (1.24, 1.58)]

# ---------------------------------------------------------------- the handle
H_R, H_Z, H_RISE = 1.45, 1.50, 2.40      # springs from z 1.50, peaks at z 3.90
BIND_A = (14.0, 166.0)                   # where the leather lashings sit on the arch

# ---------------------------------------------------------------- the fruit
# base x, base y, base z | azimuth it leans toward | tilt | height | radius | seed
# Each base sits low in the bowl and each z is set so the body's MIDPOINT is level with
# the rim (Z_TOP 1.74) - half the cucumber stands proud.  The azimuths keep well clear of
# the y = 0 plane the handle arch lives in; the tilts are capped by the inside wall.
CUKES = [
    (0.054, 0.045, 0.528, 40.0, 27.0, 2.72, 0.46, 11),
    (-0.154, 0.112, 0.516, 144.0, 22.0, 2.64, 0.46, 12),
    (-0.008, -0.240, 0.442, 268.0, 19.0, 2.86, 0.46, 13),
]


def _wall_r(z):
    """Outer radius of the basket wall at height z."""
    if z <= 0.0:
        return R_FOOT
    if z < Z_TAPER:
        return R_FOOT + (R_BASE - R_FOOT) * (z / Z_TAPER)
    if z < Z_WALL:
        return R_BASE + (R_RIM - R_BASE) * ((z - Z_TAPER) / (Z_WALL - Z_TAPER))
    return R_RIM


def _handle_pt(a_deg):
    a = math.radians(a_deg)
    return (H_R * math.cos(a), 0.0, H_Z + H_RISE * math.sin(a))


def _handle_dir(a_deg):
    a = math.radians(a_deg)
    dx, dz = -H_R * math.sin(a), H_RISE * math.cos(a)
    L = math.hypot(dx, dz) or 1.0
    return (dx / L, 0.0, dz / L)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- basket shell + cane handle ------------------------------------------
    bm = bmesh.new()
    D.lathe(bm, BASKET, segs=SEGS, phase=PHASE)

    arc = D.arc_pts((0.0, H_Z), H_R, 0.0, 180.0, n=9, ry=H_RISE)
    pts = ([(H_R - 0.01, 0.0, 1.06)]
           + [(x, 0.0, z) for (x, z) in arc]
           + [(-(H_R - 0.01), 0.0, 1.06)])
    radii = [0.15, 0.15, 0.145, 0.14, 0.135, 0.13, 0.135, 0.14, 0.145, 0.15, 0.15]
    D.tube(bm, pts, radii, segs=6)
    D.new_obj("Basket", bm, c, D.C("farm_basket"), rbx_material="Wood")

    # ---- weave: staves, horizontal bands, rim collar --------------------------
    bm = bmesh.new()
    lean = math.degrees(math.atan2(_wall_r(STAVE_Z1) - _wall_r(STAVE_Z0),
                                   STAVE_Z1 - STAVE_Z0))
    zc = (STAVE_Z0 + STAVE_Z1) / 2.0
    half = (STAVE_Z1 - STAVE_Z0) / 2.0
    rc = _wall_r(zc) + 0.02
    for i in range(STAVES):
        ang = 90.0 + 360.0 * i / STAVES          # one stave square on the front
        a = math.radians(ang)
        cx, cy = rc * math.cos(a), rc * math.sin(a)
        D.beveled_box(bm, (cx - 0.12, cy - 0.16, zc - half),
                      (cx + 0.12, cy + 0.16, zc + half), bevel=0.05,
                      rot=D.rot_euler(0.0, lean, ang))
    for z in BANDS:
        rb, rt = _wall_r(z - 0.10), _wall_r(z + 0.10)
        D.lathe(bm, [(rb - 0.09, z - 0.10), (rb + 0.07, z - 0.075),
                     (rt + 0.07, z + 0.075), (rt - 0.09, z + 0.10),
                     (rb - 0.09, z - 0.10)], segs=SEGS, phase=PHASE, cap=False)
    D.lathe(bm, COLLAR, segs=SEGS, phase=PHASE, cap=False)
    D.new_obj("Weave", bm, c, D.C("farm_basket_d"), rbx_material="Wood")

    # ---- leather binds holding the handle to the rim --------------------------
    bm = bmesh.new()
    for a_deg in BIND_A:
        p, t = _handle_pt(a_deg), _handle_dir(a_deg)
        D.cyl(bm, (p[0] - t[0] * 0.14, 0.0, p[2] - t[2] * 0.14),
              (p[0] + t[0] * 0.14, 0.0, p[2] + t[2] * 0.14), 0.215, segs=6)
    D.new_obj("Binds", bm, c, D.C("farm_strap"), rbx_material="Leather")

    # ---- the three cucumbers --------------------------------------------------
    bmc, bmu, bms = bmesh.new(), bmesh.new(), bmesh.new()
    for (x, y, z, az, tilt, hh, rr, sd) in CUKES:
        m = D.place((x, y, z), D.rot_euler(0.0, tilt, az))
        D.cuke_body(bmc, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, nub=None, matrix=m)
        D.cuke_studs(bmu, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, rows=4, per_row=2,
                     z0=0.24, z1=0.88, size=0.21, rise=0.045, seed=sd, matrix=m)
        vs = D.beveled_box(bms, (-0.10, -0.10, hh - 0.08), (0.10, 0.10, hh + 0.20),
                           bevel=0.035)
        D.xform(bms, vs, m)
    D.new_obj("Cukes", bmc, c, D.C("cuke_green"), rbx_material="SmoothPlastic")
    D.new_obj("CukeStuds", bmu, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")
    D.new_obj("Stems", bms, c, D.C("cuke_stem"), rbx_material="SmoothPlastic")

    return c
