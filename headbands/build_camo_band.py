"""Tier 3 'Camo Band' - an olive military band under irregular three-tone camo blotches."""
import bmesh

COLLECTION = "CamoBand"
TIER = 3
DISPLAY_NAME = "Camo Band"
NOTES = ("Four MeshParts, one per colour: Band / PatchesDark / PatchesSage / PatchesTan. "
         "The blotches are short arcs of band() sitting 0.014-0.023 proud of the olive "
         "ring's outer face, so they follow the curve exactly and read as printed camo "
         "rather than stuck-on tiles. Every arc is generated from random.Random(BLOTCH_SEED) "
         "with a fixed colour order and a fixed top/bottom/floating pattern, so the layout "
         "is identical on every rebuild - change BLOTCH_SEED to reroll the camo. "
         "The base ring is deliberately un-bulged: the patches have to clear the band's "
         "widest point at every angle, and a bulge would swallow them at mid-height. "
         "Tightest radius anywhere = 0.630 (the band's own inner wall); patches never come "
         "inside 0.732. Everything lives in z -0.139..+0.139, i.e. the 0.26-tall band plus "
         "the <=0.01 lip where a patch wraps over an edge. No yaw offset is required on "
         "install - the pattern is asymmetric on purpose and reads the same from any side.")

# ---------------------------------------------------------------- palette
C_OLIVE = "4a5d32"         # base band - the mid value everything else is judged against
C_DARK = "2f3a22"          # darkest blotch, reads as the shadow shape
C_SAGE = "6b7a44"          # light sage, one step up in value from the olive
C_TAN = "7a6a45"           # warm tan, the lightest and only warm note

# ---------------------------------------------------------------- dial box
BAND_SEGS = 28             # plain ring, no bulge (224 tris)
PATCH_SEGS = 26            # ring density the arcs are cut from -> 3 or 4 facets per patch
BLOTCH_SEED = 153          # reroll the whole camo layout

PATCH_R_IN = 0.732         # buried 0.018 inside the band's outer wall - no seam, no gap
PROUD_0 = 0.014            # first patch stands this far out from R_OUT (0.75)
PROUD_STEP = 0.0008        # each later patch is a hair further out, so overlapping
                           # patches never end up coplanar (no z-fighting)

ARC_MIN, ARC_MAX = 28.0, 62.0      # blotch width in degrees
SPIN = 8.0                 # jitter on each blotch's centre angle, +/- degrees
H_MIN, H_MAX = 0.080, 0.215        # blotch height in studs (band is 0.26 tall)
H_FLOAT_MAX = 0.175        # a blotch that touches neither edge is capped shorter
LIP_MIN, LIP_MAX = 0.003, 0.010    # how far a blotch wraps over the edge it hugs
INSET = 0.014              # olive left showing above/below a floating blotch

# Which colour each blotch is, walking round the band.  Fixed rather than random so all
# three colours stay spread out instead of clumping into one quadrant.
ORDER = ["dark", "sage", "tan", "dark", "tan", "sage", "dark", "sage",
         "tan", "sage", "dark", "tan", "dark", "sage", "tan"]
# ...and where each one sits vertically: "top" and "bot" spill over that edge of the band,
# "mid" floats clear of both.  Each colour gets a mix of all three.
MODES = ["top", "bot", "mid", "bot", "top", "top", "mid", "mid",
         "bot", "bot", "top", "mid", "bot", "top", "top"]

KEYS = ("dark", "sage", "tan")
HEX = {"dark": C_DARK, "sage": C_SAGE, "tan": C_TAN}
PART = {"dark": "PatchesDark", "sage": "PatchesSage", "tan": "PatchesTan"}


