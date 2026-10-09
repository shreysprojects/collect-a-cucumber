"""Champion Band - tier 12: gold ring, winged trophy-cup crest, red accent panels."""
import bmesh
import math
from mathutils import Matrix, Vector

COLLECTION = "ChampionBand"
TIER = 12
DISPLAY_NAME = "Champion Band"

NOTES = (
    "Top-tier flex piece. Front is +Y: the trophy cup stands on the forehead at angle 0 "
    "and the wings sweep off angles ~56-86 (left) and their mirror (right). "
    "HEAD CLEARANCE: the tightest point anywhere on the model is the band's own inner "
    "wall at r = 0.63 (H.R_IN); every decoration is further out than that. The trophy is "
    "deliberately built around an axis at y = 0.86 rather than on the band's outer face, "
    "because a cup centred any nearer the front would put its rear rim inside the head - "
    "so the cup PROJECTS FORWARD off the brow (its base overlaps the band top from "
    "y 0.69 to 1.03 and is embedded in the top of the ring, so it reads as seated, not "
    "floating). Nearest trophy point to the axis is the deep-gold lip disc at r 0.660. "
    "ENVELOPE: radius max ~1.11 (left primary feather tip, incl. its thickness), "
    "z from -0.18 (wing root plates) to +0.709 (primary feather tips). The cup tops out "
    "at z 0.630, i.e. 0.50 studs above the band's top edge (0.13). "
    "The wings are the silhouette and are the only geometry above z 0.60. "
    "Both wings live in ONE object (Wings); the right wing is the exact mirror of the "
    "left (angle, in-plane sweep and profile x all negated), so a reflection through the "
    "YZ plane maps one onto the other. "
    "Six MeshParts, grouped by colour: Band + Cup share the mid gold f5c542 but never "
    "touch (the deep-gold stepped base sits between them); Wings are the bright gold so "
    "they read light against the mid-gold ring; GoldTrim d99a1a is every dark structural "
    "element (bottom rail, wing root plates, cup base/stem/collar/lip). "
    "Gold is Foil / Metal, the red accents are Fabric so the band still reads as cloth "
    "under the metalwork."
)

# ------------------------------------------------------------------ shared numbers
CY = 0.86           # trophy axis, y.  bowl top r 0.190 -> nearest point r 0.670 > 0.63
R_ROOT = 0.73       # feather roots sit INSIDE the band's outer wall (r_out 0.75)

BZ0, BZ1 = 0.355, 0.575     # bowl: bottom / top z
BR0, BR1 = 0.105, 0.190     # bowl: bottom / top radius (wider at the top)

# a feather blade, normalised: x in units of half-width, y in units of length.
# Simple (non-self-intersecting) 7-gon, wound CCW -> 4*7-4 = 24 tris per feather.
FEATHER_PROFILE = [(-0.55, 0.00), (0.55, 0.00), (1.00, 0.30), (0.85, 0.62),
                   (0.00, 1.00), (-0.70, 0.60), (-0.90, 0.26)]

# One wing, root to trailing edge: angle, in-plane sweep (0 = straight up, 90 = straight
# back), outward tilt, length, half-width, thickness, root z.  Decreasing size, increasing
# sweep -> the fan runs from a tall vertical primary to a short horizontal trailing quill.
FEATHERS = [
    (56.0,  4.0, 30.0, 0.34, 0.085, 0.045,  0.04),   # leading covert
    (62.0, 18.0, 26.0, 0.78, 0.100, 0.055,  0.03),   # primary - the silhouette
    (68.0, 32.0, 25.0, 0.66, 0.088, 0.050,  0.01),
    (74.0, 46.0, 24.0, 0.52, 0.075, 0.045, -0.01),
    (80.0, 60.0, 23.0, 0.40, 0.062, 0.040, -0.03),
    (86.0, 72.0, 22.0, 0.30, 0.052, 0.038, -0.05),   # trailing quill
]


