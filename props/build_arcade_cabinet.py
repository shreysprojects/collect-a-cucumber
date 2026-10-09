"""Upright arcade cabinet: two profiled side panels capped edge-to-edge in bright orange
T-molding, a lit marquee, a raked CRT with neon pixel art, an angled control deck (stick
left, six buttons right) and a coin door over a kick space.  Faces +Y.

The player-facing front is built in three value steps - near-black control deck, charcoal
frame around the screen and marquee, mid-grey plinth under the coin door - so the recess
and the overhang still read with every neon part switched off."""
import bmesh, math

COLLECTION = "ArcadeCabinet"

NOTES = (
    "Upright cabinet, 2.84 wide (x) x 3.00 deep (y) x 6.42 tall over the T-molding "
    "bead; the body inside the bead is 2.76 x 3.00 x 6.40.  Centred on x=0, facing +Y. "
    "It stands on four feet, so the body floats 0.16 clear of the floor and the front "
    "kick space reads.  Both side panels are one prism of the classic cabinet profile "
    "- vertical back, marquee stepping forward at the top, screen recessed, control "
    "deck jutting out to y=+1.50, coin door and kick tucked back underneath.  Along the "
    "molded run (over the top and down the whole front) the panel stops EDGE_SET=0.13 "
    "short of that silhouette and the orange T-molding bead rides ON the set-back edge, "
    "so it caps it as a 0.30-wide half-round standing 0.15 proud of the panel edge and "
    "0.04 proud of each side face - no blue edge strip is left showing (recolour "
    "TMolding for a cheap variant; it is the piece that names the object).  The panel's "
    "back and bottom edges are NOT set back: they carry no molding and have to stay "
    "flush with the body core and sit on the feet.\n"
    "The front is three objects at three values so it reads with the neon off: "
    "DarkShell (near-black - control deck, its under-slope, the coin slots, the feet), "
    "FrontFrame (charcoal - marquee surround, the solid the screen recess is sunk into, "
    "the bezel) and Plinth (mid grey - coin-door face, kick, base).  The screen is a "
    "hole punched in a lighter frame, and the deck reads as a dark slab overhanging a "
    "grey plinth.\n"
    "The player-facing layout is deliberately asymmetric: the joystick is at x=+0.62, "
    "i.e. the player's LEFT as they stand in front of the cabinet, and the six buttons "
    "run from x=-0.26 to x=-0.88; the two coin slots sit on the +x half of the coin door "
    "and the coin return on the -x half.  Control-deck surface is z 2.62-2.86 (waist "
    "height on an R15 avatar); a player stands at about y=+2.5.\n"
    "Glowing parts are rbx_material Neon: MarqueeText, PixelsCyan, PixelsLime.  Cycle "
    "their Transparency to flicker the marquee or animate the screen.  RedControls holds "
    "the joystick ball top AND the front row of three buttons (one colour + material = "
    "one part, per the merge rule); YellowButtons is the back row.  Metalwork holds the "
    "joystick base plate/washer/shaft plus the coin-door plate and its return lip."
)

PIVOTS = {
    "JoystickPivot": (0.62, 1.06, 2.74),    # ball-top swivel, on the deck surface
    "CoinDoorHinge": (-1.16, 0.76, 1.25),   # door swings open toward -x
    "MarqueeCentre": (0.00, 0.62, 5.675),   # marquee panel face centre
}

STATES = {"CoinDoorShut": 0.0, "CoinDoorOpen": -100.0}   # degrees about CoinDoorHinge

# ---------------------------------------------------------------- master dimensions
SIDE_IN, SIDE_OUT = 1.16, 1.38      # side panel inner / outer x
MOLD_X, MOLD_R = 1.27, 0.15         # T-molding bead centre / radius -> half width 1.42
EDGE_SET = 0.13                     # how far the PANEL edge is set back from the outer
                                    # silhouette along the molded run, so the bead caps
                                    # that edge instead of hiding inside it
FOOT_Z = 0.16                       # body starts here; the feet fill 0 .. FOOT_Z

# The whole prop is this one silhouette, drawn in the YZ plane (y, z), front = +y.
PROFILE = [(-1.50, FOOT_Z),   # back, on the floor
           (-1.50, 6.40),     # back, at full height
           (0.66, 6.40),      # top of the marquee
           (0.66, 5.05),      # bottom of the marquee, overhanging the screen
           (0.14, 4.62),      # top of the raked screen recess
           (0.46, 3.06),      # bottom of the raked screen recess
           (0.62, 2.86),      # rear edge of the control deck
           (1.50, 2.62),      # deck nose - the most forward point of the cabinet
           (1.50, 2.30),      # nose underside
           (0.76, 1.88),      # slope back under the deck
           (0.76, 0.62),      # coin door face, straight down
           (0.34, 0.38),      # kick angle
           (0.34, FOOT_Z)]    # base, on the feet

