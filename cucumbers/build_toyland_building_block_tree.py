"""Toyland: Building Block Tree - a toy-brick tree: stacked brown trunk bricks, a stepped
crown of green bricks with chunky round studs on every exposed top face."""
import bmesh, math

COLLECTION = "ToylandBuildingBlockTree"
NOTES = ("A tree built from toy bricks, transcribed from the reference tile.  Faces +Y, "
         "centred on the trunk at x=0/y=0, lowest point exactly z=0, nothing below it.  "
         "Footprint ~6.9 x 3.4, 8.8 tall (stud tops at z 8.76).  "
         "TRUNK: four stacked brown bricks (bevel 0.08) - a wider foot brick 1.80 across "
         "(z 0-1.25), then 1.64 (z 1.25-2.32), 1.58 (z 2.32-3.38) and 1.52 (z 3.38-5.0, "
         "running up into the crown and seen only through the crown's front notch).  A "
         "thin dark-brown band sits in the bevel groove at each joint (z 1.25 / 2.32 / "
         "3.38) so the brick seams read as the tile's dark lines.  "
         "CROWN (all one toy green, bevel 0.08), bottom at z 3.38: layer 1 (z 3.38-4.76) "
         "and layer 2 (z 4.76-6.16) are both the full 6.9 x 3.4, split into staggered "
         "front and back rows of bricks.  As in the tile, layer 1 has a 0.76-wide NOTCH "
         "in the front centre where the brown trunk shows through, and layer 2's middle "
         "front brick (x -1.0..1.55) is RECESSED to y 0.84 (the flanking bricks come "
         "forward to y 1.70).  On top sits a narrower two-tier block 3.44 wide x 2.6 deep, "
         "offset toward -X (the tile's RIGHT, the +X trap) and a little back: a thin "
         "layer 3 of three bricks (z 6.16-6.98) under one big top brick (z 6.98-8.32).  "
         "STUDS: 8 chunky round studs (r 0.48, 0.44 tall, chamfered top, 12 segs, sized "
         "from the tile: ~0.28 of the top brick's width): 2 x 2 "
         "on the top brick and a front/back pair on each exposed shoulder of layer 2 "
         "(x +2.30 and x -2.75).  They stand in for the set's square speckle.  "
         "Four parts: Trunk (toy_brown), TrunkSeams (toy_brown_dk), Crown (toy_green), "
         "CrownStuds (nar_alien_grn), all SmoothPlastic.  ~1.4k tris.  "
         "DEVIATIONS from the brief (the tile wins): (1) proportions follow the tile, not "
         "the brief's 6.4 x 3.4 x 10.2 with a 1.25-wide trunk to z 5: the tile's trunk is "
         "about a quarter of the crown's width and only ~39% of the height, and its crown "
         "is ~0.8 of the height wide.  Holding the crown at the contract's <= 7 wide, the "
         "tree is 8.8 tall, below the set's usual 11-13.  In the game this changes nothing: "
         "install_game.lua scales every tree so its dominant axis (height here) is 8.6 in "
         "the field, so only the proportions reach the player, and the authored 8.8 is "
         "already about its in-field size.  (2) The top brick is as wide as layer 3 (3.4 x "
         "2.5), as in the tile, not the brief's 2.4 x 2.0.  (3) 8 big studs (r 0.48 x 0.44) "
         "where the tile shows them, not <= 26 small r 0.30 x 0.20 ones on a 1.0 grid (the "
         "tile's studs are chunky and "
         "sparse; every exposed top that can hold one has one).  (4) Stud colour is "
         "nar_alien_grn, not plastic_green: plastic_green has exactly the same luminance "
         "as toy_green (0.328), so it would not read as the lighter step the brief asks "
         "for; nar_alien_grn is the same hue one clear step lighter.  (5) No CrownDark "
         "part: the tile's crown is a single green.  (6) Crown depth kept at the brief's "
         "3.4 (the tile hints ~2.6) because the game spins the model to a random yaw.")

BEVEL = 0.08

# ---- trunk: (z0, z1, width) - stacked bricks, all centred on x = y = 0 --------------
TRUNK = [
    (0.00, 1.25, 1.80),     # the wider foot brick, as in the tile
    (1.25, 2.32, 1.64),
    (2.32, 3.38, 1.58),
    (3.38, 5.00, 1.52),     # inside the crown; its top is buried in layer 2
]
SEAM_H = 0.10               # dark band filling the bevel groove at each trunk joint
SEAM_INSET = 0.03           # band half-width = the narrower neighbour's half-width - this

