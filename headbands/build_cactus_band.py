"""Tier 8 'Cactus Band' - a green band with cactus pads growing off it and white daisies."""
import bmesh
import math
from mathutils import Matrix, Vector

COLLECTION = "CactusBand"
TIER = 8
DISPLAY_NAME = "Cactus Band"
NOTES = (
    "Six MeshParts, one per colour: Band / CactusPads / CactusHighlight / Spines / "
    "Petals / FlowerCentres. Four cactus clusters sit round the ring at -42, 50, 138 and "
    "230 deg (0 deg = forehead / +Y); three five-petal daisies fill the gaps at -6, 92 "
    "and 185 deg, so the -6 one lands on the forehead and MUST NOT be yaw-offset away "
    "from it on install. Every pad is buried to z=0.03 inside the band, i.e. its widest "
    "cross-section is still inside the ring, so no pad floats or shows a neck. Tightest "
    "vertex radius anywhere is 0.630 - the band's own inner wall; the nearest decoration "
    "to the head is a cactus pad at 0.676, so there is 0.076 of clearance over a default "
    "R15 head. Vertical extent is z -0.130 .. +0.336 (the band is -0.130..+0.130; only "
    "the pads, their ribs and their spines go above it), so the piece sits well inside "
    "the standard z -0.35..+0.60 envelope and needs no headroom waiver. Widest point is "
    "a spine tip at radius 0.848. No moving parts, no centrepiece."
)

# ---------------------------------------------------------------- palette
C_BAND = "5f9e3f"          # mid green fabric ring
C_CACTUS = "4a8c3a"        # cactus pad body - a step DARKER than the band
C_HILITE = "6fb54d"        # cactus highlight - small buds + the vertical ribs
C_SPINE = "e8e0b0"         # pale spines
C_PETAL = "ffffff"         # daisy petals
C_CENTRE = "f5c542"        # daisy centre

# ---------------------------------------------------------------- dial box
SEED = 831
BAND_SEGS = 18             # 18 x 6 quads with the bulge on = 216 tris
BAND_BULGE = 0.028         # soft cloth ring: outer wall swells to 0.778 at mid height

PAD_R = 0.725              # ring radius of a pad's CENTRE
PAD_Z0 = 0.030             # every pad's underside, i.e. how deep it sits in the band
PAD_LEAN = (4.0, 10.0)     # deg the pad tops lean outward (negative tilt in face_out)

DAISY_R = 0.780            # radius of the petal slab's mid-plane
PETAL_T = 0.050            # petal thickness, radial (0.755 .. 0.805)
# petal profile in the flower plane, tip along +Y; 0.118 long, 0.072 across
PETAL_PTS = [(0.0, 0.018), (0.036, 0.062), (0.0, 0.118), (-0.036, 0.062)]
CENTRE_R0 = DAISY_R - 0.020    # centre disc back face - rooted inside the petal slab
CENTRE_R1 = DAISY_R + 0.050    # centre disc front face, 0.025 proud of the petals

# Cluster centre angle, then its pads: (d_angle, height, half_tangential, half_radial,
# big?).  "big" pads are the dark 4a8c3a body; the small ones are the 6fb54d buds.  Every
# pad is scaled narrow in the RADIAL axis so it hugs the ring instead of sticking out.
CLUSTERS = (
    (-42.0, ((0.0, 0.300, 0.100, 0.058, True),
             (13.0, 0.210, 0.076, 0.050, True),
             (-12.0, 0.180, 0.066, 0.045, False))),
    (50.0, ((0.0, 0.270, 0.095, 0.056, True),
            (-13.0, 0.190, 0.070, 0.048, False))),
    (138.0, ((0.0, 0.290, 0.098, 0.057, True),
             (13.0, 0.220, 0.078, 0.050, True),
             (-12.0, 0.185, 0.068, 0.046, False))),
    (230.0, ((0.0, 0.260, 0.092, 0.055, True),
             (12.0, 0.200, 0.072, 0.048, False))),
)

# (ring angle, z of the flower centre, roll of the petal rosette)
DAISIES = ((-6.0, 0.010, 18.0), (92.0, 0.000, -10.0), (185.0, 0.020, 6.0))

N_RIBBED = 3               # how many pads get the pair of vertical ribs
RIB_PSI = 25.0             # deg either side of the pad's outward meridian
RIB_RADII = (0.014, 0.022, 0.012)   # tapered ridge, thickest at mid height

SPINE_LEN = (0.055, 0.075)
SPINE_R = 0.019


