"""Playground slide: an angled ladder with a grab hoop at -Y, a slatted deck at z 4.4, and
a yellow U-channel chute that drops away in a curve and flattens into a run-out at +Y.
Faces +Y - the player climbs at the back and slides toward the viewer."""
import bmesh, math

COLLECTION = "Slide"
NOTES = (
    "Footprint about 3.6 (x) x 11.1 (y) x 6.0 (z), centred on x=0.  Four ground-anchor "
    "pads sit flat on z=0: ladder pads at (+/-1.40, -5.04) and the splayed chute-post "
    "pads at (+/-1.30, 1.00); the red exit bumper at y 5.28..5.62 also touches the "
    "ground.  Deck walking surface z=4.40 spanning y -4.18..-2.45, x +/-1.70; step onto "
    "it from the top rung at z=4.24.  Deck is fenced on both sides by a top rail at "
    "z=5.66 (1.26 above the deck) and a mid rail at z=5.04, on three posts a side; the "
    "back is open under the grab hoop, whose apex clears the deck by 1.44 studs.  Chute "
    "riding surface runs z=4.40 at y=-2.45 down a parabola to z=0.40 at y=5.40, clear "
    "channel 2.24 wide and 0.74 deep - an R15 avatar fits.  The mid-span is carried by "
    "an A-frame: two dark posts splayed to x=+/-1.30 at the ground, tied at z=0.85, "
    "capped by saddles that lie flat against the chute underside.  ONE asymmetric "
    "detail: the red sit-down grab handle on the deck is at negative x only (screen "
    "RIGHT seen from the front).  Rigid prop, no moving parts."
)

# ------------------------------------------------------------------ layout constants
DECK_Z, DECK_X = 4.40, 1.70          # deck top surface / half width
DECK_Y0, DECK_Y1 = -4.18, -2.45      # back edge / front edge (= chute mouth)
SLAT_T, PAN_T = 0.22, 0.24

CH_Y0, CH_Y1 = -2.45, 5.40           # chute mouth -> run-out end
CH_Z0, CH_Z1 = 4.40, 0.40            # riding surface at each end
CH_N = 10                            # segments stepped along the parabola
CH_OVER = 1.16                       # segment length overlap factor (no gaps at joints)
IW, OW = 1.12, 1.40                  # channel inner / outer half width
FL, WH = 0.28, 0.74                  # floor slab thickness / side wall height
LIP_X, LIP_R = 1.26, 0.175           # rolled lip centre-line x / radius

LAD_X, LAD_R = 1.42, 0.14            # ladder rail x / radius
LAD_FOOT = (-5.04, 0.12)             # (y, z) at the pad
LAD_TOP = (-4.32, 4.70)              # (y, z) at the top
RUNG_Z = (0.80, 1.66, 2.52, 3.38, 4.24)

RAIL_X, RAIL_Z = 1.56, 5.66          # deck guard rail line / top rail height
RAIL_MID_Z = 5.04                    # mid rail, so the fence reads as a fence
RAIL_R, RAIL_R2 = 0.16, 0.14         # top / mid rail gauge
RAIL_Y0, RAIL_Y1 = -2.50, -4.20      # rail run along the deck
RAIL_POST_Y = (-2.58, -3.35, -4.12)  # the three uprights a side

POST_Y = 1.00                        # mid-chute A-frame: y of the support
POST_X, POST_TOP_X = 1.30, 1.02      # splayed foot x -> where it caps into the chute
POST_R, TIE_R, TIE_Z = 0.26, 0.16, 0.85

# (x, y, pad half-x, pad half-y, y offset of the anchor bolt)
PADS = ((1.40, -5.04, 0.38, 0.34, 0.0), (-1.40, -5.04, 0.38, 0.34, 0.0),
        (POST_X, POST_Y, 0.46, 0.40, 0.28), (-POST_X, POST_Y, 0.46, 0.40, 0.28))


# ------------------------------------------------------------------ the curve
def _node(i):
    """(y, z) of chute node i on the parabola: steep off the deck, flat at the run-out."""
    t = i / float(CH_N)
    u = 1.0 - t
    return CH_Y0 + (CH_Y1 - CH_Y0) * t, CH_Z1 + (CH_Z0 - CH_Z1) * u * u


