"""Three garden lanterns in one line-up: a wrought-iron post lantern, a paper lantern
hanging off a shepherd's hook, and a low hexagonal garden lantern.  All face +Y."""
import bmesh, math

COLLECTION = "Lantern"
NOTES = (
    "Three separable lanterns, name-prefixed A_/B_/C_, standing along X with ~3.3 studs "
    "of air between them.  A PostLantern (x -5.2, 4.62 tall, 1.44 sq stone base) is a "
    "path/driveway lamp - the scroll bracket is deliberately on ONE side only, at "
    "negative x (the viewer's right).  B PaperLantern (x 0.0, 3.64 tall) hangs off a "
    "shepherd's hook: the post foot is at x +0.42 of its origin and the ball hangs at "
    "x -0.30, so the pair balances about the origin.  C GardenLantern (x +4.6, 1.32 "
    "tall, 1.04 across the flats) is a border/step light.  PIVOTS gives the point to "
    "parent a PointLight to in each, plus B's hang point if you want the ball to swing. "
    "Glass is tinted at transparency 0.58, the paper 0.25; every glow is a two-shell "
    "Neon flame - a saturated orange body with a white-hot tip rising out of it - so "
    "all three read switched ON from 40 studs."
)

PIVOTS = {"A_Light": (-5.20, 0.00, 3.46),      # inside the four-pane housing
          "B_Hang":  (-0.30, 0.00, 3.34),      # hook tip the ball swings from
          "B_Light": (-0.30, 0.00, 2.42),      # centre of the paper ovoid
          "C_Light": (4.60, 0.00, 0.64)}       # inside the hex housing

VARIANTS = {"A": {"name": "PostLantern",   "x": -5.2},
            "B": {"name": "PaperLantern",  "x":  0.0},
            "C": {"name": "GardenLantern", "x":  4.6}}

SQ = math.pi / 4.0          # lathe phase that turns a segs=4 revolve into a square post


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    _post_lantern(D, c, VARIANTS["A"]["x"])
    _paper_lantern(D, c, VARIANTS["B"]["x"])
    _garden_lantern(D, c, VARIANTS["C"]["x"])
    return c


# ---------------------------------------------------------------- shared look
def _stone(D, name, bm, c):
    return D.new_obj(name, bm, c, D.C("stone_mid"), rbx_material="Slate", roughness=0.88)


def _iron(D, name, bm, c):
    return D.new_obj(name, bm, c, D.C("iron_dark"), rbx_material="Metal",
                     metallic=0.35, roughness=0.55)


def _brass(D, name, bm, c):
    return D.new_obj(name, bm, c, D.C("brass"), rbx_material="Metal",
                     metallic=0.7, roughness=0.32)


def _glass(D, name, bm, c):
    """Tinted, and darker than the flame behind it - a pale pane over a pale glow was
    the whole reason the old lanterns read as switched off."""
    return D.new_obj(name, bm, c, D.C("glass_tint"), rbx_material="Glass",
                     transparency=0.58, roughness=0.15)


