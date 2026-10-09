"""Review render of the Aquarium CLIENT as the Lua actually builds it: the tank model (primlib) + every runtime part the
behaviour made (fish, flakes) and the posed flap / chest lid, from the DUMP / POSE lines tests.luau prints at 2 s into
a feeding (authored frame, scale 1).

    luau run.luau > dump.txt
    blender -b --factory-startup --python render_dump.py -- dump.txt
-> renders/aqua_feed_front.png, renders/aqua_feed_top.png (next to this file)
"""
import bpy
import sys
import os
import json
import importlib.util
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
FB = os.path.dirname(os.path.dirname(HERE))
GAMES = os.path.dirname(os.path.dirname(FB))
OUT = os.path.join(HERE, "renders")
os.makedirs(OUT, exist_ok=True)
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
dump_path = args[0] if args else os.path.join(HERE, "dump.txt")


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
D = _load(os.path.join(GAMES, "defenses", "defenselib.py"), "defenselib")
D.bpy = bpy
P = _load(os.path.join(FB, "models", "primlib.py"), "primlib")
B = _load(os.path.join(FB, "models", "build_Aquarium.py"), "build_Aquarium")
B.build(D, P)
info = json.load(open(os.path.join(FB, "models", "out", "Aquarium.parts.json"), encoding="utf-8"))
rest = {p["name"]: p["cf"] for p in info["parts"]}


def mat(c):
    M = Matrix.Identity(4)
    for i in range(3):
        for j in range(3):
            M[i][j] = c[3 + i * 3 + j]
        M[i][3] = c[i]
    return M


R2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # Roblox (x, y, z) -> Blender (x, -z, y)

rt = P.Model(D, "_Runtime")
n = 0
for line in open(dump_path, encoding="utf-8"):
    line = line.strip()
    if line.startswith("POSE|"):
        _, name, cfs = line.split("|")
        c = [float(v) for v in cfs.split(",")]
        delta = mat(c) @ mat(rest[name]).inverted()
        o = bpy.data.objects.get("Aquarium." + name)
        o.matrix_world = R2B @ delta @ R2B.inverted() @ o.matrix_world
    elif line.startswith("DUMP|"):
        _, name, shape, size, cfs, col, material = line.split("|")
        s = [float(v) for v in size.split(",")]
        c = [float(v) for v in cfs.split(",")]
        rgb = [float(v) for v in col.split(",")]
        hexc = "".join("%02x" % max(0, min(255, round(v * 255))) for v in rgb)
        R = Matrix(((c[3], c[4], c[5]), (c[6], c[7], c[8]), (c[9], c[10], c[11])))
        mtl = material.split(".")[-1]
        n += 1
        nm = "%s_%d" % (name, n)
        s = [max(0.05, v) for v in s]
        if shape == "Ball":
            rt.ball(nm, tuple(c[:3]), s[0], hexc, mtl, rot=R)
        elif shape == "Wedge":
            rt.wedge(nm, tuple(c[:3]), tuple(s), hexc, mtl, rot=R)
        elif shape == "Ellipsoid":
            rt.ellipsoid(nm, tuple(c[:3]), tuple(s), hexc, mtl, rot=R)
        else:
            rt.block(nm, tuple(c[:3]), tuple(s), hexc, mtl, rot=R)
rt.finish()
print("runtime parts", n)

c = D.coll("_Stage")
D.clear_collection("_Stage")
import bmesh
bm = bmesh.new()
D.box(bm, (-11, -9, -0.25), (11, 9, 0.0))
D.new_obj("Floor", bm, c, "5c6672", roughness=0.95)
D.bounds = lambda cn: (Vector((-3.1, -1.4, 3.0)), Vector((3.1, 1.4, 6.9)))
D.render(["Aquarium", "_Runtime"], os.path.join(OUT, "aqua_feed_front.png"), size=(960, 640), yaw_deg=0, pitch_deg=6,
         margin=1.02, with_stage=True, show_ref=False, focus=(0, 0, 4.7))
D.render(["Aquarium", "_Runtime"], os.path.join(OUT, "aqua_feed_top.png"), size=(960, 640), yaw_deg=20, pitch_deg=40,
         margin=1.05, with_stage=True, show_ref=False, focus=(0, 0, 4.8))
print("RENDER OK")
