"""TeslaCoil - charcoal coil tower: bolted octagon plinth, two glowing coil bands, a
four-prong crown cradling a metallic blue orb."""
import bmesh
import math
from mathutils import Matrix, Vector

COLLECTION = "TeslaCoil"

# Crown geometry lives at module level so build() and PIVOTS share ONE set of numbers and
# the exported prong-tip points are the real ones, not a hand-typed guess.
PRONG_R = 1.45          # radius of each prong's base centre (45 / 135 / 225 / 315 deg)
PRONG_LEAN = 7.0        # degrees; the top tilts toward the axis (rotation about the tangent)
PRONG_Z0 = 7.60         # base pivot, sunk 0.05 into CapTop so the tilted bottom edge never floats
PRONG_H = 1.70          # prong length along its own (leaning) axis, 0.75 x 0.75 in section
TIP_Z0, TIP_Z1 = 1.65, 2.00   # blue tip block in prong-local z (0.35 tall, 0.05 into the prong)
ORB_Z = 9.00            # crests the tip blocks by ~0.27 so the ball reads from eye level
ORB_R = 0.85            # the tip blocks graze the sphere at z ~9.3 (0.02 clear): a grip, not a clip


def _prong_matrix(k):
    """4x4 taking prong-local space (origin = base centre, +X = radially outward, +Z = up
    the prong) onto the k-th crown position.  Rightmost applies first: lean about the
    tangent (local Y), swing round to the diagonal, then translate out to the ring."""
    ang = 45.0 + 90.0 * k
    a = math.radians(ang)
    return (Matrix.Translation(Vector((PRONG_R * math.cos(a), PRONG_R * math.sin(a), PRONG_Z0)))
            @ _rot_z(ang) @ _rot_y(-PRONG_LEAN))


def _rot_y(deg):
    r = math.radians(deg)
    return Matrix(((math.cos(r), 0.0, math.sin(r), 0.0), (0.0, 1.0, 0.0, 0.0),
                   (-math.sin(r), 0.0, math.cos(r), 0.0), (0.0, 0.0, 0.0, 1.0)))


def _rot_z(deg):
    r = math.radians(deg)
    return Matrix(((math.cos(r), -math.sin(r), 0.0, 0.0), (math.sin(r), math.cos(r), 0.0, 0.0),
                   (0.0, 0.0, 1.0, 0.0), (0.0, 0.0, 0.0, 1.0)))


def _tip_point(k):
    """Centre of the top face of the k-th blue tip block, in prop space."""
    p = _prong_matrix(k) @ Vector((0.0, 0.0, TIP_Z1))
    return (round(p.x, 3), round(p.y, 3), round(p.z, 3))


NOTES = (
    "Static tower, nothing yaws. Footprint: the 8-gon plate is r 3.7 (7.4 across the "
    "vertices, 6.84 across the flats, flats face the axes AND the diagonals); the blue "
    "corner clamps ride the four diagonal flats and stay inside the plate's axis extent, so "
    "the bounding box is ~6.84 x 6.84. Height 9.85 to the top of the orb. "
    "Rig: 'Orb' spins in place about OrbCentre (0, 0, 9.00), radius 0.85, "
    "rbx_material Metal + smooth shading - the ONLY smooth part. "
    "Lightning: Beams run OrbCentre -> ProngTip1..4 (the centre of each blue tip block's top "
    "face; the prongs stand at radius 1.45 and lean 7 deg inward so the tips sit at radius "
    "~1.21, z 9.59, and the orb crests them by 0.27), then on to the zombie. "
    "'CoilGlow' is the one Neon part: two 12-gon rings (r 2.10, 0.23 tall) standing "
    "0.05 proud of the blue 'CoilBands' (r 2.05) at z 3.46..3.69 and z 4.66..4.89 - flicker "
    "or pulse its transparency for the charge-up. "
    "Tesla blue 4f7fc2 = BaseCorners, CoilBands, ProngTips; Tesla glow 35a7ff = CoilGlow; "
    "Tesla orb 7fb3e8 = Orb. Everything else is charcoal. "
    "Two colour tweaks vs the brief so no two touching parts share a value: BaseRing and "
    "CapTop are body LIGHT (6a6e78) instead of body dark, because each is sandwiched "
    "between a body-mid part below and a body-dark part above (Column / Prongs). "
    "BaseBolts = 8 hex heads (2f3136): one on each corner clamp's outer face plus four on "
    "the plate top at the axes, radius 3.0. Nothing dips below z = 0."
)

