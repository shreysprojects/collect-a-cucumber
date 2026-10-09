"""Renders every launcher alone in its GRIP PIVOT frame (template scale) from three orthographic
views, with the pivot axes drawn in, and writes geometry stats per launcher.
    pivot frame: +X red, +Y green, +Z blue.  The grip (pivot) is the white dot at the origin.
Views: SIDE (looking along -X), TOP (looking along +Z, i.e. from the launcher's underside... see
labels), END (looking along +Y from the far end back to the grip).
Output: out/inspect/meta_<a>-<b>.png (with meta markers)"""
import bpy
import bmesh
import json
import math
import os
import sys
import importlib
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)
import numpy as np

OUT = os.path.join(HERE, "out", "inspect")
os.makedirs(OUT, exist_ok=True)
scene = bpy.context.scene

# hide the character + props
hidden = []
for ob in bpy.data.objects:
    if ob.name.startswith("Blk_") or ob.name in ("Ground", "TrackArrow", "Ball", "ActiveLauncher"):
        if not ob.hide_render:
            hidden.append(ob)
        ob.hide_render = True


def mk_axis(name, direction, color, length=1.2):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    d = Vector(direction)
    m = Matrix.Translation(d * length / 2) @ (d.to_track_quat('Z', 'Y').to_matrix().to_4x4()) @ Matrix.Diagonal((0.035, 0.035, length, 1.0))
    bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(name + "M")
    mat.diffuse_color = color
    me.materials.append(mat)
    return ob


tmp_objs = []
# pivot axes in BLENDER space of the pivot frame: pivot-local Roblox (x,y,z) -> Blender (x,-z,y)
tmp_objs.append(mk_axis("AxX", L.r2b((1, 0, 0)), (1, 0.1, 0.1, 1)))
tmp_objs.append(mk_axis("AxY", L.r2b((0, 1, 0)), (0.1, 0.9, 0.1, 1)))
tmp_objs.append(mk_axis("AxZ", L.r2b((0, 0, 1)), (0.1, 0.3, 1, 1)))
me = bpy.data.meshes.new("PivotDot")
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.06)
bm.to_mesh(me)
bm.free()
dot = bpy.data.objects.new("PivotDot", me)
scene.collection.objects.link(dot)
m = bpy.data.materials.new("DotM")
m.diffuse_color = (1, 1, 1, 1)
me.materials.append(m)
tmp_objs.append(dot)

view_obj = bpy.data.objects.new("InspectLauncher", None)
scene.collection.objects.link(view_obj)
tmp_objs.append(view_obj)

camd = bpy.data.cameras.new("InspectCam")
camd.type = 'ORTHO'
cam = bpy.data.objects.new("InspectCam", camd)
scene.collection.objects.link(cam)
tmp_objs.append(cam)
scene.camera = cam
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'TEXTURE'
scene.display.shading.show_xray = False
W, H = 300, 300
scene.render.resolution_x, scene.render.resolution_y = W, H
scene.render.film_transparent = False
tmp = os.path.join(OUT, "_t.png")