def _star_pts(r_out, r_in, points=5, phase_deg=90.0):
    """A simple (non-self-intersecting) 5-point star polygon, one point straight up."""
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(phase_deg + 180.0 * i / points)
        pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    GOLD = "f5c542"      # mid gold - the ring and the cup bowl
    DEEP = "d99a1a"      # deep gold - rails, mounts, the cup's stem and base
    BRIGHT = "ffe08a"    # bright gold - the wings, lightest value, reads against sky
    RED = "c0322b"       # accent red - cloth panels and the cup's inlay
    WHITE = "ffffff"     # the star

    # ------------------------------------------------------------------ 1. BAND
    # Plain hard-edged metal ring, no bulge - this is a trophy fillet, not cloth.
    bm = bmesh.new()
    H.band(bm, r_in=H.R_IN, r_out=H.R_OUT, z0=-0.13, z1=0.13, segs=28)
    H.new_obj("Band", bm, c, GOLD, rbx_material="Foil", metallic=0.75, roughness=0.30)

    # ------------------------------------------------------------------ 2. RED ACCENTS
    # Two panels between the cup and the wings, plus a long panel across the back, all
    # proud of the ring by 0.062.  Inner radius 0.745 keeps them buried in the band.
    bm = bmesh.new()
    for a in (32.0, -32.0):
        H.stripe(bm, 0.745, 0.812, -0.115, 0.115, segs=24, arc_deg=30.0, center_deg=a)
    H.stripe(bm, 0.745, 0.812, -0.115, 0.115, segs=24, arc_deg=140.0, center_deg=180.0)
    # Red inlay filling the cup's mouth - sits 0.015 proud of the deep-gold lip disc so
    # the cup reads as an open bowl rather than a capped peg.
    H.cyl(bm, (0.0, CY, 0.605), (0.0, CY, 0.630), 0.152, segs=16)
    H.new_obj("RedAccents", bm, c, RED, rbx_material="Fabric", roughness=0.85)

    # ------------------------------------------------------------------ 3. GOLD TRIM
    bm = bmesh.new()
    # Bottom rail: frames the band from below and gives the gold a dark value to sit on.
    H.stripe(bm, 0.730, 0.790, -0.175, -0.120, segs=24)
    # Wing root plates - chunky cuffs that swallow every feather root (they cover ring
    # angles ~51 to ~85 at radius 0.700..0.820, and the roots all sit at radius 0.73).
    for a in (68.0, -68.0):
        H.cube(bm, H.on_ring(0.760, a, 0.0), (0.46, 0.12, 0.36), rot=H.face_out(a))
    # Stepped square base of the trophy, sunk 0.035 into the top of the band.
    H.box(bm, (-0.170, CY - 0.170, 0.095), (0.170, CY + 0.170, 0.150))
    H.box(bm, (-0.128, CY - 0.128, 0.150), (0.128, CY + 0.128, 0.198))
    H.box(bm, (-0.092, CY - 0.092, 0.198), (0.092, CY + 0.092, 0.232))
    # Stem, then a flared collar that the bowl flowers out of.
    H.cyl(bm, (0.0, CY, 0.232), (0.0, CY, 0.330), 0.048, segs=8)
    H.cyl(bm, (0.0, CY, 0.300), (0.0, CY, 0.380), 0.055, segs=8, r2=0.135)
    # Lip disc capping the bowl; 0.05 of gold shows all the way round the red inlay.
    H.cyl(bm, (0.0, CY, 0.550), (0.0, CY, 0.615), 0.200, segs=16)
    H.new_obj("GoldTrim", bm, c, DEEP, rbx_material="Metal", metallic=0.70, roughness=0.35)

    # ------------------------------------------------------------------ 4. CUP
    bm = bmesh.new()
    # Tapered bowl - a truncated cone, wider at the top.
    H.cyl(bm, (0.0, CY, BZ0), (0.0, CY, BZ1), BR0, segs=16, r2=BR1)
    # Two C-handles, one per flank (+/-X).  Each end is tucked inside the bowl wall:
    # the wall radius is 0.178 at z 0.545 and 0.120 at z 0.393, and the handle ends sit
    # at 0.170 and 0.115, so nothing floats.
    for sx in (1.0, -1.0):
        H.tube(bm,
               [(sx * 0.170, CY, 0.545), (sx * 0.295, CY, 0.520),
                (sx * 0.315, CY, 0.440), (sx * 0.115, CY, 0.393)],
               [0.030, 0.036, 0.036, 0.028], segs=8)
    H.new_obj("Cup", bm, c, GOLD, rbx_material="Foil", metallic=0.80, roughness=0.25)

    # ------------------------------------------------------------------ 5. WINGS
    # Both wings in ONE object.  Frame per feather:
    #   M = T(root) . Rz(-angle) . Rx(90 - tilt) . Rz(-sweep)
    # so the blade's local +Y (its spine) leaves the band pointing up, `tilt` leans it
    # outward off the head and `sweep` rakes it backward inside the wing's own plane.
    # Mirroring is exact: negate angle, negate sweep, negate the profile's x.
    bm = bmesh.new()
    for side in (1.0, -1.0):
        for angle, sweep, tilt, length, hw, thick, z_root in FEATHERS:
            a, s = side * angle, side * sweep
            m = (Matrix.Translation(Vector(H.on_ring(R_ROOT, a, z_root)))
                 @ H.rot_euler(0.0, 0.0, -a)
                 @ H.rot_euler(90.0 - tilt, 0.0, 0.0)
                 @ H.rot_euler(0.0, 0.0, -s))
            prof = [(side * px * hw, py * length) for px, py in FEATHER_PROFILE]
            H.prism(bm, prof, -thick / 2.0, thick / 2.0, matrix=m)
    H.new_obj("Wings", bm, c, BRIGHT, rbx_material="Foil", metallic=0.70, roughness=0.30)

    # ------------------------------------------------------------------ 6. STAR
    # Raised five-point star lying against the bowl's front face.  The bowl wall leans
    # out, so the star's plate is rotated about X to match that lean - otherwise it would
    # bite into the wall at the top and float clear of it at the bottom.
    nlen = math.hypot(BZ1 - BZ0, BR1 - BR0)
    ny, nz = (BZ1 - BZ0) / nlen, -(BR1 - BR0) / nlen      # outward wall normal in (y, z)
    tilt_deg = math.degrees(math.atan2(ny, -nz))          # ~68.9 deg
    zc = 0.460                                            # star centre, up the bowl
    rc = BR0 + (zc - BZ0) / (BZ1 - BZ0) * (BR1 - BR0)     # wall radius there, 0.1456
    lift = 0.035                                          # how far it stands proud
    face = (0.0, CY + rc + ny * lift, zc + nz * lift)
    bm = bmesh.new()
    # depth 0.09 along the inward normal buries the star's back face behind the wall even
    # at the widest points of the star, which sit off the flat of the 16-sided cone.
    H.prism(bm, _star_pts(0.085, 0.037), 0.0, 0.09,
            matrix=Matrix.Translation(Vector(face)) @ H.rot_euler(tilt_deg, 0.0, 0.0))
    H.new_obj("Star", bm, c, WHITE, rbx_material="SmoothPlastic", roughness=0.40)

    return c


