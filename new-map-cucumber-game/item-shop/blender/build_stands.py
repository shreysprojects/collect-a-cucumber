"""build_stands.py -- display fixtures for the two lobby carts (2026-09-23).

User: "Make the buy shop model include headbands and make it kind of display the thing its selling via
blender; make the sell shop model into a buy stand ... display the potions and boosts that we made; in
our new models lets avoid using decals ... just display physical stuff."

Everything here is PRIMITIVES ONLY (itemlib.Item: Ball / Block / Cylinder) so the build emits
out/<Key>.parts.json and install_stands.lua rebuilds each fixture out of plain Parts in Studio - no
asset upload needed (no Open Cloud key on this machine). Conventions = itemlib: 1 unit = 1 stud, Z up,
the fixture stands on z = 0 (= the cart's counter top) with its FRONT toward +Y (= the customer side);
Roblox = (x, z, -y). A viewer standing in front sees the model's +X on their LEFT, so the stroke-letter
signs lay their glyphs out from +X to -X (first letter at the largest x) - the render camera (defenselib
yaw 0 = dead-on the front) proves the reading order.

Collections / keys:
  ItemStand     wooden two-tier shelf for the 9 drop items: a raised back riser with 5 pedestals and a
                low front tray with 4 pedestals (the items themselves are cloned from
                ReplicatedStorage.Assets.Items by the installer; SLOTS lists where they stand)
  HeadbandRack  wooden riser + 12 mannequin busts (base, post, neck, egg head 1.16 wide = an R15 head)
                for the 12 headbands (cloned from ReplicatedStorage.Assets.Headbands; HEADS lists the
                head centres, the band sits BAND_ABOVE_HEAD above each)
  ItemSign      "POTIONS" / "BOOSTS" in chunky stroke letters + a mini flask and a mini bolt, replacing
                the "CUCUMBERS & PETS" letters + emoji SurfaceGuis on the cart's white side board
  MiniFlask     a hand-sized potion flask (the old A-frame image icon on the potion cart)
  MiniBolt      a lightning bolt (the old Bolt image icon on the headband cart's A-frame)
"""
import math
from itemlib import Item, rot

WOOD = "a05f35"        # the cart's tray wood (160, 95, 53)
WOOD_LIGHT = "c58a56"
GREEN = "3a7d15"       # the cart's green (58, 125, 21)
GREEN_DARK = "014700"  # the small sign letters (1, 71, 0)
BLUE = "0d69ac"        # the headband cart's blue (13, 105, 172)
CREAM = "e8dcc8"
DARK = "3b3b40"
GLASS_T = 0.35

# ------------------------------------------------------------------ item stand
# 9 slots in MODEL space (x, y, z = pedestal top); the installer stands the item clones on them
ITEM_STAND = {
    "width": 14.8, "depth": 5.2,
    "riser": {"y0": -2.6, "y1": -0.7, "h": 1.25},
    "tray": {"y0": -0.45, "y1": 1.6, "h": 0.22},
    "pedestal_r": 0.72, "pedestal_h": 0.28,
}
BACK_X = (-6.0, -3.0, 0.0, 3.0, 6.0)
FRONT_X = (-4.6, -1.55, 1.55, 4.6)


