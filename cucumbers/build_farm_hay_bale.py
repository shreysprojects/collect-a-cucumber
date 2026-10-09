"""Farm: Hay Bale - a round-bale-shaped CUCUMBER roll lying on its side, cut ends out."""
import bmesh, math

COLLECTION = "FarmHayBale"
NOTES = ("A 4.4 x 3.0 x 3.0 round bale that is not straw at all - it is a fat "
         "cucumber ROLL lying on its side.  The body is a 14-sided `cuke_green` "
         "cylinder whose axis runs along X from x=-2.15 to +2.15 at radius 1.45, the "
         "axis sitting at z=1.52 so the three hoops (not the skin) rest on the ground.  "
         "Sixteen `cuke_stud` raised squares are seated by hand on the curved skin "
         "across the front and the top (angles -26 deg to 194 deg round the axis), laid "
         "in the four clear x zones BETWEEN the hoops so no band buries one.  Three tan "
         "`farm_crate` bands 0.26 wide hoop the bale at x = -1.25, 0 and +1.25, radius "
         "1.52 so they stand proud of the skin and carry its weight.  BOTH flat ends "
         "are cut-cucumber faces: the green cylinder cap reads as a 0.25-wide rim round "
         "a `cuke_pale` 14-gon disc of radius 1.20 standing 0.04 proud, each disc "
         "carrying four `cuke_seed` square pips on a 0.58 ring.  Faces +Y, centred on "
         "x=0 / y=0, nothing below z=0.  Five parts: Body, Studs, Bands, Faces, Seeds.")

# ---- the roll ------------------------------------------------------------------
SEGS = 14
R = 1.45                     # roll radius
HX = 2.15                    # half length along X
ZC = 1.52                    # axis height - equals BAND_R, so the hoops touch z = 0
RR = R * math.cos(math.pi / SEGS)   # facet-plane radius: what the speckles sit on

# ---- the three hoops -----------------------------------------------------------
BAND_R = 1.52
BAND_HW = 0.13               # half width -> 0.26 wide
BAND_X = (-1.25, 0.0, 1.25)

# ---- the cut faces on both ends ------------------------------------------------
FACE_R = 1.20
FACE_Z0, FACE_Z1 = -0.03, 0.04      # local, along the end's outward normal
SEED_RING = 0.58
SEED_ANGLES = (45.0, 135.0, 225.0, 315.0)

# ---- speckles: (x along the axis, angle round the axis in degrees) -------------
# angle 0 = straight at the camera (+Y), 90 = the top of the roll, 180 = the back.
# The x values keep every square inside one of the four clear zones between hoops.
SPECKLES = [
    (-1.90, -16.0), (-1.62,  58.0), (-1.86, 126.0), (-1.58, 190.0),
    (-0.88,  22.0), (-0.46,  92.0), (-0.90, 158.0), (-0.52, -26.0),
    ( 0.44,  10.0), ( 0.90,  74.0), ( 0.48, 142.0), ( 0.86, 194.0),
    ( 1.58, -24.0), ( 1.92,  44.0), ( 1.62, 110.0), ( 1.90, 168.0),
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- the cucumber roll ------------------------------------------------
    bm = bmesh.new()
    D.cyl(bm, (-HX, 0.0, ZC), (HX, 0.0, ZC), R, segs=SEGS)
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the set's raised squares, seated on the curved skin ---------------
    bm = bmesh.new()
    for u, deg in SPECKLES:
        a = math.radians(deg)
        point = (u, math.cos(a) * RR, ZC + math.sin(a) * RR)
        normal = (0.0, math.cos(a), math.sin(a))
        D.stud_patch(bm, point, normal, size=0.30, rise=0.05, bevel=0.03)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- three tan bands hooping the bale ----------------------------------
    bm = bmesh.new()
    for bx in BAND_X:
        D.cyl(bm, (bx - BAND_HW, 0.0, ZC), (bx + BAND_HW, 0.0, ZC), BAND_R, segs=SEGS)
    D.new_obj("Bands", bm, c, D.C("farm_crate"), rbx_material="Fabric")

    # ---- both flat ends are cut-cucumber faces -----------------------------
    # the green cylinder cap is left showing as the rim; a pale 14-gon disc stands
    # proud of it.  s = +1 is the +X end, s = -1 the -X end.
    bm = bmesh.new()
    pts = D.ngon_pts(SEGS, FACE_R, phase=math.pi / SEGS)
    for s in (1.0, -1.0):
        D.prism(bm, pts, FACE_Z0, FACE_Z1,
                matrix=D.place((s * HX, 0.0, ZC), D.rot_euler(0.0, s * 90.0, 0.0)))
    D.new_obj("Faces", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    # ---- four pips on each cut face ----------------------------------------
    bm = bmesh.new()
    for s in (1.0, -1.0):
        x = s * (HX + FACE_Z1)
        for deg in SEED_ANGLES:
            a = math.radians(deg)
            D.stud_patch(bm, (x, math.cos(a) * SEED_RING, ZC + math.sin(a) * SEED_RING),
                         (s, 0.0, 0.0), size=0.24, rise=0.03, sink=0.05, bevel=0.02)
    D.new_obj("Seeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    return c
