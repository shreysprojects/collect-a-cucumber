"""run_one.py -- build ONE lobby model headless, write out/<Key>.json and review renders.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python run_one.py -- <Key> [--no-render] [--save]

<Key> names models/build_<Key>.py, which must define  build(L) -> L.Model(...).finish().
A fresh empty scene every run (never the user's open Blender), so several of these can run side by side.
--save also writes out/<Key>.blend (used by the central review in the live Blender MCP session).

Renders (renders/<Key>_<view>.png, 900 x 700):
    front   dead-on the front, eye height          (snow floor, 5-stud avatar to the side for scale)
    three   3/4 from the front-left, looking down  (snow floor)
    back    from behind                            (snow floor)
    lobby   3/4 from ~45 studs away on a DARK basalt floor (how it reads in the Volcano / Haunted lobbies)
Prints REPORT {...} (sizes, tris, merged meshes, problems) and RENDERED <paths>.
"""
import bpy
import sys
import os
import json
import math
import traceback
import importlib.util

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "out")
RENDERS = os.path.join(ROOT, "renders")
os.makedirs(OUT, exist_ok=True)
os.makedirs(RENDERS, exist_ok=True)

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not args:
    print("usage: blender -b --factory-startup --python run_one.py -- <Key> [--no-render] [--save]")
    sys.exit(1)
key = args[0]
no_render = "--no-render" in args
save = "--save" in args


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
sys.path.insert(0, ROOT)
L = _load(os.path.join(ROOT, "lobbylib.py"), "lobbylib")
D = L.D
B = _load(os.path.join(ROOT, "models", "build_" + key + ".py"), "build_" + key)

try:
    info = B.build(L)
except Exception:
    print("BUILD ERROR " + key + "\n" + traceback.format_exc())
    sys.exit(2)

with open(os.path.join(OUT, key + ".json"), "w", encoding="utf-8") as f:
    json.dump(info, f, indent=1)
summary = {k: info[k] for k in ("key", "size_studs", "parts", "meshes_after_merge", "labels", "tris_total", "problems")}
print("REPORT " + json.dumps(summary))

if save:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, key + ".blend"))

if no_render:
    sys.exit(0)


def stage(floor_hex, width, depth, avatar_at):
    import bmesh
    c = D.coll("_Stage")
    D.clear_collection("_Stage")
    b = bmesh.new()
    D.box(b, (-width / 2, -depth / 2, -0.25), (width / 2, depth / 2, 0.0))
    D.new_obj("Floor", b, c, floor_hex, roughness=0.95)
    b = bmesh.new()  # R15-ish blockout, 5 studs tall
    D.box(b, (-1.0, -0.5, 0.0), (1.0, 0.5, 3.5))
    D.box(b, (-0.6, -0.4, 3.5), (0.6, 0.4, 5.0))
    D.box(b, (-1.5, -0.35, 1.9), (-1.0, 0.35, 3.5))
    D.box(b, (1.0, -0.35, 1.9), (1.5, 0.35, 3.5))
    o = D.new_obj("ScaleRef", b, c, "d94f4f", roughness=0.8)
    o.location = avatar_at


_orig_world = D._setup_world


def _world(scene, bg=None):
    _orig_world(scene, bg=(0.46, 0.60, 0.76))  # lobby-ish sky
    node = next((n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND'), None)
    if node:
        node.inputs[1].default_value = 0.55    # a full-strength sky washes the flat colours out to pastel


D._setup_world = _world

try:
    scene = bpy.context.scene
    try:
        scene.eevee.taa_render_samples = 24
    except Exception:
        pass
    mn, mx = info["min"], info["max"]
    sx = mx[0] - mn[0]
    sy = mx[1] - mn[1]
    avatar = (mn[0] - 2.4, 0.0, 0.0)  # viewer's RIGHT when looking at the front
    paths = []
    stage("ebf6fc", max(30.0, sx * 2.2 + 12), max(24.0, sy * 3 + 14), avatar)
    for tag, yaw, pitch, margin in (("front", 0, 8, 1.08), ("three", -35, 22, 1.08), ("back", 180, 14, 1.08)):
        p = os.path.join(RENDERS, "%s_%s.png" % (key, tag))
        D.render([key], p, size=(900, 700), yaw_deg=yaw, pitch_deg=pitch, margin=margin, with_stage=True,
                 show_ref=(tag != "back"))
        paths.append(p)
    stage("2f2b2e", 140.0, 140.0, avatar)
    p = os.path.join(RENDERS, "%s_lobby.png" % key)
    D.render([key], p, size=(900, 700), yaw_deg=30, pitch_deg=14, margin=2.6, with_stage=True, show_ref=True)
    paths.append(p)
    print("RENDERED " + ", ".join(paths))
except Exception:
    print("RENDER ERROR " + key + "\n" + traceback.format_exc())
    sys.exit(3)