# ---- crown bricks: (x0, x1, y0, y1, z0, z1).  +X renders on the LEFT of the tile. ---
Z_L1, Z_L2, Z_L3, Z_TOP, Z_END = 3.38, 4.76, 6.16, 6.98, 8.32
CROWN = [
    # layer 1 - full width.  Front row leaves a notch at |x| < 0.38 where the trunk
    # shows; back row is split at x 1.00 / -1.20 (staggered against layer 2).
    (0.38, 3.45, 0.40, 1.70, Z_L1, Z_L2),         # front, screen-left
    (-3.45, -0.38, 0.40, 1.70, Z_L1, Z_L2),       # front, screen-right
    (1.00, 3.42, -1.70, 0.40, Z_L1, Z_L2),        # back row
    (-1.20, 1.00, -1.70, 0.40, Z_L1, Z_L2),
    (-3.43, -1.20, -1.70, 0.40, Z_L1, Z_L2),
    # layer 2 - full width.  The middle front brick is recessed (front at y 0.84) so
    # the flanking bricks stand proud of it, as in the tile.  Back row split at x 0.25.
    (1.55, 3.47, 0.00, 1.70, Z_L2, Z_L3),         # front, screen-left
    (-1.00, 1.55, 0.00, 0.84, Z_L2, Z_L3),        # front middle, recessed
    (-3.44, -1.00, 0.00, 1.72, Z_L2, Z_L3),       # front, screen-right
    (0.25, 3.44, -1.72, 0.00, Z_L2, Z_L3),        # back row
    (-3.46, 0.25, -1.70, 0.00, Z_L2, Z_L3),
    # layer 3 - the thin lower tier of the upper block, three bricks, offset to -X
    (0.45, 1.34, -1.40, 1.20, Z_L3, Z_TOP),
    (-0.87, 0.45, -1.38, 1.23, Z_L3, Z_TOP),
    (-2.10, -0.87, -1.40, 1.20, Z_L3, Z_TOP),
    # the big top brick, inset a hair so its seam with layer 3 reads
    (-2.07, 1.31, -1.37, 1.17, Z_TOP, Z_END),
]

# ---- round studs: (x, y, z of the brick top they stand on) -------------------------
# tile: each top stud is ~0.28 of the top brick's width and ~1/3 of its height
STUD_R, STUD_H, STUD_CHAMFER, STUD_SINK, STUD_SEGS = 0.48, 0.44, 0.06, 0.03, 12
STUDS = [
    (0.28, 0.50, Z_END), (-1.04, 0.50, Z_END),     # 2 x 2 on the top brick
    (0.28, -0.70, Z_END), (-1.04, -0.70, Z_END),
    (2.30, 0.65, Z_L3), (2.30, -0.65, Z_L3),       # layer-2 shoulder, screen-left
    (-2.75, 0.65, Z_L3), (-2.75, -0.65, Z_L3),     # layer-2 shoulder, screen-right
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- trunk bricks -------------------------------------------------------------
    bm = bmesh.new()
    for (z0, z1, w) in TRUNK:
        h = w / 2.0
        D.beveled_box(bm, (-h, -h, z0), (h, h, z1), bevel=BEVEL)
    D.new_obj("Trunk", bm, c, D.C("toy_brown"), rbx_material="SmoothPlastic")

    # ---- dark seam bands tucked into the bevel groove at each joint ---------------
    bm = bmesh.new()
    for i in range(len(TRUNK) - 1):
        zj = TRUNK[i][1]
        h = min(TRUNK[i][2], TRUNK[i + 1][2]) / 2.0 - SEAM_INSET
        D.box(bm, (-h, -h, zj - SEAM_H / 2.0), (h, h, zj + SEAM_H / 2.0))
    D.new_obj("TrunkSeams", bm, c, D.C("toy_brown_dk"), rbx_material="SmoothPlastic")

    # ---- crown bricks -------------------------------------------------------------
    bm = bmesh.new()
    for (x0, x1, y0, y1, z0, z1) in CROWN:
        D.beveled_box(bm, (x0, y0, z0), (x1, y1, z1), bevel=BEVEL)
    D.new_obj("Crown", bm, c, D.C("toy_green"), rbx_material="SmoothPlastic")

    # ---- chunky round studs, sunk a hair into the brick top, chamfered rim ----------
    bm = bmesh.new()
    for (x, y, zt) in STUDS:
        prof = [(STUD_R, zt - STUD_SINK),
                (STUD_R, zt + STUD_H - STUD_CHAMFER),
                (STUD_R - STUD_CHAMFER, zt + STUD_H)]
        D.lathe(bm, prof, segs=STUD_SEGS, matrix=D.place((x, y, 0.0)), cap=True)
    # toy_green's own lighter step (plastic_green has the SAME luminance as toy_green)
    D.new_obj("CrownStuds", bm, c, D.C("nar_alien_grn"), rbx_material="SmoothPlastic")

    return c
