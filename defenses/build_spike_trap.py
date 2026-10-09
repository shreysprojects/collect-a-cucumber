"""Spike trap - an 8 x 8 pit ringed by a raised yellow/black hazard kerb, with nine big
steel-headed impaling spikes rising out of it.  Modelled in the EXTENDED (deployed) pose."""
import bmesh
from mathutils import Matrix

COLLECTION = "SpikeTrap"

NOTES = (
    "Floor trap, 8 x 8 studs, x/y in [-4, 4], modelled EXTENDED (spikes up) so the render "
    "shows the danger. Three forms only: a dark plate, a RAISED hazard kerb ringing it, and "
    "nine large spikes in a black pit. "
    "The kerb is a real 0.45-stud-proud lip (top z = 0.90) rather than a flat decal, so the "
    "yellow/black warning is legible EDGE-ON at player eye height and not just from above; "
    "it is trivially steppable (a Roblox humanoid clears ~2 studs). Walkable surface inside "
    "the kerb is the pit pad at z = 0.52. Nothing dips below z = 0 in this pose. "
    "Spikes: 3 x 3 staggered, 1.8 pitch, heights falling off with distance from centre so the "
    "bed reads as a toothed mound, not a pincushion - tips run z 1.90 (outer) to 2.97 (centre), "
    "i.e. waist-to-chest on a 5-stud avatar. Each spike is a flared Danger-red socket (bottom "
    "37% of its length) carrying a Steel-bright needle (top 63%); because a cone's silhouette "
    "area goes as the square of the height fraction, that split puts ~38% of each spike's ink "
    "in the bright steel - enough for the head to read as a polished point instead of a speck. "
    "METALLIC IS DELIBERATELY LOW (<= 0.15) on every part. These previews light a dark world "
    "with two suns, so a high-metallic surface mirrors that dark world and renders near-black: "
    "at metallic 0.9 the d5dbe4 tips measured luminance 0.40 against a 0.44 sky and vanished. "
    "The rbx_material custom prop still says Metal/DiamondPlate, which is what carries the "
    "look into Roblox - the Blender metallic value only affects these renders. "
    "MOVING PARTS are exactly the two objects whose names start with 'Spikes' (SpikesBed, "
    "SpikesTips); BasePlate / DeckPit / HazardKerb / HazardKerbDark never move. STATES is the "
    "z offset applied to the Spikes* parts: Retracted = -2.63 drops the tallest tip from "
    "z 2.9726 to 0.3426 - below the pit pad (0.52) and below the deck top (0.45), so nothing "
    "pokes through - and sinks the spike roots to z = -2.17. That is below the floor on "
    "purpose; the installer should either let them clip or hide the shaft. "
    "Spike lengths carry a subtractive seeded jitter (D.random.Random(7)) so no two match, and "
    "the same rng yaws each 4-sided spike so the facets do not all line up. Jitter only ever "
    "SHORTENS a spike, which is what makes the Retracted number provably safe. "
    "The rng comes off the lib as D.random to keep this module's only import as bmesh + "
    "mathutils.Matrix; bpy is never imported and bpy.ops is never called."
)

STATES = {"Extended": 0.0, "Retracted": -2.63}

SEED = 7

# ---- deck constants (studs) ------------------------------------------------
HALF = 4.00           # plate half-extent -> 8 x 8 footprint
DECK_Z = 0.45         # top of the plate slab
BEVEL = 0.15          # chamfer; makes the flat top face span exactly +/- 3.85
FLAT = HALF - BEVEL   # 3.85 - outer edge of the kerb, where the top chamfer begins
BAND_IN = 2.90        # inner face of the kerb = the lip of the pit

# ---- the raised hazard kerb ------------------------------------------------
KERB_Z0 = 0.38        # buried 0.07 inside the plate: no coplanar faces with its top
KERB_TOP = 0.90       # 0.45 proud of the deck - a shin-high warning lip
KERB_SEGS = 7         # blocks per side; even indices yellow -> yellow at both ends
KERB_EPS = 0.012      # dark blocks are grown by this so they OVERLAP the yellow ring
                      # rather than butting it (butting coplanar faces would z-fight)