def _pads(H, rng):
    """Every cactus pad as a dict: world centre `p`, frame `m`, and its three semi-axes
    (`ht` tangential, `hr` radial, `hh` vertical) in that frame.

    face_out(a, tilt) puts local +Y radially outward and local +X along the ring, so
    scaling (ht, hr, hh) squashes the sphere in exactly the axes we care about.  A
    NEGATIVE tilt leans the pad's top outward, away from the head."""
    out = []
    for a0, specs in CLUSTERS:
        for d_ang, height, ht, hr, big in specs:
            hh = 0.5 * height * (1.0 + rng.uniform(-0.08, 0.08))
            ht = ht * (1.0 + rng.uniform(-0.06, 0.06))
            hr = hr * (1.0 + rng.uniform(-0.05, 0.05))
            tilt = -rng.uniform(*PAD_LEAN)
            ang = a0 + d_ang + rng.uniform(-2.0, 2.0)
            z = PAD_Z0 + hh * math.cos(math.radians(tilt))
            out.append({"m": H.face_out(ang, tilt),
                        "p": Vector(H.on_ring(PAD_R, ang, z)),
                        "ht": ht, "hr": hr, "hh": hh, "big": big})
    return out


def _to_world(pad, local):
    """A point given in a pad's own (tangential, radial, up) frame -> world."""
    return tuple(pad["p"] + (pad["m"].to_3x3() @ Vector(local)))


def _surface(pad, phi, psi_deg):
    """A point ON a pad's ellipsoid surface: `phi` is the height fraction (-1..1) and
    `psi_deg` the angle round the pad measured from its outward meridian.  Keep |psi|
    under ~70 so the detail lands on the half a player can actually see."""
    k = math.sqrt(max(0.0, 1.0 - phi * phi))
    psi = math.radians(psi_deg)
    return Vector((pad["ht"] * k * math.sin(psi),
                   pad["hr"] * k * math.cos(psi),
                   pad["hh"] * phi))


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    rng = H.random.Random(SEED)
    pads = _pads(H, rng)
    # the ribs go on the tallest pads - they are the only ones with room for a ridge that
    # reads at this scale.  Sorted so the choice never depends on dict order.
    ribbed = sorted(range(len(pads)),
                    key=lambda i: (-pads[i]["hh"] if pads[i]["big"] else 9.0, i))[:N_RIBBED]

    # ---- 1. the band: soft green cloth ring, 0.630 -> 0.778 at mid height -------------
    bm = bmesh.new()
    H.band(bm, segs=BAND_SEGS, bulge=BAND_BULGE)
    H.new_obj("Band", bm, c, C_BAND, rbx_material="Fabric", roughness=0.90)

    # ---- 2. the cactus pads: upright squashed spheres, 2-3 per cluster ----------------
    # Each one is buried 0.03..0.13 inside the band, so at the band's top rim the pad is
    # still ~94% of its full width and reads as growing out of the cloth, not sitting on
    # top of it.
    bm = bmesh.new()
    for pad in pads:
        if pad["big"]:
            H.uvsphere(bm, tuple(pad["p"]), 1.0, segs=6, rings=4, rot=pad["m"],
                       scale=(pad["ht"], pad["hr"], pad["hh"]))
    H.new_obj("CactusPads", bm, c, C_CACTUS, rbx_material="Plastic", roughness=0.75)

    # ---- 3. highlight green: the small buds AND the ribbing --------------------------
    # A rib is a 3-sided tube whose spine walks the pad's own surface at phi -0.5, 0,
    # +0.5, so the ridge follows the curve instead of standing off it at the ends.  Its
    # centreline sits ON the surface, so roughly half the tube is buried and it protrudes
    # by its radius - 0.022 at mid height, tapering to 0.012.
    bm = bmesh.new()
    for pad in pads:
        if not pad["big"]:
            H.uvsphere(bm, tuple(pad["p"]), 1.0, segs=6, rings=3, rot=pad["m"],
                       scale=(pad["ht"], pad["hr"], pad["hh"]))
    for i in ribbed:
        pad = pads[i]
        for side in (-1.0, 1.0):
            spine = [_to_world(pad, _surface(pad, phi, side * RIB_PSI))
                     for phi in (-0.5, 0.0, 0.5)]
            H.tube(bm, spine, list(RIB_RADII), segs=3)
    H.new_obj("CactusHighlight", bm, c, C_HILITE, rbx_material="SmoothPlastic",
              roughness=0.70)

    # ---- 4. spines: tiny 4-sided cones scattered over every pad, one object -----------
    # Direction is the true ellipsoid normal, cocked upward, and the base is pushed 0.012
    # back down that normal so each spine is rooted in the pad rather than balanced on it.
    bm = bmesh.new()
    rng = H.random.Random(SEED + 17)
    for i, pad in enumerate(pads):
        n_spine = 3 if i in ribbed else (2 if pad["big"] else 1)
        for _ in range(n_spine):
            phi = rng.uniform(-0.55, 0.62)
            psi = rng.uniform(-58.0, 58.0)
            s = _surface(pad, phi, psi)
            n = Vector((s.x / (pad["ht"] ** 2), s.y / (pad["hr"] ** 2),
                        s.z / (pad["hh"] ** 2)))
            n.normalize()
            n = (n + Vector((0.0, 0.0, 0.45)))
            n.normalize()
            length = rng.uniform(*SPINE_LEN)
            H.cone(bm, _to_world(pad, s - n * 0.012), _to_world(pad, s + n * length),
                   SPINE_R, 0.0, segs=4)
    H.new_obj("Spines", bm, c, C_SPINE, rbx_material="SmoothPlastic", roughness=0.55)

    # ---- 5. daisy petals -------------------------------------------------------------
    # face_out(a) puts local +Y radially out; rot_euler(90,0,0) then swings prism's
    # extrusion axis (+Z) onto -Y, so the flat profile lands in the plane TANGENT to the
    # band (x = along the ring, y = up) and the slab thickens radially.  The slab spans
    # radius 0.755..0.805, and the band's outer wall is 0.778 at mid height, so every
    # daisy is half sunk into the cloth all the way to its petal tips.
    bm = bmesh.new()
    rng = H.random.Random(SEED + 41)
    for ang, z, roll in DAISIES:
        base = Matrix.Translation(Vector(H.on_ring(DAISY_R, ang, z))) \
            @ H.face_out(ang) @ H.rot_euler(90, 0, 0)
        for k in range(5):
            m = base @ H.rot_euler(0, 0, roll + 72.0 * k + rng.uniform(-3.5, 3.5))
            H.prism(bm, PETAL_PTS, -PETAL_T / 2, PETAL_T / 2, matrix=m)
    H.new_obj("Petals", bm, c, C_PETAL, rbx_material="SmoothPlastic", roughness=0.60)

    # ---- 6. daisy centres: a slightly domed disc aimed straight out -------------------
    bm = bmesh.new()
    for ang, z, _roll in DAISIES:
        H.cyl(bm, H.on_ring(CENTRE_R0, ang, z), H.on_ring(CENTRE_R1, ang, z),
              0.052, segs=6, r2=0.040)
    H.new_obj("FlowerCentres", bm, c, C_CENTRE, rbx_material="SmoothPlastic",
              roughness=0.65)

    return c


