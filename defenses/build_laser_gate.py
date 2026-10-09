"""LaserGate - two bolted charcoal pillars with four red laser beams strung across the gap."""
import bmesh
import math
from mathutils import Matrix, Vector

COLLECTION = "LaserGate"

NOTES = (
    "Static prop, nothing moves: two identical pillars PillarL* (x = -2.9) and PillarR* "
    "(x = +2.9) and four free-standing beams Beam1..Beam4 (bottom to top) at z = 2.0 / 3.0 "
    "/ 4.0 / 5.0. Each beam is ONE Neon ff2f2f part, r 0.07, spanning x -1.95..1.95 (length "
    "3.90) at y = 0 - the runtime flickers / toggles these by name. The beam ends sit 0.27 "
    "inside the emitter cores (the red core faces are at x = +/-1.68, the dark rims stand "
    "0.25 proud of the column faces at x = +/-2.05), so a beam shortened at either end still "
    "appears to leave the emitter. The damage plane is the x-z rectangle between the "
    "pillars: x in [-1.95, 1.95], z 0..5.5, at y = 0; enemies walk THROUGH the gap along Y "
    "(the gap between the columns is 4.10 wide, 3.36 between the emitter faces). "
    "Neon parts: Beam1..Beam4, PillarLCores, PillarRCores (four cores in one part per "
    "pillar). Overall 8.0 wide (the outer foot-bolt tips reach x = +/-3.99), 2.62 deep "
    "(front bolt heads on the feet, the feet themselves are y -1.2..1.2), 6.4 tall. "
    "Pillar: foot 2.1 x 2.4 x 1.1 (bevel 0.30, body dark, its outer face at |x| 3.85 so "
    "the outer bolt stays inside the tile), column 1.7 x 1.7 z 0.75..5.56 (the extra "
    "length is sunk into the foot and the cap so the chamfered joins read clean; the "
    "visible column runs z 1.1..5.5), cap 2.0 x 2.1 x 0.7 z 5.5..6.2 with a 1.5 x 1.5 x "
    "0.2 slab on top to z 6.4, a dark panel 0.9 x 2.8 standing 0.06 proud of the OUTER "
    "column face, four 8-gon emitter rims r 0.42 on the INNER face. Nothing below z = 0. "
    "Footprint in the 8 x 8 tile with 2.7 studs of clearance front and back."
)

PIVOTS = {
    "BeamLeft":  (-1.95, 0.0, 3.5),   # mid-height beam end, left; the runtime's damage plane edge
    "BeamRight": (1.95, 0.0, 3.5),
}

