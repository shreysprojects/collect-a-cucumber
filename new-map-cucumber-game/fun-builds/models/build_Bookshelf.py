"""Bookshelf (Home, fun-builds 2026-09-24): a tall wooden bookshelf, 6 wide x 8 high x 1.6 deep, four
shelves of colourful books (varied heights / depths / colours, a few leaning, a stack lying flat, gold
bands and paper labels on some spines), a golden trophy on the top shelf and a potted plant on the chest-high shelf.

Behaviour contract (behaviours/server|client/Bookshelf.lua):
  Book_NN   upright books that may SLIDE OUT 0.5 stud toward the front (-Z) and back when someone reads
  Band_NN   the spine band / label of Book_NN (moves with it); not every book has one
  Lean_N / Held_N / Stack_N   leaning books, the books they lean on, flat books - never moved
  Pivot_Read   front-centre of the shelf at chest height: where the "Read a book" prompt sits
"""
import math

WOOD = "8a5a2b"
WOOD_DARK = "6b4423"
BACK = "5a3a1e"
GOLD = "f2c13d"
PAPER = "f2f0ea"

RED = "d9443c"
BLUE = "3f79d4"
YELLOW = "f2c13d"
GREEN = "5aa845"
PURPLE = "8e5bd1"
TEAL = "2f9e9e"
ORANGE = "f08a30"
PINK = "e87fa8"
NAVY = "2c3e7a"
WHITE = "f2f0ea"
BLACK = "23262c"
MAROON = "8e2f2f"
LEAF = "3f8f3a"
LEAF2 = "5aa845"
POT = "c2653a"

W, H, DEPTH = 6.0, 8.0, 1.6
INNER = 2.75            # inner faces of the side panels at x = +/-INNER
Z_BACK = 0.69           # books' backs rest against the back panel (front face at z 0.70)
SHELF_T = 0.2
FLOOR0 = 0.65           # top of the bottom deck
CAP_BOTTOM = 7.6
COMP = (CAP_BOTTOM - FLOOR0 - 3 * SHELF_T) / 4.0   # inner height of each compartment (~1.59)
GAP = 0.018


def floors():
    """Top surface y of the four shelves (bottom deck first)."""
    return [FLOOR0 + i * (COMP + SHELF_T) for i in range(4)]


class Shelf:
    def __init__(self, m):
        self.m = m
        self.n_book = 0
        self.n_lean = 0
        self.n_held = 0
        self.n_stack = 0

    def upright(self, x_left, floor, t, h, d, color, mat="SmoothPlastic", band=None, held=False):
        """A standing book whose +X (viewer's left) face is at x_left; returns the next x_left."""
        cx = x_left - t / 2
        cz = Z_BACK - d / 2
        if held:
            self.n_held += 1
            name = "Held_%d" % self.n_held
        else:
            self.n_book += 1
            name = "Book_%02d" % self.n_book
        self.m.block(name, (cx, floor - 0.01 + h / 2, cz), (t, h, d), color, mat)
        if band and not held:
            kind, bcolor = band
            front = Z_BACK - d
            if kind == "band":      # a gold ring round the spine near the top and one near the bottom -> one wide
                self.m.block("Band_%02d" % self.n_book, (cx, floor + h * 0.78, front + 0.01), (t + 0.02, 0.1, 0.06),
                             bcolor, "SmoothPlastic", collide=False, shadow=False)
            else:                   # a paper label in the middle of the spine
                self.m.block("Band_%02d" % self.n_book, (cx, floor + h * 0.55, front + 0.005),
                             (max(0.05, t * 0.62), min(0.34, h * 0.26), 0.05), bcolor, "SmoothPlastic",
                             collide=False, shadow=False)
        return x_left - t - GAP

    def row(self, x_left, floor, books):
        for b in books:
            t, h, d, color = b[:4]
            opts = b[4] if len(b) > 4 else {}
            x_left = self.upright(x_left, floor, t, h, d, color, **opts)
        return x_left

    def lean(self, support_x, floor, t, h, d, color, toward, deg, mat="SmoothPlastic"):
        """A book leaning `toward` +1 (+X, its top resting on a support face at x = support_x) or -1 (-X)."""
        a = math.radians(deg)
        cy = floor - 0.01 + (t / 2) * math.sin(a) + (h / 2) * math.cos(a)
        off = (t / 2) * math.cos(a) + (h / 2) * math.sin(a)
        cx = support_x - off if toward > 0 else support_x + off
        rz = -deg if toward > 0 else deg
        self.n_lean += 1
        self.m.block("Lean_%d" % self.n_lean, (cx, cy, Z_BACK - d / 2 - 0.02), (t, h, d), color, mat, rot=(0, 0, rz))
        # the far bottom corner (for placing whatever comes next)
        return cx - toward * ((t / 2) * math.cos(a) + (h / 2) * math.sin(a)) - toward * GAP

    def flat(self, cx, y_bottom, length, thick, d, color, yaw=0.0, mat="SmoothPlastic"):
        self.n_stack += 1
        self.m.block("Stack_%d" % self.n_stack, (cx, y_bottom + thick / 2, Z_BACK - d / 2 - 0.06), (length, thick, d),
                     color, mat, rot=(0, yaw, 0))
        return y_bottom + thick


