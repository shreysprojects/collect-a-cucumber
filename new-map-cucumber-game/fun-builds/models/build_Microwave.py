"""Microwave (Home, fun-builds 2026-09-24, package HomeKitchenA): an off-white microwave with a black door
(dark see-through window, chrome bar handle, hinged on the viewer's LEFT = +X) and a dark keypad column
(green LCD display, 3x3 buttons, Start / Stop, door-release) standing on a blue wheeled kitchen cart
(wood shelves, back rail with ball finials, a push handle on the left side, four casters). Inside, a red
mug of cocoa with a marshmallow sits off-centre on the glass turntable, so the spin shows. On the lower
shelf: a striped popcorn box and a stack of plates. ~3 wide x 4.1 high x 2.4 deep.

Behaviour contract (behaviours/server|client/Microwave.lua):
  Door*         the door group (frame, window, handle): swings about the vertical axis through
                Pivot_DoorHinge by State_DoorOpen degrees (negative = the free -X edge swings to the front)
  Turntable*    plate + mug + cocoa + marshmallow: spin about the vertical axis through Pivot_Turntable
  CavityLight   lamp on the cavity wall (SmoothPlastic) -> Neon while heating / open
  Display       the LCD: the client puts a SurfaceGui on its Front face (clock / countdown / END)
  Pivot_CavityLight  cavity centre (PointLight, hum)
  Pivot_Keypad       front centre of the keypad column (the prompts)
  Pivot_Steam        just in front of the door's top edge (steam puff after the ding)
"""

import os
import importlib.util

BODY = "f2f0ea"
PANEL = "23262c"
DOOR = "23262c"
WINDOW = "2a3540"
CHROME = "e3e8ee"
LCD = "1f3326"
KEY = "d9dde3"
CART = "3f79d4"
WOOD = "8a5a2b"
RUBBER = "23262c"
RED = "d9443c"
GREEN = "5aa845"
COCOA = "6b4423"
POPCORN = "fff3c4"

LEG_X, LEG_Z = 1.32, 1.02
MW_Y0 = 2.68           # microwave body bottom (on its feet)
MW_Y1 = 4.13           # microwave body top
MW_MID = (MW_Y0 + MW_Y1) / 2


