"""Review only (not shipped): the Fridge with both doors swung open, to check the stocked interior.
Delete out/_FridgeOpen.parts.json after a run - it is not a build."""
import os
import importlib.util


def build(D, P):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_Fridge.py")
    spec = importlib.util.spec_from_file_location("build_Fridge_review", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build(D, P, key="_FridgeOpen", open_deg=int(os.environ.get("FRIDGE_OPEN_DEG", "100")))
