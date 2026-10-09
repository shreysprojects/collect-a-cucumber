"""Neon: the Cyber Cucumber - a green cucumber wearing chunky lavender VR goggles."""
import bmesh, math

COLLECTION = "NeonCyberCucumber"
NOTES = (
    "The Neon biome's landmark: the set's standard upright cucumber (cuke_green, h 4.0, "
    "r 0.68, the (0.30, 0.30) stem nub, 18 cuke_stud speckles) wearing chunky lavender VR "
    "GOGGLES round its upper third.  The whole goggle assembly is built upright round "
    "z 2.72 (zf 0.68) and then tipped -6 degrees about X through the body axis at that "
    "height, so it sits lower at the front than at the back; the body itself stays "
    "upright (REV3 departure 1, the tile leans the whole cucumber).  "
    "GOGGLES (neo_goggle, one part): an 8-sided strap band hugging the body, inradius "
    "0.728 (0.10 proud of the skin), 0.48 tall with chamfered edges, world z ~2.40-3.04 "
    "front to back; a VISOR on the front, 1.46 wide x 0.68 tall, its back face at y 0.56 "
    "(inside the body, strap and temples; only a 0.10 ledge above and below the strap "
    "shows from behind) and its face 0.40 proud of the skin (y 1.03), front edges "
    "chamfered 0.06, corners cut 0.12, and a NOSE NOTCH cut up into its lower edge "
    "(0.42 wide at the bottom, 0.18 at the top, 0.14 high) as the tile shows; and two "
    "side TEMPLE blocks (x 0.47-0.73, y 0.05-0.75) that fill the gap between the visor's "
    "back and the strap, so each side of the goggles is one flat lavender panel at "
    "x = +-0.73, flush with the strap's side facets.  "
    "On the visor face, each outline a true inset of the visor's (notch included): "
    "GoggleRim (neo_goggle_dk) a 0.04-wide raised frame line 0.10 in from the visor edge, "
    "standing 0.045 proud; Lenses (neo_lens) one dark panel inside it, 0.02 proud, which "
    "is the dark border (it follows the nose notch too, so the notch itself stays "
    "lavender, framed by the rim) and the 0.10 dark bridge between the lenses; "
    "LensGlow (neo_magenta, Neon, emit 0.6) two glowing lenses ~0.50 x 0.32 on the dark "
    "panel, 0.02 proud of it, their lower inner corners cut away by the nose notch.  "
    "SideLight (neon_blue, Neon, emit 0.6) a 0.18 x 0.34 x 0.26 block set into the "
    "goggles' side panel just behind the visor on the NEGATIVE-x side only (the tile's "
    "right), 0.05 proud; SideLightHi (neo_cyan, Neon, emit 0.6) a thin vertical stripe "
    "on its face toward the front.  "
    "Speckles: the standard 7 x 3 scatter (seed 7) minus the two rows the goggles cover "
    "(zf 0.64 and 0.76 - checked: the 0.64 row is under the strap, and the jittered "
    "0.763 row would be half-buried in the tilted strap's back or jammed within 0.02 of "
    "the temples and visor at the front, so the skip band is zf 0.56 .. 0.78, not the "
    "brief's 0.60 .. 0.76), "
    "whose three studs are re-seated just above the goggles at zf 0.81 on facets 0, 3, 6 "
    "so the upper body is not bare.  "
    "Deviations from the brief, where the tile wins: the lenses glow magenta-pink over "
    "almost their whole area inside a dark frame (so LensGlow fills each lens instead of "
    "a lower-half bar, and uses neo_magenta, the nearest key to the tile's violet-pink, "
    "not neo_pink), and Lenses is the tile's one dark window panel rather than two "
    "separate 0.46 x 0.34 dark lenses; the visor is 1.46 x 0.68 (not 1.30 x 0.62) so its sides run flush "
    "into the strap, with the tile's nose notch and side housings; the side light is "
    "BLUE with a cyan highlight stripe as drawn, not a plain cyan block.  The tile's "
    "darker-magenta glare strokes inside the lenses are left out (a ninth colour for a "
    "detail that does not read at range).  "
    "Footprint about 1.53 (x) x 1.84 (y) x 4.30 tall (nub top), centred on x = 0, "
    "y = 0, nothing below z = 0.  About 1500 tris.  8 parts: Body, Studs, Goggles, GoggleRim, Lenses, LensGlow, SideLight, "
    "SideLightHi.  Everything on the goggles is placed with one matrix, so dryrun's "
    "transform-blind bounding box shows it untilted."
)

