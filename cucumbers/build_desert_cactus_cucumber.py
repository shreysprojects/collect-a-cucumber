"""Desert: Cactus Cucumber - a saguaro with two elbowed arms and a yellow crown flower."""
import bmesh, math

COLLECTION = "DesertCactusCucumber"
NOTES = ("A saguaro made of cucumbers: the standard 4.0-tall body with TWO elbowed arms - "
         "a short horizontal stub out of each side that turns up into a slim vertical "
         "column.  The left arm (POSITIVE x, screen-left) reaches to z 3.05, the right one "
         "only to z 2.30, so the silhouette is lopsided like a real saguaro.  Body and "
         "arms cuke_green with cuke_stud speckles; cream des_spike pyramid thorns over the "
         "body and both arms, all angled slightly UP and out.  On its head a five-petal "
         "des_flower yellow flower round a des_flower_c brown centre cube.  Footprint "
         "~3.4 x 1.7, height ~4.5.  Six parts: Body, Arms, Studs, Spikes, Petals, "
         "FlowerCentre.")

AR = 0.30           # arm radius (both segments)

# root x, root z, tilt of the horizontal stub (deg, signed), stub length, upright height
#   tilt is a rotation about Y: +76 sends the stub out to +x and slightly up.
ARMS = [
    (0.40, 1.72, 76.0, 0.88, 1.45),     # LEFT arm  (+x / screen-left) - the tall one
    (-0.40, 1.28, -76.0, 0.80, 1.16),   # RIGHT arm (-x) - the short one
]

# (height fraction, facet) speckles on each arm's upright column and horizontal stub
UP_STUDS = [(0.30, 1), (0.66, 1)]
STUB_STUDS = [(0.45, 1)]

# (height fraction, facet) thorns: outward facets differ per side, so one list per arm
UP_SPIKES = [[(0.26, 1), (0.54, 0), (0.80, 7)],      # left  arm: +Y, +45, +X
             [(0.26, 1), (0.54, 2), (0.80, 3)]]      # right arm: +Y, 135, -X
STUB_SPIKES = [[(0.42, 1), (0.74, 3)],               # left  stub: +Y, and local -X = up
               [(0.42, 1), (0.74, 7)]]               # right stub: +Y, and local +X = up

FLOWER_Z = 4.28     # the petal ring sits on the shoulder of the stem nub
PETAL_R = 0.26      # ring radius of the petal centres
CENTRE = 0.20       # brown centre cube, 0.2 across


def _rot_y(p, deg):
    """Rotate a point/vector about Y by `deg` - the same transform D.rot_euler(0, deg, 0)
    applies inside the lib, done in plain maths so no mathutils is needed here."""
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return (p[0] * ca + p[2] * sa, p[1], -p[0] * sa + p[2] * ca)


def _arms(D):
    """Per arm: (stub matrix, stub length, tilt, stub loc, upright matrix, upright h,
    upright loc)."""
    out = []
    for x0, z0, tilt, hlen, uph in ARMS:
        a = math.radians(tilt)
        ex = x0 + math.sin(a) * hlen          # elbow, where the stub hands over
        ez = z0 + math.cos(a) * hlen
        base = (ex, 0.0, ez - 0.33)           # the column starts just under the elbow
        out.append({
            "tilt": tilt, "hlen": hlen, "uph": uph,
            "stub_loc": (x0, 0.0, z0),
            "stub_m": D.place((x0, 0.0, z0), D.rot_euler(0.0, tilt, 0.0)),
            "up_loc": base,
            "up_m": D.place(base),
        })
    return out


def _thorn(D, bm, point, normal, length=0.21, base_r=0.095, lift=0.20):
    """One hard little pyramid thorn, pointing out of the skin and slightly UP."""
    d = (normal[0], normal[1], normal[2] + lift)
    n = math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) or 1.0
    tip = (point[0] + d[0] / n * length,
           point[1] + d[1] / n * length,
           point[2] + d[2] / n * length)
    D.spike(bm, point, tip, base_r, segs=4)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R
    arms = _arms(D)

    # ---- trunk ------------------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the two arms: a stub out of the side, then a column turning up ----
    bm = bmesh.new()
    for a in arms:
        D.cuke_body(bm, h=a["hlen"], r=AR, nub=None, matrix=a["stub_m"])
        D.cuke_body(bm, h=a["uph"], r=AR, nub=None, matrix=a["up_m"])
    D.new_obj("Arms", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- speckles: body + both arms, one object ---------------------------
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=5, per_row=3, z0=0.12, z1=0.90,
                 size=0.26, rise=0.05, seed=7)
    for a in arms:
        D.cuke_studs(bm, h=a["uph"], r=AR, slots=UP_STUDS, size=0.17, rise=0.035,
                     matrix=a["up_m"])
        D.cuke_studs(bm, h=a["hlen"], r=AR, slots=STUB_STUDS, size=0.17, rise=0.035,
                     matrix=a["stub_m"])
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- thorns: the ring round the body, then a few by hand on the arms ---
    bm = bmesh.new()
    D.spike_ring(bm, h=H, r=R, rows=4, per_row=2, z0=0.14, z1=0.90,
                 length=0.24, base_r=0.11, segs_spike=4, droop=-0.16, seed=5)
    for i, a in enumerate(arms):
        for zf, facet in UP_SPIKES[i]:
            p, n = D.cuke_facet_point(h=a["uph"], r=AR, zf=zf, facet=facet, offset=-0.03)
            loc = a["up_loc"]
            _thorn(D, bm, (p[0] + loc[0], p[1] + loc[1], p[2] + loc[2]), n)
        for zf, facet in STUB_SPIKES[i]:
            p, n = D.cuke_facet_point(h=a["hlen"], r=AR, zf=zf, facet=facet, offset=-0.03)
            wp, wn = _rot_y(p, a["tilt"]), _rot_y(n, a["tilt"])
            loc = a["stub_loc"]
            _thorn(D, bm, (wp[0] + loc[0], wp[1] + loc[1], wp[2] + loc[2]), wn)
    D.new_obj("Spikes", bm, c, D.C("des_spike"), rbx_material="SmoothPlastic")

    # ---- the crown flower: five petals round a brown middle ---------------
    bm = bmesh.new()
    petal = D.rounded_rect_pts(0.26, 0.42, 0.11, segs=3)
    for i, (px, py) in enumerate(D.ring_xy(5, PETAL_R, phase_deg=90.0)):
        yaw = 72.0 * i                          # point the petal's +Y end outward
        D.prism(bm, petal, -0.045, 0.045,
                matrix=D.place((px, py, FLOWER_Z), D.rot_euler(25.0, 0.0, yaw)))
    D.new_obj("Petals", bm, c, D.C("des_flower"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.beveled_box(bm, (-CENTRE / 2, -CENTRE / 2, FLOWER_Z - 0.01),
                  (CENTRE / 2, CENTRE / 2, FLOWER_Z - 0.01 + CENTRE), bevel=0.035)
    D.new_obj("FlowerCentre", bm, c, D.C("des_flower_c"), rbx_material="SmoothPlastic")

    return c