def build(D, P):
    m = P.Model(D, "Bookshelf", category="Home")
    f0, f1, f2, f3 = floors()

    # ------------------------------------------------------------ carcass
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Side" + side, (sx * (INNER + 0.125), (CAP_BOTTOM + 0.01) / 2, 0), (0.25, CAP_BOTTOM + 0.01, DEPTH), WOOD, "Wood")
    m.block("TopCap", (0, CAP_BOTTOM + 0.12, -0.02), (6.2, 0.26, 1.7), WOOD, "Wood")
    m.block("Crown", (0, H - 0.1, -0.03), (6.44, 0.2, 1.82), WOOD_DARK, "Wood")
    m.block("Plinth", (0, 0.25, 0.02), (5.56, 0.5, 1.5), WOOD_DARK, "Wood")
    m.block("BackPanel", (0, (0.45 + CAP_BOTTOM) / 2, 0.75), (5.54, CAP_BOTTOM - 0.43, 0.1), BACK, "WoodPlanks")
    for i, fy in enumerate((f0, f1, f2, f3)):
        m.block("Shelf%d" % i, (0, fy - SHELF_T / 2, -0.05), (5.52, SHELF_T, 1.5), WOOD, "Wood")
        if i > 0:  # the bottom deck sits on the plinth: no lip
            m.block("ShelfLip%d" % i, (0, fy - SHELF_T / 2, -0.79), (5.52, SHELF_T + 0.06, 0.08), WOOD_DARK, "Wood")

    s = Shelf(m)
    x0 = INNER - 0.01

    # ------------------------------------------------------------ top shelf: trophy (viewer's left) + a row + a lean + a flat pair
    trophy(m, 1.95, f3)
    x = s.row(1.3, f3, [
        (0.38, 1.22, 1.05, RED, {"band": ("band", GOLD)}),
        (0.32, 1.34, 1.1, NAVY),
        (0.44, 1.12, 1.0, YELLOW, {"band": ("label", PAPER)}),
        (0.34, 1.3, 1.08, GREEN),
        (0.36, 1.38, 1.1, TEAL, {"held": True}),
    ])
    x = s.lean(x + GAP, f3, 0.32, 1.2, 1.0, ORANGE, toward=+1, deg=20)
    y = s.flat(-2.1, f3 - 0.01, 1.15, 0.28, 0.95, BLUE, yaw=4)
    s.flat(-2.12, y - 0.01, 1.0, 0.24, 0.85, PINK, yaw=-7)

    # ------------------------------------------------------------ eye-level shelf: a full row with a gap + a lean
    x = s.row(x0, f2, [
        (0.38, 1.3, 1.1, BLUE, {"band": ("band", GOLD)}),
        (0.34, 1.18, 1.02, RED),
        (0.44, 1.38, 1.12, BLACK, {"band": ("band", GOLD)}),
        (0.36, 1.1, 1.0, YELLOW),
        (0.4, 1.34, 1.1, GREEN, {"held": True}),
    ])
    x = s.lean(x + GAP, f2, 0.34, 1.26, 1.05, PURPLE, toward=+1, deg=22)
    s.row(x - 0.1, f2, [
        (0.36, 1.36, 1.1, ORANGE),
        (0.42, 1.22, 1.06, MAROON),
        (0.34, 1.3, 1.02, TEAL, {"band": ("label", PAPER)}),
        (0.4, 1.16, 1.0, WHITE),
        (0.36, 1.28, 1.06, PINK),
        (0.44, 1.4, 1.12, NAVY),
    ])

    # ------------------------------------------------------------ chest shelf: a row + a lean + the plant pot
    x = s.row(x0, f1, [
        (0.4, 1.28, 1.08, GREEN, {"band": ("label", PAPER)}),
        (0.34, 1.36, 1.1, RED),
        (0.32, 1.14, 1.0, BLUE, {"band": ("band", GOLD)}),
        (0.44, 1.24, 1.06, YELLOW),
        (0.36, 1.32, 1.08, PURPLE),
        (0.38, 1.34, 1.1, NAVY, {"held": True}),
    ])
    x = s.lean(x + GAP, f1, 0.32, 1.18, 1.0, PINK, toward=+1, deg=24)
    plant(m, (x - INNER) / 2, f1)

    # ------------------------------------------------------------ bottom shelf: a flat stack + big books + a lean
    y = s.flat(2.05, f0 - 0.01, 1.3, 0.3, 1.05, MAROON, yaw=-3, mat="Leather")
    y = s.flat(2.02, y - 0.01, 1.2, 0.26, 1.0, TEAL, yaw=5)
    s.flat(2.06, y - 0.01, 1.08, 0.24, 0.92, YELLOW, yaw=-8)
    s.row(1.3, f0, [
        (0.46, 1.48, 1.15, NAVY, {"band": ("band", GOLD)}),
        (0.42, 1.4, 1.12, RED, {"mat": "Leather"}),
        (0.48, 1.5, 1.15, GREEN),
        (0.4, 1.36, 1.1, BLACK),
        (0.46, 1.44, 1.12, PURPLE),
        (0.44, 1.46, 1.14, BLUE),
    ])
    s.lean(-INNER + 0.01, f0, 0.42, 1.34, 1.1, WHITE, toward=-1, deg=14)

    m.pivot("Read", (0, f1 + 1.2, -0.95))
    m.attr("Cost", 500)
    m.attr("DisplayName", "Bookshelf")
    return m.finish()