def _seg_angle(i):
    y0, z0 = _node(i)
    y1, z1 = _node(i + 1)
    return math.atan2(z1 - z0, y1 - y0)


def _wall_top(i):
    """(y, z) of the side-wall crown at node i - the lip follows this line."""
    y, z = _node(i)
    if i <= 0:
        a = _seg_angle(0)
    elif i >= CH_N:
        a = _seg_angle(CH_N - 1)
    else:
        a = 0.5 * (_seg_angle(i - 1) + _seg_angle(i))
    return y - WH * math.sin(a), z + WH * math.cos(a)


def _chute_angle(y):
    """Slope of the chute (radians, negative = falling) at world y."""
    t = (y - CH_Y0) / (CH_Y1 - CH_Y0)
    return math.atan2(-2.0 * (CH_Z0 - CH_Z1) * (1.0 - t), CH_Y1 - CH_Y0)


def _under_z(y):
    """World z of the chute's underside above world y - where a support has to land."""
    t = (y - CH_Y0) / (CH_Y1 - CH_Y0)
    z = CH_Z1 + (CH_Z0 - CH_Z1) * (1.0 - t) ** 2
    return z - FL / math.cos(_chute_angle(y))


def _rung_y(z):
    fy, fz = LAD_FOOT
    ty, tz = LAD_TOP
    return fy + (ty - fy) * (z - fz) / (tz - fz)


