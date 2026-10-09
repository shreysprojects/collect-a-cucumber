"""Sofa (Home) -- a chunky 3-seat rolled-arm couch, fun-builds HomeLiving 2026-09-24.

~8 x 3.6 x 3.4 studs, seat puff top 2.1 (1.91 squashed = the seat pivots), back to 3.6. Three seats (Pivot_Seat1..3, facing -Z); the client squashes
Cushion<i> while seat i is taken (FB/src/behaviours/*/Sofa.lua). The couch itself lives in couchlib.py so the
Armchair matches it exactly.
"""
import os
import importlib.util


def _couchlib():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "couchlib.py")
    spec = importlib.util.spec_from_file_location("couchlib", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build(D, P):
    C = _couchlib()
    m = P.Model(D, "Sofa", category="Home")
    C.build_couch(m, P, seats=3, seat_w=2.0, pillows=(("L", 1, "f2c13d"), ("R", -1, "d9443c")))
    m.attr("Cost", 800)
    m.attr("Seats", 3)
    m.attr("Notes", "3-seat rolled-arm sofa (primlib parts). Seats Pivot_Seat1..3 face -Z; Cushion<i> squashes "
                    "while seat i is taken, BackCushion<i> gives a little. Built by fun-builds/models/build_Sofa.py.")
    return m.finish()