def trophy(m, cx, floor):
    z = -0.12
    m.block("TrophyBase", (cx, floor + 0.13, z), (0.8, 0.28, 0.62), BLACK, "SmoothPlastic")
    m.block("TrophyPlaque", (cx, floor + 0.13, z - 0.31), (0.46, 0.13, 0.05), GOLD, "Metal", collide=False)
    m.cyl("TrophyStem", (cx, floor + 0.25, z), (cx, floor + 0.66, z), 0.16, GOLD, "Metal", collide=False)
    m.ellipsoid("TrophyBowl", (cx, floor + 0.78, z), (0.66, 0.4, 0.66), GOLD, "Metal", collide=False)
    m.cyl("TrophyCup", (cx, floor + 0.78, z), (cx, floor + 1.18, z), 0.66, GOLD, "Metal", collide=False)
    for side, sx in (("L", 1), ("R", -1)):
        m.disc("TrophyHandle" + side, (cx + sx * 0.38, floor + 0.98, z), (0, 0, 1), 0.34, 0.07, GOLD, "Metal",
               collide=False)


def plant(m, cx, floor):
    z = -0.15
    m.cyl("PlantPot", (cx, floor - 0.01, z), (cx, floor + 0.56, z), 0.78, POT, "SmoothPlastic")
    m.cyl("PlantRim", (cx, floor + 0.48, z), (cx, floor + 0.66, z), 0.9, POT, "SmoothPlastic")
    m.ellipsoid("PlantLeafUp", (cx + 0.02, floor + 1.02, z), (0.34, 0.8, 0.26), LEAF, "SmoothPlastic",
                collide=False, rot=(0, 0, -6))
    m.ellipsoid("PlantLeafL", (cx + 0.3, floor + 0.9, z - 0.06), (0.3, 0.66, 0.24), LEAF2, "SmoothPlastic",
                collide=False, rot=(0, 0, -40))
    m.ellipsoid("PlantLeafR", (cx - 0.3, floor + 0.88, z + 0.05), (0.3, 0.62, 0.24), LEAF2, "SmoothPlastic",
                collide=False, rot=(0, 0, 42))
