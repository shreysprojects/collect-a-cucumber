"""Snow: Frozen Cucumber - a GREEN cucumber sealed inside a chunky block of ice, snow on top."""
import bmesh, math

COLLECTION = "SnowFrozenCucumber"
NOTES = ("An ordinary cucumber-green body (standard h 4.0 / r 0.68, cuke_green with 18 "
         "cuke_stud speckles, stem nub on top) FROZEN INSIDE A BLOCK OF ICE.  The ice is a "
         "chunky 7-sided faceted mass (snow_ice_lt, Roblox material Ice, transparency 0.42 "
         "so the green body and its speckles read straight through it): a lathe that hugs "
         "the body from z = 0 to z 3.56, 1.12 across at the foot and pinching to 0.50 at the "
         "neck, its flanks stepped in and out four times so it reads as stacked ice shelves "
         "rather than a smooth sleeve.  Five angular crystal spires grow out of it - a big "
         "one at +X (screen-LEFT) spearing past the cucumber's head to z = 5.0, a shorter "
         "one at -X, and three small ones jutting low off the front, back and upper front.  "
         "The cucumber's HEAD AND NUB stick out of the top, bare green from z 3.6 to 4.3.  "
         "Settled on the ice's crown, a thick snow_white (Snow) drift: a lathed mound "
         "z 3.02-3.62 overhanging the ice shoulder by ~0.25, broken up by three heaped "
         "clumps so it does not read as turned, with four fat tongues spilling off its brim "
         "and running down the ice to z 2.4.  Four parts: Body, Studs, Ice, Snow.  About "
         "2.4 x 2.2 x 5.0 studs, centred on x = 0, y = 0, nothing below z = 0.  The ice and "
         "snow lathes are (radius, z) profiles and the spires are placed by matrix, so "
         "dryrun's bounding box only approximates the real one.")

H_STUDS = 18            # speckle count (rows x per_row below)

# ---- the ice mass ---------------------------------------------------------
ICE_SEGS = 7                                  # 7 facets: deliberately NOT the body's 8,
ICE_PHASE = math.pi / 2.0 - math.pi / 7.0     # so the ice reads as a separate block.

# (radius, z).  The in-and-out wobble is what makes it chunky rather than a smooth cone.
ICE_PROFILE = [
    (0.00, 0.00),
    (1.12, 0.00),
    (1.15, 0.34),
    (0.99, 0.66),
    (1.05, 1.18),
    (0.92, 1.52),
    (0.97, 2.06),
    (0.86, 2.42),
    (0.90, 2.86),
    (0.78, 3.18),
    (0.72, 3.46),
    (0.50, 3.56),
]

# Spires growing out of the mass: (base, height, radius, lean deg, outward azimuth deg).
# Azimuth is measured like every angle in the set: +Y = 90, +X = 0 (screen LEFT).
SPIRES = [
    ((0.84, -0.10, 1.98), 3.02, 0.32, 6.0, 0.0),      # the big one, spears past the head
    ((-0.78, 0.16, 1.46), 2.24, 0.30, 10.0, 180.0),   # its shorter partner
    ((0.52, -0.62, 0.55), 1.15, 0.26, 28.0, -55.0),   # low, jutting at the front
    ((-0.52, 0.70, 0.85), 1.10, 0.24, 22.0, 125.0),   # low, jutting at the back
    ((-0.30, -0.66, 2.55), 1.05, 0.22, 24.0, -105.0),  # high on the front shoulder
]

# ---- the snow settled on the ice's crown ----------------------------------
SNOW_PROFILE = [
    (0.00, 3.58),
    (0.50, 3.62),
    (0.78, 3.56),
    (0.94, 3.40),
    (0.98, 3.20),
    (0.86, 3.02),
]

# Clumps heaped on the drift: (centre, half-size, yaw deg).  Each is half sunk into it.
CLUMPS = [
    ((0.00, 0.80, 3.42), (0.28, 0.26, 0.20), 0.0),      # front (+Y), the big one
    ((0.74, -0.34, 3.46), (0.26, 0.26, 0.19), 30.0),    # +X = screen-LEFT, front
    ((-0.66, 0.42, 3.30), (0.25, 0.24, 0.18), -35.0),   # screen-right shoulder
]

# Tongues spilling off the brim and down the ice: (ice facet, top z, tip z, top radius).
TONGUES = [
    (0, 3.26, 2.34, 0.27),      # facet 0 faces +Y: the longest, straight down the front
    (1, 3.28, 2.66, 0.23),      # 141 deg
    (6, 3.24, 2.52, 0.24),      # 39 deg
    (4, 3.30, 2.80, 0.20),      # 296 deg, so the load reads from the front-left too
]


def _ice_facet_deg(k):
    """Outward angle (degrees) of the centre of ice facet `k`.  Facet 0 faces +Y."""
    return math.degrees(ICE_PHASE + (2.0 * k + 1.0) * math.pi / ICE_SEGS)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- the cucumber, ordinary and green ------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- its speckles, read through the ice ----------------------------------
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=6, per_row=3, z0=0.12, z1=0.90, size=0.28,
                 rise=0.055, seed=23)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the ice: a faceted block with spires growing off it -----------------
    bm = bmesh.new()
    D.lathe(bm, ICE_PROFILE, segs=ICE_SEGS, phase=ICE_PHASE)

    for base, height, radius, lean, azim in SPIRES:
        # rot_euler(lean, 0, yaw) leans local +Z toward azimuth (yaw - 90).
        D.crystal_spire(bm, base=base, height=height, radius=radius, segs=6,
                        taper=0.56, tip=0.34,
                        rot=D.rot_euler(lean, 0.0, azim + 90.0))

    D.new_obj("Ice", bm, c, D.C("snow_ice_lt"), rbx_material="Ice", transparency=0.42,
              roughness=0.32)

    # ---- the snow settled on top of the ice ----------------------------------
    bm = bmesh.new()
    D.lathe(bm, SNOW_PROFILE, segs=ICE_SEGS, phase=ICE_PHASE)

    for (cx, cy, cz), (hx, hy, hz), yaw in CLUMPS:
        rot = D.rot_euler(0, 0, yaw) if abs(yaw) > 1e-6 else None
        D.beveled_box(bm, (cx - hx, cy - hy, cz - hz), (cx + hx, cy + hy, cz + hz),
                      bevel=0.10, rot=rot)

    for facet, z_top, z_tip, rtop in TONGUES:
        a = math.radians(_ice_facet_deg(facet))
        ca, sa = math.cos(a), math.sin(a)
        mid_z = z_top - (z_top - z_tip) * 0.55
        D.tube(bm, [(ca * 0.94, sa * 0.94, z_top),
                    (ca * 0.88, sa * 0.88, mid_z),
                    (ca * 0.90, sa * 0.90, z_tip)],
               [rtop, rtop * 0.80, rtop * 0.38], segs=6)

    D.new_obj("Snow", bm, c, D.C("snow_white"), rbx_material="Snow", roughness=0.62)

    return c