# ---------------------------------------------------------------------------------------
# PARTS                                             COLOUR   MATERIAL       TRIS
#   Band              ring, 18 segs + 0.028 bulge   5f9e3f   Fabric          216  (18 x 6 quads)
#   CactusPads        6 big pads, uvsphere 6 x 4    4a8c3a   Plastic         216  (6 x 36)
#   CactusHighlight   4 buds, uvsphere 6 x 3        6fb54d   SmoothPlastic    96  (4 x 24)
#                     6 ribs, 3-seg 3-pt tube       6fb54d   SmoothPlastic    84  (6 x 14)
#   Spines            19 x 4-sided cone             e8e0b0   SmoothPlastic   114  (19 x 6)
#   Petals            3 daisies x 5 kite prisms     ffffff   SmoothPlastic   180  (15 x 12)
#   FlowerCentres     3 x 6-seg tapered disc        f5c542   SmoothPlastic    60  (3 x 20)
#                                                                          -----
#                                                                            966  of 1000
#
# Traced vertex-by-vertex through a pure-python stub of the lib before shipping:
#
#   PART               TRIS    radius min..max     z min..max
#   Band                216    0.6300 .. 0.7780   -0.1300 .. 0.1300
#   CactusPads          216    0.6762 .. 0.7775    0.0300 .. 0.3364
#   CactusHighlight     180    0.6813 .. 0.7990    0.0300 .. 0.2561
#   Spines              114    0.7339 .. 0.8484    0.0561 .. 0.2809
#   Petals              180    0.7550 .. 0.8136   -0.1034 .. 0.1377
#   FlowerCentres        60    0.7604 .. 0.8310   -0.0450 .. 0.0650
#
# FIT   min radius 0.630  the band's own inner wall - exactly H.R_IN, 0.03 over the head.
#                         The tightest DECORATION is a cactus pad at 0.676: its centre is
#                         at 0.725 and its radial support is sqrt((hr cos t)^2 +
#                         (hh sin t)^2) <= 0.049 at the worst seeded size and lean.  Buds
#                         bottom out at 0.681, ribs at ~0.73, spines at 0.734, and no
#                         daisy vertex comes inside 0.755.
#       max radius 0.848  a spine tip off the widest pad (flower centres reach 0.831,
#                         ribs 0.799, pads 0.778) - well under the 1.15 cap.
#       z range   -0.130 .. +0.336   band -0.130..+0.130; the tallest pad tops out at
#                         0.336, so nothing needs the "decorations may go above +0.60"
#                         waiver and the daisies stay flush on the band's outer wall.
# ---------------------------------------------------------------------------------------
