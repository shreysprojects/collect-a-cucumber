"""Gift -- the "like the game / join the group" gift spot for the RAS lobby (replaces the asset-pack `Group`).

Layout (as the player sees it from the front, +Y in Blender; remember +X = the viewer's LEFT):
    viewer's left  : a round royal-blue badge with a chunky white thumbs-up (frost palm + frost sleeve block), gold
                     bezel, on a wood post, "LIKE" plaque
    centre (hero)  : a giant green present, dark-green frame + bright panels, gold ribbon cross, overhanging lid,
                     a two-tone four-loop bow (gold front loops, dark-gold back loops) round a dark-gold-banded knot,
                     two notched tails front AND back, and a "GIFT" tag hanging on a red string that tucks up under the lid
    viewer's right : a rounded royal-blue board with three person icons (middle one bigger), gold bezel, "JOIN" plaque
    at the base    : small presents (red / purple / blue) with gold ribbons, turned a little for play, each placed
                     so it just clears the big present (computed, see small_present)
    floating       : Neon gold sparkle-stars around the bow (no collision)
Both signs are double-sided (the icons + words repeat on the back); both frames tuck 0.1 into their plaque. JOIN turns
12 degrees in toward the front centre; LIKE turns 6 degrees OUT, toward the launch pad (players see the Gift from its
+X / LIKE side there). Colours for the shared roles come from the set judge's palette (SET below).

Collision: the hero (Present, Ribbon, Knot), the minis and the sign structure (Posts, SignSlate, SignTrim, Badges)
collide; tiny / surface decor (Dots, Letters, Tag, RedBits, GoldBits, IconWhite, IconShade, Sparkles) does not.
"""
import math
import bmesh
from mathutils import Vector, Matrix


# ------------------------------------------------------------------------------------------------ helpers
def view_mat(u, v, y, rot=0.0, scale=1.0):
    """Local (a = viewer's right, b = up, c = toward the viewer) -> Blender, placed at view position (u, v), depth y.
    `rot` turns the piece in the view plane, counter-clockwise as the viewer sees it (degrees)."""
    M = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))   # a -> -X, b -> +Z, c -> +Y (det +1)
    s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
    return (Matrix.Translation(Vector((-u, y, v))) @ M @ Matrix.Rotation(math.radians(rot), 4, 'Z')
            @ Matrix.Diagonal((s[0], s[1], s[2], 1)))


BACK = Matrix.Rotation(math.pi, 4, 'Z')          # the mirror-free copy for the back of a double-sided sign


def slab(L, b, pts, c0, c1, bevel=0.1, segments=1, matrix=None):
    """Extrude a 2-D outline from c0 to c1 and bevel only the two outline rims (never the side seams), so rounded
    outlines stay clean. Returns the new verts (after `matrix`)."""
    pre = set(b.verts)
    vs = L.D.prism(b, pts, c0, c1)
    if bevel > 1e-5:
        n = len(pts)
        bot, top = set(vs[:n]), set(vs[n:])
        edges = [e for e in b.edges if (e.verts[0] in bot and e.verts[1] in bot) or (e.verts[0] in top and e.verts[1] in top)]
        bmesh.ops.bevel(b, geom=edges, offset=bevel, segments=segments, profile=0.5, affect='EDGES', clamp_overlap=True)
    b.verts.ensure_lookup_table()
    new = [v for v in b.verts if v not in pre]
    if matrix is not None:
        bmesh.ops.transform(b, matrix=matrix, verts=new)
    return new


def stadium_pts(p0, p1, r, n=6, r0=None):
    """Capsule outline (2-D) from point p0 (radius r0, default r) to point p1 (radius r)."""
    r0 = r if r0 is None else r0
    p0, p1 = Vector(p0), Vector(p1)
    d = (p1 - p0)
    ang = math.atan2(d.y, d.x)
    pts = []
    for i in range(n + 1):                       # round end at p1
        a = ang - math.pi / 2 + math.pi * i / n
        pts.append((p1.x + r * math.cos(a), p1.y + r * math.sin(a)))
    for i in range(n + 1):                       # round end at p0
        a = ang + math.pi / 2 + math.pi * i / n
        pts.append((p0.x + r0 * math.cos(a), p0.y + r0 * math.sin(a)))
    return pts


