"""Review-only: the Fireplace with its embers glowing and candle flames shown (never installed)."""
import os
import importlib.util


def build(D, P):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_Fireplace.py")
    spec = importlib.util.spec_from_file_location("build_Fireplace_lit", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.PREVIEW_LIT = True
    orig = P.Model

    class LitModel(orig):
        def __init__(self, D, key, category="Home"):
            super().__init__(D, "_FireplaceLit", category)
    P.Model = LitModel
    try:
        return mod.build(D, P)
    finally:
        P.Model = orig