# ------------------------------------------------------------------ build
def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- the chute: 10 short U-channel segments stepped along the parabola.
    # The profile is authored in (x, -z) and swung by (angle - 90) about X, so the
    # extrusion axis lands on +Y and one prism carries floor + both walls per segment.
    prof = [(-OW, -WH), (-OW, FL), (OW, FL), (OW, -WH),
            (IW, -WH), (IW, 0.0), (-IW, 0.0), (-IW, -WH)]
    bm = bmesh.new()
    for i in range(CH_N):
        y0, z0 = _node(i)
        y1, z1 = _node(i + 1)
        ym, zm = 0.5 * (y0 + y1), 0.5 * (z0 + z1)
        ang = math.atan2(z1 - z0, y1 - y0)
        half = 0.5 * math.hypot(y1 - y0, z1 - z0) * CH_OVER
        D.prism(bm, prof, -half, half,
                matrix=D.place((0.0, ym, zm), D.rot_euler(rx=math.degrees(ang) - 90.0)))
    D.new_obj("Chute", bm, c, D.C("plastic_yellow"), rbx_material="SmoothPlastic",
              roughness=0.42)

    # ---- everything blue: rolled chute lips, deck guard rails + posts, ladder grab hoop
    bm = bmesh.new()
    lip_nodes = [_wall_top(i) for i in (0, 2, 4, 6, 8, 10)]
    for sx in (1.0, -1.0):
        pts = [(sx * LIP_X, -2.70, 4.45)]                       # tucks back onto the deck
        pts += [(sx * LIP_X, y, z) for (y, z) in lip_nodes]
        pts.append((sx * LIP_X, 5.52, 0.86))                    # rolled-over exit end
        D.tube(bm, pts, [LIP_R] * len(pts), segs=6)

        # guard fence: top rail + mid rail carried on three chunky uprights.  The rear
        # upright runs into the hoop's leg, so the fence and the arch read as one frame.
        for (rz, rr) in ((RAIL_Z, RAIL_R), (RAIL_MID_Z, RAIL_R2)):
            D.cyl(bm, (sx * RAIL_X, RAIL_Y0, rz), (sx * RAIL_X, RAIL_Y1, rz), rr, segs=6)
        for py in RAIL_POST_Y:
            D.cyl(bm, (sx * RAIL_X, py, 4.28), (sx * RAIL_X, py, RAIL_Z + 0.04),
                  RAIL_R, segs=6)
        # collar sleeving the ladder rail's bare top cap where the hoop meets it
        D.cyl(bm, (sx * LAD_X, -4.37, 4.40), (sx * LAD_X, -4.29, 4.88), 0.20, segs=6)

    hoop = [(1.40, -4.34, 4.12)]
    for k in range(7):
        a = math.radians(8.0 + (172.0 - 8.0) * k / 6.0)
        hoop.append((math.cos(a) * 1.24, -4.34 + 0.16 * math.sin(a),
                     4.60 + math.sin(a) * 1.24))
    hoop.append((-1.40, -4.34, 4.12))
    D.tube(bm, hoop, [0.14] * len(hoop), segs=5)
    D.new_obj("Railings", bm, c, D.C("plastic_blue"), rbx_material="SmoothPlastic",
              roughness=0.40)

    # ---- red: deck slats, ladder rungs, the one-sided sit-down handle, exit bumper
    bm = bmesh.new()
    D.slat_run(bm, (-DECK_X, DECK_Y0, DECK_Z - SLAT_T), (DECK_X, DECK_Y1, DECK_Z),
               5, gap_frac=0.20, axis='y', bevel=0.04)
    for rz in RUNG_Z:
        ry = _rung_y(rz)
        D.cyl(bm, (-LAD_X, ry, rz), (LAD_X, ry, rz), 0.11, segs=6)
    grab = [(-0.52, -2.62, 4.34), (-0.58, -2.78, 5.10),
            (-1.16, -2.78, 5.10), (-1.22, -2.62, 4.34)]
    D.tube(bm, grab, [0.14] * len(grab), segs=6)
    D.beveled_box(bm, (-1.42, 5.28, 0.00), (1.42, 5.62, 0.42), bevel=0.09)
    D.new_obj("SlatsAndRungs", bm, c, D.C("plastic_red"), rbx_material="SmoothPlastic",
              roughness=0.45)

    # ---- bright ladder rails + the anchor bolts on the pads
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        D.cyl(bm, (sx * LAD_X, LAD_FOOT[0], LAD_FOOT[1]),
              (sx * LAD_X, LAD_TOP[0], LAD_TOP[1]), LAD_R, segs=8)
    for (px, py, _hx, _hy, bdy) in PADS:
        D.cyl(bm, (px, py + bdy, 0.15), (px, py + bdy, 0.30), 0.10, segs=5)
    D.new_obj("LadderRails", bm, c, D.C("metal_light"), rbx_material="Metal",
              metallic=0.6, roughness=0.36)

    # ---- lighter frame: deck pan and the ladder's front braces
    bm = bmesh.new()
    D.box(bm, (-1.66, DECK_Y0 - 0.04, DECK_Z - SLAT_T - PAN_T),
          (1.66, DECK_Y1 + 0.04, DECK_Z - SLAT_T))
    for sx in (1.0, -1.0):
        D.cyl(bm, (sx * 1.52, -2.56, 4.06), (sx * 1.36, -5.00, 0.20), 0.13, segs=6)
    D.new_obj("Frame", bm, c, D.C("metal_mid"), rbx_material="Metal",
              metallic=0.55, roughness=0.44)

    # ---- dark metal on the ground: four anchor pads plus the mid-span A-frame.  Dark
    # against the light ground plane is the only value that survives at distance.
    bm = bmesh.new()
    for (px, py, hx, hy, _bdy) in PADS:
        D.beveled_box(bm, (px - hx, py - hy, 0.0), (px + hx, py + hy, 0.18), bevel=0.06)
    cap_z = _under_z(POST_Y)
    tilt = math.degrees(_chute_angle(POST_Y))
    for sx in (1.0, -1.0):
        D.cyl(bm, (sx * POST_X, POST_Y, 0.14), (sx * POST_TOP_X, POST_Y, cap_z + 0.06),
              POST_R, segs=8)
        # saddle: lies flat on the chute underside so the cap reads as a bracket
        D.beveled_box(bm, (sx * POST_TOP_X - 0.28, POST_Y - 0.25, cap_z - 0.16),
                      (sx * POST_TOP_X + 0.28, POST_Y + 0.25, cap_z + 0.02),
                      bevel=0.05, rot=D.rot_euler(rx=tilt))
    D.cyl(bm, (-1.20, POST_Y, TIE_Z), (1.20, POST_Y, TIE_Z), TIE_R, segs=6)
    D.new_obj("FeetAndPosts", bm, c, D.C("metal_dark"), rbx_material="Metal",
              metallic=0.5, roughness=0.5)

    return c
