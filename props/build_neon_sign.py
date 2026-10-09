"""Three neon signs in one collection: a wall-mounted OPEN box sign, a THIS WAY arrow
sign on a post, and a two-post CUCUMBER marquee.  All face +Y, all lit with tube letters
standing proud of a near-black backing panel."""
import bmesh, math

COLLECTION = "NeonSign"

NOTES = (
    "Three variants side by side along X, each built about its own origin and then offset "
    "(A x=+9.8, B x=+2.3, C x=-7.4), so a variant drops into a game by name prefix and "
    "lands at its own origin.  Footprints / heights: A_OpenSign 4.7 wide x 2.4 tall "
    "(the sign box itself is 4.7 x 1.9, z 0.5-2.4); B_ArrowSign 4.0 wide x 4.8 tall on a "
    "1.1-wide hex foot; C_Marquee 8.0 wide x 6.25 tall on two poles 6.6 apart.  Whole "
    "line-up spans x -11.4 to +12.2 with 3.2 studs of air A-B and 3.7 B-C.  "
    "Nothing goes below z=0.\n"
    "A is a WALL sign: the two metal_dark struts at its back are the standoff channel it "
    "bolts to, and they run to the floor only so the prop can stand on its own for the "
    "render - delete A_Struts and bolt A_Hardware's two brackets to a wall if you are "
    "hanging it.  B's arrow points toward -x, i.e. to the RIGHT of a player facing the "
    "sign; mirror the whole variant in X to send them left.  C's stepped crown is "
    "its own part, C_Crown: the profile runs 0.9 studs down behind the panel top so "
    "it reads as one solid mass, and it is matte steel so it never out-shines the "
    "tubes.\n"
    "Every glow part is rbx_material Neon: A_Border + A_Text, B_Text + B_Arrow + B_Bulbs, "
    "C_Text + C_Bulbs.  To animate, flicker A_Text, or chase B_Bulbs / C_Bulbs by cycling "
    "their Neon parts' Transparency - the bulbs are separate little cylinders in one mesh, "
    "so split that mesh per bulb first if you want a running chase."
)

VARIANTS = {
    "A": {"name": "OpenSign", "x": 9.8},    # wall box sign, 4.7 x 2.4
    "B": {"name": "ArrowSign", "x": 2.3},   # post sign, 4.0 x 4.8
    "C": {"name": "Marquee", "x": -7.4},    # two-post marquee, 8.0 x 6.25
}


def _finish(D, name, bm, c, ox, hexcol, **kw):
    """Slide a finished variant part to its lane on X, then hand it to new_obj."""
    if ox:
        D.translate(bm, list(bm.verts), (ox, 0.0, 0.0))
    return D.new_obj(name, bm, c, hexcol, **kw)


