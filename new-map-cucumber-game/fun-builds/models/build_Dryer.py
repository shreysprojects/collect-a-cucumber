"""Dryer (Home, fun-builds HomeLaundry 2026-09-24): the WashingMachine's matching tumble dryer, RED accents.

Same cabinet / drum / door / console as the washer (laundrylib.py) with a lint-trap pull where the washer has its
detergent drawer, no water, a round louvred exhaust vent on the viewer's-right (-X) side and a yellow laundry
basket of clean clothes on top. Cost 1000.
Behaviour (behaviours/server|client/Dryer.lua -> WashingMachine.lua's engine): "Start" runs a 15 s cycle - the
drum turns steadily one way with the clothes tumbling, a warm glow inside, warm lint puffs out of the vent while
its louvres flutter open, the machine hums and gently shakes, the screen counts down, Ding at the end.
"Open door" swings the Door* group about Pivot_DoorHinge.
Vent parts: VentRing, VentHole (fixed), VentSlat1..3 (tilt about their own authored-Z axis);
Pivot_Vent = the vent mouth, Pivot_VentOut = a point 1 stud out along the blow direction.
"""
import os
import math
import importlib.util


def _lib():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "laundrylib.py")
    spec = importlib.util.spec_from_file_location("laundrylib", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ACCENT = "d9443c"
ACCENT_DARK = "a8322c"
CLOTHES = [  # (degrees from the drum bottom, radius, z, size, colour)
    (-30, 0.64, -0.8, (0.66, 0.24, 0.42), "e87fa8"),   # pink towel
    (18, 0.66, -1.06, (0.56, 0.2, 0.3), "f2f0ea"),     # white sock
    (48, 0.62, -0.72, (0.74, 0.24, 0.5), "2f9e9e"),    # teal shirt
    (-6, 0.7, -1.3, (0.6, 0.22, 0.22), "5aa845"),      # a cucumber, drying off
]
VENT = (-1.73, 3.05, 0.85)   # vent centre on the -X side (the body's side face is at x -1.69)


def build(D, P, key="Dryer", pose=None):
    L = _lib()
    pose = pose or {}
    m = P.Model(D, key, category="Home")
    L.build_machine(m, P, "dryer", ACCENT, ACCENT_DARK, CLOTHES, pose=pose)
    L.back_details(m, False, ACCENT, plate=False)

    # ------------------------------------------------------------ side exhaust vent (-X, the viewer's right)
    vx, vy, vz = VENT
    m.disc("VentRing", (vx, vy, vz), (1, 0, 0), 0.84, 0.12, L.CHROME, "Metal", collide=False)
    m.disc("VentHole", (vx - 0.08, vy, vz), (1, 0, 0), 0.64, 0.06, L.BLACK, "SmoothPlastic", collide=False, shadow=False)
    tilt = pose.get("vent", 0)
    for i, dy in enumerate((0.18, 0.0, -0.18)):
        half = math.sqrt(0.32 ** 2 - dy ** 2) - 0.03
        m.block("VentSlat%d" % (i + 1), (vx - 0.135, vy + dy, vz), (0.05, 0.12, 2 * half), L.CHROME, "Metal",
                rot=(0, 0, -tilt), collide=False, shadow=False)
    m.pivot("Vent", (vx - 0.2, vy, vz))
    m.pivot("VentOut", (vx - 1.2, vy + 0.25, vz))

    # ------------------------------------------------------------ on top: a basket of clean laundry
    top = L.TOP_Y
    bx, bz = 0.5, 0.2
    BASKET = "f2c13d"
    m.block("BasketFront", (bx, top + 0.3, bz - 0.5), (1.64, 0.6, 0.08), BASKET, "SmoothPlastic")
    m.block("BasketBack", (bx, top + 0.3, bz + 0.5), (1.64, 0.6, 0.08), BASKET, "SmoothPlastic")
    for side, sx in (("L", 1), ("R", -1)):
        m.block("Basket" + side, (bx + sx * 0.78, top + 0.3, bz), (0.08, 0.6, 0.94), BASKET, "SmoothPlastic")
    m.ellipsoid("BasketLaundry", (bx, top + 0.5, bz), (1.5, 0.56, 0.94), "f2f0ea", "Fabric", collide=False)
    m.ellipsoid("BasketSock", (bx - 0.35, top + 0.5, bz - 0.56), (0.18, 0.56, 0.12), "3f79d4", "Fabric",
                rot=(-12, 0, 8), collide=False, shadow=False)

    m.attr("Cost", 1000)
    m.attr("DisplayName", "Dryer")
    m.attr("Notes", "Tumble dryer matching the WashingMachine (primlib parts, fun-builds/models/build_Dryer.py + "
                    "laundrylib.py). Drum* spins about Pivot_Drum (authored Z axis), DrumCloth1..4 tumble, Door* swings "
                    "about Pivot_DoorHinge (vertical), Dial* turns about Pivot_Dial, Screen shows the countdown on its "
                    "Front face, VentSlat1..3 flutter and lint puffs from Pivot_Vent toward Pivot_VentOut.")
    return m.finish()
