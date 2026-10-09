"""Playground seesaw: a steel A-frame fulcrum with a bearing block and axle pin, and a
chamfered plank running ALONG X - red at the +X end, blue at the -X end - swung 12 degrees
so the red seat is down on its rubber tyre-stop and the blue seat is up in the air.  The
long side-on profile is the thing that says 'seesaw', so it is the side that faces +Y."""
import bmesh, math

COLLECTION = "Seesaw"
NOTES = (
    "7.90 long (x) x 1.60 wide (y) x 3.20 tall at the raised grab bar.  THE PLANK RUNS "
    "ALONG X and the axle along Y, so the long side-on profile faces the +Y camera and a "
    "player walks up to a seat from the front, not into the tip.  The A-frame stands on two "
    "foot rails spanning x +/-1.36, its bearing block tops out at z 1.26 and the axle pin "
    "runs along Y at z 1.32.  EVERYTHING NAMED Plank* IS ONE RIGID ASSEMBLY - PlankBeamRed, "
    "PlankBeamBlue, PlankSeats, PlankHandles, PlankPivotStrap - and swings about "
    "PIVOTS['PlankPivot'] = (0, 0, 1.35), axis = Y.  STATES are absolute angles applied as "
    "rot_euler(ry=angle) about that pivot; a POSITIVE angle drops the red +X end.  THE MODEL "
    "AS BUILT IS IN THE 'RedDown' POSE (+12 deg): the red +X end - screen LEFT in a front "
    "render - is down and resting on its tyre-stop, the blue -X end is up.  From the shipped "
    "pose subtract 12 deg to reach Level and 24 deg to reach BlueDown.  Seat pads land at "
    "z ~1.11 (down end) and z ~2.41 (up end), and each grab bar crowns 0.95 above its own "
    "seat pad - hand height for a seated R15.  The two rubber tyre-stops are holed rings "
    "1.10 across, centred at x +/-3.40, whose tops are sheared to the 12-degree plank line, "
    "so the low tip sits dead flush on one and the high tip has a matching landing waiting "
    "under it.  The red/blue colour split is at x = 0, separated by the bright pivot strap "
    "band so the two mid-value plastics never touch.  One deliberate asymmetry: the yellow "
    "hazard chevron is on the +Y (camera-facing) A-frame plate only.")
PIVOTS = {"PlankPivot": (0.0, 0.0, 1.35)}
STATES = {"RedDown": 12.0, "Level": 0.0, "BlueDown": -12.0}


def _span(s, a, b):
    """Ordered (lo, hi) for a pair of coordinates mirrored by the sign `s`."""
    return (min(s * a, s * b), max(s * a, s * b))


