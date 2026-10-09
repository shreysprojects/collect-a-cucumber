"""Party DJ booth: a leaning LED front panel with big DJ letters, two MIRRORED turntables
and a recessed mixer on the top deck, flanked by two three-way speaker stacks with spot
cans clipped on top.  Faces +Y - the panel, every driver and both spots aim at the floor."""
import bmesh, math

COLLECTION = "DJBooth"

NOTES = (
    "Faces +Y.  Footprint 8.1 wide (x -4.04..4.04) x 2.7 deep (y -1.78..0.93), 4.21 tall to "
    "the top of the spot cans.  The desk is 4.44 wide (x -2.22..2.22), its work surface is at "
    "z 2.44 - hip height for a 5-stud avatar standing on the -y side - and each turntable is a "
    "0.49-tall console standing proud of it: deck top 2.90, platter top 3.00 (sunk to 2.87), "
    "record face 3.09, label 3.14, spindle 3.22 - the decks read as machines sitting ON the "
    "desk rather "
    "than trays sunk into it.  The mixer stays sunk between them at 2.54.  Nothing below z 0.\n"
    "Every part that rests on another sinks 0.03 INTO its host instead of butting flush "
    "(deck and mixer bottoms 2.41, yoke arms 3.43, cabinets 0.23, carcass and cheeks 0.27) and "
    "every slot is a proud track, not a flush inlay - two coplanar faces z-fight and render as "
    "a band of grainy dirt.  Keep 0.03 of overlap if you move anything.\n"
    "Deck A / stack A are at +x, deck B / stack B at -x.  A render is taken from +Y, so +x is "
    "SCREEN-LEFT: 'A' is the deck on the left of the picture.  The two decks are true mirror "
    "images, not copies - each tonearm pivots on its own OUTER rear corner so the arms swing "
    "away from the mixer, and each deck's pitch slot sits on its own INNER edge.\n"
    "Speaker cabinets are 1.36 x 1.88 x 3.20 at x +/-3.30: woofer at z 1.16, a 4-slat grille "
    "at z 1.78-2.28, a mid at z 2.64 and a square horn tweeter at z 3.16.  Each spot can is "
    "clamped in a two-arm yoke above the cabinet - the arms are 0.08 thick at x +/-0.25 from "
    "the spot axis, so their inner faces bite into the 0.25-radius can wall instead of missing "
    "it, they run past its axis to z 3.98, and a 0.07 pivot boss bridges each arm into the can "
    "at z 3.88 - tilted 30 degrees below horizontal, so the beam lands about 6 studs out on "
    "the dance floor.\n"
    "Everything sharing a colour + material is ONE mesh, so this is 11 objects rather than 60. "
    "To move a speaker stack on its own, split that stack's islands out of Frame / Shell / "
    "Consoles / Hardware / Trim / SpotGlow first.  The greys are a deliberate value ladder - "
    "Records (darkest) < Shell < Consoles < Frame < Hardware < Knobs (brightest) - so no two "
    "touching parts share a value: black cabinet, mid plinth and cones, dark console, light "
    "platter, near-black matte vinyl on top of it.\n"
    "Glow parts: LedStrip (neon_cyan, emit 1.2 - the wide front strip plus the +x mixer level "
    "LED), Letters (neon_pink, emit 1.3 - the DJ letters plus the -x level LED) and SpotGlow "
    "(neon_purple, emit 1.15 - both spot lenses, the pinstripe along the top of the panel and "
    "the 3-bar VU ladder).  Beat-sync by cycling their Transparency; nothing else has to move.\n"
    "The two ground cables are deliberately unequal - the -x run is longer and climbs higher up "
    "its cabinet - and the DJ letters sit off-centre at +x with the VU ladder at -x, so the "
    "prop never reads as a mirrored blank."
)

PIVOTS = {
    "DeckAPlatter": (1.30, -0.44, 2.90),    # spin about +Z
    "DeckBPlatter": (-1.30, -0.44, 2.90),
    "DeckATonearm": (1.74, -1.00, 3.20),    # swing about +Z, +angle parks it off the record
    "DeckBTonearm": (-1.74, -1.00, 3.20),   # mirrored: negate the angle
    "SpotA": (3.30, -0.30, 3.88),           # tilt about +X
    "SpotB": (-3.30, -0.30, 3.88),
}