def ribbon(b, pts, normals, width, thick, closed=False, notch=0.0, widths=None):
    """Flat ribbon swept along a polyline. `normals` = the ribbon's face normal per point (or one for all) =
    the thickness direction; the width runs across (tangent x normal). `notch` cuts a swallowtail V into the end."""
    P = [Vector(p) for p in pts]
    n = len(P)
    single = not isinstance(normals[0], (list, tuple, Vector))
    secs = []
    for i in range(n):
        if closed:
            d = P[(i + 1) % n] - P[(i - 1) % n]
        elif i == 0:
            d = P[1] - P[0]
        elif i == n - 1:
            d = P[-1] - P[-2]
        else:
            d = P[i + 1] - P[i - 1]
        d.normalize()
        nn = Vector(normals) if single else Vector(normals[i])
        nn = (nn - d * nn.dot(d)).normalized()
        s = d.cross(nn).normalized()
        hw = (widths[i] if widths else width) / 2
        ht = thick / 2
        c = P[i]
        mid = c - d * notch if (not closed and notch > 0 and i == n - 1) else c
        coords = [c + s * hw + nn * ht, mid + nn * ht, c - s * hw + nn * ht,
                  c - s * hw - nn * ht, mid - nn * ht, c + s * hw - nn * ht]
        secs.append([b.verts.new(q) for q in coords])
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        a, c = secs[i], secs[(i + 1) % n]
        for j in range(6):
            b.faces.new((a[j], a[(j + 1) % 6], c[(j + 1) % 6], c[j]))
    if not closed:
        for sec in (secs[0], secs[-1]):
            b.faces.new((sec[0], sec[1], sec[4], sec[5]))
            b.faces.new((sec[1], sec[2], sec[3], sec[4]))
    return [v for s_ in secs for v in s_]


def bow_loop_pts(origin, e1, e2, length, height, n=28):
    """Teardrop loop path: pinched at `origin`, round at the far end (along e1), `height` across (along e2)."""
    o, e1, e2 = Vector(origin), Vector(e1).normalized(), Vector(e2).normalized()
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        ex = length * (1 - math.cos(t)) / 2
        pinch = min(1.0, (ex / (0.55 * length)) ** 0.7) if ex > 0 else 0.0
        ey = (height / 2) * math.sin(t) * pinch
        pts.append(o + e1 * ex + e2 * ey)
    return pts


def loop_normals(pts, origin, nrm):
    """In-plane normals (perpendicular to the path, inside the loop plane) for a loop path - stable even at the
    pinch, where a radial-from-the-origin normal would run parallel to the path."""
    out = []
    n = len(pts)
    for i in range(n):
        d = Vector(pts[min(i + 1, n - 1)]) - Vector(pts[max(i - 1, 0)])
        out.append(Vector(nrm).cross(d).normalized())
    return out


# ---- 2-D convex separation (used to seat the small presents right against the big one, never inside it)
def _hull(pts):
    pts = sorted(set((round(x, 6), round(y, 6)) for x, y in pts))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def sat_gap(A, B):
    """Separating-axis gap between two convex 2-D polygons (> 0 = apart by at least that much)."""
    best = -1e9
    for poly in (A, B):
        n = len(poly)
        for i in range(n):
            ex, ey = poly[(i + 1) % n][0] - poly[i][0], poly[(i + 1) % n][1] - poly[i][1]
            ln = math.hypot(ex, ey)
            if ln < 1e-9:
                continue
            ax, ay = -ey / ln, ex / ln
            pa = [p[0] * ax + p[1] * ay for p in A]
            pb = [p[0] * ax + p[1] * ay for p in B]
            best = max(best, min(pb) - max(pa), min(pa) - max(pb))
    return best


def rect_poly(cx, cy, hx, hy, rz_deg=0.0):
    c, s = math.cos(math.radians(rz_deg)), math.sin(math.radians(rz_deg))
    return [(cx + x * c - y * s, cy + x * s + y * c) for (x, y) in ((hx, hy), (-hx, hy), (-hx, -hy), (hx, -hy))]


# The set judge's shared palette (2026-09-24 final round): the three lobby models use these EXACT colours for the
# shared roles. Gold is a warmer ffad2b because ffc93c read lemon-yellow under the lobby's sun + Bloom.
SET = {"gold": "ffad2b", "gold_dark": "d4861e", "gold_neon": "ffa82e", "white": "ffffff", "snow": "f4f8fc",
       "marble": "f3f5fa", "slate_navy": "2c3a55", "slate_light": "3b4a66", "royal_blue": "2f5fbf", "wood": "9a6238",
       "wood_light": "c68c52", "wood_dark": "6b4226", "ice": "9fd3ff", "frost": "c4e8ff", "red": "e8413c"}


