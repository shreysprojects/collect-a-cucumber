"""Red Bandana - tier 2.  A wrapped red cloth band with the knot and two pointed tails
tied off at the wearer's LEFT (ring angle 90), pitched so both tails flick out and down."""
import bmesh
from mathutils import Matrix, Vector

COLLECTION = "RedBandana"
TIER = 2
DISPLAY_NAME = "Red Bandana"

NOTES = (
    "Fit: tightest vertex radius is 0.640 (the band's inner wall) against the 0.63 head "
    "limit, and every ring here is built with enough segments that the FACE chords never "
    "dip inside 0.63 either - a 22-gon at r_in 0.640 bottoms out at 0.6335, a 16-gon at "
    "0.660 at 0.6473. Widest point is 1.14 (the upper tail's tip ring); z spans "
    "-0.302 .. +0.201, so nothing needs the above-0.60 allowance. "
    "CLOTH, NOT A WASHER: the main ring carries bulge 0.028 plus a seeded per-segment "
    "radial jitter of +/-0.014, so its outer wall breathes between 0.731 and 0.759 and "
    "the closing seam (row 21 -> row 0) reads as the overlap where the cloth is tucked "
    "under itself. The top edge is deliberately NOT a circle: band() cannot vary z per "
    "segment, so the height variation is added as separate geometry - one lighter-red "
    "fold arc riding the top edge across the forehead (ring angles -100 to +60, cresting "
    "to z 0.178) and five hand-tuned crest slabs around the back at z 0.131..0.152, each "
    "at its own tilt. Nothing is random at build time; the crest table is literal, so two "
    "builds are bit-identical. "
    "KNOT: H.knot() only drops its SECOND tail (tail_drop), which would leave one tail "
    "sticking out dead level. So the knot is built into its own bmesh at the ORIGIN with "
    "angle_deg 90, then transformed by Translation(0.79, 0, -0.012) @ rot_euler(0, 14, 0) "
    "- a 14 deg pitch about +Y tips the outward axis (+X at angle 90) downward, so BOTH "
    "tails flick out and down, one at z -0.09 and the lower one at z -0.28. The knot's "
    "own dark cinch strap gets the matching tilt via H.face_out(90, -14). "
    "PARTS: five MeshParts over the brief's three reds. The light-red fold cloth and the "
    "deep-red shadow cloth are each grouped into one bmesh per REGION rather than one per "
    "detail - all five crest slabs plus the fold arc are a single object, and the knot's "
    "underside lump plus its cinch strap are a single object. The knot is split off from "
    "the band's fold cloth (same hex), and the hem off the knot shadow (same hex), only "
    "because knot and band are physically separate elements the installer may want to "
    "weld, offset or swap on their own. All five are Fabric."
)

# ---- band ------------------------------------------------------------------
BAND_RIN = 0.640      # 22-gon chord bottoms out at 0.6335 - clear of the 0.63 head limit
BAND_ROUT = 0.745
BAND_Z0, BAND_Z1 = -0.130, 0.130
BAND_SEGS = 22
BAND_BULGE = 0.028    # max outer reach = 0.745 + 0.014 jitter + 0.028 = 0.787
BAND_JITTER = 0.014
BAND_SEED = 5

# ---- deep-red hem under the band -------------------------------------------
HEM_RIN, HEM_ROUT = 0.660, 0.788    # 16-gon: inner chord 0.6473, outer chord 0.7729,
HEM_Z0, HEM_Z1 = -0.162, -0.086     # so the hem stays proud of the band's 0.759 max
HEM_SEGS = 16

# ---- lighter-red fold arc riding the top edge across the forehead ----------
FOLD_RIN, FOLD_ROUT = 0.685, 0.800
FOLD_Z0, FOLD_Z1 = 0.055, 0.178
FOLD_ARC, FOLD_CENTER = 160.0, -20.0   # spans -100 .. +60, stopping 30 deg short of the knot
FOLD_SEGS = 20                         # -> 9 spans, inner chord 0.6768

# ring angle, ring radius, z, tangential, radial, vertical, tilt.
# Crest folds that break the top edge round the back.  Literal, never RNG.
_CRESTS = (
    (126.0, 0.734, 0.136, 0.175, 0.112, 0.076, -7.0),
    (161.0, 0.741, 0.150, 0.205, 0.122, 0.092,  5.0),
    (197.0, 0.732, 0.131, 0.160, 0.106, 0.068, -9.0),
    (233.0, 0.743, 0.152, 0.190, 0.126, 0.086,  6.0),
    (269.0, 0.736, 0.139, 0.172, 0.114, 0.079, -4.0),
)

