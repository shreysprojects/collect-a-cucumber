"""Review-only: the FloorLamp switched on (never installed)."""
import os
import importlib.util


def build(D, P):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_FloorLamp.py")
    spec = importlib.util.spec_from_file_location("build_FloorLamp_lit", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.PREVIEW_ON = True
    orig = P.Model

    class LitModel(orig):
        def __init__(self, D, key, category="Home"):
            super().__init__(D, "_FloorLampLit", category)
    P.Model = LitModel
    try:
        return mod.build(D, P)
    finally:
        P.Model = orig
