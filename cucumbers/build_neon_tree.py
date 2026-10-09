"""Neon: Neon Tree - dark blocky trunk with two neon bands under a crown of glowing cubes."""
import bmesh, math, random

COLLECTION = "NeonTree"
NOTES = ("An 11.45-stud neon tree built on the CucumberTree recipe.  A flat dark square "
         "plinth 2.6 x 2.6 x 0.22 (neo_night, Metal - the set's pedestal material) with a "
         "thin glowing purple frame (0.06 wide, z 0.17-0.26, 0.02 proud of the sides) "
         "wrapped round its top edge.  On it a dark-indigo blocky trunk (neo_trunk, "
         "SmoothPlastic): a flared square foot (1.36 -> 1.00 across, z 0.15-0.95, its "
         "bottom buried in the plinth), then three stacked blocks tapering 1.05 -> 0.85 "
         "from z 0.22 to z 6.0, with a magenta Neon band at z 2.4 and a cyan Neon band at "
         "z 3.9 (0.14 tall, 0.04 proud, both on the middle block, clear of its seams).  "
         "Two short square arms (0.42 -> 0.30 thick, about 1 stud of each showing) leave "
         "the trunk above the cyan band - the +X one (screen-LEFT) at z ~4.6, the -X one "
         "(screen-right) at z ~5.1 - and run up-outward: the +X one dies inside the lower "
         "magenta cube, the -X one inside the lower-right green cube.  The trunk top is "
         "buried in the lower-centre and lower-right green cubes.  The crown is TWELVE "
         "cubes (1.5-2.1 on a side, "
         "bevel 0.09, every one overlapping a neighbour, none floating) between z 5.2 and "
         "z 11.45, x -3.42 .. +3.18 (6.6 wide) and y -2.45 .. +2.25, transcribed from the "
         "tile with +X on the tile's LEFT: a big cyan cube crowns the top, cyan cubes cap "
         "both outer sides (+X mid, -X mid-low) and the upper back at -X; a big magenta "
         "cube stands proud at the front centre (slightly -X) and a second hangs lowest "
         "at the front +X side; five solid green cubes fill the core (upper-left back, "
         "right-upper, centre-back, lower-centre, lower-right).  Cyan and Magenta are Neon "
         "at emit 0.55 and also hold the trunk band of their colour.  Only the green cubes "
         "carry the set's speckles (43 of them, neo_green_dk, a jittered 2 x 2 lattice on "
         "every side and top face, plus a centre one on faces that neighbours mostly "
         "cover); any speckle that would be buried in or poke through a neighbouring "
         "cube is culled, so none clip.  The glowing cubes and bands are plain.  About "
         "2860 tris.  DEVIATIONS: (1) the tile shows only TWO "
         "magenta cubes; the brief asks for three, so the third sits at the BACK (-Y) of "
         "the cluster where the tile's front view cannot see it - it gives the back view "
         "some glow when the game spins the tree.  (2) The tile shows five green cubes, "
         "not four, so there are five (12 cubes, not ~11).  (3) The tile's tree is "
         "stubbier than the set allows (its crown would be ~8.5 wide at 11.5 tall); the "
         "crown is held to the brief's <= 7 wide and 11-12 tall, so the trunk below the "
         "crown reads a little longer than in the tile.  (4) The flared trunk foot comes "
         "from the tile, not the brief.  (5) The trunk stays plain, as in the tile.  "
         "(6) The crown spans z 5.2-11.45 rather than the brief's 5.5-11.2: the low "
         "magenta cube hangs lowest, as in the tile, and the top cube is 2.1 on a side.  "
         "Footprint 6.6 x 4.7 x 11.45, lowest point z = 0 (the plinth), faces +Y.  Seven "
         "parts: Base, BaseGlow, Trunk, Cyan, Magenta, CubesGreen, CubeStuds.  The arms "
         "and trunk foot are placed with matrices, so dryrun's bounding box is local-space "
         "for them; nothing real sits below z = 0.")

# ---- plinth ----------------------------------------------------------------
BASE_W, BASE_H = 2.60, 0.22
GLOW_W, GLOW_Z0, GLOW_Z1, GLOW_OUT = 0.06, 0.17, 0.26, 0.02   # frame: width, z range, overhang

