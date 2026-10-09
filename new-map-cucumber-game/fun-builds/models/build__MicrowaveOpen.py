"""Review only (not shipped): the Microwave with its door swung open (State_DoorOpen) and the turntable a
quarter turn on, to check the swing direction, the clearance over the cart and the cavity. Delete
out/_MicrowaveOpen.parts.json after a run - it is not a build."""
import os
import importlib.util


def build(D, P):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build_Microwave.py")
    spec = importlib.util.spec_from_file_location("build_Microwave_review", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.build(D, P, key="_MicrowaveOpen", open_deg=int(os.environ.get("MICROWAVE_OPEN_DEG", "-100")),
                     spin_deg=int(os.environ.get("MICROWAVE_SPIN_DEG", "90")))
