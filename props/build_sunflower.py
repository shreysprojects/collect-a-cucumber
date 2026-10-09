"""Sunflower, three variants side by side: a tall single stem, a medium one carrying an
unopened bud on a side shoot, and a short three-stem clump growing out of a dirt mound.

Every head is a domed seed disc ringed by teardrop petal prisms behind a green sepal
collar, built once by `_head()` and called five times at different scales.  Heads face
+Y and nod 15-24 degrees forward/down, the way a sunflower actually hangs."""
import bmesh, math, random

COLLECTION = "Sunflower"
NOTES = ("Three separable plants in one collection, split by the A_/B_/C_ name prefix; each "
         "is modelled about its own origin then offset along X.  A 'Tall' is 4.6 studs high "
         "on a 2.0-wide footprint, B 'Medium' 3.2 high with a bud on a side shoot, C 'Clump' "
         "is three splayed stems whose heads top out 2.0-2.8 up, spread 3.3 wide over a "
         "2.4 x 2.0 domed dirt mound that already reads as its own "
         "ground patch, so C can be dropped straight onto grass with no base plate.  Nothing "
         "moves; PIVOTS marks each head's neck if an installer wants a sway or a sun-tracking "
         "nod.  Stems are thin (radius 0.08-0.15) - not walkable, not climbable, pure decor.")

VARIANTS = {"A": {"name": "Tall",   "x":  5.0},
            "B": {"name": "Medium", "x":  0.0},
            "C": {"name": "Clump",  "x": -5.4}}

# neck of each head, in collection space - rotate a head about this for a sway/nod rig
PIVOTS = {"A_Neck":  ( 5.00,  0.02, 3.62),
          "B_Neck":  ( 0.00,  0.02, 2.44),
          "C_Neck1": (-4.45, -0.13, 2.10),
          "C_Neck2": (-5.52, -0.68, 1.38),
          "C_Neck3": (-6.52,  0.08, 1.78)}


# ---------------------------------------------------------------- head factory
def _head(D, bms, loc, R, petal_len, petal_w, n_petals, orange_ix, seed,
          disc_segs=8, sepal_segs=6, petal_pts=4, tilt=22.0, yaw=0.0,
          rich_disc=True, thick=0.075):
    """One sunflower head, nodding `tilt` degrees forward/down off +Y.

    Local frame: the seed disc lies in local XY and its face normal is local +Z, which the
    matrix sends onto +Y tipped `tilt` below the horizon.  Geometry is appended into the
    shared bmeshes in `bms` ("disc" / "green" / "yellow" / "orange") so a head adds detail
    without adding objects.  Returns the head matrix."""
    mat = D.place(loc, D.rot_euler(rz=yaw) @ D.rot_euler(rx=-90.0 - tilt))
    rng = random.Random(seed)

    # domed seed disc - proud in the middle, tapering to a thin rim
    if rich_disc:
        prof = [(0.00, 0.26 * R), (0.66 * R, 0.15 * R), (1.00 * R, -0.02 * R), (0.00, -0.17 * R)]
    else:
        prof = [(0.00, 0.22 * R), (1.00 * R, 0.00), (0.00, -0.13 * R)]
    D.lathe(bms["disc"], prof, segs=disc_segs, matrix=mat)

    # sepal collar: a shallow green saucer showing as a ring between disc rim and petals
    D.lathe(bms["green"], [(0.00, -0.70 * R), (1.30 * R, -0.07 * R)],
            segs=sepal_segs, matrix=mat)

    # petal ring - bases tucked under the disc rim, whole ring dished back a little
    base = R * 0.86
    for i in range(n_petals):
        bm = bms["orange"] if i in orange_ix else bms["yellow"]
        h = petal_len * rng.uniform(0.92, 1.07)
        w = petal_w * rng.uniform(0.90, 1.08)
        pts = D.teardrop_pts(w, h, n=petal_pts, center=(0.0, base + h / 2.0))
        m = (mat
             @ D.rot_euler(rz=360.0 * i / n_petals + rng.uniform(-5.0, 5.0))
             @ D.rot_euler(rx=-9.0 + rng.uniform(-5.0, 6.0)))
        D.prism(bm, pts, -thick / 2.0, thick / 2.0, matrix=m)
    return mat


def _leaf(D, bm, at, direction, pitch, roll, w, h, n=4, thick=0.06):
    """A teardrop leaf blade growing out of the stem at `at`.  `direction` is the compass
    heading in degrees (-90 sends the tip to +X, i.e. screen LEFT), `pitch` lifts or droops
    the tip, `roll` cants the blade out of horizontal so it shows area from the front."""
    pts = D.teardrop_pts(w, h, n=n, center=(0.0, h / 2.0))
    m = D.place(at, D.rot_euler(rz=direction) @ D.rot_euler(rx=pitch) @ D.rot_euler(ry=roll))
    D.prism(bm, pts, -thick / 2.0, thick / 2.0, matrix=m)


