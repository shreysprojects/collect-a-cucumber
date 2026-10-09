"""Three garden bushes side by side: a stemmed Shrub, a clipped box Hedge and a
FloweringBush.  Every variant faces +Y and is built around its own origin, then offset
along X, so a variant is separable by name prefix and drops into a game on its own."""
import bmesh

COLLECTION = "Bush"
NOTES = (
    "Three separable variants, prefixed A_ / B_ / C_, each centred on its own origin and "
    "then moved to the X offset in VARIANTS.  All three stand on a gravel ground pad that "
    "IS the footprint.  A_Shrub: 3.04 pad, five-lobe canopy 2.53 wide x 2.56 deep, 2.24 "
    "tall, carried on three woody stems that run from the litter at z 0.12 up to 1.02-1.10 "
    "- half a stud INSIDE the foliage - so the join can never show daylight; the canopy "
    "underside rumples between 0.44 and 0.71 and its lowest vertex (0.35) sits down among "
    "the stem tops.  B_Hedge: 4.0 wide x 2.0 deep pad, body 3.76 x 1.56, clipped cap at "
    "1.94 with three unclipped tufts scalloping the outline up to ~2.2 and one escaped "
    "sprig at 2.38; the pad and the dark base band are 4.00 / 3.96 wide so copies TILE "
    "cleanly at 4.0 stud spacing along X, and nothing on top crosses x +/-1.86.  "
    "C_FloweringBush: 2.84 pad, clump 2.35 across x 2.07 tall, sunk into a 0.34-tall mulch "
    "skirt so no daylight shows under it; 8 blooms and 3 berries are solved ONTO the clump "
    "surface, all on the +Y half (pink high in the light, red low against the skirt, "
    "berries on the +X shoulder) - move the clump and every one of them moves with it.  "
    "Nothing moves, no pivots."
)
VARIANTS = {
    "A": {"name": "Shrub",         "x": 7.0},
    "B": {"name": "Hedge",         "x": 0.0},
    "C": {"name": "FloweringBush", "x": -7.0},
}

# The viewer stands on +Y, so +X is screen LEFT: A reads leftmost, C rightmost.
AX = VARIANTS["A"]["x"]
BX = VARIANTS["B"]["x"]
CX = VARIANTS["C"]["x"]

LEAFY = "LeafyGrass"
GROUND = "Ground"


# ---------------------------------------------------------------- A : Shrub
def _shrub(D, c):
    """A lumpy leaf_mid canopy + a leaf_light sun-catch blob, sitting on three woody
    stems that run up inside it, ringed by a dark litter pad on gravel."""
    # gravel pad - the footprint, and the lightest ground value so the dark litter reads
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(9, 1.52, phase=0.15, center=(AX, 0.0)), 0.0, 0.06)
    D.new_obj("A_Soil", bm, c, D.C("gravel"), rbx_material=GROUND, roughness=0.85)

    # fallen leaves: a scalloped litter mound plus three strays flicked off the ring
    bm = bmesh.new()
    D.prism(bm, D.star_pts(7, 1.22, 0.88, phase=0.30, center=(AX, 0.0)), 0.02, 0.17)
    D.box(bm, (AX + 1.12, 0.44, 0.06), (AX + 1.35, 0.61, 0.11), rot=D.rot_euler(rz=18))
    D.box(bm, (AX - 1.00, 0.94, 0.06), (AX - 0.76, 1.10, 0.10), rot=D.rot_euler(rz=-32))
    D.box(bm, (AX + 0.22, -1.30, 0.06), (AX + 0.46, -1.14, 0.10), rot=D.rot_euler(rz=8))
    D.new_obj("A_Litter", bm, c, D.C("leaf_dark"), rbx_material=LEAFY, roughness=0.8)

    # three woody stems: splayed feet in the litter, tops converging on the canopy axis
    # and running a good half stud UP INSIDE it, so no daylight can show at the join
    bm = bmesh.new()
    D.cyl(bm, (AX - 0.46, 0.26, 0.12), (AX - 0.18, 0.10, 1.10), 0.100, segs=5)
    D.cyl(bm, (AX + 0.30, 0.44, 0.12), (AX + 0.12, 0.20, 1.06), 0.092, segs=5)
    D.cyl(bm, (AX + 0.48, -0.26, 0.12), (AX + 0.20, -0.14, 1.02), 0.084, segs=5)
    D.new_obj("A_Stems", bm, c, D.C("wood_light"), rbx_material="Wood", roughness=0.75)

    # canopy: five jittered lobes, wider than tall, so the outline is a lumpy dome and
    # the underside is a rumpled floor at z 0.44-0.71 rather than one taper to a point.
    # Its lowest vertex (0.35) sits down among the converging stem tops.
    bm = bmesh.new()
    D.foliage(bm, (AX, 0.0, 1.20), 0.95, seed=52, blobs=5, spread=0.60, jitter=0.28,
              subdiv=1, scale=(1.16, 1.0, 1.0), flatten=0.78)
    D.new_obj("A_Canopy", bm, c, D.C("leaf_mid"), rbx_material=LEAFY, roughness=0.7)

    # the sun-catch: one lighter blob seated ON the canopy's forward shoulder (its
    # centre sits on that lobe's surface, so half of it stands proud of the mid green)
    bm = bmesh.new()
    D.foliage(bm, (AX + 0.33, 0.68, 1.79), 0.40, seed=23, blobs=1, jitter=0.22,
              subdiv=1, flatten=0.9)
    D.new_obj("A_Highlight", bm, c, D.C("leaf_light"), rbx_material=LEAFY, roughness=0.65)


