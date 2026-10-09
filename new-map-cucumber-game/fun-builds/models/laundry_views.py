"""laundry_views.py -- extra review angles for the HomeLaundry builds (fun-builds 2026-09-24), headless:

    blender -b --factory-startup --python laundry_views.py -- <Key> <tag>:<yaw>:<pitch> [...]

Builds models/build_<Key>.py in a fresh scene (like run_one.py, but writes NO parts.json) and renders
renders/<Key>_<tag>.png for each yaw / pitch (yaw 0 = the build's front, +90 = its right-hand side as seen
from the front... i.e. the -X side, 180 = back). The 6-stud avatar stands beside it as usual.
"""
import bpy
import sys
import os
import importlib.util

ROOT = os.path.dirname(os.path.abspath(__file__))
GAMES = os.path.dirname(os.path.dirname(os.path.dirname(ROOT)))
RENDERS = os.path.join(ROOT, "renders")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
key, shots = args[0], args[1:]


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
D = _load(os.path.join(GAMES, "defenses", "defenselib.py"), "defenselib")
D.bpy = bpy
P = _load(os.path.join(ROOT, "primlib.py"), "primlib")
RUN = _load(os.path.join(ROOT, "run_one.py").replace("run_one.py", "build_" + key + ".py"), "build_" + key)
info = RUN.build(D, P)

import bmesh  # noqa: E402
c = D.coll("_Stage")
D.clear_collection("_Stage")
bm = bmesh.new()
D.box(bm, (-12, -10, -0.25), (12, 10, 0.0))
D.new_obj("Floor", bm, c, "5c6672", roughness=0.95)
bm = bmesh.new()
s = 6.0 / 5.0
D.box(bm, (-1.0 * s, -0.5 * s, 0.0), (1.0 * s, 0.5 * s, 3.5 * s))
D.box(bm, (-0.6 * s, -0.4 * s, 3.5 * s), (0.6 * s, 0.4 * s, 5.0 * s))
o = D.new_obj("ScaleRef", bm, c, "d94f4f", roughness=0.8)
o.location = (info["max"][0] + 2.6, 0.0, 0.0)  # on the +X side (the vent side -X stays clear)
for shot in shots:
    tag, yaw, pitch = shot.split(":")
    D.render([info["key"]], os.path.join(RENDERS, "%s_%s.png" % (info["key"], tag)), size=(720, 600),
             yaw_deg=float(yaw), pitch_deg=float(pitch), margin=1.12, with_stage=True, show_ref=False)
print("VIEWS " + ", ".join(shots))
