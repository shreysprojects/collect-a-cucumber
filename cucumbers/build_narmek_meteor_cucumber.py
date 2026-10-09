"""Narmek: the Meteor Cucumber - a dark purple space rock split by a lightning crack."""
import bmesh, math, random

COLLECTION = "NarmekMeteorCucumber"
NOTES = ("A standard 4.0-tall cucumber body in dark purple `nar_meteor` rock (4.30 to the "
         "top of the stem nub, about 2.0 x 2.0 across once the shards are counted).  "
         "Twelve CHUNKY faceted `nar_meteor_lt` rock shards - D.gem, segs 6, squash 1.0, "
         "radii 0.26-0.34 - are driven into facet centres all the way up the body, each "
         "one tilted up to 24 degrees off its facet normal and spun a random amount so "
         "they jut out at broken angles.  Each shard's centre sits 0.04 OUTSIDE the facet "
         "plane, so roughly two thirds of every lump stands proud of the skin while its "
         "back stub still keys into it - no floaters.  Half of them (three on facet 7, "
         "three on facet 3) sit on the SILHOUETTE facets at angles 0 and 180 rather than "
         "only on the camera side, so the outline reads lumpy all the way up instead of "
         "like a smooth pillar.  Twenty-one `nar_meteor_lt` speckles (rows 7 x 3, size "
         "0.26) fill the gaps between them: each one searches for the nearest spot - up or down its "
         "own facet first, then a facet or two round - that clears the shards, the crack "
         "and the speckles already placed, so nothing on the model interpenetrates.  "
         "Down the FRONT facet (facet 1, +Y) runs the one bright note - a single "
         "`nar_glow_pur` lightning crack, one surface_line 0.11 wide zig-zagging between "
         "angles 80 and 100 from zf 0.12 to zf 0.80, Neon at emit 1.3.  It is the only "
         "lit thing on the model, so the silhouette reads black-purple rock with a "
         "glowing scar.  Centred on x=0, y=0; nothing below z=0; facet 1 faces +Y.  "
         "4 parts: Body (pillar + nub), Studs, Shards, Crack.  Studs and Shards share "
         "the colour `nar_meteor_lt` but carry different Roblox materials - Rock for the "
         "skin speckles, Slate for the crystal shards - so they stay separate objects.")

# ------------------------------------------------------------------ the shards
# (height fraction, facet index, gem radius).  Facet angles are 45*f + 45 degrees,
# so facet 1 = +Y (the camera side), 0 and 2 flank it, 4/5 are the back.
# Facets 7 (angle 0) and 3 (angle 180) are the SILHOUETTE seen from the front, so
# half the shards live there - that is what makes the outline read lumpy rather
# than like a smooth pillar.  Facet 1 is left almost clear for the lightning crack.
SHARDS = [
    (0.11, 7, 0.30),
    (0.17, 2, 0.27),
    (0.24, 3, 0.32),
    (0.31, 0, 0.29),
    (0.38, 7, 0.34),
    (0.45, 5, 0.28),
    (0.53, 3, 0.30),
    (0.60, 6, 0.26),
    (0.68, 7, 0.28),
    (0.76, 4, 0.31),
    (0.86, 3, 0.27),
    (0.92, 1, 0.28),
]
SHARD_OUT = 0.04           # how far a shard's centre sits OUTSIDE the facet plane
SHARD_TILT = 24.0          # max degrees a shard leans off its facet normal
SHARD_SEED = 11

# ------------------------------------------------------------------ the crack
# (height fraction, angle in degrees); +Y is 90, so this zig-zags down the front.
CRACK = [(0.12, 96.0), (0.30, 80.0), (0.45, 100.0), (0.62, 82.0), (0.80, 98.0)]
CRACK_W, CRACK_RISE = 0.11, 0.032

# ------------------------------------------------------------------ the speckles
STUD_ROWS, STUD_PER_ROW = 7, 3
STUD_Z0, STUD_Z1 = 0.11, 0.90
STUD_SIZE, STUD_RISE = 0.26, 0.05
STUD_SEED = 7
STUD_LO, STUD_HI = 0.09, 0.94        # how far a stud may be slid up or down its facet
STUD_STEP = 0.004                    # resolution of the search for a clear spot
FACET_COST = 0.15                    # how much a stud dislikes hopping to the next facet


def _place(zf, facet, blockers, segs):
    """The nearest clear (height fraction, facet) for one speckle.

    Sweeps the facet it wants first and then its neighbours, and returns the spot that
    clears every blocker - shards, the crack, and the speckles already placed - for the
    least movement.  `blockers` = [(facet, height_fraction, minimum_gap), ...].
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
    rng = random.Random(SHARD_SEED)

    # ---------------------------------------------------------------- body
    bm = bmesh.new()
    D.cuke_body(bm, h=h, r=r, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("nar_meteor"), rbx_material="Rock", roughness=0.82)

    # ---------------------------------------------------------------- speckles
    # Every shard, and the whole span of the crack, is a no-go zone for a speckle.
    stud_half = STUD_SIZE / 2.0 / h
    blockers = [(f, zf, sr / h + stud_half + 0.035) for zf, f, sr in SHARDS]

    crack_lo = min(zf for zf, _ in CRACK)
    crack_hi = max(zf for zf, _ in CRACK)
    crack_mid = (crack_lo + crack_hi) / 2.0
    crack_gap = (crack_hi - crack_lo) / 2.0 + CRACK_W / 2.0 / h + stud_half
    blockers.append((1, crack_mid, crack_gap))

    slots = []
    for zf, facet in D.cuke_stud_slots(STUD_ROWS, STUD_PER_ROW, STUD_Z0, STUD_Z1,
                                       D.CUKE_SEGS, True, STUD_SEED, 0.018):
        spot = _place(zf, facet, blockers, D.CUKE_SEGS)
        if spot is None:                       # no clear skin left - drop this one
            continue
        slots.append((spot[0], spot[1]))
        blockers.append((spot[1], spot[0], 2.0 * stud_half + 0.03))

    bm = bmesh.new()
    D.cuke_studs(bm, h=h, r=r, size=STUD_SIZE, rise=STUD_RISE, slots=slots)
    D.new_obj("Studs", bm, c, D.C("nar_meteor_lt"), rbx_material="Rock", roughness=0.78)

    # ---------------------------------------------------------------- rock shards
    bm = bmesh.new()
    for zf, facet, rad in SHARDS:
        p, n = D.cuke_facet_point(h, r, zf, facet, None, SHARD_OUT)
        rot = D.aim(n) @ D.rot_euler(rng.uniform(-SHARD_TILT, SHARD_TILT),
                                     rng.uniform(-SHARD_TILT, SHARD_TILT),
                                     rng.uniform(0.0, 360.0))
        D.gem(bm, p, radius=rad, segs=6, squash=1.0, rot=rot)
    D.new_obj("Shards", bm, c, D.C("nar_meteor_lt"), rbx_material="Slate",
              roughness=0.34)

    # ---------------------------------------------------------------- lightning
    bm = bmesh.new()
    D.surface_line(bm, CRACK, h=h, r=r, width=CRACK_W, rise=CRACK_RISE, offset=0.014)
    D.new_obj("Crack", bm, c, D.C("nar_glow_pur"), rbx_material="Neon", emit=0.65)

    return c