# ---------------------------------------------------------------- B : Hedge
def _hedge(D, c):
    """A clipped box hedge: dark shadow plinth, mid body, and a jittered cap one value
    step lighter, scalloped by the tufts and twigs the shears missed."""
    bm = bmesh.new()
    D.box(bm, (BX - 2.00, -1.00, 0.0), (BX + 2.00, 1.00, 0.07))
    D.new_obj("B_Soil", bm, c, D.C("gravel"), rbx_material=GROUND, roughness=0.85)

    # shadow band: slightly proud of the body so the hedge looks planted, not floating
    bm = bmesh.new()
    D.beveled_box(bm, (BX - 1.98, -0.86, 0.05), (BX + 1.98, 0.86, 0.50), bevel=0.10)
    D.new_obj("B_Base", bm, c, D.C("leaf_dark"), rbx_material=LEAFY, roughness=0.8)

    bm = bmesh.new()
    D.beveled_box(bm, (BX - 1.88, -0.78, 0.42), (BX + 1.88, 0.78, 1.66), bevel=0.14)
    D.new_obj("B_Body", bm, c, D.C("leaf_mid"), rbx_material=LEAFY, roughness=0.7)

    # cap: a jittered slab (so the top is never dead flat) with three unclipped tufts
    # straddling its long edges and two escaped sprigs.  The tufts are round blobs, not
    # trays: they scallop the top outline and overhang the body, so the hedge stops
    # reading as a box with a lid.  Only one value step off the body, not two.
    bm = bmesh.new()
    D.stone_block(bm, (BX - 1.82, -0.74, 1.58), (BX + 1.82, 0.74, 1.92),
                  seed=7, jitter=0.045, bevel=0.09)
    D.foliage(bm, (BX - 1.28, 0.62, 1.82), 0.36, seed=61, blobs=1, jitter=0.24,
              subdiv=1, scale=(1.15, 1.0, 1.0), flatten=0.85)
    D.foliage(bm, (BX + 0.06, -0.64, 1.79), 0.33, seed=67, blobs=1, jitter=0.24,
              subdiv=1, scale=(1.20, 1.0, 1.0), flatten=0.85)
    D.foliage(bm, (BX + 1.22, 0.66, 1.84), 0.34, seed=73, blobs=1, jitter=0.24,
              subdiv=1, scale=(1.15, 1.0, 1.0), flatten=0.85)
    D.spike(bm, (BX - 1.58, 0.34, 2.00), (BX - 1.70, 0.52, 2.38), 0.10, segs=5)
    D.spike(bm, (BX + 1.14, -0.34, 1.95), (BX + 1.22, -0.46, 2.26), 0.10, segs=5)
    D.new_obj("B_Top", bm, c, D.C("plastic_green"), rbx_material=LEAFY, roughness=0.65)