stats = {}
markers = []
VIEWS = [  # (label, camera direction in pivot-local Roblox coords (camera looks ALONG this), up)
    ("side_from+X", (-1, 0, 0), (0, 0, -1)),
    ("from-Z(top?)", (0, 0, 1), (0, -1, 0)),
    ("end_from-Y", (0, 1, 0), (0, 0, -1)),
]
rows = []
for lid in range(1, 31):
    name, info = L.launcher_info(lid)
    po = L.pivot_offset(lid)
    po1 = L.cf_components(info["pivot"])           # template scale
    # launcher mesh placed so the pivot is at the origin, template scale (divide the 1.5 back out)
    mesh = bpy.data.meshes["M_" + name]
    ob = bpy.data.objects.get("InspectMesh")
    if ob is None:
        ob = bpy.data.objects.new("InspectMesh", mesh)
        scene.collection.objects.link(ob)
        tmp_objs.append(ob)
    ob.data = mesh
    ob.hide_render = False
    Mr = po1.inverted() @ Matrix.Diagonal((1 / L.LAUNCHER_SCALE,) * 3 + (1.0,))
    ob.matrix_world = L.rbx_to_blender_matrix(Mr)
    bpy.context.view_layer.update()

    # ---- meta markers (pivot-local template coords == this view's coords)
    for mk in list(markers):
        bpy.data.objects.remove(mk, do_unlink=True)
    markers.clear()
    meta = L.load_meta(lid)
    def sphere(nm, pos, r, col):
        me2 = bpy.data.meshes.new(nm)
        bm2 = bmesh.new()
        bmesh.ops.create_uvsphere(bm2, u_segments=14, v_segments=8, radius=r)
        bm2.to_mesh(me2); bm2.free()
        o = bpy.data.objects.new(nm, me2)
        scene.collection.objects.link(o)
        mt = bpy.data.materials.new(nm + "M"); mt.diffuse_color = col; me2.materials.append(mt)
        o.location = L.r2b(pos)
        markers.append(o)
        return o
    def arrow(nm, pos, d, col, length=0.9):
        d = Vector(d).normalized()
        me2 = bpy.data.meshes.new(nm)
        bm2 = bmesh.new()
        db = L.r2b(d)
        m2 = Matrix.Translation(L.r2b(pos) + db * length / 2) @ (db.to_track_quat('Z', 'Y').to_matrix().to_4x4()) @ Matrix.Diagonal((0.05, 0.05, length, 1.0))
        bmesh.ops.create_cube(bm2, size=1.0, matrix=m2)
        bm2.to_mesh(me2); bm2.free()
        o = bpy.data.objects.new(nm, me2)
        scene.collection.objects.link(o)
        mt = bpy.data.materials.new(nm + "M"); mt.diffuse_color = col; me2.materials.append(mt)
        markers.append(o)
    R0 = L.BALL_RADIUS / L.LAUNCHER_SCALE
    if "Seat" in meta:
        sphere("mSeat", meta["Seat"]["pos"], R0, (1, 1, 1, 1))
    if "Muzzle" in meta:
        sphere("mMuz", meta["Muzzle"]["pos"], 0.08, (1, 0.1, 0.1, 1))
        arrow("mMuzA", meta["Muzzle"]["pos"], meta["Muzzle"]["look"], (1, 0.1, 0.1, 1))
        arrow("mMuzU", meta["Muzzle"]["pos"], meta["Muzzle"]["up"], (1, 0.8, 0.1, 1), 0.4)
    if "Grip2" in meta:
        sphere("mG2", meta["Grip2"]["pos"], 0.17, (0.1, 0.9, 0.2, 1))
    if "Tip" in meta:
        sphere("mTip", meta["Tip"]["pos"], 0.08, (1, 1, 0.1, 1))
    for i, b in enumerate(meta.get("Bands", [])):
        sphere("mBand%d" % i, b, 0.08, (1, 0.2, 1, 1))
    # stats in pivot-local (template) coords
    pts = [L.b2r(ob.matrix_world @ v.co) for v in mesh.vertices]
    xs = [p.x for p in pts]; ys = [p.y for p in pts]; zs = [p.z for p in pts]
    ymin = min(ys)
    end = [p for p in pts if p.y < ymin + 0.12]
    ec = sum(end, Vector()) / len(end)
    stats[name] = {"bbox_min": [round(min(xs), 3), round(ymin, 3), round(min(zs), 3)],
                   "bbox_max": [round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)],
                   "far_end_centroid": [round(v, 3) for v in ec],
                   "far_end_count": len(end)}
    ext = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs), 1.0)
    centre = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2))
    row = []
    for label, d, up in VIEWS:
        d = Vector(d)
        eye = centre - d * 10.0
        camd.ortho_scale = ext * 1.25
        cam.location = L.r2b(eye)
        cam.rotation_euler = (L.r2b(d)).to_track_quat('-Z', 'Y').to_euler()
        # roll so that "up" is up in the image
        q = L.look_frame(d, up)
        cam.matrix_world = L.C3.to_4x4() @ L.cf(eye, q)
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
        bpy.data.images.remove(img)
        px[:2, :, :3] = 0; px[:, :2, :3] = 0
        row.append(px)
    rows.append((lid, row))

for start in range(0, 30, 6):
    chunk = rows[start:start + 6]
    sheet = np.ones((H * len(chunk), W * 3, 4), dtype=np.float32)
    for ri, (lid, row) in enumerate(chunk):
        y0 = (len(chunk) - 1 - ri) * H
        for ci, px in enumerate(row):
            sheet[y0:y0 + H, ci * W:(ci + 1) * W] = px
    img = bpy.data.images.new("sheet", width=W * 3, height=H * len(chunk), alpha=True)
    img.pixels = sheet.ravel()
    img.filepath_raw = os.path.join(OUT, "meta_%02d-%02d.png" % (chunk[0][0], chunk[-1][0]))
    img.file_format = 'PNG'
    img.save()
    bpy.data.images.remove(img)

for mk in markers:
    bpy.data.objects.remove(mk, do_unlink=True)
for ob in tmp_objs:
    bpy.data.objects.remove(ob, do_unlink=True)
for ob in hidden:
    ob.hide_render = False
if os.path.exists(tmp):
    os.remove(tmp)
print("done", len(stats))
