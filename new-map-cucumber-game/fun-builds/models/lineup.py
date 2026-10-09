"""lineup.py -- run INSIDE the live Blender (Blender MCP execute_blender_code) to build several primlib models side by side
and render one review sheet:
    exec(open(r"<FB>\\models\\lineup.py").read()); lineup(["Sofa", "Armchair"], "home_lineup")
Builds into collections named after each key in the CURRENT scene (clears them first), spaces them along X with a
6-stud avatar, renders renders/<name>.png, and leaves everything in the scene for inspection.
"""
import bpy, os, sys, json, importlib.util

FB_MODELS = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds\models"
GAMES = r"C:\Users\shrey\OneDrive\Documents\RobloxGames"


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def lineup(keys, name, gap=3.0, yaw=24, pitch=16, size=(1900, 820)):
    D = _load(os.path.join(GAMES, "defenses", "defenselib.py"), "defenselib")
    D.bpy = bpy
    P = _load(os.path.join(FB_MODELS, "primlib.py"), "primlib")
    infos = []
    for key in keys:
        B = _load(os.path.join(FB_MODELS, "build_" + key + ".py"), "build_" + key)
        infos.append((key, B.build(D, P)))
    # lay out left-to-right as seen from the front (+Blender Y); Roblox +X is the viewer's LEFT, so go toward -X
    x = 0.0
    for key, info in infos:
        w = info["size_studs"][0]
        cx = x - w / 2 - (info["max"][0] + info["min"][0]) / 2
        for o in bpy.data.collections[key].objects:
            o.location.x += cx
        x -= w + gap
    total = -x
    c = D.coll("_Stage")
    D.clear_collection("_Stage")
    import bmesh
    bm = bmesh.new()
    D.box(bm, (x - 6, -14, -0.25), (6, 14, 0.0))
    D.new_obj("Floor", bm, c, "5c6672", roughness=0.95)
    bm = bmesh.new()
    s = 1.2
    ax = x - 2.5
    D.box(bm, (ax - 1.0 * s, -0.5 * s, 0.0), (ax + 1.0 * s, 0.5 * s, 3.5 * s))
    D.box(bm, (ax - 0.6 * s, -0.4 * s, 3.5 * s), (ax + 0.6 * s, 0.4 * s, 5.0 * s))
    D.box(bm, (ax - 1.5 * s, -0.35 * s, 1.9 * s), (ax - 1.0 * s, 0.35 * s, 3.5 * s))
    D.box(bm, (ax + 1.0 * s, -0.35 * s, 1.9 * s), (ax + 1.5 * s, 0.35 * s, 3.5 * s))
    D.new_obj("ScaleRef", bm, c, "d94f4f", roughness=0.8)
    out = os.path.join(FB_MODELS, "renders", name + ".png")
    D.render(keys, out, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=1.04, with_stage=True, show_ref=True)
    return out, total