BEAM_Z = (2.0, 3.0, 4.0, 5.0)      # Beam1..Beam4, bottom to top
PILLAR_X = 2.9                     # column centres at +/- this
BEAM_HALF = 1.95                   # beams run x -BEAM_HALF..BEAM_HALF


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    DARK = "45474d"      # body dark  - feet, caps, panels
    MID = "565962"       # body mid   - columns, cap slabs
    BOLT = "2f3136"      # bolt / bore - hex bolts, emitter rims
    RED = "ff2f2f"       # laser red  - cores + beams (Neon)

    OCT = math.pi / 8.0  # 8-gon phase that puts a FLAT on top / bottom / front / back

    def bolt(bm, p, n, proud=0.22, sink=0.06):
        """Hex bolt head standing `proud` off the face point p along the unit normal n,
        sunk `sink` into the face so it never floats over a chamfer."""
        p, n = Vector(p), Vector(n)
        D.cyl(bm, p - n * sink, p + n * proud, 0.24, segs=6)

    def pillar(s, prefix):
        """One pillar. `s` = -1 (left) / +1 (right). Everything is written as an OUTWARD
        offset u from the column centre: world x = s * (PILLAR_X + u), so the two pillars
        are exact mirrors and the inner face (u = -0.85) always looks at the gap."""
        cx = s * PILLAR_X

        def xr(u0, u1):
            """x range from outward offsets, sorted so lo < hi on either side."""
            a, b = cx + s * u0, cx + s * u1
            return (a, b) if a < b else (b, a)

        def ox(u):
            return cx + s * u

        # Flared foot. 2.1 (x) x 2.4 (y) x 1.1 with a big 0.30 chamfer: the chamfer is the
        # "flare". Its outer face is at |x| 3.85 - 0.15 short of the tile edge - so the
        # bolt on that face can stand proud and still keep the prop inside x +/-4.
        bm = bmesh.new()
        xa, xb = xr(-1.15, 0.95)
        D.beveled_box(bm, (xa, -1.20, 0.00), (xb, 1.20, 1.10), bevel=0.30)
        D.new_obj(prefix + "Foot", bm, c, DARK, rbx_material="SmoothPlastic", roughness=0.6)

        # Three hex bolts on the foot: two on the front (+Y) face at foot-centre +/- 0.5,
        # one on the outer face. The front flat (inside the chamfer) is z 0.30..0.80, so
        # the r 0.24 heads sit at z 0.55. The outer bolt is 0.14 proud: tip at |x| 3.99.
        bm = bmesh.new()
        for u in (-0.60, 0.40):
            bolt(bm, (ox(u), 1.20, 0.55), (0.0, 1.0, 0.0))
        bolt(bm, (ox(0.95), 0.00, 0.55), (s, 0.0, 0.0), proud=0.14, sink=0.07)
        D.new_obj(prefix + "Bolts", bm, c, BOLT, rbx_material="Metal", metallic=0.4,
                  roughness=0.45)

        # Column, 1.7 square in plan. Visible z 1.1..5.5; it is sunk 0.35 into the foot and
        # 0.06 into the cap so its own chamfered ends hide inside the bigger chamfers of
        # the foot top and the cap underside (no daylight at either join).
        bm = bmesh.new()
        xa, xb = xr(-0.85, 0.85)
        D.beveled_box(bm, (xa, -0.85, 0.75), (xb, 0.85, 5.56), bevel=0.12)
        D.new_obj(prefix + "Column", bm, c, MID, rbx_material="SmoothPlastic", roughness=0.6)

        # Service panel on the OUTER face: a dark 0.9 x 2.8 plate, 0.12 thick, standing
        # 0.06 proud. Dark on the mid column reads as an inset from any distance.
        bm = bmesh.new()
        xa, xb = xr(0.79, 0.91)
        D.beveled_box(bm, (xa, -0.45, 1.90), (xb, 0.45, 4.70), bevel=0.05)
        D.new_obj(prefix + "Panel", bm, c, DARK, rbx_material="SmoothPlastic", roughness=0.6)

        # Cap: 2.0 (x) x 2.1 (y) x 0.7 with a fat 0.28 chamfer, flush with the foot's outer
        # face so the pillar's outer silhouette is one straight line foot-to-cap.
        bm = bmesh.new()
        xa, xb = xr(-1.05, 0.95)
        D.beveled_box(bm, (xa, -1.05, 5.50), (xb, 1.05, 6.20), bevel=0.28)
        D.new_obj(prefix + "Cap", bm, c, DARK, rbx_material="SmoothPlastic", roughness=0.6)

        # Top slab, 1.5 x 1.5 x 0.2, centred on the cap, mid value so the cap's dark chamfer
        # reads as a step under it.
        bm = bmesh.new()
        xa, xb = xr(-0.80, 0.70)
        D.beveled_box(bm, (xa, -0.75, 6.20), (xb, 0.75, 6.40), bevel=0.06)
        D.new_obj(prefix + "CapTop", bm, c, MID, rbx_material="SmoothPlastic", roughness=0.6)

        # Four emitter rims on the INNER face, one part. Each is an 8-gon (flat on top, like
        # the set's octagonal plinths) r 0.42, 0.30 long along X, sunk 0.05 into the column
        # face and standing 0.25 proud of it. Built with prism + Ry(90) so the phase is
        # controlled: prism extrudes local Z, Ry(90) turns local Z into world X.
        to_x = D.rot_euler(ry=90)
        bm = bmesh.new()
        xa, xb = xr(-0.80, -1.10)
        for z in BEAM_Z:
            D.prism(bm, D.ngon_pts(8, 0.42, phase=OCT), xa, xb,
                    matrix=Matrix.Translation((0.0, 0.0, z)) @ to_x)
        D.new_obj(prefix + "Emitters", bm, c, BOLT, rbx_material="Metal", metallic=0.4,
                  roughness=0.45)

        # Red Neon cores on the rim faces: 8-gon r 0.26, 0.12 long, sunk 0.02 into the rim
        # so the two faces never z-fight. Core face at |x| 1.68 - the beams start inside it.
        bm = bmesh.new()
        xa, xb = xr(-1.08, -1.22)
        for z in BEAM_Z:
            D.prism(bm, D.ngon_pts(8, 0.26, phase=OCT), xa, xb,
                    matrix=Matrix.Translation((0.0, 0.0, z)) @ to_x)
        D.new_obj(prefix + "Cores", bm, c, RED, rbx_material="Neon")

    pillar(-1, "PillarL")
    pillar(+1, "PillarR")

    # ------------------------------------------------------------------ BEAMS (Neon)
    # ONE PART EACH, Beam1 at the bottom. r 0.07 along X between the pivots; the last
    # 0.27 at each end is buried inside the emitter core + rim, so the runtime can shorten
    # or flicker a beam and it still reads as leaving the core.
    for i, z in enumerate(BEAM_Z, start=1):
        bm = bmesh.new()
        D.cyl(bm, (-BEAM_HALF, 0.0, z), (BEAM_HALF, 0.0, z), 0.07, segs=8)
        D.new_obj("Beam%d" % i, bm, c, RED, rbx_material="Neon")

    return c


# ---------------------------------------------------------------------------------------
# PART LIST - name / colour role / hex / approx tris        (tri = 44 per beveled_box,
#                                                            4n-4 per n-seg cyl / n-gon
#                                                            prism)
#   per pillar (PillarL* / PillarR*):
#   Foot            body dark   45474d   beveled_box, bevel 0.30 .........  44
#   Bolts           bolt        2f3136   3 x 6-seg cyl ...................  60
#   Column          body mid    565962   beveled_box, bevel 0.12 .........  44
#   Panel           body dark   45474d   beveled_box (thin) ..............  44
#   Cap             body dark   45474d   beveled_box, bevel 0.28 .........  44
#   CapTop          body mid    565962   beveled_box (slab) ..............  44
#   Emitters        bolt        2f3136   4 x 8-gon prism ................. 112
#   Cores           laser red   ff2f2f   4 x 8-gon prism  [NEON] ......... 112
#                                                        PILLAR subtotal   504
#   Beam1..Beam4    laser red   ff2f2f   4 x 8-seg cyl    [NEON] ......... 112
#
#   20 objects, ~1120 tris of a 1500 budget.
#   Bounding box  x -3.99..3.99  |  y -1.20..1.42  |  z 0.00..6.40  = 7.98 x 2.62 x 6.40
#   Value ladder up a pillar: DARK foot -> MID column -> DARK cap -> MID slab; DARK panel
#   on the MID column; BOLT-dark rims on the MID column; RED cores on the BOLT rims.
#   No two touching parts share a value.
# ---------------------------------------------------------------------------------------
