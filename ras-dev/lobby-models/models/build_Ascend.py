"""Ascend - heaven's gate. Marble steps rise out of a cloud bank to a dais; two fluted marble columns with gold ionic
capitals carry a lintel with big gold ASCEND letters on a slate-navy plaque (the set's sign board); a glowing sky
portal (a mid-blue Neon core in an ice frame, saturated enough that lobby Bloom keeps it blue) fills the arch with
stacked golden up-chevrons mounted on the pane; big layered angel wings (white coverts -> ice mid row -> sky-blue
flight tips that stay darker than the Frostpeak sky, shingled so every feather casts a line on its neighbour) cup
forward behind the gate; a golden halo floats on top.

Colours follow the set judge's shared palette (2026-09-24 final round): gold ffad2b, gold_neon ffa82e, slate navy
2c3a55, royal 2f5fbf, ice 9fd3ff, frost c4e8ff, marble f3f5fa, white ffffff. lobbylib.PALETTE still holds the older
lemon golds, so this file names its colours itself."""
import math
import bpy
from mathutils import Matrix, Vector


def _bez2(p0, p1, p2, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])


def _catmull(pts, t):
    """Uniform Catmull-Rom through pts, t in [0, 1]."""
    n = len(pts) - 1
    f = min(max(t, 0.0), 1.0) * n
    i = min(int(f), n - 1)
    u = f - i
    p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, n)]
    out = []
    for k in range(2):
        a, b, c, d = p0[k], p1[k], p2[k], p3[k]
        out.append(0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (-a + 3 * b - 3 * c + d) * u ** 3))
    return tuple(out)


FEATHER_T = [0.0, 0.18, 0.4, 0.58, 0.72, 0.8, 0.9, 0.97, 1.0]     # flight feathers (split white / sky tip at 0.72)
MID_T = [0.0, 0.3, 0.55, 0.72, 0.8, 0.88, 0.94, 0.98, 1.0]        # middle row (split white / ice tip at 0.72)
COV_T = [0.0, 0.3, 0.6, 0.8, 0.92, 1.0]                          # short rounded coverts


def _hw(t, W, base=0.4):
    """Feather half-width along its length: narrow quill end, full belly, rounded tip."""
    if t <= 0.5:
        return W / 2 * (base + (1 - base) * math.sin(math.pi / 2 * t / 0.5))
    u = (t - 0.5) / 0.5
    return W / 2 * max(0.0, 1 - u ** 2.2) ** 0.55


WING_ARM = ((1.9, 13.9), (3.5, 17.7), (8.2, 18.2))           # quadratic Bezier: root (on the cornice), control, top
WING_EDGE = [(2.0, 6.6), (4.2, 6.4), (6.7, 7.4), (8.8, 9.5), (9.9, 12.4), (10.15, 15.3), (9.8, 17.6)]


def _feather_outline(length, W, ta=0.0, tb=1.0, bend=0.0, base=0.4, samples=None):
    ts = sorted(set([ta, tb] + [t for t in (samples or FEATHER_T) if ta < t < tb]))
    top = [(t * length, _hw(t, W, base) + bend * t * t) for t in ts]
    bot = [(t * length, -_hw(t, W, base) + bend * t * t) for t in ts]
    if _hw(tb, W, base) < 1e-4:
        bot = bot[:-1]
    return top + list(reversed(bot))


