"""Samurai: Sakura Tree - pink blossom cubes, each carrying a cut-cucumber medallion."""
import bmesh, math, random

COLLECTION = "SamuraiSakuraTree"
NOTES = (
    "An 11.8-stud CUCUMBER cherry tree on the CucumberTree skeleton: a three-step "
    "sam_bark_dk plinth, a tapering sam_bark blocky trunk speckled with cuke_stud green "
    "squares (two per face on the +y and both side faces of each of its three blocks), "
    "forking into five straight square branches (four spreading out low and wide, one "
    "central leader running up into the head), and a broad flat-topped crown of SEVEN "
    "sam_sakura blossom cubes (size 2.30).  Every blossom cube carries a CUT-CUCUMBER "
    "MEDALLION on its outward face - a cuke_green rim disc r 0.62 / 0.22 thick, half "
    "sunk into the cube so it stands ~0.11 proud, with a cuke_pale cut face and six "
    "cuke_seed pips on it; five stand on the cubes' +y faces (the camera side) and two, "
    "on the cubes whose +y face is buried inside the cluster, lie flat on their tops.  "
    "That slice motif replaces rev 1's sam_sakura_dk speckles entirely - it is what makes "
    "this a cucumber sakura tree rather than a pink cucumber tree.  At the foot sit three "
    "sam_rock boulders and a low ring of seven grass tufts (a squat five-sided pad with "
    "three blades each).  Six tiny sam_sakura petals (0.22 across, 0.05 thick, each on "
    "its own random tilt) hang in the air between z 1.6 and 5.6 around the trunk; they "
    "share the Blossom object because they share its colour and material (the merge "
    "rule), so an installer that wants to animate them must split the six loose squares "
    "out of Blossom first.  Faces +Y, centred on x=0/y=0, nothing below z=0.  Footprint "
    "about 6.8 x 5.6, 11.75 tall.  Nine parts: Base, Trunk, TrunkStuds, Blossom, "
    "SliceRims, SliceFaces, SliceSeeds, Stones, Tufts."
)

# ---- trunk ---------------------------------------------------------------
BASE_TOP_W, BASE_H = 1.50, 1.35
TRUNK_Z0, TRUNK_Z1 = 1.35, 5.70
TRUNK_W0, TRUNK_W1 = 1.34, 0.94
TRUNK_BLOCKS, TRUNK_TWIST = 3, 5.0

# (end x, end y, end z, start z, butt width, tip width) for each fork
BRANCHES = [
    (-2.15, 0.30, 8.30, 5.00, 0.60, 0.40),
    (2.20, -0.25, 8.50, 4.85, 0.62, 0.42),
    (-1.20, -1.70, 8.00, 5.25, 0.56, 0.38),
    (1.30, 1.60, 8.10, 5.25, 0.56, 0.38),
    (0.10, 0.10, 9.30, 5.45, 0.64, 0.44),      # central leader into the head
]

# ---- crown ---------------------------------------------------------------
CROWN_CTR = (0.0, 0.0, 8.85)
CROWN_SIZE = 2.30

# (dx, dy, dz, size multiplier) - the camera sits on +Y, so +y is every cube's front
CROWN = [
    (0.00, 0.05, 1.45, 1.20),    # the head
    (-2.20, 0.25, 0.55, 1.02),   # screen-right limb (+x reads on the LEFT of frame)
    (2.25, -0.20, 0.70, 1.03),   # screen-left limb
    (-1.25, -1.72, 0.15, 0.96),  # back, away from the camera
    (1.35, 1.68, 0.25, 0.98),    # front, nearest the camera
    (-0.85, 0.55, -0.35, 0.90),  # low front filler
    (1.05, -0.95, 0.95, 0.92),   # back-left, tucked under the head
]

