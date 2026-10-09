"""Underwater: the Coral Cucumber - a purple body sprouting five red staghorn arms."""
import bmesh, math

COLLECTION = "UnderwaterCoralCucumber"
NOTES = ("A standard 4.0-tall cucumber body in purple `sea_coral_p` (4.30 to the top of "
         "the stem nub) with FIVE red `sea_coral_r` staghorn coral arms growing out of "
         "its sides - one per level at height fractions 0.25, 0.42, 0.55, 0.70 and 0.80, "
         "each rooted on a different body facet so they spiral round it rather than "
         "stacking up one face.  Going up: 45 degrees (front, screen-left, low), 180 "
         "(screen-right), 315 (back, screen-left), 135 (front, screen-right) and 0 "
         "(screen-left, and the tallest - its tip is the top of the model at z 4.61).  "
         "Two of them - the 45 and the 135 arm - lean toward the camera so the branching "
         "reads in the hero render instead of only in silhouette.  Every arm is one "
         "`coral_arm`: a 0.95-long, 0.15-radius trunk that forks twice into two, so seven "
         "tapering tubes per arm, pitched 36-60 degrees above horizontal and sunk 0.10 "
         "into the skin so no arm floats off the body.  The low arms lie out flatter, the "
         "top two rear up, which keeps the whole thing inside about 3.0 x 2.6 studs of "
         "floor and 4.6 tall.  Twenty-one `sea_coral_r` speckles (rows 7 x 3, size 0.28) "
         "cover the skin between them: each one searches for the nearest clear spot - up "
         "or down its own facet first, then a facet or two round - that misses every arm "
         "root and every speckle already placed, so nothing on the model interpenetrates. "
         " Centred on x=0, y=0; nothing below z=0 (the lowest arm geometry sits at "
         "z 0.85); facet 1 faces +Y.  3 parts: Body (pillar + nub), Studs, Arms.  Studs "
         "and Arms share the colour `sea_coral_r` but carry different Roblox materials - "
         "SmoothPlastic for the speckles on the cucumber skin, Limestone for the chalky "
         "coral - so they stay separate objects.")

# ------------------------------------------------------------------ the coral arms
# (height fraction, body facet, pitch in degrees above horizontal, coral_arm seed).
# Facet angles are 45 * (facet + 1) degrees, so facet 1 = +Y (the camera side):
#   0 -> 45    1 -> 90 (+Y)   2 -> 135   3 -> 180 (-X)
#   4 -> 225   5 -> 270 (-Y)  6 -> 315   7 -> 0 (+X)
# Remember +X is screen-LEFT.  Facet 1 is left clear so the front of the cucumber
# still reads as a cucumber.
ARMS = [
    (0.25, 0, 36.0, 21),          # front, screen-left, flung out low
    (0.42, 3, 60.0, 58),          # screen-right, rearing up
    (0.55, 6, 40.0, 32),          # back, screen-left - depth behind the body
    (0.70, 2, 40.0, 41),          # front, screen-right, reaching at the camera
    (0.80, 7, 60.0, 57),          # screen-left, the crown of the model
]
ARM_LEN, ARM_R = 0.95, 0.15       # trunk length and root radius
ARM_DEPTH, ARM_BRANCHES = 2, 2    # two forks deep, two ways each -> 7 tubes an arm
ARM_SPREAD = 40.0                 # degrees a fork turns off its parent
ARM_SHRINK = 0.42                 # each fork this fraction of its parent's length
ARM_CURL = 0.10                   # every tube tips up a little at its end
ARM_SEGS = 5                      # 5-sided tubes: the house style for anything thin
ARM_SINK = 0.10                   # how far an arm's root sits inside the skin

# ------------------------------------------------------------------ the speckles
STUD_ROWS, STUD_PER_ROW = 7, 3
STUD_Z0, STUD_Z1 = 0.11, 0.90
STUD_SIZE, STUD_RISE = 0.28, 0.055
STUD_SEED = 7
STUD_LO, STUD_HI = 0.08, 0.94     # how far a speckle may be slid up or down its facet
STUD_STEP = 0.005                 # resolution of the search for a clear spot
FACET_COST = 0.16                 # how much a speckle dislikes hopping to the next facet

ARM_ROOT_RISE = 0.06              # an arm's no-go band sits a touch above its root
ARM_ROOT_GAP = 0.17               # ... and is this tall in height fractions


def _clear_slot(zf, facet, blockers, segs):
    """The nearest clear (height fraction, facet) for one speckle.

    Sweeps the facet it wants first and then its neighbours, and returns the spot that
    clears every blocker - the arm roots and the speckles already placed - for the least
    movement.  `blockers` = [(facet, height fraction, minimum gap), ...].
    Returns None when this body simply has no room left for it."""
    best, best_cost = None, 1e9
    steps = int(round((STUD_HI - STUD_LO) / STUD_STEP))
    for df in (0, 1, -1, 2, -2):
        f = (facet + df) % segs
        near = [(z, g) for ff, z, g in blockers if ff == f]
        base = FACET_COST * abs(df)
        if base >= best_cost:
            break
        for i in range(steps + 1):
            cand = STUD_LO + (STUD_HI - STUD_LO) * i / float(steps)
            cost = base + abs(cand - zf)
            if cost >= best_cost:
                continue
            if any(abs(cand - z) < g - 1e-9 for z, g in near):
                continue
            best, best_cost = (cand, f), cost
    return best


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    h, r = D.CUKE_H, D.CUKE_R

    # ---------------------------------------------------------------- body
    bm = bmesh.new()
    D.cuke_body(bm, h=h, r=r, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("sea_coral_p"), rbx_material="SmoothPlastic",
              roughness=0.48)

    # ---------------------------------------------------------------- speckles
    # Every arm root is a no-go band on its own facet; then each speckle, once placed,
    # becomes a blocker for the ones after it.
    stud_half = STUD_SIZE / 2.0 / h
    blockers = [(facet, zf + ARM_ROOT_RISE, ARM_ROOT_GAP + stud_half)
                for zf, facet, _pitch, _seed in ARMS]

    slots = []
    for zf, facet in D.cuke_stud_slots(STUD_ROWS, STUD_PER_ROW, STUD_Z0, STUD_Z1,
                                       D.CUKE_SEGS, True, STUD_SEED, 0.018):
        spot = _clear_slot(zf, facet, blockers, D.CUKE_SEGS)
        if spot is None:                       # no clear skin left - drop this one
            continue
        slots.append(spot)
        blockers.append((spot[1], spot[0], 2.0 * stud_half + 0.03))

    bm = bmesh.new()
    D.cuke_studs(bm, h=h, r=r, size=STUD_SIZE, rise=STUD_RISE, slots=slots)
    D.new_obj("Studs", bm, c, D.C("sea_coral_r"), rbx_material="SmoothPlastic",
              roughness=0.5)

    # ---------------------------------------------------------------- coral arms
    bm = bmesh.new()
    for zf, facet, pitch, seed in ARMS:
        base, n = D.cuke_facet_point(h, r, zf, facet, None, -ARM_SINK)
        cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
        D.coral_arm(bm, base=base, direction=(n[0] * cp, n[1] * cp, sp),
                    length=ARM_LEN, radius=ARM_R, depth=ARM_DEPTH,
                    branches=ARM_BRANCHES, spread=ARM_SPREAD, shrink=ARM_SHRINK,
                    seed=seed, segs=ARM_SEGS, curl=ARM_CURL)
    D.new_obj("Arms", bm, c, D.C("sea_coral_r"), rbx_material="Limestone",
              roughness=0.74)

    return c
