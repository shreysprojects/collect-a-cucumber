"""Neon: the Hologram Cucumber - a translucent glowing-blue cucumber projected above a dark
hexagonal pedestal, with glowing pixels floating round it."""
import bmesh, math, random

COLLECTION = "NeonHologramCucumber"
NOTES = (
    "A HOLOGRAM of a cucumber hovering over a projector pedestal.  PEDESTAL: a dark "
    "neo_night Metal hexagon (6-sided lathe, circumradius 1.35, flat-to-flat 2.34, a flat "
    "face square to +Y, points at +-X) from z 0 to 0.42 with 0.05 chamfers top and bottom; "
    "a neo_night_lt SmoothPlastic top plate (hex r 1.22, z 0.40-0.50) on it.  STRIPS (one "
    "neo_cyan Neon part, emit 0.6): a 0.9 x 0.12 light strip standing 0.03 proud of the "
    "middle of each of the six side faces (z 0.15-0.27), a hexagonal glowing band hugging "
    "the top plate's edge (centreline circumradius 1.18, 0.10 x 0.09 section, z "
    "0.455-0.545; hexagonal, not the brief's round torus, because a round r 1.18 ring "
    "would hang ~0.17 past the plate's flat sides and float off the pedestal) and a "
    "glowing hexagonal projector pad (r 0.92, 0.025 proud) in the middle "
    "of the plate - the tile's top glows, so the pad is added on top of the brief.  HOLO: "
    "the set's standard body (h 4.0, r 0.68, nub 0.30 x 0.30) in neo_holo Neon at "
    "transparency 0.35, emit 0.5, its base centre at (0.30, 0, 0.78) - floating 0.28 over "
    "the plate - and LEANING 10 degrees about Y toward -X (screen right, as in the tile, "
    "whose much stronger lean is capped at 10 by the rev-3 rule), so its tip ends near "
    "x -0.45 and its lowest corner at z ~0.71.  SCANLINES (neo_holo_lt Neon, transparency "
    "0.3, emit 0.6, carried by the same lean): five rings round the body at zf 0.20 / 0.35 "
    "/ 0.50 / 0.65 / 0.80, drawn through the octagon's corners so they hug the facets, "
    "and four lengthwise lines down alternate facet edges (22.5 / 112.5 / 202.5 / 292.5 "
    "deg) - the tile's wireframe; plus the set's twelve raised square speckles (size 0.26) "
    "sitting between the rings, which is also how the tile's lighter squares inside the "
    "hologram read.  PIXELS (neo_holo_lt Neon, emit 0.6): nine small bevelled cubes "
    "0.16-0.26 floating round the hologram, alternating the screen-left (+X) and "
    "screen-right (-X) side on a rising ladder from z ~1.5 to ~4.1, 1.15-1.5 from the "
    "leaning axis (drawn from 1.1-1.6 by random.Random(58)), some in front of the body and "
    "some behind - they float, that is the point.  Footprint about 2.85 x 2.4 (x -1.35 .. "
    "+1.49, y -1.20 .. +1.22: pedestal strips plus pixels), height 5.04 (the leaning nub).  "
    "~2050 tris.  Lowest point: the pedestal's underside at z 0.  The hologram and its "
    "lines are placed with a matrix, so dryrun's bounding box ignores the lean.  "
    "6 parts: Pedestal, PedestalTop, Strips, Holo, ScanLines, Pixels."
)

# ------------------------------------------------------------------ the pedestal
PED_R = 1.35                    # circumradius of the hexagon (flat-to-flat 2.34)
PED_H = 0.42
PED_CH = 0.05                   # chamfer on the top and bottom edges
PED_AP = PED_R * math.cos(math.pi / 6.0)       # apothem of the straight sides, 1.169

TOP_R, TOP_Z0, TOP_Z1 = 1.22, 0.40, 0.50       # the lighter top plate (sunk 0.02)

STRIP_HL = 0.45                 # light strip: 0.9 long ...
STRIP_Z0, STRIP_Z1 = 0.15, 0.27 # ... 0.12 tall, centred at z 0.21
STRIP_PROUD, STRIP_SINK = 0.03, 0.02
FACE_ANGLES = [30.0, 90.0, 150.0, 210.0, 270.0, 330.0]     # side-face centres, 90 = +Y

RING_R, RING_HW = 1.18, 0.05    # the glowing band on the plate's edge (circumradius)
RING_Z0, RING_Z1 = 0.455, 0.545

PAD_R, PAD_Z0, PAD_Z1 = 0.92, 0.47, 0.525     # the projector pad in the middle

# ------------------------------------------------------------------ the hologram
HOLO_X, HOLO_Z = 0.30, 0.78     # base centre: 0.28 over the plate, nudged to +X so the
LEAN = -10.0                    # lean (top toward -X = screen right) centres the body

RING_ZF = [0.20, 0.35, 0.50, 0.65, 0.80]
CORNERS = [22.5 + 45.0 * k for k in range(9)]  # octagon corners, closing the loop
LONG_ANGLES = [22.5, 112.5, 202.5, 292.5]      # alternate facet edges
LONG_ZF = [0.04, 0.082, 0.25, 0.66, 0.858, 0.92]   # the profile's own break points
LINE_W = 0.05

