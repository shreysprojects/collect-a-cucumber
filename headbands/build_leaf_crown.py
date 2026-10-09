"""Tier 6 'Leaf Crown' - a Roman laurel: two leafed vines meeting low at the forehead."""
import bmesh
import math
from mathutils import Matrix, Vector

COLLECTION = "LeafCrown"
TIER = 6
DISPLAY_NAME = "Leaf Crown"
NOTES = (
    "NOT a closed band - the signature is the open V over the forehead. The two vines meet "
    "under a gold bud at angle 0 (front) and sweep back to a second bud at the nape; every "
    "leaf leans BACKWARD along its own vine, so the front-top stays empty. Do not add a "
    "ring to 'close' it. Four MeshParts, grouped by colour; the two greens alternate along "
    "each vine so every overlap shows a value step. Tightest radius is 0.662 (the vine), "
    "so it clears a 1.2-stud R15 head with ~0.06 of slack; top of the leaves is z 0.41."
)

# ---------------------------------------------------------------- wreath geometry
N_LEAF = 12          # leaves per vine -> 24 total
A_FIRST = 13.0       # ring angle of the front-most leaf (the V opens between -13 and +13)
A_LAST = 169.0       # ring angle of the back-most leaf
A_VINE0 = 4.0        # vine ends: front tie ...
A_VINE1 = 177.0      # ... and nape tie
R_VINE = 0.710       # vine path radius   (min radius 0.710*cos(9.6) - 0.038 = 0.662)
R_LEAF = 0.720       # leaf base radius   (min radius 0.720 - 0.021 = 0.699)
Z_FRONT = -0.090     # vine height at the front tie
Z_RISE = 0.200       # how much the vine climbs from the forehead to the nape


def _t(angle_deg):
    """Wreath parameter: 0 at the front-most leaf, 1 at the back-most one."""
    return max(0.0, min(1.10, (abs(angle_deg) - A_FIRST) / (A_LAST - A_FIRST)))


def _z(angle_deg):
    """Vine height at a ring angle - lowest over the brow, climbing round to the nape.
    This rise is what makes the wreath read as a U from the front."""
    return Z_FRONT + Z_RISE * (_t(angle_deg) ** 0.8)


