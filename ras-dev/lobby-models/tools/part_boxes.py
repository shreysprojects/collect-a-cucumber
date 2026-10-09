"""part_boxes.py -- list every part of a lobby model with its axis-aligned box (to pick collider patterns).

    blender -b --factory-startup --python tools/part_boxes.py -- <Key> [filter-substring]

Prints one line per part: name, mesh label, collide flag, AABB min/max in BLENDER coords (z up, front +Y), size, and
fill = mesh volume / box volume (low fill = rotated or hollow part, a poor box collider).
"""
import bpy, bmesh, sys, os, importlib.util
from mathutils import Vector
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = sys.argv[sys.argv.index("--") + 1:]
key = args[0]
flt = args[1].lower() if len(args) > 1 else ""
bpy.ops.wm.read_factory_settings(use_empty=True)
sys.path.insert(0, ROOT)


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


L = _load(os.path.join(ROOT, "lobbylib.py"), "lobbylib")
B = _load(os.path.join(ROOT, "models", "build_" + key + ".py"), "b")
B.build(L)
bpy.context.view_layer.update()
rows = []
for o in bpy.data.collections[key].objects:
    name = o.get("rbx_part", o.name)
    if flt and flt not in name.lower() and flt not in str(o.get("rbx_mesh", "")).lower():
        continue
    ws = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector((min(p.x for p in ws), min(p.y for p in ws), min(p.z for p in ws)))
    hi = Vector((max(p.x for p in ws), max(p.y for p in ws), max(p.z for p in ws)))
    b = bmesh.new()
    b.from_mesh(o.data)
    vol = abs(b.calc_volume())
    b.free()
    box = max(1e-6, (hi.x - lo.x) * (hi.y - lo.y) * (hi.z - lo.z))
    rows.append((name, o.get("rbx_mesh"), bool(o.get("rbx_collide")), lo, hi, vol / box))
rows.sort(key=lambda r: (r[1], r[0]))
for name, label, col, lo, hi, fill in rows:
    s = hi - lo
    print("BOX %-22s %-16s col=%d min(%6.2f %6.2f %6.2f) max(%6.2f %6.2f %6.2f) size(%5.2f %5.2f %5.2f) fill %.2f" % (
        name[:22], str(label)[:16], col, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, s.x, s.y, s.z, fill))