# ---- trunk -----------------------------------------------------------------
TRUNK_Z0, TRUNK_Z1 = BASE_H, 6.00
TRUNK_W0, TRUNK_W1, TRUNK_BLOCKS = 1.10, 0.80, 3
# flared foot: a, b, w0, w1 - starts 0.07 inside the plinth so its bottom chamfer is buried
FOOT = ((0.0, 0.0, 0.15), (0.0, 0.0, 0.95), 1.36, 1.00)
# (part, z centre) - both land on the middle trunk block, clear of its seams
BANDS = [("Magenta", 2.40), ("Cyan", 3.90)]
BAND_H, BAND_PROUD = 0.14, 0.04
# (start inside the trunk, end inside a crown cube)
ARMS = [
    ((0.05, 0.05, 4.35), (1.75, 0.60, 5.65)),       # +X (screen-left) -> magenta low cube
    ((-0.05, 0.05, 4.55), (-1.35, 0.35, 6.30)),     # -X (screen-right) -> green low cube
]
ARM_W0, ARM_W1 = 0.42, 0.30

# ---- crown -----------------------------------------------------------------
# (part, x, y, z, size).  +X is the tile's LEFT.  Front = +Y.
CUBES = [
    ("Cyan", -0.10, 0.05, 10.40, 2.10),         # crowns the top
    ("Cyan", -1.80, -1.15, 9.85, 1.50),         # small, upper right, set back
    ("Cyan", 2.30, 0.45, 7.95, 1.75),           # outer left, mid height
    ("Cyan", -2.52, 0.35, 7.20, 1.80),          # outer right, mid-low
    ("Magenta", -0.60, 1.20, 8.40, 2.10),       # big one, proud at the front centre
    ("Magenta", 1.90, 0.90, 6.12, 1.85),        # hangs lowest, front left
    ("Magenta", 0.25, -1.55, 7.60, 1.80),       # the back one (not visible in the tile)
    ("CubesGreen", 1.62, -1.05, 9.40, 1.60),    # upper left, behind the top cube
    ("CubesGreen", -2.12, -0.25, 8.85, 1.65),   # right, upper
    ("CubesGreen", 1.05, -0.30, 8.45, 1.70),    # centre, behind the magenta
    ("CubesGreen", 0.50, 0.30, 6.85, 1.95),     # lower centre, sits on the trunk top
    ("CubesGreen", -1.05, 0.20, 6.70, 1.60),    # lower right
]
CUBE_BEVEL = 0.09

# ---- speckles (green cubes only) -----------------------------------------------
STUD_SIZE, STUD_RISE, STUD_BEVEL = 0.34, 0.06, 0.03
STUD_FACES = ("+x", "-x", "+y", "-y", "+z")
STUD_EDGE = CUBE_BEVEL + 0.09        # clear distance kept between a stud and a cube edge
STUD_GAP = 0.05                      # a stud this close to another cube is culled
_AXES = {"+x": (0, 1.0), "-x": (0, -1.0), "+y": (1, 1.0), "-y": (1, -1.0), "+z": (2, 1.0)}

EMIT = 0.55


# ================================================================ pure helpers
def cube_box(cube):
    """(lo, hi) of one crown cube."""
    _, x, y, z, s = cube
    h = s / 2.0
    return (x - h, y - h, z - h), (x + h, y + h, z + h)


