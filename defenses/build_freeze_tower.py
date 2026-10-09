"""FreezeTower - a charcoal stone rook overgrown with ice, four claws cradling a frost orb."""
import bmesh
import math
import random
from mathutils import Matrix, Vector

COLLECTION = "FreezeTower"

NOTES = (
    "Static tower with ONE moving part: 'Orb' (faceted icosphere r 1.0, Ice glow bfe4ff, "
    "Neon) spins in place about OrbCentre (0, 0, 8.68); the freeze aura / slow field is "
    "cast from OrbCentre. The orb's lowest vertex is at z 7.68, 0.08 clear of CollarTop "
    "(z 7.3..7.6), so it turns freely; the four prongs graze its equator (a deliberate "
    "cradle, ~0.05 of interpenetration, no gap). Everything else is one static body - "
    "no yaw / pitch groups. "
    "Footprint: base octagon +/-3.23 on the axes (r 3.5 at the vertices), ice tips reach "
    "r ~3.75, so the whole prop stays inside the 8 x 8 tile; height 9.75 to the tallest "
    "prong ice cap (prongs 9.30, orb top 9.68); nothing below z = 0. "
    "Ice parts are Ice 9ed6ff / SmoothPlastic, NOT emissive: IceCrystals (6 clusters on "
    "tier 1's top edge), IceSheets (2 slabs slumped over the tier-1 edge, each with an "
    "icicle), BandIcicles (3 under the mid band), CollarIcicles (2 under the collar's "
    "overhang), ProngIce (caps on the +Y and +X prongs). A frost shimmer / sparkle "
    "emitter belongs on those; the only glow is Orb. "
    "Charcoal value ladder: body dark 45474d = BaseTier1, Column, Prongs; body mid "
    "565962 = BaseTier2, Band, Collar; body light 6a6e78 = BaseLip and CollarTop (the "
    "two small discs raised on mid parts - light so the dark column / prongs standing "
    "on them keep their feet at eye level); bolt 2f3136 = BaseBolts (8 hex heads on "
    "tier 2's top annulus, the pack's family mark). The octagon tiers have their "
    "flat faces on the axes (phase pi/8); the prongs stand at 0 / 90 / 180 / 270 deg at "
    "radius 1.42 and lean 8 deg inward. Faces +Y by convention only - the tower is "
    "radially symmetric apart from where the ice happens to grow."
)

PIVOTS = {
    "OrbCentre": (0.0, 0.0, 8.68),   # icosphere centre; spin axis + aura origin
}

STATES = {}

# Plan angles (deg, +X = 0, +Y = 90 = the prop's front) of the scattered ice, chosen so no
# cluster lands on a sheet (sheets on the 0 / 90 flats, +/-23 deg) and the front-right
# quadrant the renders look at is the busiest.
CLUSTER_DEGS = (40.0, 140.0, 185.0, 230.0, 275.0, 320.0)
CLUSTER_COUNTS = (3, 2, 3, 2, 3, 3)          # crystals per cluster (big, small[, mid])
SHEET_DEGS = (90.0, 0.0)
BAND_ICICLE_DEGS = (30.0, 120.0, 240.0)
COLLAR_ICICLE_DEGS = (65.0, 160.0)
PRONG_DEGS = (0.0, 90.0, 180.0, 270.0)
PRONG_ICE_DEGS = (90.0, 0.0)                 # the two claws that wear an ice cap

TIER1_R = 3.5
PRONG_R, PRONG_LEAN = 1.42, 8.0              # ring radius of the claws, inward lean (deg)
PRONG_Z0, PRONG_Z1 = 7.25, 9.30              # bottom sunk 0.35 into CollarTop, see below
ORB_Z = PIVOTS["OrbCentre"][2]


def _polar(r, deg, z):
    a = math.radians(deg)
    return Vector((r * math.cos(a), r * math.sin(a), z))


def _octagon_edge_r(r_vertex, deg):
    """Distance from the axis to the SIDE of a phase-pi/8 octagon (flats on the axes) at
    plan angle `deg` - the apothem on a flat's centre line, r_vertex at a corner."""
    apothem = r_vertex * math.cos(math.pi / 8.0)
    off = deg % 45.0
    off = min(off, 45.0 - off)
    return apothem / math.cos(math.radians(off))