def _leaf_on_vine(H, bm, angle_deg, length, width, tilt_deg, sweep_deg, curl_deg,
                  thick=0.042):
    """One laurel leaf standing on the vine.

    H.leaf() tilts a blade out from vertical but has no sweep ALONG the ring, and a laurel
    lives on that sweep - the leaves have to lie back over their neighbours like scales.
    So build the blade at the origin (there face_out is the identity, local X = tangent,
    Y = radial out, Z = up), then re-apply the ring frame ourselves with an extra rotation
    about the radial axis.  Ry leaves the radial component alone, so a sweep can never
    push a vertex inward toward the head.

    sweep_deg > 0 leans the tip toward increasing ring angle.  Passing side*sweep and
    side*curl makes the right-hand vine an exact mirror of the left (the leaf profile is
    symmetric in its own X, which is what makes the mirror come out exact).
    """
    vs = H.leaf(bm, (0.0, 0.0, 0.0), length, width, angle_deg=0.0,
                tilt_deg=tilt_deg, curl_deg=curl_deg, thick=thick)
    m = (Matrix.Translation(Vector(H.on_ring(R_LEAF, angle_deg, _z(angle_deg))))
         @ H.rot_euler(0.0, 0.0, -angle_deg)
         @ H.rot_euler(0.0, sweep_deg, 0.0))
    H.xform(bm, vs, m)
    return vs


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    # ---- 1. the two vines ------------------------------------------------------------
    # A slim tapered twig each, not a band: thickest at the front tie, thinning to the
    # nape.  Mostly buried under the leaf bases; only the bare front span shows.
    bm = bmesh.new()
    for side in (1.0, -1.0):
        pts, radii = [], []
        n = 10
        for k in range(n):
            u = k / (n - 1.0)
            a = side * (A_VINE0 + (A_VINE1 - A_VINE0) * u)
            pts.append(H.on_ring(R_VINE, a, _z(a)))
            radii.append(0.038 - 0.012 * u)
        H.tube(bm, pts, radii, segs=5)
    H.new_obj("Vines", bm, c, "4a5c2a", rbx_material="Wood", roughness=0.85)

    # ---- 2. the leaves ---------------------------------------------------------------
    # Length humps in the middle of each vine and tapers at both ends; the blades stand
    # nearly upright at the brow (tilt 20) and lie further out toward the nape (tilt 42),
    # every one swept ~30 deg back along the ring so it overlaps its two neighbours.
    bm_mid, bm_dark = bmesh.new(), bmesh.new()
    for i, a0 in enumerate(H.ring_angles(N_LEAF, span_deg=A_LAST - A_FIRST,
                                         center_deg=(A_FIRST + A_LAST) / 2.0)):
        t = i / (N_LEAF - 1.0)
        length = 0.360 + 0.150 * math.sin(math.pi * (t ** 0.7))   # 0.36 .. 0.51 .. 0.36
        width = length * 0.42                                     # lance-shaped, laurel
        tilt = 20.0 + 22.0 * t
        sweep = 32.0 - 8.0 * t
        curl = 5.0 if (i % 2 == 0) else -5.0
        target = bm_mid if (i % 2 == 0) else bm_dark
        for side in (1.0, -1.0):
            _leaf_on_vine(H, target, side * a0, length, width,
                          tilt, side * sweep, side * curl)
    H.new_obj("LeavesMid", bm_mid, c, "3f9b3a", rbx_material="Grass", roughness=0.72)
    H.new_obj("LeavesDark", bm_dark, c, "2d7a28", rbx_material="Grass", roughness=0.80)

    # ---- 3. gold buds ----------------------------------------------------------------
    # The tie at the front (covers the 0.099 gap between the two vine ends), a small pair
    # flanking it, a berry tucked at each front leaf join, and the tie at the nape.
    bm = bmesh.new()
    for a, r, dz, s in ((0.0, 0.735, 0.002, 0.052),
                        (9.0, 0.730, 0.004, 0.038),
                        (-9.0, 0.730, 0.004, 0.038),
                        (34.0, 0.775, 0.050, 0.036),
                        (-34.0, 0.775, 0.050, 0.036),
                        (180.0, 0.730, 0.012, 0.050)):
        H.octa_gem(bm, H.on_ring(r, a, _z(a) + dz), s, a, point=1.4, flat=0.8)
    H.new_obj("Buds", bm, c, "e8c34a", rbx_material="Metal", metallic=0.8, roughness=0.35)

    return c


# ---------------------------------------------------------------------------------------
# PARTS
#   Vines       2 tapered 5-gon tubes, 10 path points each, r 0.038 -> 0.026,
#               path radius 0.710, z -0.090 -> +0.116        4a5c2a  Wood    192 tris
#   LeavesMid   12 leaves (even index, both vines), 20 tris each
#                                                            3f9b3a  Grass   240 tris
#   LeavesDark  12 leaves (odd index, both vines), 20 tris each
#                                                            2d7a28  Grass   240 tris
#   Buds        6 octa_gems: front tie, 2 flankers, 2 berries, nape tie
#                                                            e8c34a  Metal    48 tris
#                                                                    TOTAL   720 tris
#
# FIT
#   tightest radius  0.662  (vine chord midpoint: 0.710*cos(9.6 deg) - 0.038)
#                    0.699  (leaf base, 0.720 - half-thickness * cos(tilt))
#                    0.693  (front bud, 0.735 - 0.052*0.8)          limit 0.63  OK
#   widest radius     1.016 (leaf tips at the sides)                limit 1.15  OK
#   z range          -0.140 (front bud underside) .. +0.412 (leaf tips at the sides)
#                                                                   limit -0.35..0.60  OK
#   open V           no geometry between -13 and +13 above z 0.0 except the front buds
# ---------------------------------------------------------------------------------------
