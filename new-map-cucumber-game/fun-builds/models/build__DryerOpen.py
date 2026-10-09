"""_DryerOpen -- REVIEW ONLY (never installed): the Dryer mid-cycle pose used to check the pivots.
Door swung open about Pivot_DoorHinge (-105 degrees, as the client does), drum turned 25 degrees, vent louvres open,
dial wound. Its out/_DryerOpen.parts.json is deleted after the renders; the renders stay for the integrator."""
import os
import importlib.util


def build(D, P):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_Dryer.py")
    spec = importlib.util.spec_from_file_location("build_Dryer_preview", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build(D, P, key="_DryerOpen", pose={"door": -105, "drum": 25, "vent": 40, "dial": 120})