def _oval_tube(b, points, ay, az, segs=12):
    """Tube along a polyline with an OVAL cross-section: semi-axis ay[i] toward world Y (front/back, so it can cap
    the whole layered feather stack from both sides), az[i] in the wing plane (the width seen from the front)."""
    pts = [Vector(p) for p in points]
    rings = []
    Y = Vector((0.0, 1.0, 0.0))
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n1 = (Y - d * Y.dot(d)).normalized()
        n2 = d.cross(n1).normalized()
        rings.append([b.verts.new(p + n1 * (ay[i] * math.cos(2 * math.pi * j / segs))
                                  + n2 * (az[i] * math.sin(2 * math.pi * j / segs))) for j in range(segs)])
    for i in range(len(rings) - 1):
        for j in range(segs):
            b.faces.new((rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    b.faces.new(tuple(reversed(rings[0])))
    b.faces.new(tuple(rings[-1]))


def build(L):
    # the set judge's shared palette (mandatory for the matching roles)
    P = dict(L.PALETTE)
    P.update({"gold": "ffad2b", "gold_dark": "d4861e", "gold_neon": "ffa82e", "white": "ffffff", "snow": "f4f8fc",
              "marble": "f3f5fa", "slate_navy": "2c3a55", "slate_light": "3b4a66", "royal_blue": "2f5fbf",
              "ice": "9fd3ff", "frost": "c4e8ff"})
    m = L.Model("Ascend", kept=["Ascend_05_Wings"])

    MARBLE = P["marble"]
    GOLD = P["gold"]                 # the lobby's blue ambient + sun pull a warm gold toward yellow: author it warm
    NAVY = P["slate_navy"]           # sign boards (plaque + crest): the same board as SHOP / LIKE / JOIN
    ROYAL = P["royal_blue"]          # the runner
    CLOUD = P["white"]
    CLOUD_LO = "8fbbe8"              # cloud skirt: a visible blue underline on snow and on the white AscendCircle ring
    ICE = P["ice"]
    SKY = "3f82e2"                   # flight-feather tips: darker than the Frostpeak sky (4eb0de) lit or shaded
    PORTAL = "3d9bff"                # Neon core: red ~60 cannot bloom to white, so the doorway stays ice-blue

    # ------------------------------------------------------------------ dais + steps
    DZ = 1.88                     # walking surface of the dais
    m.box("DaisBody", (-5.95, -2.9, 0.0), (5.95, 1.5, 1.56), MARBLE, "Marble", bevel=0.16, mesh="Steps")
    m.box("DaisRim", (-6.08, -3.03, 1.5), (6.08, 1.63, 1.83), GOLD, bevel=0.1, mesh="GoldTrim")
    m.box("DaisTop", (-5.78, -2.73, 1.6), (5.78, 1.33, DZ), MARBLE, "Marble", bevel=0.08, mesh="Steps")
    for i, (top, front, hw) in enumerate(((0.63, 4.3, 4.5), (1.26, 2.9, 4.1))):
        m.box("Step%d" % i, (-hw, front - 1.6, 0.0), (hw, front, top), MARBLE, "Marble", bevel=0.12, mesh="Steps")
        m.box("Nose%d" % i, (-hw - 0.06, front - 0.34, top - 0.26), (hw + 0.06, front + 0.07, top + 0.05), GOLD,
              bevel=0.08, mesh="GoldTrim")

    # royal-blue runner up the steps to the portal (rides 0.05 over the treads + nosing, closes inside the steps)
    runner = [(4.42, 0.0), (4.42, 0.73), (3.02, 0.73), (3.02, 1.36), (1.70, 1.36), (1.70, 1.95), (-0.3, 1.95),
              (-0.3, 1.8), (1.6, 1.8), (1.6, 1.2), (2.85, 1.2), (2.85, 0.58), (4.25, 0.58), (4.25, 0.0)]
    YZX = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))    # outline (y, z), extrude along x
    m.prism("Runner", runner, -1.28, 1.28, ROYAL, "Fabric", matrix=YZX, bevel=0.03, mesh="Carpet")
    for s in (1, -1):                           # gold edging along both sides of the runner
        m.prism("RunnerEdge%d" % (s > 0), runner, min(s * 1.28, s * 1.62), max(s * 1.28, s * 1.62), GOLD,
                matrix=YZX, bevel=0.03, mesh="GoldTrim")

    # ------------------------------------------------------------------ columns
    # walk-surface gold (plinths, tori, dais rim, nosing, runner edging) collides; high decorative gold does not
    DECO = dict(mesh="GoldDeco", collide=False)
    CX, CY, R = 3.6, -0.5, 0.82
    flute = [(R * (1 - 0.1 * (0.5 - 0.5 * math.cos(12 * a))) * math.cos(a),
              R * (1 - 0.1 * (0.5 - 0.5 * math.cos(12 * a))) * math.sin(a))
             for a in (2 * math.pi * i / 48 for i in range(48))]
    for s in (1, -1):
        x = s * CX
        tag = "L" if s > 0 else "R"
        m.box("Plinth" + tag, (x - 1.05, CY - 1.05, DZ - 0.02), (x + 1.05, CY + 1.05, DZ + 0.36), GOLD, bevel=0.1,
              mesh="GoldTrim")
        m.lathe("Torus" + tag, [(0, DZ + 0.34), (0.98, DZ + 0.34), (1.03, DZ + 0.52), (0.95, DZ + 0.68),
                                (0.84, DZ + 0.72), (0, DZ + 0.72)], GOLD, matrix=L.xf((x, CY, 0)), mesh="GoldTrim")
        m.prism("Shaft" + tag, flute, DZ + 0.7, 10.36, MARBLE, "Marble", matrix=L.xf((x, CY, 0)), mesh="Columns")
        m.lathe("Cap" + tag, [(0, 10.32), (0.84, 10.32), (0.9, 10.46), (1.08, 10.68), (1.13, 10.8), (0, 10.8)],
                GOLD, matrix=L.xf((x, CY, 0)), **DECO)
        m.box("Abacus" + tag, (x - 1.2, CY - 1.2, 10.78), (x + 1.2, CY + 1.2, 11.22), GOLD, bevel=0.1, **DECO)
        for k, dx in enumerate((-0.84, 0.84)):  # ionic volutes: a bolster (cushion) with a scroll disc + raised eye
            vx, vz = x + dx, 10.5               # on each face, so they read as scrolls from the front and the side
            m.cyl("Bolster%s%d" % (tag, k), (vx, CY - 1.08, vz + 0.02), (vx, CY + 1.08, vz + 0.02), 0.34, GOLD, segs=12,
                  **DECO)
            for sy, tg in ((1, "F"), (-1, "B")):
                m.cyl("Scroll%s%s%d" % (tag, tg, k), (vx, CY + sy * 1.04, vz), (vx, CY + sy * 1.24, vz), 0.42, GOLD,
                      segs=16, smooth=False, **DECO)
                m.cyl("Eye%s%s%d" % (tag, tg, k), (vx, CY + sy * 1.2, vz), (vx, CY + sy * 1.34, vz), 0.18, GOLD,
                      segs=10, smooth=False, **DECO)

    # ------------------------------------------------------------------ arch spandrels + portal
    ZS, RA = 8.2, 2.8
    arch = [(3.0, ZS), (3.0, 11.22), (-3.0, 11.22), (-3.0, ZS)] + \
        [(RA * math.cos(math.radians(a)), ZS + RA * math.sin(math.radians(a))) for a in range(180, -1, -10)]
    m.prism("Spandrel", arch, 0.0, 1.0, MARBLE, "Marble", matrix=L.xf((0, CY + 0.5, 0), rx=90), mesh="Lintel")
    m.tube("ArchMould", [(RA * math.cos(math.radians(a)), CY + 0.52, ZS + RA * math.sin(math.radians(a)))
                         for a in range(180, -1, -10)], [0.2] * 19, GOLD, segs=10, **DECO)
    for s in (1, -1):                           # gold imposts: the arch springs from a block on each column, so
        m.box("Impost%s" % ("L" if s > 0 else "R"),  # the mould's ends are buried instead of hanging in the air
              (min(s * 2.45, s * 3.2), CY - 0.1, 7.85), (max(s * 2.45, s * 3.2), CY + 0.75, 8.25), GOLD, bevel=0.08,
              **DECO)
    # the portal: an ice frame pane (plastic) with a smaller glowing Neon core inset 0.5 from the arch/columns.
    # The core is a MID blue (red ~60) at low transparency: lobby Bloom cannot push it to white, so the doorway reads
    # as a blue glow behind the gold chevrons; light sources cast no shadows
    m.box("PortalFrame", (-2.95, CY - 0.05, DZ + 0.02), (2.95, CY + 0.05, 11.0), ICE, bevel=0.0,
          collide=False, shadow=False, mesh="Portal")
    RI = RA - 0.5
    core = [(RI, DZ + 0.4)] + [(RI * math.cos(math.radians(a)), ZS + RI * math.sin(math.radians(a)))
                               for a in range(0, 181, 10)] + [(-RI, DZ + 0.4)]
    m.prism("PortalCore", core, -0.09, 0.09, PORTAL, "Neon", matrix=L.xf((0, CY, 0), rx=90), transparency=0.15,
            collide=False, shadow=False, mesh="Portal")

    # stacked golden chevrons pointing up, growing toward the top (the lead arrow), on both faces of the pane:
    # 0.4 thick, centred 0.28 off the pane, so each back face sinks 0.01 into the core's skin (mounted, not floating)
    for i, (z, w, dp, th) in enumerate(((3.25, 2.8, 1.5, 0.66), (5.15, 3.1, 1.68, 0.72), (7.15, 3.55, 1.95, 0.8))):
        pts = L.D.chevron_pts(w, dp, th, tip_at=+1)
        for sy, tg in ((1, ""), (-1, "B")):
            m.prism("Chev%s%d" % (tg, i), pts, -0.2, 0.2, GOLD, matrix=L.xf((0, CY + sy * 0.28, z), rx=90),
                    bevel=0.08, collide=False, mesh="Arrow")

    # ------------------------------------------------------------------ lintel + plaque + letters + crest
    LY0, LY1 = -1.45, 0.45
    LZ1 = 13.35                                  # lintel top (the plaque is 1.85 tall for big letters)
    m.box("LintelBlock", (-5.2, LY0, 11.2), (5.2, LY1, LZ1), MARBLE, "Marble", bevel=0.15, mesh="Lintel")
    m.box("Plaque", (-4.85, LY1 - 0.1, 11.36), (4.85, LY1 + 0.14, 13.21), NAVY, bevel=0.1, mesh="Plaque")
    m.text("Letters", "ASCEND", size=2.4, depth=0.3, hex=GOLD, loc=(0, LY1 + 0.26, 12.3), collide=False,
           mesh="Letters")
    m.box("Cornice", (-5.5, LY0 - 0.2, LZ1 - 0.02), (5.5, LY1 + 0.2, LZ1 + 0.38), GOLD, bevel=0.1, **DECO)
    m.prism("BackStar", L.star_pts(4, 0.82, 0.32), -0.12, 0.12, GOLD, matrix=L.xf((0, LY0 - 0.08, 12.28), rx=90),
            bevel=0.04, **DECO)                  # a gold emblem where the lintel back shows between the wings
    CR, CZ = 2.35, LZ1 + 0.36
    crest = [(0.0, 0.0)] + [(CR * math.cos(math.radians(a)), CR * math.sin(math.radians(a))) for a in range(0, 181, 10)]
    m.prism("Crest", crest, -0.6, 0.6, NAVY, matrix=L.xf((0, -0.5, CZ), rx=90), mesh="Plaque")
    rim = [((CR + 0.42) * math.cos(math.radians(a)), (CR + 0.42) * math.sin(math.radians(a))) for a in range(0, 181, 10)] + \
          [((CR - 0.05) * math.cos(math.radians(a)), (CR - 0.05) * math.sin(math.radians(a))) for a in range(180, -1, -10)]
    m.prism("CrestRim", rim, -0.72, 0.72, GOLD, matrix=L.xf((0, -0.5, CZ), rx=90), bevel=0.06, **DECO)
    # sunrise on both faces of the crest
    for side, (z0, z1) in (("F", (-0.78, -0.56)), ("B", (0.56, 0.78))):
        sun = [(0.82 * math.cos(math.radians(a)), 0.82 * math.sin(math.radians(a))) for a in range(0, 181, 15)]
        m.prism("Sun" + side, sun, z0, z1, GOLD, matrix=L.xf((0, -0.5, CZ - 0.02), rx=90), bevel=0.05, **DECO)
        for k, a in enumerate((25, 57, 90, 123, 155)):
            ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
            r1, r2, w1, w2 = 1.05, 2.02, 0.14, 0.28
            ray = [(r1 * ca + w1 * sa, r1 * sa - w1 * ca), (r2 * ca + w2 * sa, r2 * sa - w2 * ca),
                   (r2 * ca - w2 * sa, r2 * sa + w2 * ca), (r1 * ca - w1 * sa, r1 * sa + w1 * ca)]
            m.prism("Ray%s%d" % (side, k), ray, z0, z1, GOLD, matrix=L.xf((0, -0.5, CZ + 0.02), rx=90), bevel=0.05,
                    **DECO)

    # halo + twinkles (glow decor: no collision, no shadows; one "Halo" mesh)
    GLOW = dict(mesh="Halo", collide=False, shadow=False)
    m.torus("Halo", (0, -0.5, 18.05), 1.45, 0.27, P["gold_neon"], "Neon", rot=L.xf(rx=35), seg_major=28, seg_minor=8,
            **GLOW)
    for k, (x, y, z, r, rz) in enumerate(((2.35, -0.3, 18.45, 0.55, 8), (-2.5, -0.3, 17.45, 0.42, -10),
                                          (6.9, 0.9, 4.9, 0.62, 12), (-7.1, 0.7, 6.0, 0.5, -6))):
        m.prism("Twinkle%d" % k, L.star_pts(4, r, r * 0.34), -0.1, 0.1, P["gold_neon"], "Neon",
                matrix=L.xf((x, y, z), rx=90, ry=rz), bevel=0.03, **GLOW)

    # ------------------------------------------------------------------ wings
    # Wing plane coordinates (u = outward from the centre line, v = up). C = the golden leading edge (the TOP of the
    # wing), E = the trailing edge where the flight-feather tips land. Feathers run from C(t) toward E(t).
    # Depth: the plane sweeps back 9 deg and cups FORWARD in its outer half (a shallow C from the side).
    P0, P1, P2 = WING_ARM
    EDGE = WING_EDGE
    YW = -2.1
    TS = math.tan(math.radians(9))
    CUP, CUP_U = 0.085, 4.5                     # forward cup of the outer half (tips ~0.9 in front of the root)

    def wy(u, base_y):
        return base_y - (u - 2.0) * TS + CUP * max(0.0, u - CUP_U) ** 2

    def secant(u0, u1):
        if abs(u1 - u0) < 0.4:
            um = (u0 + u1) / 2
            return -TS + 2 * CUP * max(0.0, um - CUP_U)
        return (wy(u1, 0.0) - wy(u0, 0.0)) / (u1 - u0)

    def A(t):                                   # the arm's depth offset (it recedes a little toward the tip)
        return YW + 0.25 - 0.35 * t

    def feather(name, s, b, tip, width, y0, y1, label, hexc, ta=0.0, tb=1.0, bend=0.35, base=0.4, twist=0.0,
                thick=0.24, samples=None):
        """y0 = depth offset at the quill end, y1 = at the full-length tip (pitch: tucked base, lifted tip)."""
        du, dv = tip[0] - b[0], tip[1] - b[1]
        length = math.hypot(du, dv)
        ang = math.atan2(dv, du)                         # in the (outward, up) plane
        world_ang = math.degrees(math.atan2(math.sin(ang), s * math.cos(ang)))
        pts = _feather_outline(length, width, ta, tb, bend=s * bend, base=base, samples=samples)
        rz = s * math.degrees(math.atan(secant(b[0], tip[0])))    # follow the cupped wing surface
        pitch = math.asin(max(-0.5, min(0.5, (y1 - y0) / length)))
        M = L.xf((s * b[0], wy(b[0], y0), b[1]), rz=rz, ry=-world_ang, rx=90 + twist) @ Matrix.Rotation(pitch, 4, 'Y')
        m.prism(name, pts, -thick / 2, thick / 2, hexc, "SmoothPlastic", matrix=M, bevel=0.07, collide=False,
                mesh=label)

    def C(t):
        return _bez2(P0, P1, P2, t)

    def Ct(t):                                  # unit tangent of the arm
        a, b = C(max(0.0, t - 0.01)), C(min(1.0, t + 0.01))
        d = (b[0] - a[0], b[1] - a[1])
        ln = math.hypot(*d)
        return (d[0] / ln, d[1] / ln)

    def E(t):
        return _catmull(EDGE, t)

    def span(t, frac, width, back=-0.05):
        """Feather from the arm toward the trailing edge; its base is pushed below the arm by the part of its
        half-width that would otherwise poke above the leading edge (x1.15, so every base starts under the tube)."""
        c, e = C(t), E(t)
        tg = Ct(t)
        nrm = (tg[1], -tg[0])                   # arm normal on the trailing side
        d = (e[0] - c[0], e[1] - c[1])
        ln = math.hypot(*d)
        dn = (d[0] / ln, d[1] / ln)
        push = 0.5 * width * abs(dn[0] * tg[0] + dn[1] * tg[1]) * 1.15
        c2 = (c[0] + nrm[0] * push, c[1] + nrm[1] * push)
        d = (e[0] - c2[0], e[1] - c2[1])
        ln = math.hypot(*d)
        b = (c2[0] - d[0] / ln * back, c2[1] - d[1] / ln * back)
        return b, (c2[0] + d[0] * frac, c2[1] + d[1] * frac)

    WHITE = P["white"]
    for s in (1, -1):
        tag = "L" if s > 0 else "R"
        # every row is shingled: the edge toward the next (outer) feather is lifted toward the viewer, so each
        # feather throws a line on its neighbour whatever the sun does
        # The wrist (top-outer corner, under the ArmEnd ball) is where the forward cup turns the last feathers of
        # each row edge-on; there they read as a comb of slivers in the engine. So the feather that runs along the
        # arm (flight i = N-1), the last middle-row feather and the last front covert are left out, and the two
        # remaining wrist flight feathers lie flat (no twist): the corner closes cleanly under the ball.
        N = 11
        for i in range(N):                      # flight feathers: white body + sky-blue tip
            if i == N - 1:
                continue
            t = i / (N - 1)
            wd = (2.0, 1.8, 1.6)[max(0, i - (N - 3))]    # the wrist feathers run along the arm: narrower + unbent
            bend = 0.35 if i < N - 2 else 0.0          # so they stay under the ball tip
            tw = 0.0 if i >= N - 3 else -s * 9
            b, e = span(t, 1.0, wd)
            y = A(t) - 0.25
            feather("Fly%s%d" % (tag, i), s, b, e, wd, y, y, "Ascend_05_Wings", WHITE, tb=0.72, twist=tw,
                    bend=bend)
            feather("Tip%s%d" % (tag, i), s, b, e, wd, y, y, "WingTips", SKY, ta=0.72, twist=tw, bend=bend)
        for i in range(N - 2):                  # middle row: white body + ice tip (white -> ice -> sky bands)
            if i == N - 3:
                continue
            t = (i + 0.5) / (N - 2)
            b, e = span(t, 0.62, 1.8)
            y0, y1 = A(t) + 0.02, A(t) + 0.34
            feather("Mid%s%d" % (tag, i), s, b, e, 1.8, y0, y1, "Ascend_05_Wings", WHITE, tb=0.72, twist=-s * 7,
                    samples=MID_T)
            feather("MidTip%s%d" % (tag, i), s, b, e, 1.8, y0, y1, "WingTipsMid", ICE, ta=0.72, twist=-s * 7,
                    samples=MID_T)
        for i in range(8):                      # coverts (front face)
            if i == 7:
                continue
            t = (i + 0.5) / 8
            b, e = span(t, 0.33, 1.55)
            feather("Cov%s%d" % (tag, i), s, b, e, 1.55, A(t) + 0.22, A(t) + 0.68, "Ascend_05_Wings", WHITE,
                    base=0.55, twist=-s * 6, samples=COV_T)
        for i in range(8):                      # back coverts: the back face gets its own short rounded row
            t = (i + 0.5) / 8
            b, e = span(t, 0.3, 1.5)
            feather("Back%s%d" % (tag, i), s, b, e, 1.5, A(t) - 0.42, A(t) - 0.8, "WingBack", WHITE,
                    base=0.55, twist=-s * 6, samples=COV_T, tb=0.7)
            feather("BackTip%s%d" % (tag, i), s, b, e, 1.5, A(t) - 0.42, A(t) - 0.8, "WingTipsMid", ICE,
                    base=0.55, twist=-s * 6, samples=COV_T, ta=0.7)
        # golden leading edge: an oval tube centred ON the feather stack (caps the quill ends from front and back),
        # rising from a gold collar that sits on the back edge of the cornice
        ts = [0.0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
        arm, ay, az = [], [], []
        for t in ts:
            c = C(t)
            arm.append((s * c[0], wy(c[0], A(t)), c[1]))
            ay.append(min(0.5 + 0.4 * t, 0.62 - 0.14 * t))     # slimmer in depth where it passes behind the crest
            az.append(0.44 - 0.1 * t)
        tg = Ct(1.0)                            # run the tube a little past the wrist so the ball caps it
        ue, ve = P2[0] + 0.35 * tg[0], P2[1] + 0.35 * tg[1]
        arm.append((s * ue, wy(ue, A(1.0)), ve))
        ay.append(ay[-1])
        az.append(az[-1])
        m.custom("Arm" + tag, lambda bb, arm=arm, ay=ay, az=az: _oval_tube(bb, arm, ay, az, segs=12), GOLD,
                 collide=False, smooth=True, mesh="WingArm")
        m.sphere("Collar" + tag, arm[0], 0.55, GOLD, scale=(1, 0.9, 1), subdiv=2, collide=False, mesh="WingArm")
        m.sphere("ArmEnd" + tag, arm[-1], 0.48, GOLD, scale=(1, 1.1, 1), subdiv=2, collide=False, mesh="WingArm")

    # ------------------------------------------------------------------ clouds
    # a continuous cushion of flattened puffs around the dais on a pale-blue skirt (so the bank never melts into a
    # white snow floor, and never reads as a pile of snowballs)
    ring = [(5.3, 3.2, 1.2), (6.8, 2.1, 1.5), (7.6, 0.3, 1.15), (7.7, -1.6, 1.45), (6.9, -3.0, 1.1), (5.1, -3.45, 1.35),
            (3.0, -3.55, 1.05), (1.0, -3.45, 1.3)]
    PUFF = (1.15, 1.0, 0.62)
    ci = 0
    for s in (1, -1):
        for k, (x, y, r) in enumerate(ring):
            zc = 0.62 * r + 0.14
            m.sphere("Puff%d" % ci, (s * x, y, zc), r, CLOUD, scale=PUFF, subdiv=(3 if k < 4 else 2), collide=False,
                     mesh="Clouds")
            ln = math.hypot(x, y)
            m.sphere("CloudLo%d" % ci, (s * (x + 0.15 * x / ln), y + 0.15 * y / ln, 0.22), 1.7, CLOUD_LO,
                     scale=(1.0, 0.64, 0.28), collide=False, mesh="CloudShade")
            if k + 1 < len(ring):
                x2, y2, _ = ring[k + 1]
                mx, my = (x + x2) / 2, (y + y2) / 2
                ln = math.hypot(mx, my)
                m.sphere("Bit%d" % ci, (s * (mx + 0.45 * mx / ln), my + 0.45 * my / ln, 0.62 * 0.8 + 0.14), 0.8,
                         CLOUD, scale=PUFF, collide=False, mesh="Clouds")
            if k in (1, 3, 5, 7):               # a smaller puff sunk 40 % into the one below
                tr = 0.45 * r
                m.sphere("Top%d" % ci, (s * (x - 0.3), y, zc + 0.62 * r + 0.072 * r), tr, CLOUD,
                         scale=(1.1, 1.0, 0.8), collide=False, mesh="Clouds")
            ci += 1

    # ------------------------------------------------------------------ centre the footprint
    bpy.context.view_layer.update()
    mins, maxs = L.D.bounds("Ascend")
    T = Matrix.Translation((-(mins.x + maxs.x) / 2, -(mins.y + maxs.y) / 2, 0))
    for o in m.objs:
        o.data.transform(T)
        if not o["rbx_shadow"]:
            try:
                o.visible_shadow = False        # render-only: the review renders match CastShadow = false in Studio
            except Exception:
                pass
    # the walk surfaces want a precise collision hull (a coarse decomposition leaves bumps on the treads)
    m.attr("PreciseCollision", ["Steps", "Carpet", "GoldTrim"])
    return m.finish()
