"""Samurai: Bamboo Grove - four banded bamboo stalks, leaves, stones and shoots."""
import bmesh, math, random

COLLECTION = "SamuraiBambooGrove"
NOTES = ("A 9.2-stud clump of bamboo: four tapering 8-sided stalks (9.2 / 7.6 / 6.4 / 5.0 "
         "tall) rising from a tight 1.2 x 0.95 footprint, each leaning 2.5-3.7 degrees in a "
         "different direction.  Tan node bands ring every stalk each 1.3 studs; eight leaf "
         "blades sprout from the nodes in the upper thirds, three grey stones sit round the "
         "base and five dark shoots poke up between them.  Footprint about 3.3 x 2.5, "
         "centred on x=0,y=0, facing +Y, nothing below z=0.  Six parts: Stalks, Bands, "
         "Studs, Leaves, Stones, Shoots.")

# ---- stalks: (base x, base y, height, top dx, top dy, base r, top r, first band s)
STALKS = [
    (-0.16,  0.26, 9.20,  0.34, -0.20, 0.250, 0.195, 0.70),
    ( 0.58, -0.34, 7.60,  0.36, -0.18, 0.240, 0.195, 0.55),
    (-0.62, -0.22, 6.40, -0.34, -0.16, 0.235, 0.190, 0.80),
    ( 0.22,  0.60, 5.00, -0.12,  0.30, 0.225, 0.185, 0.60),
]
BAND_STEP = 1.30      # studs between node bands
BAND_OUT = 0.050      # band radius = the stalk radius there + this
BAND_H = 0.14         # band height along the stalk
BAND_TOP_GAP = 0.38   # no band inside this much of the cut top

# ---- leaves: (stalk, arc s, surface angle deg, pitch up deg, roll deg)
# the surface angle uses the cucumber convention: 0 = +X, 90 = +Y (the front).
LEAVES = [
    (0, 6.00, 120.0, 34.0,  70.0),
    (0, 7.30,  44.0, 30.0, -62.0),
    (0, 8.60, 168.0, 26.0,  56.0),
    (1, 5.85, 315.0, 44.0, -68.0),
    (1, 7.15,  78.0, 30.0,  64.0),
    (2, 4.80, 235.0, 40.0,  60.0),
    (2, 6.10, 125.0, 34.0, -66.0),
    (3, 4.60, 350.0, 34.0,  58.0),
]
LEAF_L, LEAF_W, LEAF_T = 1.00, 0.32, 0.075

# ---- speckles: (stalk, arc s, surface angle deg) - one per internode, front-biased
STUDS = [
    (0, 1.35,  96.0), (0, 3.95,  62.0), (0, 5.25, 128.0), (0, 6.55,  84.0),
    (1, 1.20, 104.0), (1, 3.80,  70.0), (1, 6.40, 120.0),
    (2, 1.45,  88.0), (2, 4.05, 132.0), (2, 5.35,  66.0),
    (3, 1.25, 100.0), (3, 3.85,  74.0),
]
STUD_SIZE = 0.17

# ---- stones: (x, y, radius, z scale, y scale, jitter, spin deg, seed)
STONES = [
    ( 1.02,  0.34, 0.50, 0.70, 1.00, 0.24,  18.0, 11),
    (-0.95,  0.62, 0.45, 0.72, 1.00, 0.24, -35.0, 23),
    ( 0.16, -0.78, 0.60, 0.62, 0.78, 0.22,  12.0, 37),
]

# ---- shoots: (x, y, lean dx, lean dy, height, base radius)
SHOOTS = [
    (-0.34, -0.55, -0.08, -0.13, 0.92, 0.115),
    ( 0.30,  0.18,  0.10,  0.12, 0.66, 0.100),
    (-0.12,  0.52, -0.10,  0.10, 1.15, 0.125),
    ( 0.72,  0.10,  0.12,  0.06, 0.78, 0.105),
    (-0.48,  0.14, -0.12, -0.08, 0.54, 0.095),
]


# ------------------------------------------------------------------ small vector math
def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(a):
    L = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    return (0.0, 0.0, 1.0) if L < 1e-9 else (a[0] / L, a[1] / L, a[2] / L)


