"""Tier 7 headband: a plain brushed-steel ring with proud rivets - the austere one."""
import bmesh

COLLECTION = "SteelBand"
TIER = 7
DISPLAY_NAME = "Steel Band"
NOTES = (
    "Three MeshParts, grouped by colour: Band (steel b8bec6), EdgeRims (bright d5dbe4 - "
    "the top and bottom chamfer rings share one mesh), Rivets (dark steel 8a9199, six "
    "half-buried spheres). Every part is Enum.Material.Metal; no ornament by design, this "
    "is the austere tier of the set. The ring runs radius 0.635..0.80 and z -0.172..+0.172, "
    "so it is 0.344 tall and 0.165 thick against the 0.26 x 0.12 cloth bands - it should "
    "read visibly heavier next to tiers 1-6. Only the rivets leave the ring, bulging to "
    "radius 0.855. Tightest radius anywhere is 0.635: 0.035 of clearance over a default "
    "R15 head, 0.005 outside H.R_IN. Nothing rises above the band, so this one needs no "
    "special headroom when it is worn."
)

SEG = 14            # ring segments: three full rings at 8 tris/segment eat most of the budget
R_INNER = 0.635     # a hair outside H.R_IN so no vertex can ever land inside the head
R_BODY = 0.80       # outer face of the band proper (H.R_OUT is 0.75 - this one is thicker)
R_RIM = 0.772       # bright edge rings step IN; that step is the machined chamfer
Z_BODY = 0.125      # half-height of the band body
Z_RIM = 0.172       # outer top / bottom of the edge rings
RIVET_R = 0.075
RIVET_AT = 0.78     # rivet centre radius - about a third of each ball stands proud of R_BODY


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    # --- band body -------------------------------------------------------------------
    # bulge=0: this is rolled plate, not cloth, so the outer face stays dead cylindrical
    # and the top/bottom edges stay hard.
    bm = bmesh.new()
    H.band(bm, r_in=R_INNER, r_out=R_BODY, z0=-Z_BODY, z1=Z_BODY, segs=SEG, bulge=0.0)
    H.new_obj("Band", bm, c, "b8bec6", rbx_material="Metal", metallic=0.8, roughness=0.35)

    # --- machined edges ----------------------------------------------------------------
    # One brighter ring at each rim, 0.028 tighter in radius than the body. The little
    # shelf that leaves on the top and bottom faces of the body is what sells the chamfer,
    # and it costs two plain rings instead of a bevelled profile.
    bm = bmesh.new()
    for z0, z1 in ((Z_BODY, Z_RIM), (-Z_RIM, -Z_BODY)):
        H.stripe(bm, R_INNER, R_RIM, z0, z1, segs=SEG)
    H.new_obj("EdgeRims", bm, c, "d5dbe4", rbx_material="Metal",
              metallic=0.85, roughness=0.28)

    # --- rivets --------------------------------------------------------------------------
    # Six round heads, one dead centre on the forehead (start_deg=0 is +Y). Darker than the
    # band so they read as recessed hardware rather than highlights. Centred at z=0, well
    # clear of both edge rings; segs=6/rings=3 keeps each head to 24 tris.
    bm = bmesh.new()
    H.stud_ring(bm, 6, RIVET_AT, z=0.0, size=RIVET_R, kind="sphere",
                start_deg=0.0, segs=6, rings=3)
    H.new_obj("Rivets", bm, c, "8a9199", rbx_material="Metal", metallic=0.8, roughness=0.40)

    return c


# ---------------------------------------------------------------------------------------
# PARTS                     COLOUR    MATERIAL  TRIS
#   Band       body ring    b8bec6    Metal      112   (14 segs x 4 quads)
#   EdgeRims   top+bottom   d5dbe4    Metal      224   (2 rings x 14 segs x 4 quads)
#   Rivets     6 x sphere   8a9199    Metal      144   (6 x 24, segs=6 rings=3)
#                                              -----
#                                                480   of a 500 budget
#
# FIT   min radius 0.635 (band inner wall; rivets bottom out at 0.705)
#       max radius 0.855 (rivet crowns)      z range -0.172 .. +0.172
# ---------------------------------------------------------------------------------------
