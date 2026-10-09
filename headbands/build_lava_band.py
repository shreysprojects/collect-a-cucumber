"""Tier 11 - Lava Band: obsidian chunks ringing a glowing lava core, dark diamond emblem."""
import bmesh

COLLECTION = "LavaBand"
TIER = 11
DISPLAY_NAME = "Lava Band"
NOTES = (
    "The glowing ring IS the band - there is no cloth/plastic band underneath. "
    "'Lava' and 'HotCore' MUST stay Material=Neon (and should keep a high-ish "
    "Color brightness) or the cracks between the rock chunks go dead. "
    "The rocks are 16 separate chunks left with real gaps between them; the gaps are "
    "not modelled, they are just holes in the rock ring that let the neon ring show "
    "through, so never weld/merge the Rocks mesh onto the Lava mesh. "
    "Tightest radius is 0.64 (inner wall of Lava); rock chunks never come inside 0.71. "
    "Z spans -0.235 (underglow lip) to +0.31 (emblem top point)."
)

# ---------------------------------------------------------------- fit constants
R_LAVA_IN = 0.64          # inner wall of the whole accessory - the head clearance number
R_LAVA_OUT = 0.745        # outer wall of the glowing core ring
Z_LAVA_BOT = -0.155
Z_LAVA_TOP = 0.195

R_CHUNK = 0.795           # radial centre of every obsidian chunk
N_CHUNK = 16              # chunks round the ring (brief: 14-20)