def trunk_blocks():
    """(lo, hi, width) of each trunk block, exactly as D.blocky_trunk lays them out."""
    sh = (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    out = []
    for i in range(TRUNK_BLOCKS):
        w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * ((i + 0.5) / float(TRUNK_BLOCKS))
        out.append(((-w / 2, -w / 2, TRUNK_Z0 + i * sh),
                    (w / 2, w / 2, TRUNK_Z0 + (i + 1) * sh + 0.014), w))
    return out


def band_box(zc):
    """(lo, hi) of the square neon band hugging the trunk block at height zc."""
    for lo, hi, w in trunk_blocks():
        if lo[2] <= zc <= hi[2]:
            h = w / 2.0 + BAND_PROUD
            return (-h, -h, zc - BAND_H / 2.0), (h, h, zc + BAND_H / 2.0)
    raise ValueError("band at z %.2f is off the trunk" % zc)


def glow_bars():
    """The four bars of the plinth's glowing frame, abutting at the corners."""
    o = BASE_W / 2.0 + GLOW_OUT
    i = o - GLOW_W
    z0, z1 = GLOW_Z0, GLOW_Z1
    return [((-o, i, z0), (o, o, z1)), ((-o, -o, z0), (o, -i, z1)),
            ((i, -i, z0), (o, i, z1)), ((-o, -i, z0), (-i, i, z1))]


def _overlap(alo, ahi, blo, bhi, pad=0.0):
    return all(alo[k] < bhi[k] + pad and blo[k] - pad < ahi[k] for k in range(3))


def stud_spots():
    """(point, normal) for every speckle on the green cubes: a lightly jittered 2 x 2
    lattice on each side and top face, minus any stud that would sit inside, or poke
    through, a neighbouring cube or the trunk.  A face left with fewer than two (it is
    mostly covered by neighbours) also tries one speckle at its centre."""
    boxes = [cube_box(cu) for cu in CUBES]
    blockers = boxes + [(lo, hi) for lo, hi, _ in trunk_blocks()]
    out = []
    for ci, cube in enumerate(CUBES):
        if cube[0] != "CubesGreen":
            continue
        rng = random.Random(20 + ci)
        lo, hi = boxes[ci]
        ctr = [(lo[k] + hi[k]) / 2.0 for k in range(3)]
        ext = (hi[0] - lo[0]) / 2.0
        d = ext - STUD_EDGE - STUD_SIZE / 2.0
        for f in STUD_FACES:
            ax, sgn = _AXES[f]
            tang = [k for k in range(3) if k != ax]

            def try_spot(u, v):
                p = list(ctr)
                p[ax] = ctr[ax] + sgn * ext
                p[tang[0]] += u * d + rng.uniform(-0.12, 0.12) * d
                p[tang[1]] += v * d + rng.uniform(-0.12, 0.12) * d
                slo, shi = list(p), list(p)
                for k in tang:
                    slo[k] -= STUD_SIZE / 2.0
                    shi[k] += STUD_SIZE / 2.0
                if sgn > 0:
                    shi[ax] += STUD_RISE
                else:
                    slo[ax] -= STUD_RISE
                if any(_overlap(slo, shi, blo, bhi, STUD_GAP)
                       for j, (blo, bhi) in enumerate(blockers) if j != ci):
                    return False
                n = [0.0, 0.0, 0.0]
                n[ax] = sgn
                out.append((tuple(p), tuple(n)))
                return True

            kept = sum(1 for v in (-1.0, 1.0) for u in (-1.0, 1.0) if try_spot(u, v))
            if kept < 2:
                try_spot(0.0, 0.0)
    return out


# ================================================================ build
def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- the flat dark plinth + its glowing purple frame ----------------------
    h = BASE_W / 2.0
    bm = bmesh.new()
    D.beveled_box(bm, (-h, -h, 0.0), (h, h, BASE_H), bevel=0.05)
    D.new_obj("Base", bm, c, D.C("neo_night"), rbx_material="Metal")

    bm = bmesh.new()
    for lo, hi in glow_bars():
        D.box(bm, lo, hi)
    D.new_obj("BaseGlow", bm, c, D.C("neo_purple"), rbx_material="Neon", emit=0.6)

    # ---- trunk: flared foot, three tapering blocks, two arms ------------------
    bm = bmesh.new()
    fa, fb, fw0, fw1 = FOOT
    D.branch_box(bm, fa, fb, fw0, fw1, bevel=0.05)
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.07)
    for a, b in ARMS:
        D.branch_box(bm, a, b, ARM_W0, ARM_W1, bevel=0.04)
    D.new_obj("Trunk", bm, c, D.C("neo_trunk"), rbx_material="SmoothPlastic")

    # ---- crown cubes, one bmesh per part --------------------------------------
    parts = {"Cyan": bmesh.new(), "Magenta": bmesh.new(), "CubesGreen": bmesh.new()}
    for part, zc in BANDS:
        lo, hi = band_box(zc)
        D.beveled_box(parts[part], lo, hi, bevel=0.03)
    for cube in CUBES:
        part, x, y, z, s = cube
        D.crown_cube(parts[part], (x, y, z), s, bevel=CUBE_BEVEL)
    D.new_obj("Cyan", parts["Cyan"], c, D.C("neo_cyan"), rbx_material="Neon", emit=EMIT)
    D.new_obj("Magenta", parts["Magenta"], c, D.C("neo_magenta"), rbx_material="Neon",
              emit=EMIT)
    D.new_obj("CubesGreen", parts["CubesGreen"], c, D.C("neo_green"),
              rbx_material="SmoothPlastic")

    # ---- the set's speckles, on the green cubes only --------------------------
    bm = bmesh.new()
    for p, n in stud_spots():
        D.stud_patch(bm, p, n, size=STUD_SIZE, rise=STUD_RISE, bevel=STUD_BEVEL)
    D.new_obj("CubeStuds", bm, c, D.C("neo_green_dk"), rbx_material="SmoothPlastic")

    return c
