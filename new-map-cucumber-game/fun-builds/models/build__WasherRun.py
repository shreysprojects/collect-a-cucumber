"""_WasherRun -- REVIEW ONLY (never installed): the WashingMachine mid-wash with the porthole SHUT - water shown,
drum turned 25 degrees, dial wound - to check the water reads through the SmoothPlastic DoorGlass (Roblox's Glass
material would hide it in game). Its out/_WasherRun.parts.json is deleted after the renders."""
import os
import importlib.util


def build(D, P):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_WashingMachine.py")
    spec = importlib.util.spec_from_file_location("build_WashingMachine_preview", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build(D, P, key="_WasherRun", pose={"door": 0, "drum": 25, "water": True, "dial": 120})
