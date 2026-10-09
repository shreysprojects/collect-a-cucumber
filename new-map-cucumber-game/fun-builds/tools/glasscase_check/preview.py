"""Headless review renders for the GlassCase package (trophies + neon overlays), from geometry.json
(the real Luau TrophySpecs / Layout output). Run:
  blender -b --factory-startup --python preview.py -- [trophies|case|neon|all]
"""
import bpy, sys, os, json, math, importlib.util, bmesh
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
GAMES = r"C:\Users\shrey\OneDrive\Documents\RobloxGames"
FB = os.path.join(GAMES, "new-map-cucumber-game", "fun-builds")
RENDERS = os.path.join(FB, "models", "renders")
os.makedirs(RENDERS, exist_ok=True)
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["all"]
what = args[0] if args else "all"


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
D = _load(os.path.join(GAMES, "props", "proplib.py"), "proplib")
D.bpy = bpy
P = _load(os.path.join(FB, "models", "primlib.py"), "primlib")
geo = json.load(open(os.path.join(HERE, "geometry.json"), encoding="utf-8"))
_n = [0]


def add_part(coll, shape, size, cf, color, material, transparency=0.0, offset=(0, 0, 0), scale=1.0, rot=None):
    """A Roblox-frame part (cf = x,y,z,R00..R22) -> Blender object. rot (3x3) turns it about `offset`."""
    _n[0] += 1
    sx, sy, sz = [s * scale for s in size]
    R = Matrix(((cf[3], cf[4], cf[5]), (cf[6], cf[7], cf[8]), (cf[9], cf[10], cf[11])))
    t = Vector((cf[0] * scale, cf[1] * scale, cf[2] * scale))
    if rot is not None:
        R = rot @ R
        t = rot @ t
    t = t + Vector(offset)
    if shape == "Block":
        v, f = P._box_geo(sx, sy, sz)
    elif shape == "Wedge":
        v, f = P._wedge_geo(sx, sy, sz)
    elif shape == "Cylinder":
        v, f = P._cyl_geo(sx, sy, 20)
    else:
        v, f = P._sphere_geo(sx, sy, sz)
    bm = bmesh.new()
    verts = [bm.verts.new(P._to_blender(R @ Vector(p) + t)) for p in v]
    for face in f:
        try:
            bm.faces.new([verts[i] for i in face])
        except ValueError:
            pass
    return D.new_obj("p%03d" % _n[0], bm, coll, color, rbx_material=material, transparency=transparency,
                     metallic=0.55 if material in ("Metal",) else 0.15,
                     roughness=0.28 if material in ("SmoothPlastic", "Marble") else 0.6,
                     smooth=shape in ("Cylinder", "Ball", "Ellipsoid"),
                     emit=1.3 if material == "Neon" else None)


def stage(width=40.0, depth=30.0, avatar_x=None):
    c = D.coll("_Stage")
    D.clear_collection("_Stage")
    bm = bmesh.new()
    D.box(bm, (-width / 2, -depth / 2, -0.25), (width / 2, depth / 2, 0.0))
    D.new_obj("Floor", bm, c, "5c6672", roughness=0.95)
    if avatar_x is not None:
        bm = bmesh.new()
        s = 6.0 / 5.0
        D.box(bm, (-1.0 * s, -0.5 * s, 0.0), (1.0 * s, 0.5 * s, 3.5 * s))
        D.box(bm, (-0.6 * s, -0.4 * s, 3.5 * s), (0.6 * s, 0.4 * s, 5.0 * s))
        D.box(bm, (-1.5 * s, -0.35 * s, 1.9 * s), (-1.0 * s, 0.35 * s, 3.5 * s))
        D.box(bm, (1.0 * s, -0.35 * s, 1.9 * s), (1.5 * s, 0.35 * s, 3.5 * s))
        o = D.new_obj("ScaleRef", bm, c, "d94f4f", roughness=0.8)
        o.location = (avatar_x, 0.0, 0.0)


def trophy(coll, d, offset, scale, spin_deg=0.0, opaque=False):
    rot = Matrix.Rotation(math.radians(spin_deg), 3, 'Y')  # about Roblox +Y
    for p in geo["trophies"][d - 1]:
        add_part(coll, p["shape"], p["size"], p["cf"], p["color"], p["material"], 0.0 if opaque else p["transparency"], offset, scale, rot)


def lerp_hex(a, b, t):
    ca = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "".join("%02x" % round(ca[i] + (cb[i] - ca[i]) * t) for i in range(3))


