"""review_live.py -- central review in the LIVE Blender (Blender MCP), 2026-09-24.

Run from the Blender MCP:  exec(open(r"<this file>").read(), {"__name__": "__review__", "KEYS": ["Shop", "Ascend", "Gift"]})

Builds the given models (models/build_<Key>.py, fresh modules every call) into their own scene "RAS_Lobby_Review"
(the user's open scene is left alone), lines them up left-to-right the way the lobby shows them from the launch pad
(Gift, Ascend, Shop) on a snow floor with a 5-stud avatar, switches the window to that scene and frames the 3-D
viewport on the line-up in Material Preview so get_viewport_screenshot shows the real colours.
Nothing is saved.
"""
import bpy
import os
import sys
import math
import importlib.util
from mathutils import Vector, Euler

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\ras-dev\lobby-models"
KEYS = globals().get("KEYS") or ["Gift", "Ascend", "Shop"]
SPACING = globals().get("SPACING") or 26.0
SCENE = "RAS_Lobby_Review"


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


scene = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
win = bpy.context.window_manager.windows[0]
win.scene = scene
with bpy.context.temp_override(window=win, scene=scene):
    for c in list(scene.collection.children):
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        scene.collection.children.unlink(c)
        if c.users == 0:
            bpy.data.collections.remove(c)
    sys.modules.pop("defenselib", None)
    L = _load(os.path.join(ROOT, "lobbylib.py"), "lobbylib")
    D = L.D
    reports = {}
    ordered = [k for k in ("Gift", "Ascend", "Shop") if k in KEYS] + [k for k in KEYS if k not in ("Gift", "Ascend", "Shop")]
    n = len(ordered)
    for i, key in enumerate(ordered):
        B = _load(os.path.join(ROOT, "models", "build_" + key + ".py"), "build_" + key)
        info = B.build(L)
        reports[key] = {k: info[k] for k in ("size_studs", "meshes_after_merge", "tris_total", "problems")}
        # viewer at +Y looks toward -Y, so screen-left is +X: Gift left, Ascend middle, Shop right
        dx = (n - 1) / 2.0 * SPACING - i * SPACING
        for o in bpy.data.collections[key].objects:
            o.location.x += dx
    import bmesh
    stage = D.coll("_Stage")
    D.clear_collection("_Stage")
    b = bmesh.new()
    D.box(b, (-SPACING * n / 2 - 6, -18, -0.25), (SPACING * n / 2 + 6, 14, 0.0))
    D.new_obj("Floor", b, stage, "ebf6fc", roughness=0.95)
    b = bmesh.new()
    D.box(b, (-1.0, -0.5, 0.0), (1.0, 0.5, 3.5))
    D.box(b, (-0.6, -0.4, 3.5), (0.6, 0.4, 5.0))
    D.box(b, (-1.5, -0.35, 1.9), (-1.0, 0.35, 3.5))
    D.box(b, (1.0, -0.35, 1.9), (1.5, 0.35, 3.5))
    ref = D.new_obj("ScaleRef", b, stage, "d94f4f", roughness=0.8)
    ref.location = (SPACING * 0.5, 7.0, 0.0)
    sun = bpy.data.objects.get("ReviewSun")
    if sun is None:
        sun = bpy.data.objects.new("ReviewSun", bpy.data.lights.new("ReviewSun", 'SUN'))
    if sun.name not in scene.collection.objects:
        scene.collection.objects.link(sun)
    sun.data.energy = 3.2
    sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(-30)))
    if scene.world is None:
        scene.world = bpy.data.worlds.new("ReviewWorld")
    scene.world.use_nodes = True
    bg = next((nd for nd in scene.world.node_tree.nodes if nd.type == 'BACKGROUND'), None)
    if bg:
        bg.inputs[0].default_value = (0.46, 0.60, 0.76, 1)
        bg.inputs[1].default_value = 0.55
    try:
        scene.view_settings.view_transform = 'Standard'
    except Exception:
        pass
    for area in win.screen.areas:
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        space.shading.type = 'MATERIAL'
        try:
            space.shading.use_scene_lights = True
            space.shading.use_scene_world = True
        except Exception:
            pass
        r3d = space.region_3d
        r3d.view_perspective = 'PERSP'
        r3d.view_location = Vector((0.0, 0.0, 8.0))
        r3d.view_rotation = Euler((math.radians(76), 0.0, math.radians(180))).to_quaternion()
        r3d.view_distance = SPACING * n * 1.05 + 10
        space.overlay.show_floor = False
        space.overlay.show_axis_x = False
        space.overlay.show_axis_y = False
        area.tag_redraw()
print("REVIEW", reports)
