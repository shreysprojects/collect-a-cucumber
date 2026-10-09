"""Neon biome guardian 10/10: SCAN, the hovering laser sentinel that never lands.

Reference sheet: a gloss-black angular drone floating above a charging pad.  A wedge
head like an arrowhead pointing forward, a wide magenta visor bar across its face and
two antenna spikes raked off the top.  The body is a hexagonal core plate with a white
glowing hex at its centre, ringed by a cyan strip and a magenta strip.  Two floating
shoulder pods hang either side on short black links, each an angular shield with a cyan
inner face and a magenta edge.  Four long angular fins hang below and behind, each with
a magenta strip down its leading edge and a cyan strip down its trailing edge.  An
under-lens on the belly is where the scan cone comes from, and a ring of little cyan
hover nozzles keeps it up.  Nothing touches the ground.
"""
import bmesh, math

COLLECTION = "Scan"
GUARDIAN = "Scan"
SEAT = "Scan_Seat"

NOTES = (
    "8.06 studs tall - the fin tips hang at z 0.62 and the lit antenna pips top out at "
    "z 8.68 - by 6.72 across the shoulder pods and 4.68 deep from the nose spike "
    "(y 2.62) to the rear fin tips (y -2.06).  THE WHOLE MODEL HOVERS: min_z is 0.62, "
    "so the air gap under the fins is deliberate and this is the second guardian (with "
    "Orbit) allowed off the floor - the dry run reports min_z 0.00 only because it reads "
    "unit axis=/normal= vectors as points.  The core plate, and Root, sit at z 4.0, "
    "which IS the hover height; everything hangs off Core, so one Core rotation banks "
    "the whole drone (that is the Run pose).  Parts: a 1.80-deep hexagonal core plate "
    "carrying the drone's HEART on its FRONT face - a 1.60-wide white Neon hex ringed by "
    "a cyan hex strip and a magenta hex strip, stacked forward off the 1.689 front flat "
    "so the white is the brightest thing on the model from straight ahead - plus a cyan "
    "strip round the top seam and a magenta strip round the belly seam; six hover "
    "nozzles with cyan throats under the hex vertices; a gimballed belly turret carrying "
    "the scan lens; a neck post and a BROAD arrowhead wedge head, 3.32 wide against the "
    "core's 3.90 and 1.72 tall with its crest, widest across its back corners and "
    "tapering to a point at y 2.30, wearing a wide magenta visor BAR laid across its two "
    "forward-facing faces and two SHORT raked antenna spikes with lit tips; two shoulder "
    "pods held out on long links, each a canted shield with a cyan inner face and "
    "magenta rim rails; and four near-vertical blade fins swept back like a tail "
    "assembly.  Rig: Root > Core > (Neck > Head > Visor/HeadTrim/Antenna_R|L > "
    "AntennaTip, Link_R|L > Pod > PodFace/PodEdge, four Fin_* > FinEdge/FinTrim, "
    "LensHousing > Lens, Thrusters > ThrustGlow).  Each fin carries its OWN magenta "
    "leading strip and cyan trailing strip rather than the sheet's single shared FinGlow "
    "part, so the four fins fan and fold independently - a shared strip would have "
    "frozen them together.  Every lit piece uses Magenta, Cyan or Core, so SLEEP_LOOK "
    "darkens the visor, the heart and its two rings, both pod faces, all eight fin "
    "strips, the core ring, the lens, the nozzle throats and the antenna pips together "
    "in one stamp.  The character's RIGHT is +X, which is screen-LEFT in a render.  IT "
    "LANDS ON ALL FOUR FIN TIPS: the fins already hang only 24-25 degrees off vertical, "
    "so Sit swings them 3-6 degrees forward and 5-6 degrees inboard and all four tips "
    "come down on the 0.56 pad face - the front pair at radius 0.90, inside the glowing "
    "ring, the rear pair at radius 2.16, outside it and well clear of the rim clamps, "
    "which now sit at the hex FLATS so no tip can land on one.  POSE_LOC adds only the "
    "last 0.01 of settle."
)

# ---------------------------------------------------------------- the skeleton
HOVER_Z = 4.00                 # the core plate, the Root, and the hover height
CORE_R = 1.95                  # hex radius; phase 0 puts VERTICES at +-X, flats at +-Y
CORE_TOP = 4.90                # top face of the main plate
CORE_BOT = 3.10                # bottom face of the main plate
CORE_H = CORE_TOP - CORE_BOT   # 1.80 deep, so its FRONT FACE can carry the white heart
CORE_FACE = 1.689              # apothem: where the +Y front flat of the hex sits
# The heart, STEPPED forward off that flat - magenta at +0.12, cyan at +0.20, white at
# +0.34 - so each ring shows as a 0.12-wide band round the one in front of it.  Sunk
# level with the flat they were invisible; the whole point is that they stand off it.
# `plate` uses surface_frame, so the hexagons come out with vertices at +-X and flats
# top and bottom - height 1.732 * r - which is what keeps HEART_R * 1.732 = 1.386 inside
# the 1.80 face instead of trusting hex_prism(axis=(0,1,0))'s arbitrary roll.
HEART_R = 0.80                 # the WHITE hex: 1.60 wide by 1.39 tall, the drone's core
RING_CY_R = 0.92               # the cyan strip round it
RING_MG_R = 1.04               # the magenta strip round that