def item_stand(D):
    it = Item(D, "ItemStand")
    W = ITEM_STAND["width"]
    r = ITEM_STAND["riser"]
    t = ITEM_STAND["tray"]
    # back riser (a step the back row stands on) + a green top-front lip and end caps
    cy = (r["y0"] + r["y1"]) / 2
    it.block("Riser", (0, cy, r["h"] / 2), (W, r["y1"] - r["y0"], r["h"]), WOOD)
    it.block("RiserLip", (0, r["y1"] - 0.06, r["h"] + 0.05), (W + 0.1, 0.16, 0.12), GREEN)
    it.block("RiserCapL", (-W / 2 + 0.06, cy, r["h"] / 2 + 0.05), (0.14, r["y1"] - r["y0"] + 0.1, r["h"] + 0.1), GREEN)
    it.block("RiserCapR", (W / 2 - 0.06, cy, r["h"] / 2 + 0.05), (0.14, r["y1"] - r["y0"] + 0.1, r["h"] + 0.1), GREEN)
    # front tray: a low board with a green front lip
    ty = (t["y0"] + t["y1"]) / 2
    it.block("Tray", (0, ty, t["h"] / 2), (W, t["y1"] - t["y0"], t["h"]), WOOD)
    it.block("TrayLip", (0, t["y1"] - 0.06, t["h"] + 0.16), (W + 0.1, 0.14, 0.34), GREEN)
    it.block("TrayLipL", (-W / 2 + 0.06, ty, t["h"] + 0.16), (0.14, t["y1"] - t["y0"], 0.34), GREEN)
    it.block("TrayLipR", (W / 2 - 0.06, ty, t["h"] + 0.16), (0.14, t["y1"] - t["y0"], 0.34), GREEN)
    slots = []
    pr, ph = ITEM_STAND["pedestal_r"], ITEM_STAND["pedestal_h"]
    by = (r["y0"] + r["y1"]) / 2 + 0.1
    for i, x in enumerate(BACK_X):
        it.cyl("PedB%d" % (i + 1), (x, by, r["h"]), (x, by, r["h"] + ph), pr, WOOD_LIGHT)
        it.disc("PedBTop%d" % (i + 1), (x, by, r["h"] + ph + 0.02), (0, 0, 1), pr - 0.1, 0.04, GREEN)
        slots.append({"row": "back", "x": x, "y": by, "z": r["h"] + ph + 0.04})
    fy = (t["y0"] + t["y1"]) / 2 - 0.05
    for i, x in enumerate(FRONT_X):
        it.cyl("PedF%d" % (i + 1), (x, fy, t["h"]), (x, fy, t["h"] + ph), pr, WOOD_LIGHT)
        it.disc("PedFTop%d" % (i + 1), (x, fy, t["h"] + ph + 0.02), (0, 0, 1), pr - 0.1, 0.04, GREEN)
        slots.append({"row": "front", "x": x, "y": fy, "z": t["h"] + ph + 0.04})
    info = it.finish()
    info["slots"] = slots
    return info


# ------------------------------------------------------------------ headband rack
RACK = {"width": 14.8, "riser": {"y0": -2.6, "y1": -0.45, "h": 1.7}}
BUST_X = (-6.25, -3.75, -1.25, 1.25, 3.75, 6.25)
HEAD_R = 0.58                     # x/y radius: 1.16 wide, an R15 head is 1.2 (band inner radius 0.63)
HEAD_SCALE = (1.0, 0.92, 1.08)    # a little egg-shaped
BAND_ABOVE_HEAD = 0.22            # the band's centre above the head centre (brow height)


def _bust(it, tag, x, y, z0):
    it.cyl("%sBase" % tag, (x, y, z0), (x, y, z0 + 0.2), 0.64, DARK)
    it.cyl("%sPost" % tag, (x, y, z0 + 0.2), (x, y, z0 + 0.95), 0.15, DARK)
    it.cyl("%sNeck" % tag, (x, y, z0 + 0.9), (x, y, z0 + 1.3), 0.27, CREAM)
    hz = z0 + 1.3 + HEAD_R * HEAD_SCALE[2] - 0.06
    it.ball("%sHead" % tag, (x, y, hz), HEAD_R, CREAM, scale=HEAD_SCALE)
    return {"x": x, "y": y, "z": hz}


def headband_rack(D):
    it = Item(D, "HeadbandRack")
    W = RACK["width"]
    r = RACK["riser"]
    cy = (r["y0"] + r["y1"]) / 2
    it.block("Riser", (0, cy, r["h"] / 2), (W, r["y1"] - r["y0"], r["h"]), WOOD)
    it.block("RiserLip", (0, r["y1"] - 0.06, r["h"] + 0.05), (W + 0.1, 0.16, 0.12), BLUE)
    it.block("RiserCapL", (-W / 2 + 0.06, cy, r["h"] / 2 + 0.05), (0.14, r["y1"] - r["y0"] + 0.1, r["h"] + 0.1), BLUE)
    it.block("RiserCapR", (W / 2 - 0.06, cy, r["h"] / 2 + 0.05), (0.14, r["y1"] - r["y0"] + 0.1, r["h"] + 0.1), BLUE)
    # a low front board so the front busts are not on the bare counter
    it.block("Board", (0, 0.55, 0.09), (W, 2.0, 0.18), WOOD)
    it.block("BoardLip", (0, 1.5, 0.28), (W + 0.1, 0.14, 0.22), BLUE)
    heads = []
    for i, x in enumerate(BUST_X):
        heads.append(dict(_bust(it, "F%d" % (i + 1), x, 0.5, 0.18), row="front"))
    for i, x in enumerate(BUST_X):
        heads.append(dict(_bust(it, "B%d" % (i + 1), x, cy + 0.05, r["h"]), row="back"))
    info = it.finish()
    info["heads"] = heads
    info["band_above_head"] = BAND_ABOVE_HEAD
    return info


