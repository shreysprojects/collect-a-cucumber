"""WashingMachine (Home, fun-builds HomeLaundry 2026-09-24): a chunky white front-loader with BLUE accents.

~3.5 wide x 4.0 high x 3.4 deep, Cost 1200. The cabinet, drum, door and console live in laundrylib.py (shared
with the Dryer). On top: a folded pink + teal towel stack and an orange detergent jug.
Behaviour (behaviours/server|client/WashingMachine.lua): "Start" runs a 15 s cycle - water fills the drum
(Water), the drum sloshes back and forth, drains, then spins fast while the whole machine shakes; the screen
counts down, Ding at the end. "Open door" swings the Door* group about Pivot_DoorHinge.
"""
import os
import importlib.util


def _lib():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "laundrylib.py")
    spec = importlib.util.spec_from_file_location("laundrylib", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ACCENT = "3f79d4"
ACCENT_DARK = "2c5aa8"
CLOTHES = [  # (degrees from the drum bottom, radius, z, size, colour)
    (-32, 0.66, -0.78, (0.58, 0.2, 0.3), "d9443c"),    # red sock
    (16, 0.64, -1.02, (0.78, 0.26, 0.58), "f2c13d"),   # yellow shirt
    (46, 0.62, -0.72, (0.66, 0.24, 0.5), "8e5bd1"),    # purple pants
    (-6, 0.7, -1.3, (0.6, 0.22, 0.22), "5aa845"),      # a cucumber that got in the wash
]


def build(D, P, key="WashingMachine", pose=None):
    L = _lib()
    m = P.Model(D, key, category="Home")
    L.build_machine(m, P, "washer", ACCENT, ACCENT_DARK, CLOTHES, pose=pose)
    L.back_details(m, True, ACCENT)

    # ------------------------------------------------------------ on top: folded towels + a detergent jug
    top = L.TOP_Y
    m.block("TowelA", (0.78, top + 0.09, 0.35), (1.1, 0.2, 0.8), "e87fa8", "Fabric", rot=(0, 4, 0))
    m.block("TowelA_Band", (0.78, top + 0.09, 0.35), (1.12, 0.1, 0.14), "f2f0ea", "Fabric", rot=(0, 4, 0), collide=False)
    m.block("TowelB", (0.74, top + 0.28, 0.33), (1.0, 0.18, 0.72), "2f9e9e", "Fabric", rot=(0, -7, 0))
    m.block("Jug", (-0.85, top + 0.4, 0.55), (0.56, 0.8, 0.4), "f08a30", "SmoothPlastic", collide=False)
    m.block("JugLabel", (-0.85, top + 0.36, 0.33), (0.4, 0.36, 0.05), "f2f0ea", collide=False, shadow=False)
    m.cyl("JugCap", (-0.95, top + 0.78, 0.55), (-0.95, top + 0.94, 0.55), 0.24, ACCENT, "SmoothPlastic", collide=False)
    m.ellipsoid("JugDrop", (-0.85, top + 0.37, 0.305), (0.14, 0.2, 0.05), ACCENT, collide=False, shadow=False)

    m.attr("Cost", 1200)
    m.attr("DisplayName", "Washing Machine")
    m.attr("Notes", "Front-loading washing machine (primlib parts, fun-builds/models/build_WashingMachine.py + "
                    "laundrylib.py). Drum* spins about Pivot_Drum (authored Z axis), DrumCloth1..4 tumble, Water is "
                    "authored invisible and filled by the client, Door* swings about Pivot_DoorHinge (vertical), "
                    "Dial* turns about Pivot_Dial, Screen shows the countdown on its Front face.")
    return m.finish()