# ---------------------------------------------------------------------------------------
# PART LIST                                       (tri maths: full band/stripe ring = 8*segs;
#                                                  an arc = 8*n + 4 caps; n-seg capped cyl
#                                                  = 4n-4; box/cube = 12; k-gon prism = 4k-4;
#                                                  p-point s-seg tube = 2s(p-1) + 2s-4)
#
#   Band          mid gold      f5c542  Foil   ring r 0.63..0.75, z +/-0.13, segs 28 ... 224
#
#   RedAccents    accent red    c0322b  Fabric
#       2 x side panel  arc 30 deg  @ +/-32                      2 x 28 ............... 56
#       back panel      arc 140 deg @ 180                                ............... 76
#       cup mouth inlay 16-seg cyl r 0.152                                .............. 60
#                                                                    subtotal .......... 192
#
#   GoldTrim      deep gold     d99a1a  Metal
#       bottom rail     full ring, segs 24, z -0.175..-0.120               ............ 192
#       2 x wing root plate    cube 0.46 x 0.12 x 0.36           2 x 12 ................ 24
#       3 x stepped base box                                     3 x 12 ................ 36
#       stem           8-seg cyl r 0.048                                   ............. 28
#       collar         8-seg tapered cyl r 0.055 -> 0.135                  ............. 28
#       lip disc      16-seg cyl r 0.200                                   ............. 60
#                                                                    subtotal .......... 368
#
#   Cup           mid gold      f5c542  Foil
#       bowl          16-seg cone r 0.105 -> 0.190, z 0.355..0.575         ............. 60
#       2 x C-handle   4-point 8-seg tube                        2 x 60 ............... 120
#                                                                    subtotal .......... 180
#
#   Wings         bright gold   ffe08a  Foil   12 feathers (6 per side) x 24 .......... 288
#
#   Star          white         ffffff  SmoothPlastic   10-gon prism, depth 0.09 ....... 36
#
#   6 objects, ~1288 tris of a 1400 budget.
#
# ENVELOPE (traced by hand, worst cases)
#   tightest radius   0.630  Band inner wall (= H.R_IN, the head).  Next tightest, in
#                            order: 0.660 cup lip disc, 0.670 bowl top, 0.690 base step A,
#                            0.698 feather root corners (buried inside the ring, whose
#                            outer wall is 0.75), 0.708 red inlay, 0.725 collar,
#                            0.730 bottom rail, 0.737 root-plate corner, 0.745 red panels,
#                            0.812 stem, 0.837 handles, 0.931 star.
#   widest radius     1.107  primary feather tip incl. its 0.055 thickness (next:
#                            1.069 star top point, 1.060 lip disc, 1.050 bowl top,
#                            1.044 base-step corner) - all inside the 1.15 limit.
#   z range          -0.180 (wing root plates) .. +0.709 (primary feather tips).
#                            Only the wings go above +0.60, as the brief allows; the cup
#                            tops out at 0.630 = 0.50 above the band's top edge (0.13).
#
# VALUE LADDER (no two touching parts share a value)
#   deep gold rail -> mid gold band -> deep gold root plate -> BRIGHT gold wing
#   mid gold band  -> deep gold stepped base -> mid gold bowl -> WHITE star
#   mid gold bowl  -> deep gold lip -> RED inlay
#   mid gold band  -> RED cloth panels (the darkest thing on the ring)
# ---------------------------------------------------------------------------------------