STATES = {
    "SpotAimFloor": -120.0,   # degrees about X - as built, 30 deg below horizontal
    "SpotAimCrowd": -100.0,
    "SpotAimSky": -55.0,
    "ArmPlaying": 0.0,        # degrees about Z for a tonearm (negate on deck B)
    "ArmParked": 20.0,
}

# ---------------------------------------------------------------- the leaning front panel
FACE_TILT = 10.0                       # degrees; the top of the panel leans back toward -y
_FC = (0.0, 0.58, 1.31)                # centre of the panel slab
_FH = 1.00                             # half length up the slope
_CS = math.cos(math.radians(FACE_TILT))
_SN = math.sin(math.radians(FACE_TILT))


def _face(u, v, d):
    """A point on the leaning panel: u across, v up the slope, d out of the front face."""
    return (u, _FC[1] - _SN * v + _CS * d, _FC[2] + _CS * v + _SN * d)


def _face_box(D, bm, u, v, d, du, dv, dd, bevel=0.0):
    """A slab lying on the panel: half sizes du across, dv up the slope, dd out of the face."""
    cx, cy, cz = _face(u, v, d)
    lo, hi = (cx - du, cy - dd, cz - dv), (cx + du, cy + dd, cz + dv)
    rot = D.rot_euler(rx=FACE_TILT)
    if bevel > 0.0:
        return D.beveled_box(bm, lo, hi, bevel=bevel, rot=rot)
    return D.box(bm, lo, hi, rot=rot)