# ---- the pit the spikes rise out of ----------------------------------------
PIT_HALF = 2.96       # runs UNDER the kerb (2.90) so their faces never coincide
PIT_Z0 = 0.42
PIT_TOP = 0.52

# ---- spike bed constants ---------------------------------------------------
GRID_N = 3
PITCH = 1.80
GRID_CX = -PITCH / 4.0   # -0.45: re-centres the staggered odd row about x = 0
R_BASE = 0.52            # circumradius at the root - a chunky flared socket
R_SPLIT = 0.30           # where the red socket hands over to the steel needle
Z_ROOT = 0.46            # roots buried inside the pit pad (0.42 .. 0.52)
H_HIGH = 2.70            # length at the centre of the bed
H_LOW = 1.50             # length at the far corner
H_JITTER = 0.14          # SUBTRACTIVE only, so H_HIGH stays a hard ceiling
SPLIT = 0.37             # fraction of the length that is the red socket


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    rng = D.random.Random(SEED)

    # --- 1. base plate: the chunky dark slab the whole trap sits in -----------
    bm = bmesh.new()
    D.beveled_box(bm, (-HALF, -HALF, 0.0), (HALF, HALF, DECK_Z), bevel=BEVEL)
    D.new_obj("BasePlate", bm, c, "3b4350", rbx_material="DiamondPlate",
              metallic=0.15, roughness=0.55)

    # --- 2. the black pit floor; wider than the kerb bore so it tucks under it -
    bm = bmesh.new()
    D.box(bm, (-PIT_HALF, -PIT_HALF, PIT_Z0), (PIT_HALF, PIT_HALF, PIT_TOP))
    D.new_obj("DeckPit", bm, c, "2a2d33", rbx_material="SmoothPlastic", roughness=0.85)

    # --- 3. hazard kerb: a continuous yellow ring, raised into a real lip ------
    bm = bmesh.new()
    D.box(bm, (-FLAT, -FLAT, KERB_Z0), (FLAT, -BAND_IN, KERB_TOP))          # south
    D.box(bm, (-FLAT, BAND_IN, KERB_Z0), (FLAT, FLAT, KERB_TOP))            # north
    D.box(bm, (-FLAT, -BAND_IN, KERB_Z0), (-BAND_IN, BAND_IN, KERB_TOP))    # west
    D.box(bm, (BAND_IN, -BAND_IN, KERB_Z0), (FLAT, BAND_IN, KERB_TOP))      # east
    D.new_obj("HazardKerb", bm, c, "f2c13d", rbx_material="SmoothPlastic", roughness=0.60)

    # --- 4. the black half of the stripe: blocks sunk INTO the yellow ring -----
    #     every dark block is grown by KERB_EPS on all six sides, so it swallows the
    #     yellow locally instead of sharing a face with it.
    bm = bmesh.new()
    e = KERB_EPS
    z0, z1 = KERB_Z0 - e, KERB_TOP + e
    step = (2.0 * BAND_IN) / KERB_SEGS                  # 0.828571 per block
    for i in range(KERB_SEGS):
        if i % 2 == 0:                                  # even blocks stay yellow
            continue
        a = -BAND_IN + i * step
        b = -BAND_IN + (i + 1) * step
        D.box(bm, (a, -FLAT - e, z0), (b, -BAND_IN + e, z1))                # south
        D.box(bm, (a, BAND_IN - e, z0), (b, FLAT + e, z1))                  # north
        D.box(bm, (-FLAT - e, a, z0), (-BAND_IN + e, b, z1))                # west
        D.box(bm, (BAND_IN - e, a, z0), (FLAT + e, b, z1))                  # east
    for sx in (-1.0, 1.0):                              # solid dark corner blocks
        for sy in (-1.0, 1.0):
            x0, x1 = sorted((sx * (BAND_IN - e), sx * (FLAT + e)))
            y0, y1 = sorted((sy * (BAND_IN - e), sy * (FLAT + e)))
            D.box(bm, (x0, y0, z0), (x1, y1, z1))
    D.new_obj("HazardKerbDark", bm, c, "2a2d33", rbx_material="SmoothPlastic", roughness=0.70)

    # --- 5/6. the spike bed: nine big spikes, tallest in the middle -----------
    cells = D.grid_positions(GRID_N, GRID_N, PITCH, PITCH,
                             center=(GRID_CX, 0.0), stagger=True)
    rmax = max((x * x + y * y) ** 0.5 for (x, y) in cells)   # 2.8810 at (-2.25, +-1.8)

    bed = bmesh.new()
    tips = bmesh.new()
    for (x, y) in cells:
        r = (x * x + y * y) ** 0.5
        h = H_HIGH - (H_HIGH - H_LOW) * (r / rmax) - rng.uniform(0.0, H_JITTER)
        spin = (Matrix.Translation((x, y, 0.0))
                @ D.rot_euler(rz=rng.uniform(-45.0, 45.0))
                @ Matrix.Translation((-x, -y, 0.0)))
        z_split = Z_ROOT + SPLIT * h
        vs = D.spike(bed, (x, y, Z_ROOT), (x, y, z_split), R_BASE, segs=4, tip_r=R_SPLIT)
        D.xform(bed, vs, spin)
        vs = D.spike(tips, (x, y, z_split), (x, y, Z_ROOT + h), R_SPLIT, segs=4, tip_r=0.0)
        D.xform(tips, vs, spin)
    D.new_obj("SpikesBed", bed, c, "d9443c", rbx_material="Metal",
              metallic=0.12, roughness=0.45)
    D.new_obj("SpikesTips", tips, c, "d5dbe4", rbx_material="Metal",
              metallic=0.10, roughness=0.34)

    return c


