"""Piano (Home) -- a glossy black GRAND piano with its lid propped open + a matching bench, fun-builds HomePiano 2026-09-24.

~6 wide x 7.1 high (lid up; the case top is at 3.85) x 10.7 long including the bench (~8.3 without it). The
keyboard faces the FRONT (-Z); the pianist sits on the bench in front of it, facing +Z. Seen from the keyboard the
long straight (bass) side is on the pianist's LEFT (+X) and the curved (treble) side on the right (-X): the case
outline is a front block + a bass block + two round columns (the bentside and the tail) joined by a "bridge"
block along their common tangent, pushed in a little so the bentside keeps a gentle S-curve. The lid (the same
outline, hinged along the bass side) is propped open on the treble side, showing the gold harp plate, the
strings, the dampers and the pin block; a music desk with a sheet of music stands in front of the pianist.
Gold details: the band round the case, leg cuffs, pedals, nameboard logo, key-slip pinstripe, the harp plate,
bench feet + cushion tufts.

Behaviour (FB/src/behaviours/*/Piano.lua): an invisible Seat on Pivot_Bench (top of the bench cushion, facing the
keyboard) with a "Play piano" prompt opens the piano GUI for whoever sits there; notes sound at Pivot_Sound and
music-note billboards float up from Pivot_Notes. Pivot_Keys = centre of the keyboard top (the pianist's hands).
"""
import math

BLACK = "1c1e24"      # glossy case (Reflectance 0.12 in Roblox)
BLACK_K = "15171b"    # black keys
IVORY = "f7f5ee"      # white keys
GOLD = "d9a93b"
WOOD = "8a5a2b"
STRING = "c9d0d8"
FELT = "23262c"
RED = "c7372f"
CREAM = "f2f0ea"
INK = "3b4350"
HOLE = "4a3322"

GLOSS = 0.12

# ---------------------------------------------------------------- layout (authored studs)
Z_FRONT = -1.5                            # case front
CASE_Y0, CASE_Y1 = 2.5, 3.85              # case bottom / top
CURVE_C, CURVE_R = (0.0, 1.5), 3.0        # treble bentside: a vertical round column (centre x, z), radius
TAIL_C, TAIL_R = (1.5, 4.0), 1.5          # rounded tail on the bass side
BRIDGE_IN = 0.06                          # the bridge face sits this far inside the columns' common tangent (a hint of S-curve)
LID_DEG = 32                              # lid opening, hinged along x = +3 at the case top
HINGE = (3.0, CASE_Y1)
KEYS_X = 2.7                              # keys span x in [-2.7, 2.7]
KEYBED_Y0 = CASE_Y0                       # keybed bottom (flush with the case bottom)
WHITE_Y0, WHITE_TOP = CASE_Y0 + 0.43, CASE_Y0 + 0.73
KEY_Z0 = -2.62                            # white key fronts
BENCH_Z = -4.5
BENCH_TOP = 2.2


def vdisc(m, name, cx, cz, y0, y1, diameter, color, material="SmoothPlastic", **kw):
    """vertical cylinder (a round slab / column) from y0 to y1"""
    return m.cylx(name, (cx, (y0 + y1) / 2, cz), y1 - y0, diameter, color, material, rot=(0, 0, 90), **kw)


def lid_place(x, y, z):
    """a point of the CLOSED lid -> where it is with the lid propped open (rotated about the hinge line, axis Z)"""
    a = math.radians(-LID_DEG)
    dx, dy = x - HINGE[0], y - HINGE[1]
    return (HINGE[0] + dx * math.cos(a) - dy * math.sin(a), HINGE[1] + dx * math.sin(a) + dy * math.cos(a), z)


