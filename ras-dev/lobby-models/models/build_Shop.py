"""Shop -- a snowy market stall that sells snowballs + launchers (RAS - Dev lobby, 2026-09-24).

Front = +Y (the ring players stand in). +X = the viewer's LEFT.

Launchers are placed where every camera sees them: a big red shovel leaning on the outer face of the left front
post (planted in a snow drift), a slingshot standing in the ice-ball crate at the right end, a small cannon on the
counter, and a blue scoop hung low on the pegboard (below the valance sight line).

Final polish (set judge): shared set palette (gold ffad2b / gold_dark d4861e / neon gold ffa82e twinkles + lantern,
royal-blue scoop), a mid ice-blue pegboard 6f9fd6 with 8 x 4 slate holes so the pale goods separate from it.
NOTE for install: the magenta light at ShopCircle tints this whole stall pink/maroon in-engine - neutralise it there.
"""
import math
from mathutils import Matrix, Vector


def build(L):
    P = L.PALETTE
    m = L.Model("Shop")

    # the set judge's shared palette (all three lobby models use these exact colours for these roles)
    S = {"gold": "ffad2b", "gold_dark": "d4861e", "gold_neon": "ffa82e", "white": "ffffff", "snow": "f4f8fc",
         "marble": "f3f5fa", "slate_navy": "2c3a55", "slate_light": "3b4a66", "royal_blue": "2f5fbf",
         "wood": "9a6238", "wood_light": "c68c52", "wood_dark": "6b4226", "ice": "9fd3ff", "frost": "c4e8ff",
         "red": "e8413c"}
    WOOD, WOOD_L, WOOD_D = S["wood"], S["wood_light"], S["wood_dark"]
    ORANGE, CREAM = P["orange"], "ffe6b8"      # a warmer cream than the palette so it never melts into the snow cap
    GOLD, GOLD_D, GOLD_N = S["gold"], S["gold_dark"], S["gold_neon"]
    SLATE, SLATE_L = S["slate_navy"], S["slate_light"]
    SNOW, ICE = S["snow"], S["ice"]
    WHITE_B, ICE_B, ROCK_B, PINK_B = S["snow"], S["ice"], "a39382", "ff9ecd"   # snowball flavours
    BALL_COLS = [WHITE_B, ICE_B, ROCK_B, PINK_B]
    PEG = S["frost"]           # frost accents (snowflakes, chalk arrow, windows)
    BOARD = "6f9fd6"           # the pegboard: a mid ice-blue, so the white / pink / ice goods separate from it

    def w(M, p):
        return tuple(M @ Vector(p))

    def ball(*a, **kw):
        # Blender 5.x icospheres: subdivisions=3 is the 320-tri sphere (2 is only 80 tris and looks faceted)
        kw.setdefault("subdiv", 3)
        return m.sphere(*a, **kw)

    # ------------------------------------------------------------------ helpers
    def xz_prism(name, pts, y0, y1, hex, mat="SmoothPlastic", bevel=0.0, pre=None, **kw):
        """Outline (x, z) in the vertical plane, extruded along world Y from y0 to y1."""
        M = L.xf((0, y0, 0), rx=90)
        if pre is not None:
            M = pre @ M
        return m.prism(name, pts, -(y1 - y0), 0.0, hex, mat, matrix=M, bevel=bevel, **kw)

    def coin_face(name, c, r, t, hex, mesh="Coins", star_hex=None, star_scale=0.55, facing=1, **kw):
        """A coin standing up, facing +Y (facing=-1: -Y), its back on the plane y = c[1]: raised rim + an
        embossed star."""
        prof = [(0, 0), (r, 0), (r, t * 0.75), (r - 0.07, t), (r - 0.2, t), (r - 0.26, t * 0.66), (0, t * 0.66)]
        m.lathe(name, prof, hex, matrix=L.xf(c, rx=-90 * facing), segs=28, mesh=mesh, **kw)
        if star_hex:
            sp = L.star_pts(5, r * star_scale, r * star_scale * 0.45)
            ya, yb = sorted((c[1] + facing * t * 0.5, c[1] + facing * t * 0.98))
            xz_prism(name + "Star", [(x + c[0], z + c[2]) for (x, z) in sp], ya, yb, star_hex, bevel=0.03, mesh=mesh,
                     **kw)

    def coin_flat(name, c, r, t, hex, mesh="Coins", segs=12, **kw):
        prof = [(0, 0), (r - 0.05, 0), (r, 0.05), (r, t - 0.05), (r - 0.05, t), (0, t)]
        m.lathe(name, prof, hex, matrix=L.xf(c), segs=segs, mesh=mesh, **kw)

    def star_coin(name, c, r, t, hex, star_hex):
        """A thick standing coin (both faces show an embossed star): the post-top crown."""
        m.cyl(name, (c[0], c[1] - t / 2, c[2]), (c[0], c[1] + t / 2, c[2]), r, hex, segs=20, smooth=True,
              mesh="Coins")
        sp = L.star_pts(5, r * 0.62, r * 0.62 * 0.45)
        xz_prism(name + "Star", [(x + c[0], z + c[2]) for (x, z) in sp], c[1] - t / 2 - 0.07, c[1] + t / 2 + 0.07,
                 star_hex, bevel=0.03, mesh="Coins")

    def sparkle(name, c, r, y0, y1):
        # the set's shared twinkle: a mid-saturated neon gold (light neon blooms to white in the lobby)
        xz_prism(name, [(x + c[0], z + c[1]) for (x, z) in L.star_pts(4, r, r * 0.29)], y0, y1, GOLD_N, "Neon",
                 bevel=0.03, mesh="Sparkles", collide=False, shadow=False)

    def drift(name, c, rx, ry, h, rz=0.0):
        """A low snow mound (lathe dome squashed to rx x ry, h tall)."""
        prof = [(0, h), (0.35, h * 0.93), (0.62, h * 0.74), (0.83, h * 0.45), (0.96, h * 0.16), (1.0, 0.0), (0, 0)]
        m.lathe(name, prof, SNOW, "Snow", matrix=L.xf(c, rz=rz, scale=(rx, ry, 1.0)), segs=14, mesh="Drifts")

    # ------------------------------------------------------------------ deck
    DZ = 0.3
    m.box("Deck", (-6.75, -3.15, 0), (6.75, 2.85, DZ), WOOD_D, "WoodPlanks", bevel=0.1, mesh="Deck")

    # ------------------------------------------------------------------ counter
    CX, CY0, CY1, CT, CTOP = 5.95, -0.45, 1.8, 3.1, 3.45
    m.box("CounterBody", (-CX, CY0, DZ - 0.02), (CX, CY1, CT), WOOD, "WoodPlanks", bevel=0.08, mesh="Counter")
    m.box("CounterTop", (-6.1, CY0 - 0.15, CT - 0.01), (6.1, CY1 + 0.32, CTOP), WOOD_L, "Wood", bevel=0.12,
          mesh="CounterTop")
    # front frame: kickboard, top rail, pilasters, two mullions (dark wood)
    m.box("Kick", (-CX + 0.02, CY1 - 0.1, DZ - 0.02), (CX - 0.02, CY1 + 0.14, 0.72), WOOD_D, "Wood", bevel=0.06,
          mesh="Trim")
    m.box("Rail", (-CX + 0.02, CY1 - 0.1, 2.82), (CX - 0.02, CY1 + 0.12, CT - 0.02), WOOD_D, "Wood", bevel=0.05,
          mesh="Trim")
    for sx in (1, -1):
        px0, px1 = sorted((sx * 5.2, sx * 5.95))
        m.box("Pilaster%d" % sx, (px0, CY1 - 0.12, DZ - 0.02), (px1, CY1 + 0.18, CT - 0.02), WOOD_D, "Wood",
              bevel=0.07, mesh="Trim")
        m.box("MidPost%d" % sx, (sx * 1.55 - 0.18, CY1 - 0.1, 0.7), (sx * 1.55 + 0.18, CY1 + 0.1, 2.84), WOOD_D,
              "Wood", bevel=0.05, mesh="Trim")
    # side panels closing the booth (the counter wraps round to the back wall)
    for sx in (1, -1):
        x0, x1 = sorted((sx * 5.55, sx * 5.93))
        m.box("SidePanel%d" % sx, (x0, -2.62, DZ - 0.02), (x1, CY0 + 0.02, CT), WOOD, "WoodPlanks", bevel=0.06,
              mesh="Counter")
        m.box("SideTop%d" % sx, (x0 - 0.1, -2.62, CT - 0.01), (x1 + 0.1, CY0, CTOP - 0.05), WOOD_L, "Wood",
              bevel=0.08, mesh="CounterTop")
    # big gold coin emblem on the counter front, a frosty snowflake on each side panel
    coin_face("Emblem", (0, CY1 - 0.02, 1.77), 1.0, 0.34, GOLD, star_hex=GOLD_D)

    def rot2(pts, ang, off):
        ca_, sa_ = math.cos(ang), math.sin(ang)
        return [(off[0] + x * ca_ - y * sa_, off[1] + x * sa_ + y * ca_) for (x, y) in pts]

    def snowflake(tag, fc, y0, y1, R=0.78, arm_w=0.28, br_len=0.34, br_w=0.22, hub=0.24):
        """A chunky 6-armed snowflake in the vertical plane, from y0 to y1 (symmetric, so it reads from either
        side). Each arm has a pair of branches half-way out."""
        t = y1 - y0
        for k in range(6):
            ang = math.radians(90 + 60 * k)
            arm = L.rounded_rect_pts(R, arm_w, arm_w * 0.46, segs=2, center=(R / 2, 0))
            xz_prism(tag + "Arm%d" % k, rot2(arm, ang, fc), y0, y1, PEG, mesh="Frost")
            tip = (fc[0] + 0.5 * R * math.cos(ang), fc[1] + 0.5 * R * math.sin(ang))
            for side in (1, -1):
                br = L.rounded_rect_pts(br_len, br_w, br_w * 0.45, segs=2, center=(br_len * 0.44, 0))
                xz_prism(tag + "Br%d_%d" % (k, side), rot2(br, ang + side * math.radians(55), tip),
                         y0 + t * 0.06, y1 - t * 0.12, PEG, mesh="Frost")
        xz_prism(tag + "Hub", L.circle_pts(hub, 6, center=fc, phase=math.pi / 6), y0 - t * 0.0, y1 + t * 0.18, PEG,
                 bevel=0.04, mesh="Frost")

    for sx in (1, -1):
        snowflake("Flake%d" % sx, (sx * 3.45, 1.77), CY1 - 0.03, CY1 + 0.13)

    # ------------------------------------------------------------------ awning geometry (needed by posts)
    A = math.radians(16)
    sA, cA, tA = math.sin(A), math.cos(A), math.tan(A)
    YF, ZF, YB = 3.1, 8.6, -2.6
    LEN = (YF - YB) / cA
    MA = Matrix(((1, 0, 0, 0), (0, sA, -cA, YF), (0, cA, sA, ZF), (0, 0, 0, 1)))  # local x, y'=normal, z'=up-slope

    def under_awning(y):
        return ZF + (YF - y) * tA

    # ------------------------------------------------------------------ sign heights (raised clear of the awning snow)
    SB = 10.9             # board bottom
    SZ = 12.25            # letter centre
    SF_TOP, SB_TOP = 13.17, 12.9

    # ------------------------------------------------------------------ posts
    PX, PFY, PBY, PH = 6.25, 2.3, -2.75, 0.3
    POST_TOP = 13.6
    for sx in (1, -1):
        m.box("PostF%d" % sx, (sx * PX - PH, PFY - PH, DZ - 0.02), (sx * PX + PH, PFY + PH, under_awning(PFY) + 0.1),
              WOOD_L, "Wood", bevel=0.09, mesh="Posts")
        m.box("PostB%d" % sx, (sx * PX - PH, PBY - PH, DZ - 0.02), (sx * PX + PH, PBY + PH, POST_TOP), WOOD_L, "Wood",
              bevel=0.09, mesh="Posts")
        m.box("PostFoot%d" % sx, (sx * PX - 0.42, PFY - 0.42, DZ - 0.02), (sx * PX + 0.42, PFY + 0.42, 0.75), WOOD_D,
              "Wood", bevel=0.08, mesh="Trim")
        m.box("PostCap%d" % sx, (sx * PX - 0.4, PBY - 0.4, POST_TOP - 0.05), (sx * PX + 0.4, PBY + 0.4, POST_TOP + 0.2),
              WOOD_D, "Wood", bevel=0.07, mesh="Trim")
        # crown: a chunky standing gold star coin on a short stem
        m.cyl("FinialStem%d" % sx, (sx * PX, PBY, POST_TOP + 0.15), (sx * PX, PBY, POST_TOP + 0.45), 0.2, GOLD_D,
              segs=10, mesh="Coins")
        star_coin("Finial%d" % sx, (sx * PX, PBY, POST_TOP + 0.2 + 0.56), 0.56, 0.26, GOLD, GOLD_D)
        # knee brace under the awning's back corner (the overhang past the back post reads as intentional)
        zu = under_awning(PBY + 0.25)
        tri = [(sx * (PX + PH - 0.02), zu - 1.05), (sx * (PX + PH - 0.02), zu + 0.02), (sx * (PX + PH + 0.72), zu + 0.02)]
        xz_prism("CornerBrace%d" % sx, tri, PBY + 0.12, PBY + 0.36, WOOD_D, "Wood", bevel=0.03, mesh="Trim")

    # ------------------------------------------------------------------ back wall + pegboard
    m.box("BackWall", (-5.98, -2.95, DZ - 0.02), (5.98, -2.6, SB + 0.2), WOOD, "WoodPlanks", bevel=0.06,
          mesh="Counter")
    for i, bx in enumerate((-3.4, 3.4)):
        m.box("Batten%d" % i, (bx - 0.2, -3.1, 0.5), (bx + 0.2, -2.9, 10.2), WOOD_D, "Wood", bevel=0.06, mesh="Trim")
    for sx in (1, -1):
        x0, x1 = sorted((sx * 1.3, sx * 5.9))
        m.box("BackRail%d" % sx, (x0, -3.12, 4.2), (x1, -2.9, 4.55), WOOD_D, "Wood", bevel=0.06, mesh="Trim")
    # back door: dark frame, light panel, round frosty window, gold knob
    m.box("DoorFrame", (-1.3, -3.14, DZ - 0.02), (1.3, -2.9, 4.55), WOOD_D, "Wood", bevel=0.08, mesh="Trim")
    m.box("Door", (-1.02, -3.2, DZ + 0.05), (1.02, -3.0, 4.28), WOOD_L, "WoodPlanks", bevel=0.06,
          mesh="Props")                         # same look as the crate -> merges
    m.cyl("DoorWindowRim", (0, -3.05, 3.25), (0, -3.28, 3.25), 0.5, WOOD_D, "Wood", segs=20, mesh="Trim")
    m.cyl("DoorWindow", (0, -3.1, 3.25), (0, -3.32, 3.25), 0.36, S["frost"], segs=20, mesh="Frost")
    ball("DoorKnob", (0.66, -3.3, 2.0), 0.17, GOLD, subdiv=2, mesh="Coins")
    snowflake("BackFlake", (0, 7.6), -3.12, -2.92, R=1.45, arm_w=0.42, br_len=0.62, br_w=0.32, hub=0.42)
    # a shuttered frost window in each outer back panel, snow on the sill
    for sx in (1, -1):
        wx = sx * 4.72
        WZ0, WZ1, WHW = 5.65, 7.15, 0.6
        m.box("WinFrame%d" % sx, (wx - WHW, -3.16, WZ0), (wx + WHW, -2.9, WZ1), WOOD_D, "Wood", bevel=0.07,
              mesh="Trim")
        m.box("WinPane%d" % sx, (wx - WHW + 0.17, -3.22, WZ0 + 0.17), (wx + WHW - 0.17, -3.1, WZ1 - 0.17), PEG,
              bevel=0.04, mesh="Frost")
        m.box("WinMullion%d" % sx, (wx - WHW + 0.1, -3.27, (WZ0 + WZ1) / 2 - 0.1),
              (wx + WHW - 0.1, -3.14, (WZ0 + WZ1) / 2 + 0.1), WOOD_D, "Wood", bevel=0.04, mesh="Trim")
        for side in (1, -1):
            sx0, sx1 = sorted((wx + side * (WHW - 0.02), wx + side * (WHW + 0.44)))
            m.box("Shutter%d_%d" % (sx, side), (sx0, -3.14, WZ0 - 0.02), (sx1, -2.92, WZ1 + 0.02), ORANGE,
                  bevel=0.06, mesh="Awning")    # same look as the awning stripes -> merges
        m.box("WinSill%d" % sx, (wx - WHW - 0.12, -3.4, WZ0 - 0.2), (wx + WHW + 0.12, -2.9, WZ0 + 0.02), WOOD_D,
              "Wood", bevel=0.05, mesh="Trim")
        m.tube("WinSnow%d" % sx, [(wx - WHW - 0.02, -3.2, WZ0 + 0.04), (wx, -3.22, WZ0 + 0.1),
                                  (wx + WHW + 0.02, -3.2, WZ0 + 0.04)], [0.14, 0.2, 0.14], SNOW, "Snow", segs=8,
               mesh="SnowCap")
    PBF = -2.45
    m.box("Pegboard", (-5.3, -2.64, 3.55), (5.3, PBF, 9.6), BOARD, bevel=0.1, mesh="Pegboard")
    m.box("PegTrim", (-5.45, -2.62, 9.45), (5.45, PBF + 0.1, 9.75), WOOD_D, "Wood", bevel=0.06, mesh="Trim")
    for sx in (1, -1):
        x0, x1 = sorted((sx * 5.08, sx * 5.42))
        m.box("PegBatten%d" % sx, (x0, -2.66, 3.5), (x1, PBF + 0.1, 9.6), WOOD_D, "Wood", bevel=0.05, mesh="Trim")
    # peg-hole grid (the board reads as a tool pegboard, not a window): 8 x 4 chunky holes at the Gift's dot scale
    HOLE_R = 0.24
    hole_pts = L.circle_pts(HOLE_R, 6, phase=math.pi / 6)
    CBX, CBZ, CB_HW, CB_HH = -3.0, 5.0, 0.95, 0.62          # the chalkboard frame (placed further down)

    def peg_holes(b):
        # one flat hexagon per hole, 0.05 proud of the board (no z-fight from across the lobby), facing +Y;
        # holes the chalkboard frame would half-cover are left out
        for i in range(8):
            for j in range(4):
                hx, hz = -4.55 + 1.3 * i, 4.3 + 1.3 * j
                if abs(hx - CBX) < CB_HW + HOLE_R and abs(hz - CBZ) < CB_HH + HOLE_R:
                    continue
                vs = [b.verts.new((hx + x, PBF + 0.05, hz + z)) for (x, z) in reversed(hole_pts)]
                b.faces.new(vs)
    m.custom("PegHoles", peg_holes, SLATE, mesh="Pegboard", collide=False, shadow=False)

    # ------------------------------------------------------------------ launchers
    # 1) big red shovel planted in a drift, leaning on the outer (+X) face of the left front post
    SHY, SS, STILT = PFY + 0.08, 1.15, 14.0
    # blade tip on the floor; the handle axis touches the post's +X face just under the grip
    SHX = PX + PH + 0.17 * SS + 3.95 * SS * math.sin(math.radians(STILT))
    Msh = L.xf((SHX, SHY, 0.0), ry=-STILT, scale=SS)
    blade = [(0.7, 1.55), (-0.7, 1.55), (-0.7, 0.55)] + \
            [(-0.7 * math.cos(math.radians(a)), 0.55 - 0.55 * math.sin(math.radians(a))) for a in range(15, 180, 15)] + \
            [(0.7, 0.55)]
    # (blade outline is in the shovel's local x-z plane; extrude it along local y, then place it with Msh)
    m.prism("ShovelBlade", blade, -0.11, 0.11, S["red"], matrix=Msh @ L.xf(rx=90), bevel=0.06, mesh="Launchers")
    m.box("ShovelRib", (-0.12, -0.2, 0.75), (0.12, 0.2, 1.5), S["red"], bevel=0.05, matrix=Msh, mesh="Launchers")
    m.cyl("ShovelCollar", w(Msh, (0, 0, 1.4)), w(Msh, (0, 0, 1.95)), 0.24 * SS, SLATE, segs=12, mesh="Launchers")
    m.cyl("ShovelHandle", w(Msh, (0, 0, 1.85)), w(Msh, (0, 0, 4.12)), 0.17 * SS, WOOD_L, "Wood", segs=10,
          mesh="Launchers")
    m.cyl("ShovelGrip", w(Msh, (0, -0.36, 4.16)), w(Msh, (0, 0.36, 4.16)), 0.18 * SS, WOOD_D, "Wood", segs=10,
          mesh="Launchers")

    # 2) slingshot standing in the ice-ball crate (viewer's right end), loaded with a candy-pink snowball
    KX, KY, KR = -7.5, 0.95, 5.0
    Mk = L.xf((KX, KY, 0), rz=KR)
    KH, KT = 0.88, 1.62
    SG = 1.36
    Mg = Mk @ L.xf((0, -0.08, 2.84), scale=SG)
    m.tube("SlingArmL", [w(Mg, p) for p in [(0, 0, -1.3), (0, 0, -0.2), (0.32, 0, 0.3), (0.62, 0, 1.05)]],
           [0.2 * SG, 0.2 * SG, 0.18 * SG, 0.18 * SG], WOOD_D, "Wood", segs=10, mesh="Launchers")
    m.tube("SlingArmR", [w(Mg, p) for p in [(0, 0, -0.2), (-0.32, 0, 0.3), (-0.62, 0, 1.05)]],
           [0.2 * SG, 0.18 * SG, 0.18 * SG], WOOD_D, "Wood", segs=10, mesh="Launchers")
    for sx in (1, -1):
        ball("SlingTip%d" % sx, w(Mg, (sx * 0.62, 0, 1.06)), 0.2 * SG, WOOD_D, "Wood", subdiv=2, mesh="Launchers")
    m.cyl("SlingWrap", w(Mg, (0, 0, -0.92)), w(Mg, (0, 0, -0.36)), 0.25 * SG, SLATE, segs=10, mesh="Launchers")
    m.tube("SlingBand", [w(Mg, p) for p in [(0.62, 0.1, 0.95), (0.25, 0.22, 0.45), (0, 0.25, 0.35),
                                              (-0.25, 0.22, 0.45), (-0.62, 0.1, 0.95)]],
           [0.13 * SG] * 5, ORANGE, segs=8, mesh="Launchers")
    ball("SlingBall", w(Mg, (0, 0.3, 0.52)), 0.34 * SG, PINK_B, mesh="Snowballs")

    # 3) blue snow scoop hung low on the pegboard (clears the valance from a gameplay camera)
    # the bowl opens forward and 30 degrees up so its hollow reads, and it holds a snowball
    SCX, SCZ, SCR, SCT = 2.62, 4.38, 0.66, 0.12
    bowl = [(0, 0)] + [(SCR * math.sin(math.radians(a)), SCR - SCR * math.cos(math.radians(a)))
                       for a in (22, 45, 68, 90)] + \
           [(SCR - SCT, SCR)] + [((SCR - SCT) * math.sin(math.radians(a)),
                                  SCR - (SCR - SCT) * math.cos(math.radians(a))) for a in (68, 45, 22)] + [(0, SCT)]
    # turned toward the viewer's right so the bowl shows its domed side profile, not a flat ring
    SC_UP, SC_TURN = 25.0, 58.0
    ax = (Matrix.Rotation(math.radians(SC_TURN), 3, 'Z') @
          Vector((0, math.cos(math.radians(SC_UP)), math.sin(math.radians(SC_UP)))))
    pole = Vector((SCX, PBF + SCR * (1 - ax.y) + 0.01, SCZ))   # the bowl's back just touches the board
    m.lathe("ScoopBowl", bowl, S["royal_blue"], matrix=L.xf(tuple(pole), rx=-(90 - SC_UP), rz=SC_TURN), segs=16,
            mesh="Launchers")
    bc = pole + ax * SCR                                   # centre of the bowl's sphere (= the rim's centre)
    up = (Vector((0, 0, 1)) - ax * ax.z).normalized()
    rim_top = bc + up * SCR
    ball("ScoopBall", tuple(bc + ax * 0.05 + Vector((0, 0, -0.04))), 0.46, WHITE_B, mesh="Snowballs")
    htop = SCZ + 2.0
    m.tube("ScoopHandle", [tuple(rim_top + Vector((0, -0.02, -0.1))), (SCX, PBF + 0.3, SCZ + 1.45),
                           (SCX, PBF + 0.3, htop)], [0.17, 0.17, 0.17], WOOD_L, "Wood", segs=10, mesh="Launchers")
    m.cyl("ScoopGrip", (SCX - 0.42, PBF + 0.3, htop + 0.08), (SCX + 0.42, PBF + 0.3, htop + 0.08), 0.19,
          WOOD_D, "Wood", segs=10, mesh="Launchers")
    for sx in (1, -1):
        m.cyl("ScoopPeg%d" % sx, (SCX + sx * 0.3, PBF - 0.02, htop - 0.2),
              (SCX + sx * 0.3, PBF + 0.52, htop - 0.2), 0.13, WOOD_D, "Wood", segs=8, mesh="Launchers")

    # a little price-less chalkboard on the right half of the pegboard: coin -> snowball pictogram
    # (CBX, CBZ, CB_HW, CB_HH are set with the peg holes above)
    m.box("ChalkFrame", (CBX - CB_HW, PBF - 0.02, CBZ - CB_HH), (CBX + CB_HW, PBF + 0.14, CBZ + CB_HH), WOOD_D,
          "Wood", bevel=0.06, mesh="Trim")
    m.box("Chalkboard", (CBX - 0.8, PBF + 0.08, CBZ - 0.47), (CBX + 0.8, PBF + 0.18, CBZ + 0.47), SLATE, bevel=0.03,
          mesh="Pegboard", collide=False, shadow=False)      # same look as the peg holes -> merges
    m.cyl("ChalkCoin", (CBX + 0.47, PBF + 0.14, CBZ), (CBX + 0.47, PBF + 0.28, CBZ), 0.27, GOLD, segs=14,
          mesh="Coins")
    m.cyl("ChalkBall", (CBX - 0.47, PBF + 0.14, CBZ), (CBX - 0.47, PBF + 0.26, CBZ), 0.27, WHITE_B, segs=14,
          mesh="Snowballs")
    arrow = [(0.19, 0.09), (-0.02, 0.09), (-0.02, 0.22), (-0.22, 0.0), (-0.02, -0.22), (-0.02, -0.09), (0.19, -0.09)]
    xz_prism("ChalkArrow", [(x + CBX, z + CBZ) for (x, z) in arrow], PBF + 0.14, PBF + 0.23, PEG, bevel=0.02,
             mesh="Frost")

    # 4) snowball cannon for sale on the counter (centre)
    CS = 1.4
    CN = L.xf((-0.55, 0.62, CTOP - 0.01), rz=-62, scale=CS)   # side-on to the approach, aimed at the pile
    m.box("CannonCarriage", (-0.36, -0.95, 0.0), (0.36, 0.35, 0.6), WOOD_D, "Wood", bevel=0.06, matrix=CN,
          mesh="Launchers")
    for sx in (1, -1):
        m.cyl("CannonWheel%d" % sx, w(CN, (sx * 0.36, -0.15, 0.46)), w(CN, (sx * 0.6, -0.15, 0.46)), 0.46 * CS, WOOD_L,
              "Wood", segs=16, mesh="Launchers")
        m.cyl("CannonHub%d" % sx, w(CN, (sx * 0.58, -0.15, 0.46)), w(CN, (sx * 0.68, -0.15, 0.46)), 0.17 * CS, GOLD,
              segs=12, mesh="Coins")
    ca, sa = math.cos(math.radians(18)), math.sin(math.radians(18))
    breech = (0, -0.7, 0.66)
    barrel = [(0, 0), (0.3, 0), (0.36, 0.08), (0.36, 0.3), (0.32, 0.36), (0.29, 1.35), (0.37, 1.4), (0.37, 1.62),
              (0.25, 1.62), (0.25, 1.45), (0, 1.45)]
    m.lathe("CannonBarrel", barrel, SLATE, matrix=CN @ L.xf(breech, rx=-72), segs=18, mesh="Launchers")
    ball("CannonKnob", w(CN, (0, breech[1] - 0.11 * ca, breech[2] - 0.11 * sa)), 0.19 * CS, SLATE, subdiv=2,
         mesh="Launchers")
    ball("CannonBall", w(CN, (0, breech[1] + 1.66 * ca, breech[2] + 1.66 * sa)), 0.28 * CS, WHITE_B,
         mesh="Snowballs")

    # ------------------------------------------------------------------ awnings (the hero + a little one over the back door)
    def awning(tag, AW, NS, yf, zf, run, ang_deg, T0, BUMP, band, depth_k, flap_t, pre=None, snow_v0=0.66,
               tongue=0.55, h_edge=0.1, h_peak=0.42, r_fall=0.7, wiggle=0.08, samples=6, nv=10):
        """Striped cushion awning built in its own frame: the low front edge at (y=yf, z=zf), rising `run` studs
        back toward -Y at ang_deg, a scalloped valance under the front edge and a snow blanket draped over the
        upper part (a tongue of snow sliding down each crest, echoing the scallops). `pre` places the whole thing
        (e.g. turned 180 degrees for the back door)."""
        a = math.radians(ang_deg)
        s_, c_ = math.sin(a), math.cos(a)
        length = run / c_
        M = Matrix(((1, 0, 0, 0), (0, s_, -c_, yf), (0, c_, s_, zf), (0, 0, 0, 1)))  # x, y'=normal, z'=up-slope
        if pre is not None:
            M = pre @ M
        sw = 2 * AW / NS

        def cushion(u):
            if u <= -AW or u >= AW:
                return T0
            f = ((u + AW) / sw) % 1.0
            return T0 + BUMP * math.sin(math.pi * f)

        for i in range(NS):
            x0 = -AW + i * sw
            pts = [(x0, 0.0), (x0 + sw, 0.0)]
            for k in range(11):
                u = 1 - k / 10
                pts.append((x0 + sw * u, T0 + BUMP * math.sin(math.pi * u)))
            col = ORANGE if i % 2 == 0 else CREAM
            m.prism(tag + "Stripe%d" % i, pts, 0.0, length, col, matrix=M, smooth=True, mesh="Awning")
            xc, r = x0 + sw / 2, sw / 2
            top, mid = zf + T0 * 0.9, zf - band
            flap = [(xc - r, top), (xc - r, mid)] + \
                   [(xc - r * math.cos(math.radians(q)), mid - depth_k * r * math.sin(math.radians(q)))
                    for q in range(15, 180, 15)] + [(xc + r, mid), (xc + r, top)]
            xz_prism(tag + "Flap%d" % i, flap, yf - flap_t, yf, col, bevel=0.04, pre=pre, mesh="Awning")

        def snow_cap(b):
            import bmesh
            us = [-AW - 0.07] + [-AW + sw * k / samples for k in range(NS * samples + 1)] + [AW + 0.07]
            vback = length + 0.03
            V0 = length * snow_v0

            def vfront(u):
                f = ((u + AW) / sw) % 1.0 if -AW < u < AW else 0.0
                return V0 - tongue * math.sin(math.pi * f) ** 2 + wiggle * math.sin(u * 3.1)

            top, bot = [], []
            for u in us:
                vf = vfront(u)
                c = cushion(u)
                rt, rb = [], []
                for j in range(nv + 1):
                    t = j / nv
                    v = vf + (vback - vf) * t
                    d = min(u - us[0], us[-1] - u, (v - vf) * 1.3, (vback - v) * 3.0)
                    s = max(0.0, min(1.0, d / r_fall))
                    s = s * s * (3 - 2 * s)
                    hh = h_edge + (h_peak - h_edge) * s
                    rt.append(b.verts.new(M @ Vector((u, c + hh, v))))
                    rb.append(b.verts.new(M @ Vector((u, c - 0.12, v))))
                top.append(rt)
                bot.append(rb)
            nu = len(us) - 1
            for i in range(nu):
                for j in range(nv):
                    b.faces.new((top[i][j], top[i][j + 1], top[i + 1][j + 1], top[i + 1][j]))
                    b.faces.new((bot[i][j], bot[i + 1][j], bot[i + 1][j + 1], bot[i][j + 1]))
            for i in range(nu):
                for j in (0, nv):
                    b.faces.new((top[i][j], top[i + 1][j], bot[i + 1][j], bot[i][j]))
            for j in range(nv):
                for i in (0, nu):
                    b.faces.new((top[i][j], top[i][j + 1], bot[i][j + 1], bot[i][j]))
            bmesh.ops.recalc_face_normals(b, faces=b.faces[:])

        m.custom(tag + "SnowCap", snow_cap, SNOW, "Snow", smooth=True, mesh="SnowCap")
        return sw

    AW = 7.3
    SW = awning("", AW, 7, YF, ZF, YF - YB + 0.1, 16, 0.25, 0.3, 0.3, 0.62, 0.24)

    # chunky icicles hanging from the scallops (the lowest point of a flap is its centre)
    flap_mid, flap_r, flap_k = ZF - 0.3, SW / 2, 0.62
    icicles = [(0, 0.0, 0.9), (1, 0.45, 0.55), (2, 0.0, 0.72), (3, -0.4, 0.6), (4, 0.0, 0.85), (5, 0.42, 0.55),
               (6, 0.0, 0.75)]
    for i, du, ln in icicles:
        xc = -AW + SW * (i + 0.5) + du * flap_r
        q = math.acos(max(-1.0, min(1.0, (-du * flap_r) / flap_r)))  # xc_off = -r cos q
        zb = flap_mid - flap_k * flap_r * math.sin(q) + 0.08
        m.cyl("Icicle%d" % i, (xc, YF - 0.12, zb), (xc, YF - 0.12, zb - ln), 0.22 if ln > 0.6 else 0.19, ICE,
              segs=8, r2=0.03, smooth=False, mesh="Frost")

    # little canopy over the back door (built facing +Y, then turned to face -Y), on two brackets
    R180 = Matrix.Rotation(math.pi, 4, 'Z')
    BW = 2.95                      # the back wall's outer face, in the turned frame
    DYF, DZF, DRUN, DANG = BW + 1.25, 5.05, 1.25, 24
    awning("Door", 1.85, 3, DYF, DZF, DRUN + 0.15, DANG, 0.18, 0.18, 0.18, 0.6, 0.2, pre=R180, snow_v0=0.45, tongue=0.22,
           h_edge=0.07, h_peak=0.22, r_fall=0.3, wiggle=0.03, samples=6, nv=6)
    under_at = lambda yy: DZF + (DYF - yy) * math.tan(math.radians(DANG))
    YZ = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))   # local (x, y, z) -> world (y, z, x)
    for sx in (1, -1):
        tri = [(BW - 0.03, 4.62), (BW - 0.03, under_at(BW) + 0.02), (DYF - 0.3, under_at(DYF - 0.3) + 0.02)]
        m.prism("DoorBracket%d" % sx, tri, -0.12, 0.12, WOOD_D, "Wood",
                matrix=R180 @ Matrix.Translation((sx * 1.45, 0, 0)) @ YZ, bevel=0.03, mesh="Trim")

    # ------------------------------------------------------------------ header sign
    def sign_pts(W, zb, zs, hump, n=20):
        pts = [(-W, zb), (W, zb)]
        for k in range(n + 1):
            x = W - 2 * W * k / n
            pts.append((x, zs + hump * math.cos(math.pi * x / (2 * W))))
        return pts

    SY0, SY1 = -3.05, -2.45
    xz_prism("SignFrame", sign_pts(6.02, SB - 0.27, SF_TOP, 0.72), SY0 + 0.1, SY1 - 0.1, GOLD_D, bevel=0.08,
             mesh="SignFrame")
    xz_prism("SignBoard", sign_pts(5.72, SB, SB_TOP, 0.7), SY0, SY1, SLATE, bevel=0.1, mesh="Sign")
    m.text("SignWord", "SHOP", 2.6, 0.45, GOLD, loc=(0, SY1 + 0.2, SZ), mesh="SignLetters")
    m.text("SignWordBack", "SHOP", 2.6, 0.45, GOLD, loc=(0, SY0 - 0.2, SZ), rz=180, mesh="SignLetters")
    for sx in (1, -1):
        coin_face("SignCoin%d" % sx, (sx * 4.6, SY1 - 0.02, SZ), 0.72, 0.26, GOLD, star_hex=GOLD_D)
        coin_face("SignCoinB%d" % sx, (sx * 4.6, SY0 + 0.02, SZ), 0.72, 0.26, GOLD, star_hex=GOLD_D, facing=-1)
    # snow roll along the top of the sign
    arch, radii = [], []
    n = 16
    for k in range(n + 1):
        x = 5.9 - 11.8 * k / n
        z = SF_TOP + 0.72 * math.cos(math.pi * x / (2 * 6.02)) + 0.1
        arch.append((x, (SY0 + SY1) / 2, z))
        radii.append(0.2 + 0.2 * math.sin(math.pi * k / n))
    m.tube("SignSnow", arch, radii, SNOW, "Snow", segs=10, mesh="SnowCap")

    # gold 4-point sparkles round the crown (the set's shared sparkle language)
    # (bigger + thicker to match the Gift / Ascend twinkles; the top pair sits a little lower and further out so
    # the tips stay under the finials' 14.92 and clear of the snow roll)
    SPY0, SPY1 = SY1 + 0.25, SY1 + 0.55
    for k, (sx_, sz_, sr) in enumerate(((7.45, 12.95, 0.8), (-7.35, 12.3, 0.65), (-3.65, 14.38, 0.5),
                                        (3.85, 14.42, 0.45))):
        sparkle("Sparkle%d" % k, (sx_, sz_), sr, SPY0, SPY1)

    # ------------------------------------------------------------------ goods on the counter
    # snowball pyramid on a tray (viewer's left end)
    GX, GY = 4.25, 0.83
    m.box("Tray", (GX - 1.3, GY - 1.2, CTOP - 0.02), (GX + 1.3, GY + 1.2, CTOP + 0.16), WOOD_D, "Wood",
          bevel=0.06, mesh="Trim")
    r = 0.38
    base = CTOP + 0.16 + r
    idx = 0
    layers = [(3, 0.0), (2, r * math.sqrt(2)), (1, 2 * r * math.sqrt(2))]
    for li, (n, dz) in enumerate(layers):
        for a in range(n):
            for c in range(n):
                x = GX + (a - (n - 1) / 2) * 2 * r
                y = GY + (c - (n - 1) / 2) * 2 * r
                col = BALL_COLS[(a + 2 * c + li) % 4] if li < 2 else PINK_B
                hidden = li == 1 or (li == 0 and c == 0)    # middle layer + back row: mostly hidden -> cheaper
                ball("Ball%d" % idx, (x, y, base + dz), r * 0.98, col, subdiv=2 if hidden else 3, mesh="Snowballs")
                idx += 1
    # coin stacks (viewer's right end)
    stacks = [((-4.0, 0.75), 5), ((-4.85, 1.2), 3), ((-4.75, 0.15), 2), ((-3.35, 1.35), 1)]
    ci = 0
    for (sx_, sy_), cnt in stacks:
        for k in range(cnt):
            jx = 0.04 * math.sin(k * 2.3 + sx_)
            jy = 0.04 * math.cos(k * 1.7 + sy_)
            coin_flat("StackCoin%d" % ci, (sx_ + jx, sy_ + jy, CTOP - 0.01 + k * 0.19), 0.42, 0.2, GOLD)
            ci += 1

    # ------------------------------------------------------------------ barrel of snowballs (viewer's left, floor)
    BX, BY = 7.65, 1.0
    prof = [(0, 0), (0.78, 0), (0.9, 0.55), (0.95, 1.1), (0.9, 1.65), (0.78, 2.2), (0.66, 2.2), (0.66, 1.95),
            (0, 1.95)]
    m.lathe("Barrel", prof, WOOD, "Wood", matrix=L.xf((BX, BY, 0)), segs=16, smooth=True, mesh="Props")
    for zb_, zt_, rr in ((0.28, 0.52, 0.915), (1.68, 1.92, 0.92)):
        m.cyl("Hoop%d" % int(zb_ * 10), (BX, BY, zb_), (BX, BY, zt_), rr, WOOD_D, "Wood", segs=16, mesh="Trim")
    for k, (dx, dy, dz) in enumerate(((0.27, 0.0, 2.15), (-0.14, 0.24, 2.15), (-0.14, -0.24, 2.15), (0, 0, 2.6))):
        ball("BarrelBall%d" % k, (BX + dx, BY + dy, dz), 0.37, (WHITE_B, WHITE_B, ICE_B, WHITE_B)[k],
             mesh="Snowballs")

    # ------------------------------------------------------------------ crate of ice snowballs (viewer's right)
    m.box("Crate", (-KH, -KH, 0), (KH, KH, KT), WOOD_L, "WoodPlanks", bevel=0.06, matrix=Mk, mesh="Props")
    for sx in (1, -1):
        for sy in (1, -1):
            m.box("CrateCorner%d%d" % (sx, sy), (sx * KH - 0.16, sy * KH - 0.16, 0), (sx * KH + 0.16,
                  sy * KH + 0.16, KT + 0.03), WOOD_D, "Wood", bevel=0.04, matrix=Mk, mesh="Trim")
    m.box("CrateBand", (-KH - 0.04, -KH - 0.04, 0.62), (KH + 0.04, KH + 0.04, 0.98), WOOD_D, "Wood", bevel=0.04,
          matrix=Mk, mesh="Trim")
    for k, (dx, dy) in enumerate(((0.4, 0.4), (-0.4, 0.4), (0.4, -0.42), (-0.4, -0.42))):
        ball("CrateBall%d" % k, w(Mk, (dx, dy, KT + 0.1)), 0.41, ICE_B, subdiv=2 if dy < 0 else 3, mesh="Snowballs")

    # ------------------------------------------------------------------ lantern on the left front post
    LX = PX + 1.0
    LZ = 7.55
    m.box("LanternArm", (PX + PH - 0.02, PFY - 0.14, LZ), (LX + 0.2, PFY + 0.14, LZ + 0.28), WOOD_D, "Wood",
          bevel=0.04, mesh="Trim")
    m.cyl("LanternHook", (LX, PFY, LZ + 0.02), (LX, PFY, LZ - 0.25), 0.09, SLATE, segs=8, mesh="Lantern")
    m.cyl("LanternCap", (LX, PFY, LZ - 0.5), (LX, PFY, LZ - 0.2), 0.42, SLATE, segs=8, r2=0.12, mesh="Lantern")
    m.box("LanternTop", (LX - 0.36, PFY - 0.36, LZ - 0.6), (LX + 0.36, PFY + 0.36, LZ - 0.47), SLATE, bevel=0.03,
          mesh="Lantern")
    m.box("LanternGlow", (LX - 0.28, PFY - 0.28, LZ - 1.25), (LX + 0.28, PFY + 0.28, LZ - 0.58), GOLD_N, "Neon",
          bevel=0.05, mesh="Lantern", shadow=False)
    m.box("LanternBase", (LX - 0.36, PFY - 0.36, LZ - 1.35), (LX + 0.36, PFY + 0.36, LZ - 1.23), SLATE, bevel=0.03,
          mesh="Lantern")

    # ------------------------------------------------------------------ snow drifts at the deck corners
    drift("DriftFL", (7.7, 2.55, 0.0), 0.88, 0.72, 0.42, rz=-8)       # round the shovel blade
    drift("DriftFR", (-6.95, 2.72, 0.0), 0.95, 0.6, 0.36, rz=10)      # beside the right front post foot
    drift("DriftBL", (6.55, -3.25, 0.0), 1.05, 0.68, 0.4, rz=12)
    drift("DriftBR", (-6.5, -3.3, 0.0), 1.2, 0.7, 0.44, rz=-6)

    # ------------------------------------------------------------------ decor never collides (no phantom hulls)
    NOCOLLIDE = {"Frost", "Coins", "Snowballs", "Launchers", "SignLetters", "Sparkles", "Lantern", "Drifts"}
    for o in m.objs:
        if o["rbx_mesh"] in NOCOLLIDE:
            o["rbx_collide"] = False

    # ------------------------------------------------------------------ crisp creases on smooth parts
    # (lobbylib calls Mesh.set_sharpness_by_angle, which Blender 5.x renamed to set_sharp_from_angle)
    for o in m.objs:
        me = o.data
        if any(p.use_smooth for p in me.polygons):
            fn = getattr(me, "set_sharp_from_angle", None) or getattr(me, "set_sharpness_by_angle", None)
            if fn:
                fn(angle=math.radians(40))

    # ------------------------------------------------------------------ centre the footprint on the origin
    import bpy
    bpy.context.view_layer.update()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in m.objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    print("SHOP pre-centre bounds", [round(c, 2) for c in lo], [round(c, 2) for c in hi])
    off = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, 0))
    if off.length > 1e-4:
        for o in m.objs:
            o.data.transform(Matrix.Translation(off))
            o.data.update()
    return m.finish()
