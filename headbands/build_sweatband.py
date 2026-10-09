"""Tier 1 Sweatband: white terrycloth ring with one bold blue stripe round its middle."""
import bmesh

COLLECTION = "Sweatband"
TIER = 1
DISPLAY_NAME = "Sweatband"
NOTES = (
    "The cheapest item in the set and it is meant to look it: three concentric rings, no "
    "centrepiece, no metal, no glow, nothing above the band. It is fully ROTATIONALLY "
    "SYMMETRIC - there is no front detail - so the installer can drop it on at any yaw and "
    "it still reads correctly (the +Y front only matters for the tiers that have a badge).\n"
    "Construction, outside in: Hem is a plain ring (r 0.635 -> 0.730, z -0.17 .. +0.17) that "
    "is BOTH the lining against the head and the pinched, slightly greyer edge of the "
    "towelling. Terry is the fat bulged ring (r 0.710 -> 0.755 + 0.05 bulge, z -0.14 .. "
    "+0.14) that sits inside it, so 0.03 of the darker hem is left exposed as a rim at the "
    "top and the bottom - that step, not the hue, is what keeps the two whites apart. "
    "Stripe is a flat-walled ring standing 0.020 proud of the bulge at mid-height (0.040 at "
    "its own edges, where the terry has curved away).\n"
    "Terry and Stripe are built with the SAME seed, segment count and jitter, so the "
    "per-segment radial wobble is identical on both and the stripe stays exactly parallel to "
    "the cloth it sits on all the way round instead of sinking into it on some facets. Do "
    "not change SEG on one ring without changing it on all three: the facet corners of the "
    "three 16-gons line up exactly at the moment, which is what stops the terry poking "
    "through the stripe.\n"
    "Head fit: the tightest point anywhere is the hem's inner wall at radius 0.635, i.e. "
    "0.035 of clearance over a default R15 head. Nothing else on the model ever comes inside "
    "that. Total height is 0.34 studs (z -0.17 .. +0.17), a touch taller than the plain "
    "0.26 band, and the widest point is radius 0.834 at the stripe.\n"
    "Roblox: all three parts are Fabric and all three want FLAT shading - the flat facets "
    "plus the radial jitter are the whole towelling read, and smoothing them turns it back "
    "into shiny plastic."
)

# ---------------------------------------------------------------- geometry contract
# Studs. Band axis is +Z (up out of the head), front is +Y, ring centred on the origin.
SEG = 16            # shared by all three rings so their facet corners coincide exactly
SEED = 7            # matched jitter: Terry and Stripe draw the same random sequence
JIT = 0.009         # radial per-segment wobble - the "not glassy-smooth" terry cue

Z_HEM = 0.17                                    # band half-height: 0.34 tall overall
R_HEM_IN, R_HEM_OUT = 0.635, 0.730              # 0.635 is the tightest radius on the model

Z_TERRY = 0.14                                  # leaves 0.03 of hem showing top and bottom
R_TERRY_IN, R_TERRY_OUT, BULGE = 0.710, 0.755, 0.05   # outer surface swells to 0.805 at z=0

Z_STRIPE = 0.057                                # 0.114 tall = a third of the 0.34 band
R_STRIPE_IN, R_STRIPE_OUT = 0.740, 0.825        # inner edge buried in the terry, outer proud


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    # 1. Hem / lining - the greyer white. Full height, smallest radius, NO jitter: the
    #    overlocked edge of a sweatband is the one pinched, even part of it, which is what
    #    makes the jittered terry beside it read as soft.
    bm = bmesh.new()
    H.band(bm, r_in=R_HEM_IN, r_out=R_HEM_OUT, z0=-Z_HEM, z1=Z_HEM, segs=SEG)
    H.new_obj("Hem", bm, c, "e2e2df", rbx_material="Fabric", roughness=0.90)

    # 2. Terry - the towelling body. Bulged so the profile is a soft barrel rather than a
    #    washer, and jittered so no two facets catch the light identically.
    bm = bmesh.new()
    H.band(bm, r_in=R_TERRY_IN, r_out=R_TERRY_OUT, z0=-Z_TERRY, z1=Z_TERRY,
           segs=SEG, bulge=BULGE, seed=SEED, jitter=JIT)
    H.new_obj("Terry", bm, c, "f2f2f0", rbx_material="Fabric", roughness=0.95)

    # 3. Stripe - one bold blue ring, centred. H.band with bulge=0 rather than H.stripe
    #    because stripe() cannot take a seed, and the stripe MUST inherit the terry's
    #    per-segment jitter to stay a uniform 0.020 proud of it the whole way round.
    bm = bmesh.new()
    H.band(bm, r_in=R_STRIPE_IN, r_out=R_STRIPE_OUT, z0=-Z_STRIPE, z1=Z_STRIPE,
           segs=SEG, bulge=0.0, seed=SEED, jitter=JIT)
    H.new_obj("Stripe", bm, c, "2f7fd4", rbx_material="Fabric", roughness=0.90)

    return c


# ---------------------------------------------------------------------------------
# AUDIT - 3 parts, 448 tris (budget 450), bbox 1.67 x 1.67 x 0.34, z -0.170 .. +0.170
#
#  part     colour role            hex      material  prims                       tris
#  Hem      towelling edge/lining  e2e2df   Fabric    1 band, 16 segs, no bulge    128
#  Terry    white towelling body   f2f2f0   Fabric    1 band, 16 segs, bulged      192
#  Stripe   sports blue            2f7fd4   Fabric    1 band, 16 segs, no bulge    128
#                                                                          total   448
#  (band ring = segs * 4 quads * 2; with bulge it is segs * 6 quads * 2.)
#
# value ladder: Stripe 2f7fd4 (~0.50 value)  <<  Hem e2e2df (0.89)  <  Terry f2f2f0 (0.95).
#   The blue carries the whole silhouette break. The two whites are only 0.06 apart, so
#   they are NOT asked to separate on value alone: the hem is recessed 0.025-0.075 behind
#   the terry surface and only 0.03 tall, so it reads as a shadowed edge, and the geometric
#   step does the work the hue cannot at accessory size.
#
# radial trace (the head is radius 0.60; nothing may come inside 0.63):
#   0.635  Hem inner wall .............. TIGHTEST POINT ON THE MODEL, 0.035 clear of the head
#   0.710  Terry inner wall ............ buried inside the hem (0.635 .. 0.730)
#   0.730  Hem outer wall .............. exposed only as the rim strip above/below the terry
#   0.740  Stripe inner wall ........... buried: terry surface is >= 0.776 across the
#                                        stripe's z-band even on the thinnest facet
#   0.746 .. 0.764  Terry outer at z = +-0.14   (0.755 +- jitter)
#   0.796 .. 0.814  Terry outer at z = 0        (+ 0.05 bulge)
#   0.816 .. 0.834  Stripe outer ........ WIDEST POINT; jitter matched to the terry, so the
#                                        stripe stands a constant 0.020 proud at z = 0 and
#                                        0.040 proud at z = +-0.057, on every facet
#
# key z levels: -0.170 bottom of hem | -0.140 bottom of terry | -0.057 stripe bottom
#   0.000 the bulge's widest line | +0.057 stripe top | +0.140 top of terry | +0.170 top
#   of hem (highest point - nothing on this tier goes above the band).
# ---------------------------------------------------------------------------------
