"""Blender headless: render the runtime koi (poses dumped by the Luau harness, KOI lines in out.txt) with primlib.
blender -b --factory-startup --python koi_preview.py"""
import bpy, os, sys, importlib.util, math
from mathutils import Matrix
HERE = os.path.dirname(os.path.abspath(__file__))
FBM = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds\models"
GAMES = r"C:\Users\shrey\OneDrive\Documents\RobloxGames"
ZOOM = 3.0


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
D = _load(os.path.join(GAMES, "defenses", "defenselib.py"), "defenselib")
D.bpy = bpy
P = _load(os.path.join(FBM, "primlib.py"), "primlib")

m = P.Model(D, "KoiPreview")
lines = [l.split() for l in open(os.path.join(HERE, "out.txt"), encoding="utf-8") if l.startswith("KOI ")]
xs, zs = [], []
for i, t in enumerate(lines):
    name, shape = t[1], t[2]
    px, py, pz = (float(v) * ZOOM for v in t[3:6])
    r = [float(v) for v in t[6:15]]
    sx, sy, sz = (max(0.05, float(v) * ZOOM) for v in t[15:18])
    cr, cg, cb = (float(v) for v in t[18:21])
    alpha = float(t[21])
    col = "%02x%02x%02x" % (round(cr * 255), round(cg * 255), round(cb * 255))
    rot = Matrix(((r[0], r[1], r[2]), (r[3], r[4], r[5]), (r[6], r[7], r[8])))
    kw = dict(rot=rot, transparency=alpha)
    nm = "%s_%d" % (name, i)
    if shape == "Wedge":
        m.wedge(nm, (px, py, pz), (sx, sy, sz), col, **kw)
    elif shape == "Ball":
        m.ball(nm, (px, py, pz), sx, col, **kw)
    else:
        m.ellipsoid(nm, (px, py, pz), (sx, sy, sz), col, **kw)
    xs.append(px); zs.append(pz)
# a dark pond bed under them (world bed top 0.16 x 1.3) for contrast
cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
m.block("Bed", (cx, 0.10 * 1.3 * ZOOM, cz), (max(xs) - min(xs) + 6, 0.12 * ZOOM, max(zs) - min(zs) + 6), "1d6f9c", "Slate")
info = m.finish()
for tag, yaw, pitch in (("top", 0, 70), ("three", 38, 30)):
    D.render(["KoiPreview"], os.path.join(HERE, "koi_%s.png" % tag), size=(900, 700), yaw_deg=yaw, pitch_deg=pitch,
             margin=1.05, with_stage=False, show_ref=False)
print("RENDERED", info["part_count"])