def bridge(grow, depth):
    """The block that joins the two round columns along their outer common tangent (treble/back side), pushed
    BRIDGE_IN inside it, for the outline grown by `grow`. Returns (centre (x, z), length, yaw_deg, n (x, z))
    with the block's OUTER face on the line; depth = how far it reaches inward."""
    ax, az = CURVE_C
    bx, bz = TAIL_C
    ra, rb = CURVE_R + grow, TAIL_R + grow
    dx, dz = bx - ax, bz - az
    L = math.hypot(dx, dz)
    th_n = math.atan2(dz, dx) + math.acos((ra - rb) / L)      # the tangent's outward normal (the other one is +X)
    n = (math.cos(th_n), math.sin(th_n))
    c = n[0] * ax + n[1] * az + ra - BRIDGE_IN
    psi_a = math.acos((c - (n[0] * ax + n[1] * az)) / ra)
    psi_b = math.acos((c - (n[0] * bx + n[1] * bz)) / rb)
    qa = (ax + ra * math.cos(th_n - psi_a), az + ra * math.sin(th_n - psi_a))   # the line leaves column A here...
    qb = (bx + rb * math.cos(th_n + psi_b), bz + rb * math.sin(th_n + psi_b))   # ...and enters column B here
    t = (qb[0] - qa[0], qb[1] - qa[1])
    tl = math.hypot(*t)
    t = (t[0] / tl, t[1] / tl)
    eps = 0.1                                                   # run a little way into both columns
    qa = (qa[0] - t[0] * eps, qa[1] - t[1] * eps)
    qb = (qb[0] + t[0] * eps, qb[1] + t[1] * eps)
    centre = ((qa[0] + qb[0]) / 2 - n[0] * depth / 2, (qa[1] + qb[1]) / 2 - n[1] * depth / 2)
    yaw = math.degrees(math.atan2(-t[1], t[0]))                # CFrame.Angles(0, yaw, 0): local X along t
    return centre, tl + 2 * eps, yaw, n