def _crystal(D, bm, deg, r, length, tilt, twist, z0=0.95):
    """One faceted crystal standing on tier 1's top rim: a 6-sided spike whose base is
    sunk into the tier (z0 < 1.2) right at the octagon's edge, leaning OUTWARD by `tilt`
    deg (so the longer ones hang their tips past the side) with a tangential `twist`."""
    edge = _octagon_edge_r(TIER1_R, deg)
    t, w = math.radians(tilt), math.radians(twist)
    base_r = edge - r * math.cos(t) - 0.03      # base cap never pokes out of the side
    base = _polar(base_r, deg, z0)
    a = math.radians(deg)
    radial = Vector((math.cos(a), math.sin(a), 0.0))
    tangent = Vector((-math.sin(a), math.cos(a), 0.0))
    axis = (Vector((0.0, 0.0, math.cos(t)))
            + radial * (math.sin(t) * math.cos(w))
            + tangent * (math.sin(t) * math.sin(w))).normalized()
    D.spike(bm, tuple(base), tuple(base + axis * length), r, segs=6, tip_r=0.08)


def _prong_matrix(D, deg):
    """Local frame of the claw at plan angle `deg`: box centre on the ring, local +Z up
    the claw, tipped `PRONG_LEAN` deg about the ring's tangent so the top moves inward."""
    zc = 0.5 * (PRONG_Z0 + PRONG_Z1)
    return (D.rot_euler(rz=deg)
            @ Matrix.Translation(Vector((PRONG_R, 0.0, zc)))
            @ D.rot_euler(ry=-PRONG_LEAN))


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    DARK = "45474d"      # body dark  - big masses
    MID = "565962"       # body mid   - the tier / band touching a dark part
    LIGHT = "6a6e78"     # body light - the two small discs raised on mid parts
    BOLT = "2f3136"      # bolt / bore
    ICE = "9ed6ff"       # ice crystals + icicles (SmoothPlastic)
    GLOW = "bfe4ff"      # the orb (Neon)

    PH = math.pi / 8.0   # octagon phase: flats face the axes

    # ------------------------------------------------------------------ BASE (static)
    # Tier 1: the ground octagon, r 3.5 (apothem 3.23), 1.2 tall - the plinth everything
    # else stacks on and the surface the ice grows from.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 3.5, phase=PH), 0.0, 1.2)
    D.new_obj("BaseTier1", bm, c, DARK, rbx_material="SmoothPlastic", roughness=0.6)

    # Tier 2: r 2.7, z 1.2..2.0, mid so the step reads against the dark tier below.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 2.7, phase=PH), 1.2, 2.0)
    D.new_obj("BaseTier2", bm, c, MID, rbx_material="SmoothPlastic", roughness=0.6)

    # Lip: r 2.1, z 2.0..2.5, the last octagonal step before the round column. Body
    # LIGHT (a small raised detail on the mid tier) rather than the brief's dark: at eye
    # level a dark lip under the dark column merged into one mass, and the light disc
    # is what separates the base from the shaft.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 2.1, phase=PH), 2.0, 2.5)
    D.new_obj("BaseLip", bm, c, LIGHT, rbx_material="SmoothPlastic", roughness=0.6)

    # Eight hex bolt heads on tier 2's top annulus (ring r 2.22 fits between the lip's
    # flats at 1.94 and tier 2's flats at 2.49), one per flat - the pack's family mark.
    bm = bmesh.new()
    for x, y in D.ring_positions(8, 2.22, phase=0.0):
        D.cyl(bm, (x, y, 1.98), (x, y, 2.22), 0.24, segs=6)
    D.new_obj("BaseBolts", bm, c, BOLT, rbx_material="SmoothPlastic", roughness=0.5)

    # ------------------------------------------------------------------ ICE ON THE BASE
    # Six crystal clusters on tier 1's top rim. Sizes / leans come from a seeded RNG so
    # no two clusters match but every build is identical. Each cluster = a big crystal
    # on the cluster's centre line, a small one to one side, and (4 of 6) a mid one to
    # the other side; the bases overlap so they read as one growth.
    rng = random.Random(1609)
    bm = bmesh.new()
    for i, (deg, count) in enumerate(zip(CLUSTER_DEGS, CLUSTER_COUNTS)):
        side = 1.0 if i % 2 == 0 else -1.0
        _crystal(D, bm, deg + rng.uniform(-3.0, 3.0),
                 r=rng.uniform(0.47, 0.55), length=rng.uniform(1.35, 1.60),
                 tilt=rng.uniform(12.0, 25.0), twist=rng.uniform(-10.0, 10.0))
        _crystal(D, bm, deg + side * rng.uniform(9.0, 12.0),
                 r=rng.uniform(0.34, 0.40), length=rng.uniform(0.90, 1.10),
                 tilt=rng.uniform(10.0, 22.0), twist=rng.uniform(-25.0, 25.0))
        if count == 3:
            _crystal(D, bm, deg - side * rng.uniform(8.0, 11.0),
                     r=rng.uniform(0.40, 0.45), length=rng.uniform(1.00, 1.25),
                     tilt=rng.uniform(10.0, 20.0), twist=rng.uniform(-20.0, 20.0))
    D.new_obj("IceCrystals", bm, c, ICE, rbx_material="SmoothPlastic", roughness=0.35)

    # Two flat ice sheets slumped over tier 1's edge on the 90 (front) and 0 (right)
    # flats: a 1.4 x 1.0 x 0.18 chamfered slab straddling the edge, tipped 5 deg so its
    # outer end droops, with an icicle dripping from the overhang.
    bm = bmesh.new()
    for deg in SHEET_DEGS:
        rc = _octagon_edge_r(TIER1_R, deg) - 0.15        # overhangs the edge by 0.35
        m = D.rot_euler(rz=deg) @ Matrix.Translation(Vector((rc, 0.0, 1.22)))
        vs = D.beveled_box(bm, (-0.50, -0.70, -0.09), (0.50, 0.70, 0.09), bevel=0.06,
                           rot=D.rot_euler(ry=5.0))    # +ry drops the outer (+x) end
        D.xform(bm, vs, m)
        b = m @ Vector((0.38, 0.18, -0.02))              # inside the slab's overhang
        t = m @ Vector((0.42, 0.18, -1.00))
        D.spike(bm, tuple(b), tuple(t), 0.18, segs=6, tip_r=0.05)
    D.new_obj("IceSheets", bm, c, ICE, rbx_material="SmoothPlastic", roughness=0.35)

    # ------------------------------------------------------------------ COLUMN
    # The rook's shaft: 12-sided, r 1.5, z 2.5..6.6, dark.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 2.5), (0.0, 0.0, 6.6), 1.5, segs=12)
    D.new_obj("Column", bm, c, DARK, rbx_material="SmoothPlastic", roughness=0.6)

    # Band: an octagonal ring r 1.95 around the column at z 3.9..4.7, mid on dark.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 1.95, phase=PH), 3.9, 4.7)
    D.new_obj("Band", bm, c, MID, rbx_material="SmoothPlastic", roughness=0.6)

    # Three icicles hanging under the band's overhang (base buried 0.05 in the band,
    # r 0.28, 1.3 long, tips at z 2.65 - clear of the lip's top at 2.5).
    bm = bmesh.new()
    for deg in BAND_ICICLE_DEGS:
        D.spike(bm, tuple(_polar(1.72, deg, 3.95)), tuple(_polar(1.75, deg, 2.65)),
                0.28, segs=6, tip_r=0.08)
    D.new_obj("BandIcicles", bm, c, ICE, rbx_material="SmoothPlastic", roughness=0.35)

    # ------------------------------------------------------------------ COLLAR
    # Octagonal collar r 2.1, z 6.6..7.3 (mid), capped by a 12-seg disc r 1.7,
    # z 7.3..7.6 that the prongs and the orb sit over. The disc is body LIGHT (same
    # reasoning as the lip): dark prongs on a dark disc lost their feet.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 2.1, phase=PH), 6.6, 7.3)
    D.new_obj("Collar", bm, c, MID, rbx_material="SmoothPlastic", roughness=0.6)

    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 7.3), (0.0, 0.0, 7.6), 1.7, segs=12)
    D.new_obj("CollarTop", bm, c, LIGHT, rbx_material="SmoothPlastic", roughness=0.6)

    # Two icicles under the collar's rim (its 0.6 overhang past the column), r 0.25,
    # 1.1 long, nestled against the column.
    bm = bmesh.new()
    for deg in COLLAR_ICICLE_DEGS:
        D.spike(bm, tuple(_polar(1.72, deg, 6.65)), tuple(_polar(1.74, deg, 5.55)),
                0.25, segs=6, tip_r=0.07)
    D.new_obj("CollarIcicles", bm, c, ICE, rbx_material="SmoothPlastic", roughness=0.35)

    # ------------------------------------------------------------------ PRONGS + ORB
    # Four claws on the axes, 0.85 sq chamfered posts, ring radius 1.42, leaning 8 deg
    # inward about the ring tangent. They run z 7.25..9.30: the extra 0.35 below the
    # CollarTop face is what keeps the tilted bottom's outer corner (z 7.37, r 1.99)
    # buried rather than floating over the disc's rim.
    half = 0.5 * (PRONG_Z1 - PRONG_Z0)
    bm = bmesh.new()
    for deg in PRONG_DEGS:
        vs = D.beveled_box(bm, (-0.425, -0.425, -half), (0.425, 0.425, half), bevel=0.14)
        D.xform(bm, vs, _prong_matrix(D, deg))
    D.new_obj("Prongs", bm, c, DARK, rbx_material="SmoothPlastic", roughness=0.6)

    # Ice caps on the front (+Y) and right (+X) claws: a small crystal continuing the
    # claw's axis, base sunk 0.08 into the claw's top.
    bm = bmesh.new()
    for deg in PRONG_ICE_DEGS:
        m = _prong_matrix(D, deg)
        b = m @ Vector((0.0, 0.0, half - 0.08))
        t = m @ Vector((0.0, 0.0, half + 0.50))
        D.spike(bm, tuple(b), tuple(t), 0.26, segs=6, tip_r=0.06)
    D.new_obj("ProngIce", bm, c, ICE, rbx_material="SmoothPlastic", roughness=0.35)

    # THE ORB - faceted icosphere r 1.0 floating between the claws. Neon = the only glow.
    # subdiv=2 here: Blender counts the bare icosahedron as subdivision 1, and that
    # 20-face d20 read as a pointed gem (and would wobble when spun); 2 is the 80-face
    # ball that is still clearly faceted under flat shading.
    bm = bmesh.new()
    D.ico(bm, (0.0, 0.0, ORB_Z), 1.0, subdiv=2)
    D.new_obj("Orb", bm, c, GLOW, rbx_material="Neon")

    return c


