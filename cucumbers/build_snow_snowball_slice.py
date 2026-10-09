"""Snow: Snowball Slice - one big snowball with a cucumber slice set into its face."""
import bmesh, math, random

COLLECTION = "SnowSnowballSlice"
NOTES = ("ONE big snowball carrying a cut-cucumber medallion pressed into the face it "
         "turns to the camera.  The ball is a 14 x 10 uvsphere of radius 1.25 centred "
         "at z 1.25 in snow_white with the Snow material, resting exactly on z = 0.  "
         "Set into its +Y side - the side the render camera and the player see - is a "
         "standard cut slice standing upright: a cuke_green rim drum (radius 0.72, "
         "0.42 thick), a cuke_pale cut face and five cuke_seed pips (four in a ring "
         "plus one in the middle), placed with slice_stand((0, 1.08, 1.30)) so the back "
         "half of the drum is buried in the snow while the green rim and the pale face "
         "stand proud of it.  Only the camera-side face and pips are built "
         "(both=False); the buried side has none.  Seven cuke_stud green speckle "
         "squares - the set's signature - are snapped to the ball's own facet centres "
         "around and above the medallion, kept out of the cone the slice fills and off "
         "the buried underside, so the snow reads as part of the cucumber set.  "
         "Nothing dips below z = 0.  5 parts, ~2.5 x 2.5 x 2.5 studs.")

SEGS, RINGS = 14, 10
BALL_C = (0.0, 0.0, 1.25)
BALL_R = 1.25

# the medallion: standing, cut face to +Y, sunk half its thickness into the snow
SLICE_LOC = (0.0, 1.08, 1.30)
SLICE_RAD = 0.72
SLICE_THK = 0.42

STUDS = 7
STUD_SIZE = 0.30
STUD_SEED = 17


def _facets(segs, rings):
    """(unit direction, inset) for every QUAD facet centre of a uvsphere; the two polar
    triangle bands are skipped.  `inset` is the facet plane's distance from the centre as
    a fraction of the radius, so a stud placed there sits flat ON the facet instead of
    floating above it."""
    out = []
    for j in range(1, rings - 1):
        p0, p1 = math.pi * j / rings, math.pi * (j + 1) / rings
        for i in range(segs):
            t0, t1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
            cx = cy = cz = 0.0
            for p, t in ((p0, t0), (p0, t1), (p1, t1), (p1, t0)):
                cx += math.sin(p) * math.cos(t)
                cy += math.sin(p) * math.sin(t)
                cz += math.cos(p)
            cx, cy, cz = cx / 4.0, cy / 4.0, cz / 4.0
            L = math.sqrt(cx * cx + cy * cy + cz * cz)
            if L > 1e-6:
                out.append(((cx / L, cy / L, cz / L), L))
    return out


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _pick(facets, n, rng, avoid=(), spread_deg=52.0):
    """`n` facet centres, well spread over the ball and biased to the camera side and
    the top, skipping anything inside one of the `avoid` cones - (direction, cos limit)."""
    scored = []
    for d, inset in facets:
        if any(_dot(d, a) > lim for a, lim in avoid):
            continue
        scored.append((0.45 * d[1] + 0.38 * d[2] + rng.uniform(0.0, 0.55), d, inset))
    scored.sort(key=lambda t: -t[0])
    out = []
    for step in range(10):
        cosmin = math.cos(math.radians(max(8.0, spread_deg - step * 5.0)))
        out = []
        for _s, d, inset in scored:
            if all(_dot(d, p) < cosmin for p, _i in out):
                out.append((d, inset))
                if len(out) >= n:
                    return out
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ------------------------------------------------------------ the snowball
    bm = bmesh.new()
    D.uvsphere(bm, BALL_C, BALL_R, segs=SEGS, rings=RINGS)
    D.new_obj("Ball", bm, c, D.C("snow_white"), rbx_material="Snow", roughness=0.74)

    # ------------------------------------- the cut slice set into the +Y face
    m = D.slice_stand(SLICE_LOC)

    bm = bmesh.new()
    D.slice_disc(bm, radius=SLICE_RAD, thick=SLICE_THK, matrix=m, bevel=0.05)
    D.new_obj("Rim", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.slice_face(bm, radius=SLICE_RAD, thick=SLICE_THK, matrix=m, inset=0.11,
                 proud=0.03, both=False)
    D.new_obj("Face", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.slice_seeds(bm, radius=SLICE_RAD, thick=SLICE_THK, matrix=m, n=4, size=0.16,
                  ring=0.44, proud=0.03, both=False, centre_seed=True, phase_deg=24.0)
    D.new_obj("Seeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    # ------------------------------- the set's green speckles over the snow
    rng = random.Random(STUD_SEED)
    avoid = [((0.0, 1.0, 0.0), math.cos(math.radians(46.0))),   # where the slice sits
             ((0.0, 0.0, -1.0), math.cos(math.radians(56.0)))]  # the buried underside
    bm = bmesh.new()
    for d, inset in _pick(_facets(SEGS, RINGS), STUDS, rng, avoid=avoid):
        reach = BALL_R * inset
        p = (BALL_C[0] + d[0] * reach, BALL_C[1] + d[1] * reach, BALL_C[2] + d[2] * reach)
        D.stud_patch(bm, p, d, size=STUD_SIZE * rng.uniform(0.90, 1.12), rise=0.055,
                     bevel=0.03, spin=rng.uniform(-16.0, 16.0))
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