PIVOTS = {"OrbCentre": (0.0, 0.0, ORB_Z)}
for _k in range(4):
    PIVOTS["ProngTip%d" % (_k + 1)] = _tip_point(_k)
del _k


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    DARK = "45474d"      # body dark  - big masses
    MID = "565962"       # body mid   - the tier / band touching a dark part
    LIGHT = "6a6e78"     # body light - small raised details on mid parts
    BOLT = "2f3136"      # bolt heads
    BLUE = "4f7fc2"      # tesla blue - corner clamps, coil bands, prong tips
    GLOW = "35a7ff"      # tesla glow - neon ring cores
    ORB = "7fb3e8"       # tesla orb  - metal, smooth

    OCT = math.pi / 8.0  # 8-gon phase: flats face the axes and the diagonals

    def hex_bolt(bm, at, direction, length=0.22, r=0.24, sink=0.05):
        """Hex head standing `length` proud of a face at `at`, along the unit `direction`;
        starts `sink` inside the face so the seam never z-fights."""
        d = Vector(direction).normalized()
        a = Vector(at) - d * sink
        b = Vector(at) + d * length
        D.cyl(bm, tuple(a), tuple(b), r, segs=6)

    # ------------------------------------------------------------------ BASE (static)
    # Octagonal plate, r 3.7, flats on the axes and the diagonals.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 3.7, phase=OCT), 0.0, 1.0)
    D.new_obj("BasePlate", bm, c, DARK, rbx_material="Metal", metallic=0.3, roughness=0.55)

    # Four BLUE corner clamps astride the diagonal flats (apothem 3.42): 1.2 radial x 1.7
    # tangential x 1.05 tall, centred at radius 3.0, so each pokes 0.18 past the flat and
    # 0.10 above the plate top - a bolted-on bracket, not a paint stripe.
    bm = bmesh.new()
    for k in range(4):
        ang = 45.0 + 90.0 * k
        a = math.radians(ang)
        px, py = 3.0 * math.cos(a), 3.0 * math.sin(a)
        D.beveled_box(bm, (px - 0.6, py - 0.85, 0.05), (px + 0.6, py + 0.85, 1.10),
                      bevel=0.14, rot=D.rot_euler(rz=ang))
    D.new_obj("BaseCorners", bm, c, BLUE, rbx_material="SmoothPlastic", roughness=0.6)

    # Hex bolts: one on each clamp's outer face (radius 3.6, along the diagonal) and four
    # on the plate top at the axes, in the free annulus between tier and plate edge.
    bm = bmesh.new()
    for k in range(4):
        a = math.radians(45.0 + 90.0 * k)
        ca, sa = math.cos(a), math.sin(a)
        hex_bolt(bm, (3.6 * ca, 3.6 * sa, 0.575), (ca, sa, 0.0))
    for k in range(4):
        a = math.radians(90.0 * k)
        hex_bolt(bm, (3.0 * math.cos(a), 3.0 * math.sin(a), 1.0), (0.0, 0.0, 1.0))
    D.new_obj("BaseBolts", bm, c, BOLT, rbx_material="Metal", metallic=0.5, roughness=0.45)

    # Second octagonal tier, then a 12-gon ring the column stands on.  The ring is body
    # LIGHT: mid tier below it, dark column above it, so it has to be the odd one out.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 2.8, phase=OCT), 1.0, 1.6)
    D.new_obj("BaseTier", bm, c, MID, rbx_material="Metal", metallic=0.3, roughness=0.55)

    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(12, 2.15), 1.6, 2.0)
    D.new_obj("BaseRing", bm, c, LIGHT, rbx_material="Metal", metallic=0.35, roughness=0.5)

    # ------------------------------------------------------------------ COLUMN
    # 12-seg cylinder, vertices at multiples of 30 deg - same phase as ngon_pts(12, r), so
    # the bands and cap facets line up with the column's.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 2.0), (0.0, 0.0, 6.6), 1.5, segs=12)
    D.new_obj("Column", bm, c, DARK, rbx_material="Metal", metallic=0.3, roughness=0.55)

    # Two BLUE coil bands, 0.75 tall, r 2.05, at z 3.2 and z 4.4 ...
    bm = bmesh.new()
    for h in (3.2, 4.4):
        D.prism(bm, D.ngon_pts(12, 2.05), h, h + 0.75)
    D.new_obj("CoilBands", bm, c, BLUE, rbx_material="SmoothPlastic", roughness=0.6)

    # ... each with a NEON groove ring standing 0.05 proud of the band, 0.23 tall.
    bm = bmesh.new()
    for h in (3.2, 4.4):
        D.prism(bm, D.ngon_pts(12, 2.10), h + 0.26, h + 0.49)
    D.new_obj("CoilGlow", bm, c, GLOW, rbx_material="Neon")

    # ------------------------------------------------------------------ CAP
    # 12-gon cap overhanging the column by 0.45, then a LIGHT disc the crown stands on
    # (mid cap below, dark prongs above).
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(12, 1.95), 6.6, 7.3)
    D.new_obj("Cap", bm, c, MID, rbx_material="Metal", metallic=0.3, roughness=0.55)

    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 7.3), (0.0, 0.0, 7.65), 1.45, segs=12)
    D.new_obj("CapTop", bm, c, LIGHT, rbx_material="Metal", metallic=0.35, roughness=0.5)

    # ------------------------------------------------------------------ CROWN
    # Four claws on the diagonals (front view shows two), 0.75 square, leaning 7 deg in.
    # Built in prong-local space and pushed out with _prong_matrix so the PIVOTS match.
    bm = bmesh.new()
    for k in range(4):
        vs = D.beveled_box(bm, (-0.375, -0.375, 0.0), (0.375, 0.375, PRONG_H), bevel=0.12)
        D.xform(bm, vs, _prong_matrix(k))
    D.new_obj("Prongs", bm, c, DARK, rbx_material="Metal", metallic=0.3, roughness=0.55)

    # BLUE tip blocks, 0.85 square x 0.35, riding each prong top (0.05 sunk in).
    bm = bmesh.new()
    for k in range(4):
        vs = D.beveled_box(bm, (-0.425, -0.425, TIP_Z0), (0.425, 0.425, TIP_Z1), bevel=0.12)
        D.xform(bm, vs, _prong_matrix(k))
    D.new_obj("ProngTips", bm, c, BLUE, rbx_material="SmoothPlastic", roughness=0.6)

    # Stem up into the orb, then the orb itself: the ONE smooth part, metal so it picks up
    # a highlight the flat charcoal never does.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 7.65), (0.0, 0.0, ORB_Z - 0.55), 0.28, segs=8)
    D.new_obj("OrbStem", bm, c, MID, rbx_material="Metal", metallic=0.3, roughness=0.55)

    bm = bmesh.new()
    D.uvsphere(bm, (0.0, 0.0, ORB_Z), ORB_R, segs=12, rings=8)
    D.new_obj("Orb", bm, c, ORB, rbx_material="Metal", metallic=0.85, roughness=0.25,
              smooth=True)

    return c


