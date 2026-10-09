"""Round cedar hot tub: a lathed drum clad in twenty tapered staves in two wood values,
two steel hoops at different heights, a wide flat coping rim you can sit on, steaming
water over a submerged bench ring, a two-step timber stair at the +Y front and a little
black control panel with neon indicator dots parked off to one side of the rim."""
import bmesh, math, random

COLLECTION = "HotTub"
NOTES = (
    "6.40 studs across the coping rim - the two steel hoops are the widest thing on the "
    "tub at 6.52 - and 2.56 studs to the top of the rim, 3.05 to the top of the steam. "
    "The tub is a closed vessel sitting flat on z=0, nothing below the ground plane and "
    "no pit. "
    "Water surface is at z 2.25 (water_mid, transparency 0.30), 0.31 of freeboard under "
    "the rim, over a floor at z 0.28; the water disc runs out to r 2.70 so its edge is "
    "buried inside the 2.62..2.86 wall and meets the wood with no gap and no z-fight. "
    "The submerged bench ring is 1.98..2.58 out from the axis with its top at z 1.35, "
    "i.e. 0.90 under the surface - chest-deep on a seated player. The coping rim is "
    "2.62..3.20 out (0.58 wide) with its top at z 2.56 - that is the sit surface, and "
    "its inner edge is flush with the cavity wall so it never overhangs the water. "
    "The two-step stair is on the +Y face, x -1.00..1.00, treads at z 0.62 and z 1.30, "
    "reaching out to y 4.42 at the lower steel nosing, so the whole prop's footprint is "
    "about 6.52 (X) x 7.68 (Y). "
    "The control panel is deliberately OFF-AXIS at 128 deg (front, negative X = the "
    "viewer's right), with the conduit that feeds it running from the ground up the "
    "outside of the staves and a flared drain nozzle at 118 deg - the only things that "
    "break the tub's radial symmetry. "
    "Steam is three pale transparency-0.88 pancake puffs floating over the middle of the "
    "water between z 2.60 and z 3.05; they never cross the rim line and are the only "
    "geometry above the rim, so delete the Steam part if the plot needs a clean "
    "2.56-tall silhouette. "
    "Parts are merged by colour+material, so Shell also holds the coping rim and foot "
    "ring, StavesMid also holds the stair treads, StavesPale also holds the bench ring, "
    "and Steel also holds the conduit, the nozzle and the two step nosings."
)

PIVOTS = {
    "WaterSurface": (0.00, 0.00, 2.25),      # parent a splash/ripple effect here
    "RimSeatFront": (0.00, 2.91, 2.56),      # centre of the sit rim on the front arc
    "StepTop": (0.00, 3.30, 1.30),           # top tread, where a player steps up
    "PanelTop": (-1.75, 2.24, 2.90),         # face of the control panel
}

# ---------------------------------------------------------------- dimensions
R_OUT, R_IN = 2.86, 2.62          # drum outer wall / inner cavity
Z_TOP, Z_FLOOR = 2.30, 0.28       # top of the drum shell / inner floor
N_STAVE, R_STAVE = 20, 2.92       # cladding staves: count and centreline radius
Z_STAVE0, Z_STAVE1 = 0.16, 2.30
RIM_IN, RIM_OUT = 2.62, 3.20      # coping rim - inner edge flush with the cavity wall
RIM_Z0, RIM_Z1 = 2.30, 2.56
FOOT_IN, FOOT_OUT, FOOT_Z = 2.80, 3.08, 0.24
HOOP_IN, HOOP_OUT = 2.96, 3.30    # a real strap: 0.09 of bite, 0.25 standing proud
WATER_Z, WATER_R = 2.25, 2.70     # 0.31 of freeboard; the disc edge hides in the wall
BENCH_Z0, BENCH_Z1 = 1.17, 1.35   # seat top 0.90 under the surface
PANEL_DEG, CONDUIT_R = 128.0, 3.10
NOZZLE_DEG = 118.0

SEG = 16                          # segments on every body of revolution
SQ = math.sqrt(2.0)               # 4-seg lathe radius that gives a UNIT square section
PH = math.pi / 4.0                # ...phased so that square is axis-aligned