def _blotches(H):
    """Deterministic camo layout: (colour_key, center_deg, arc_deg, z0, z1, r_out).

    Sizes and angles come from one seeded RNG; the colour and the vertical mode come from
    the fixed patterns above.  Arcs are wide enough to overlap their neighbours (mean arc
    45 deg against a 24 deg spacing), which is what stops the blotches reading as evenly
    spaced dashes."""
    rng = H.random.Random(BLOTCH_SEED)
    n = len(ORDER)
    z_bot, z_top = -H.BAND_H / 2.0, H.BAND_H / 2.0          # -0.13 .. +0.13
    out = []
    for i in range(n):
        center = i * (360.0 / n) + rng.uniform(-SPIN, SPIN)
        arc = rng.uniform(ARC_MIN, ARC_MAX)
        h = rng.uniform(H_MIN, H_MAX)
        mode = MODES[i]
        if mode == "top":                                   # wraps over the top edge
            z1 = z_top + rng.uniform(LIP_MIN, LIP_MAX)
            z0 = z1 - h
        elif mode == "bot":                                 # wraps under the bottom edge
            z0 = z_bot - rng.uniform(LIP_MIN, LIP_MAX)
            z1 = z0 + h
        else:                                               # floats clear of both edges
            h = min(h, H_FLOAT_MAX)
            z0 = rng.uniform(z_bot + INSET, z_top - h - INSET)
            z1 = z0 + h
        out.append((ORDER[i], center, arc, z0, z1,
                    H.R_OUT + PROUD_0 + PROUD_STEP * i))
    return out


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    # ---- 1. the base band: plain olive ring, 0.63 -> 0.75, 0.26 tall.
    # No bulge on purpose: the blotches sit at a fixed radius and have to stay proud of
    # the band at every height, and a mid-height bulge would eat them.
    bm = bmesh.new()
    H.band(bm, segs=BAND_SEGS, bulge=0.0)
    H.new_obj("Band", bm, c, C_OLIVE, rbx_material="Fabric", roughness=0.92)

    # ---- 2-4. the camo, one bmesh (one MeshPart) per overlay colour.
    # Each blotch is an arc of band() at a slightly larger radius: it follows the ring's
    # curve exactly, its inner wall is buried inside the olive so no seam shows, and its
    # end caps close the arc off.
    bms = {k: bmesh.new() for k in KEYS}
    for key, center, arc, z0, z1, r_out in _blotches(H):
        H.band(bms[key], r_in=PATCH_R_IN, r_out=r_out, z0=z0, z1=z1,
               segs=PATCH_SEGS, arc_deg=arc, center_deg=center)
    for key in KEYS:
        H.new_obj(PART[key], bms[key], c, HEX[key], rbx_material="Fabric", roughness=0.92)

    return c


# ---------------------------------------------------------------- parts / budget
# Part          Colour   Material  Pieces        Tris
# Band          4a5d32   Fabric    1 ring         224   (28 segs x 4 quads)
# PatchesDark   2f3a22   Fabric    5 blotches     156   (arcs of 3-4 facets: 8n + 4 each)
# PatchesSage   6b7a44   Fabric    5 blotches     156
# PatchesTan    7a6a45   Fabric    5 blotches     156
#                                  TOTAL          692   of an 800 budget
#
# Layout at BLOTCH_SEED = 153, centres in degrees (0 = forehead, +ve to the wearer's left):
#   dark  8 / 69 / 142 / 235 / 287    sage  30 / 121 / 176 / 215 / 311
#   tan  56 / 101 / 187 / 272 / 339   - arcs 30-58 deg wide, so every neighbour overlaps
#   and there is no angle where bare olive rings all the way round.
#
# Fit: tightest radius anywhere = 0.630, the band's own inner wall (exactly the head line);
# the blotches never come inside 0.732 and reach out to 0.775 at most. Vertical extent
# z -0.139 .. +0.139: the band is -0.13..+0.13 and ten of the fifteen blotches wrap 0.003
# -0.010 over one edge, which is what keeps the top and bottom lines irregular.
# Proudness check: a blotch's outer face is 26-sided like the band, so its shallowest point
# (a facet centre, at most a 15.9 deg step) still sits 0.0076 outside the band's widest
# point - it can never sink into the olive at any angle.