# ---------------------------------------------------------------------------------------
# PART LIST - name / colour role / hex / approx tris        (tri = 44 per beveled_box,
#                                                            4n-4 per n-seg cylinder or
#                                                            n-gon prism, 20 per hex bolt)
#
#   BasePlate       body dark     45474d   8-gon prism r 3.7 ...................  28
#   BaseCorners     tesla blue    4f7fc2   4 x beveled_box ..................... 176
#   BaseBolts       bolt          2f3136   8 x 6-seg cyl ....................... 160
#   BaseTier        body mid      565962   8-gon prism r 2.8 ...................  28
#   BaseRing        body light    6a6e78   12-gon prism r 2.15 .................  44
#                                                                 BASE subtotal   436
#
#   Column          body dark     45474d   12-seg cyl r 1.5 ....................  44
#   CoilBands       tesla blue    4f7fc2   2 x 12-gon prism r 2.05 .............  88
#   CoilGlow        tesla glow    35a7ff   2 x 12-gon prism r 2.10  [NEON] .....  88
#   Cap             body mid      565962   12-gon prism r 1.95 .................  44
#   CapTop          body light    6a6e78   12-seg cyl r 1.45 ...................  44
#                                                               COLUMN subtotal   308
#
#   Prongs          body dark     45474d   4 x beveled_box ..................... 176
#   ProngTips       tesla blue    4f7fc2   4 x beveled_box ..................... 176
#   OrbStem         body mid      565962   8-seg cyl ...........................  28
#   Orb             tesla orb     7fb3e8   uvsphere 12 x 8  [Metal, smooth] .... 168
#                                                                CROWN subtotal   548
#
#   14 objects, ~1292 tris of an 1800 budget.
#   Bounding box  x -3.42..3.42  |  y -3.42..3.42  |  z 0.00..9.85
#   Value ladder, ground to sky:
#     DARK plate -> BLUE clamps / MID tier -> LIGHT ring -> DARK column -> BLUE bands ->
#     GLOW rings -> MID cap -> LIGHT cap top -> DARK prongs -> BLUE tips ; MID stem -> ORB.
#   No two touching parts share a value.
# ---------------------------------------------------------------------------------------