TILT = 11.6                   # screen rake off vertical, degrees (top leans back)
S_C = (0.30, 3.84)            # (y, z) centre of the screen face plane
V_TOP = 0.796                 # half the screen opening measured up the raked face
BEZEL_D = 0.30                # how deep the screen sits behind the bezel face


# ---------------------------------------------------------------- local helpers
def _yz(D, bm, pts, x0, x1):
    """Extrude a (y, z) side profile along X from x0 to x1.

    Done as two single-axis rotations applied in sequence (Rx then Rz), so it never
    depends on which way round rot_euler composes a multi-axis Euler."""
    vs = D.prism(bm, pts, x0, x1)
    D.xform(bm, vs, D.rot_euler(rx=90))
    D.xform(bm, vs, D.rot_euler(rz=90))
    return vs


def _inset(pts, delta):
    """Offset a closed (y, z) polygon inward by `delta`, mitred so every edge keeps
    exactly `delta` of clearance.  This is what sets the side panel back from the outer
    silhouette without the setback opening up at every corner."""
    n = len(pts)
    area = sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1]
               for i in range(n))
    sgn = 1.0 if area > 0 else -1.0          # inward normal is left of travel when CCW
    out = []
    for i in range(n):
        p, q, r = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
        ns = []
        for (a, b) in ((p, q), (q, r)):
            dx, dy = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dy) or 1.0
            ns.append((-sgn * dy / L, sgn * dx / L))
        bx, by = ns[0][0] + ns[1][0], ns[0][1] + ns[1][1]
        L = math.hypot(bx, by) or 1.0
        cdot = max(-1.0, min(1.0, ns[0][0] * ns[1][0] + ns[0][1] * ns[1][1]))
        t = delta / max(0.35, math.sqrt(max(0.0, (1.0 + cdot) / 2.0)))   # mitre, clamped
        out.append((q[0] + bx / L * t, q[1] + by / L * t))
    return out


def _panel_edge():
    """The side-panel outline: PROFILE with the molded run (index 1 round to the last
    point - over the top and down the whole front) pulled back by EDGE_SET, so the
    T-molding bead can sit centred ON that edge and cap it.  The back edge and the
    bottom edge carry no molding, so their corners are restored: the back has to stay
    flush with the body core and the base has to keep sitting on the feet."""
    ins = _inset(PROFILE, EDGE_SET)
    p = list(ins)
    p[0] = PROFILE[0]                            # back bottom - neither edge is molded
    p[1] = (PROFILE[1][0], ins[1][1])            # back top - only the top edge moves in
    p[-1] = (ins[-1][0], PROFILE[-1][1])         # base front - only the kick moves in
    return p


PANEL = _panel_edge()         # side-panel outline; PANEL[1:] is the T-molding bead path


def _scr(u, v, d=0.0):
    """Screen-plane coords -> world.  u across (+x is the player's left), v up the raked
    face, d out of the face (d = 0 is flush with the outer silhouette PROFILE)."""
    s, ct = math.sin(math.radians(TILT)), math.cos(math.radians(TILT))
    return (u, S_C[0] - v * s + d * ct, S_C[1] + v * ct + d * s)


def _scr_box(D, bm, u, v, d, hu, hd, hv, bevel=None):
    """A box lying in the raked screen plane, centred at (u, v, d)."""
    p = _scr(u, v, d)
    lo = (p[0] - hu, p[1] - hd, p[2] - hv)
    hi = (p[0] + hu, p[1] + hd, p[2] + hv)
    rot = D.rot_euler(rx=TILT)
    if bevel:
        return D.beveled_box(bm, lo, hi, bevel=bevel, rot=rot)
    return D.box(bm, lo, hi, rot=rot)


