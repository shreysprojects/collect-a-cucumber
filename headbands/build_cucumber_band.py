"""Tier 4 'Cucumber Band' - a bright green band ringed with six cucumber slices."""
import bmesh
import math
from mathutils import Matrix, Vector

COLLECTION = "CucumberBand"
TIER = 4
DISPLAY_NAME = "Cucumber Band"
NOTES = ("Signature item. Four MeshParts, one per colour: Band / Rinds / Flesh / Seeds. "
         "Six slices at 0, 60, 120, 180, 240, 300 deg - the 0 deg one is dead centre on "
         "the forehead (+Y), so the accessory must not be yaw-offset on install. "
         "Nothing reaches inside radius 0.63 (the band's own inner wall is the tightest "
         "point); everything lives in z -0.17..+0.17, well inside the head clearance.")

# ---------------------------------------------------------------- palette
C_BAND = "5aa832"          # mid green - darker than the flesh so the slices pop
C_RIND = "2f7d2a"          # dark green rind
C_FLESH = "d8f0b0"         # pale green flesh
C_SEED = "9ec96a"          # seed marks

# ---------------------------------------------------------------- dial box
SLICE_N = 6                # slices around the band
BAND_SEGS = 28             # plain ring, no bulge (224 tris)
DISC_SEGS = 10             # facets per slice disc - reads round at 0.34 studs across

# radii below are distances from the band AXIS; the band itself is 0.63 -> 0.75
R_RIND_BACK = 0.700        # buried inside the band wall, so no seam
R_RIND_FRONT = 0.845       # rind face stands 0.095 proud of the band
R_FLESH_BACK = 0.835       # overlaps the rind by 0.01 - no gap
R_FLESH_FRONT = 0.875
R_SEED_BACK = 0.868        # sunk 0.007 into the flesh
R_SEED_FRONT = 0.902       # seeds sit 0.027 proud of the flesh

RIND_R = 0.170             # slice is 0.34 studs across
FLESH_R = 0.132            # leaves a 0.038 ring of rind showing all round

SEED_PHI = (45.0, 135.0, 225.0, 315.0)   # rosette, off the vertical/horizontal axes
SEED_RING_R = 0.062        # seed centre, out from the slice centre
SEED_HALF_LEN = 0.030      # 0.06 long, pointing in toward the slice centre
SEED_HALF_WID = 0.018      # 0.036 across


def _seed_face_pts(phi_deg):
    """A seed's triangle in SLICE-FACE coords (u = tangential, v = up), tip inward."""
    r = math.radians(phi_deg)
    nu, nv = math.cos(r), math.sin(r)            # outward across the slice face
    tu, tv = -nv, nu                             # across the seed
    cu, cv = SEED_RING_R * nu, SEED_RING_R * nv
    return [
        (cu - nu * SEED_HALF_LEN, cv - nv * SEED_HALF_LEN),
        (cu + nu * SEED_HALF_LEN + tu * SEED_HALF_WID,
         cv + nv * SEED_HALF_LEN + tv * SEED_HALF_WID),
        (cu + nu * SEED_HALF_LEN - tu * SEED_HALF_WID,
         cv + nv * SEED_HALF_LEN - tv * SEED_HALF_WID),
    ]


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    angles = H.ring_angles(SLICE_N)              # 0 = forehead (+Y), then every 60 deg

    # ---- 1. the band: plain mid-green ring, 0.63 -> 0.75, 0.26 tall
    bm = bmesh.new()
    H.band(bm, segs=BAND_SEGS)
    H.new_obj("Band", bm, c, C_BAND, rbx_material="Plastic")

    # ---- 2. dark rind discs - short cylinders aimed radially outward
    bm = bmesh.new()
    for a in angles:
        H.cyl(bm, H.on_ring(R_RIND_BACK, a, 0.0), H.on_ring(R_RIND_FRONT, a, 0.0),
              RIND_R, segs=DISC_SEGS)
    H.new_obj("Rinds", bm, c, C_RIND, rbx_material="Plastic")

    # ---- 3. pale flesh discs, slightly smaller and proud of the rind
    bm = bmesh.new()
    for a in angles:
        H.cyl(bm, H.on_ring(R_FLESH_BACK, a, 0.0), H.on_ring(R_FLESH_FRONT, a, 0.0),
              FLESH_R, segs=DISC_SEGS)
    H.new_obj("Flesh", bm, c, C_FLESH, rbx_material="SmoothPlastic")

    # ---- 4. seed rosettes on each flesh face
    # face_out() puts local +Y radially out; rot_euler(-90,0,0) then swings prism's
    # extrusion axis (+Z) onto it, so a profile (x, y) lands as (tangential, DOWN)
    # and the prism thickens outward along the radius.
    bm = bmesh.new()
    depth = R_SEED_FRONT - R_SEED_BACK
    for a in angles:
        m = (Matrix.Translation(Vector(H.on_ring(R_SEED_BACK, a, 0.0)))
             @ H.face_out(a) @ H.rot_euler(-90, 0, 0))
        for phi in SEED_PHI:
            pts = [(u, -v) for (u, v) in _seed_face_pts(phi)]
            H.prism(bm, pts, 0.0, depth, matrix=m)
    H.new_obj("Seeds", bm, c, C_SEED, rbx_material="SmoothPlastic")

    return c


# ---------------------------------------------------------------- parts / budget
# Part    Colour   Material        Pieces  Tris
# Band    5aa832   Plastic         1 ring    224   (28 segs x 4 quads)
# Rinds   2f7d2a   Plastic         6 discs   216   (6 x 10-seg capped cylinder)
# Flesh   d8f0b0   SmoothPlastic   6 discs   216   (6 x 10-seg capped cylinder)
# Seeds   9ec96a   SmoothPlastic   24 seeds  192   (24 x triangular prism)
#                                  TOTAL     848   of a 900 budget
#
# Fit: tightest radius anywhere = 0.630 (the band's inner wall) - exactly the head line.
# Every slice part starts at radius 0.700 or further out; widest point is a seed tip at
# 0.905. Vertical extent z -0.162 .. +0.162 (the 0.34 discs overhang the 0.26-tall band
# top and bottom, which is what makes them read as mounted slices).
