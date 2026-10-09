"""Riveted iron plate wall - the tier above the stone wall.  Five vertical DiamondPlate
plates in a dark iron frame, two riveted reinforcing straps, a dark leaning nosing carrying
a row of bright anti-climb barbs, and a chevron-striped kick plate.  Faces +Y, tiles at
x = +/-4."""
import bmesh

COLLECTION = "IronWall"

NOTES = (
    "Tiling wall segment: exactly 8 wide (x -4.00..4.00), 8.00 tall, 1.60 deep "
    "(y -0.60..+1.00).  Faces +Y - the plates, straps, rivets, chevrons, rust and the "
    "leaning nosing with its barbs are all on the +Y (attacker) side; the -Y side is a "
    "flat web with four vertical stiffener ribs and nothing else.\n"
    "TOP.  The dark top rail and the dark leaning nosing in front of it make ONE flat "
    "coping at z 7.24 running from y -0.44 out to y +1.00, braced by four corbels.  The "
    "only bright thing up there is the row of eight barbs: 4-sided spikes 0.40 across, "
    "rooted at z 7.10 inside the nosing and raked out to a point at y 0.84 / z 8.00, so "
    "0.76 of each barb stands clear of the coping as a sawtooth against the sky.\n"
    "TILING MATHS.  The full corner post is 0.90 wide and is centred ON the seam, so each "
    "tile carries HALF of it: x 3.55..4.00 at the +x end and -4.00..-3.55 at the -x end.  "
    "Butt two tiles (A on -4..4, B on 4..12) and A's 3.55..4.00 meets B's 4.00..4.45 to "
    "make one 0.90 post centred on x = 4.  Every element that reaches a tiling plane "
    "(back web, ground sill, kick plate, both straps, top rail, blade rail, weld beads, "
    "the posts) is a prism extruded ALONG x, so its x = +/-4 end faces are dead flat "
    "quads with no chamfer - a beveled_box there would cut a groove down the seam.  "
    "Everything else stops short: plates +/-3.55, ribs +/-3.16, chevrons +/-3.85, blade "
    "barbs +/-3.70, strap rivets +/-3.66, post rivets +/-3.91.  Repeating details use a "
    "period that divides 8 so the pattern continues across the joint: strap rivets and "
    "blade barbs every 1.00 (at x = +/-0.5, 1.5, 2.5, 3.5), chevrons, ribs and nosing "
    "corbels every 2.00 (at x = +/-1, 3).  The post rivet columns land at x = 3.78 and, "
    "from the next tile, 4.22 - i.e. +/-0.22 either side of the full post's centreline.\n"
    "PLATE FIELD.  The 7.10 between the posts is five 1.308 plates separated by four 0.14 "
    "seam gaps.  The gaps are the wall's darks: the plates are 0.36 thick and sit on the "
    "iron_dark back web, so each gap is a 0.14-wide slot 0.36 deep (0.26 at the mouth "
    "after the 0.06 chamfer) whose floor is the darkest colour in the prop.\n"
    "VALUE LADDER (5 colours).  iron_dark frame / kick / straps / blade rail (darkest), "
    "iron_mid plates and back ribs, iron_rust ONLY on the repair patch and its drips, "
    "metal_light rivets / weld beads / anti-climb barbs, warning_yellow chevrons "
    "(brightest).  Every stack steps in value: bright rivets on "
    "dark straps on mid plates, yellow chevrons on the dark kick plate, bright barbs "
    "against the sky and the dark coping they stand on.  The sill and the kick plate share "
    "iron_dark, but the sill stands 0.14 further out in y and is chamfered, so a shadow "
    "line separates them.\n"
    "ASYMMETRY.  One iron_rust repair patch (x 0.86..2.46, z 3.20..4.80) bridges the seam "
    "between plates 4 and 5 with four of its own bright rivets, plus three rust streaks "
    "dripping from under the straps at x -1.55, +2.72 and -2.95.  Remember the render "
    "camera looks down -Y, so the patch and the +2.72 streak read on the LEFT of a "
    "front-on view.\n"
    "Static prop - no moving parts, so no PIVOTS / STATES are exported."
)

# ---------------------------------------------------------------- envelope (studs)
X_END = 4.00                 # tiling planes - nothing may cross these
POST_HW = 0.45               # half of the 0.90 full post; one tile carries this at each end
X_IN = X_END - POST_HW       # 3.55 - inner face of the half posts

GAP = 0.14                   # seam gap between plates
N_PLATES = 5
PLATE_W = (2 * X_IN - GAP * (N_PLATES - 1)) / N_PLATES      # 1.308

# depth planes (y).  Total depth -0.60 .. +1.00
Y_RIB = -0.60                # back of the stiffener ribs
Y_WEB_B, Y_WEB_F = -0.42, -0.06
Y_PLATE = 0.30               # plate face
Y_POST = 0.46                # post / frame face
Y_KICK = 0.44                # kick-plate face
Y_STRAP = 0.52               # reinforcing strap face
Y_SILL_B, Y_SILL_F = -0.52, 0.58

