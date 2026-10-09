"""Desert: Sandstone Tree - the CucumberTree silhouette carved out of desert rock."""
import bmesh, math

COLLECTION = "DesertSandstoneTree"
NOTES = ("An 11.5-stud tree cut from sandstone: a wide three-step plinth in des_stone_dk, "
         "a column of four stacked sandstone blocks in des_stone banded by three proud "
         "ledge courses up to a capital at z 6.3, four brown branch beams forking out of "
         "it, and a crown of five chunky sandstone cubes.  Every speckle is des_trunk_dk "
         "- the branch brown - because des_stone_dk is too close in value to des_stone to "
         "read: chunky 0.50 squares on a 2x2 grid over the crown cubes plus smaller 0.34 "
         "ones on the four clear bands of column between the ledges, both dark enough to "
         "show from 40 studs.  No hanging fruit.  Footprint 6.5 x 5.5, base plinth 2.9 "
         "square, crown top at z 11.5.  Faces +Y, centred on x=0/y=0, nothing below z=0.  "
         "Five parts: Base, Trunk, Branches, Crown, Studs.  Crown and Studs carry "
         "\"Rock\" (the weathered boulder crown), the plinth and column \"Sandstone\" "
         "(the cut masonry) and the branches \"Wood\" - so every object's colour+material "
         "pair stays unique even though Studs and Branches share des_trunk_dk.")

# --- the column --------------------------------------------------------------
BASE_H = 1.90                 # top of the stepped plinth
TRUNK_TOP = 6.20              # top of the stacked blocks (the capital caps it at 6.34)

# proud ledge courses banding the column: (z0, z1, width)
LEDGES = [
    (2.86, 3.14, 1.62),
    (4.30, 4.56, 1.42),
    (6.04, 6.34, 1.30),       # the capital the branches spring from
]

# speckle bands on the column: (z0, z1, half width) - the clear stone BETWEEN the ledges,
# so no stud ends up buried inside a proud ledge course
TRUNK_STUDS = [
    (1.98, 2.80, 0.73),
    (3.22, 4.02, 0.67),
    (4.64, 5.10, 0.61),
    (5.22, 6.00, 0.56),
]

# --- the forks ---------------------------------------------------------------
# (end x, end y, end z, start z) - tips finish INSIDE their crown cube
BRANCHES = [
    (-1.95, 0.28, 8.35, 5.10),
    (1.98, -0.22, 8.55, 4.85),
    (-0.88, -1.60, 8.05, 5.50),
    (0.98, 1.48, 8.15, 5.50),
]

# --- the crown ---------------------------------------------------------------
CROWN_CTR = (0.0, 0.0, 8.73)
CROWN_SIZE = 2.45
# (dx, dy, dz, size multiplier) around the crown centre
CROWN = [
    (0.05, 0.00, 1.35, 1.16),     # the crest block
    (-2.00, 0.30, 0.40, 1.00),
    (2.00, -0.25, 0.60, 1.02),
    (-0.90, -1.72, 0.10, 0.90),
    (1.00, 1.58, 0.25, 0.92),
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- stepped plinth ----------------------------------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=1.6, h=BASE_H, steps=3, grow=1.34, bevel=0.07)
    D.new_obj("Base", bm, c, D.C("des_stone_dk"), rbx_material="Sandstone")

    # ---- stacked sandstone column ------------------------------------------
    bm = bmesh.new()
    D.blocky_trunk(bm, BASE_H, TRUNK_TOP, 1.52, 1.06, blocks=4, bevel=0.07)
    for (z0, z1, w) in LEDGES:
        D.beveled_box(bm, (-w / 2, -w / 2, z0), (w / 2, w / 2, z1), bevel=0.06)
    D.new_obj("Trunk", bm, c, D.C("des_stone"), rbx_material="Sandstone")

    # ---- branches ----------------------------------------------------------
    bm = bmesh.new()
    for (bx, by, bz, z0) in BRANCHES:
        D.branch_box(bm, (0.0, 0.0, z0), (bx, by, bz), 0.62, 0.42, bevel=0.05)
    D.new_obj("Branches", bm, c, D.C("des_trunk_dk"), rbx_material="Wood")

    # ---- crown -------------------------------------------------------------
    bm = bmesh.new()
    D.crown_cluster(bm, CROWN_CTR, CROWN_SIZE, CROWN, bevel=0.13)
    D.new_obj("Crown", bm, c, D.C("des_stone"), rbx_material="Rock")

    cx, cy, cz = CROWN_CTR
    bm = bmesh.new()
    for i, (dx, dy, dz, k) in enumerate(CROWN):
        s = CROWN_SIZE * k
        lo = (cx + dx - s / 2, cy + dy - s / 2, cz + dz - s / 2)
        hi = (cx + dx + s / 2, cy + dy + s / 2, cz + dz + s / 2)
        D.box_studs(bm, lo, hi, faces=("-y", "+x", "-x"), grid=(2, 2), size=0.50,
                    rise=0.08, seed=20 + i, margin=0.34)
        if dz >= 0.30:                       # only the cubes whose top face reads
            D.box_studs(bm, lo, hi, faces=("+z",), grid=(2, 2), size=0.50,
                        rise=0.08, seed=40 + i, margin=0.34)
    for i, (z0, z1, hw) in enumerate(TRUNK_STUDS):
        D.box_studs(bm, (-hw, -hw, z0), (hw, hw, z1), faces=("-y", "+x", "-x"),
                    grid=(2, 1), size=0.34, rise=0.06, seed=60 + i, margin=0.42)
    D.new_obj("Studs", bm, c, D.C("des_trunk_dk"), rbx_material="Rock")

    return c