# ------------------------------------------------------------------ the goggles
ZC = 0.68 * 4.0             # 2.72: goggle centre height (zf 0.68, mid-strap)
TILT = -6.0                 # degrees about X: NEGATIVE drops the front, lifts the back

SKIN = 0.68 * math.cos(math.pi / 8.0)   # 0.628: facet inradius where the body is full

STRAP_HH = 0.24             # half-height: zf 0.62 .. 0.74
STRAP_IN = SKIN + 0.10      # 0.728 outer inradius, 0.10 proud of the skin
STRAP_CH = 0.035            # chamfer on the strap's top and bottom edges

VIS_HW, VIS_HH = 0.73, 0.34     # visor half-width / half-height (1.46 x 0.68)
VIS_CORNER = 0.12               # corner cut of the visor outline
NOTCH_BOT, NOTCH_TOP, NOTCH_H = 0.21, 0.09, 0.14    # nose notch (half-widths, height)
VIS_Y0 = 0.56                   # back face, buried in the front facet
VIS_Y1 = SKIN + 0.40            # 1.028: the visor face, 0.40 proud of the skin
VIS_BEVEL = 0.06                # chamfer round the visor face

TEMPLE_X = (0.47, 0.73)         # the side blocks linking visor and strap (mirrored)
TEMPLE_Y = (0.05, 0.75)
TEMPLE_HH = 0.23

RIM_OUT, RIM_IN = 0.10, 0.14    # GoggleRim: inset range from the visor outline
PANEL_IN = 0.125                # dark panel: its edge hides under the rim
LENS_IN = 0.18                  # glowing lenses: 0.04 of dark border inside the rim
BRIDGE_HW = 0.05                # half of the dark bridge between the lenses

RIM_Y = (VIS_Y1 - 0.01, VIS_Y1 + 0.045)
PANEL_Y = (VIS_Y1 - 0.015, VIS_Y1 + 0.02)
LENS_Y = (VIS_Y1 + 0.005, VIS_Y1 + 0.04)

# side light on the NEGATIVE-x side (the tile's right; +X renders on the left)
LIGHT_LO = (-0.78, 0.15, -0.13)     # z relative to ZC
LIGHT_HI = (-0.60, 0.49, 0.13)
STRIPE_LO = (-0.80, 0.36, -0.10)
STRIPE_HI = (-0.77, 0.43, 0.10)

# ------------------------------------------------------------------ speckles
STUD_SKIP = (0.56, 0.78)                    # rows the goggle assembly covers
STUD_EXTRA = [(0.81, 0), (0.81, 3), (0.81, 6)]   # ... re-seated above the goggles


# ------------------------------------------------------------------ 2-D outline maths
def _goggle_outline(hw=VIS_HW, hh=VIS_HH, c=VIS_CORNER,
                    nb=NOTCH_BOT, nt=NOTCH_TOP, nh=NOTCH_H):
    """The visor's front silhouette in (x, z-ZC), counter-clockwise with x to the
    right and z up: a corner-cut rectangle with the nose notch biting up into the
    middle of its lower edge."""
    return [(-hw + c, -hh), (-nb, -hh), (-nt, -hh + nh), (nt, -hh + nh), (nb, -hh),
            (hw - c, -hh), (hw, -hh + c), (hw, hh - c), (hw - c, hh),
            (-hw + c, hh), (-hw, hh - c), (-hw, -hh + c)]