def _bulb(D, bm, x, z, y0=0.12, y1=0.34, r=0.12):
    """One marquee bulb: a stubby domed cylinder poking out of the panel toward +Y."""
    return D.cyl(bm, (x, y0, z), (x, y1, z), r, segs=5, r2=r * 0.56)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    dark = D.C("plastic_black")      # backing panels - the darkest value, so tubes pop
    steel = D.C("metal_mid")         # brackets, poles, crown
    iron = D.C("metal_dark")         # struts, conduit, braces (a step darker than steel)
    pink = D.C("neon_pink")
    cyan = D.C("neon_cyan")
    lime = D.C("neon_lime")
    amber = D.C("neon_yellow")
    orange = D.C("neon_orange")

    PANEL = dict(rbx_material="SmoothPlastic", roughness=0.5)
    BRIGHT = dict(rbx_material="Metal", metallic=0.6, roughness=0.4)
    DULL = dict(rbx_material="Metal", metallic=0.45, roughness=0.5)
    MATTE = dict(rbx_material="Metal", metallic=0.22, roughness=0.66)   # up-facing steel

    # =========================================================== A  OpenSign
    # A wall box sign: 4.7 x 1.9 panel, cyan tube border, pink OPEN standing off the face,
    # hung on two back struts with a transformer and conduit on the -x one only.
    ox = VARIANTS["A"]["x"]

    bm = bmesh.new()
    D.beveled_box(bm, (-2.35, -0.20, 0.50), (2.35, 0.14, 2.40), bevel=0.09)
    _finish(D, "A_Panel", bm, c, ox, dark, **PANEL)

    bm = bmesh.new()                                  # border tube, flush on the face
    loop = [(2.03, 0.20, 0.78), (2.03, 0.20, 2.12), (-2.03, 0.20, 2.12),
            (-2.03, 0.20, 0.78), (2.03, 0.20, 0.78)]
    D.tube(bm, loop, [0.07] * len(loop), segs=4)
    _finish(D, "A_Border", bm, c, ox, cyan, rbx_material="Neon", emit=1.15)

    bm = bmesh.new()                                  # OPEN, 0.15 proud of the panel face
    D.stroke_text(bm, "OPEN", (0.0, 0.255, 1.10), height=0.70, radius=0.075, segs=4)
    _finish(D, "A_Text", bm, c, ox, pink, rbx_material="Neon", emit=1.25)

    bm = bmesh.new()                                  # the two standoff channels
    for sx in (-1.42, 1.42):
        D.box(bm, (sx - 0.16, -0.74, 0.00), (sx + 0.16, -0.38, 2.28))
    _finish(D, "A_Struts", bm, c, ox, iron, **DULL)

    bm = bmesh.new()                                  # brackets + gussets + gear
    for sx in (-1.42, 1.42):
        D.box(bm, (sx - 0.13, -0.44, 1.86), (sx + 0.13, -0.16, 2.12))
        D.wedge(bm, (sx - 0.09, -0.42, 1.46), (sx + 0.09, -0.20, 1.86), rise='-Y')
    D.beveled_box(bm, (-1.96, -0.96, 0.18), (-1.06, -0.42, 0.76), bevel=0.07)
    D.tube(bm, [(-1.42, -0.68, 0.76), (-1.42, -0.50, 1.50), (-1.42, -0.26, 1.84)],
           [0.075] * 3, segs=4)
    _finish(D, "A_Hardware", bm, c, ox, steel, **BRIGHT)

    # =========================================================== B  ArrowSign
    # 4.0 x 3.2 rounded panel at z 1.6-4.8 on one post; THIS / WAY stacked on two lines at
    # A-and-C stroke weight, and a fat chevron below them pointing -x (the viewer's right).
    # "THIS WAY" on ONE line at that weight would be 5.6 studs of text on a 4.0 panel, and
    # widening the panel would eat the 3-stud gap to its neighbours - hence two lines.
    ox = VARIANTS["B"]["x"]

    bm = bmesh.new()
    D.prism(bm, D.rounded_rect_pts(4.0, 3.2, 0.34, segs=3), -0.13, 0.13,
            matrix=D.place((0.0, 0.0, 3.20), D.rot_euler(rx=90)))
    _finish(D, "B_Panel", bm, c, ox, dark, **PANEL)

    bm = bmesh.new()
    D.cyl(bm, (0.0, -0.16, 0.00), (0.0, -0.16, 2.05), 0.24, segs=8)
    D.prism(bm, D.ngon_pts(6, 0.56, phase=0.26, center=(0.0, -0.16)), 0.0, 0.20)
    _finish(D, "B_Post", bm, c, ox, steel, **BRIGHT)

    bm = bmesh.new()                                  # 2.70 and 1.98 wide on a 4.0 panel
    D.stroke_text(bm, "THIS", (0.0, 0.21, 3.82), height=0.55, radius=0.075, segs=4)
    D.stroke_text(bm, "WAY", (0.0, 0.21, 3.12), height=0.55, radius=0.075, segs=4)
    _finish(D, "B_Text", bm, c, ox, cyan, rbx_material="Neon", emit=1.2)

    bm = bmesh.new()                                  # chevron: +Y tip rotated onto -X
    chev = [(-p[1], p[0]) for p in D.chevron_pts(0.92, 1.05, 0.34)]
    D.prism(bm, chev, -0.09, 0.09, matrix=D.place((0.355, 0.22, 2.51), D.rot_euler(rx=90)))
    _finish(D, "B_Arrow", bm, c, ox, orange, rbx_material="Neon", emit=1.2)

    bm = bmesh.new()                                  # even 10-bulb perimeter loop
    for bz in (4.56, 1.84):
        for bx in (-1.76, -0.59, 0.59, 1.76):
            _bulb(D, bm, bx, bz, y0=0.10, y1=0.30, r=0.11)
    for bx in (-1.76, 1.76):
        _bulb(D, bm, bx, 3.20, y0=0.10, y1=0.30, r=0.11)
    _finish(D, "B_Bulbs", bm, c, ox, amber, rbx_material="Neon", emit=1.2)

    bm = bmesh.new()                                  # junction box, conduit, one clip
    D.box(bm, (-0.52, -0.60, 0.92), (-0.14, -0.26, 1.42))
    D.tube(bm, [(-0.33, -0.43, 1.42), (-0.30, -0.36, 1.92), (-0.22, -0.17, 2.42)],
           [0.065] * 3, segs=4)
    D.box(bm, (-0.42, -0.47, 1.70), (-0.20, -0.27, 1.82))
    _finish(D, "B_Gear", bm, c, ox, iron, **DULL)

    # =========================================================== C  Marquee
    # 8.0 x 2.0 panel at z 2.95-4.95 on two poles, stepped crown to 6.25, bulb border,
    # X brace under the panel, transformer + conduit on the +x pole only.
    ox = VARIANTS["C"]["x"]

    bm = bmesh.new()
    D.prism(bm, D.rounded_rect_pts(8.0, 2.0, 0.30, segs=2), -0.15, 0.15,
            matrix=D.place((0.0, 0.0, 3.95), D.rot_euler(rx=90)))
    _finish(D, "C_Panel", bm, c, ox, dark, **PANEL)

    bm = bmesh.new()
    D.stroke_text(bm, "CUCUMBER", (0.0, 0.28, 3.62), height=0.66, radius=0.078, segs=4)
    _finish(D, "C_Text", bm, c, ox, lime, rbx_material="Neon", emit=1.25)

    bm = bmesh.new()
    for bx in (-3.00, -1.50, 0.00, 1.50, 3.00):
        _bulb(D, bm, bx, 4.70)
        _bulb(D, bm, bx, 3.20)
    for bx in (-3.72, 3.72):
        _bulb(D, bm, bx, 3.95)
    _finish(D, "C_Bulbs", bm, c, ox, amber, rbx_material="Neon", emit=1.2)

    bm = bmesh.new()                                  # stepped crown, one buried mass
    # Profile y is measured from the PANEL TOP (z 4.95): it runs 0.90 down behind the
    # panel so the crown reads as one solid block, and the tiers stand 0.60 / 0.95 / 1.30
    # proud of it so the outer step is a real shoulder.  x stays inside the 8.0 panel.
    crown = [(-3.90, -0.90), (-3.90, 0.60), (-2.62, 0.60), (-2.62, 0.95), (-1.24, 0.95),
             (-1.24, 1.30), (1.24, 1.30), (1.24, 0.95), (2.62, 0.95), (2.62, 0.60),
             (3.90, 0.60), (3.90, -0.90)]
    # prism z maps to -y, so -0.06..0.30 puts the slab at y -0.30..0.06 - tucked behind
    # the panel face (0.15) and clear of the bulbs (y 0.12+), so the buried half is hidden.
    D.prism(bm, crown, -0.06, 0.30, matrix=D.place((0.0, 0.0, 4.95), D.rot_euler(rx=90)))
    _finish(D, "C_Crown", bm, c, ox, steel, **MATTE)

    bm = bmesh.new()                                  # poles + feet
    for px in (-3.30, 3.30):
        D.cyl(bm, (px, -0.24, 0.00), (px, -0.24, 3.45), 0.26, segs=6)
        D.box(bm, (px - 0.46, -0.66, 0.00), (px + 0.46, 0.16, 0.26))
    _finish(D, "C_Frame", bm, c, ox, steel, **BRIGHT)

    bm = bmesh.new()                                  # X brace + transformer + conduit
    D.cyl(bm, (-3.30, -0.26, 0.62), (3.30, -0.26, 2.55), 0.10, segs=5)
    D.cyl(bm, (3.30, -0.26, 0.62), (-3.30, -0.26, 2.55), 0.10, segs=5)
    # transformer stands ON the ground and on the foot plate, a third of it inside the pole
    D.box(bm, (3.05, -0.72, 0.00), (3.80, -0.20, 0.80))
    D.tube(bm, [(3.55, -0.46, 0.80), (3.63, -0.40, 1.95), (3.46, -0.22, 3.02)],
           [0.07] * 3, segs=4)
    _finish(D, "C_Rigging", bm, c, ox, iron, **DULL)

    return c