def report_trophies():
    for d, parts in enumerate(geo["trophies"], 1):
        lo, hi = 1e9, -1e9
        xs = []
        for p in parts:
            cf, s = p["cf"], p["size"]
            ext = 0.5 * (abs(cf[6]) * s[0] + abs(cf[7]) * s[1] + abs(cf[8]) * s[2])
            lo, hi = min(lo, cf[1] - ext), max(hi, cf[1] + ext)
            extx = 0.5 * (abs(cf[3]) * s[0] + abs(cf[4]) * s[1] + abs(cf[5]) * s[2])
            xs.append(abs(cf[0]) + extx)
        print("TROPHY %d parts=%d y=%.3f..%.3f height=%.3f maxRadiusX=%.3f" % (d, len(parts), lo, hi, hi - lo, max(xs)))


report_trophies()

if what in ("trophies", "all"):
    c = D.coll("Trophies")
    D.clear_collection("Trophies")
    stage()
    for d in range(1, 6):
        trophy(c, d, ((3 - d) * 2.1, 0.0, 0.0), 1.25, spin_deg=-25)
    D.render(["Trophies"], os.path.join(RENDERS, "GlassCase_trophies.png"), size=(1100, 520), yaw_deg=0,
             pitch_deg=12, margin=1.08, with_stage=True, show_ref=False)
    D.render(["Trophies"], os.path.join(RENDERS, "GlassCase_trophies_top.png"), size=(1100, 520), yaw_deg=30,
             pitch_deg=42, margin=1.08, with_stage=True, show_ref=False)
    print("RENDERED trophies")

if what in ("case", "all"):
    B = _load(os.path.join(GAMES, "props", "build_glass_case.py"), "build_glass_case")
    for d in (1, 2, 3, 4, 5):
        B.build(D)
        c = D.coll("Trophy")
        D.clear_collection("Trophy")
        stage(avatar_x=-4.6)
        trophy(c, d, (0.0, 3.05 + 0.08 + 0.06, 0.0), 1.0, spin_deg=-20, opaque=(d == 5))
        # the server's nameplate: brass block over the TROPHY plate
        add_part(c, "Block", [2.5, 0.52, 0.1], [0, 0.53, -1.48, 1, 0, 0, 0, 1, 0, 0, 0, 1], "c9a227", "Metal")
        D.render(["GlassCase", "Trophy"], os.path.join(RENDERS, "GlassCase_case_%d.png" % d), size=(760, 760),
                 yaw_deg=18, pitch_deg=10, margin=1.1, with_stage=True, show_ref=False)
    print("RENDERED case")

if what in ("neon", "all"):
    NS = _load(os.path.join(GAMES, "props", "build_neon_sign.py"), "build_neon_sign")
    for letter in ("B", "C"):
        NS.build(D)
        sign = bpy.data.collections["NeonSign"]
        for o in list(sign.objects):
            if not o.name.split(".", 1)[1].startswith(letter + "_"):
                bpy.data.objects.remove(o, do_unlink=True)
        c = D.coll("Overlay")
        D.clear_collection("Overlay")
        stage()
        L = geo["neon"][letter]
        for b in L["balls"]:
            lit = (b["group"] % 2 == 1)
            pos = b["pos"]
            add_part(c, "Ball", [b["d"]] * 3, [pos[0], pos[1], pos[2], 1, 0, 0, 0, 1, 0, 0, 0, 1],
                     "ffe14d" if lit else lerp_hex("ffe14d", "23262c", 0.5), "Neon" if lit else "SmoothPlastic")
        for ci, chev in enumerate(L["chevrons"]):
            for arm in chev:
                add_part(c, "Block", arm["size"], arm["cf"], "ff8a3d" if ci == 0 else lerp_hex("ff8a3d", "23262c", 0.72),
                         "Neon" if ci == 0 else "SmoothPlastic")
        D.render(["NeonSign", "Overlay"], os.path.join(RENDERS, "NeonSign_%s_overlays.png" % letter), size=(900, 720),
                 yaw_deg=0, pitch_deg=4, margin=1.06, with_stage=False, show_ref=False)
        D.render(["NeonSign", "Overlay"], os.path.join(RENDERS, "NeonSign_%s_overlays_side.png" % letter), size=(900, 720),
                 yaw_deg=55, pitch_deg=10, margin=1.06, with_stage=False, show_ref=False)
    print("RENDERED neon")

