"""Fridge (Home, fun-builds 2026-09-24, package HomeKitchenA): a tall stainless top-freezer fridge,
4 wide x 8 high x ~3.2 deep (handles included). Freezer door on top, fridge door below, both hinged on the
viewer's RIGHT (-X) with chrome bar handles on the free (+X) edge. Notes, a kid's cucumber drawing and
magnets on the fridge door, a cucumber magnet + badge on the freezer door. The inside is fully stocked so
an opened door shows a real fridge: glass shelves, crisper drawers of cucumbers and tomatoes, a milk
carton, eggs, a layered strawberry cake, a pickle jar, cheese, leftovers; door bins of ketchup / mustard /
soda / juice / cans / butter; in the freezer ice cream, a bag of ice, a pizza box, peas and frost.

Behaviour contract (behaviours/server|client/Fridge.lua):
  Door*          the fridge door group (panel, gasket, liner, bins + bottles, handle, notes, magnets):
                 rigid, swings about the vertical axis through Pivot_DoorHinge by State_DoorOpen degrees
                 (+ = the free +X edge swings toward the front, -Z)
  FreezerDoor*   the freezer door group, about Pivot_FreezerHinge by State_FreezerDoorOpen degrees
  LightStrip     fridge ceiling strip (SmoothPlastic) -> Neon while the fridge door is open
  FreezerLight   freezer back-wall strip -> Neon while the freezer door is open
  Pivot_FridgeLight / Pivot_FreezerLight   where the PointLights go (compartment centres, near the top)
  Pivot_FridgeMist / Pivot_FreezerMist     bottom-front centre of each opening (cold mist spills from here)
  Pivot_PromptDoor / Pivot_PromptFreezer   in front of each handle (prompt spots)
  Pivot_Hum      the back bottom (compressor hum)
  Model attrs: OpeningFridge / OpeningFreezer = authored (width, height) of each opening (mist emitter size)

Review renders with the doors open: build__FridgeOpen.py (not shipped).
"""
import os
import importlib.util

STEEL = "c9d0d8"      # stainless skin + doors
LINER = "f2f0ea"      # cabinet interior
LINER2 = "e6ecf1"     # door liners (a touch cooler)
GASKET = "3b4350"
DARK = "23262c"
CHROME = "e3e8ee"
GLASS = "d8ecf5"
RED = "d9443c"
BLUE = "3f79d4"
YELLOW = "f2c13d"
GREEN = "3f8f3a"
GREEN2 = "5aa845"
ORANGE = "f08a30"
PINK = "e87fa8"
CREAM = "f7efe0"
PAPER = "fbfaf5"
STICKY = "ffe680"
CARDBOARD = "c9b089"

HINGE_X = -1.98        # hinge side (viewer's right)
HINGE_Z = -1.12        # the doors' back face
OPEN_DEG = 100         # State_DoorOpen / State_FreezerDoorOpen

FRIDGE_Y = (0.56, 5.40)    # fridge door
FREEZER_Y = (5.46, 7.96)   # freezer door