NECK_PIVOT = (0.00, 0.22, 5.22)
HEAD_PIVOT = (0.00, 0.16, 6.14)
HEAD_Z0, HEAD_Z1 = 6.16, 7.14  # the wedge slab
CREST_Z1 = 7.50                # the raked crest on top of it
NOSE_Y = 2.30                  # where the arrowhead outline comes to its point
HEAD_W = 1.66                  # half-width across the BACK corners of the wedge

VISOR_PIVOT = (0.00, 1.30, 6.64)
ANT_BASE = (0.46, 0.06, 7.42)
ANT_TIP = (0.68, -0.24, 8.52)   # + the lit pip = the model's ceiling at z 8.68

LINK_IN = (1.86, 0.00, 4.52)   # where a link leaves the core's +X vertex
POD_HINGE = (2.84, 0.00, 4.80)
POD_C = (3.08, -0.05, 4.58)    # the shield plate's centre
POD_X = 3.08

LENS_PIVOT = (0.00, 0.30, 2.68)   # the top of the yoke, where the turret hangs off the hull
LENS_FACE = (0.00, 0.30, 1.96)
NOZZLE_R = 1.72                # hover nozzles, one under each hex vertex / rim lug
NOZZLE_Z = 3.08

# Fin roots on the core underside, and where each blade points.  side = +1 is the
# character's RIGHT (+X, screen LEFT); F is the forward pair, B the rear pair.  The
# roots sit INSIDE the nozzle ring (radius 1.16 / 1.42 vs 1.72) so a mount never eats a
# nozzle.  The sheet's fins are a TAIL ASSEMBLY, not legs: each blade leans only 4-5
# degrees outward in x and the whole 24-25 degree lean is BACKWARD along -Y.
FIN_ROOT_F = (0.95, 0.66, 2.90)
FIN_TIP_F = (1.14, -0.34, 0.66)
FIN_ROOT_B = (0.98, -1.02, 2.90)
FIN_TIP_B = (1.16, -2.06, 0.62)


def _xs(a, b):
    """lo/hi for a box whose x pair was mirrored - box() needs lo < hi on every axis."""
    return (a, b) if a <= b else (b, a)


def _fin(tag):
    """(root, tip, side) for one of the four fins, mirrored off the two authored pairs."""
    side = +1 if tag.endswith("R") else -1
    root, tip = (FIN_ROOT_F, FIN_TIP_F) if tag.startswith("F") else (FIN_ROOT_B, FIN_TIP_B)
    return ((side * root[0], root[1], root[2]), (side * tip[0], tip[1], tip[2]), side)


