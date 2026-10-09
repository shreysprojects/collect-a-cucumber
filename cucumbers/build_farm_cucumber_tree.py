"""Farm: Cucumber Tree - flared root plinth, two big forks, four crown cubes, hanging fruit."""
import bmesh, math

COLLECTION = "FarmCucumberTree"
NOTES = ("An 11.8-stud orchard tree, the farm cousin of CucumberTree.  A THREE-step "
         "farm_bark_dk plinth gives it a wide root flare (2.78 across at the ground), a "
         "farm_bark blocky trunk of three stacked boxes runs up into the crown, and just "
         "TWO big square forks swing out low (z 5.05 / 5.35) into the side crown cubes.  "
         "The crown is four LARGE cuke_green cubes (size 2.8) around (0, 0, 8.85), "
         "speckled with cuke_stud box_studs on their outward faces.  Three cucumbers hang "
         "under the crown, their tops tucked up inside the cubes so ~1.8 studs of each "
         "dangles clear in silhouette.  Footprint 6.44 x 5.53, height 11.84, centred on "
         "x = 0 / y = 0, facing +Y, nothing below z = 0.  Five parts: Base, Trunk, Crown, "
         "Studs, Cukes  (the hanging fruit's speckles are merged into the one Studs "
         "object to hold the brief's five-part count).")

# ---- the plinth and the trunk ------------------------------------------------
BASE_TOP_W = 1.55
BASE_H = 1.75
TRUNK_Z1 = 7.60

# two big forks: (start, end)
BRANCHES = [
    ((0.05, 0.00, 5.05), (1.90, -0.62, 8.35)),
    ((-0.05, 0.00, 5.35), (-1.82, 0.70, 8.20)),
]

CROWN_CTR = (0.0, 0.0, 8.85)
CROWN_SIZE = 2.8

# four large crown cubes: (dx, dy, dz, size multiplier, stud faces)
CROWN = [
    (0.00, 0.10, 1.55, 1.03, ("+z", "+y", "+x", "-x")),   # the big one on top
    (-1.78, 1.18, 0.20, 1.00, ("-x", "+y", "+z")),        # screen-right, forward
    (1.86, -0.60, 0.30, 1.00, ("+x", "+y", "+z")),        # screen-left
    (0.15, -1.58, -0.15, 0.98, ("-y", "+z", "+x")),       # back, low
]

# three hanging cucumbers: (x, y, top z, height, radius, lean degrees)
HANGING = [
    (-2.25, 1.35, 7.72, 2.15, 0.36, 6.0),
    (2.35, 0.30, 7.82, 1.95, 0.34, -7.0),
    (0.65, -1.10, 7.45, 1.80, 0.33, 5.0),
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- flared root plinth ------------------------------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=3, grow=1.34, bevel=0.09)
    D.new_obj("Base", bm, c, D.C("farm_bark_dk"), rbx_material="Wood")

    # ---- trunk + the two big forks -----------------------------------------
    bm = bmesh.new()
    D.blocky_trunk(bm, BASE_H, TRUNK_Z1, 1.45, 1.00, blocks=3, bevel=0.08)
    for a, b in BRANCHES:
        D.branch_box(bm, a, b, 0.78, 0.50, bevel=0.06)
    D.new_obj("Trunk", bm, c, D.C("farm_bark"), rbx_material="Wood")

    # ---- crown -------------------------------------------------------------
    bm = bmesh.new()
    D.crown_cluster(bm, CROWN_CTR, CROWN_SIZE, CROWN, bevel=0.15)
    D.new_obj("Crown", bm, c, D.C("cuke_green"), rbx_material="Grass")

    # ---- every speckle: crown cubes + the hanging fruit ---------------------
    cx, cy, cz = CROWN_CTR
    bm = bmesh.new()
    for i, (dx, dy, dz, k, faces) in enumerate(CROWN):
        s = CROWN_SIZE * k
        lo = (cx + dx - s / 2, cy + dy - s / 2, cz + dz - s / 2)
        hi = (cx + dx + s / 2, cy + dy + s / 2, cz + dz + s / 2)
        D.box_studs(bm, lo, hi, faces=faces, grid=(2, 2), size=0.50, rise=0.07,
                    seed=40 + i, margin=0.34)

    # ---- hanging cucumbers -------------------------------------------------
    bm2 = bmesh.new()
    for i, (x, y, ztop, hh, rr, lean) in enumerate(HANGING):
        m = D.place((x, y, ztop - hh), D.rot_euler(lean, 0.0, 24.0 * i))
        D.cuke_body(bm2, h=hh, r=rr, nub=(0.17, 0.16), matrix=m)
        D.cuke_studs(bm, h=hh, r=rr, rows=3, per_row=2, z0=0.20, z1=0.82, size=0.16,
                     rise=0.035, seed=60 + i, matrix=m)

    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="Grass")
    D.new_obj("Cukes", bm2, c, D.C("cuke_mid"), rbx_material="SmoothPlastic")

    return c
