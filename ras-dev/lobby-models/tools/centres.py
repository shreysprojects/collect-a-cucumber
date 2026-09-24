"""Print each merged mesh's bbox centre (Blender coords) for a key, to compare with the uploaded asset's MeshPart positions.
    blender -b --factory-startup --python tools/centres.py -- <Key>
"""
import bpy, bmesh, sys, os, json, importlib.util
from mathutils import Vector
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
key = sys.argv[sys.argv.index("--") + 1]
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
groups = {}
for o in bpy.data.collections[key].objects:
    look = (o["rbx_mesh"], o["rbx_hex"], o["rbx_material"])
    for c in o.bound_box:
        p = o.matrix_world @ Vector(c)
        g = groups.setdefault(look, [Vector((1e9,) * 3), Vector((-1e9,) * 3)])
        g[0] = Vector((min(g[0].x, p.x), min(g[0].y, p.y), min(g[0].z, p.z)))
        g[1] = Vector((max(g[1].x, p.x), max(g[1].y, p.y), max(g[1].z, p.z)))
out = {}
for look, (lo, hi) in groups.items():
    c = (lo + hi) / 2
    out.setdefault(look[0], []).append([round(c.x, 3), round(c.y, 3), round(c.z, 3)])
print("CENTRES " + json.dumps(out))