def _yspan(s, a, b):
    """Extrusion range that lands a SIDE-rotated slab at world y between s*a and s*b.
    SIDE sends the extrusion axis to -Y, so the pair comes back negated."""
    return (min(-s * a, -s * b), max(-s * a, -s * b))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    steel = D.C("metal_dark")       # A-frame, grab bars - the darkest value
    bright = D.C("metal_light")     # bearing housing + the plank's pivot strap
    red = D.C("plastic_red")        # +X half of the plank
    blue = D.C("plastic_blue")      # -X half of the plank
    yellow = D.C("plastic_yellow")  # seat pads, backstops, the hazard chevron
    rubber = "5b5f66"               # dark GREY rubber - the palette's only rubber is a
                                    # near-black that sits below the frame's own value and
                                    # welded the bumpers into one dark mass with it

    # ---- the numbers the whole prop hangs off -----------------------------------
    PIV_Z = 1.35                 # axle line = underside of the plank at x = 0
    TILT = 12.0                  # built pose: RedDown - a positive ry drops the +X end
    TAN = math.tan(math.radians(12.0))
    F_IN, F_OUT = 0.40, 0.62     # the A-frame side slabs occupy y 0.40..0.62 (+ mirror)
    HALF = 3.80                  # plank half length
    BW, BT = 0.46, 0.28          # plank half width / thickness
    B_X, B_OUT, B_IN, B_CH = 3.40, 0.55, 0.21, 0.06   # tyre-stop centre, radii, chamfer

    # D.prism extrudes along +Z.  rot_euler(rx=90) maps (px, py, pz) -> (px, -pz, py), so a
    # profile written in (x, z) - the seesaw's side-on silhouette - extruded across the width
    # lands as a slab standing in the XZ plane.  _yspan() undoes the axis flip so the call
    # sites still read in world y.
    SIDE = D.rot_euler(rx=90)
    # The plank is modelled about the pivot at the origin, then swung into the tilted pose.
    PLANK = D.place((0.0, 0.0, PIV_Z), D.rot_euler(ry=TILT))

    # ---- A-frame: two side plates with a triangular void, a crossbar each, a tie tube --
    # The plates splay along the plank (x) and stand in the XZ plane, one either side of the
    # beam.  The bottom edge is broken between x -0.60..0.60 so the void opens downward and
    # the thing reads as a splayed 'A' rather than a solid triangle.
    aframe = [(-1.28, 0.00), (-0.60, 0.00), (0.00, 0.88), (0.60, 0.00), (1.28, 0.00),
              (0.38, 1.08), (0.30, 1.18), (-0.30, 1.18), (-0.38, 1.08)]
    bm = bmesh.new()
    for sy in (1.0, -1.0):
        p0, p1 = _yspan(sy, F_IN, F_OUT)
        D.prism(bm, aframe, p0, p1, matrix=SIDE)
        b0, b1 = _span(sy, 0.38, 0.64)                       # crossbar - closes the 'A'
        D.beveled_box(bm, (-0.50, b0, 0.44), (0.50, b1, 0.62), bevel=0.05)
        f0, f1 = _span(sy, 0.36, 0.66)                       # foot rail on the ground
        D.beveled_box(bm, (-1.36, f0, 0.00), (1.36, f1, 0.12), bevel=0.04)
    D.cyl(bm, (0.0, -0.72, 0.53), (0.0, 0.72, 0.53), 0.12, segs=8)   # cross tube
    D.new_obj("Frame", bm, c, steel, rbx_material="Metal", metallic=0.55, roughness=0.42)

    # ---- bearing block on top, with the axle pin and a fat nut on each end -------
    bm = bmesh.new()
    D.beveled_box(bm, (-0.30, -0.66, 1.06), (0.30, 0.66, 1.26), bevel=0.06)
    D.cyl(bm, (0.0, -0.74, 1.32), (0.0, 0.74, 1.32), 0.12, segs=8)
    for sy in (1.0, -1.0):
        D.cyl(bm, (0.0, sy * 0.72, 1.32), (0.0, sy * 0.80, 1.32), 0.17, segs=5)
    D.new_obj("Bearing", bm, c, bright, rbx_material="Metal", metallic=0.70, roughness=0.32)

    # ---- one hazard chevron on the +Y plate: the asymmetry that dates the prop, kept on
    #      the face the camera actually sees.  0.09 proud so its tip clears the bearing ---
    bm = bmesh.new()
    ch0, ch1 = _yspan(1.0, F_OUT, F_OUT + 0.09)
    D.prism(bm, [(px, 0.84 + py) for (px, py) in D.chevron_pts(0.60, 0.30, 0.13)],
            ch0, ch1, matrix=SIDE)
    D.new_obj("FrameChevron", bm, c, yellow, rbx_material="SmoothPlastic", roughness=0.45)

    # ---- rubber tyre-stops: a squat holed ring, not a crate.  Lathed round, then the top
    #      rings are sheared onto the 12-degree plank line so the low tip lands flush ----
    bm = bmesh.new()
    top_z = PIV_Z - TAN * B_X                # ring height at its own centre
    for sx in (1.0, -1.0):
        cx = sx * B_X
        prof = [(0.00, 0.00), (B_OUT, 0.00), (B_OUT, top_z - B_CH), (B_OUT - B_CH, top_z),
                (B_IN, top_z), (B_IN, 0.05), (0.00, 0.05)]
        for v in D.lathe(bm, prof, segs=10, matrix=D.place((cx, 0.0, 0.0))):
            if v.co.z > 0.5 * (top_z - B_CH):        # the top annulus and its chamfer
                v.co.z -= TAN * sx * (v.co.x - cx)
    D.new_obj("Bumpers", bm, c, rubber, rbx_material="Rubber", roughness=0.90)

    # ---- the plank, split at x = 0 into a red half and a blue half ---------------
    for (nm, col, x0, x1) in (("PlankBeamRed", red, 0.0, HALF),
                              ("PlankBeamBlue", blue, -HALF, 0.0)):
        bm = bmesh.new()
        D.beveled_box(bm, (x0, -BW, 0.0), (x1, BW, BT), bevel=0.07)
        D.xform(bm, list(bm.verts), PLANK)
        D.new_obj(nm, bm, c, col, rbx_material="SmoothPlastic", roughness=0.48)

    # ---- seat pad + backstop at each end, cut as one L-profile ------------------
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        seat = [(2.34, BT), (3.20, BT), (3.20, BT + 0.32), (3.13, BT + 0.38),
                (3.06, BT + 0.38), (3.06, BT + 0.12), (2.42, BT + 0.12), (2.34, BT + 0.06)]
        D.prism(bm, [(sx * a, b) for (a, b) in seat], -0.52, 0.52, matrix=SIDE)
    D.xform(bm, list(bm.verts), PLANK)
    D.new_obj("PlankSeats", bm, c, yellow, rbx_material="SmoothPlastic", roughness=0.45)

    # ---- grab bar in front of each seat: a tube socketed into the beam and carried up to
    #      hand height - 0.95 above the seat pad - so a seated rider has something to hold -
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        arch = [(sx * 2.16, 0.34, 0.10), (sx * 2.13, 0.44, 0.60), (sx * 2.07, 0.40, 1.12),
                (sx * 2.03, 0.24, 1.35), (sx * 2.03, -0.24, 1.35), (sx * 2.07, -0.40, 1.12),
                (sx * 2.13, -0.44, 0.60), (sx * 2.16, -0.34, 0.10)]
        D.tube(bm, arch, [0.11, 0.11, 0.11, 0.105, 0.105, 0.11, 0.11, 0.11], segs=5)
    D.xform(bm, list(bm.verts), PLANK)
    D.new_obj("PlankHandles", bm, c, steel, rbx_material="Metal", metallic=0.60,
              roughness=0.40)

    # ---- pivot strap: two cheek plates, a clamp bolt, and a bright band over the
    #      colour split so the red and blue halves never abut directly -------------
    bm = bmesh.new()
    for sy in (1.0, -1.0):
        y0, y1 = _span(sy, 0.44, 0.56)
        D.box(bm, (-0.36, y0, 0.00), (0.36, y1, 0.32))
    D.box(bm, (-0.12, -BW, BT - 0.02), (0.12, BW, BT + 0.06))
    D.cyl(bm, (0.0, -0.62, 0.12), (0.0, 0.62, 0.12), 0.07, segs=6)
    D.xform(bm, list(bm.verts), PLANK)
    D.new_obj("PlankPivotStrap", bm, c, bright, rbx_material="Metal", metallic=0.70,
              roughness=0.34)

    return c
