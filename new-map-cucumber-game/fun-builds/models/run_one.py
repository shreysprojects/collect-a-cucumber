"""run_one.py -- build ONE primlib model headless, write out/<Key>.parts.json and three review renders.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python run_one.py -- <Key>

<Key> names models/build_<Key>.py, which must define  build(D, P) -> P.Model(...).finish().
A fresh empty scene every run (never the user's open Blender), so any number of these run side by side.
Renders (renders/<Key>_front.png, _three.png, _back.png) look from the FRONT (-Z in Roblox) with a
6-stud blockout avatar (New Map characters are ~6 studs tall) standing to the build's side for scale.
Prints REPORT {...} on success, BUILD ERROR / RENDER ERROR + traceback otherwise.
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

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not args:
    print("usage: blender -b --python run_one.py -- <Key> [--no-render]")
    sys.exit(1)
key = args[0]
no_render = "--no-render" in args


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
B = _load(os.path.join(ROOT, "build_" + key + ".py"), "build_" + key)

try:
    info = B.build(D, P)
except Exception:
    print("BUILD ERROR " + key + "\n" + traceback.format_exc())
    sys.exit(2)

with open(os.path.join(OUT, key + ".parts.json"), "w", encoding="utf-8") as f:
    json.dump(info, f, indent=1)
print("REPORT " + json.dumps({"key": key, "parts": info["part_count"], "size_studs": info["size_studs"],
                              "min": info["min"], "max": info["max"], "duplicate_names": info["duplicate_names"],
                              "pivots": list(info["pivots"].keys())}))

if no_render:
    sys.exit(0)


def stage(width, depth, avatar_x):
    """Floor + a 6-stud R15-ish blockout (Blender coords: the build's front faces +Y)."""
    import bmesh
    c = D.coll("_Stage")
    D.clear_collection("_Stage")
    bm = bmesh.new()
    D.box(bm, (-width / 2, -depth / 2, -0.25), (width / 2, depth / 2, 0.0))
    D.new_obj("Floor", bm, c, "5c6672", roughness=0.95)
    bm = bmesh.new()
    s = 6.0 / 5.0
    D.box(bm, (-1.0 * s, -0.5 * s, 0.0), (1.0 * s, 0.5 * s, 3.5 * s))
    D.box(bm, (-0.6 * s, -0.4 * s, 3.5 * s), (0.6 * s, 0.4 * s, 5.0 * s))
    D.box(bm, (-1.5 * s, -0.35 * s, 1.9 * s), (-1.0 * s, 0.35 * s, 3.5 * s))
    D.box(bm, (1.0 * s, -0.35 * s, 1.9 * s), (1.5 * s, 0.35 * s, 3.5 * s))
    o = D.new_obj("ScaleRef", bm, c, "d94f4f", roughness=0.8)
    o.location = (avatar_x, 0.0, 0.0)


try:
    sx, sy, sz = info["size_studs"]
    avatar_x = -(info["max"][0] + 2.6)  # to the build's right as seen from the front (Roblox +X is the viewer's left)
    stage(max(20.0, sx * 2 + 14), max(16.0, sz * 2 + 10), avatar_x)
    shots = [("front", 0, 12), ("three", 38, 24), ("back", 180, 18)]
    for tag, yaw, pitch in shots:
        D.render([key], os.path.join(RENDERS, "%s_%s.png" % (key, tag)), size=(720, 600), yaw_deg=yaw,
                 pitch_deg=pitch, margin=1.12, with_stage=True, show_ref=(tag != "back"))
    print("RENDERED " + ", ".join(os.path.join(RENDERS, "%s_%s.png" % (key, t[0])) for t in shots))
except Exception:
    print("RENDER ERROR " + key + "\n" + traceback.format_exc())
    sys.exit(3)