def _blade(D, bm, at, yaw, lean, w, h, thick=0.05):
    """An upright triangular grass blade standing on the mound."""
    pts = [(-w / 2.0, 0.0), (w / 2.0, 0.0), (0.0, h)]
    m = D.place(at, D.rot_euler(rz=yaw) @ D.rot_euler(rx=90.0 - lean))
    D.prism(bm, pts, -thick / 2.0, thick / 2.0, matrix=m)


def _bms():
    return {"green": bmesh.new(), "leaf": bmesh.new(), "disc": bmesh.new(),
            "yellow": bmesh.new(), "orange": bmesh.new()}


# ---------------------------------------------------------------- build
def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    GREEN, LEAFY = D.C("stem_green"), D.C("leaf_light")
    YEL, ORG = D.C("petal_yellow"), D.C("petal_orange")
    SEED, SOIL = D.C("seed_brown"), D.C("dirt")
    M_STEM, M_LEAF, M_PETAL = "Grass", "LeafyGrass", "Grass"

    def finish(tag, bms):
        D.new_obj(tag + "_Stem" if tag != "C" else "C_Stems", bms["green"], c, GREEN,
                  rbx_material=M_STEM, roughness=0.78)
        D.new_obj(tag + "_Leaves", bms["leaf"], c, LEAFY, rbx_material=M_LEAF, roughness=0.82)
        D.new_obj(tag + "_Disc" if tag != "C" else "C_Discs", bms["disc"], c, SEED,
                  rbx_material="Pebble", roughness=0.88)
        D.new_obj(tag + "_PetalsYellow", bms["yellow"], c, YEL, rbx_material=M_PETAL, roughness=0.62)
        D.new_obj(tag + "_PetalsOrange", bms["orange"], c, ORG, rbx_material=M_PETAL, roughness=0.62)

    # ======================================================== A - Tall, ~4.6 studs
    ox = VARIANTS["A"]["x"]
    bms = _bms()

    # one stem: dead vertical off the ground so the base ring sits flat on z=0, then bent
    D.tube(bms["green"],
           [(ox + 0.00,  0.00, 0.00), (ox + 0.00,  0.00, 0.95),
            (ox + 0.07, -0.13, 2.35), (ox - 0.02, -0.02, 3.62)],
           [0.145, 0.128, 0.112, 0.092], segs=5)

    _head(D, bms, (ox + 0.00, 0.10, 3.80), R=0.36, petal_len=0.50, petal_w=0.30,
          n_petals=12, orange_ix={1, 6, 9}, seed=11,
          disc_segs=9, sepal_segs=7, petal_pts=4, tilt=22.0, yaw=-4.0)

    # three leaves, deliberately uneven: one big low one on the left, two on the right
    _leaf(D, bms["leaf"], (ox + 0.03, -0.06, 1.16),  -96.0, -10.0,  66.0, 0.50, 1.04)
    _leaf(D, bms["leaf"], (ox + 0.05, -0.12, 2.18),   84.0,  15.0, -60.0, 0.44, 0.88)
    _leaf(D, bms["leaf"], (ox + 0.01, -0.05, 2.95),  122.0,  -2.0,  54.0, 0.30, 0.58, n=3)

    finish("A", bms)

    # ======================================================== B - Medium, ~3.2 studs
    ox = VARIANTS["B"]["x"]
    bms = _bms()

    D.tube(bms["green"],
           [(ox + 0.00,  0.00, 0.00), (ox + 0.00,  0.00, 0.72),
            (ox - 0.07, -0.11, 1.66), (ox + 0.02, -0.03, 2.44)],
           [0.132, 0.120, 0.104, 0.086], segs=5)

    # side shoot to +X (screen LEFT) carrying an unopened bud.  The shoot reaches well
    # clear of the main head's petal ring (0.68 reach vs a 0.96 gap) or the bud reads as
    # a tin can wedged under the flower; the profile tapers to a nose for the same reason.
    D.tube(bms["green"],
           [(ox - 0.05, -0.09, 1.46), (ox + 0.34, -0.06, 1.70), (ox + 0.74, -0.02, 1.92)],
           [0.075, 0.064, 0.054], segs=4)
    budrot = D.rot_euler(rx=-14.0, ry=22.0)
    D.lathe(bms["green"], [(0.000, 0.00), (0.150, 0.09), (0.130, 0.26),
                           (0.062, 0.36), (0.000, 0.44)],
            segs=6, matrix=D.place((ox + 0.74, -0.02, 1.92), budrot))
    # a pinch of yellow already showing at the bud's nose
    D.lathe(bms["yellow"], [(0.070, 0.00), (0.000, 0.14)], segs=5,
            matrix=D.place((ox + 0.886, 0.077, 2.28), budrot))

    _head(D, bms, (ox + 0.00, 0.09, 2.60), R=0.30, petal_len=0.42, petal_w=0.27,
          n_petals=10, orange_ix={3, 8}, seed=23,
          disc_segs=8, sepal_segs=6, petal_pts=4, tilt=24.0, yaw=6.0)

    _leaf(D, bms["leaf"], (ox + 0.02, -0.06, 0.78),   88.0,  -8.0, -62.0, 0.44, 0.86)
    _leaf(D, bms["leaf"], (ox - 0.05, -0.10, 1.72), -100.0,  12.0,  58.0, 0.36, 0.70)

    finish("B", bms)

    # ======================================================== C - Clump, 2.0-2.8 studs
    ox = VARIANTS["C"]["x"]
    bms = _bms()

    # soil dome: a closed lathe whose first ring IS the ground ring, so it cannot float.
    # Squashed in Y and jittered above the ground ring so it heaps like earth, not a board.
    bm = bmesh.new()
    mound = D.lathe(bm, [(1.15, 0.00), (0.94, 0.22), (0.56, 0.40), (0.00, 0.52)],
                    segs=7, matrix=D.place((ox, 0.0, 0.0), scale=(1.0, 0.85, 1.0)))
    mrng = random.Random(5)
    for v in mound:
        if v.co.z > 0.06:                      # never touch the ring sitting on z = 0
            v.co.x += mrng.uniform(-0.07, 0.07)
            v.co.y += mrng.uniform(-0.06, 0.06)
            v.co.z += mrng.uniform(-0.04, 0.05)
    D.new_obj("C_Mound", bm, c, SOIL, rbx_material="Ground", roughness=0.95)

    # every stem starts on the ground, not on the mound's skin, so no cut end can ever
    # surface in mid-air; the first segment is dead vertical so the base ring lies on z=0.
    # Tops are splayed wide apart - the three petal rings must not reach each other.
    stems = ([(ox + 0.46,  0.10, 0.00), (ox + 0.46,  0.10, 0.42),
              (ox + 0.64,  0.00, 1.26), (ox + 0.95, -0.13, 2.10)],
             [(ox - 0.18, -0.34, 0.00), (ox - 0.18, -0.34, 0.44),
              (ox - 0.15, -0.50, 0.94), (ox - 0.12, -0.68, 1.38)],
             [(ox - 0.60,  0.20, 0.00), (ox - 0.60,  0.20, 0.40),
              (ox - 0.86,  0.15, 1.10), (ox - 1.12,  0.08, 1.78)])
    radii = ([0.105, 0.105, 0.094, 0.080],
             [0.098, 0.098, 0.088, 0.076],
             [0.100, 0.100, 0.090, 0.078])
    for pts, rr in zip(stems, radii):
        D.tube(bms["green"], pts, rr, segs=5)

    # three heads, one over each stem top: sizes, heights and nods differ, but every
    # centre-to-centre gap (1.32-2.10) beats the two petal reaches it has to clear.
    _head(D, bms, (ox + 0.95, -0.05, 2.22), R=0.30, petal_len=0.40, petal_w=0.24,
          n_petals=7, orange_ix={2}, seed=31,
          disc_segs=6, sepal_segs=5, petal_pts=3, tilt=20.0, yaw=-16.0, rich_disc=False)
    # the middle one is the smallest, so it needs the closed petal ring and the domed
    # disc to still read as a flower rather than a brown starburst
    _head(D, bms, (ox - 0.12, -0.60, 1.50), R=0.27, petal_len=0.34, petal_w=0.21,
          n_petals=9, orange_ix={4}, seed=37,
          disc_segs=7, sepal_segs=5, petal_pts=3, tilt=16.0, yaw=0.0)
    _head(D, bms, (ox - 1.12,  0.16, 1.90), R=0.26, petal_len=0.36, petal_w=0.22,
          n_petals=6, orange_ix={1, 4}, seed=41,
          disc_segs=6, sepal_segs=5, petal_pts=3, tilt=15.0, yaw=5.0, rich_disc=False)

    _leaf(D, bms["leaf"], (ox + 0.61, -0.02, 1.10),  -88.0, -6.0,  62.0, 0.30, 0.62, n=3)
    _leaf(D, bms["leaf"], (ox - 0.88,  0.11, 1.16),  100.0,  8.0, -56.0, 0.26, 0.54, n=3)

    # grass tufts rooted on the ground at the foot of the mound, never on its slope
    _blade(D, bms["leaf"], (ox + 1.00,  0.36, 0.02),   24.0, 14.0, 0.15, 0.46)
    _blade(D, bms["leaf"], (ox - 0.58,  0.78, 0.02), -140.0, 10.0, 0.13, 0.40)
    _blade(D, bms["leaf"], (ox + 0.14, -0.92, 0.02),  165.0, 18.0, 0.12, 0.36)

    finish("C", bms)

    return c