def _deck(u, t, h=0.0):
    """Control-deck coords -> world.  t = 0 at the rear edge, 1 at the front nose,
    h above the deck surface (the deck rakes down ~15 deg toward the player)."""
    return (u, 0.62 + 0.88 * t + h * 0.2631, 2.86 - 0.24 * t + h * 0.9648)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    blue = D.C("plastic_blue")        # the big mass: side panels, hood, marquee lip
    black = D.C("plastic_black")      # darkest front step: control deck, slots, feet
    char = D.C("metal_dark")          # middle step: marquee + screen frame
    grey = D.C("metal_mid")           # lightest step: coin-door plinth, kick, base
    orange = D.C("accent_orange")     # T-molding - the signature edge
    white = D.C("plastic_white")
    pink = D.C("neon_pink")
    dark = D.C("screen_dark")
    cyan = D.C("neon_cyan")
    lime = D.C("neon_lime")
    red = D.C("plastic_red")
    yellow = D.C("plastic_yellow")
    steel = D.C("metal_light")

    # where the screen recess bottoms out, in (y, z)
    bt, bb = _scr(0.0, V_TOP, -BEZEL_D), _scr(0.0, -V_TOP, -BEZEL_D)

    # ============================================================ 1  cabinet shell
    bm = bmesh.new()
    _yz(D, bm, PANEL, SIDE_IN, SIDE_OUT)                   # side panel, player's left
    _yz(D, bm, PANEL, -SIDE_OUT, -SIDE_IN)                 # side panel, player's right
    D.box(bm, (-SIDE_IN, -1.50, FOOT_Z), (SIDE_IN, -0.10, 6.10))          # body core
    D.beveled_box(bm, (-SIDE_IN, -1.50, 6.10), (SIDE_IN, 0.66, 6.40), bevel=0.06)  # hood
    D.beveled_box(bm, (-SIDE_IN, 0.24, 5.05), (SIDE_IN, 0.66, 5.30), bevel=0.05)   # lip
    D.new_obj("Cabinet", bm, c, blue, rbx_material="SmoothPlastic", roughness=0.5)

    # ======================================================= 2  front mass, darkest step
    # The front is split into three objects at three values: without that, the recessed
    # screen and the jutting deck only separate by facet shading and by the neon on top.
    bm = bmesh.new()
    # control deck + the slope under its overhang
    _yz(D, bm, [(0.62, 2.86), (1.50, 2.62), (1.50, 2.30), (0.76, 1.88),
                (-0.30, 1.88), (-0.30, 2.86)], -SIDE_IN, SIDE_IN)
    for sx in (0.22, 0.44):                                # coin slots, dark on the plate
        D.box(bm, (sx - 0.045, 0.80, 1.14), (sx + 0.045, 0.87, 1.44))
    D.box(bm, (-0.54, 0.80, 0.90), (-0.20, 0.87, 1.08))                   # return mouth
    for (fx, fy) in ((MOLD_X, -1.30), (-MOLD_X, -1.30), (MOLD_X, 0.10), (-MOLD_X, 0.10)):
        D.cyl(bm, (fx, fy, 0.00), (fx, fy, FOOT_Z + 0.02), 0.13, segs=5)  # levelling feet
    D.new_obj("DarkShell", bm, c, black, rbx_material="SmoothPlastic", roughness=0.55)

    # ======================================================= 3  front mass, middle step
    bm = bmesh.new()
    # marquee underside + the solid the screen recess is sunk into
    _yz(D, bm, [(0.66, 5.05), (bt[1], bt[2]), (bb[1], bb[2]), (0.62, 2.86),
                (-0.30, 2.86), (-0.30, 5.05)], -SIDE_IN, SIDE_IN)
    D.box(bm, (-SIDE_IN, -0.30, 5.30), (SIDE_IN, 0.58, 6.10))             # marquee box
    # bezel frame: 0.30 deep, front face flush with the outer silhouette
    _scr_box(D, bm, 0.00, 0.683, -0.15, SIDE_IN, 0.15, 0.113, bevel=0.05)
    _scr_box(D, bm, 0.00, -0.683, -0.15, SIDE_IN, 0.15, 0.113, bevel=0.05)
    for sx in (0.96, -0.96):
        _scr_box(D, bm, sx, 0.00, -0.15, 0.20, 0.15, 0.57, bevel=0.05)
    D.new_obj("FrontFrame", bm, c, char, rbx_material="SmoothPlastic", roughness=0.5)

    # ======================================================= 4  front mass, lightest step
    bm = bmesh.new()
    _yz(D, bm, [(0.76, 1.88), (0.76, 0.62), (0.34, 0.38), (0.34, FOOT_Z),
                (-0.30, FOOT_Z), (-0.30, 1.88)], -SIDE_IN, SIDE_IN)   # coin door + kick
    D.new_obj("Plinth", bm, c, grey, rbx_material="SmoothPlastic", roughness=0.55)

    # ============================================================ 5  T-molding
    # The bead centre rides ON the set-back panel edge, so half of it stands proud as a
    # 0.30-wide orange cap.  Bedding it INTO the panel is what made it a hairline before.
    bm = bmesh.new()
    for sx in (MOLD_X, -MOLD_X):
        pts = [(sx, p[0], p[1]) for p in PANEL[1:]]        # over the top, down the front
        D.tube(bm, pts, [MOLD_R] * len(pts), segs=6)
    D.new_obj("TMolding", bm, c, orange, rbx_material="SmoothPlastic", roughness=0.55)

    # ============================================================ 6  marquee
    bm = bmesh.new()
    D.beveled_box(bm, (-1.09, 0.52, 5.35), (1.09, 0.62, 6.00), bevel=0.05)
    D.new_obj("MarqueePanel", bm, c, white, rbx_material="SmoothPlastic", roughness=0.35)

    bm = bmesh.new()
    D.stroke_text(bm, "ARCADE", (0.0, 0.665, 5.54), height=0.27, radius=0.05, segs=3)
    D.new_obj("MarqueeText", bm, c, pink, rbx_material="Neon", emit=1.25)

    # ============================================================ 7  screen
    bm = bmesh.new()
    _scr_box(D, bm, 0.0, 0.0, -0.26, 0.76, 0.04, 0.57, bevel=0.03)
    D.new_obj("Screen", bm, c, dark, rbx_material="SmoothPlastic", roughness=0.15)

    bm = bmesh.new()                                        # a chunky invader, 6 blocks
    for (u, v, hu, hv) in ((-0.21, 0.36, 0.07, 0.06), (0.21, 0.36, 0.07, 0.06),
                           (0.00, 0.22, 0.34, 0.08), (0.00, 0.06, 0.48, 0.08),
                           (-0.34, -0.10, 0.14, 0.08), (0.34, -0.10, 0.14, 0.08)):
        _scr_box(D, bm, u, v, -0.195, hu, 0.025, hv)
    D.new_obj("PixelsCyan", bm, c, cyan, rbx_material="Neon", emit=1.2)

    bm = bmesh.new()                                        # ground bar, ship, its shot
    _scr_box(D, bm, 0.00, -0.48, -0.195, 0.70, 0.025, 0.04)
    _scr_box(D, bm, -0.32, -0.37, -0.195, 0.12, 0.025, 0.05)
    _scr_box(D, bm, -0.32, -0.16, -0.195, 0.03, 0.025, 0.06)
    D.new_obj("PixelsLime", bm, c, lime, rbx_material="Neon", emit=1.2)

    # ============================================================ 8  controls
    bm = bmesh.new()
    D.uvsphere(bm, _deck(0.62, 0.50, 0.46), 0.15, segs=8, rings=5)        # ball top
    for u in (-0.26, -0.54, -0.82):                                       # front row
        D.cyl(bm, _deck(u, 0.66, -0.03), _deck(u, 0.66, 0.055), 0.115, segs=8, r2=0.10)
    D.new_obj("RedControls", bm, c, red, rbx_material="SmoothPlastic", roughness=0.35)

    bm = bmesh.new()
    for u in (-0.32, -0.60, -0.88):                                       # back row
        D.cyl(bm, _deck(u, 0.32, -0.03), _deck(u, 0.32, 0.055), 0.115, segs=8, r2=0.10)
    D.new_obj("YellowButtons", bm, c, yellow, rbx_material="SmoothPlastic", roughness=0.35)

    # ============================================================ 9  metalwork
    bm = bmesh.new()
    D.cyl(bm, _deck(0.62, 0.50, -0.02), _deck(0.62, 0.50, 0.05), 0.26, segs=10)  # plate
    D.cyl(bm, _deck(0.62, 0.50, 0.03), _deck(0.62, 0.50, 0.12), 0.13, segs=8)    # washer
    D.cyl(bm, _deck(0.62, 0.50, 0.10), _deck(0.62, 0.50, 0.44), 0.055, segs=6)   # shaft
    D.beveled_box(bm, (-0.68, 0.76, 0.80), (0.68, 0.84, 1.70), bevel=0.05)       # coin door
    D.box(bm, (-0.58, 0.76, 0.72), (-0.16, 0.94, 0.86))                          # return lip
    D.new_obj("Metalwork", bm, c, steel, rbx_material="Metal", metallic=0.6, roughness=0.35)

    return c
