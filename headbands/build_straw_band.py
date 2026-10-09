"""Tier 5 headband: a woven straw band with loose straw spikes round its top edge."""
import bmesh
import math

COLLECTION = "StrawBand"
TIER = 5
DISPLAY_NAME = "Straw Band"
NOTES = (
    "Three MeshParts, one per colour, exactly as the reference sheet reads: Weave "
    "(shadowed straw b8873c - the core ring PLUS every recessed checker cell), Strands "
    "(light straw d9b063 - the 16 proud cells that pass over the top) and Spikes "
    "(e8c87a). All three are Enum.Material.Sand. The weave is a two-row basket checker: "
    "16 cells per row on the same angular grid with the parity flipped between rows, so a "
    "light cell in the lower row always sits under a shadowed cell in the upper one. The "
    "proud cells stand up to 0.09 out from the core ring and the recessed ones 0.05, "
    "so the checker shades as well as reading in value, and a "
    "2-degree shadow gap is left between neighbouring cells so the dark core ring shows "
    "through as the gap between strands. The core ring is also 0.018 taller than the "
    "tallest cell at both rims, which gives the band a bound dark edge for free. "
    "The band proper lives in z -0.150 .. +0.150 and radius 0.642 .. 0.812. Only the 20 "
    "straw spikes leave that envelope: they root INSIDE the core ring (z 0.06..0.12, "
    "radius 0.688..0.714, so no spike floats) and reach z +0.227 at most, 0.087..0.149 "
    "long. Give the accessory ~0.24 of headroom above the band when it is worn. Tightest "
    "vertex radius anywhere is 0.642 - 0.042 of clearance over a default R15 head and "
    "0.012 outside H.R_IN. No moving parts, no centrepiece, nothing sinks below the band."
)

# ------------------------------------------------------------------ weave geometry
NCELL = 16                    # checker cells per row
CELL = 360.0 / NCELL          # 22.5 deg of ring per cell
HALF = CELL * 0.455           # half arc width -> ~2 deg of shadow gap between neighbours

R_IN_RING = 0.642             # core ring inner wall - 0.012 outside H.R_IN
R_OUT_RING = 0.712            # core ring outer wall (jitter/bulge push it to ~0.730)
Z_RING = 0.150                # core ring half height

R_CELL_IN = 0.680             # every cell starts buried inside the core ring
R_LIGHT = 0.805               # proud strand outer face
R_SHADOW = 0.762              # recessed strand outer face

# (light z0, light z1, shadow z0, shadow z1, cell parity that gets the LIGHT strand).
# The two rows share one angular grid and flip parity, which is what makes the checker;
# the 0.004 gaps at z=0 between the rows let the dark core ring through as a seam.
ROWS = (
    (-0.132, 0.004, -0.120, -0.008, 0),
    (-0.004, 0.132, 0.008, 0.120, 1),
)

# ------------------------------------------------------------------ spikes
N_SPIKE = 20
SPIKE_R = 0.698               # root radius, well inside the core ring's outer wall
SPIKE_Z = 0.090               # root height, well inside the core ring's top