# heights (z)
Z_SILL = 0.34
Z_KICK = 1.30
Z_PLATE_T = 6.80
Z_RAIL0, Z_RAIL1 = 6.80, 7.24
STRAP_LO = (1.72, 2.32)
STRAP_HI = (5.02, 5.62)
Z_TOP = 8.00

# repeating-detail x positions (both periods divide the 8-stud tile)
X_P1 = (-3.5, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 3.5)     # period 1.0
X_P2 = (-3.0, -1.0, 1.0, 3.0)                           # period 2.0

# +Y-facing cross-section of the leaning nosing that carries the barbs, given as (y, z).
# Its top is FLUSH with the top rail at Z_RAIL1, so the cap is one flat dark coping and
# the whole 0.76 above it belongs to the barbs; the rake lives in the underside and nose.
BLADE = [(0.24, 6.84), (0.58, 6.84), (1.00, 7.04), (1.00, Z_RAIL1), (0.24, Z_RAIL1)]

# anti-climb barbs: 4-sided spikes 0.40 across, rooted inside the nosing at z 7.10 and
# raked out to a point on the 8.00 envelope.  (y, z) of the root and of the tip.
BARB_R = 0.20
BARB_ROOT = (0.68, 7.10)
BARB_TIP = (0.84, Z_TOP)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    dark = D.C("iron_dark")
    mid = D.C("iron_mid")
    bright = D.C("metal_light")
    rust = D.C("iron_rust")
    yellow = D.C("warning_yellow")

    # Axis-swap matrices, built from rot_euler so no mathutils import is needed.
    #   MYZ: a (y, z) profile extruded ALONG X - flat, un-chamfered ends on the seams.
    #   MXZ: an (x, z) profile extruded along Y (world y = -w, so the span is negated).
    MYZ = D.rot_euler(rx=90, rz=90)
    MXZ = D.rot_euler(rx=90)

    def yz(bm, pts, x0, x1):
        """Extrude a (y, z) cross-section along X from x0 to x1."""
        return D.prism(bm, pts, x0, x1, matrix=MYZ)

    def xz(bm, pts, y0, y1):
        """Extrude an (x, z) profile along Y from y0 to y1."""
        return D.prism(bm, pts, -y1, -y0, matrix=MXZ)

    # ---------------------------------------------------------------- frame
    # Back web, both half posts, the ground sill, the top rail and the nosing corbels:
    # one dark iron carcass that everything else is bolted to.
    bm = bmesh.new()
    D.box(bm, (-X_END, Y_WEB_B, 0.0), (X_END, Y_WEB_F, Z_RAIL1))

    for s in (1, -1):
        yz_post = [(s * X_IN, 0.0), (s * X_END, 0.0), (s * X_END, Z_RAIL1),
                   (s * (X_IN + 0.13), Z_RAIL1), (s * X_IN, Z_RAIL1 - 0.13)]
        xz(bm, yz_post, Y_WEB_B, Y_POST)

    yz(bm, [(Y_SILL_B, 0.0), (Y_SILL_F, 0.0), (Y_SILL_F, 0.22),
            (Y_SILL_F - 0.12, Z_SILL), (Y_WEB_B - 0.02, Z_SILL), (Y_SILL_B, 0.26)],
       -X_END, X_END)

    yz(bm, [(-0.44, Z_RAIL0), (0.42, Z_RAIL0), (0.52, Z_RAIL0 + 0.12),
            (0.52, Z_RAIL1 - 0.12), (0.40, Z_RAIL1), (-0.44, Z_RAIL1)],
       -X_END, X_END)

    for gx in X_P2:                                   # corbels bracing the nosing
        yz(bm, [(Y_PLATE - 0.04, 6.34), (Y_PLATE - 0.04, 6.88), (0.94, 7.02)],
           gx - 0.12, gx + 0.12)
    D.new_obj("Frame", bm, c, dark, rbx_material="Metal", metallic=0.6, roughness=0.45)

    # ---------------------------------------------------------------- kick plate
    # Runs the FULL width so the hazard stripe crosses the posts unbroken, as painted.
    bm = bmesh.new()
    yz(bm, [(Y_WEB_F, Z_SILL), (Y_KICK, Z_SILL), (Y_KICK, Z_KICK - 0.12),
            (Y_KICK - 0.12, Z_KICK), (Y_WEB_F, Z_KICK)], -X_END, X_END)
    D.new_obj("KickPlate", bm, c, dark, rbx_material="Metal", metallic=0.6, roughness=0.5)

    # ---------------------------------------------------------------- reinforcing straps
    bm = bmesh.new()
    for (z0, z1) in (STRAP_LO, STRAP_HI):
        yz(bm, [(Y_WEB_F, z0), (Y_KICK, z0), (Y_STRAP, z0 + 0.10),
                (Y_STRAP, z1 - 0.10), (Y_KICK, z1), (Y_WEB_F, z1)], -X_END, X_END)
    D.new_obj("Straps", bm, c, dark, rbx_material="Metal", metallic=0.65, roughness=0.4)

    # ---------------------------------------------------------------- the plate field
    bm = bmesh.new()
    for i in range(N_PLATES):
        x0 = -X_IN + i * (PLATE_W + GAP)
        D.beveled_box(bm, (x0, Y_WEB_F, Z_KICK), (x0 + PLATE_W, Y_PLATE, Z_PLATE_T),
                      bevel=0.06)
    D.new_obj("Plates", bm, c, mid, rbx_material="DiamondPlate", metallic=0.5, roughness=0.5)

    # ---------------------------------------------------------------- back stiffeners
    bm = bmesh.new()
    for rx in X_P2:
        D.box(bm, (rx - 0.16, Y_RIB, Z_SILL), (rx + 0.16, Y_WEB_B, Z_PLATE_T))
    D.new_obj("BackRibs", bm, c, mid, rbx_material="Metal", metallic=0.55, roughness=0.5)

    # ---------------------------------------------------------------- anti-climb rail
    # The nosing belongs to the dark carcass, so the cap reads as one dark coping against
    # the sky and the only bright thing on the skyline is the row of barbs.
    bm = bmesh.new()
    yz(bm, BLADE, -X_END, X_END)
    D.new_obj("BladeRail", bm, c, dark, rbx_material="Metal", metallic=0.7, roughness=0.4)

    bm = bmesh.new()
    for tx in X_P1:                                   # the sawtooth, period 1.0 so it tiles
        D.spike(bm, (tx, BARB_ROOT[0], BARB_ROOT[1]), (tx, BARB_TIP[0], BARB_TIP[1]),
                BARB_R, segs=4)
    D.new_obj("BladeBarbs", bm, c, bright, rbx_material="Metal", metallic=0.75, roughness=0.3)

    # ---------------------------------------------------------------- rivets
    bm = bmesh.new()
    for (z0, z1) in (STRAP_LO, STRAP_HI):             # a big head per stud on each strap
        zc = (z0 + z1) / 2.0
        for rx in X_P1:
            D.cyl(bm, (rx, Y_STRAP - 0.02, zc), (rx, Y_STRAP + 0.14, zc), 0.16,
                  segs=6, r2=0.11)
    for s in (1, -1):                                 # post columns, +/-0.22 off the seam
        for rz in (0.90, 3.70, 6.30):
            D.cyl(bm, (s * 3.78, Y_POST - 0.02, rz), (s * 3.78, Y_POST + 0.12, rz), 0.13,
                  segs=6, r2=0.09)
    for (px, pz) in ((1.02, 3.36), (2.30, 3.36), (1.02, 4.64), (2.30, 4.64)):
        D.cyl(bm, (px, 0.38, pz), (px, 0.52, pz), 0.13, segs=6, r2=0.09)
    D.new_obj("Rivets", bm, c, bright, rbx_material="Metal", metallic=0.8, roughness=0.28)

    # ---------------------------------------------------------------- hazard chevrons
    bm = bmesh.new()
    for cx in X_P2:
        pts = [(px + cx, pz + 0.76) for (px, pz) in D.chevron_pts(1.70, 0.50, 0.30)]
        xz(bm, pts, Y_KICK, Y_KICK + 0.09)
    D.new_obj("Chevrons", bm, c, yellow, rbx_material="Metal", metallic=0.15, roughness=0.7)

    # ---------------------------------------------------------------- rusted repair patch
    bm = bmesh.new()
    D.beveled_box(bm, (0.86, Y_PLATE - 0.02, 3.20), (2.46, 0.40, 4.80), bevel=0.07)
    D.new_obj("RepairPatch", bm, c, rust, rbx_material="CorrodedMetal",
              metallic=0.25, roughness=0.85)

    # ---------------------------------------------------------------- weld beads
    # metal_light, not rust: a thin line of bright metal along each seam reads as a weld
    # catching the sun.  In iron_rust they read as copper - or worse, timber - battens.
    bm = bmesh.new()
    D.box(bm, (-X_END, 0.28, Z_KICK + 0.02), (X_END, 0.36, Z_KICK + 0.09))
    D.box(bm, (-X_END, 0.28, Z_PLATE_T - 0.09), (X_END, 0.36, Z_PLATE_T - 0.02))
    D.new_obj("WeldBeads", bm, c, bright, rbx_material="Metal", metallic=0.7, roughness=0.35)

    # ---------------------------------------------------------------- rust drips
    bm = bmesh.new()
    for (sx, sw, zt, zb) in ((-1.55, 0.15, STRAP_HI[0], 3.10),
                             (2.72, 0.11, STRAP_HI[0], 4.05),
                             (-2.95, 0.13, STRAP_LO[0], 1.34)):
        xz(bm, [(sx - sw, zt), (sx + sw, zt), (sx + sw * 0.3, zb), (sx - sw * 0.3, zb)],
           Y_PLATE - 0.01, Y_PLATE + 0.035)
    D.new_obj("RustStreaks", bm, c, rust, rbx_material="CorrodedMetal",
              metallic=0.2, roughness=0.9)

    return c
