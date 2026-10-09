"""Mortar - stubby charcoal mortar on a low hex base: tan bolted corner blocks, a yawing mount
with two stepped trunnion cheeks, and a fat ringed tube pitched 55 deg toward +Y whose muzzle
reads hollow."""
import bmesh
import math
from mathutils import Vector, Matrix

COLLECTION = "Mortar"

# Tube frame: trunnion T, elevation 55 deg, unit direction d in the Y-Z plane (+Y and up).
_ELEV = 55.0
_T = (0.0, 0.0, 4.0)
_D = (0.0, math.cos(math.radians(_ELEV)), math.sin(math.radians(_ELEV)))


def _p(s):
    """Point on the tube axis, `s` studs along d from the trunnion (negative = breech side)."""
    return (_T[0] + _D[0] * s, _T[1] + _D[1] * s, _T[2] + _D[2] * s)


_MUZZLE = tuple(round(v, 3) for v in _p(3.5))      # (0.0, 2.008, 6.867)

NOTES = (
    "Rig by name prefix: Base* is static, Mount* yaws about the world Z axis through (0, 0) "
    "(YawPivot = top of BasePlatform, z 1.3), Tube* pitches about the trunnion axis, a line "
    "parallel to X through PitchPivot (0, 0, 4.0). Modelled at zero yaw and 55 deg elevation "
    "(STATES.Elevation) with the tube pointing +Y and up: d = (0, cos 55, sin 55). Shells "
    "leave MuzzleTip = PitchPivot + d * 3.5, the centre of the muzzle face. "
    "Base plate is an octagon r 3.4 (vertex) = 6.28 flat-to-flat, so the static footprint is "
    "6.28 x 6.28; total height 7.51 to the top of the muzzle collar rim (the muzzle face "
    "centre is at z 6.87). Widest yawing point is the muzzle collar rim at radius 2.93 from "
    "the yaw axis, so a full 360 deg yaw of Mount* + Tube* stays inside the base plate and "
    "well inside the 8 x 8 tile. Pitch clearance traced by hand: the tube (r <= 1.12 at the "
    "collar) clears the cheek inner faces at x = +/-1.25 at every angle, and the breech cap "
    "clears MountBar (top z 2.5) from 20 deg up to 90 deg, so 25..85 deg elevation is a safe "
    "usable range. TubeMuzzle's front face is a real annulus (outer r 1.12, inner r 0.78) "
    "with a 0.2-deep recess, and TubeBore is the dark disc sitting 0.05 inside that recess - "
    "that pair is what makes the muzzle read hollow, keep them together. "
    "MountTrunnionDiscs are embedded 0.1 into the cheeks and MountBar 0.1 into each cheek so "
    "no two parts share a coplanar face. Nothing dips below z = 0. No Neon parts. Tan (c8b276) "
    "accents: BaseCorners, MountTrunnionDiscs. Bolt-dark (2f3136) parts: BaseBolts (one per "
    "corner block, on its outer face), MountBolts (two on each cheek's front lower face plus "
    "one axle bolt in the centre of each trunnion disc), TubeBore."
)

PIVOTS = {
    "YawPivot":   (0.0, 0.0, 1.3),     # top face of BasePlatform, on the vertical axis
    "PitchPivot": (0.0, 0.0, 4.0),     # trunnion centre, axis parallel to X
    "MuzzleTip":  _MUZZLE,             # centre of the muzzle face = PitchPivot + d * 3.5
}

STATES = {"Elevation": 55}