# ---------------------------------------------------------------------------------------
# PART LIST - name / colour role / hex / approx tris        (tri = 44 per beveled_box,
#                                                            4n-4 per n-seg cylinder,
#                                                            spike or n-gon prism, 80 per
#                                                            subdiv-1 icosphere)
#
#   BaseTier1       body dark   45474d   8-gon prism r 3.5, z 0..1.2 ...........  28
#   BaseTier2       body mid    565962   8-gon prism r 2.7, z 1.2..2.0 .........  28
#   BaseLip         body light  6a6e78   8-gon prism r 2.1, z 2.0..2.5 .........  28
#   BaseBolts       bolt        2f3136   8 x 6-seg cyl on tier 2's top .......... 160
#   IceCrystals     ice         9ed6ff   16 x 6-seg spikes, 6 clusters .......... 320
#   IceSheets       ice         9ed6ff   2 x (beveled_box + 6-seg icicle) ....... 128
#                                                          BASE subtotal   692
#
#   Column          body dark   45474d   12-seg cyl r 1.5, z 2.5..6.6 ...........  44
#   Band            body mid    565962   8-gon prism r 1.95, z 3.9..4.7 .........  28
#   BandIcicles     ice         9ed6ff   3 x 6-seg spikes, hanging ..............  60
#   Collar          body mid    565962   8-gon prism r 2.1, z 6.6..7.3 ..........  28
#   CollarTop       body light  6a6e78   12-seg disc r 1.7, z 7.3..7.6 ..........  44
#   CollarIcicles   ice         9ed6ff   2 x 6-seg spikes, hanging ..............  40
#                                                        COLUMN subtotal   244
#
#   Prongs          body dark   45474d   4 x beveled_box, 8 deg inward lean ..... 176
#   ProngIce        ice         9ed6ff   2 x 6-seg spikes on the +Y / +X claws ..  40
#   Orb             ice glow    bfe4ff   icosphere subdiv 2 (80 f)  [NEON] ......  80
#                                                         CROWN subtotal   296
#
#   15 objects, ~1232 tris of a 1700 budget (measured 1232).
#   Bounding box  6.85 x 6.91 x 9.79 (x/y about +/-3.45, ice tips; the octagon itself is
#   +/-3.23 on the axes)  |  z 0.00..9.79  - inside the 8 x 8 tile, ~7 wide, ~9.5 tall.
#   Value ladder, ground to crown - no two touching parts share a value:
#     DARK tier 1 -> MID tier 2 (+ BOLT heads) -> LIGHT lip -> DARK column -> MID band ->
#     DARK column -> MID collar -> LIGHT top -> DARK prongs -> GLOW orb.
# ---------------------------------------------------------------------------------------