def _polar(deg, radius):
    a = math.radians(deg)
    return math.cos(a) * radius, math.sin(a) * radius


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    dark = D.C("wood_dark")
    mid = D.C("wood_mid")
    pale = D.C("wood_light")

    # ------------------------------------------------------------ shell, rim, foot
    # One hollow vessel: up the outside, across the rim, back down the inside to the
    # floor.  Dark, so the gaps between the pale staves read as shadow lines.
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 0.00), (R_OUT, 0.00), (R_OUT, Z_TOP),
                 (R_IN, Z_TOP), (R_IN, Z_FLOOR), (0.00, Z_FLOOR)], segs=SEG)
    # wide flat coping rim - the sit surface, overhanging the staves all the way round
    D.lathe(bm, [(RIM_IN, RIM_Z0), (RIM_OUT, RIM_Z0), (RIM_OUT, RIM_Z1),
                 (RIM_IN, RIM_Z1), (RIM_IN, RIM_Z0)], segs=SEG, cap=False)
    # foot ring: hides the bottom of every stave and lifts the barrel visually
    D.lathe(bm, [(FOOT_IN, 0.00), (FOOT_OUT, 0.00), (FOOT_OUT, FOOT_Z),
                 (FOOT_IN, FOOT_Z)], segs=SEG, cap=False)
    D.new_obj("Shell", bm, c, dark, rbx_material="Wood", roughness=0.82)

    # ------------------------------------------------------------ cedar staves
    # Each stave is a 4-segment lathe (a square post) squashed to a thin plank by the
    # matrix' scale and tapered towards the rim by the profile.  Alternating values so
    # the barrel reads as planks rather than a smooth drum.
    rng = random.Random(11)
    bm_mid, bm_pale = bmesh.new(), bmesh.new()
    for i, (px, py) in enumerate(D.ring_positions(N_STAVE, R_STAVE)):
        ang = math.degrees(math.atan2(py, px))
        half_t = 0.13 * rng.uniform(0.92, 1.08)          # radial half-thickness
        half_w = 0.40 * rng.uniform(0.94, 1.05)          # tangential half-width
        taper = rng.uniform(0.83, 0.91)                  # shrink at the top
        D.lathe(bm_mid if i % 2 == 0 else bm_pale,
                [(SQ, Z_STAVE0), (SQ * taper, Z_STAVE1)], segs=4, phase=PH,
                matrix=D.place((px, py, 0.0), D.rot_euler(rz=ang),
                               scale=(half_t, half_w, 1.0)))

    # two-step stair on the +Y face, merged into the mid-value cedar
    D.beveled_box(bm_mid, (-1.00, 2.95, 0.00), (1.00, 3.66, 1.30), bevel=0.08)
    D.beveled_box(bm_mid, (-1.00, 3.64, 0.00), (1.00, 4.32, 0.62), bevel=0.08)
    D.new_obj("StavesMid", bm_mid, c, mid, rbx_material="Wood", roughness=0.80)

    # submerged bench ring, merged into the pale cedar so it stays readable under water
    D.lathe(bm_pale, [(2.58, BENCH_Z1), (1.98, BENCH_Z1), (1.98, BENCH_Z0),
                      (2.58, BENCH_Z0)], segs=SEG, cap=False)
    D.new_obj("StavesPale", bm_pale, c, pale, rbx_material="Wood", roughness=0.78)

    # ------------------------------------------------------------ steelwork
    # The hoops are lathed at N_STAVE segments, half a segment out of phase with the
    # staves, so every flat of the strap sits square on one plank instead of beating
    # against the plank edges.  They bite 0.09 into the cladding and stand 0.25 proud.
    bm = bmesh.new()
    for (z0, z1) in ((0.62, 0.92), (1.74, 2.00)):        # two hoops, unequal widths
        D.lathe(bm, [(HOOP_IN, z0), (HOOP_OUT, z0), (HOOP_OUT, z1), (HOOP_IN, z1)],
                segs=N_STAVE, phase=math.pi / N_STAVE, cap=False)
    cx, cy = _polar(PANEL_DEG, CONDUIT_R)                # conduit up to the panel
    D.cyl(bm, (cx, cy, 0.00), (cx, cy, 2.58), 0.09, segs=6)
    nx0, ny0 = _polar(NOZZLE_DEG, 2.96)                  # flared drain nozzle
    nx1, ny1 = _polar(NOZZLE_DEG, 3.38)
    D.cyl(bm, (nx0, ny0, 0.42), (nx1, ny1, 0.42), 0.10, segs=6, r2=0.16)
    # Step nosings wrap the front top edge of each tread - no face of the nosing is
    # near-coplanar with a tread face, and they run 0.04 proud on both ends so their
    # sides clear the tread sides too.
    D.box(bm, (-1.04, 3.50, 1.16), (1.04, 3.74, 1.36))   # step nosings
    D.box(bm, (-1.04, 4.18, 0.48), (1.04, 4.42, 0.68))
    D.new_obj("Steel", bm, c, D.C("metal_mid"), rbx_material="Metal",
              metallic=0.62, roughness=0.34)

    # ------------------------------------------------------------ water
    # The disc runs 0.08 past the cavity wall so its edge is buried in the wood: no gap
    # and no coplanar seam where the surface meets the shell.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(SEG, WATER_R), 0.30, WATER_Z)
    D.new_obj("Water", bm, c, D.C("water_mid"), rbx_material="SmoothPlastic",
              transparency=0.30, roughness=0.12)

    # ------------------------------------------------------------ foam on the surface
    # Froth, not pebbles: flat crescents lying in an arc against the far wall where the
    # jets would churn, each breaking the surface by only 0.055.  Middle of the pool is
    # left clear so the water reads as water.
    bm = bmesh.new()
    rngf = random.Random(97)
    for k in range(4):
        a = math.radians(214.0 + k * 34.0 + rngf.uniform(-7.0, 7.0))
        blob = rngf.uniform(0.50, 0.80)
        rr = rngf.uniform(2.56, 2.72) - blob      # placed by its OUTER edge, at the wall
        D.uvsphere(bm, (math.cos(a) * rr, math.sin(a) * rr,
                        WATER_Z + 0.055 - 0.28 * blob), blob,
                   segs=8, rings=3, scale=(1.0, 1.0, 0.28))
    D.new_obj("Foam", bm, c, D.C("foam"), rbx_material="SmoothPlastic",
              transparency=0.45, roughness=0.9)

    # ------------------------------------------------------------ steam
    # Three flat puffs hanging over the water, not posts growing out of it: rounder in
    # plan, a third as tall, and kept inside r 1.95 and between z 2.60 and z 3.05 so
    # nothing crosses the rim line or pokes out of the tub's silhouette.
    bm = bmesh.new()
    for (sx, sy, sz, sr) in ((0.58, 0.46, 2.82, 0.80),
                             (-0.64, -0.30, 2.79, 0.68),
                             (0.10, -0.78, 2.88, 0.56)):
        D.uvsphere(bm, (sx, sy, sz), sr, segs=8, rings=4, scale=(1.5, 1.5, 0.28))
    D.new_obj("Steam", bm, c, D.C("foam"), rbx_material="SmoothPlastic",
              transparency=0.88, roughness=0.95)

    # ------------------------------------------------------------ control panel
    prx, pry = _polar(PANEL_DEG, 2.84)
    bm = bmesh.new()
    D.beveled_box(bm, (prx - 0.50, pry - 0.27, 2.54), (prx + 0.50, pry + 0.27, 2.90),
                  bevel=0.07, rot=D.rot_euler(rz=PANEL_DEG + 90.0))
    D.new_obj("Panel", bm, c, D.C("plastic_black"), rbx_material="SmoothPlastic",
              roughness=0.45)

    bm = bmesh.new()
    for u in (-0.30, 0.0, 0.30):
        D.cyl(bm, (u, 0.0, 0.0), (u, 0.0, 0.06), 0.075, segs=5)
    D.xform(bm, list(bm.verts),
            D.place((prx, pry, 2.90), D.rot_euler(rz=PANEL_DEG + 90.0)))
    D.new_obj("PanelLights", bm, c, D.C("neon_cyan"), rbx_material="Neon", emit=1.2)

    return c