def _span(a, b):
    return (a, b) if a <= b else (b, a)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    black = D.C("plastic_black")     # dark value: carcasses, cabinets, slot tracks
    dark = D.C("metal_dark")         # turntable bodies, mixer, spot yokes
    mid = D.C("metal_mid")           # plinths, cheeks, work surface, grille, driver cones
    light = D.C("metal_light")       # platters, tonearms, horns, spot cans
    white = D.C("plastic_white")     # brightest value: knobs, faders, dust caps
    orange = D.C("accent_orange")
    cyan = D.C("neon_cyan")
    pink = D.C("neon_pink")
    purple = D.C("neon_purple")
    rubber = D.C("rubber_black")

    METAL = dict(rbx_material="Metal", metallic=0.55, roughness=0.42)
    DULL = dict(rbx_material="Metal", metallic=0.40, roughness=0.55)
    PLAS = dict(rbx_material="SmoothPlastic", roughness=0.45)

    SIDES = (1, -1)      # A = +x (screen-left in a +Y render), B = -x
    SPX = 3.30           # speaker stack centre |x|
    DKX = 1.30           # turntable centre |x|
    YDX = 0.25           # yoke arm offset from the spot axis - it BITES the can (r 0.24-0.26)
    tilt = D.rot_euler(rx=FACE_TILT)
    lay = D.rot_euler(rx=-90)          # local +Z -> +Y, for drivers mounted on a baffle

    # ============================================================ frame, plinths, deck, cones
    # metal_mid is the value that carries the black shells: plinth under them, cheeks beside
    # them, work surface on top, grille and driver cones on the black baffle.
    bm = bmesh.new()
    D.beveled_box(bm, (-2.30, -1.62, 0.00), (2.30, 0.90, 0.30), bevel=0.07)       # desk plinth
    D.beveled_box(bm, (-2.00, -1.56, 2.27), (2.00, 0.60, 2.44), bevel=0.05)       # work surface
    for s in SIDES:                                                               # side cheeks
        x0, x1 = _span(s * 2.00, s * 2.22)
        D.beveled_box(bm, (x0, -1.56, 0.27), (x1, 0.72, 2.58), bevel=0.06)
    for s in SIDES:                                                               # stack plinths
        x0, x1 = _span(s * 2.56, s * 4.04)
        D.beveled_box(bm, (x0, -1.66, 0.00), (x1, 0.34, 0.26), bevel=0.06)
    for s in SIDES:
        g0, g1 = _span(s * 2.68, s * 3.92)
        D.slat_run(bm, (g0, 0.24, 1.78), (g1, 0.34, 2.28), 4,
                   gap_frac=0.40, axis='x', bevel=0.0)                            # grille
        D.lathe(bm, [(0.00, 0.00), (0.50, 0.00), (0.50, 0.05), (0.12, 0.24), (0.00, 0.26)],
                segs=8, matrix=D.place((s * SPX, 0.20, 1.16), lay))               # woofer cone
        D.lathe(bm, [(0.00, 0.00), (0.28, 0.00), (0.28, 0.04), (0.00, 0.16)],
                segs=6, matrix=D.place((s * SPX, 0.20, 2.64), lay))               # mid cone
    D.new_obj("Frame", bm, c, mid, **METAL)

    # ============================================================ black shells
    bm = bmesh.new()
    D.beveled_box(bm, (-2.00, -1.52, 0.27), (2.00, 0.44, 2.30), bevel=0.10)       # desk carcass
    D.beveled_box(bm, (-2.00, _FC[1] - 0.13, _FC[2] - _FH),                       # leaning panel
                  (2.00, _FC[1] + 0.13, _FC[2] + _FH), bevel=0.09, rot=tilt)
    for s in SIDES:
        x0, x1 = _span(s * 2.62, s * 3.98)
        D.beveled_box(bm, (x0, -1.60, 0.23), (x1, 0.28, 3.46), bevel=0.09)        # cabinet
        p0, p1 = _span(s * 0.86 - 0.05, s * 0.86 + 0.05)                          # pitch track,
        D.box(bm, (p0, -0.10, 2.80), (p1, 0.22, 2.94))                            # proud of 2.90
    for fx in (-0.34, 0.00, 0.34):                                                # fader tracks,
        D.box(bm, (fx - 0.05, -0.34, 2.48), (fx + 0.05, 0.16, 2.60))              # proud of 2.54
    D.new_obj("Shell", bm, c, black, **PLAS)

    # ============================================================ turntable bodies, mixer, yokes
    # a value step darker than the work surface they stand on, so each console reads as a
    # separate box and the light platters pop off it.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.62, -1.18, 2.41), (0.62, 0.28, 2.54), bevel=0.04)       # mixer, sunk
    for s in SIDES:
        x0, x1 = _span(s * DKX - 0.62, s * DKX + 0.62)
        D.beveled_box(bm, (x0, -1.20, 2.41), (x1, 0.30, 2.90), bevel=0.05)        # deck body
        for dx in (-YDX, YDX):         # spot yoke: the arm runs past the can's axis to 3.98 and
            xa = s * SPX               # its inner face bites the can wall from z 3.63 to 3.98
            a0, a1 = _span(xa + dx - 0.04, xa + dx + 0.04)
            D.box(bm, (a0, -0.40, 3.43), (a1, -0.20, 3.98))                       # arm
            D.cyl(bm, (xa + dx * 0.64, -0.30, 3.88),                              # pivot boss:
                  (xa + dx * 1.28, -0.30, 3.88), 0.07, segs=6)                    # arm -> can
    D.new_obj("Consoles", bm, c, dark, **DULL)

    # ============================================================ bright hardware
    bm = bmesh.new()
    for s in SIDES:
        D.lathe(bm, [(0.00, 0.00), (0.50, 0.00), (0.50, 0.10), (0.46, 0.13), (0.00, 0.13)],
                segs=8, matrix=D.place((s * DKX, -0.44, 2.87)))                   # platter, sunk
        D.cyl(bm, (s * DKX, -0.44, 3.05), (s * DKX, -0.44, 3.22), 0.06, segs=6)   # spindle
        D.cyl(bm, (s * 1.74, -1.00, 2.85), (s * 1.74, -1.00, 3.20), 0.09, segs=5)  # arm pivot
        D.tube(bm, [(s * 1.74, -1.00, 3.20), (s * 1.68, -0.74, 3.26),
                    (s * 1.36, -0.40, 3.20), (s * 1.09, -0.23, 3.14)],
               [0.055, 0.046, 0.042, 0.042], segs=4)                              # tonearm
        D.cyl(bm, (s * 1.79, -1.06, 3.18), (s * 1.83, -1.18, 3.15), 0.10, segs=5)  # counterweight
        h0, h1 = _span(s * 1.09 - 0.075, s * 1.09 + 0.075)
        D.box(bm, (h0, -0.31, 3.06), (h1, -0.15, 3.17))                           # headshell
        D.lathe(bm, [(0.09, 0.00), (0.10, 0.06), (0.34, 0.26)], segs=4, phase=math.pi / 4,
                matrix=D.place((s * SPX, 0.16, 3.16), lay))                       # horn tweeter
        D.lathe(bm, [(0.00, -0.21), (0.24, -0.21), (0.26, 0.21), (0.00, 0.21)], segs=8,
                matrix=D.place((s * SPX, -0.30, 3.88), D.rot_euler(rx=-120)))     # spot can
    D.new_obj("Hardware", bm, c, light, **METAL)

    # ============================================================ vinyl
    # its own near-black MATTE colour, not the cabinets' plastic_black: the record faces up
    # into the sky light, and sharing the shell grey made it merge with the platter under it.
    # r 0.36 on a 0.50 platter leaves a 0.14 ring of bright metal all the way round.
    bm = bmesh.new()
    for s in SIDES:
        D.cyl(bm, (s * DKX, -0.44, 2.97), (s * DKX, -0.44, 3.09), 0.36, segs=8)   # record
    D.new_obj("Records", bm, c, D.C("screen_dark"), rbx_material="SmoothPlastic", roughness=0.90)

    # ============================================================ knobs / faders / dust caps
    bm = bmesh.new()
    for ky in (-0.94, -0.66):
        for kx in (-0.36, 0.00, 0.36):
            D.cyl(bm, (kx, ky, 2.49), (kx, ky, 2.67), 0.075, segs=6)
    for (fx, fy) in ((-0.34, -0.16), (0.00, 0.06), (0.34, -0.02)):                # caps, unequal
        D.box(bm, (fx - 0.085, fy - 0.055, 2.57), (fx + 0.085, fy + 0.055, 2.68))  # on the track
    for s in SIDES:
        D.lathe(bm, [(0.12, 0.00), (0.00, 0.09)], segs=6,
                matrix=D.place((s * SPX, 0.44, 1.16), lay))                       # dust cap
    D.new_obj("Knobs", bm, c, white, **PLAS)

    # ============================================================ orange trim
    bm = bmesh.new()
    _face_box(D, bm, 0.00, -0.92, 0.155, 1.90, 0.050, 0.035)                      # sill bar
    _face_box(D, bm, 0.00, -0.34, 0.150, 1.66, 0.035, 0.030)                      # bar over the LED
    for s in SIDES:
        D.cyl(bm, (s * DKX, -0.44, 3.06), (s * DKX, -0.44, 3.14), 0.20, segs=8)   # record label
        x0, x1 = _span(s * 2.66, s * 3.94)
        D.box(bm, (x0, 0.24, 0.38), (x1, 0.32, 0.52))                             # cabinet stripe
    D.new_obj("Trim", bm, c, orange, **PLAS)

    # ============================================================ glow
    bm = bmesh.new()
    _face_box(D, bm, 0.00, -0.62, 0.160, 1.80, 0.210, 0.060, bevel=0.05)          # LED strip
    D.box(bm, (0.14, -1.14, 2.51), (0.50, -1.06, 2.585))                          # level LED
    D.new_obj("LedStrip", bm, c, cyan, rbx_material="Neon", emit=1.2)

    bm = bmesh.new()
    D.stroke_text(bm, "DJ", (0.0, 0.0, 0.0), height=0.78, radius=0.075, segs=4,
                  matrix=D.place(_face(0.80, -0.09, 0.20), tilt))
    D.box(bm, (-0.50, -1.14, 2.51), (-0.14, -1.06, 2.585))                        # level LED
    D.new_obj("Letters", bm, c, pink, rbx_material="Neon", emit=1.3)

    bm = bmesh.new()
    for s in SIDES:
        D.cyl(bm, (s * SPX, -0.1355, 3.785), (s * SPX, -0.1008, 3.765), 0.22, segs=6)
    _face_box(D, bm, 0.00, 0.92, 0.150, 1.90, 0.040, 0.030)                       # pinstripe
    for (vv, uu) in ((-0.06, 0.30), (0.22, 0.22), (0.50, 0.14)):                  # VU ladder
        _face_box(D, bm, -1.30, vv, 0.155, uu, 0.055, 0.035)
    D.new_obj("SpotGlow", bm, c, purple, rbx_material="Neon", emit=1.15)

    # ============================================================ cable runs
    bm = bmesh.new()
    D.tube(bm, [(1.85, -1.48, 0.16), (2.20, -1.74, 0.10), (2.70, -1.78, 0.10),
                (3.20, -1.68, 0.11), (3.42, -1.60, 0.30), (3.42, -1.56, 0.62)],
           [0.055] * 6, segs=4)
    D.tube(bm, [(-1.85, -1.48, 0.16), (-2.15, -1.72, 0.10), (-2.62, -1.78, 0.10),
                (-3.05, -1.72, 0.10), (-3.40, -1.62, 0.26), (-3.46, -1.56, 0.68),
                (-3.38, -1.60, 0.94)],
           [0.055] * 7, segs=4)
    D.new_obj("Cables", bm, c, rubber, rbx_material="Rubber", roughness=0.70)

    return c