# ---------------------------------------------------------------------------
# PART AUDIT                        colour role                    tris
# ---------------------------------------------------------------------------
# BasePlate       8x8x0.45 beveled  Metal dark   3b4350 (v .26)      44
# DeckPit         5.92 sq pad       Rubber black 2a2d33 (v .18)      12
# HazardKerb      4 ring boxes      Warning yel. f2c13d (v .75)      48
# HazardKerbDark  12 stripe blocks  Rubber black 2a2d33 (v .18)     192
#                 + 4 corners (x12)
# SpikesBed       9 4-sided frusta  Danger red   d9443c (v .40)     108
# SpikesTips      9 4-sided cones   Steel bright d5dbe4 (v .85)      54
# ---------------------------------------------------------------------------
# TOTAL           6 parts                                           458   (budget 900)
#
# Bounds: x,y in [-4.00, 4.00]; z in [0.00, 2.9726].  min_z = 0.0, nothing floats.
#
# SPIKE HEIGHTS traced by hand (rmax = 2.88101, jitter subtracted on top):
#   r 0.450 -> h 2.5126 -> tip 2.9726   (0.45, 0)          the peak
#   r 1.350 -> h 2.1377 -> tip 2.5977   (-1.35, 0)
#   r 1.855 -> h 1.9272 -> tip 2.3872   (-0.45, +-1.8)
#   r 2.250 -> h 1.7628 -> tip 2.2228   (2.25, 0) (1.35, +-1.8)
#   r 2.881 -> h 1.5000 -> tip 1.9600   (-2.25, +-1.8)     the outer corners
# RETRACTED = -2.63: 2.9726 - 2.63 = 0.3426, which is 0.11 under the deck top (0.45)
#   and 0.18 under the pit pad (0.52).  Because H_JITTER only ever subtracts, 2.9726 is
#   a hard ceiling, so no seed can push a tip through the deck.  Roots land at -2.17.
#
# CLEARANCES (circumradius r(z) = 0.52 - 0.22 * (z - 0.46)/(SPLIT*h)):
#   widest visible section is at the pit pad, z 0.52 -> r <= 0.506.
#   Outermost spikes sit at |x| = 2.25, |y| = 1.8; swept over z 0.52 .. 0.90 the worst
#   reach is 2.750 vs the kerb bore at 2.90 - 0.150 clear.  By the kerb top those spikes
#   are down to r ~0.37.  Nothing touches the kerb, at any yaw.
#   Nearest spike centres are 1.80 apart (in row) / 2.01 (diagonal) against a maximum
#   corner-to-corner width of 1.012, so ~0.79 studs of daylight between neighbours -
#   the gaps are what let you count individual teeth instead of reading a brush.