# ------------------------------------------------------------------------------------------------ build
def build(L):
    P = L.PALETTE
    m = L.Model("Gift")
    GREEN, GREEN_D = P["green"], P["green_dark"]                 # the Gift's identity colours
    GOLD, GOLD_D, GOLD_N = SET["gold"], SET["gold_dark"], SET["gold_neon"]
    ROYAL, SLATE = SET["royal_blue"], SET["slate_navy"]          # sign faces: deeper than the sky so they stand out
    MINI_BLUE, MINI_BLUE_D = P["blue"], "2a68c0"                 # the small blue present (a present colour, not a role)
    RED = SET["red"]
    CREAM, WHITE, FROST = P["cream"], SET["white"], SET["frost"]
    WOOD = SET["wood"]

    def put(name, b, matrix, hexc, material="SmoothPlastic", **kw):
        if matrix is not None:
            bmesh.ops.transform(b, matrix=matrix, verts=b.verts)
        return m.add(name, b, hexc, material, **kw)

    # ================================================================ the giant present
    cy = -0.18                              # present centre (y) - balances the footprint around the origin
    bw, bd, bh = 6.7, 5.4, 6.2              # body
    x1, y0, y1 = bw / 2, cy - bd / 2, cy + bd / 2
    m.box("Body", (-x1, y0, 0.0), (x1, y1, bh), GREEN_D, bevel=0.22, mesh="Present")

    band = 1.3                              # ribbon width
    hb = band / 2
    gap = 0.28                              # dark-green seam between the ribbon and the bright panels
    inset = 0.34                            # dark-green frame around the panels
    lid_z0, lid_z1 = bh - 0.25, bh + 1.2
    pz0, pz1 = inset, lid_z0 - 0.3
    pt = 0.09                               # panel thickness proud of the face
    for sgn, yf in ((1, y1), (-1, y0)):     # front + back panels, either side of the vertical band
        for side in (1, -1):
            xa, xb = sorted((side * (hb + gap), side * (x1 - inset)))
            ya, yb = sorted((yf - sgn * 0.05, yf + sgn * pt))
            m.box("PanelF%d%d" % (sgn, side), (xa, ya, pz0), (xb, yb, pz1), GREEN, bevel=0.07, mesh="Present")
    for sx in (1, -1):                      # side panels
        for side in (1, -1):
            ya, yb = sorted((cy + side * (hb + gap), cy + side * (bd / 2 - inset)))
            xa, xb = sorted((sx * (x1 - 0.05), sx * (x1 + pt)))
            m.box("PanelS%d%d" % (sx, side), (xa, ya, pz0), (xb, yb, pz1), GREEN, bevel=0.07, mesh="Present")
    # polka dots on the panels (staggered, light green) - surface decor, no collision
    DOT = "8ee6a4"
    rows = [pz0 + (j + 0.5) * (pz1 - pz0) / 4 for j in range(4)]
    k_dot = 0
    for sgn, yf in ((1, y1), (-1, y0)):
        for side in (1, -1):
            xc = side * ((hb + gap) + (x1 - inset)) / 2
            for j, z in enumerate(rows):
                off = 0.45 if j % 2 == 0 else -0.45
                x = xc + side * off
                m.cyl("Dot%d" % k_dot, (x, yf + sgn * 0.02, z), (x, yf + sgn * (pt + 0.07), z), (0.34 if j % 2 == 0 else 0.24), DOT, segs=12,
                      mesh="Dots", collide=False)
                k_dot += 1
    for sx in (1, -1):
        for side in (1, -1):
            yc = cy + side * ((hb + gap) + (bd / 2 - inset)) / 2
            for j, z in enumerate(rows):
                off = 0.3 if j % 2 == 0 else -0.3
                y = yc + side * off
                m.cyl("Dot%d" % k_dot, (sx * (x1 + 0.02), y, z), (sx * (x1 + pt + 0.07), y, z), (0.3 if j % 2 == 0 else 0.22), DOT, segs=12,
                      mesh="Dots", collide=False)
                k_dot += 1

    def plus_pts(hx, hy, h, ccx=0.0, ccy=cy):
        return [(ccx + h, ccy + hy), (ccx - h, ccy + hy), (ccx - h, ccy + h), (ccx - hx, ccy + h), (ccx - hx, ccy - h),
                (ccx - h, ccy - h), (ccx - h, ccy - hy), (ccx + h, ccy - hy), (ccx + h, ccy - h), (ccx + hx, ccy - h),
                (ccx + hx, ccy + h), (ccx + h, ccy + h)]

    rp = 0.14                               # ribbon proud of the faces
    m.prism("RibbonBody", plus_pts(x1 + rp, bd / 2 + rp, hb), 0.0, lid_z0 + 0.2, GOLD, bevel=0.05, mesh="Ribbon")
    lx, ly = x1 + 0.32, bd / 2 + 0.32       # the lid overhangs the body
    m.box("Lid", (-lx, cy - ly, lid_z0), (lx, cy + ly, lid_z1), GREEN, bevel=0.2, mesh="Present")
    m.prism("RibbonLid", plus_pts(lx + rp, ly + rp, hb), lid_z0 - 0.06, lid_z1 + rp, GOLD, bevel=0.05, mesh="Ribbon")
    top = lid_z1 + rp
    # the lid wears the same paper: one row of dots round its sides, two per quarter on top
    zl = (lid_z0 + lid_z1) / 2
    for sgn in (1, -1):
        for xs in (1.75, 2.85):
            for side in (1, -1):
                x = side * xs
                yf = cy + sgn * ly
                m.cyl("LDot%d" % k_dot, (x, yf - sgn * 0.04, zl), (x, yf + sgn * 0.08, zl), 0.28, DOT, segs=12,
                      mesh="Dots", collide=False)
                k_dot += 1
    for sx in (1, -1):
        for ys in (1.45, 2.4):
            for side in (1, -1):
                y = cy + side * ys
                m.cyl("LDot%d" % k_dot, (sx * (lx - 0.04), y, zl), (sx * (lx + 0.08), y, zl), 0.28, DOT, segs=12,
                      mesh="Dots", collide=False)
                k_dot += 1
    for qx in (1, -1):
        for qy in (1, -1):
            for (ax, ay, ar) in ((1.5, 1.2, 0.34), (2.8, 1.35, 0.22), (2.3, 2.4, 0.28)):
                x, y = qx * ax, cy + qy * ay
                m.cyl("LDot%d" % k_dot, (x, y, lid_z1 - 0.04), (x, y, lid_z1 + 0.08), ar, DOT, segs=12,
                      mesh="Dots", collide=False)
                k_dot += 1

    # ---------------------------------------------------------------- the bow: knot, four loops, four tails
    # the knot: a round squashed ball (buries every loop end, front AND back) wrapped by a dark-gold band
    kz, kyc = top + 0.48, cy - 0.05
    kax, kay, kaz = 1.2, 1.1, 0.74
    m.sphere("Knot", (0.0, kyc, kz), 1.0, GOLD, scale=(kax, kay, kaz), subdiv=3, mesh="Ribbon")
    # the wrap: a barrel sleeve round the knot's middle (x -0.68..0.68) that hugs the ball 8 % proud, so it reads
    # as a wide dark-gold band pulled tight over the knot (its lower half is buried in the lid)
    bhw = 0.68
    band_prof = [(1.08 * math.sqrt(max(0.0, 1 - (z_ / kax) ** 2)), z_) for z_ in [-bhw + 2 * bhw * i / 6 for i in range(7)]]
    band_M = (Matrix.Translation(Vector((0.0, kyc, kz))) @ Matrix.Diagonal((1.0, kay, kaz, 1.0))
              @ Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    m.custom("KnotBand", lambda b: L.lathe(b, band_prof, segs=32, matrix=band_M), GOLD_D, mesh="Knot", smooth=True)
    loops = []
    for sx in (1, -1):   # big side loops, tops leaning toward the viewer so the ribbon face shows from the front
        loops.append((sx, Vector((sx * math.cos(math.radians(30)), 0.12, math.sin(math.radians(30)))), 3.7, 2.3, 42, 1.45))
    for sx in (1, -1):   # smaller back loops standing up behind
        loops.append((sx, Vector((sx * 0.55, -0.55, 0.75)), 2.7, 1.9, 30, 1.25))
    for i, (sx, e1, length, height, tilt, width) in enumerate(loops):
        e1 = e1.normalized()
        e2 = (Vector((0, 0, 1)) - e1 * e1.z).normalized()
        e2 = Matrix.Rotation(math.radians(-sx * tilt), 3, e1) @ e2
        nrm = e1.cross(e2).normalized()
        # back loops root a little wider apart, so the knot's band shows between them as a clean strip from behind
        o = Vector((sx * (0.3 if i < 2 else 0.5), cy + (0.0 if i < 2 else -0.2), kz))
        # open path: both ends tuck inside the knot (a closed sweep flips 180 degrees at the pinch and crumples)
        pts = bow_loop_pts(o, e1, e2, length, height, n=34)[2:-1]
        nr = loop_normals(pts, o, nrm)
        # the ribbon is gathered (narrower) where the knot squeezes it
        ws = [width * (0.5 + 0.5 * min(1.0, ((p - o).dot(e1) / (0.4 * length)) ** 0.8)) if (p - o).dot(e1) > 0
              else width * 0.5 for p in pts]
        # two-tone bow: the back loops wear the knot band's dark gold, so the big front loops' openings read as holes
        # (same-gold back loops filled them into one flat yellow lump in Studio)
        front = i < 2
        m.custom("Loop%d" % i, lambda b, pts=pts, nr=nr, w=width, ws=ws: ribbon(b, pts, nr, w, 0.4, closed=False, widths=ws),
                 GOLD if front else GOLD_D, mesh="Ribbon" if front else "Knot", smooth=True)
    for fb, tg in ((1, ""), (-1, "Bk")):    # tails over the lid's front edge AND its back edge, notched ends
        for sx in (1, -1):
            yo = [0.5, 1.6, ly - 0.2, ly + 0.08, ly + 0.13, ly + 0.2]
            xs_ = [0.35, 1.15, 1.55, 1.7, 1.8, 2.2] if fb > 0 else [0.35, 1.2, 1.7, 1.85, 1.95, 2.35]
            zs = [top + 0.25, lid_z1 + 0.12, lid_z1 + 0.12, lid_z1 - 0.1, lid_z1 - 0.5, lid_z0 - 1.3]
            pts = [(sx * x_, cy + fb * y_, z_) for x_, y_, z_ in zip(xs_, yo, zs)]
            nrms = [(0, 0, 1), (0, 0, 1), (0, fb * 0.3, 1), (0, fb * 1, 1), (0, fb * 1, 0.1), (0, fb * 1, 0)]
            m.custom("Tail%s%d" % (tg, sx), lambda b, pts=pts, nrms=nrms: ribbon(b, pts, nrms, 1.1, 0.24, notch=0.5),
                     GOLD, mesh="Ribbon", smooth=True)

    # ---------------------------------------------------------------- the GIFT tag on the front face (decor)
    tag_u, tag_v, tag_rot = 0.3, 3.3, -11.0
    tag_y = y1 + rp + 0.06
    ts = 1.16
    tag_pts = [(ts * 1.65, ts * 0.78), (ts * -1.05, ts * 0.78), (ts * -1.7, ts * 0.2), (ts * -1.7, ts * -0.2),
               (ts * -1.05, ts * -0.78), (ts * 1.65, ts * -0.78)]
    b = bmesh.new()
    slab(L, b, tag_pts, 0.0, 0.26, bevel=0.07, matrix=view_mat(tag_u, tag_v, tag_y, rot=tag_rot))
    put("Tag", b, None, CREAM, mesh="Tag", collide=False)
    eye = view_mat(tag_u, tag_v, tag_y, rot=tag_rot) @ Vector((-1.3 * ts, 0.0, 0.26))
    m.torus("TagEyelet", tuple(eye), 0.24, 0.1, GOLD, rot=L.xf(rx=90), seg_major=12, seg_minor=6, mesh="GoldBits",
            collide=False)
    tb = L.text_bm("GIFT", size=1.2, depth=0.24, font="gill", bevel=0.03)
    bmesh.ops.transform(tb, matrix=view_mat(tag_u, tag_v, tag_y + 0.3, rot=tag_rot) @ Matrix.Translation(Vector((0.36, -0.02, 0.0)))
                        @ Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))).inverted(), verts=tb.verts)
    m.add("TagWord", tb, RED, mesh="RedBits", collide=False)
    # a soft red string (it matches the GIFT word and reads as string against the gold band): up off the eyelet, a
    # gentle sag, then up the band and in under the lid's 0.32 overhang, where its end hides inside the lid (no bead:
    # a gold cord + ball on the gold band read as a lever knob in Studio)
    e0 = Vector(eye) + Vector((0, 0.06, 0))
    p1 = e0 + Vector((-0.12, 0.12, 0.35))
    p4 = Vector((-0.05, y1 + 0.2, lid_z0 + 0.15))
    p2 = p1.lerp(p4, 0.42) + Vector((0, 0.04, -0.2))
    p3 = p1.lerp(p4, 0.78) + Vector((0, 0.02, -0.08))
    m.tube("TagCord", [tuple(e0), tuple(p1), tuple(p2), tuple(p3), tuple(p4)], [0.17] * 5, RED, segs=8,
           mesh="RedBits", collide=False)

    # ================================================================ small presents at the base
    # hero body footprint incl. panels + dots (x +-3.51, front/back dots 0.16 proud); the sign feet (see below)
    hero_rect = rect_poly(0.0, cy, x1 + pt + 0.07, bd / 2 + pt + 0.07)
    FOOT_H = 0.85
    # LIKE faces 6 degrees OUT toward the launch pad (the pad sees the Gift ~60 degrees off its front on this +X side;
    # the old 12-degree turn-in pushed the thumbs-up edge-on there). JOIN keeps its turn-in, which already faces +X.
    SIGN_L = (7.0, 0.1, -6.0)
    SIGN_R = (-7.0, 0.1, -12.0)
    feet = [rect_poly(sx_, sy_, FOOT_H, FOOT_H, r_) for (sx_, sy_, r_) in (SIGN_L, SIGN_R)]

    def mini_footprint(cx, cyy, w, d, rz):
        pts = []
        for (px, py) in ((w / 2 + 0.12, d / 2 + 0.12), (w / 2 + 0.22, 0.26), (0.26, d / 2 + 0.22)):
            for a in (1, -1):
                for c_ in (1, -1):
                    pts.append((a * px, c_ * py))
        c, s = math.cos(math.radians(rz)), math.sin(math.radians(rz))
        return _hull([(cx + x * c - y * s, cyy + x * s + y * c) for (x, y) in pts])

    def seat(side, cyy, w, d, rz, clear=-0.08, foot_clear=0.1):
        """Slide the mini out from the hero along x until it just clears it; nudge it along y off a sign foot.
        The 2-D envelope is conservative (sharp corners, dots everywhere along the sides), so a small negative
        `clear` leaves the real meshes a few hundredths apart (checked with scratch/Gift/check.py)."""
        for _ in range(60):
            cx = side * 3.0
            while sat_gap(mini_footprint(cx, cyy, w, d, rz), hero_rect) < clear:
                cx += side * 0.005
            if all(sat_gap(mini_footprint(cx, cyy, w, d, rz), f) >= foot_clear for f in feet):
                return cx, cyy
            cyy += 0.05 if cyy > cy else -0.05
        return cx, cyy

    def small_present(tag, side, cyy, w, d, h, rz, hexc, hexd, clear=-0.08):
        cx, cyy = seat(side, cyy, w, d, rz, clear=clear)
        R = L.xf((cx, cyy, 0), rz=rz)
        m.box("Mini%s" % tag, (-w / 2, -d / 2, 0), (w / 2, d / 2, h - 0.3), hexc, bevel=0.14, matrix=R, mesh="Minis")
        m.box("MiniLid%s" % tag, (-w / 2 - 0.12, -d / 2 - 0.12, h - 0.4), (w / 2 + 0.12, d / 2 + 0.12, h), hexd,
              bevel=0.1, matrix=R, mesh="Minis")
        hr = 0.26
        b = bmesh.new()
        L.prism_bevel(b, plus_pts(w / 2 + 0.22, d / 2 + 0.22, hr, 0.0, 0.0), 0.0, h + 0.1, bevel=0.04)
        put("MiniRibbon%s" % tag, b, R, GOLD, mesh="GoldBits", collide=False)
        for s in (1, -1):
            loc = R @ Vector((s * 0.36, 0, h + 0.42))
            m.torus("MiniBow%s%d" % (tag, s), tuple(loc), 0.33, 0.14, GOLD,
                    rot=L.xf(rx=90, ry=s * 35, rz=rz), seg_major=12, seg_minor=6, mesh="GoldBits", collide=False)
        m.sphere("MiniKnot%s" % tag, tuple(R @ Vector((0, 0, h + 0.2))), 0.24, GOLD, subdiv=1, mesh="GoldBits",
                 collide=False)

    small_present("Red", 1, cy + 2.15, 2.2, 2.0, 2.1, 14, RED, "b92f2b")
    small_present("Purple", -1, cy + 2.2, 1.8, 1.8, 1.7, -11, P["purple"], "7d3fb5", clear=-0.04)   # its lid edge meets a dot
    small_present("Blue", 1, cy - 2.05, 1.7, 1.7, 1.6, 24, MINI_BLUE, MINI_BLUE_D)

    # ================================================================ the two signs (double-sided, turned in a little)
    plaque_z = 3.95
    PW, PH = 5.6, 2.0                       # plaque (big enough for 1.1-stud caps)
    plaque_top = plaque_z + PH / 2
    plaque_bot = plaque_z - PH / 2

    def both(name, make, S, hexc, material="SmoothPlastic", **kw):
        """Build a piece with make(b) in sign-local coords, place it on the front and (turned 180) on the back."""
        for tag, extra in (("", Matrix.Identity(4)), ("Bk", BACK)):
            b = bmesh.new()
            make(b)
            put(name + tag, b, S @ extra, hexc, material, **kw)

    def sign_base(tag, S, frame_bottom):
        b = bmesh.new()                     # slate block + a gold cap plate: reads on snow AND on dark basalt
        L.D.beveled_box(b, (-FOOT_H, -FOOT_H, 0), (FOOT_H, FOOT_H, 0.36), bevel=0.12)
        put("Foot" + tag, b, S, SLATE, mesh="SignSlate")
        b = bmesh.new()
        L.D.beveled_box(b, (-0.68, -0.68, 0.3), (0.68, 0.68, 0.5), bevel=0.07)
        put("FootCap" + tag, b, S, GOLD, mesh="SignTrim")
        b = bmesh.new()
        L.D.cyl(b, (0, 0, 0.45), (0, 0, frame_bottom + 0.3), 0.32, segs=12)
        put("Post" + tag, b, S, WOOD, "Wood", mesh="Posts", smooth=True)
        for i, z in enumerate((0.48, plaque_bot - 0.35)):
            b = bmesh.new()
            L.D.cyl(b, (0, 0, z), (0, 0, z + 0.3), 0.42, segs=12)
            put("Collar%s%d" % (tag, i), b, S, GOLD, mesh="SignTrim", smooth=True)
        b = bmesh.new()
        slab(L, b, L.rounded_rect_pts(PW, PH, 0.55, segs=3), -0.36, 0.36, bevel=0.1, matrix=view_mat(0, plaque_z, 0.0))
        put("Plaque" + tag, b, S, SLATE, mesh="SignSlate")
        su = PW / 2 - 0.31
        for j, (u, yy) in enumerate(((-su, 0.36), (su, 0.36), (-su, -0.36), (su, -0.36))):   # gold rivets
            b = bmesh.new()
            out = 1 if yy > 0 else -1          # a round rivet head, domed toward the viewer
            L.D.cyl(b, (-u, yy - out * 0.08, plaque_z), (-u, yy + out * 0.1, plaque_z), 0.21, segs=12, r2=0.13)
            put("Stud%s%d" % (tag, j), b, S, GOLD, mesh="SignTrim", smooth=True)

    def letters(tag, word, S):
        for bk, extra in (("", Matrix.Identity(4)), ("Bk", BACK)):
            tb = L.text_bm(word, size=2.0, depth=0.3, font="gill", bevel=0.03, spacing=1.1)   # air between the heavy caps
            zs_ = [v.co.z for v in tb.verts]
            xs_ = [v.co.x for v in tb.verts]
            off = Vector((-(min(xs_) + max(xs_)) / 2, 0.44, plaque_z - (min(zs_) + max(zs_)) / 2))   # centred on the plaque
            bmesh.ops.transform(tb, matrix=S @ extra @ Matrix.Translation(off), verts=tb.verts)
            m.add("Word%s%s" % (tag, bk), tb, GOLD, mesh="Letters", collide=False)

    def sign_mat(spec):
        return Matrix.Translation(Vector((spec[0], spec[1], 0))) @ Matrix.Rotation(math.radians(spec[2]), 4, 'Z')

    # ---------------- LIKE (viewer's left = +X), turned to face the front centre a little
    S_L = sign_mat(SIGN_L)
    rim_r = 2.42
    zL = plaque_top + rim_r + 0.16          # the bezel's outer edge tucks 0.1 into the plaque
    sign_base("L", S_L, zL - rim_r)
    letters("L", "LIKE", S_L)
    b = bmesh.new()
    L.D.cyl(b, (0, -0.26, zL), (0, 0.26, zL), rim_r - 0.1, segs=36)
    put("Badge", b, S_L, ROYAL, mesh="Badges")
    ring = [Vector((rim_r * math.cos(a), 0.0, zL + rim_r * math.sin(a))) for a in [2 * math.pi * i / 44 for i in range(44)]]
    b = bmesh.new()
    ribbon(b, ring, (0, 1, 0), 0.52, 0.84, closed=True)
    put("BadgeRim", b, S_L, GOLD, mesh="SignTrim", smooth=True)
    # thumbs-up, view coords (u = viewer's right) relative to the badge centre; decor (no collision)
    hu, hv, k = 0.2, -0.26, 0.98

    def hand_piece(name, pts, c0, c1, hexc, label, bev=0.14):
        both(name, lambda b: slab(L, b, [(p[0] * k, p[1] * k) for p in pts], c0, c1, bevel=bev, segments=2,
                                  matrix=view_mat(hu, zL + hv, 0.0)), S_L, hexc, mesh=label, smooth=True, collide=False)

    # the sleeve block in the palm's frost (the standard like-icon look); red here read as a lone red bar in Studio
    hand_piece("Cuff", L.rounded_rect_pts(0.78, 2.28, 0.24, segs=3, center=(-1.62, -0.5)), 0.2, 0.8, FROST, "IconShade")
    hand_piece("Palm", L.rounded_rect_pts(1.95, 2.13, 0.52, segs=4, center=(-0.25, -0.5)), 0.2, 0.92, FROST, "IconShade")
    # four fingers stepping back from the index (top) finger, with real gaps between them
    for i, (vc, ue, c1) in enumerate(((0.3, 1.34, 1.20), (-0.24, 1.3, 1.14), (-0.78, 1.2, 1.08), (-1.32, 1.04, 1.02))):
        hand_piece("Finger%d" % i, stadium_pts((-0.4, vc), (ue - 0.235, vc), 0.235), 0.2, c1, WHITE, "IconWhite", bev=0.12)
    hand_piece("Thumb", stadium_pts((-0.78, 0.25), (-0.62, 1.72), 0.5, r0=0.55), 0.2, 1.28, WHITE, "IconWhite")

    # ---------------- JOIN (viewer's right = -X)
    S_R = sign_mat(SIGN_R)
    bw2, bh2 = 5.0, 4.2
    zR = plaque_top + (bh2 / 2 + 0.31) - 0.1
    sign_base("R", S_R, zR - bh2 / 2 - 0.05)
    letters("R", "JOIN", S_R)
    b = bmesh.new()
    slab(L, b, L.rounded_rect_pts(bw2, bh2, 0.7, segs=4), -0.26, 0.26, bevel=0.0, matrix=view_mat(0, zR, 0.0))
    put("Board", b, S_R, ROYAL, mesh="Badges")
    path = [(-u, 0.0, zR + v) for (u, v) in L.rounded_rect_pts(bw2 + 0.1, bh2 + 0.1, 0.75, segs=5)]
    b = bmesh.new()
    ribbon(b, path, (0, 1, 0), 0.52, 0.84, closed=True)
    put("BoardRim", b, S_R, GOLD, mesh="SignTrim", smooth=True)

    ps = 1.15                               # person icon scale
    v_floor = -(bh2 / 2 + 0.05 - 0.26) + 0.02   # the people stand on the bezel's inner edge

    def person(tag, u, R, head_r, c0, c1, hexc, label):
        R, head_r = R * ps, head_r * ps
        pts = [(u - R, v_floor), (u + R, v_floor)] + [(u + R * math.cos(a), v_floor + 0.3 + R * math.sin(a))
                                                     for a in [math.pi * i / 12 for i in range(13)]]
        both("Body" + tag, lambda b: slab(L, b, pts, 0.16, c1, bevel=0.1, segments=2, matrix=view_mat(0, zR, 0.0)),
             S_R, hexc, mesh=label, smooth=True, collide=False)
        hv_ = v_floor + 0.3 + R + 0.14 * ps + head_r
        dep = head_r * 0.62                 # a smooth 24-sided flattened ball (clean round outline from the front)
        prof = [(head_r * math.sin(math.pi * i / 10), -dep * math.cos(math.pi * i / 10)) for i in range(11)]
        prof[0], prof[-1] = (0.0, -dep), (0.0, dep)
        both("Head" + tag, lambda b: L.lathe(b, prof, segs=24, matrix=view_mat(u, zR + hv_, (c0 + c1) / 2)),
             S_R, hexc, mesh=label, smooth=True, collide=False)

    person("M", 0.0, 1.0, 0.66, 0.34, 0.86, WHITE, "IconWhite")
    person("A", 1.42, 0.70, 0.5, 0.28, 0.62, FROST, "IconShade")
    person("B", -1.42, 0.70, 0.5, 0.28, 0.62, FROST, "IconShade")

    # ================================================================ sparkles (Neon, no collision)
    def star3d(b, r, depth):
        """A puffy 4-point sparkle: the star outline with a raised point front and back (reads from the side too)."""
        ring = [b.verts.new((x, y, 0.0)) for (x, y) in L.star_pts(4, r, r * 0.3)]
        f = b.verts.new((0, 0, depth))
        k_ = b.verts.new((0, 0, -depth))
        n = len(ring)
        for j in range(n):
            b.faces.new((ring[j], ring[(j + 1) % n], f))
            b.faces.new((ring[(j + 1) % n], ring[j], k_))

    for i, (x, y, z, r, rot, yaw) in enumerate(((4.4, cy + 0.4, 11.4, 0.95, 0, -18), (-4.2, cy + 0.3, 12.1, 0.75, 12, 18),
                                                (1.3, cy - 0.3, 13.0, 0.58, -10, -8), (-1.6, cy + 0.6, 12.6, 0.42, 20, 10))):
        b = bmesh.new()
        star3d(b, r, r * 0.34)
        put("Sparkle%d" % i, b, L.xf((x, y, z), rx=90, ry=rot, rz=yaw), GOLD_N, "Neon", collide=False, mesh="Sparkles")

    return m.finish()