SEED = 1121


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    rng = H.random.Random(SEED)          # headbandlib re-exports `random`

    def diamond(bm, half_w, half_h, y, z, thick):
        """A flat diamond plate standing in the XZ plane at the FRONT, faces +Y.

        rot_euler(90,0,0) sends the profile's local +Y to world +Z (up) and its
        extrusion axis (local +Z) to world -Y, so z0..z1 becomes a thickness in Y
        centred on `y`."""
        pts = [(0.0, half_h), (half_w, 0.0), (0.0, -half_h), (-half_w, 0.0)]
        m = H.Matrix.Translation((0.0, y, z)) @ H.rot_euler(90, 0, 0)
        return H.prism(bm, pts, -thick / 2.0, thick / 2.0, matrix=m)

    # ------------------------------------------------------------------ LAVA
    # The continuous neon ring that the rock chunks sit ON TOP OF, at a smaller
    # radius than they are - so every gap in the rock reads as a glowing crack with
    # no crack geometry at all.  It is also the structural ring of the headband.
    bm = bmesh.new()
    H.band(bm, r_in=R_LAVA_IN, r_out=R_LAVA_OUT,
           z0=Z_LAVA_BOT, z1=Z_LAVA_TOP, segs=20)                 # 160 tris
    # underglow: a thin flange tucked under the rock overhang (rock reaches ~0.88,
    # this stops at 0.82) so it lights the underside of the band.
    H.stripe(bm, R_LAVA_IN, 0.82, -0.235, -0.145, segs=16)        # 128 tris
    H.new_obj("Lava", bm, c, "ff5a1a", rbx_material="Neon")

    # ------------------------------------------------------------- HOT CORE
    # A hotter, brighter band a hair proud of the lava ring (0.755 vs 0.745) sitting
    # at mid height, so the middle of every crack is the brightest part of it.
    # Everywhere else it is buried: chunk surfaces reach in to r 0.71, well inside it.
    bm = bmesh.new()
    H.stripe(bm, 0.71, 0.755, -0.045, 0.055, segs=16)             # 128 tris
    diamond(bm, 0.200, 0.265, 0.885, 0.045, 0.10)                 # emblem outline, 12
    diamond(bm, 0.032, 0.105, 0.978, 0.045, 0.04)                 # slit in the emblem, 12
    H.new_obj("HotCore", bm, c, "ffb347", rbx_material="Neon")

    # ---------------------------------------------------------------- ROCKS
    # 16 angular chunks, evenly spaced (0.314 studs centre-to-centre) but seeded in
    # size and rotation.  Each ends up ~0.23 wide, so 0.050-0.098 studs of gap always
    # survives between neighbours - those gaps ARE the cracks, no crack geometry.
    # subdiv=1 icosphere = a 20-face icosahedron, i.e. genuinely faceted obsidian.
    bm = bmesh.new()
    step = 360.0 / N_CHUNK
    for i in range(N_CHUNK):
        a = i * step
        s = rng.uniform(0.86, 1.10)
        sx = 0.118 * s                            # tangential semi-axis
        sy = 0.065 * s * rng.uniform(0.90, 1.15)  # radial semi-axis
        sz = 0.100 * s * rng.uniform(0.85, 1.12)  # vertical semi-axis
        dz = rng.uniform(-0.022, 0.022)
        rot = H.face_out(a) @ H.rot_euler(rng.uniform(-12, 12),    # tip
                                          rng.uniform(-20, 20),    # roll
                                          rng.uniform(-15, 15))    # yaw
        H.rock(bm, H.on_ring(R_CHUNK, a, dz), 1.0, seed=200 + i,
               jitter=0.16, subdiv=1, scale=(sx, sy, sz), rot=rot)  # 20 tris each
    H.new_obj("Rocks", bm, c, "2a2529", rbx_material="Slate")

    # ----------------------------------------------------------- ROCK CHIPS
    # Lighter chips wedged onto the upper-outer shoulder of seven of the chunks, so
    # the rock ring has a lit edge instead of reading as one flat black mass.  They
    # sit ON chunks (never in the gaps) so no crack gets plugged.
    bm = bmesh.new()
    for i in (2, 4, 6, 8, 10, 12, 14):
        a = i * step + rng.uniform(-8.0, 8.0)
        r = 0.795 + rng.uniform(-0.010, 0.030)
        z = 0.100 + rng.uniform(-0.025, 0.025)
        s = rng.uniform(0.80, 1.20)
        rot = H.face_out(a) @ H.rot_euler(rng.uniform(-18, 18),
                                          rng.uniform(-25, 25),
                                          rng.uniform(-25, 25))
        H.rock(bm, H.on_ring(r, a, z), 1.0, seed=400 + i, jitter=0.18, subdiv=1,
               scale=(0.062 * s, 0.048 * s, 0.052 * s), rot=rot)    # 20 tris each
    H.new_obj("RockChips", bm, c, "4a4045", rbx_material="Slate")

    # --------------------------------------------------------------- EMBLEM
    # Dark diamond plate at angle 0 (the forehead), sitting 0.035 proud of the neon
    # outline so the outline shows as a glowing border all the way round it.
    bm = bmesh.new()
    diamond(bm, 0.145, 0.205, 0.925, 0.045, 0.09)                  # 12 tris
    H.new_obj("Emblem", bm, c, "1a1518", rbx_material="Slate")

    return c


# ---------------------------------------------------------------------------
# PARTS                       COLOUR    MATERIAL   TRIS
#   Lava        core ring + underglow flange
#                             ff5a1a    Neon        288   (160 + 128)
#   HotCore     mid stripe + emblem outline + emblem slit
#                             ffb347    Neon        152   (128 + 12 + 12)
#   Rocks       16 obsidian chunks
#                             2a2529    Slate       320   (16 x 20)
#   RockChips   7 lit shoulder chips
#                             4a4045    Slate       140   (7 x 20)
#   Emblem      dark diamond plate
#                             1a1518    Slate        12
#                                       TOTAL       912   (budget 1100)
#
# FIT (traced vertex-by-vertex over every seeded chunk, not estimated):
#      min radius 0.640  = Lava inner wall          (limit 0.630)
#      rocks       0.710 .. 0.885   chips 0.737 .. 0.876   emblems 0.835 .. 0.999
#      max radius  0.999 = emblem slit tip          (limit 1.150)
#      z          -0.235 .. +0.310                  (limit -0.35 .. +0.60)
#      rock-to-rock gaps 0.050 .. 0.098 studs - the glowing cracks.
# ---------------------------------------------------------------------------