# ---- the cut-cucumber medallions ----------------------------------------
# One per blossom cube, sitting on the cube's outward face, half sunk into it.
# (crown index, face, u, v): face "+y" -> u = x offset, v = z offset from the cube
# centre; face "+z" -> u = x offset, v = y offset.  Spots are picked so the disc is
# clear of the neighbouring cubes; the two "+z" ones are the cubes whose front face is
# buried inside the cluster, so their slice lies flat on top instead.
MEDALLIONS = [
    (0, "+y", -0.45, 0.30),
    (1, "+y", -0.35, 0.00),
    (2, "+y", 0.60, 0.50),
    (3, "+z", 0.00, -0.23),
    (4, "+y", 0.00, 0.10),
    (5, "+y", 0.00, 0.10),
    (6, "+z", 0.42, -0.42),
]

MED_R, MED_T, MED_SEGS = 0.62, 0.22, 10

# ---- ground --------------------------------------------------------------
# (x, y, z, radius, x scale, y scale, z squash, seed)
STONES = [
    (1.55, -1.15, 0.40, 0.52, 1.15, 1.00, 0.58, 3),
    (-1.70, -0.95, 0.36, 0.46, 1.10, 1.05, 0.60, 5),
    (-1.15, 1.45, 0.32, 0.40, 1.20, 1.00, 0.62, 8),
]

# (x, y, pad radius) for each grass tuft in the ring round the plinth
TUFTS = [
    (2.05, 0.35, 0.36),
    (1.10, 1.70, 0.32),
    (-0.55, 2.10, 0.34),
    (-2.15, 0.55, 0.38),
    (-2.35, -1.30, 0.30),
    (-0.30, -2.05, 0.35),
    (1.05, -2.10, 0.33),
]

# falling petals: (x, y, z, rx, ry, rz) - flat squares on their own random tilts
PETALS = [
    (-2.30, -1.15, 5.55, 52.0, 8.0, 24.0),
    (1.95, -1.60, 4.65, -38.0, 15.0, 70.0),
    (-1.55, 1.70, 3.85, 65.0, -10.0, -35.0),
    (2.45, 0.95, 3.10, 25.0, 40.0, 110.0),
    (-2.60, 0.35, 2.35, -55.0, 5.0, 15.0),
    (1.45, -2.05, 1.65, 40.0, -25.0, 85.0),
]

PETAL_W, PETAL_T = 0.22, 0.05


def _cube_box(spot):
    """(lo, hi) of one blossom cube - the same maths crown_cluster uses."""
    s = CROWN_SIZE * spot[3]
    cx = CROWN_CTR[0] + spot[0]
    cy = CROWN_CTR[1] + spot[1]
    cz = CROWN_CTR[2] + spot[2]
    return ((cx - s / 2, cy - s / 2, cz - s / 2), (cx + s / 2, cy + s / 2, cz + s / 2))