# ---------------------------------------------------------------- C : FloweringBush
# Bloom, bud and berry centres, local to the bush origin, each solved onto the SURFACE
# of the seed-20 canopy AT ITS CURRENT HEIGHT so half the blob stands proud instead of
# drowning inside a lobe - move the canopy in z and every one of these has to move with
# it.  Every y is positive: the blooms only ever face the viewer.  Pink rides high in
# the light, red sits low where the dark skirt and the canopy underside back it up, and
# the berries bunch on the +X shoulder - the flank the camera is on, so they read.
_PINK = [(-0.502, 0.741, 1.558), (0.437, 0.998, 1.611), (-0.141, 0.564, 1.899),
         (0.968, 0.725, 1.381), (-0.769, 0.517, 1.103)]
_RED = [(0.238, 1.109, 0.967), (-0.400, 0.697, 0.809), (0.613, 0.622, 0.520)]
_BERRY = [(0.958, 0.454, 0.792), (0.928, 0.656, 0.770), (0.710, 0.937, 1.004)]


def _flowering(D, c):
    """A dense mid-green clump sunk into its own mulch skirt, with eight blooms over
    its sunny face and a berry bunch seated on the +X shoulder."""
    cz, rad, sx, flat = 0.86, 0.94, 1.05, 0.86       # canopy centre and blob shape

    def on(p):
        return (CX + p[0], p[1], p[2])

    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 1.42, phase=0.35, center=(CX, 0.0)), 0.0, 0.06)
    D.new_obj("C_Soil", bm, c, D.C("gravel"), rbx_material=GROUND, roughness=0.85)

    # dark skirt: a mulch mound tall enough that the clump's underside is BURIED in it -
    # no daylight under the bush - and the value the red blooms sit against
    bm = bmesh.new()
    D.prism(bm, D.star_pts(6, 1.20, 0.90, phase=0.25, center=(CX, 0.0)), 0.02, 0.34)
    D.new_obj("C_Shade", bm, c, D.C("leaf_dark"), rbx_material=LEAFY, roughness=0.8)

    # the clump: the two solved lobes the blooms are pinned to, plus two skirt lobes
    # thrown low, wide and back (well clear of the blooms).  They break the ball
    # silhouette AND fill the flanks, where a plain sphere would leave daylight between
    # its underside and the mulch.
    bm = bmesh.new()
    D.foliage(bm, (CX, 0.0, cz), rad, seed=20, blobs=2, spread=0.52, jitter=0.25,
              subdiv=1, scale=(sx, 1.0, 1.0), flatten=flat)
    D.foliage(bm, (CX - 0.74, -0.28, 0.66), 0.46, seed=44, blobs=1, jitter=0.25,
              subdiv=1, scale=(sx, 1.0, 1.0), flatten=flat)
    D.foliage(bm, (CX + 0.70, -0.22, 0.62), 0.44, seed=58, blobs=1, jitter=0.25,
              subdiv=1, scale=(sx, 1.0, 1.0), flatten=flat)
    D.new_obj("C_Canopy", bm, c, D.C("leaf_mid"), rbx_material=LEAFY, roughness=0.7)

    bm = bmesh.new()
    for d in _PINK:
        D.uvsphere(bm, on(d), 0.175, segs=5, rings=3)
    D.new_obj("C_Blooms", bm, c, D.C("flower_pink"), roughness=0.5)

    bm = bmesh.new()
    for d in _RED:
        D.uvsphere(bm, on(d), 0.185, segs=5, rings=3)
    D.new_obj("C_Buds", bm, c, D.C("flower_red"), roughness=0.5)

    # berries: big enough to read at 40 studs and seated ON the leaves, not floating
    # off the silhouette edge as three specks of dirt
    bm = bmesh.new()
    for d in _BERRY:
        D.uvsphere(bm, on(d), 0.130, segs=5, rings=2)
    D.new_obj("C_Berries", bm, c, D.C("seed_brown"), roughness=0.45)


# ---------------------------------------------------------------- build
def build(D):
    """D is the imported proplib module.  Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    _shrub(D, c)
    _hedge(D, c)
    _flowering(D, c)
    return c
