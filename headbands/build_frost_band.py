"""Tier 9 - Frost Band: a blue ice ring growing pale crystal shards, snowflake on the brow."""
import bmesh
import math

COLLECTION = "FrostBand"
TIER = 9
DISPLAY_NAME = "Frost Band"
NOTES = (
    "'Snowflake' is the ONLY Neon part - the four Ice parts must stay non-emissive or the "
    "flake stops reading as the hero. "
    "The flake is held off the brow by a short tapered ice stem that lives in the "
    "'Crystals' mesh (it starts buried in the band at y 0.66 and pokes 0.005 into the "
    "flake's lower arm), so Crystals and Snowflake must never be moved relative to each "
    "other. "
    "The forehead arc +-22.5 deg carries no shards on purpose - that gap is the flake's "
    "window; the small 'Frost' shards deliberately stop at +-27 deg for the same reason. "
    "Tightest radius is 0.630 (the plain band bore); everything else grows outward, widest "
    "point r 0.851 (a snowflake arm tip). Z spans -0.155 (Rim lip) to +0.410 (flake top)."
)

# ---------------------------------------------------------------- fit constants
Z_TOP = 0.130             # band top edge (H.BAND_H/2) - shard bases sit just inside it
FLAKE_Y = 0.81            # radial stand-off of the snowflake plate (band outer face 0.75)
FLAKE_Z = 0.22            # height of the flake's hub
FLAKE_R = 0.19            # arm tip radius -> the flake is 0.38 across, tip to tip

N_SHARD = 15              # big shards, at 22.5 deg steps, skipping the forehead
N_FROST = 12              # small shards, over a 306 deg arc centred on the nape

