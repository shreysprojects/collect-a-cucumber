"""export_mesh.py -- build a lobby model and write the MERGED-MESH FBX for the Open Cloud upload.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python export_mesh.py -- <Key> [<Key> ...]

Builds models/build_<Key>.py in a fresh scene, then merges every part that shares (mesh label, look) into ONE
object named after the label (a second look under the same label becomes <label>_2, ...). Look = colour, material,
transparency, reflectance, collide, shadow. Each merged object's origin sits at its own bounding-box centre
(Roblox puts a MeshPart's CFrame there anyway).

Writes out/<Key>.fbx and out/<Key>.mesh.json:
  {key, build_hash, size_studs, min, max, attrs, objects: [{name, color, material, transparency, reflectance,
   collide, shadow, tris, parts}]}
The installer re-applies each object's look by name (FBX imports arrive grey) and undoes the importer's 180-degree
yaw. Blender (x, y, z) -> Roblox (x, z, -y).
"""
import bpy
import bmesh
import sys
import os
import json
import hashlib
import traceback
import importlib.util
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "out")
os.makedirs(OUT, exist_ok=True)


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def export(key):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sys.path.insert(0, ROOT)
    L = _load(os.path.join(ROOT, "lobbylib.py"), "lobbylib")
    src_path = os.path.join(ROOT, "models", "build_" + key + ".py")
    B = _load(src_path, "build_" + key)
    info = B.build(L)
    if info["problems"]:
        print("EXPORT WARN %s problems: %s" % (key, info["problems"]))
    coll = bpy.data.collections[key]
    bpy.context.view_layer.update()

    groups, order = {}, []
    for o in sorted(coll.objects, key=lambda o: o.name):
        if o.type != 'MESH':
            continue
        look = (o["rbx_mesh"], o["rbx_hex"], o["rbx_material"], round(float(o["rbx_transparency"]), 3),
                round(float(o.get("rbx_reflectance", 0.0)), 3), bool(o["rbx_collide"]), bool(o["rbx_shadow"]))
        if look not in groups:
            groups[look] = []
            order.append(look)
        groups[look].append(o)
    # stable, readable naming: first look of a label keeps the bare label
    order.sort(key=lambda lk: (lk[0], -sum(len(o.data.polygons) for o in groups[lk])))

    out_coll = bpy.data.collections.new(key + "_Export")
    bpy.context.scene.collection.children.link(out_coll)
    taken, objects, merged = set(), [], []
    for look in order:
        label = look[0]
        name, i = label, 2
        while name in taken:
            name = "%s_%d" % (label, i)
            i += 1
        taken.add(name)
        b = bmesh.new()
        for o in groups[look]:
            tmp = o.data.copy()
            tmp.transform(o.matrix_world)
            b.from_mesh(tmp)
            bpy.data.meshes.remove(tmp)
        bmesh.ops.triangulate(b, faces=b.faces)
        lo = Vector((min(v.co.x for v in b.verts), min(v.co.y for v in b.verts), min(v.co.z for v in b.verts)))
        hi = Vector((max(v.co.x for v in b.verts), max(v.co.y for v in b.verts), max(v.co.z for v in b.verts)))
        centre = (lo + hi) / 2
        bmesh.ops.translate(b, verts=b.verts, vec=-centre)
        me = bpy.data.meshes.new(name)
        b.to_mesh(me)
        b.free()
        ob = bpy.data.objects.new(name, me)
        ob.location = centre
        out_coll.objects.link(ob)
        merged.append(ob)
        objects.append({"name": name, "color": look[1], "material": look[2], "transparency": look[3],
                        "reflectance": look[4], "collide": look[5], "shadow": look[6],
                        "tris": len(me.polygons), "parts": len(groups[look]),
                        "size": [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)]})
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        o.select_set(o in merged)
    bpy.context.view_layer.objects.active = merged[0]
    fbx = os.path.join(OUT, key + ".fbx")
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL',
                             global_scale=1.0, axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE',
                             use_mesh_modifiers=True, path_mode='COPY', embed_textures=False, bake_anim=False,
                             use_custom_props=False)
    # colliders: merged look-groups span separate islands all over the model, and Roblox's convex decomposition of
    # such a mesh bridges them into invisible walls (measured 2026-09-24: Launchers / GoldBits / Clouds hulls stood
    # across the whole front). So every MeshPart ships NON-colliding and the solid volumes come from invisible box
    # Parts: the axis-aligned box of each part whose name matches models/colliders.json[<Key>] (fnmatch patterns).
    colliders = []
    cfg_path = os.path.join(ROOT, "models", "colliders.json")
    patterns = [p for p in (json.load(open(cfg_path, encoding="utf-8")).get(key, []) if os.path.exists(cfg_path) else [])
                if isinstance(p, str)]
    import fnmatch
    for o in sorted(coll.objects, key=lambda o: o.name):
        if o.type != 'MESH':
            continue
        pname = o.get("rbx_part", o.name)
        if not any(fnmatch.fnmatchcase(pname, pat) for pat in patterns):
            continue
        ws = [o.matrix_world @ v.co for v in o.data.vertices]
        lo = Vector((min(p.x for p in ws), min(p.y for p in ws), min(p.z for p in ws)))
        hi = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
        size = hi - lo
        if min(size) < 0.05:
            continue
        c = (lo + hi) / 2
        colliders.append({"name": pname, "centre": [round(c.x, 3), round(c.z, 3), round(-c.y, 3)],
                          "size": [round(max(size.x, 0.2), 3), round(max(size.z, 0.2), 3), round(max(size.y, 0.2), 3)]})
    # explicit boxes ({"name", "min", "max"} in Blender coords) for volumes no single part covers, e.g. the Shop's
    # stall interior up to the awning (a Humanoid steps up onto a 3-stud counter otherwise)
    for extra in (e for e in (json.load(open(cfg_path, encoding="utf-8")).get(key, []) if os.path.exists(cfg_path) else [])
                  if isinstance(e, dict)):
        lo, hi = Vector(extra["min"]), Vector(extra["max"])
        c, size = (lo + hi) / 2, hi - lo
        colliders.append({"name": extra["name"], "centre": [round(c.x, 3), round(c.z, 3), round(-c.y, 3)],
                          "size": [round(size.x, 3), round(size.z, 3), round(size.y, 3)]})
    h = hashlib.sha1()
    for p in (src_path, os.path.join(ROOT, "lobbylib.py")) + ((cfg_path,) if os.path.exists(cfg_path) else ()):
        h.update(open(p, "rb").read())
    meta = {"key": key, "build_hash": h.hexdigest()[:12], "size_studs": info["size_studs"], "min": info["min"],
            "max": info["max"], "attrs": info.get("attrs", {}), "tris_total": sum(o["tris"] for o in objects),
            "objects": objects, "colliders": colliders}
    with open(os.path.join(OUT, key + ".mesh.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=1)
    print("MESH %s: %d parts -> %d meshes, %d tris, fbx %d KB, hash %s" % (
        key, info["parts"], len(objects), meta["tris_total"], os.path.getsize(fbx) // 1024, meta["build_hash"]))


keys = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for k in keys:
    try:
        export(k)
    except Exception:
        print("MESH ERROR " + k + "\n" + traceback.format_exc())