def _hollow_collar(D, bm, a, b, r_out, r_in, depth, segs=12):
    """Cylinder a -> b whose FRONT cap (at b) is an annulus r_in..r_out around a recess
    `depth` deep: outer wall, back cap, front ring, inner wall, recess floor. Closed manifold."""
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length
    m = Matrix.Translation(a) @ D.aim(d)

    def ring(r, z):
        return [bm.verts.new(m @ Vector((math.cos(2 * math.pi * i / segs) * r,
                                         math.sin(2 * math.pi * i / segs) * r, z)))
                for i in range(segs)]

    back = ring(r_out, 0.0)
    front = ring(r_out, length)
    lip = ring(r_in, length)
    floor = ring(r_in, length - depth)
    bm.faces.new(tuple(reversed(back)))                 # back cap, faces -d
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((back[i], back[j], front[j], front[i]))   # outer wall
        bm.faces.new((front[i], front[j], lip[j], lip[i]))     # front annulus, faces +d
        bm.faces.new((lip[i], lip[j], floor[j], floor[i]))     # inner wall, faces the axis
    bm.faces.new(tuple(floor))                          # recess floor, faces +d
    return back + front + lip + floor


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    DARK = "45474d"      # body dark  - big masses
    MID = "565962"       # body mid   - the tier / band touching a dark part
    BOLT = "2f3136"      # bolt heads, the bore
    TAN = "c8b276"       # corner blocks, trunnion discs

    CORNERS = (45, 135, 225, 315)

    # ------------------------------------------------------------------ BASE (static)
    # Octagonal plate, flats facing the axes.  r 3.4 at the vertices = 6.28 flat-to-flat.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 3.4, phase=math.pi / 8.0), 0.0, 0.9)
    D.new_obj("BasePlate", bm, c, DARK)

    # Four tan corner blocks clamped over the plate's diagonal faces: 1.5 wide (tangential)
    # x 1.1 deep (radial) x 1.0 tall, centred at radius 2.75, so each stands 0.16 proud of
    # the diagonal face and 0.15 above the plate top.
    bm = bmesh.new()
    for ang in CORNERS:
        r = math.radians(ang)
        cx, cy = 2.75 * math.cos(r), 2.75 * math.sin(r)
        D.beveled_box(bm, (cx - 0.75, cy - 0.55, 0.05), (cx + 0.75, cy + 0.55, 1.05),
                      bevel=0.14, rot=D.rot_euler(rz=ang - 90))
    D.new_obj("BaseCorners", bm, c, TAN)

    # One hex bolt on each block's outer face, along the radial (face) normal.
    bm = bmesh.new()
    for ang in CORNERS:
        r = math.radians(ang)
        ux, uy = math.cos(r), math.sin(r)
        D.cyl(bm, (3.20 * ux, 3.20 * uy, 0.55), (3.52 * ux, 3.52 * uy, 0.55), 0.24, segs=6)
    D.new_obj("BaseBolts", bm, c, BOLT, rbx_material="Metal", metallic=0.5, roughness=0.45)

    # Inner 12-gon platform the mount turns on.  Sunk 0.03 into the plate.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(12, 2.2, phase=math.pi / 12.0), 0.87, 1.3)
    D.new_obj("BasePlatform", bm, c, MID)

    # ------------------------------------------------------------------ MOUNT (yaws about Z)
    # Turntable disc.  Sunk 0.03 into the platform.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 1.27), (0.0, 0.0, 1.7), 1.9, segs=12)
    D.new_obj("MountTurntable", bm, c, DARK)

    # Two stepped trunnion cheeks: a long low block, then a narrower upright that carries
    # the trunnion at z 4.0.  Inner faces at x = +/-1.25 are the tube's clearance envelope.
    bm = bmesh.new()
    for s in (1, -1):
        x0, x1 = sorted((s * 1.25, s * 1.75))
        D.beveled_box(bm, (x0, -1.35, 1.67), (x1, 1.05, 3.4), bevel=0.12)
        D.beveled_box(bm, (x0, -0.6, 3.3), (x1, 0.6, 4.7), bevel=0.12)
    D.new_obj("MountCheeks", bm, c, MID)

    # Tan trunnion discs on the outside of each upright, embedded 0.1 so no coplanar faces.
    bm = bmesh.new()
    D.cyl(bm, (1.65, 0.0, 4.0), (2.0, 0.0, 4.0), 0.62, segs=12)
    D.cyl(bm, (-1.65, 0.0, 4.0), (-2.0, 0.0, 4.0), 0.62, segs=12)
    D.new_obj("MountTrunnionDiscs", bm, c, TAN)

    # Rear crossbar tying the cheeks together, embedded 0.1 into each.
    bm = bmesh.new()
    D.beveled_box(bm, (-1.35, -1.3, 1.67), (1.35, -0.9, 2.5), bevel=0.12)
    D.new_obj("MountBar", bm, c, DARK)

    # Two hex bolts on each cheek's front lower face (+Y) and one axle bolt per trunnion disc.
    bm = bmesh.new()
    for s in (1, -1):
        for z in (2.2, 2.9):
            D.cyl(bm, (s * 1.5, 0.90, z), (s * 1.5, 1.27, z), 0.22, segs=6)
        D.cyl(bm, (s * 1.9, 0.0, 4.0), (s * 2.22, 0.0, 4.0), 0.24, segs=6)
    D.new_obj("MountBolts", bm, c, BOLT, rbx_material="Metal", metallic=0.5, roughness=0.45)

    # ------------------------------------------------------------------ TUBE (pitches about X)
    # Main tube: r 0.95, from 1.1 behind the trunnion to just short of the muzzle recess
    # floor (its front cap is hidden inside the collar).
    bm = bmesh.new()
    D.cyl(bm, _p(-1.1), _p(3.28), 0.95, segs=12)
    D.new_obj("TubeBarrel", bm, c, DARK)

    # Two reinforcing rings.
    bm = bmesh.new()
    for s0 in (0.6, 2.4):
        D.cyl(bm, _p(s0 - 0.16), _p(s0 + 0.16), 1.07, segs=12)
    D.new_obj("TubeRings", bm, c, MID)

    # Muzzle collar: 0.45 long, ends exactly at the muzzle, front face is an annulus around
    # a 0.2-deep recess.
    bm = bmesh.new()
    _hollow_collar(D, bm, _p(3.05), _p(3.5), 1.12, 0.78, 0.2, segs=12)
    D.new_obj("TubeMuzzle", bm, c, MID)

    # The bore: a dark disc 0.05 inside the muzzle face, so the muzzle reads hollow.
    bm = bmesh.new()
    D.cyl(bm, _p(3.35), _p(3.45), 0.72, segs=12)
    D.new_obj("TubeBore", bm, c, BOLT, roughness=0.9)

    # Breech cap, stepped in behind the tube (embedded 0.05 so no coplanar caps).
    bm = bmesh.new()
    D.cyl(bm, _p(-1.4), _p(-1.05), 0.8, segs=12)
    D.new_obj("TubeBreech", bm, c, MID)

    return c