def _trunk_block(i):
    """(lo, hi, spin) of trunk block `i` - mirrors blocky_trunk's own maths."""
    sh = (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    t = (i + 0.5) / float(TRUNK_BLOCKS)
    w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * t
    z0 = TRUNK_Z0 + i * sh
    return ((-w / 2, -w / 2, z0), (w / 2, w / 2, z0 + sh + 0.014),
            TRUNK_TWIST * (i - (TRUNK_BLOCKS - 1) / 2.0))


def _medallion_matrix(D, idx, face, u, v):
    """The 4x4 that seats one slice medallion on crown cube `idx`."""
    lo, hi = _cube_box(CROWN[idx])
    cx, cy, cz = ((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0, (lo[2] + hi[2]) / 2.0)
    if face == "+y":                        # standing, cut face toward the camera
        return D.slice_stand((cx + u, hi[1], cz + v))
    return D.slice_lay((cx + u, cy + v, hi[2]))     # lying flat on the cube's top


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- dark root plinth --------------------------------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=3, grow=1.30, bevel=0.07)
    D.new_obj("Base", bm, c, D.C("sam_bark_dk"), rbx_material="Wood", roughness=0.72)

    # ---- trunk and the five forks ------------------------------------------
    bm = bmesh.new()
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08, twist=TRUNK_TWIST)
    for (bx, by, bz, z0, w0, w1) in BRANCHES:
        D.branch_box(bm, (0.0, 0.0, z0), (bx, by, bz), w0, w1, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("sam_bark"), rbx_material="Wood", roughness=0.68)

    # ---- green cucumber speckles up the bark -------------------------------
    bm = bmesh.new()
    for i in range(TRUNK_BLOCKS):
        lo, hi, spin = _trunk_block(i)
        D.box_studs(bm, lo, hi, faces=("+y", "+x", "-x"), grid=(1, 2), size=0.30,
                    rise=0.05, seed=21 + i, margin=0.30,
                    matrix=D.rot_euler(0.0, 0.0, spin))
    D.new_obj("TrunkStuds", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic",
              roughness=0.55)

    # ---- pink blossom cubes + the loose petals ------------------------------
    bm = bmesh.new()
    D.crown_cluster(bm, CROWN_CTR, CROWN_SIZE, CROWN, bevel=0.15)
    for (px, py, pz, rx, ry, rz) in PETALS:
        D.beveled_box(bm, (px - PETAL_W / 2, py - PETAL_W / 2, pz - PETAL_T / 2),
                      (px + PETAL_W / 2, py + PETAL_W / 2, pz + PETAL_T / 2),
                      bevel=0.02, rot=D.rot_euler(rx, ry, rz))
    D.new_obj("Blossom", bm, c, D.C("sam_sakura"), rbx_material="Grass", roughness=0.58)

    # ---- a cut-cucumber medallion on every blossom cube --------------------
    mats = [_medallion_matrix(D, idx, face, u, v) for (idx, face, u, v) in MEDALLIONS]

    bm = bmesh.new()
    for m in mats:
        D.slice_disc(bm, radius=MED_R, thick=MED_T, segs=MED_SEGS, bevel=0.035, matrix=m)
    D.new_obj("SliceRims", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic",
              roughness=0.55)

    bm = bmesh.new()
    for m in mats:
        D.slice_face(bm, radius=MED_R, thick=MED_T, segs=MED_SEGS, inset=0.14,
                     proud=0.02, both=False, matrix=m)
    D.new_obj("SliceFaces", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic",
              roughness=0.60)

    bm = bmesh.new()
    for m in mats:
        D.slice_seeds(bm, radius=MED_R, thick=MED_T, n=5, size=0.11, ring=0.44,
                      rise=0.022, bevel=0.0, both=False, centre_seed=True, matrix=m)
    D.new_obj("SliceSeeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic",
              roughness=0.62)

    # ---- three boulders at the foot ----------------------------------------
    bm = bmesh.new()
    for (x, y, z, rr, sx, sy, sz, sd) in STONES:
        D.rock(bm, (x, y, z), rr, seed=sd, jitter=0.20, subdiv=1, scale=(sx, sy, sz))
    D.new_obj("Stones", bm, c, D.C("sam_rock"), rbx_material="Rock", roughness=0.80)

    # ---- a low ring of grass tufts -----------------------------------------
    bm = bmesh.new()
    rng = random.Random(17)
    for i, (x, y, pr) in enumerate(TUFTS):
        D.prism(bm, D.ngon_pts(5, pr, phase=rng.uniform(0.0, 1.2), center=(x, y)),
                0.0, 0.13 + pr * 0.18)
        for _ in range(3):
            ang = rng.uniform(0.0, math.tau)
            out = pr * rng.uniform(0.55, 1.05)
            hgt = rng.uniform(0.42, 0.78)
            # blades start INSIDE the pad, so their tilted base cap never dips under z=0
            D.spike(bm, (x + math.cos(ang) * out * 0.25,
                         y + math.sin(ang) * out * 0.25, 0.11),
                    (x + math.cos(ang) * out, y + math.sin(ang) * out, hgt),
                    0.095, segs=4)
    D.new_obj("Tufts", bm, c, D.C("grass"), rbx_material="LeafyGrass", roughness=0.70)

    return c