SEED_SHARD = 90901
SEED_FROST = 31771


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    def front_bias(angle_deg):
        """1.0 at the forehead, 0.0 at the nape - drives 'taller toward the front'."""
        return 0.5 * (1.0 + math.cos(math.radians(angle_deg)))

    def shard(bm, angle_deg, base_r, base_z, height, lean, twist, r_base, r_tip):
        """One tapered 5-sided ice shard rising up and outward off the top edge.

        A non-zero tip radius is what makes it read faceted rather than needle-thin;
        `twist` swings the tip a few degrees around the ring so no two lean alike."""
        a = H.on_ring(base_r, angle_deg, base_z)
        b = H.on_ring(base_r + lean, angle_deg + twist, base_z + height)
        return H.cone(bm, a, b, r_base, r_tip, segs=5)

    # -------------------------------------------------------------------- BAND
    # Plain hard-edged ring (no bulge - ice, not cloth) with a hair of radial jitter
    # so the outer wall reads chipped.  Inner wall stays exactly on R_IN = 0.63.
    bm = bmesh.new()
    H.band(bm, segs=20, bulge=0.0, seed=17, jitter=0.010)             # 160 tris
    H.new_obj("Band", bm, c, "4a9fd8", rbx_material="Ice")

    # --------------------------------------------------------------------- RIM
    # A deep-blue lip under the band.  This is the only dark value in the piece and
    # it is what lets the pale shards above it pop; r_in 0.715 keeps it buried in the
    # band even where the jitter pulls the band's outer wall in to 0.740.
    bm = bmesh.new()
    H.stripe(bm, 0.715, 0.788, -0.155, -0.075, segs=20)               # 160 tris
    H.new_obj("Rim", bm, c, "2f6fa8", rbx_material="Ice")

    # ---------------------------------------------------------------- CRYSTALS
    # 15 big shards at 22.5 deg steps starting at 22.5, so nothing lands at angle 0.
    # Base radius 0.705..0.735 with a 0.048 base radius -> the tightest shard vertex
    # is r 0.657, and the base disc is inside the band solid so nothing floats.
    # Worst-case tip is r 0.802 at 16.5 deg off the front, i.e. |x| >= 0.228, which
    # clears the flake's 0.165 half-width with room to spare.
    bm = bmesh.new()
    rng = H.random.Random(SEED_SHARD)                # headbandlib re-exports `random`
    for i in range(1, N_SHARD + 1):
        a = 22.5 * i
        shard(bm, a,
              base_r=0.720 + rng.uniform(-0.015, 0.015),
              base_z=0.100,
              height=0.125 + 0.135 * front_bias(a) + rng.uniform(-0.015, 0.030),
              lean=0.020 + rng.uniform(0.0, 0.035),
              twist=rng.uniform(-6.0, 6.0),
              r_base=0.048, r_tip=0.012)                              # 15 x 16 tris
    # ice stem: buried in the band at y 0.66, tapering out to meet the flake's lower
    # arm at y 0.79 (the flake's back face is 0.785), rising slightly as it goes.
    H.cone(bm, (0.0, 0.660, 0.100), (0.0, FLAKE_Y - 0.020, 0.140),
           0.075, 0.045, segs=6)                                      # 20 tris
    H.new_obj("Crystals", bm, c, "a8dcf5", rbx_material="Ice")

    # ------------------------------------------------------------------- FROST
    # The second, smaller, lighter set: a low fringe of sub-shards sitting a touch
    # further out (0.723..0.747) and lower (base z 0.085) than the big ones, so it
    # reads as frost creeping up the band rather than as more crystals.  The 306 deg
    # arc leaves the forehead clear for the flake.
    bm = bmesh.new()
    rng = H.random.Random(SEED_FROST)
    for a in H.ring_angles(N_FROST, 306.0, 180.0):        # 27 .. 333 deg
        shard(bm, a,
              base_r=0.735 + rng.uniform(-0.012, 0.012),
              base_z=0.085,
              height=0.075 + 0.055 * front_bias(a) + rng.uniform(-0.010, 0.020),
              lean=0.015 + rng.uniform(0.0, 0.035),
              twist=rng.uniform(-7.0, 7.0),
              r_base=0.030, r_tip=0.008)                              # 12 x 16 tris
    H.new_obj("Frost", bm, c, "dcf1ff", rbx_material="Ice")

    # --------------------------------------------------------------- SNOWFLAKE
    # Built FLAT in a local plane (local +x = world +x, local +y = world +z, the
    # extrusion axis = thickness in y) and stood up at the front: rot_euler(90,0,0)
    # sends local +y to world +z and the extrusion axis to world -y, and face_out(0)
    # is the identity because the flake already faces +Y.
    bm = bmesh.new()
    M = H.Matrix.Translation((0.0, FLAKE_Y, FLAKE_Z)) @ H.face_out(0.0) @ H.rot_euler(90, 0, 0)

    # hub: a hexagon a touch thicker (0.066) than the arms (0.050) so the centre
    # catches its own highlight.  phase 30 deg puts a hub vertex under every arm.
    H.prism(bm, H.ngon_pts(6, 0.055, phase=math.radians(30)),
            -0.033, 0.033, matrix=M)                                  # 20 tris

    # one arm, drawn along local +x, tapering 0.052 wide at the hub to 0.026 at the tip
    arm = [(0.030, -0.026), (FLAKE_R, -0.013), (FLAKE_R, 0.013), (0.030, 0.026)]
    # the side-branches - a 0.030-wide wedge springing off each edge of the shaft at
    # ~50 deg, 0.070 long.  These are what stop the flake reading as an asterisk.
    branch_a = [(0.088, 0.010), (0.118, 0.010), (0.150, 0.062)]
    branch_b = [(0.118, -0.010), (0.088, -0.010), (0.150, -0.062)]
    for k in range(6):
        A = M @ H.rot_euler(0.0, 0.0, 30.0 + 60.0 * k)   # arms at 30,90,...,330 -> one up, one down
        H.prism(bm, arm, -0.025, 0.025, matrix=A)                     # 6 x 12 tris
        H.prism(bm, branch_a, -0.018, 0.018, matrix=A)                # 6 x  8 tris
        H.prism(bm, branch_b, -0.018, 0.018, matrix=A)                # 6 x  8 tris
    H.new_obj("Snowflake", bm, c, "e8f7ff", rbx_material="Neon")

    return c


# ---------------------------------------------------------------------------
# PARTS                          COLOUR    MATERIAL   TRIS
#   Band       jittered ice ring, 20 segs, r 0.630-0.760
#                                4a9fd8    Ice         160
#   Rim        deep-blue lip under the band, 20 segs
#                                2f6fa8    Ice         160
#   Crystals   15 big shards + the flake's ice stem
#                                a8dcf5    Ice         260   (15 x 16 + 20)
#   Frost      12 small shards, 306 deg arc round the back
#                                dcf1ff    Ice         192   (12 x 16)
#   Snowflake  hex hub + 6 arms + 12 side-branches
#                                e8f7ff    Neon        188   (20 + 6 x 28)
#                                          TOTAL       960   (budget 1000)
#
# FIT: tightest radius 0.630 - the band bore, exactly H.R_IN.  Next tightest is
#      0.657 (a big shard's base disc at base_r 0.705 less its 0.048 radius) and
#      0.660 (the stem's base disc, buried in the band).  Widest point r 0.851
#      (a snowflake arm tip at x 0.165, y 0.835).  Z spans -0.155 (Rim) to +0.410
#      (top arm of the flake); the tallest shard tip reaches +0.402.
# VALUE LADDER (luma): Rim 96 < Band 140 < Crystals 207 < Frost 236 < Snowflake 243,
#      and the Snowflake is Neon on top of that.  Frost and Crystals are the closest
#      pair (29 apart) but differ 2x in height and never share an angle.
# ---------------------------------------------------------------------------