# ---- knot ------------------------------------------------------------------
KNOT_ANGLE = 90.0     # the wearer's LEFT - the reference's 3-o'clock tie
KNOT_R = 0.790        # ring radius of the knot's centre
KNOT_Z = -0.012
KNOT_SIZE = 0.135
KNOT_TAIL = 0.220     # keeps the upper tail's tip ring at radius 1.139 (<= 1.15)
KNOT_DROP = 0.200
KNOT_PITCH = 14.0     # deg the whole tie is pitched nose-down about +Y


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    # 1 - the wrapped band ---------------------------------------------- 264 tris
    bm = bmesh.new()
    H.band(bm, r_in=BAND_RIN, r_out=BAND_ROUT, z0=BAND_Z0, z1=BAND_Z1,
           segs=BAND_SEGS, bulge=BAND_BULGE, seed=BAND_SEED, jitter=BAND_JITTER)
    H.new_obj("Band", bm, c, "c0322b", rbx_material="Fabric")

    # 2 - deep-red hem rolled under the band's lower edge ---------------- 128 tris
    bm = bmesh.new()
    H.stripe(bm, HEM_RIN, HEM_ROUT, HEM_Z0, HEM_Z1, segs=HEM_SEGS)
    H.new_obj("LowerHem", bm, c, "8f231d", rbx_material="Fabric")

    # 3 - lit cloth: the forehead fold arc + five crest slabs ------------ 136 tris
    bm = bmesh.new()
    H.band(bm, r_in=FOLD_RIN, r_out=FOLD_ROUT, z0=FOLD_Z0, z1=FOLD_Z1,
           segs=FOLD_SEGS, arc_deg=FOLD_ARC, center_deg=FOLD_CENTER,
           seed=11, jitter=0.009)
    for ang, rad, z, sx, sy, sz, tilt in _CRESTS:
        H.cube(bm, H.on_ring(rad, ang, z), (sx, sy, sz), rot=H.face_out(ang, tilt))
    H.new_obj("BandFolds", bm, c, "d94a3d", rbx_material="Fabric")

    # 4 - the tie: lump + two tapered tails, pitched down then set on the ring
    bm = bmesh.new()                                                    # 84 tris
    kv = H.knot(bm, (0.0, 0.0, 0.0), KNOT_SIZE, angle_deg=KNOT_ANGLE,
                tail_len=KNOT_TAIL, tail_drop=KNOT_DROP, seed=2)
    H.xform(bm, kv, Matrix.Translation(Vector((KNOT_R, 0.0, KNOT_Z)))
            @ H.rot_euler(0, KNOT_PITCH, 0))
    H.new_obj("Knot", bm, c, "d94a3d", rbx_material="Fabric")

    # 5 - the knot's shadow: underside lump + the dark cinch across it ---- 32 tris
    bm = bmesh.new()
    H.ico(bm, (0.775, 0.0, -0.088), 0.108, subdiv=1, scale=(0.82, 1.05, 0.60))
    H.cube(bm, (0.800, 0.0, 0.000), (0.082, 0.250, 0.235),
           rot=H.face_out(KNOT_ANGLE, -KNOT_PITCH))
    H.new_obj("KnotShadow", bm, c, "8f231d", rbx_material="Fabric")

    return c


# ============================================================================
# PARTS                       colour     material   tris
#   Band                      c0322b     Fabric      264   22 segs x 6 quads (bulge)
#   LowerHem                  8f231d     Fabric      128   16 segs x 4 quads
#   BandFolds                 d94a3d     Fabric      136   arc 76 + 5 crest cubes 60
#   Knot                      d94a3d     Fabric       84   ico 20 + 2 tubes @ 32
#   KnotShadow                8f231d     Fabric       32   ico 20 + cinch cube 12
#                                                    ---
#                                          TOTAL     644   (budget 700)
#
# VALUE LADDER (why it reads at accessory size): d94a3d (light) crests and knot sit
# directly on the c0322b (mid) band, which sits on the 8f231d (dark) hem.  Every seam
# in the silhouette is a value step, not just a hue step.
#
# RADIUS TRACE - tightest point of every part (head limit 0.63, outer limit 1.15):
#   Band       inner verts 0.640; 22-gon face chord 0.640*cos(8.18) = 0.6335
#              outer max 0.745 + 0.014 + 0.028 = 0.787
#   LowerHem   inner verts 0.660; face chord 0.660*cos(11.25) = 0.6473
#              outer 0.788; outer chord 0.7729 > the band's 0.759 max, so it stays proud
#   BandFolds  arc inner 0.685; 9 spans of 17.8 deg -> chord 0.685*cos(8.9) = 0.6768
#              crests: worst radial half-extent 0.0672 (the 233 deg slab, tilt 6),
#              so 0.743 - 0.0672 = 0.6758; widest crest corner 0.816
#   Knot       ico r 0.135 scaled (1.0, 0.85, 0.9) then pitched 14 deg about +Y.
#              On the unit sphere min(0.1310*x + 0.0294*z) = -0.1343, so the lump
#              cannot get nearer than 0.790 - 0.1343 = 0.6557.
#   KnotShadow lump 0.775 - 0.0886 = 0.6864; cinch strap radial half-extent
#              0.125*cos14 + 0.1175*sin14 = 0.1497 -> 0.800 - 0.1497 = 0.6504
#   MINIMUM OVER EVERYTHING = 0.640 (the band's inner wall).
#
# TAIL TRACE (knot built at the origin, then Ry(14), then +(0.790, 0, -0.012)):
#   upper tail tip rel (0.3145,  0.2295,  0.000) -> (1.0952,  0.2295, -0.088)  R 1.119
#   lower tail tip rel (0.3145, -0.1836, -0.200) -> (1.0468, -0.1836, -0.282)  R 1.063
#   tip rings are radius 0.02, so the true extremes are R 1.139 and z -0.302.
#
# Z RANGE  -0.302 (lower tail tip) .. +0.201 (the 233 deg crest's top corner).
# ============================================================================
