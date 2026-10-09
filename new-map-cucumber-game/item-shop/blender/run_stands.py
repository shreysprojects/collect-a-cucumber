"""run_stands.py -- build the cart display fixtures headless (fresh empty scene, never the user's open
Blender), write out/<Key>.parts.json, render each fixture, save stands.blend.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --python run_stands.py [-- Key ...]
"""
import bpy
import sys
import os
import json
import traceback
import importlib.util

ROOT = os.path.dirname(os.path.abspath(__file__))
GAMES = os.path.dirname(os.path.dirname(os.path.dirname(ROOT)))
OUT = os.path.join(ROOT, "out")
RENDERS = os.path.join(ROOT, "renders")
os.makedirs(OUT, exist_ok=True)
os.makedirs(RENDERS, exist_ok=True)

only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
D = _load(os.path.join(GAMES, "defenses", "defenselib.py"), "defenselib")
L = _load(os.path.join(GAMES, "new-map-cucumber-game", "items", "itemlib.py"), "itemlib")
L.FBX_DIR = OUT  # parts.json go next to this script, not into items/fbx
B = _load(os.path.join(ROOT, "build_stands.py"), "build_stands")

D.build_stage(size=(30.0, 14.0), ref_at=(-10.0, 4.0, 0.0))

built = []
for key, fn in B.BUILDERS:
    if only and key not in only:
        continue
    try:
        info = fn(D)
    except Exception:
        print("BUILD ERROR " + key + "\n" + traceback.format_exc())
        continue
    L.write_parts(info)
    rep = D.report(key)
    print("REPORT " + json.dumps({"key": key, "parts": rep["parts"], "tris": rep["tris"], "size_studs": rep["size_studs"], "min_z": rep["min_z"]}))
    built.append(key)

VIEWS = {
    "ItemStand": dict(yaw_deg=18, pitch_deg=20, with_stage=True, show_ref=True),
    "HeadbandRack": dict(yaw_deg=18, pitch_deg=20, with_stage=True, show_ref=True),
    "ItemSign": dict(yaw_deg=0, pitch_deg=4, with_stage=False),
    "MiniFlask": dict(yaw_deg=25, pitch_deg=15, with_stage=False),
    "MiniBolt": dict(yaw_deg=0, pitch_deg=5, with_stage=False),
}
for key in built:
    try:
        kw = VIEWS.get(key, {})
        D.render([key], os.path.join(RENDERS, key + ".png"), size=(1100, 640), margin=1.08, **kw)
        print("RENDER " + key)
        if key in ("ItemStand", "HeadbandRack"):
            D.render([key], os.path.join(RENDERS, key + "_front.png"), size=(1100, 500), yaw_deg=0, pitch_deg=12, margin=1.05, with_stage=False)
    except Exception:
        print("RENDER ERROR " + key + "\n" + traceback.format_exc())

try:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "stands.blend"))
    print("BLEND saved")
except Exception:
    print("BLEND ERROR\n" + traceback.format_exc())
print("DONE " + ",".join(built))