def _kitchenlib():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kitchenlib.py")
    spec = importlib.util.spec_from_file_location("kitchenlib", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(D, P, key="Fridge", open_deg=0):
    K = _kitchenlib()
    m = P.Model(D, key, category="Home")

    # ------------------------------------------------------------ cabinet: white liner walls inside stainless skins
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Skin" + side, (sx * 1.96, 3.97, 0.09), (0.08, 7.9, 2.42), STEEL, "Metal")
        m.block("Wall" + side, (sx * 1.82, 4.21, 0.05), (0.22, 7.42, 2.3), LINER)
    m.block("SkinTop", (0, 7.95, 0.095), (4.02, 0.1, 2.45), STEEL, "Metal")
    m.block("WallTop", (0, 7.81, 0.05), (3.46, 0.22, 2.3), LINER)
    m.block("Floor", (0, 0.64, 0.05), (3.46, 0.28, 2.3), LINER)
    m.block("Divider", (0, 5.46, 0.05), (3.46, 0.32, 2.3), LINER)
    m.block("LinerBack", (0, 4.21, 1.11), (3.46, 7.42, 0.22), LINER)
    m.block("BackPanel", (0, 4.0, 1.27), (3.9, 7.8, 0.1), GASKET, "Metal")
    m.block("Coils", (0, 4.4, 1.35), (2.9, 5.2, 0.08), DARK, "DiamondPlate", collide=False)
    m.block("Plinth", (0, 0.27, 0.12), (3.84, 0.54, 2.2), GASKET)
    m.block("KickGrille", (0, 0.27, -1.0), (3.7, 0.4, 0.06), DARK, "DiamondPlate")
    m.block("HingeTop", (-1.78, 8.02, -1.3), (0.38, 0.08, 0.34), GASKET, "Metal", collide=False)

    # ------------------------------------------------------------ fridge interior
    for i, y in enumerate((1.74, 2.99, 4.19)):
        m.block("Shelf%d" % (i + 1), (0, y, 0.25), (3.44, 0.08, 1.5), GLASS, "Glass", transparency=0.35)
    # crisper drawers (clear, pale green) with cucumbers (left) and tomatoes (right)
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Crisper" + side, (sx * 0.87, 1.24, -0.46), (1.64, 0.9, 0.08), "cfe8d2", "SmoothPlastic",
                transparency=0.55, collide=False)
    m.ellipsoid("Cuke1", (0.48, 0.97, 0.15), (0.36, 0.36, 1.3), GREEN, collide=False)
    m.ellipsoid("Cuke2", (1.14, 0.97, 0.2), (0.36, 0.36, 1.24), GREEN2, collide=False, rot=(0, 7, 0))
    m.ellipsoid("Cuke3", (0.8, 1.28, 0.1), (0.34, 0.34, 1.28), GREEN, collide=False, rot=(0, -9, 0))
    m.ball("Tomato1", (-0.6, 1.06, 0.0), 0.54, RED, collide=False)
    m.ball("Tomato2", (-1.2, 1.05, 0.25), 0.52, RED, collide=False)
    # shelf 1: milk carton + eggs
    mx, mz = 1.0, 0.3
    m.block("MilkBox", (mx, 2.2, mz), (0.64, 0.84, 0.64), PAPER, collide=False)
    m.block("MilkBand", (mx, 2.22, mz), (0.66, 0.34, 0.66), BLUE, collide=False)
    m.wedge("MilkRoofF", (mx, 2.73, mz - 0.16), (0.64, 0.22, 0.32), BLUE, collide=False)
    m.wedge("MilkRoofB", (mx, 2.73, mz + 0.16), (0.64, 0.22, 0.32), BLUE, collide=False, rot=(0, 180, 0))
    m.block("EggCarton", (-0.62, 1.9, 0.05), (1.3, 0.24, 0.52), CARDBOARD, "Cardboard", collide=False)
    for i, x in enumerate((-1.02, -0.62, -0.22)):
        m.ellipsoid("Egg%d" % (i + 1), (x, 2.13, 0.05), (0.3, 0.4, 0.3), CREAM, collide=False)
    # shelf 2: layered strawberry cake + pickle jar
    cx, cz = 0.42, 0.3
    m.disc("CakePlate", (cx, 3.06, cz), (0, 1, 0), 1.34, 0.06, PAPER, collide=False)
    m.cyl("CakeBody", (cx, 3.08, cz), (cx, 3.6, cz), 1.0, PINK, collide=False)
    m.cyl("CakeCream", (cx, 3.3, cz), (cx, 3.38, cz), 1.03, PAPER, collide=False)
    m.cyl("CakeIcing", (cx, 3.58, cz), (cx, 3.68, cz), 1.06, PAPER, collide=False)
    m.ball("CakeCherry", (cx, 3.78, cz - 0.05), 0.24, RED, collide=False)
    jx, jz = -1.05, 0.35
    m.cyl("PickleJar", (jx, 3.03, jz), (jx, 3.83, jz), 0.62, "9fd18a", "Glass", transparency=0.3, collide=False)
    m.cyl("PickleLid", (jx, 3.81, jz), (jx, 3.93, jz), 0.66, RED, "Metal", collide=False)
    m.ellipsoid("Pickle", (jx + 0.04, 3.36, jz - 0.03), (0.24, 0.58, 0.24), GREEN, collide=False, rot=(0, 0, 10))
    # shelf 3: cheese wedge + leftovers
    # cheese wedge turned so its triangle faces the door (slope rises toward +X), one hole on the face
    m.wedge("Cheese", (1.02, 4.46, 0.2), (0.62, 0.46, 0.8), YELLOW, collide=False, rot=(0, 90, 0))
    m.disc("CheeseHole", (1.2, 4.36, -0.115), (0, 0, 1), 0.13, 0.06, "d9a21f", collide=False)
    m.block("Leftovers", (-0.45, 4.43, 0.25), (1.0, 0.4, 0.7), ORANGE, collide=False)
    m.block("LeftoversLid", (-0.45, 4.67, 0.25), (1.04, 0.1, 0.74), BLUE, collide=False)
    m.block("LightStrip", (0, 5.27, -0.2), (1.6, 0.1, 0.3), LINER, collide=False)

    # ------------------------------------------------------------ freezer interior
    m.block("FreezerShelf", (0, 6.6, 0.25), (3.44, 0.06, 1.5), "9aa7b8", "Metal")
    m.cyl("IceCream", (0.75, 5.62, 0.3), (0.75, 6.2, 0.3), 0.8, PAPER, collide=False)
    m.cyl("IceCreamLid", (0.75, 6.18, 0.3), (0.75, 6.3, 0.3), 0.84, PINK, collide=False)
    m.block("IceTray", (-0.7, 5.7, 0.2), (1.2, 0.16, 0.62), "8fc9ee", collide=False)
    m.block("IceCubes", (-0.7, 5.82, 0.2), (1.08, 0.18, 0.5), "e6f4ff", "Ice", transparency=0.25, collide=False)
    m.block("PizzaBox", (-0.6, 6.73, 0.25), (1.3, 0.2, 1.2), RED, "Cardboard", collide=False)
    m.ellipsoid("PeasBag", (0.8, 6.84, 0.2), (0.95, 0.42, 0.72), GREEN2, collide=False, rot=(0, 12, 0))
    m.block("Frost", (0, 7.64, 0.05), (3.42, 0.14, 2.28), "e6f4ff", "Ice", transparency=0.2, collide=False)
    m.block("FreezerLight", (0, 7.3, 0.97), (0.8, 0.14, 0.08), LINER, collide=False)

    # ------------------------------------------------------------ fridge door (Door*)
    fy0, fy1 = FRIDGE_Y
    fcy, fh = (fy0 + fy1) / 2, fy1 - fy0
    g = K.Swing(m, P, (HINGE_X, fcy, HINGE_Z), open_deg)
    g.block("DoorPanel", (0, fcy, -1.3), (3.96, fh, 0.36), STEEL, "Metal")
    g.block("DoorGasket", (0, fcy, -1.1), (3.76, fh - 0.18, 0.06), GASKET, collide=False)
    g.block("DoorLiner", (0, 3.03, -1.04), (3.36, 4.36, 0.12), LINER2, collide=False)
    g.block("DoorBin1", (0, 1.3, -0.78), (3.0, 0.5, 0.4), "cfe3f2", transparency=0.35, collide=False)
    g.block("DoorBin2", (0, 3.35, -0.78), (3.0, 0.4, 0.4), "cfe3f2", transparency=0.35, collide=False)
    bz = -0.78
    for name, x, top, d, col, cap, mat, tr in (
            ("DoorKetchup", -1.05, 1.95, 0.34, RED, PAPER, "SmoothPlastic", 0.0),
            ("DoorMustard", -0.55, 1.85, 0.32, YELLOW, RED, "SmoothPlastic", 0.0),
            ("DoorSoda", 0.1, 2.25, 0.36, GREEN2, RED, "Glass", 0.15),
            ("DoorJuice", 0.85, 2.15, 0.38, ORANGE, GREEN2, "SmoothPlastic", 0.0)):
        g.cyl(name, (x, 1.07, bz), (x, top, bz), d, col, mat, transparency=tr, collide=False)
        g.cyl(name + "Cap", (x, top - 0.02, bz), (x, top + 0.14, bz), d * 0.55, cap, collide=False)
    g.cyl("DoorCanRed", (-0.95, 3.17, bz), (-0.95, 3.63, bz), 0.28, RED, "Metal", collide=False)
    g.cyl("DoorCanBlue", (-0.6, 3.17, bz), (-0.6, 3.63, bz), 0.28, BLUE, "Metal", collide=False)
    g.block("DoorButter", (0.65, 3.28, bz), (0.72, 0.22, 0.3), "ffe07a", collide=False)
    # chrome bar handle on the free edge
    g.cyl("DoorHandle", (1.62, 3.2, -1.74), (1.62, 5.15, -1.74), 0.17, CHROME, "Metal")
    g.block("DoorHandleTop", (1.62, 5.02, -1.61), (0.14, 0.16, 0.3), CHROME, "Metal", collide=False)
    g.block("DoorHandleBot", (1.62, 3.33, -1.61), (0.14, 0.16, 0.3), CHROME, "Metal", collide=False)
    # notes, a drawing and magnets
    g.block("DoorNote1", (0.5, 4.3, -1.49), (0.8, 0.95, 0.05), PAPER, collide=False, rot=(0, 0, 6))
    g.disc("DoorMagnet1", (0.46, 4.7, -1.53), (0, 0, 1), 0.24, 0.06, RED, collide=False)
    g.block("DoorNote2", (-0.55, 3.95, -1.49), (0.6, 0.6, 0.05), STICKY, collide=False, rot=(0, 0, -8))
    g.disc("DoorMagnet2", (-0.55, 4.16, -1.53), (0, 0, 1), 0.22, 0.06, BLUE, collide=False)
    g.block("DoorDrawing", (0.15, 2.55, -1.49), (1.05, 0.8, 0.05), PAPER, collide=False, rot=(0, 0, -3))
    g.ellipsoid("DoorDoodle", (0.15, 2.48, -1.515), (0.62, 0.22, 0.05), GREEN2, collide=False, rot=(0, 0, 22))
    g.disc("DoorMagnet3", (0.15, 2.9, -1.53), (0, 0, 1), 0.22, 0.06, YELLOW, collide=False)

    # ------------------------------------------------------------ freezer door (FreezerDoor*)
    zy0, zy1 = FREEZER_Y
    zcy, zh = (zy0 + zy1) / 2, zy1 - zy0
    f = K.Swing(m, P, (HINGE_X, zcy, HINGE_Z), open_deg)
    f.block("FreezerDoorPanel", (0, zcy, -1.3), (3.96, zh, 0.36), STEEL, "Metal")
    f.block("FreezerDoorGasket", (0, zcy, -1.1), (3.76, zh - 0.18, 0.06), GASKET, collide=False)
    f.block("FreezerDoorLiner", (0, 6.66, -1.04), (3.36, 1.9, 0.12), LINER2, collide=False)
    f.cyl("FreezerDoorHandle", (1.62, 5.72, -1.74), (1.62, 7.0, -1.74), 0.17, CHROME, "Metal")
    f.block("FreezerDoorHandleTop", (1.62, 6.88, -1.61), (0.14, 0.16, 0.3), CHROME, "Metal", collide=False)
    f.block("FreezerDoorHandleBot", (1.62, 5.84, -1.61), (0.14, 0.16, 0.3), CHROME, "Metal", collide=False)
    f.block("FreezerDoorBadge", (0, 7.6, -1.5), (0.95, 0.24, 0.06), GASKET, collide=False)
    f.ellipsoid("FreezerDoorLogo", (0, 7.6, -1.535), (0.5, 0.15, 0.05), GREEN2, collide=False)
    f.ellipsoid("FreezerDoorMagnet", (-0.9, 6.45, -1.51), (0.62, 0.22, 0.1), GREEN2, collide=False, rot=(0, 0, 18))

    # ------------------------------------------------------------ data
    m.pivot("DoorHinge", (HINGE_X, fcy, HINGE_Z))
    m.pivot("FreezerHinge", (HINGE_X, zcy, HINGE_Z))
    m.pivot("FridgeLight", (0, 4.8, 0.1))
    m.pivot("FreezerLight", (0, 7.1, 0.1))
    m.pivot("FridgeMist", (0, 1.0, -1.05))
    m.pivot("FreezerMist", (0, 5.85, -1.05))
    m.pivot("PromptDoor", (1.62, 4.2, -1.95))
    m.pivot("PromptFreezer", (1.62, 6.4, -1.95))
    m.pivot("Hum", (0, 0.6, 1.2))
    m.attr("State_DoorOpen", OPEN_DEG)
    m.attr("State_FreezerDoorOpen", OPEN_DEG)
    m.attr("OpeningFridge", [3.42, 4.52, 0])
    m.attr("OpeningFreezer", [3.42, 2.08, 0])
    m.attr("Cost", 1500)
    m.attr("DisplayName", "Fridge")
    return m.finish()