def _kitchenlib():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kitchenlib.py")
    spec = importlib.util.spec_from_file_location("kitchenlib", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(D, P, key="Microwave", open_deg=0, spin_deg=0):
    K = _kitchenlib()
    m = P.Model(D, key, category="Home")

    # ------------------------------------------------------------ cart
    m.block("TopShelf", (0, 2.53, 0), (3.0, 0.14, 2.4), WOOD, "Wood")
    m.block("TopEdge", (0, 2.53, -1.21), (3.04, 0.2, 0.06), CART)
    m.block("LowerShelf", (0, 0.78, 0), (2.84, 0.12, 2.24), WOOD, "Wood")
    m.block("LowerEdge", (0, 0.8, -1.13), (2.88, 0.18, 0.06), CART)
    for tag, sx, sz in (("FL", 1, -1), ("FR", -1, -1), ("BL", 1, 1), ("BR", -1, 1)):
        x, z = sx * LEG_X, sz * LEG_Z
        top = 2.86 if sz > 0 else 2.5
        m.cyl("Leg" + tag, (x, 0.44, z), (x, top, z), 0.16, CART)
        if sz > 0:
            m.ball("Finial" + tag, (x, top + 0.06, z), 0.24, CART)
        m.block("Caster" + tag, (x, 0.44, z), (0.24, 0.1, 0.3), "9aa7b8", "Metal", collide=False)
        m.cyl("Wheel" + tag, (x - 0.07, 0.2, z), (x + 0.07, 0.2, z), 0.4, RUBBER, "Rubber")
    m.cyl("RailBack", (-LEG_X, 2.82, LEG_Z), (LEG_X, 2.82, LEG_Z), 0.1, CART, collide=False)
    # push handle on the viewer's left side
    hx = 1.72
    m.cyl("HandleBar", (hx, 2.28, -LEG_Z), (hx, 2.28, LEG_Z), 0.13, CHROME, "Metal")
    m.cyl("HandleF", (LEG_X, 2.28, -LEG_Z), (hx + 0.06, 2.28, -LEG_Z), 0.1, CHROME, "Metal", collide=False)
    m.cyl("HandleB", (LEG_X, 2.28, LEG_Z), (hx + 0.06, 2.28, LEG_Z), 0.1, CHROME, "Metal", collide=False)
    # a red tea towel folded over the handle bar
    m.cyl("TowelFold", (hx, 2.28, -0.02), (hx, 2.28, 0.62), 0.2, RED, "Fabric", collide=False)
    m.block("TowelOut", (hx + 0.075, 1.98, 0.3), (0.05, 0.62, 0.64), RED, "Fabric", collide=False)
    m.block("TowelIn", (hx - 0.075, 2.04, 0.3), (0.05, 0.5, 0.64), RED, "Fabric", collide=False)
    m.block("TowelStripe", (hx + 0.085, 1.8, 0.3), (0.05, 0.1, 0.645), "fbfaf5", "Fabric", collide=False)

    # lower shelf: striped popcorn box + a stack of plates
    px = 0.72
    m.block("PopcornBox", (px, 1.24, 0.05), (0.8, 0.8, 0.6), "fbfaf5", collide=False)
    for i, dx in enumerate((-0.25, 0.0, 0.25)):
        m.block("PopcornStripe%d" % (i + 1), (px + dx, 1.24, 0.05), (0.14, 0.8, 0.62), RED, collide=False)
    for i, (dx, dy, dz) in enumerate(((-0.18, 1.72, -0.05), (0.14, 1.74, 0.08), (0.0, 1.85, -0.02))):
        m.ball("Popcorn%d" % (i + 1), (px + dx, dy, 0.05 + dz), 0.32, POPCORN, collide=False)
    m.disc("PlateA", (-0.7, 0.88, 0.1), (0, 1, 0), 1.0, 0.08, "fbfaf5", collide=False)
    m.disc("PlateB", (-0.7, 0.96, 0.1), (0, 1, 0), 0.94, 0.08, "6ea5e8", collide=False)

    # ------------------------------------------------------------ microwave body (door +X side, keypad -X side)
    m.block("FootF", (0, 2.64, -0.62), (2.2, 0.08, 0.16), RUBBER, "Rubber")
    m.block("FootB", (0, 2.64, 0.62), (2.2, 0.08, 0.16), RUBBER, "Rubber")
    m.block("CaseTop", (0, MW_Y1 - 0.06, 0.02), (2.62, 0.12, 1.76), BODY)
    m.block("CaseBottom", (0, MW_Y0 + 0.06, 0.02), (2.62, 0.12, 1.76), BODY)
    m.block("CaseL", (1.24, MW_MID, 0.02), (0.12, 1.45, 1.76), BODY)
    m.block("CaseR", (-1.24, MW_MID, 0.02), (0.12, 1.45, 1.76), BODY)
    m.block("CaseBack", (0, MW_MID, 0.85), (2.58, 1.45, 0.14), BODY)
    m.block("Partition", (-0.36, MW_MID, -0.02), (0.12, 1.3, 1.6), "d8dde2")
    for i, y in enumerate((3.78, 3.64)):
        m.block("VentL%d" % (i + 1), (1.31, y, 0.3), (0.05, 0.06, 0.9), "9aa7b8", collide=False)
    m.block("CavityLight", (-0.29, 3.78, 0.25), (0.05, 0.22, 0.3), BODY, collide=False)
    # keypad column
    m.block("KeypadPanel", (-0.85, MW_MID, -0.9), (0.9, 1.41, 0.08), PANEL)
    m.block("Display", (-0.85, 3.86, -0.955), (0.66, 0.24, 0.05), LCD, collide=False)
    n = 0
    for y in (3.58, 3.4, 3.22):
        for x in (-1.08, -0.85, -0.62):
            n += 1
            m.block("Btn%d" % n, (x, y, -0.955), (0.17, 0.13, 0.05), KEY, collide=False)
    m.block("BtnStop", (-0.99, 3.0, -0.96), (0.34, 0.16, 0.06), RED, collide=False)
    m.block("BtnStart", (-0.71, 3.0, -0.96), (0.34, 0.16, 0.06), GREEN, collide=False)
    m.block("BtnOpen", (-0.85, 2.8, -0.96), (0.6, 0.1, 0.06), "9aa7b8", collide=False)

    # ------------------------------------------------------------ turntable (Turntable*): cavity x -0.3..1.18, z -0.86..0.78
    tx, ty, tz = 0.44, 2.84, -0.04
    t = K.Swing(m, P, (tx, ty, tz), spin_deg)
    t.disc("TurntablePlate", (tx, ty, tz), (0, 1, 0), 1.2, 0.06, "e6f2f8", "Glass", transparency=0.25, collide=False)
    mx, mz = tx + 0.2, tz - 0.12
    t.cyl("TurntableMug", (mx, ty + 0.03, mz), (mx, ty + 0.49, mz), 0.4, RED, collide=False)
    t.disc("TurntableMugHandle", (mx + 0.22, ty + 0.26, mz), (0, 0, 1), 0.26, 0.07, RED, collide=False)
    t.disc("TurntableCocoa", (mx, ty + 0.45, mz), (0, 1, 0), 0.34, 0.06, COCOA, collide=False)
    t.block("TurntableMallow", (mx - 0.04, ty + 0.5, mz + 0.03), (0.12, 0.1, 0.12), "fbfaf5", collide=False,
            rot=(0, 25, 0))

    # ------------------------------------------------------------ door (Door*): x -0.4..1.3, hinge at +X
    dz, dt = -0.96, 0.12
    g = K.Swing(m, P, (1.3, MW_MID, -0.9), open_deg)
    g.block("DoorFrameL", (1.16, MW_MID, dz), (0.28, 1.41, dt), DOOR)
    g.block("DoorFrameR", (-0.23, MW_MID, dz), (0.34, 1.41, dt), DOOR)
    g.block("DoorFrameTop", (0.48, 3.985, dz), (1.08, 0.25, dt), DOOR)
    g.block("DoorFrameBot", (0.48, 2.81, dz), (1.08, 0.22, dt), DOOR)
    g.block("DoorWindow", (0.48, 3.39, -0.95), (1.08, 0.94, 0.06), WINDOW, "Glass", transparency=0.45)
    g.cyl("DoorHandle", (-0.2, 2.95, -1.14), (-0.2, 3.85, -1.14), 0.1, CHROME, "Metal")
    g.block("DoorHandleTop", (-0.2, 3.78, -1.06), (0.08, 0.08, 0.12), CHROME, "Metal", collide=False)
    g.block("DoorHandleBot", (-0.2, 3.02, -1.06), (0.08, 0.08, 0.12), CHROME, "Metal", collide=False)

    # ------------------------------------------------------------ data
    m.pivot("DoorHinge", (1.3, MW_MID, -0.9))
    m.pivot("Turntable", (tx, ty, tz))
    m.pivot("CavityLight", (0.44, 3.45, -0.04))
    m.pivot("Keypad", (-0.85, 3.4, -1.0))
    m.pivot("Steam", (0.48, 4.1, -1.1))
    m.attr("State_DoorOpen", -100)
    m.attr("Cost", 600)
    m.attr("DisplayName", "Microwave")
    return m.finish()