# ---------------------------------------------------------------- A: post lantern
def _post_lantern(D, c, X):
    """Square tapered iron post on a stepped stone base, scroll bracket on one side,
    four-pane housing with a peaked brass cap and a finial spike.  4.62 studs tall."""

    # stepped stone base - two chamfered slabs, the wide one on the ground
    bm = bmesh.new()
    D.beveled_box(bm, (X - 0.72, -0.72, 0.00), (X + 0.72, 0.72, 0.20), bevel=0.07)
    D.beveled_box(bm, (X - 0.55, -0.55, 0.20), (X + 0.55, 0.55, 0.40), bevel=0.06)
    _stone(D, "A_Base", bm, c)

    # all the ironwork in one mesh: plinth, tapered post, scroll, housing frame
    bm = bmesh.new()
    D.beveled_box(bm, (X - 0.36, -0.36, 0.38), (X + 0.36, 0.36, 0.56), bevel=0.05)
    # tapered square post: a 4-segment lathe phased 45 deg so its faces sit square to XY
    D.lathe(bm, [(0.30, 0.00), (0.30, 0.16), (0.21, 0.30), (0.145, 2.20), (0.19, 2.28)],
            segs=4, phase=SQ, matrix=D.place((X, 0.0, 0.52)))
    # scroll bracket - ONE volute, curling off the -x side (screen right from the front)
    D.tube(bm, [(X - 0.10, 0.0, 2.44), (X - 0.38, 0.0, 2.40), (X - 0.56, 0.0, 2.24),
                (X - 0.56, 0.0, 2.02), (X - 0.38, 0.0, 1.94), (X - 0.30, 0.0, 2.08)],
           [0.085, 0.080, 0.072, 0.065, 0.058, 0.050], segs=4)
    # housing floor tray, four corner mullions, top rail
    D.lathe(bm, [(0.26, 0.00), (0.46, 0.12), (0.46, 0.24), (0.38, 0.32)],
            segs=4, phase=SQ, matrix=D.place((X, 0.0, 2.74)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            D.box(bm, (X + sx * 0.30 - 0.048, sy * 0.30 - 0.048, 3.02),
                      (X + sx * 0.30 + 0.048, sy * 0.30 + 0.048, 3.88))
    D.lathe(bm, [(0.38, 0.00), (0.48, 0.08), (0.48, 0.20), (0.40, 0.28)],
            segs=4, phase=SQ, matrix=D.place((X, 0.0, 3.82)))
    # burner disc on the tray floor (top face z 3.06) so the flame rises off a wick
    D.cyl(bm, (X, 0.0, 3.06), (X, 0.0, 3.11), 0.14, segs=8)
    _iron(D, "A_Iron", bm, c)

    # four glass panes, tucked behind the corner mullions
    bm = bmesh.new()
    for sy in (-1, 1):
        D.box(bm, (X - 0.27, sy * 0.31 - 0.025, 3.06), (X + 0.27, sy * 0.31 + 0.025, 3.84))
    for sx in (-1, 1):
        D.box(bm, (X + sx * 0.31 - 0.025, -0.27, 3.06), (X + sx * 0.31 + 0.025, 0.27, 3.84))
    _glass(D, "A_Glass", bm, c)

    # the flame the housing exists to show off: a broad-bottomed orange body standing ON
    # the burner, with a white-hot tip rising out of its mouth
    bm = bmesh.new()
    D.lathe(bm, [(0.13, 0.00), (0.16, 0.20), (0.12, 0.40)],
            segs=8, matrix=D.place((X, 0.0, 3.11)))
    D.new_obj("A_Flame", bm, c, D.C("flame_mid"), rbx_material="Neon", emit=0.9)

    bm = bmesh.new()
    D.lathe(bm, [(0.11, 0.00), (0.095, 0.10), (0.05, 0.22), (0.00, 0.33)],
            segs=6, matrix=D.place((X, 0.0, 3.40)))
    D.new_obj("A_FlameTip", bm, c, D.C("flame_core"), rbx_material="Neon", emit=1.3)

    # peaked cap + knobbed finial spike
    bm = bmesh.new()
    D.pyramid(bm, (X, 0.0, 4.06), 1.00, 0.38)
    D.lathe(bm, [(0.00, 0.00), (0.12, 0.04), (0.12, 0.10), (0.055, 0.18), (0.00, 0.30)],
            segs=4, phase=SQ, matrix=D.place((X, 0.0, 4.32)))
    _brass(D, "A_Cap", bm, c)


# ---------------------------------------------------------------- B: paper lantern
def _paper_lantern(D, c, X):
    """Shepherd's hook with a ribbed paper ovoid and a cloth tassel hanging off it.
    3.64 studs tall; the tassel bottoms out at z 1.38."""
    PX, LX = X + 0.42, X - 0.30          # post foot x, hanging-ball x

    bm = bmesh.new()
    D.beveled_box(bm, (PX - 0.44, -0.44, 0.00), (PX + 0.44, 0.44, 0.20), bevel=0.06)
    _stone(D, "B_Base", bm, c)

    bm = bmesh.new()
    D.cyl(bm, (PX, 0.0, 0.16), (PX, 0.0, 0.36), 0.15, segs=6)          # foot collar
    D.tube(bm, [(PX, 0.0, 0.12), (PX, 0.0, 2.92), (PX - 0.04, 0.0, 3.32),
                (X + 0.16, 0.0, 3.56), (X - 0.14, 0.0, 3.54), (LX, 0.0, 3.34)],
           [0.09, 0.09, 0.085, 0.080, 0.075, 0.070], segs=5)           # the hook
    D.cyl(bm, (LX, 0.0, 3.34), (LX, 0.0, 3.08), 0.035, segs=4)         # short hanger
    _iron(D, "B_Iron", bm, c)

    # The paper ovoid - taller than it is wide (1.00 x 1.28) like a real chochin, and the
    # accordion ribbing is the paper's OWN geometry: the radius saw-tooths in and out by
    # ~0.03 up the side so the ridges self-shade.  The old floating iron hoops are gone.
    bm = bmesh.new()
    D.lathe(bm, [(0.000, 0.00), (0.230, 0.07), (0.395, 0.19), (0.368, 0.26),
                 (0.455, 0.38), (0.428, 0.45), (0.492, 0.57), (0.463, 0.64),
                 (0.500, 0.75), (0.470, 0.82), (0.430, 0.94), (0.330, 1.10),
                 (0.180, 1.21), (0.000, 1.28)],
            segs=12, matrix=D.place((LX, 0.0, 1.78)))
    D.new_obj("B_Paper", bm, c, D.C("canvas"), rbx_material="Fabric",
              transparency=0.25, roughness=0.85)

    # two-shell glow, same as A: orange body, white-hot tip out of the top
    bm = bmesh.new()
    D.lathe(bm, [(0.17, 0.00), (0.21, 0.22), (0.15, 0.44)],
            segs=8, matrix=D.place((LX, 0.0, 2.10)))
    D.new_obj("B_Core", bm, c, D.C("flame_mid"), rbx_material="Neon", emit=0.9)

    bm = bmesh.new()
    D.lathe(bm, [(0.135, 0.00), (0.115, 0.12), (0.06, 0.26), (0.00, 0.38)],
            segs=6, matrix=D.place((LX, 0.0, 2.42)))
    D.new_obj("B_CoreTip", bm, c, D.C("flame_core"), rbx_material="Neon", emit=1.3)

    # brass top cap and bottom ring - 12 segments so the flanges follow the paper's
    # silhouette instead of poking hexagonal corners through it
    bm = bmesh.new()
    D.lathe(bm, [(0.26, 0.00), (0.27, 0.06), (0.16, 0.16), (0.00, 0.22)],
            segs=12, matrix=D.place((LX, 0.0, 2.96)))
    D.lathe(bm, [(0.00, 0.00), (0.14, 0.06), (0.24, 0.16), (0.22, 0.22)],
            segs=12, matrix=D.place((LX, 0.0, 1.68)))
    _brass(D, "B_Brass", bm, c)

    # soft cloth tassel: a thin cord and a blunt, ROUNDED drop - no gold spike, which is
    # what turned the whole variant into a spinning top
    bm = bmesh.new()
    D.cyl(bm, (LX, 0.0, 1.74), (LX, 0.0, 1.54), 0.03, segs=5)
    D.lathe(bm, [(0.000, 0.00), (0.062, 0.04), (0.090, 0.10), (0.070, 0.16),
                 (0.032, 0.19)],
            segs=6, matrix=D.place((LX, 0.0, 1.38)))
    D.new_obj("B_Tassel", bm, c, D.C("cloth_cream"), rbx_material="Fabric",
              roughness=0.85)


# ---------------------------------------------------------------- C: garden lantern
def _garden_lantern(D, c, X):
    """Low hexagonal ground lantern: stone plinth, six panes, flared pagoda cap.  1.32
    studs tall.  Hexagons are phased so a flat face - not a corner - looks at +Y."""

    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(6, 0.52), 0.00, 0.18, matrix=D.place((X, 0.0, 0.0)))
    D.prism(bm, D.ngon_pts(6, 0.42), 0.18, 0.32, matrix=D.place((X, 0.0, 0.0)))
    _stone(D, "C_Base", bm, c)

    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(6, 0.38), 0.30, 0.44, matrix=D.place((X, 0.0, 0.0)))
    D.prism(bm, D.ngon_pts(6, 0.38), 0.84, 0.94, matrix=D.place((X, 0.0, 0.0)))
    for (px, py) in D.ngon_pts(6, 0.30):
        D.cyl(bm, (X + px, py, 0.42), (X + px, py, 0.86), 0.05, segs=3)
    D.cyl(bm, (X, 0.0, 0.44), (X, 0.0, 0.48), 0.10, segs=6)      # burner under the flame
    _iron(D, "C_Iron", bm, c)

    # hollow hex glass sleeve: up the outside, across the top, back down the inside
    bm = bmesh.new()
    D.lathe(bm, [(0.31, 0.00), (0.31, 0.44), (0.27, 0.44), (0.27, 0.00)],
            segs=6, matrix=D.place((X, 0.0, 0.42)))
    _glass(D, "C_Glass", bm, c)

    bm = bmesh.new()
    D.lathe(bm, [(0.10, 0.00), (0.125, 0.12), (0.085, 0.24)],
            segs=8, matrix=D.place((X, 0.0, 0.48)))
    D.new_obj("C_Flame", bm, c, D.C("flame_mid"), rbx_material="Neon", emit=0.9)

    bm = bmesh.new()
    D.lathe(bm, [(0.08, 0.00), (0.065, 0.05), (0.035, 0.11), (0.00, 0.17)],
            segs=6, matrix=D.place((X, 0.0, 0.66)))
    D.new_obj("C_FlameTip", bm, c, D.C("flame_core"), rbx_material="Neon", emit=1.3)

    # pagoda cap: apex, down the underside to the eave, round the lip, back up the roof
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 0.17), (0.10, 0.15), (0.47, 0.00), (0.50, 0.04),
                 (0.11, 0.21), (0.00, 0.30)],
            segs=6, matrix=D.place((X, 0.0, 0.90)))
    D.lathe(bm, [(0.00, 0.00), (0.095, 0.04), (0.075, 0.09), (0.00, 0.16)],
            segs=5, matrix=D.place((X, 0.0, 1.16)))
    _brass(D, "C_Cap", bm, c)
