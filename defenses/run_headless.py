"""run_headless.py -- build ONE prop script headless, report, render, export its FBX.

    blender -b defenses.blend --python run_headless.py -- build_mortar.py Mortar [yaw pitch margin]

Loads defenselib + the named build script from disk, builds the collection into the open
scene (the .blend is NEVER saved by this runner - several props build in parallel from the
same file), prints a JSON report (parts, tris, size, min_z, per-part tris), renders
renders/<Collection>.png (three-quarter) and renders/<Collection>_eye.png (player's eye),
and exports fbx/<Collection>.fbx (background-safe: no temp_override, plain selection).
Exit code 1 on a build error (the traceback is printed).
"""
import bpy
import sys
import os
import json
import math
import traceback
import importlib.util

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\defenses"
RENDERS = os.path.join(ROOT, "renders")
FBX = os.path.join(ROOT, "fbx")
os.makedirs(RENDERS, exist_ok=True)
os.makedirs(FBX, exist_ok=True)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    print("usage: -- build_<prop>.py <Collection> [yaw pitch margin]")
    sys.exit(1)
script, cname = argv[0], argv[1]
yaw = float(argv[2]) if len(argv) > 2 else 35.0
pitch = float(argv[3]) if len(argv) > 3 else 22.0
margin = float(argv[4]) if len(argv) > 4 else 1.10


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sys.modules[name] = mod
    return mod


D = _load(os.path.join(ROOT, "defenselib.py"), "defenselib")
D.build_stage()
try:
    mod = _load(os.path.join(ROOT, script), "build_" + cname)
    mod.build(D)
except Exception:
    print("BUILD ERROR\n" + traceback.format_exc())
    sys.exit(1)

rep = D.report(cname)
rep["notes"] = getattr(mod, "NOTES", "")
for extra in ("PIVOTS", "STATES"):
    if hasattr(mod, extra):
        rep[extra] = getattr(mod, extra)
print("REPORT " + json.dumps(rep, default=str))

hero = os.path.join(RENDERS, cname + ".png")
D.render([cname], hero, size=(960, 700), yaw_deg=yaw, pitch_deg=pitch, margin=margin)
eye = os.path.join(RENDERS, cname + "_eye.png")
D.render([cname], eye, size=(900, 640), yaw_deg=12, pitch_deg=8, margin=1.10)
print("RENDERS " + hero + " " + eye)


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
    return path


out = os.path.join(FBX, cname + ".fbx")
try:
    export_fbx_bg(cname, out)
    print("FBX " + out + " " + str(os.path.getsize(out)))
except Exception:
    print("FBX ERROR\n" + traceback.format_exc())

man = D.manifest([cname])
with open(os.path.join(FBX, cname + ".manifest.json"), "w") as f:
    json.dump({"collection": cname, "parts": man, "pivots": getattr(mod, "PIVOTS", {}),
               "states": getattr(mod, "STATES", {}), "notes": rep["notes"], "tris": rep["tris"],
               "size_studs": rep["size_studs"], "min_z": rep["min_z"]}, f, indent=1)
print("MANIFEST " + os.path.join(FBX, cname + ".manifest.json"))