# ------------------------------------------------------------------ the pixels
PIXEL_N = 9
PIXEL_SEED = 58
PIXEL_Z0, PIXEL_Z1 = 1.4, 4.2
PIXEL_RAD = (1.1, 1.6)
PIXEL_SIZE = (0.16, 0.26)
PIXEL_SPREAD = 50.0             # degrees either side of the +X / -X direction


def _hex_band(D, bm, r_in, r_out, z0, z1):
    """A flat-topped hexagonal frame (vertices at 0, 60, ... deg like the pedestal),
    built as six closed trapezoid prisms so every piece is a sealed shell."""
    outer = D.ngon_pts(6, r_out, phase=0.0)
    inner = D.ngon_pts(6, r_in, phase=0.0)
    vs = []
    for k in range(6):
        j = (k + 1) % 6
        vs += D.prism(bm, [outer[k], outer[j], inner[j], inner[k]], z0, z1)
    return vs


def _axis_x(z):
    """x of the hologram's leaning axis at world height z."""
    a = math.radians(LEAN)
    return HOLO_X + (z - HOLO_Z) / math.cos(a) * math.sin(a)


def _pixels(rng):
    """(centre, size) for each floating pixel: alternate sides, rising ladder."""
    out = []
    span = PIXEL_Z1 - PIXEL_Z0
    for k in range(PIXEL_N):
        s = rng.uniform(*PIXEL_SIZE)
        side = 0.0 if k % 2 == 0 else 180.0        # +X (screen left) / -X (screen right)
        az = math.radians(side + rng.uniform(-PIXEL_SPREAD, PIXEL_SPREAD))
        rad = rng.uniform(*PIXEL_RAD)
        z = PIXEL_Z0 + span * (k + 0.5) / PIXEL_N + rng.uniform(-0.10, 0.10)
        z = max(PIXEL_Z0 + s / 2.0, min(PIXEL_Z1 - s / 2.0, z))
        out.append(((_axis_x(z) + math.cos(az) * rad, math.sin(az) * rad, z), s))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- the pedestal: a chamfered dark hexagon ---------------------------
    bm = bmesh.new()
    D.lathe(bm, [(0.0, 0.0), (PED_R - PED_CH, 0.0), (PED_R, PED_CH),
                 (PED_R, PED_H - PED_CH), (PED_R - PED_CH, PED_H), (0.0, PED_H)],
            segs=6, phase=0.0)
    D.new_obj("Pedestal", bm, c, D.C("neo_night"), rbx_material="Metal")

    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(6, TOP_R, phase=0.0), TOP_Z0, TOP_Z1)
    D.new_obj("PedestalTop", bm, c, D.C("neo_night_lt"), rbx_material="SmoothPlastic")

    # ---- cyan glow: side strips, the edge band, the projector pad ----------
    bm = bmesh.new()
    for ang in FACE_ANGLES:
        vs = D.beveled_box(bm, (-STRIP_HL, PED_AP - STRIP_SINK, STRIP_Z0),
                           (STRIP_HL, PED_AP + STRIP_PROUD, STRIP_Z1), bevel=0.015)
        D.xform(bm, vs, D.rot_euler(0.0, 0.0, ang - 90.0))     # +Y face -> this face
    _hex_band(D, bm, RING_R - RING_HW, RING_R + RING_HW, RING_Z0, RING_Z1)
    D.prism(bm, D.ngon_pts(6, PAD_R, phase=0.0), PAD_Z0, PAD_Z1)
    D.new_obj("Strips", bm, c, D.C("neo_cyan"), rbx_material="Neon", emit=0.6)

    # ---- the hologram: a standard cucumber, floating and leaning ------------
    holo_m = D.place((HOLO_X, 0.0, HOLO_Z), D.rot_euler(0.0, LEAN, 0.0))

    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30), matrix=holo_m)
    D.new_obj("Holo", bm, c, D.C("neo_holo"), rbx_material="Neon",
              transparency=0.35, emit=0.5)

    # ---- scan lines + speckles, riding the same lean ----------------------
    bm = bmesh.new()
    vs = []
    for zf in RING_ZF:
        vs += D.surface_line(bm, [(zf, a) for a in CORNERS], h=H, r=R,
                             width=LINE_W, rise=0.03, flat=False)
    for a in LONG_ANGLES:
        vs += D.surface_line(bm, [(zf, a) for zf in LONG_ZF], h=H, r=R,
                             width=LINE_W, rise=0.025, flat=False)
    slots = D.cuke_stud_slots(rows=6, per_row=2, z0=0.12, z1=0.88, seed=58, jitter=0.012)
    vs += D.cuke_studs(bm, h=H, r=R, size=0.26, rise=0.05, slots=slots)
    D.xform(bm, vs, holo_m)
    D.new_obj("ScanLines", bm, c, D.C("neo_holo_lt"), rbx_material="Neon",
              transparency=0.3, emit=0.6)

    # ---- the floating pixels ----------------------------------------------
    bm = bmesh.new()
    for (x, y, z), s in _pixels(random.Random(PIXEL_SEED)):
        h = s / 2.0
        D.beveled_box(bm, (x - h, y - h, z - h), (x + h, y + h, z + h), bevel=0.03)
    D.new_obj("Pixels", bm, c, D.C("neo_holo_lt"), rbx_material="Neon", emit=0.6)

    return c