def _along(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def _arrow_pts(scale=1.0, y_off=0.0, nose=NOSE_Y):
    """The head's arrowhead outline in WORLD x/y: a BROAD wedge, WIDEST across its two
    back corners (+-1.66, nearly the core's own 1.95) and tapering to a single point at
    +Y.  The old outline pinched back in at the rear, which is what made a 2.0-wide head
    read as a little box with a band round it instead of an arrowhead."""
    return [(0.00, nose * scale + y_off),
            (0.62 * HEAD_W * scale, 0.90 * scale + y_off),
            (HEAD_W * scale, -0.10 * scale + y_off),
            (HEAD_W * scale, -0.95 * scale + y_off),
            (-HEAD_W * scale, -0.95 * scale + y_off),
            (-HEAD_W * scale, -0.10 * scale + y_off),
            (-0.62 * HEAD_W * scale, 0.90 * scale + y_off)]


# ---------------------------------------------------------------- the two states
POSES = {
    # powered down on the pad: head hung, antennae raked back, pods drooped off their
    # links, and IT LANDS ON ALL FOUR FIN TIPS.  The fins now hang only 24-25 degrees off
    # vertical at rest, so the landing is a small fold, not a splay:
    #   forward pair (2.46 long, root z 2.90): (6, +-6) drops the tip to z 0.561 at
    #   radius 0.90 - on the 0.56 pad face, inside the 1.51..1.73 glowing ring.
    #   rear pair (2.51 long, root z 2.90): (3, +-5) drops the tip to z 0.562 at radius
    #   2.16 - still on the 2.165-apothem pad face, outside the ring, and 1.0 clear of
    #   the nearest rim clamp now that the clamps sit at the hex flats.
    #   All four legs are the same length and land on the same face, so the hull is level
    #   and POSE_LOC only has to take up the last 0.01.
    "Sit": {
        "Neck": (-16, 0, 0), "Head": (-20, 0, 0),
        "Antenna_R": (30, 0, 10), "Antenna_L": (30, 0, -10),
        "Link_R": (0, 22, 0), "Link_L": (0, -22, 0),
        "Pod_R": (0, 10, -14), "Pod_L": (0, -10, 14),
        "LensHousing": (-10, 0, 0),
        "Fin_FR": (6, 6, 0), "Fin_FL": (6, -6, 0),
        "Fin_BR": (3, 5, 0), "Fin_BL": (3, -5, 0),
    },
    # the sheet's hero pose: risen, NOSE UP (rx positive tips an upright neck back, and
    # a hero drone does not stare at its own feet), pods flared wide and up, fins fanned
    # out, the belly lens tipped forward onto whatever it just found.
    "Awake": {
        "Neck": (5, 0, 0), "Head": (3, 0, 0),
        "Antenna_R": (-10, 0, 8), "Antenna_L": (-10, 0, -8),
        "Link_R": (0, -16, 0), "Link_L": (0, 16, 0),
        "Pod_R": (0, 0, -8), "Pod_L": (0, 0, 8),
        "LensHousing": (16, 0, 0),
        "Fin_FR": (-4, -10, 0), "Fin_FL": (-4, 10, 0),
        "Fin_BR": (2, -12, 0), "Fin_BL": (2, 12, 0),
    },
    # the chase cruise: the whole drone banked nose-down off Core, fins swept back into
    # the slipstream, pods tucked, antennae laid flat.
    "Run": {
        "Core": (-14, 0, 0), "Neck": (6, 0, 0), "Head": (4, 0, 0),
        "Antenna_R": (34, 0, 4), "Antenna_L": (34, 0, -4),
        "Link_R": (0, 10, 0), "Link_L": (0, -10, 0),
        "Pod_R": (0, 0, -16), "Pod_L": (0, 0, 16),
        "LensHousing": (22, 0, 0),
        "Fin_FR": (-14, -4, 0), "Fin_FL": (-14, 4, 0),
        "Fin_BR": (-10, -5, 0), "Fin_BL": (-10, 5, 0),
    },
    # the signature: a scan sweep.  The head yaws off to the character's left while the
    # belly lens rakes the ground and the pods hold wide as reflectors.
    "Sweep": {
        "Neck": (-8, 0, 34), "Head": (-10, 0, 12),
        "Antenna_R": (-14, 0, 16), "Antenna_L": (-14, 0, -2),
        "Link_R": (0, -22, 0), "Link_L": (0, 22, 0),
        "Pod_R": (0, 0, -18), "Pod_L": (0, 0, 2),
        "LensHousing": (26, 0, 18),
        "Fin_FR": (-6, -12, 0), "Fin_FL": (-6, 12, 0),
        "Fin_BR": (-4, -14, 0), "Fin_BL": (-4, 14, 0),
    },
}
# asleep it settles the last 0.05 onto the pad; awake and running it lifts off it again
POSE_LOC = {
    "Sit": {"Root": (0.0, 0.0, -0.01)},
    "Awake": {"Root": (0.0, 0.0, 0.34)},
    "Run": {"Root": (0.0, 0.0, 0.20)},
    "Sweep": {"Root": (0.0, 0.0, 0.40)},
}


def build(G):
    _guardian(G)
    _seat(G)
    return G.coll(COLLECTION)


# ================================================================= the guardian
def _guardian(G):
    c = G.begin(COLLECTION, GUARDIAN)

    G.root_part(c, (-0.60, -0.50, HOVER_Z - 0.50), (0.60, 0.50, HOVER_Z + 0.50))
    G.hitbox(c, (-3.45, -2.25, 0.55), (3.45, 2.72, 8.75), pivot=(0, 0, HOVER_Z),
             parent="Root")

    _core(G, c)
    _thrusters(G, c)
    _lens(G, c)
    _head(G, c)
    _antennae(G, c)
    for side in (+1, -1):
        _pod(G, c, side)
    for tag in ("FR", "FL", "BR", "BL"):
        _fin_blade(G, c, tag)


def _core(G, c):
    """The hexagonal core plate: a 1.80-deep main slab (it was 0.46 - a saucer with no
    front to it), a raised upper deck, a tapered belly, six rim lugs at the hex vertices,
    a ring of bolt heads, and the drone's HEART stepped off the +Y front flat."""
    bm = bmesh.new()
    G.hex_prism(bm, (0.0, 0.0, HOVER_Z), CORE_R, CORE_H, axis=(0, 0, 1), sides=6)
    G.hex_prism(bm, (0.0, 0.0, 5.06), 1.42, 0.32, axis=(0, 0, 1), sides=6)      # upper deck
    # The belly, as two stepped plates.  hex_prism's `taper` always shrinks the +axis
    # end, so a single tapered plate on axis +Z flares OUT as it goes down - a funnel
    # under the hull, not a belly - and axis -Z would fix it only by handing the dry run
    # a (0, 0, -1) it scans as a point a stud below the floor.
    G.hex_prism(bm, (0.0, 0.0, 2.99), 1.52, 0.22, axis=(0, 0, 1), sides=6)
    G.hex_prism(bm, (0.0, 0.0, 2.77), 1.12, 0.22, axis=(0, 0, 1), sides=6)
    for i in range(6):                                  # a chamfered lug at each vertex
        a = math.radians(60 * i)
        cx, cy = math.cos(a) * 1.82, math.sin(a) * 1.82
        G.box(bm, (cx - 0.27, cy - 0.19, 3.50), (cx + 0.27, cy + 0.19, 4.50),
              rot=G.rot_euler(0, 0, 60 * i))
    for i in range(6):                                  # bolt heads on the upper deck
        a = math.radians(60 * i + 30)
        G.hex_prism(bm, (math.cos(a) * 1.12, math.sin(a) * 1.12, 5.25), 0.13, 0.10,
                    axis=(0, 0, 1), sides=6)
    G.part("Core", bm, c, "Body", (0.0, 0.0, HOVER_Z), parent="Root")

    bm = bmesh.new()                                    # vent louvres + side intakes
    G.slat_run(bm, (-0.82, 0.42, 5.18), (0.82, 0.98, 5.26), 4, gap_frac=0.42, axis='x',
               bevel=0.0)
    G.slat_run(bm, (-0.82, -1.00, 5.18), (0.82, -0.44, 5.26), 4, gap_frac=0.42, axis='x',
               bevel=0.0)
    # Intake panels laid ON the four slanted side faces.  The hex flats face 30, 90, 150,
    # 210, 270, 330; 90/270 are the nose and tail, so the intakes take the other four.
    # Straddling the 1.689 apothem is what makes them SHOW - a box inboard of it is
    # swallowed whole by the plate.
    for a_deg in (30, 150, 210, 330):
        a = math.radians(a_deg)
        cx, cy = math.cos(a) * 1.70, math.sin(a) * 1.70
        G.box(bm, (cx - 0.62, cy - 0.09, 3.66), (cx + 0.62, cy + 0.09, 4.34),
              rot=G.rot_euler(0, 0, a_deg + 90))
    G.part("CorePanels", bm, c, "BodyLight", (0.0, 0.0, HOVER_Z), parent="Core")

    bm = bmesh.new()                                    # cyan strip round the top seam
    for i in range(6):
        a = math.radians(60 * i + 30)
        cx, cy = math.cos(a) * 1.70, math.sin(a) * 1.70
        G.box(bm, (cx - CORE_R / 2.0, cy - 0.07, CORE_TOP - 0.02),
              (cx + CORE_R / 2.0, cy + 0.07, CORE_TOP + 0.14),
              rot=G.rot_euler(0, 0, 60 * i + 120))
    # ... and the cyan STRIP of the heart, a hex ring standing just proud of the front
    # flat and 0.12 wider all round than the white hex that covers its middle.
    G.plate(bm, G.ngon_pts(6, RING_CY_R), 0.20, at=(0.0, CORE_FACE + 0.10, HOVER_Z),
            normal=(0, 1, 0))
    G.part("CoreRing", bm, c, "Cyan", (0.0, 0.0, HOVER_Z), parent="Core")

    bm = bmesh.new()                                    # magenta strip round the belly seam
    for i in range(6):
        a = math.radians(60 * i + 30)
        cx, cy = math.cos(a) * 1.62, math.sin(a) * 1.62
        G.box(bm, (cx - CORE_R / 2.2, cy - 0.07, CORE_BOT - 0.14),
              (cx + CORE_R / 2.2, cy + 0.07, CORE_BOT + 0.02),
              rot=G.rot_euler(0, 0, 60 * i + 120))
    # ... the magenta STRIP of the heart, the outermost ring of the stack.  1.04 * 1.732
    # = 1.80, exactly the front face's own depth, so the ring reaches the seams top and
    # bottom without overhanging them.
    G.plate(bm, G.ngon_pts(6, RING_MG_R), 0.16, at=(0.0, CORE_FACE + 0.04, HOVER_Z),
            normal=(0, 1, 0))
    for s in (+1, -1):                                  # two forward marker pips
        # Pushed out to the SLANTED front faces (the hull surface is at y 1.13 out at
        # x 1.32) - at their old x 0.62 they now sit under the heart and never render.
        G.diamond(bm, (s * 1.32, 1.18, HOVER_Z), radius=0.12, length=0.30, axis=(0, 1, 0),
                  sides=4)
    G.part("CoreEdge", bm, c, "Magenta", (0.0, 0.0, HOVER_Z), parent="Core")

    bm = bmesh.new()                                    # THE HEART: the white hex core
    # It belongs on the FRONT of the plate, not the top of it.  Face-on it is 1.60 wide
    # by 1.39 tall on a 3.90-wide hull and stands 0.34 proud of the front flat, so it is
    # the brightest and biggest single thing on the drone instead of a sliver of light
    # that only showed if the camera looked down on the deck.
    G.plate(bm, G.ngon_pts(6, HEART_R), 0.30, at=(0.0, CORE_FACE + 0.19, HOVER_Z),
            normal=(0, 1, 0))
    G.hex_prism(bm, (0.0, 0.0, 5.25), 0.56, 0.16, axis=(0, 0, 1), sides=6)   # deck pip
    # ... and the same light leaking out of the step in the belly.  A 0.50 hex at the
    # belly centre (where this was) is swallowed whole by the 1.12 step and by the lens
    # turret; at 1.26 it stands 0.14 proud of the step all the way round.
    G.hex_prism(bm, (0.0, 0.0, 2.82), 1.26, 0.12, axis=(0, 0, 1), sides=6)
    G.part("CoreGlow", bm, c, "Core", (0.0, 0.0, HOVER_Z), parent="Core")


def _thrusters(G, c):
    """Six hover nozzles under the plate - the only reason it is off the ground."""
    bm = bmesh.new()
    for i in range(6):
        a = math.radians(60 * i)
        x, y = math.cos(a) * NOZZLE_R, math.sin(a) * NOZZLE_R
        G.cyl(bm, (x, y, NOZZLE_Z), (x, y, NOZZLE_Z - 0.34), 0.30, segs=6, r2=0.22)
        G.hex_prism(bm, (x, y, NOZZLE_Z + 0.04), 0.33, 0.12, axis=(0, 0, 1), sides=6)
    G.part("Thrusters", bm, c, "BodyLight", (0.0, 0.0, NOZZLE_Z), parent="Core")

    bm = bmesh.new()
    for i in range(6):
        a = math.radians(60 * i)
        x, y = math.cos(a) * NOZZLE_R, math.sin(a) * NOZZLE_R
        G.hex_prism(bm, (x, y, NOZZLE_Z - 0.30), 0.19, 0.09, axis=(0, 0, 1), sides=6)
    G.part("ThrustGlow", bm, c, "Cyan", (0.0, 0.0, NOZZLE_Z - 0.30), parent="Thrusters")


def _lens(G, c):
    """The belly turret the scan cone comes out of - a little gimballed housing."""
    bm = bmesh.new()
    G.hex_prism(bm, (0.0, 0.30, 2.24), 0.86, 0.46, axis=(0, 0, 1), sides=6, taper=0.62)
    G.cyl(bm, (0.0, 0.30, 2.00), (0.0, 0.30, 2.24), 0.62, segs=8, r2=0.74)
    for s in (+1, -1):                                  # the gimbal yoke arms
        x0, x1 = _xs(s * 0.60, s * 0.78)
        G.box(bm, (x0, 0.16, 2.24), (x1, 0.44, 2.68))
    G.part("LensHousing", bm, c, "Body", LENS_PIVOT, parent="Core")

    bm = bmesh.new()
    G.hex_prism(bm, LENS_FACE, 0.56, 0.16, axis=(0, 0, 1), sides=8)
    G.diamond(bm, (0.0, 0.30, 1.88), radius=0.20, length=0.34, axis=(0, 0, 1), sides=4)
    G.part("Lens", bm, c, "Cyan", (0.0, 0.30, 2.02), parent="LensHousing")


def _head(G, c):
    """A short neck post and the arrowhead wedge that sits on it, visor bar and all."""
    bm = bmesh.new()
    G.beveled_box(bm, (-0.46, -0.06, 5.10), (0.46, 0.56, 6.22), bevel=0.10)
    for s in (+1, -1):                                  # two struts bracing it forward
        G.plank(bm, (s * 0.38, 0.02, 5.20), (s * 0.50, 0.50, 6.06), w=0.16, t=0.14,
                bevel=0.0)
    G.part("Neck", bm, c, "Body", NECK_PIVOT, parent="Core")

    # THE WEDGE.  3.32 wide (the core is 3.90), 3.25 deep and 0.98 thick in the slab
    # alone, 1.72 tall counting the crest and chin - roughly four times the mass of the
    # 2.0-wide, 0.60-thick block this was, which is what turns a cube with a band round
    # it back into the sheet's arrowhead.
    bm = bmesh.new()
    G.prism(bm, _arrow_pts(1.0), HEAD_Z0, HEAD_Z1)                  # the wedge slab
    G.prism(bm, _arrow_pts(0.70, y_off=-0.06), HEAD_Z1, CREST_Z1)   # the raked crest
    G.prism(bm, _arrow_pts(0.80, y_off=0.04), 5.78, HEAD_Z0)        # the tapered chin
    for s in (+1, -1):                                              # cheek armour
        x0, x1 = _xs(s * 1.30, s * 1.62)
        G.box(bm, (x0, -0.72, 6.12), (x1, 0.52, 7.10), rot=G.rot_euler(0, 0, -s * 12))
    G.spike_shard(bm, (0.0, 2.14, 6.62), (0.0, 2.62, 6.54), 0.42, thick=0.34)
    for i, x in enumerate((-0.34, 0.34)):               # bolts on the crest
        G.hex_prism(bm, (x, 0.20, CREST_Z1 + 0.02), 0.11, 0.09, axis=(0, 0, 1), sides=6)
        G.hex_prism(bm, (x, 0.86, CREST_Z1 + 0.02), 0.11, 0.09, axis=(0, 0, 1), sides=6)
    G.part("Head", bm, c, "Body", HEAD_PIVOT, parent="Neck")

    bm = bmesh.new()                                    # panel trim round the wedge
    # A collar that follows the arrowhead instead of a straight box: at scale 0.80 it
    # stands proud of the 0.70 crest all the way round and stays inside the 1.00 slab,
    # where a box wide enough to clear the crest overhung the swept-back rear corners.
    G.prism(bm, _arrow_pts(0.80, y_off=0.02), HEAD_Z1 - 0.04, HEAD_Z1 + 0.08)
    for s in (+1, -1):
        G.plank(bm, (s * 0.54, 1.52, HEAD_Z1 - 0.02), (s * 1.38, 0.26, HEAD_Z1 - 0.02),
                w=0.12, t=0.10, bevel=0.0)
        x0, x1 = _xs(s * 1.52, s * 1.68)
        G.box(bm, (x0, -0.62, 6.30), (x1, -0.10, 6.98))
    G.part("HeadTrim", bm, c, "BodyLight", HEAD_PIVOT, parent="Head")

    # THE VISOR BAR.  Not a pip on the nose: a 3.08-wide, 0.68-tall chevron bar laid
    # along BOTH forward-facing faces of the wedge, its outer edge 0.15-0.19 proud of
    # the hull and its inner edge sunk inside it, so it reads as one wide magenta band
    # set into the front of the arrowhead rather than a band wrapped round a box.
    bm = bmesh.new()
    G.prism(bm, [(0.00, 2.42), (1.12, 0.92), (1.54, 0.28), (1.28, 0.02), (0.90, 0.60),
                 (0.00, 2.00), (-0.90, 0.60), (-1.28, 0.02), (-1.54, 0.28),
                 (-1.12, 0.92)], 6.30, 6.98)
    for s in (+1, -1):                                  # a slit on each cheek
        x0, x1 = _xs(s * 1.46, s * 1.64)
        G.box(bm, (x0, -0.58, 6.36), (x1, 0.06, 6.66), rot=G.rot_euler(0, 0, -s * 12))
    G.box(bm, (-0.24, 0.80, CREST_Z1 - 0.03), (0.24, 1.16, CREST_Z1 + 0.05))
    G.part("Visor", bm, c, "Magenta", VISOR_PIVOT, parent="Head")


def _antennae(G, c):
    """Two SHORT spikes raked up and back off the crest, each with a lit tip.  They were
    2.42 long on a 0.15 root - insect feelers that owned the top of the silhouette; the
    sheet has two stubby pins, so they are 1.16 long on a 0.22 root now."""
    for s, tag in ((+1, "R"), (-1, "L")):
        base = (s * ANT_BASE[0], ANT_BASE[1], ANT_BASE[2])
        tip = (s * ANT_TIP[0], ANT_TIP[1], ANT_TIP[2])
        bm = bmesh.new()
        G.horn(bm, base, tip, r0=0.22, r1=0.06, bow=(s * 0.04, 0.07, 0.0), n=5, segs=4,
               power=1.3)
        G.hex_prism(bm, base, 0.26, 0.18, axis=(s * 0.2, -0.26, 1.0), sides=6)
        G.box(bm, (min(base[0], base[0] + s * 0.2) - 0.12, base[1] - 0.24, base[2] - 0.10),
              (max(base[0], base[0] + s * 0.2) + 0.12, base[1] + 0.20, base[2] + 0.22))
        G.part("Antenna_" + tag, bm, c, "Body", base, parent="Head")

        bm = bmesh.new()
        G.diamond(bm, tip, radius=0.13, length=0.34,
                  axis=(tip[0] - base[0], tip[1] - base[1], tip[2] - base[2]), sides=4)
        G.part("AntennaTip_" + tag, bm, c, "Magenta", tip, parent="Antenna_" + tag)


def _pod(G, c, s):
    """One floating shoulder pod: a link, an angular shield, a cyan inner face and a
    magenta rim down its outboard edges.  Pushed 0.16 further out (POD_X 2.92 -> 3.08)
    and 0.63 higher (POD_C z 3.95 -> 4.58) on a link stretched from 0.76 to 1.02, so the
    shield floats clear of the hull with daylight round it instead of nestling on it."""
    tag = "R" if s > 0 else "L"
    link_in = (s * LINK_IN[0], LINK_IN[1], LINK_IN[2])
    hinge = (s * POD_HINGE[0], POD_HINGE[1], POD_HINGE[2])

    bm = bmesh.new()
    G.plank(bm, link_in, hinge, w=0.36, t=0.32, bevel=0.06)
    G.hex_prism(bm, hinge, 0.28, 0.22, axis=(1, 0, 0), sides=6)
    G.hex_prism(bm, link_in, 0.24, 0.16, axis=(1, 0, 0), sides=6)
    G.part("Link_" + tag, bm, c, "Body", link_in, parent="Core")

    # The shield outline, drawn in the pod's own plane: local x runs along world +Y,
    # local y along world +Z (surface_frame of the +X normal), so this is a side view.
    # surface_frame of the -X normal flips its tangent to world -Y, so the LEFT pod has
    # to be fed a flipped outline or its nose-forward corner comes out pointing aft.
    shield = [(0.95, 0.72), (0.28, 1.06), (-0.78, 0.60), (-1.06, -0.36),
              (-0.40, -1.10), (0.56, -0.86), (1.06, -0.06)]
    sh = shield if s > 0 else [(-p[0], p[1]) for p in shield]
    bm = bmesh.new()
    G.plate(bm, sh, 0.34, at=(s * POD_X, POD_C[1], POD_C[2]), normal=(s, 0, 0))
    G.plate(bm, [(p[0] * 0.72, p[1] * 0.72) for p in sh], 0.46,
            at=(s * (POD_X - 0.04), POD_C[1], POD_C[2]), normal=(s, 0, 0))
    # Two armour ribs, standing 0.06 proud of both faces of the 2.91..3.25 plate and
    # both inside the shield outline (flush ribs showed only where they hung off it).
    rx0, rx1 = _xs(s * 2.86, s * 3.32)
    G.box(bm, (rx0, -0.64, 3.75), (rx1, 0.50, 4.03))                # lower rib
    G.box(bm, (rx0, -0.70, 4.97), (rx1, 0.88, 5.23))                # upper rib
    for y in (-0.55, 0.30):                                          # bolt heads
        G.hex_prism(bm, (s * 3.28, y, 4.73), 0.13, 0.10, axis=(s, 0, 0), sides=6)
    G.part("Pod_" + tag, bm, c, "Body", hinge, parent="Link_" + tag)

    bm = bmesh.new()                                    # the lit inner face
    G.plate(bm, [(p[0] * 0.60, p[1] * 0.60) for p in sh], 0.16,
            at=(s * (POD_X - 0.24), POD_C[1], POD_C[2]), normal=(s, 0, 0))
    fx0, fx1 = _xs(s * 2.76, s * 2.90)
    G.box(bm, (fx0, -0.18, 3.97), (fx1, 0.20, 5.25))
    G.part("PodFace_" + tag, bm, c, "Cyan", hinge, parent="Pod_" + tag)

    bm = bmesh.new()                                    # magenta down the outboard rim
    G.plank(bm, (s * 3.28, 0.92, 5.25), (s * 3.28, 0.22, 5.65), w=0.16, t=0.12, bevel=0.0)
    G.plank(bm, (s * 3.28, 0.92, 5.25), (s * 3.28, 1.02, 4.01), w=0.16, t=0.12, bevel=0.0)
    G.plank(bm, (s * 3.28, 1.02, 4.01), (s * 3.28, -0.36, 3.49), w=0.16, t=0.12, bevel=0.0)
    G.part("PodEdge_" + tag, bm, c, "Magenta", hinge, parent="Pod_" + tag)


def _fin_blade(G, c, tag):
    """One of the four fins: a tapering blade off the core underside, a magenta strip
    down its leading edge and a cyan strip down its trailing edge.  All four now hang
    24-25 degrees off vertical with only 4-5 degrees of that in x - a swept tail
    assembly.  They used to reach x 2.58 / y +1.22 (front) and x 2.04 / y -3.45 (rear),
    32 and 48 degrees out, which is what made the drone stand up like a spider."""
    root, tip, s = _fin(tag)
    # spike_shard runs `width` along the horizontal perpendicular of root->tip, which for
    # a blade hanging down and out is the front-back CHORD; `thick` is across the blade.
    # Magenta is on the +Y (leading) edge of all four fins and cyan on the -Y edge, so
    # the strips read the same way round whichever fin the camera catches.
    lead = (root[0], root[1] + 0.56, root[2])
    trail = (root[0], root[1] - 0.56, root[2])
    # EVERY x offset on the mount has to carry `s`, or the left mount comes out a
    # different width AND in a different place from the right one.
    x0, x1 = _xs(root[0] - s * 0.22, root[0] + s * 0.56)

    bm = bmesh.new()
    G.spike_shard(bm, root, tip, 1.16, thick=0.34)
    G.beveled_box(bm, (x0, root[1] - 0.54, root[2] - 0.24),
                  (x1, root[1] + 0.54, root[2] + 0.30), bevel=0.09)
    G.spike_shard(bm, (root[0] + s * 0.10, root[1] - 0.40, root[2] - 0.14),
                  _along(root, tip, 0.60), 0.60, thick=0.26)        # the stepped notch
    G.plank(bm, _along(root, tip, 0.16), _along(root, tip, 0.84), w=0.22, t=0.40,
            bevel=0.0)                                              # the spar
    G.part("Fin_" + tag, bm, c, "Body", root, parent="Core")

    bm = bmesh.new()                                    # magenta down the leading edge
    G.plank(bm, lead, _along(lead, tip, 0.86), w=0.20, t=0.16, bevel=0.0)
    G.spike_shard(bm, _along(lead, tip, 0.82), _along(lead, tip, 1.00), 0.26, thick=0.20)
    G.part("FinEdge_" + tag, bm, c, "Magenta", root, parent="Fin_" + tag)

    bm = bmesh.new()                                    # cyan down the trailing edge
    G.plank(bm, trail, _along(trail, tip, 0.80), w=0.18, t=0.14, bevel=0.0)
    G.part("FinTrim_" + tag, bm, c, "Cyan", root, parent="Fin_" + tag)


# ================================================================= the charging pad
def _seat(G):
    """The charging pad it sleeps on: a dark hex plate with a glowing cyan ring set into
    its face, a cable running off one side and four striped rocks around it."""
    c = G.begin(SEAT, GUARDIAN, prefix="ScanSeat")

    bm = bmesh.new()
    G.hex_prism(bm, (0.0, 0.0, 0.28), 2.50, 0.56, axis=(0, 0, 1), sides=6)
    G.hex_prism(bm, (0.0, 0.0, 0.12), 2.72, 0.24, axis=(0, 0, 1), sides=6)      # foot lip
    for i in range(6):                                  # clamps straddling the hex FLATS
        # Phase 30, not 0: the swept rear fins put their Sit tips at azimuth -64 degrees,
        # which is where a vertex clamp used to sit.  On the flats every clamp is a full
        # stud clear of a foot.
        a = math.radians(60 * i + 30)
        cx, cy = math.cos(a) * 2.34, math.sin(a) * 2.34
        G.box(bm, (cx - 0.30, cy - 0.20, 0.10), (cx + 0.30, cy + 0.20, 0.64),
              rot=G.rot_euler(0, 0, 60 * i + 30))
        G.hex_prism(bm, (cx, cy, 0.66), 0.13, 0.10, axis=(0, 0, 1), sides=6)
    G.part("Pad", bm, c, "PadDark", (0.0, 0.0, 0.0), parent=None)

    bm = bmesh.new()                                    # the ring set into the top face
    G.torus(bm, (0.0, 0.0, 0.58), 1.62, 0.11, rot=None, seg_major=14, seg_minor=5)
    G.hex_prism(bm, (0.0, 0.0, 0.58), 0.42, 0.10, axis=(0, 0, 1), sides=6)
    G.part("PadRing", bm, c, "Cyan", (0.0, 0.0, 0.56), parent="Pad")

    bm = bmesh.new()                                    # cable trim off the -x side
    G.tube(bm, [(-2.50, -0.30, 0.34), (-3.20, -0.62, 0.26), (-3.90, -0.40, 0.18),
                (-4.60, -0.86, 0.14)], [0.16, 0.14, 0.13, 0.11], segs=5)
    for x in (-3.10, -4.10):
        G.box(bm, (x - 0.16, -0.84, 0.0), (x + 0.16, -0.30, 0.22))
    G.part("Cable", bm, c, "PadDark", (-2.50, -0.30, 0.34), parent="Pad")

    # The rocks are pushed clear of where the rear fin tips come down in Sit
    # (+-0.96, -1.94, on the pad itself now) and lifted so nothing dips under the floor:
    # rock() jitters by
    # (1 +- j) BEFORE the scale, so the lowest vertex is cz - r * 0.62 * 1.24, and a
    # centre at 0.78 r leaves that a hair above zero instead of 0.26 below it.
    ROCKS = ((3.10, 1.20, 0.86), (-3.30, 0.95, 0.72),
             (3.20, -2.70, 0.72), (-3.10, -2.95, 0.86))

    bm = bmesh.new()                                    # the rocks it rests among
    for i, (x, y, r) in enumerate(ROCKS):
        G.rock(bm, (x, y, r * 0.78), r, seed=21 + i, jitter=0.24, subdiv=1,
               scale=(1.0, 0.95, 0.62))
    G.part("Rocks", bm, c, "PadRock", (0.0, 0.0, 0.0), parent="Pad")

    bm = bmesh.new()                                    # thin magenta strips on the rocks
    for i, (x, y, r) in enumerate(ROCKS):
        G.plank(bm, (x - r * 0.72, y - r * 0.18, r * 0.86),
                (x + r * 0.72, y + r * 0.24, r * 0.72), w=0.16, t=0.10, bevel=0.0)
    G.part("RockGlow", bm, c, "Magenta", (0.0, 0.0, 0.0), parent="Rocks")
    return c