# ------------------------------------------------------------------ stroke font
# glyphs on a 3 x 5 grid, bars as (x0, y0, x1, y1) in grid units (y up); "N" adds a diagonal
T = 0.8  # bar thickness in grid units
GLYPHS = {
    "I": [(0, 0, 3, T), (0, 5 - T, 3, 5), (1.5 - T / 2, 0, 1.5 + T / 2, 5)],
    "T": [(0, 5 - T, 3, 5), (1.5 - T / 2, 0, 1.5 + T / 2, 5 - T)],
    "O": [(0, 0, T, 5), (3 - T, 0, 3, 5), (0, 5 - T, 3, 5), (0, 0, 3, T)],
    "P": [(0, 0, T, 5), (0, 5 - T, 3, 5), (0, 2.2, 3, 2.2 + T), (3 - T, 2.2, 3, 5)],
    "B": [(0, 0, T, 5), (0, 5 - T, 2.7, 5), (0, 2.1, 2.7, 2.1 + T), (0, 0, 2.7, T),
          (2.7 - T, 2.1, 2.7, 5), (3 - T, 0, 3, 2.1 + T)],
    "S": [(0, 5 - T, 3, 5), (0, 2.5, T, 5), (0, 2.1, 3, 2.1 + T), (3 - T, 0, 3, 2.1 + T), (0, 0, 3, T)],
    "N": [(0, 0, T, 5), (3 - T, 0, 3, 5), "diag"],
    "E": [(0, 0, T, 5), (0, 5 - T, 3, 5), (0, 2.1, 2.4, 2.1 + T), (0, 0, 3, T)],
    "H": [(0, 0, T, 5), (3 - T, 0, 3, 5), (0, 2.1, 3, 2.1 + T)],
    "A": [(0, 0, T, 5), (3 - T, 0, 3, 5), (0, 5 - T, 3, 5), (0, 2.1, 3, 2.1 + T)],
    "D": [(0, 0, T, 5), (0, 5 - T, 2.5, 5), (0, 0, 2.5, T), (3 - T, 0.6, 3, 4.4), (2.2, 4.4, 3, 5), (2.2, 0, 3, 0.6)],
    "M": [(0, 0, T, 5), (3 - T, 0, 3, 5), (1.5 - T / 2, 2.4, 1.5 + T / 2, 5), (0, 5 - T, 3, 5)],
    "R": [(0, 0, T, 5), (0, 5 - T, 3, 5), (0, 2.2, 3, 2.2 + T), (3 - T, 2.2, 3, 5), (3 - T, 0, 3, 2.2)],
    "C": [(0, 0, T, 5), (0, 5 - T, 3, 5), (0, 0, 3, T)],
    "U": [(0, 0, T, 5), (3 - T, 0, 3, 5), (0, 0, 3, T)],
    "Y": [(0, 2.5, T, 5), (3 - T, 2.5, 3, 5), (0, 2.1, 3, 2.1 + T), (1.5 - T / 2, 0, 1.5 + T / 2, 2.1)],
    " ": [],
}


