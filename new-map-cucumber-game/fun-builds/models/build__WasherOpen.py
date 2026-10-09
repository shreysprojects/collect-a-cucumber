"""_WasherOpen -- REVIEW ONLY (never installed): the WashingMachine mid-cycle pose used to check the pivots.
Door swung open about Pivot_DoorHinge (-105 degrees, as the client does), drum turned 25 degrees, water shown,
dial wound. Its out/_WasherOpen.parts.json is deleted after the renders; the renders stay for the integrator."""
import os
import importlib.util


def build(D, P):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_WashingMachine.py")
    spec = importlib.util.spec_from_file_location("build_WashingMachine_preview", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build(D, P, key="_WasherOpen", pose={"door": -105, "drum": 25, "water": True, "dial": 120})
