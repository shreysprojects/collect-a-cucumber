"""Snow: the SnowcapCucumber - an ordinary GREEN cucumber wearing a thick snow cap."""
import bmesh, random

COLLECTION = "SnowSnowcapCucumber"
NOTES = (
    "A normal cucumber that has been left out in the snow: the set's standard 4.0-tall "
    "cuke_green body (r 0.68, 8 facets, facet 1 facing +Y) with its usual cuke_stud "
    "green speckles, and the snow sitting ON it rather than replacing it - most of the "
    "green shows.  Over its head, a soft snow_white cap (\"Snow\") from height fraction "
    "0.84 up, spreading to ~1.14x the body radius and sending four fat tongues of snow "
    "down the +Y / -X / -Y / +X facets to about z 2.4-2.9; the fattest runs down the "
    "FRONT face, which is what sells the cap from the side.  The stem nub is drawn a "
    "little long (0.30 x 0.50) so the green stem breaks up through the crown of the snow "
    "instead of being buried by it.  Lower down, four settled snow patches "
    "(\"Glacier\", size 0.36-0.46, slightly wider than tall) cling to the shoulders at "
    "height fractions 0.36-0.60 on the front-left, front, front-right and +X facets.  "
    "All 23 speckles are placed by hand (slots=): any that would have landed under a "
    "snow tongue, inside a snow patch or on top of another speckle is rolled round to "
    "the next facet (and dropped outright if the whole ring at that height is taken), "
    "and two more are added on the front facet, which the stock slot pattern never "
    "reaches - 10 of the 23 read from the camera.  NO spikes - this one is soft.  "
    "Footprint ~2.0 x 2.0 (the "
    "widest point is a snow tongue, not the body), 4.50 tall to the tip of the stem; "
    "centred on x=0, y=0, nothing below z=0.  4 parts: Body (pillar + nub), Studs, "
    "SnowCap, SnowPatches."
)

# --- the body ---------------------------------------------------------------
NUB = (0.30, 0.50)          # a slightly long stem, so it pokes out through the snow

# --- the speckles -----------------------------------------------------------
STUD_ROWS, STUD_PER_ROW = 7, 3
STUD_Z0, STUD_Z1 = 0.11, 0.80       # stop clear of the cap's skirt at 0.84
STUD_SIZE, STUD_RISE = 0.28, 0.055
STUD_SEED = 11

# --- the snow cap -----------------------------------------------------------
CAP_THICK, CAP_DRIPS, CAP_DRIP_LEN, CAP_TOP_ZF = 0.34, 4, 0.6, 0.84
CAP_SEED = 17               # this seed drops the four tongues on facets 1, 3, 5, 7

# --- snow settled on the shoulders: (height fraction, facet, size, aspect, spin)
PATCHES = [
    (0.60, 0, 0.46, 0.70,   9.0),   # front-left shoulder (facet 0 = +45 deg)
    (0.44, 2, 0.40, 0.66,  -8.0),   # front-right, lower  (facet 2 = 135 deg)
    (0.36, 1, 0.36, 0.72,   6.0),   # a small dab low on the front
    (0.52, 7, 0.42, 0.68, -11.0),   # the +X (screen-left) flank
]

# Two speckles placed by hand on the FRONT facet: `cuke_stud_slots` steps round by
# round(8/3) = 3 facets a time, so facet 1 - the one the camera looks straight at -
# is only ever reached by a rolled speckle, and the front snow patch takes that one.
EXTRA_SLOTS = [(0.155, 1), (0.527, 1)]

# keep-out distances, all in height fractions of the body (1 zf = 4 studs).  Nothing
# needs a neighbour-facet rule: studs and patches are both snapped to facet centres
# and neither is wider (0.46 max) than a facet (0.52), so they never meet round a corner.
STUD_CLEAR = 0.10           # speckle vs another speckle on the same facet
DRIP_CLEAR = 0.06           # a speckle this far under a tongue is still covered by it
PATCH_CLEAR = 0.09          # speckle vs a snow patch on the same facet


def _drip_slots(segs, drips, top_zf, seed):
    """Where `cuke_snow_cap` will drop its tongues, as (height fraction, facet).

    It is worth replaying the lib's own RNG draw for draw - facet, then height, then
    width - because a speckle hidden under a tongue is a wasted speckle."""
    rng = random.Random(seed)
    step = max(1, segs // max(1, drips))
    out = []
    for i in range(drips):
        facet = (i * step + rng.randint(0, 1)) % segs
        zf = top_zf - rng.uniform(0.10, 0.26)
        rng.uniform(0.20, 0.32)                 # the tongue's width: drawn, not needed
        out.append((zf, facet))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R, SEGS = D.CUKE_H, D.CUKE_R, D.CUKE_SEGS

    # ---------------------------------------------------------------- body
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=NUB)
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ------------------------------------------------------ speckle placement
    # `cuke_snow_cap` hangs its tongues on known facets and the shoulder patches
    # are placed by hand, so work both out first and shuffle any speckle that
    # would be buried round to the next facet.
    tongues = _drip_slots(SEGS, CAP_DRIPS, CAP_TOP_ZF, CAP_SEED)

    slots = list(EXTRA_SLOTS)
    for zf, facet in D.cuke_stud_slots(STUD_ROWS, STUD_PER_ROW, STUD_Z0, STUD_Z1,
                                       SEGS, True, STUD_SEED, 0.018):
        for _ in range(SEGS):
            clear_of_tongues = all(facet != tf or zf < tz - DRIP_CLEAR
                                   for tz, tf in tongues)
            clear_of_patches = all(facet != pf or abs(zf - pz) > PATCH_CLEAR
                                   for pz, pf, _s, _a, _sp in PATCHES)
            clear_of_studs = all(facet != f2 or abs(zf - z2) > STUD_CLEAR
                                 for z2, f2 in slots)
            if clear_of_tongues and clear_of_patches and clear_of_studs:
                slots.append((zf, facet))
                break
            facet = (facet + 1) % SEGS
        # else: every facet at this height is taken - drop the speckle rather than
        # bury it.  All 21 survive alongside the 2 hand-placed front ones.

    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, size=STUD_SIZE, rise=STUD_RISE, slots=slots)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---------------------------------------------------------------- snow cap
    bm = bmesh.new()
    D.cuke_snow_cap(bm, h=H, r=R, thick=CAP_THICK, drips=CAP_DRIPS,
                    drip_len=CAP_DRIP_LEN, top_zf=CAP_TOP_ZF, seed=CAP_SEED)
    D.new_obj("SnowCap", bm, c, D.C("snow_white"), rbx_material="Snow", roughness=0.88)

    # ------------------------------------------------- snow on the shoulders
    bm = bmesh.new()
    for zf, facet, size, aspect, spin in PATCHES:
        p, n = D.cuke_facet_point(h=H, r=R, zf=zf, facet=facet)
        D.stud_patch(bm, p, n, size=size, rise=0.065, sink=0.11, bevel=0.045,
                     aspect=aspect, spin=spin)
    D.new_obj("SnowPatches", bm, c, D.C("snow_white"), rbx_material="Glacier",
              roughness=0.52)

    return c