# ---------------------------------------------------------------------------------------
# PART LIST - name / colour / approx tris     (44 per beveled_box, 4n-4 per n-gon prism or
#                                              n-seg capped cylinder, 20 per 6-seg bolt)
#
#   BasePlate           body dark  45474d   8-gon prism ..................  28
#   BaseCorners         tan        c8b276   4 x beveled_box .............. 176
#   BaseBolts           bolt       2f3136   4 x 6-seg cyl ................  80
#   BasePlatform        body mid   565962   12-gon prism .................  44
#                                                          BASE subtotal   328
#   MountTurntable      body dark  45474d   12-seg cyl ...................  44
#   MountCheeks         body mid   565962   4 x beveled_box .............. 176
#   MountTrunnionDiscs  tan        c8b276   2 x 12-seg cyl ...............  88
#   MountBar            body dark  45474d   beveled_box ..................  44
#   MountBolts          bolt       2f3136   6 x 6-seg cyl ................ 120
#                                                         MOUNT subtotal   472
#   TubeBarrel          body dark  45474d   12-seg cyl ...................  44
#   TubeRings           body mid   565962   2 x 12-seg cyl ...............  88
#   TubeMuzzle          body mid   565962   hollow collar, 12 segs .......  92
#   TubeBore            bolt       2f3136   12-seg cyl ...................  44
#   TubeBreech          body mid   565962   12-seg cyl ...................  44
#                                                          TUBE subtotal   312
#
#   14 objects, ~1112 tris of a 1600 budget.
#   Bounding box  x -3.14..3.14  |  y -3.14..3.14  |  z 0.00..7.51
#   Yaw sweep radius 2.93 (muzzle collar rim).  Value ladder: DARK plate -> TAN corners /
#   MID platform -> DARK turntable -> MID cheeks -> TAN discs -> DARK tube -> MID rings /
#   collar -> BOLT bore.  MountBar (DARK) sits on the DARK turntable but is walled by the
#   MID cheeks on both sides and reads by its top-face highlight.
# ---------------------------------------------------------------------------------------
