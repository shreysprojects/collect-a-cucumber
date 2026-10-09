"""run_items.py -- build every drop item headless, write parts.json + FBX per item, render each one
and a line-up sheet, and save items/items.blend (2026-09-23).

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --python run_items.py [-- Key ...]

A fresh empty scene is used (never the user's open Blender), so this runs safely beside a live
Blender session. Prints one REPORT line per item and a SHEET line at the end.
"""
import bpy
import sys
import os
import json
import traceback
import importlib.util

ROOT = os.path.dirname(os.path.abspath(__file__))
GAMES = os.path.dirname(os.path.dirname(ROOT))
FBX = os.path.join(ROOT, "fbx")
RENDERS = os.path.join(ROOT, "renders")
os.makedirs(FBX, exist_ok=True)
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
L = _load(os.path.join(ROOT, "itemlib.py"), "itemlib")
B = _load(os.path.join(ROOT, "build_items.py"), "build_items")

# a small neutral floor for the renders (no 5-stud avatar: the items are hand-sized)
D.build_stage(size=(30.0, 8.0), ref_at=(-40.0, 0.0, 0.0))

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


def export_fbx_bg(coll_name, path):
    c = bpy.data.collections[coll_name]
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    objs = [o for o in c.objects if o.type == 'MESH']
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True,
                             apply_scale_options='FBX_SCALE_ALL', global_scale=1.0,
                             axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE',
                             use_mesh_modifiers=True, path_mode='COPY', embed_textures=False,
                             bake_anim=False, use_custom_props=False)


for key in built:
    try:
        export_fbx_bg(key, os.path.join(FBX, key + ".fbx"))
        print("FBX " + key)
    except Exception:
        print("FBX ERROR " + key + "\n" + traceback.format_exc())

# renders: each item alone from the front-right, then all of them in a row
for key in built:
    try:
        D.render([key], os.path.join(RENDERS, key + ".png"), size=(640, 640), yaw_deg=32, pitch_deg=18,
                 margin=1.15, with_stage=False)
        print("RENDER " + key)
    except Exception:
        print("RENDER ERROR " + key + "\n" + traceback.format_exc())

if len(built) > 1:
    spacing = 2.4
    x0 = -spacing * (len(built) - 1) / 2
    for i, key in enumerate(built):
        for o in bpy.data.collections[key].objects:
            o.location.x = x0 + i * spacing
    try:
        D.render(built, os.path.join(RENDERS, "sheet.png"), size=(1800, 700), yaw_deg=0, pitch_deg=14,
                 margin=1.05, with_stage=True, show_ref=False)
        print("SHEET " + os.path.join(RENDERS, "sheet.png"))
    except Exception:
        print("SHEET ERROR\n" + traceback.format_exc())
    for key in built:
        for o in bpy.data.collections[key].objects:
            o.location.x = 0.0

try:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "items.blend"))
    print("BLEND saved")
except Exception:
    print("BLEND ERROR\n" + traceback.format_exc())
print("DONE " + ",".join(built))
