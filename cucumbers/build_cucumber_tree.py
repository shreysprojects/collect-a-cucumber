"""Grass: Cucumber Tree - blocky brown trunk, cube crown, four cucumbers hanging."""
import bmesh, math

COLLECTION = "CucumberTree"
NOTES = ("A 12-stud toy tree: a two-step plinth, a tapering blocky trunk that forks into "
         "four straight square branches, six speckled green crown cubes sitting on the "
         "forks, and four small cucumbers hanging under the branches.  Faces +Y.  "
         "Five parts: Trunk, Crown, CrownStuds, Cukes, CukeStuds.")

H = 12.0

# (end x, end y, end z, start z) for each fork of the trunk
BRANCHES = [
    (-1.85, 0.20, 8.30, 5.20),
    (1.95, -0.15, 8.55, 5.00),
    (-0.95, -1.55, 7.95, 5.60),
    (1.05, 1.45, 8.10, 5.60),
]

# crown cubes: (dx, dy, dz, size multiplier) around the crown centre
CROWN = [
    (0.00, 0.00, 1.55, 1.16),
    (-2.25, 0.30, 0.55, 1.00),
    (2.30, -0.20, 0.75, 1.02),
    (-1.05, -1.85, 0.25, 0.92),
    (1.20, 1.75, 0.35, 0.94),
    (0.15, 0.10, -0.15, 0.86),
]

# hanging cucumbers: (x, y, top z, height, radius, lean degrees)
HANGING = [
    (-2.15, -0.55, 7.35, 1.95, 0.34, 6.0),
    (1.55, -1.05, 7.10, 2.10, 0.36, -8.0),
    (2.55, 0.55, 7.00, 1.80, 0.32, 5.0),
    (-0.55, 1.35, 6.80, 1.70, 0.30, -4.0),
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- trunk ------------------------------------------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=1.45, h=1.30, steps=2, grow=1.36, bevel=0.08)
    D.blocky_trunk(bm, 1.30, 5.90, 1.30, 0.98, blocks=3, bevel=0.08)
    for (bx, by, bz, z0) in BRANCHES:
        D.branch_box(bm, (0.0, 0.0, z0), (bx, by, bz), 0.62, 0.42, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("farm_bark"), rbx_material="Wood")

    # ---- crown ------------------------------------------------------------
    ctr = (0.15, 0.0, 8.55)
    bm = bmesh.new()
    D.crown_cluster(bm, ctr, 2.55, CROWN, bevel=0.14)
    D.new_obj("Crown", bm, c, D.C("cuke_green"), rbx_material="Grass")

    bm = bmesh.new()
    for i, (dx, dy, dz, k) in enumerate(CROWN):
        s = 2.55 * k
        lo = (ctr[0] + dx - s / 2, ctr[1] + dy - s / 2, ctr[2] + dz - s / 2)
        hi = (ctr[0] + dx + s / 2, ctr[1] + dy + s / 2, ctr[2] + dz + s / 2)
        # bevel=0 on the crown speckles: a chamfer on 96 little squares costs 3.5k tris
        # and reads identically to a crisp square at any distance a player sees this from
        D.box_studs(bm, lo, hi, faces=("-y", "+x", "-x", "+z"), grid=(2, 2), size=0.46,
                    rise=0.07, seed=20 + i, margin=0.34, bevel=0.0)
    D.new_obj("CrownStuds", bm, c, D.C("cuke_stud"), rbx_material="Grass")

    # ---- hanging cucumbers -------------------------------------------------
    bm = bmesh.new()
    bm2 = bmesh.new()
    for i, (x, y, ztop, hh, rr, lean) in enumerate(HANGING):
        m = D.place((x, y, ztop - hh), D.rot_euler(lean, 0, 18.0 * i))
        D.cuke_body(bm, h=hh, r=rr, nub=(0.16, 0.15), matrix=m)
        D.cuke_studs(bm2, h=hh, r=rr, rows=3, per_row=2, z0=0.20, z1=0.82, size=0.15,
                     rise=0.035, seed=30 + i, matrix=m)
    D.new_obj("Cukes", bm, c, D.C("cuke_mid"), rbx_material="SmoothPlastic")
    D.new_obj("CukeStuds", bm2, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
