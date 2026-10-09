"""Interactive pose test helper (Blender MCP): render the CURRENT pose from several views into one
PNG.  Usage inside Blender:
    import posetest as P; P.shot("name", views=("front", "game"))"""
import bpy
import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() else r"C:\Users\shrey\OneDrive\Documents\RobloxGames\ras-dev\launcher-anims"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L

OUT = os.path.join(HERE, "out", "posetest")


def shot(name, views=("front", "game", "top"), size=(420, 300), ball=None):
    os.makedirs(OUT, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_shadows = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    b = bpy.data.objects.get("Ball")
    if b:
        b.hide_render = ball is None
        if ball is not None:
            b.location = L.r2b(ball)
    tiles = []
    tmp = os.path.join(OUT, "_t.png")
    for v in views:
        eye, look, lens, fov = L.VIEWS[v]
        L._camera(eye, look, lens=lens, fov_deg=fov)
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(size[1], size[0], 4)
        bpy.data.images.remove(img)
        px[:2, :, :3] = 0
        px[:, :2, :3] = 0
        tiles.append(px)
    sheet = np.concatenate(tiles, axis=1)
    out = bpy.data.images.new("shot", width=sheet.shape[1], height=sheet.shape[0], alpha=True)
    out.pixels = sheet.ravel()
    path = os.path.join(OUT, name + ".png")
    out.filepath_raw = path
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    os.remove(tmp)
    return path