def _cell(H, bm, center_deg, r_out, z0, z1):
    """One woven cell: a 4-vert annular sector extruded z0..z1, 12 tris.

    Two angular samples is deliberate - over a 20-degree arc the chord sags only 0.013
    from the true circle, which is invisible at accessory scale, and it costs 12 tris
    where a band() arc costs 28 (band() floors its segment count at 3)."""
    a0 = math.radians(center_deg - HALF)
    a1 = math.radians(center_deg + HALF)
    pts = [(math.sin(a0) * R_CELL_IN, math.cos(a0) * R_CELL_IN),
           (math.sin(a1) * R_CELL_IN, math.cos(a1) * R_CELL_IN),
           (math.sin(a1) * r_out, math.cos(a1) * r_out),
           (math.sin(a0) * r_out, math.cos(a0) * r_out)]
    return H.prism(bm, pts, z0, z1)


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    # --- shadowed straw: core ring + every recessed cell ------------------------------
    # The core ring does three jobs at once, which is why it is worth its 240 tris: it is
    # the solid the cells are pegged into, it is the dark gap seen between them, and its
    # extra 0.018 of height at each rim is the band's bound edge. jitter roughens the
    # outer wall per segment so the straw never reads as machined tube.
    bm = bmesh.new()
    H.band(bm, r_in=R_IN_RING, r_out=R_OUT_RING, z0=-Z_RING, z1=Z_RING, segs=20,
           bulge=0.010, seed=17, jitter=0.008)
    rng = H.random.Random(5307)
    for _lz0, _lz1, sz0, sz1, parity in ROWS:
        for i in range(NCELL):
            if i % 2 == parity:
                continue
            _cell(H, bm, i * CELL + rng.uniform(-0.5, 0.5),
                  R_SHADOW + rng.uniform(-0.006, 0.006), sz0, sz1)
    H.new_obj("Weave", bm, c, "b8873c", rbx_material="Sand", roughness=0.92)

    # --- light straw: the strands that pass OVER --------------------------------------
    # Same grid, opposite parity, taller and 0.043 further out than their shadowed
    # neighbours. Value carries the checker; the radius step only adds the shading.
    bm = bmesh.new()
    rng = H.random.Random(4211)
    for lz0, lz1, _sz0, _sz1, parity in ROWS:
        for i in range(NCELL):
            if i % 2 != parity:
                continue
            _cell(H, bm, i * CELL + rng.uniform(-0.5, 0.5),
                  R_LIGHT + rng.uniform(-0.007, 0.007), lz0, lz1)
    H.new_obj("Strands", bm, c, "d9b063", rbx_material="Sand", roughness=0.90)

    # --- straw spikes -----------------------------------------------------------------
    # 20 tapered 4-sided cones round the top edge. Each root sits INSIDE the core ring so
    # nothing floats, and the tip is placed by walking outward along the ring: the tip's
    # ring angle is offset from the root's by `lean`, which is what gives each straw its
    # sideways kick without any extra matrix work. `up` splits the length between rise and
    # reach, so short stiff stubs and long lazy ones both come out of one seeded pass.
    bm = bmesh.new()
    rng = H.random.Random(88)
    for a in H.ring_angles(N_SPIKE, 360.0, 9.0):
        aj = a + rng.uniform(-6.0, 6.0)
        rb = SPIKE_R + rng.uniform(-0.010, 0.016)
        zb = SPIKE_Z + rng.uniform(-0.030, 0.030)
        length = rng.uniform(0.085, 0.155)
        up = rng.uniform(0.52, 0.94)
        out = math.sqrt(max(0.04, 1.0 - up * up))
        lean = rng.uniform(-18.0, 18.0)
        base = H.on_ring(rb, aj, zb)
        tip = H.on_ring(rb + out * length, aj + lean, zb + up * length)
        H.cone(bm, base, tip, rng.uniform(0.021, 0.031), 0.0, segs=4)
    H.new_obj("Spikes", bm, c, "e8c87a", rbx_material="Sand", roughness=0.88)

    return c


# ---------------------------------------------------------------------------------------
# PARTS                                       COLOUR   MATERIAL  TRIS
#   Weave    core ring, 20 segs + bulge       b8873c   Sand       240  (20 x 6 quads)
#            16 recessed checker cells        b8873c   Sand       192  (16 x 12)
#   Strands  16 proud checker cells           d9b063   Sand       192  (16 x 12)
#   Spikes   20 x 4-sided tapered cone        e8c87a   Sand       120  (20 x 6)
#                                                               -----
#                                                                 744  of a 900 budget
#
# FIT   min radius 0.642  core ring inner wall (cells start at 0.680; the widest spike
#                         root ring only reaches inward to 0.662)
#       max radius 0.812  proud strands 0.812, farthest spike tip 0.812 as well
#       z range   -0.150 .. +0.227  band is -0.150..+0.150, only the spikes go above
#       verified by tracing every vertex through a stub of the lib before shipping
# ---------------------------------------------------------------------------------------
