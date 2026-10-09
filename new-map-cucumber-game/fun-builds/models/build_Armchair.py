"""Armchair (Home) -- the Sofa's matching single rolled-arm chair, fun-builds HomeLiving 2026-09-24.

~4.4 x 3.6 x 3.4 studs, seat puff top 2.1 (1.91 squashed = Pivot_Seat1). One seat (Pivot_Seat1, facing -Z); the client squashes Cushion1 while it is
taken (FB/src/behaviours/*/Sofa.lua serves both keys). A striped knitted throw is folded over the back.
"""
import os
import importlib.util
from mathutils import Vector


def _couchlib():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "couchlib.py")
    spec = importlib.util.spec_from_file_location("couchlib", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


RED = "d9443c"
CREAM = "f2f0ea"


def build(D, P):
    C = _couchlib()
    m = P.Model(D, "Armchair", category="Home")
    C.build_couch(m, P, seats=1, seat_w=2.3)

    # ------------------------------------------------ knitted throw folded over the back roll (viewer's right)
    # Every trim piece is placed in the frame of the panel it sits on and stands >= 0.03 proud of that panel's
    # faces (the contract's no-coplanar rule: flat stripes 0.003-0.015 off a face flicker in Roblox at range).
    x0, w = -0.45, 1.4
    top_y, top_h = 3.655, 0.08
    m.block("ThrowTop", (x0, top_y, 1.36), (w, top_h, 0.72), RED, "Fabric", collide=False)
    # the fold rolls run 0.02 past the throw's sides so their end caps are not coplanar with its side faces
    m.cyl("ThrowFoldFront", (x0 - w / 2 - 0.02, 3.6, 1.0), (x0 + w / 2 + 0.02, 3.6, 1.0), 0.16, RED, "Fabric", collide=False)
    m.cyl("ThrowFoldBack", (x0 - w / 2 - 0.02, 3.56, 1.71), (x0 + w / 2 + 0.02, 3.56, 1.71), 0.2, RED, "Fabric", collide=False)
    tilt = (-2, 0, 0)                      # the hanging panel leans 2 degrees in at the bottom
    R = P.angles(*tilt)
    back_c, back_h, back_d = Vector((x0, 2.78, 1.765)), 1.56, 0.08
    m.block("ThrowBack", tuple(back_c), (w, back_h, back_d), RED, "Fabric", collide=False, rot=tilt)

    def on_back(ly, lz):
        """A point in the hanging panel's own frame (ly up it, lz out of its back face) -> authored."""
        return tuple(back_c + R @ Vector((0, ly, lz)))

    # cream stripes: 0.06 deep, sunk 0.02 into the panel and 0.04 proud of its back face, 0.03 past each side
    for k, ly in enumerate((-0.48, -0.16, 0.42)):
        m.block("ThrowStripe%d" % (k + 1), on_back(ly, back_d / 2 + 0.01), (w + 0.06, 0.12, 0.06), CREAM, "Fabric",
                collide=False, rot=tilt)
    # the stripe across the top: 0.035 above the ThrowTop's upper face, 0.03 past each side
    m.block("ThrowStripeTop", (x0, top_y + top_h / 2 + 0.005, 1.36), (w + 0.06, 0.06, 0.12), CREAM, "Fabric", collide=False)
    # tassels hang off the panel's bottom edge (0.02 up inside it) in its tilt, 0.05 deep: their back faces stand 0.02
    # proud of the panel's back face and their front faces 0.03 inside it
    for k in range(6):
        fx = -w / 2 + 0.12 + k * (w - 0.24) / 5
        m.block("ThrowTassel%d" % (k + 1), tuple(Vector(on_back(-back_h / 2 - 0.09, back_d / 2 + 0.02 - 0.025)) + Vector((fx, 0, 0))),
                (0.09, 0.22, 0.05), CREAM, "Fabric", collide=False, rot=tilt)

    m.attr("Cost", 400)
    m.attr("Seats", 1)
    m.attr("Notes", "Single rolled-arm chair matching the Sofa (primlib parts). Seat Pivot_Seat1 faces -Z; Cushion1 "
                    "squashes while it is taken. Built by fun-builds/models/build_Armchair.py + couchlib.py.")
    return m.finish()