def build(D, P):
    m = P.Model(D, "Piano", category="Home")
    gl = dict(reflectance=GLOSS)

    # ------------------------------------------------ case: front block + bass block + two round columns + the bridge
    cy, ch = (CASE_Y0 + CASE_Y1) / 2, CASE_Y1 - CASE_Y0
    m.block("CaseFront", (0, cy, (Z_FRONT + CURVE_C[1]) / 2), (6, ch, CURVE_C[1] - Z_FRONT), BLACK, **gl)
    m.block("CaseBass", (1.5, cy, (CURVE_C[1] + TAIL_C[1]) / 2), (3, ch, TAIL_C[1] - CURVE_C[1]), BLACK, **gl)
    vdisc(m, "CaseCurve", CURVE_C[0], CURVE_C[1], CASE_Y0, CASE_Y1, CURVE_R * 2, BLACK, **gl)
    vdisc(m, "CaseTail", TAIL_C[0], TAIL_C[1], CASE_Y0, CASE_Y1, TAIL_R * 2, BLACK, **gl)
    (bcx, bcz), blen, byaw, _ = bridge(0.0, 0.7)
    m.block("CaseBridge", (bcx, cy, bcz), (blen, ch, 0.7), BLACK, rot=(0, byaw, 0), **gl)
    # gold band round the bottom of the case
    g = 0.025
    band_y0, band_y1 = CASE_Y0 + 0.1, CASE_Y0 + 0.2
    by = (band_y0 + band_y1) / 2
    # (no front band: the keybed covers the case front there.) The treble straight runs from the front until it meets
    # BandCurve, which only comes outside the x = -3 wall for z > ~1.11
    m.block("BandTreble", (-3.015, by, (Z_FRONT + 1.3) / 2), (0.05, 0.1, 1.3 - Z_FRONT), GOLD, "Metal", collide=False)
    m.block("BandBass", (3.015, by, (Z_FRONT + TAIL_C[1]) / 2), (0.05, 0.1, TAIL_C[1] - Z_FRONT), GOLD, "Metal", collide=False)
    vdisc(m, "BandCurve", CURVE_C[0], CURVE_C[1], band_y0, band_y1, (CURVE_R + g) * 2, GOLD, "Metal", collide=False, smooth=False)
    vdisc(m, "BandTail", TAIL_C[0], TAIL_C[1], band_y0, band_y1, (TAIL_R + g) * 2, GOLD, "Metal", collide=False, smooth=False)
    (bcx, bcz), blen, byaw, _ = bridge(g, 0.05)
    m.block("BandBridge", (bcx, by, bcz), (blen - 0.1, 0.1, 0.05), GOLD, "Metal", rot=(0, byaw, 0), collide=False)

    # ------------------------------------------------ inside: gold harp plate, soundboard holes, strings, dampers, pin block
    # The five plate pieces overlap, so their tops are staggered 0.02 apart (textured Metal would shimmer on coplanar
    # faces): front + bass (they only meet edge to edge) highest, then bridge, tail, curve. The lowest top (py1 - 0.06)
    # stays 0.02 above the case top; every bottom is py0, hidden inside the case.
    inset = 0.3
    py0, py1 = CASE_Y1 - 0.04, CASE_Y1 + 0.08          # py0 low enough that the thinnest piece is >= 0.05 thick

    def plate_y(drop):
        """(centre y, thickness) of a plate piece whose top is `drop` below py1"""
        return (py0 + py1 - drop) / 2, py1 - drop - py0

    pz0 = Z_FRONT + 0.45
    pyc, pth = plate_y(0.0)
    m.block("PlateFront", (0, pyc, (pz0 + CURVE_C[1]) / 2), (6 - 2 * inset, pth, CURVE_C[1] - pz0), GOLD, "Metal", collide=False)
    m.block("PlateBass", (1.5 - inset / 2, pyc, (CURVE_C[1] + TAIL_C[1]) / 2), (3 - inset, pth, TAIL_C[1] - CURVE_C[1]), GOLD, "Metal",
            collide=False)
    vdisc(m, "PlateCurve", CURVE_C[0], CURVE_C[1], py0, py1 - 0.06, (CURVE_R - inset) * 2, GOLD, "Metal", collide=False, smooth=False)
    vdisc(m, "PlateTail", TAIL_C[0], TAIL_C[1], py0, py1 - 0.04, (TAIL_R - inset) * 2, GOLD, "Metal", collide=False, smooth=False)
    (bcx, bcz), blen, byaw, bn = bridge(-inset, 0.5)
    pyc, pth = plate_y(0.02)
    m.block("PlateBridge", (bcx, pyc, bcz), (blen, pth, 0.5), GOLD, "Metal", rot=(0, byaw, 0), collide=False)
    # sound holes: dark discs through the plate, topping out 0.02 above the highest piece under them
    # (hole 1 sits on PlateCurve only, hole 2 on PlateBass)
    for i, (hx, hz, d, top) in enumerate(((-1.25, 2.75, 0.75, py1 - 0.04), (1.2, 3.95, 0.62, py1 + 0.02))):
        vdisc(m, "PlateHole%d" % (i + 1), hx, hz, py0 + 0.01, top, d, HOLE, "Wood", collide=False, smooth=False)

    def plate_back(x):
        """how far back (z) the plate reaches at x (columns, bass block, bridge line)"""
        zs = []
        for (cx, cz), r in ((CURVE_C, CURVE_R - inset), (TAIL_C, TAIL_R - inset)):
            if abs(x - cx) < r:
                zs.append(cz + math.sqrt(r * r - (x - cx) ** 2))
        if 0 <= x <= 3 - inset:
            zs.append(TAIL_C[1])
        return max(zs)

    z_str0 = -0.55                                    # starts 0.05 inside the pin block (no shared end face)
    for i, x in enumerate((2.25, 1.35, 0.45, -0.45, -1.35, -2.25)):
        z1 = plate_back(x) - 0.35
        m.block("String%d" % (i + 1), (x, py1 + 0.03, (z_str0 + z1) / 2), (0.1, 0.05, z1 - z_str0), STRING, "Metal", collide=False)
    m.block("PinBlock", (0, py1 + 0.03, -0.8), (5.3, 0.1, 0.6), WOOD, "Wood", collide=False)
    m.block("Dampers", (0, py1 + 0.1, 0.15), (5.1, 0.22, 0.34), FELT, "Fabric", collide=False)

    # ------------------------------------------------ music desk with a sheet of music (narrow + low: it clears the open lid)
    tilt = 15
    desk_w, desk_h, desk_t = 2.7, 0.8, 0.1
    b = (0.0, py1 + 0.1, -1.05)                           # desk bottom-front edge
    up = (0.0, math.cos(math.radians(tilt)), math.sin(math.radians(tilt)))
    nrm = (0.0, math.sin(math.radians(tilt)), -math.cos(math.radians(tilt)))   # front face normal (toward the pianist)
    centre = (0.0, b[1] + up[1] * desk_h / 2 - nrm[1] * desk_t / 2, b[2] + up[2] * desk_h / 2 - nrm[2] * desk_t / 2)
    m.block("MusicDesk", centre, (desk_w, desk_h, desk_t), BLACK, rot=(tilt, 0, 0), **gl)
    m.block("DeskLedge", (0, b[1] + 0.03, b[2] - 0.1), (desk_w, 0.1, 0.26), BLACK, **gl)
    lift = desk_t / 2 + 0.015
    sheet_c = (0.0, centre[1] + nrm[1] * lift + up[1] * 0.06, centre[2] + nrm[2] * lift + up[2] * 0.06)
    m.block("SheetMusic", sheet_c, (1.5, 0.66, 0.05), CREAM, rot=(tilt, 0, 0), collide=False)
    for k, off in enumerate((0.14, -0.1)):
        c = (0.0, sheet_c[1] + nrm[1] * 0.03 + up[1] * off, sheet_c[2] + nrm[2] * 0.03 + up[2] * off)
        m.block("SheetStaff%d" % (k + 1), c, (1.3, 0.06, 0.05), INK, rot=(tilt, 0, 0), collide=False)

    # ------------------------------------------------ keyboard: keybed, key slip, rounded cheeks, nameboard, white + black keys
    kz0, kz1 = -2.8, Z_FRONT + 0.05                      # keybed front / back (into the case)
    kb_y1 = KEYBED_Y0 + 0.45
    m.block("Keybed", (0, (KEYBED_Y0 + kb_y1) / 2, (kz0 + kz1) / 2), (6, kb_y1 - KEYBED_Y0, kz1 - kz0), BLACK, **gl)
    m.block("KeySlip", (0, WHITE_Y0 + 0.1, -2.71), (2 * KEYS_X, 0.2, 0.14), BLACK, **gl)
    m.block("KeyPinstripe", (0, KEYBED_Y0 + 0.18, kz0 - 0.015), (6.02, 0.06, 0.05), GOLD, "Metal", collide=False)
    cheek_y0, cheek_y1 = WHITE_Y0 - 0.03, WHITE_TOP + 0.22
    cheek_y = (cheek_y0 + cheek_y1) / 2
    for side, name in ((1, "CheekL"), (-1, "CheekR")):
        x = side * (KEYS_X + 0.15)
        m.block(name, (x, cheek_y, (-2.53 + kz1) / 2), (0.3, cheek_y1 - cheek_y0, kz1 + 2.53), BLACK, **gl)
        m.cylx(name + "Nose", (x, cheek_y, -2.53), 0.3, cheek_y1 - cheek_y0, BLACK, **gl)
    m.block("WhiteKeys", (0, (WHITE_Y0 + WHITE_TOP) / 2, (KEY_Z0 + Z_FRONT) / 2), (2 * KEYS_X, WHITE_TOP - WHITE_Y0, Z_FRONT - KEY_Z0),
            IVORY)
    m.block("Nameboard", (0, WHITE_TOP + 0.21, Z_FRONT - 0.03), (2 * KEYS_X, 0.46, 0.2), BLACK, **gl)
    m.block("NameLogo", (0, WHITE_TOP + 0.24, Z_FRONT - 0.145), (0.8, 0.1, 0.05), GOLD, "Metal", collide=False)
    w = 2 * KEYS_X / 21
    n = 0
    for octave in range(3):
        for step in (0, 1, 3, 4, 5):                     # a black key after C, D, F, G, A
            i = octave * 7 + step
            x = KEYS_X - (i + 1) * w                      # low notes on the pianist's left (+X)
            n += 1
            m.block("BlackKey%02d" % n, (x, WHITE_TOP + 0.08, -1.84), (0.15, 0.2, 0.66), BLACK_K, collide=False)

    # ------------------------------------------------ legs (round, gold cuffs) + pedal lyre
    for i, (lx, lz) in enumerate(((2.45, -1.05), (-2.45, -1.05), (1.55, 4.45))):
        m.block("LegCap%d" % (i + 1), (lx, CASE_Y0 - 0.15, lz), (0.82, 0.34, 0.82), BLACK, **gl)
        vdisc(m, "Leg%d" % (i + 1), lx, lz, 0.26, CASE_Y0 - 0.29, 0.52, BLACK, **gl)
        vdisc(m, "LegCuff%d" % (i + 1), lx, lz, 0.0, 0.3, 0.62, GOLD, "Metal")
    post_y0 = 0.74
    for side in (1, -1):
        m.block("LyrePost%s" % ("L" if side > 0 else "R"), (side * 0.42, (post_y0 + CASE_Y0 + 0.02) / 2, -0.95),
                (0.16, CASE_Y0 + 0.02 - post_y0, 0.16), BLACK, **gl)
    m.block("PedalBox", (0, 0.58, -0.95), (1.3, 0.36, 0.5), BLACK, **gl)
    for k, x in enumerate((0.36, 0.0, -0.36)):
        m.block("Pedal%d" % (k + 1), (x, 0.5, -1.42), (0.15, 0.08, 0.5), GOLD, "Metal", collide=False)

    # ------------------------------------------------ lid (the case outline, propped open) + prop stick
    lt = 0.12
    ly = CASE_Y1 + lt / 2
    lrot = (0, 0, -LID_DEG)
    drot = (0, 0, 90 - LID_DEG)
    m.block("LidFront", lid_place(0, ly, (Z_FRONT + CURVE_C[1]) / 2), (6, lt, CURVE_C[1] - Z_FRONT), BLACK, rot=lrot, **gl)
    m.block("LidBass", lid_place(1.5, ly, (CURVE_C[1] + TAIL_C[1]) / 2), (3, lt, TAIL_C[1] - CURVE_C[1]), BLACK, rot=lrot, **gl)
    m.cylx("LidCurve", lid_place(CURVE_C[0], ly, CURVE_C[1]), lt, CURVE_R * 2, BLACK, rot=drot, smooth=False, **gl)
    m.cylx("LidTail", lid_place(TAIL_C[0], ly, TAIL_C[1]), lt, TAIL_R * 2, BLACK, rot=drot, smooth=False, **gl)
    (bcx, bcz), blen, byaw, _ = bridge(0.0, 0.7)
    m.block("LidBridge", lid_place(bcx, ly, bcz), (blen, lt, 0.7), BLACK, rot=P.angles(0, 0, -LID_DEG) @ P.angles(0, byaw, 0), **gl)
    stick_bot = (-2.35, py1, 1.2)
    stick_top = lid_place(-2.7, CASE_Y1 + 0.03, 1.2)
    m.cyl("LidStick", stick_bot, stick_top, 0.14, BLACK, collide=False, **gl)

    # ------------------------------------------------ bench (black, red tufted leather top, gold feet)
    bz = BENCH_Z
    m.block("BenchTop", (0, 1.9, bz), (2.9, 0.16, 1.4), BLACK, **gl)
    m.block("BenchApron", (0, 1.68, bz), (2.66, 0.3, 1.16), BLACK, **gl)
    m.block("BenchCushion", (0, (1.96 + BENCH_TOP) / 2, bz), (2.74, BENCH_TOP - 1.96, 1.26), RED, "Leather")
    for k, x in enumerate((0.75, 0.0, -0.75)):
        m.ball("BenchTuft%d" % (k + 1), (x, BENCH_TOP, bz), 0.12, GOLD, "Metal", collide=False)
    for i, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        x, z = sx * 1.22, bz + sz * 0.5
        vdisc(m, "BenchLeg%d" % (i + 1), x, z, 0.16, 1.6, 0.28, BLACK, **gl)
        vdisc(m, "BenchFoot%d" % (i + 1), x, z, 0.0, 0.2, 0.34, GOLD, "Metal")

    # ------------------------------------------------ data for the behaviour
    m.pivot("Bench", (0, BENCH_TOP, bz))                  # top of the bench cushion: the seat sits here, facing +Z (the keys)
    m.pivot("Keys", (0, WHITE_TOP, (KEY_Z0 + Z_FRONT) / 2))  # keyboard centre, top
    m.pivot("Sound", (-0.3, CASE_Y1, 1.6))                # the notes sound from inside the case
    m.pivot("Notes", (-0.7, CASE_Y1 + 0.35, 1.9))         # music-note billboards rise from here (under the open lid)
    m.attr("Cost", 2500)
    m.attr("Notes", "Glossy black grand piano (lid propped open, gold harp plate, strings, dampers, 3 gold pedals) "
                    "with a matching red-tufted bench, primlib parts. Keyboard faces -Z. Pivot_Bench = bench cushion "
                    "top (seat faces +Z toward the keys), Pivot_Keys = keyboard centre, Pivot_Sound = inside the case, "
                    "Pivot_Notes = where floating notes start. Built by fun-builds/models/build_Piano.py.")
    return m.finish()