def stroke_text(it, prefix, text, x_right, y_front, z_base, height, hexcol, depth=0.07, gap=0.12, material="SmoothPlastic"):
    """Lay `text` out reading LEFT-TO-RIGHT FOR A VIEWER IN FRONT (+Y): the first glyph at x_right,
    each next one further toward -X. Returns the total width."""
    unit = height / 5.0
    gw = 3 * unit
    x = x_right  # right edge (viewer's left) of the current glyph
    n = 0
    for ch in text:
        bars = GLYPHS.get(ch, [])
        for k, bar in enumerate(bars):
            n += 1
            name = "%s%s%d" % (prefix, ch if ch != " " else "_", n)
            if bar == "diag":
                # top-left to bottom-right for the viewer = top at +X (model), bottom at -X
                p0 = (x - 0.4 * unit, z_base + (5 - 0.45) * unit)
                p1 = (x - (3 - 0.4) * unit, z_base + 0.45 * unit)
                dx, dz = p1[0] - p0[0], p1[1] - p0[1]
                length = math.hypot(dx, dz)
                ang = math.degrees(math.atan2(-dz, dx))
                it.block(name, ((p0[0] + p1[0]) / 2, y_front + depth / 2, (p0[1] + p1[1]) / 2),
                         (length, depth, T * unit * 0.95), hexcol, material, rotation=rot(0, ang, 0))
                continue
            x0, y0, x1, y1 = bar
            cx = x - (x0 + x1) / 2 * unit           # grid x grows toward the viewer's right = model -X
            cz = z_base + (y0 + y1) / 2 * unit
            it.block(name, (cx, y_front + depth / 2, cz), ((x1 - x0) * unit, depth, (y1 - y0) * unit), hexcol, material)
        x -= gw + gap
    return (x_right - x) - gap


def mini_flask(it, prefix, cx, cy, cz, s):
    """A little potion flask (blue speed-potion palette), `s` = scale of a 1.0-stud-tall flask."""
    it.ball("%sBody" % prefix, (cx, cy, cz + 0.34 * s), 0.34 * s, "9fe3ff", "Glass", GLASS_T)
    it.ball("%sLiquid" % prefix, (cx, cy, cz + 0.32 * s), 0.26 * s, "33d6ff", "Neon")
    it.cyl("%sNeck" % prefix, (cx, cy, cz + 0.62 * s), (cx, cy, cz + 0.86 * s), 0.11 * s, "a8e6ff", "Glass", 0.3)
    it.cyl("%sCork" % prefix, (cx, cy, cz + 0.84 * s), (cx, cy, cz + 1.0 * s), 0.105 * s, "a5703f")


def mini_bolt(it, prefix, cx, cy, cz, s):
    """A lightning bolt (two tilted bars) standing `s` studs tall on cz."""
    # a zig-zag: two parallel leaning bars OFFSET sideways from each other, bridged by a short jag
    it.block("%sTop" % prefix, (cx + 0.13 * s, cy, cz + 0.74 * s), (0.20 * s, 0.10 * s, 0.46 * s), "ffd83a", "Neon", rotation=rot(0, -30, 0))
    it.block("%sBottom" % prefix, (cx - 0.13 * s, cy, cz + 0.26 * s), (0.20 * s, 0.10 * s, 0.46 * s), "ffd83a", "Neon", rotation=rot(0, -30, 0))
    it.block("%sMid" % prefix, (cx, cy, cz + 0.5 * s), (0.44 * s, 0.10 * s, 0.16 * s), "ffd83a", "Neon", rotation=rot(0, 12, 0))


def item_sign(D):
    """The side-board text: two rows centred on the board face (board 3.87 wide x 2.89 tall)."""
    it = Item(D, "ItemSign")
    H = 0.5
    rows = (("POTIONS", 0.30, "flask"), ("BOOSTS", -0.60, "bolt"))
    for text, zc, icon in rows:
        unit = H / 5.0
        width = len(text) * 3 * unit + (len(text) - 1) * 0.12
        icon_w = 0.55
        total = width + 0.2 + icon_w
        x_right = total / 2
        stroke_text(it, text[:1] + "_", text, x_right, 0.0, zc - H / 2, H, GREEN_DARK)
        ix = x_right - width - 0.2 - icon_w / 2
        if icon == "flask":
            mini_flask(it, "Flask", ix, 0.2, zc - H / 2 - 0.02, 0.56)
        else:
            mini_bolt(it, "Bolt", ix, 0.2, zc - H / 2 - 0.02, 0.56)
    return it.finish()


def a_flask(D):
    it = Item(D, "MiniFlask")
    mini_flask(it, "", 0, 0, 0, 0.85)
    return it.finish()


def a_bolt(D):
    it = Item(D, "MiniBolt")
    mini_bolt(it, "", 0, 0, 0, 0.85)
    return it.finish()


BUILDERS = [
    ("ItemStand", item_stand),
    ("HeadbandRack", headband_rack),
    ("ItemSign", item_sign),
    ("MiniFlask", a_flask),
    ("MiniBolt", a_bolt),
]