def _frame(i):
    """(base, top, direction, length, u, v) for stalk `i`.  u is the 0-degree side, v the
    90-degree (+Y, front) side; both are perpendicular to the leaning stalk axis."""
    bx, by, h, tx, ty = STALKS[i][0], STALKS[i][1], STALKS[i][2], STALKS[i][3], STALKS[i][4]
    base = (bx, by, 0.0)
    top = (bx + tx, by + ty, h)
    d = _sub(top, base)
    L = math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
    d = _norm(d)
    u = _norm(_cross((0.0, 1.0, 0.0), d))     # ~ +X
    v = _norm(_cross(d, u))                   # ~ +Y
    return base, top, d, L, u, v


def _radius(i, s, L):
    r0, r1 = STALKS[i][5], STALKS[i][6]
    t = min(1.0, max(0.0, s / L))
    return r0 + (r1 - r0) * t


def _surface(i, s, angle_deg, out=0.0):
    """A point on a stalk's skin at arc length `s` and surface angle, plus its normal."""
    base, _top, d, L, u, v = _frame(i)
    a = math.radians(angle_deg)
    n = _norm(_add(_scale(u, math.cos(a)), _scale(v, math.sin(a))))
    axis = _add(base, _scale(d, s))
    return _add(axis, _scale(n, _radius(i, s, L) + out)), n


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    rng = random.Random(9)

    # ---- stalks -----------------------------------------------------------
    bm = bmesh.new()
    for i in range(len(STALKS)):
        base, top, _d, _L, _u, _v = _frame(i)
        D.cyl(bm, base, top, STALKS[i][5], segs=8, r2=STALKS[i][6])
    D.new_obj("Stalks", bm, c, D.C("sam_stalk"), rbx_material="Wood")

    # ---- node bands -------------------------------------------------------
    bm = bmesh.new()
    for i in range(len(STALKS)):
        base, _top, d, L, _u, _v = _frame(i)
        s = STALKS[i][7]
        while s <= L - BAND_TOP_GAP:
            p = _add(base, _scale(d, s))
            a = _add(p, _scale(d, -BAND_H / 2.0))
            b = _add(p, _scale(d, BAND_H / 2.0))
            D.cyl(bm, a, b, _radius(i, s, L) + BAND_OUT, segs=8)
            s += BAND_STEP
    D.new_obj("Bands", bm, c, D.C("sam_bamboo"), rbx_material="Wood")

    # ---- speckles ---------------------------------------------------------
    bm = bmesh.new()
    for (i, s, ang) in STUDS:
        p, n = _surface(i, s, ang)
        D.stud_patch(bm, p, n, size=STUD_SIZE * rng.uniform(0.88, 1.12), rise=0.045,
                     bevel=0.025, spin=rng.uniform(-22.0, 22.0))
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- leaf blades ------------------------------------------------------
    bm = bmesh.new()
    for (i, s, ang, pitch, roll) in LEAVES:
        p, _n = _surface(i, s, ang, out=-0.04)
        # roll about the blade's own long axis first, then pitch it up, then swing it
        # round to the surface angle:  yaw turns +Y toward -X, so yaw = angle - 90.
        rot = (D.rot_euler(0.0, 0.0, ang - 90.0)
               @ D.rot_euler(pitch, 0.0, 0.0)
               @ D.rot_euler(0.0, roll, 0.0))
        D.leaf_blade(bm, length=LEAF_L, width=LEAF_W, thick=LEAF_T,
                     matrix=D.place(p, rot), ridge=0.05)
    D.new_obj("Leaves", bm, c, D.C("sam_leaf"), rbx_material="LeafyGrass")

    # ---- stones -----------------------------------------------------------
    bm = bmesh.new()
    for (x, y, r, sz, sy, jit, spin, seed) in STONES:
        cz = r * sz * (1.0 + jit) + 0.005          # keeps every stone on top of z = 0
        D.rock(bm, (x, y, cz), r, seed=seed, jitter=jit, subdiv=1,
               scale=(1.0, sy, sz), rot=D.rot_euler(0.0, 0.0, spin))
    D.new_obj("Stones", bm, c, D.C("sam_rock"), rbx_material="Slate")

    # ---- young shoots -----------------------------------------------------
    bm = bmesh.new()
    for (x, y, dx, dy, h, r) in SHOOTS:
        D.spike(bm, (x, y, 0.0), (x + dx, y + dy, h), r, segs=5, tip_r=0.030)
    D.new_obj("Shoots", bm, c, D.C("sam_stalk_dk"), rbx_material="Grass")

    return c