def _inset(pts, d):
    """Offset a counter-clockwise simple polygon INWARD by `d` with mitred corners.
    Same vertex count and order, so two insets can be lofted into each other."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        e1 = (p1[0] - p0[0], p1[1] - p0[1])
        e2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*e1), math.hypot(*e2)
        n1 = (-e1[1] / l1, e1[0] / l1)          # left of travel = inside (CCW)
        n2 = (-e2[1] / l2, e2[0] / l2)
        s = d / (1.0 + n1[0] * n2[0] + n1[1] * n2[1])
        out.append((p1[0] + (n1[0] + n2[0]) * s, p1[1] + (n1[1] + n2[1]) * s))
    return out


def _clip_x(pts, x0):
    """Keep the part of a polygon with x >= x0 (Sutherland-Hodgman, one edge)."""
    out = []
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        ina, inb = a[0] >= x0, b[0] >= x0
        if ina:
            out.append(a)
        if ina != inb:
            t = (x0 - a[0]) / (b[0] - a[0])
            out.append((x0, a[1] + t * (b[1] - a[1])))
    return out


def _mirror_x(pts):
    """Mirror an outline across x = 0, reversed so it stays counter-clockwise."""
    return [(-x, z) for (x, z) in reversed(pts)]


def lens_outlines():
    """The two glowing lenses: the visor outline inset to the lens line, split by the
    dark bridge.  Returns [+X lens (screen-left), -X lens (screen-right)]."""
    left = _clip_x(_inset(_goggle_outline(), LENS_IN), BRIDGE_HW)
    return [left, _mirror_x(left)]


def pivot_matrix(D):
    """Tilt TILT degrees about X through (0, 0, ZC): T(p) @ R @ T(-p) = T(p - R p) @ R."""
    a = math.radians(TILT)
    return D.place((0.0, math.sin(a) * ZC, ZC * (1.0 - math.cos(a))),
                   D.rot_euler(TILT, 0.0, 0.0))


def _cross0(a, b):
    """Where segment a-b crosses x = 0."""
    t = (0.0 - a[0]) / (b[0] - a[0])
    return (0.0, a[1] + t * (b[1] - a[1]))


def _right_chain(pts):
    """The x > 0 run of a counter-clockwise outline that is symmetric about x = 0:
    from where it crosses x = 0 heading right (the bottom, through the notch) to where
    it crosses back (the top edge), both crossing points included."""
    n = len(pts)
    i = next(k for k in range(n) if pts[k][0] < 0.0 < pts[(k + 1) % n][0])
    chain = [_cross0(pts[i], pts[(i + 1) % n])]
    j = (i + 1) % n
    while pts[j][0] > 0.0:
        chain.append(pts[j])
        j = (j + 1) % n
    chain.append(_cross0(pts[j - 1], pts[j]))
    return chain


def half_ring(outer, inner):
    """The x >= 0 half of the band between two nested outlines as ONE simple polygon
    (a 'C'): up the outer outline's right half, across the seam at x = 0, back down
    the inner one.  D.prism cannot make a hole, so the frame is two mirrored halves."""
    return _right_chain(outer) + list(reversed(_right_chain(inner)))


# ------------------------------------------------------------------ placement
def visor_frame(D, M):
    """Matrix for D.prism in the visor plane: its local (x, y) -> world (x, ZC + y),
    its extrusion axis z -> world -y (rot_euler(90) maps (x, y, z) to (x, -z, y)),
    then the goggle tilt M on top."""
    return M @ D.place((0.0, 0.0, ZC), D.rot_euler(90.0, 0.0, 0.0))


def _plate(D, bm, pts, y0, y1, frame):
    """Extrude an (x, z-ZC) outline through world y0 .. y1 (y0 < y1).  The prism's
    first ring (its z0 = -y1) is the FRONT face."""
    return D.prism(bm, pts, -y1, -y0, matrix=frame)


def _zbox(D, bm, lo, hi, bevel):
    """beveled_box with z given relative to the goggle centre."""
    return D.beveled_box(bm, (lo[0], lo[1], ZC + lo[2]), (hi[0], hi[1], ZC + hi[2]),
                         bevel=bevel)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R
    M = pivot_matrix(D)
    F = visor_frame(D, M)
    vis = _goggle_outline()

    # ---- the cucumber -----------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # standard speckles minus the goggle band, that row re-seated above the goggles
    slots = [(zf, f) for (zf, f)
             in D.cuke_stud_slots(rows=7, per_row=3, z0=0.11, z1=0.90, seed=7)
             if not (STUD_SKIP[0] <= zf <= STUD_SKIP[1])] + STUD_EXTRA
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, size=0.28, rise=0.055, slots=slots)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- goggles: strap + visor + the two side temples, one lavender part ----
    bm = bmesh.new()
    rs = STRAP_IN / math.cos(math.pi / 8.0)            # lathe radius = circumradius
    vs = D.lathe(bm, [(rs - STRAP_CH, ZC - STRAP_HH), (rs, ZC - STRAP_HH + STRAP_CH),
                      (rs, ZC + STRAP_HH - STRAP_CH), (rs - STRAP_CH, ZC + STRAP_HH)],
                 segs=8, phase=D.cuke_phase(), cap=True)
    for sx in (1.0, -1.0):
        x0, x1 = sorted((sx * TEMPLE_X[0], sx * TEMPLE_X[1]))
        vs += _zbox(D, bm, (x0, TEMPLE_Y[0], -TEMPLE_HH), (x1, TEMPLE_Y[1], TEMPLE_HH),
                    bevel=0.05)
    D.xform(bm, vs, M)
    # the visor: the notched outline extruded y 0.56 .. 1.03 (already tilted by F),
    # then its FRONT edges chamfered the way beveled_box chamfers a box
    vs = _plate(D, bm, vis, VIS_Y0, VIS_Y1, F)
    front = set(vs[:len(vis)])
    edges = [e for e in bm.edges if e.verts[0] in front and e.verts[1] in front]
    bmesh.ops.bevel(bm, geom=edges, offset=VIS_BEVEL, segments=1, profile=0.5,
                    affect='EDGES', clamp_overlap=True)
    D.new_obj("Goggles", bm, c, D.C("neo_goggle"), rbx_material="SmoothPlastic")

    # ---- the darker frame line round the lens window: two mirrored 'C' halves --
    bm = bmesh.new()
    right = half_ring(_inset(vis, RIM_OUT), _inset(vis, RIM_IN))
    for pts in (right, _mirror_x(right)):
        _plate(D, bm, pts, RIM_Y[0], RIM_Y[1], F)
    D.new_obj("GoggleRim", bm, c, D.C("neo_goggle_dk"), rbx_material="SmoothPlastic")

    # ---- the dark lens panel: border, bridge and nose notch in one plate ----
    bm = bmesh.new()
    _plate(D, bm, _inset(vis, PANEL_IN), PANEL_Y[0], PANEL_Y[1], F)
    D.new_obj("Lenses", bm, c, D.C("neo_lens"), rbx_material="SmoothPlastic")

    # ---- the two glowing lenses ------------------------------------------------
    bm = bmesh.new()
    for lens in lens_outlines():
        _plate(D, bm, lens, LENS_Y[0], LENS_Y[1], F)
    D.new_obj("LensGlow", bm, c, D.C("neo_magenta"), rbx_material="Neon", emit=0.6)

    # ---- the side light (negative x only) and its cyan highlight --------------
    bm = bmesh.new()
    vs = _zbox(D, bm, LIGHT_LO, LIGHT_HI, bevel=0.03)
    D.xform(bm, vs, M)
    D.new_obj("SideLight", bm, c, D.C("neon_blue"), rbx_material="Neon", emit=0.6)

    bm = bmesh.new()
    vs = _zbox(D, bm, STRIPE_LO, STRIPE_HI, bevel=0.01)
    D.xform(bm, vs, M)
    D.new_obj("SideLightHi", bm, c, D.C("neo_cyan"), rbx_material="Neon", emit=0.6)

    return c
