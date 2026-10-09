"""Blender helpers for the themed bench-press tiers (New Map Cucumber Game).

Bench space: 1 unit = 1 stud, Z up, floor at z = 0, bench long axis = X with the rack / head end
at +X, the bar runs along Y at (1.5, y, 3.5), pad top at z = 1.3 (all fixed so the lie-down seat,
the grab detection and the bench-press animation keep working for every tier).
Roblox = (x, z, -y)_blender for the bench.  The barbell is modelled in its OWN space: bar axis
along X centred on the origin (Roblox part local X = bar axis, what BenchServer/BarbellClient use).
"""
import bpy, bmesh, json, math, os, random
from mathutils import Vector, Matrix, Euler

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\assets\benches"


def hex_to_rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def material(name, hexcol, emissive=False):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    r, g, b = hex_to_rgb(hexcol)
    m.diffuse_color = (r, g, b, 1)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
        bsdf.inputs["Roughness"].default_value = 0.55
        if emissive:
            bsdf.inputs["Emission Color"].default_value = (r, g, b, 1)
            bsdf.inputs["Emission Strength"].default_value = 2.5
    return m


def coll(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def clear_collection(name):
    c = coll(name)
    for o in list(c.objects):
        me = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)


STUDS_TILE = 2.0  # studs per texture tile for the studded overlay (box-projected UVs, matches BenchRuntimeMesh)


def box_project_uvs(bm, tile=STUDS_TILE):
    """UVs by box projection along each face's dominant normal axis, one tile per `tile` studs,
    so a tiling texture (the map's studs) reads correctly on every face."""
    bm.normal_update()
    uv_layer = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            p = loop.vert.co
            if ax >= ay and ax >= az:
                u, v = p.y, p.z
            elif ay >= az:
                u, v = p.x, p.z
            else:
                u, v = p.x, p.y
            loop[uv_layer].uv = (u / tile, v / tile)


def new_obj(name, bm, c, hexcol, rbx_material="SmoothPlastic", transparency=0.0):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    box_project_uvs(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    full = c.name.split("_", 1)[0] + "_" + name  # "<Tier>_<Part>"
    obj = bpy.data.objects.new(full, me)
    me.name = full
    c.objects.link(obj)
    me.materials.append(material(full, hexcol, emissive=(rbx_material == "Neon")))
    obj["rbx_hex"] = hexcol
    obj["rbx_material"] = rbx_material
    obj["rbx_transparency"] = transparency
    return obj


# ---------- primitives (append into an existing bmesh) ----------
def _mat(loc, rot, scale):
    s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
    return Matrix.Translation(Vector(loc)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((s[0], s[1], s[2], 1))


def rot_euler(rx=0, ry=0, rz=0):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_matrix().to_4x4()


def cube(bm, loc, size, rot=None):
    s = size if isinstance(size, (tuple, list)) else (size, size, size)
    return bmesh.ops.create_cube(bm, size=1.0, matrix=_mat(loc, rot, s))['verts']


def box(bm, lo, hi, rot=None):
    """Axis-aligned box from corner lo to corner hi (rot applied about its centre)."""
    lo, hi = Vector(lo), Vector(hi)
    return cube(bm, (lo + hi) / 2, tuple(hi - lo), rot)


def cone(bm, base, tip, r_base, r_tip=0.0, segs=8):
    base, tip = Vector(base), Vector(tip)
    d = tip - base
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(base + d / 2) @ rot
    return bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_base, radius2=r_tip, depth=d.length, matrix=mat)['verts']


def disc(bm, loc, radius, thick, normal=(0, 1, 0), segs=12):
    n = Vector(normal).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix().to_4x4()
    mat = Matrix.Translation(Vector(loc)) @ rot
    return bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius, radius2=radius, depth=thick, matrix=mat)['verts']


def rough_disc(bm, loc, radius, thick, normal=(1, 0, 0), segs=10, jitter=0.12, seed=1):
    """Disc whose rim radius varies per vertex (stone / ice look), axis along `normal`."""
    rng = random.Random(seed)
    n = Vector(normal).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix()
    c = Vector(loc)
    rings = []
    for side in (-1, 1):
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            r = radius * (1 + rng.uniform(-jitter, jitter))
            p = Vector((math.cos(a) * r, math.sin(a) * r, side * thick / 2))
            ring.append(bm.verts.new(c + rot @ p))
        rings.append(ring)
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[1]))
    for j in range(segs):
        bm.faces.new((rings[0][j], rings[0][(j + 1) % segs], rings[1][(j + 1) % segs], rings[1][j]))
    return rings


def uvsphere(bm, loc, radius, segs=12, rings=6, rot=None, scale=(1, 1, 1)):
    s = (radius * scale[0], radius * scale[1], radius * scale[2])
    return bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, matrix=_mat(loc, rot, s))['verts']


def octahedron(bm, loc, r, scale=(1, 1, 1.5), rot=None):
    mat = _mat(loc, rot, (r * scale[0], r * scale[1], r * scale[2]))
    pts = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    v = [bm.verts.new(mat @ Vector(p)) for p in pts]
    top, bot = v[4], v[5]
    ring = [v[0], v[2], v[1], v[3]]
    for i in range(4):
        a, b = ring[i], ring[(i + 1) % 4]
        bm.faces.new((a, b, top))
        bm.faces.new((b, a, bot))
    return v


def crystal(bm, base, tip, r, segs=6, tip_ratio=0.18):
    """Tapered hex prism from base to tip (ice crystal / spike)."""
    return cone(bm, base, tip, r, r * tip_ratio, segs)


# ---------- stats / export ----------
def tri_count(coll_name):
    c = bpy.data.collections[coll_name]
    return {o.name: len(o.data.polygons) for o in c.objects if o.type == 'MESH'}


def manifest(coll_names):
    """Per-object Roblox appearance for the install script."""
    out = []
    for cn in coll_names:
        c = bpy.data.collections[cn]
        for o in sorted(c.objects, key=lambda o: o.name):
            if o.type != 'MESH':
                continue
            out.append({"collection": cn, "name": o.name, "hex": o.get("rbx_hex", "ffffff"),
                        "material": o.get("rbx_material", "SmoothPlastic"), "transparency": float(o.get("rbx_transparency", 0.0)),
                        "tris": len(o.data.polygons)})
    return out


def _fmt(x):
    return ("%.3g" % x) if abs(x) < 1 else ("%.4g" % x)


def export_luau(theme, tier, bar_length, path, scale=1.0, rack_offset=(1.5, 3.5)):
    """Writes a Roblox ModuleScript with the tier's geometry for the runtime EditableMesh loader
    (ReplicatedStorage.Modules.BenchRuntimeMesh). Bench parts: vertices centred on the part's bbox,
    Offset = bbox centre from the bench origin (floor under the pivot), Roblox coords (x, z, -y).
    Barbell parts: local object coordinates (bar along +X, centred on the bar), Offset from the bar
    centre; the loader places them relative to the rack CFrame / welds them to the live Bar."""
    lines = ["-- Generated from assets/benches/BenchTiers.blend (Blender %s) by benchlib.export_luau. Do not hand-edit." % bpy.app.version_string,
             "-- Geometry for the runtime-built bench tier meshes; see ReplicatedStorage.Modules.BenchRuntimeMesh.",
             "return {", '\tTheme = "%s", Tier = %d, BarLength = %.3f, Scale = %.3f,' % (theme, tier, bar_length, scale),
             "\tRackOffset = {%.3f, %.3f}, -- bar centre from the bench origin: along the bench, up" % (rack_offset[0], rack_offset[1]),
             "\tParts = {"]
    stats = []
    for coll_name, group, use_world in ((theme + "_Bench", "Bench", True), (theme + "_Barbell", "Barbell", False)):
        c = bpy.data.collections[coll_name]
        for obj in sorted(c.objects, key=lambda o: o.name):
            if obj.type != 'MESH':
                continue
            part = obj.name.split("_", 1)[1]
            if part == "Anchor":
                continue
            me = obj.data
            mw = obj.matrix_world if use_world else Matrix.Identity(4)
            pts = []
            for v in me.vertices:
                p = mw @ v.co
                pts.append((p.x, p.z, -p.y))
            mins = [min(p[i] for p in pts) for i in range(3)]
            maxs = [max(p[i] for p in pts) for i in range(3)]
            center = [(mins[i] + maxs[i]) / 2 for i in range(3)]
            size = [max(maxs[i] - mins[i], 0.05) for i in range(3)]
            me.calc_loop_triangles()
            tris = []
            for lt in me.loop_triangles:
                a, b, c_ = lt.vertices
                tris.extend((a + 1, b + 1, c_ + 1))
            vflat = []
            for p in pts:
                vflat.extend(_fmt(p[i] - center[i]) for i in range(3))
            lines.append("\t\t%s = {" % part)
            lines.append('\t\t\tGroup = "%s", Color = "%s", Material = "%s", Transparency = %s,' % (group, obj.get("rbx_hex", "ffffff"), obj.get("rbx_material", "SmoothPlastic"), _fmt(float(obj.get("rbx_transparency", 0.0)))))
            lines.append("\t\t\tSize = {%s, %s, %s}, Offset = {%s, %s, %s}," % tuple(_fmt(x) for x in size + center))
            lines.append("\t\t\tV = {" + ",".join(vflat) + "},")
            lines.append("\t\t\tT = {" + ",".join(str(t) for t in tris) + "},")
            lines.append("\t\t},")
            stats.append((part, len(pts), len(tris) // 3))
    lines.append("\t},")
    lines.append("}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return stats


def export_fbx(coll_name, path, identity=False):
    """Export a collection to FBX (Roblox import settings). identity=True exports the objects with
    their transforms reset (used for the barbell, which is modelled in its own space and only
    displayed at the rack via its object matrix)."""
    c = bpy.data.collections[coll_name]
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    saved = {}
    if identity:
        for o in c.objects:
            saved[o] = o.matrix_world.copy()
            o.matrix_world = Matrix.Identity(4)
        bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for o in c.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = c.objects[0]
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL',
                             global_scale=1.0, axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE', use_mesh_modifiers=True,
                             path_mode='COPY', embed_textures=False, bake_anim=False, use_custom_props=False)
    for o, m in saved.items():
        o.matrix_world = m
    bpy.context.view_layer.update()
    return path


def render_preview(coll_names, path, size=(900, 650), yaw_deg=38, pitch_deg=20, dist_mul=2.3):
    scene = bpy.context.scene
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = (lc.name not in coll_names)
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for cn in coll_names:
        for o in bpy.data.collections[cn].objects:
            for corner in o.bound_box:
                p = o.matrix_world @ Vector(corner)
                mins = Vector((min(mins.x, p.x), min(mins.y, p.y), min(mins.z, p.z)))
                maxs = Vector((max(maxs.x, p.x), max(maxs.y, p.y), max(maxs.z, p.z)))
    center = (mins + maxs) / 2
    radius = (maxs - mins).length / 2
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        scene.collection.objects.link(cam)
    cam.data.lens = 50
    dist = radius * dist_mul
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    offset = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * dist
    cam.location = center + offset
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    sun = bpy.data.objects.get("PreviewSun")
    if sun is None:
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", 'SUN'))
        scene.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), math.radians(15), math.radians(-30))
    fill = bpy.data.objects.get("PreviewFill")
    if fill is None:
        fill = bpy.data.objects.new("PreviewFill", bpy.data.lights.new("PreviewFill", 'SUN'))
        scene.collection.objects.link(fill)
    fill.data.energy = 1.2
    fill.rotation_euler = (math.radians(60), math.radians(-20), math.radians(150))
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines else ('BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_WORKBENCH')
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.62, 0.62, 0.66, 1)
        bg.inputs[1].default_value = 1.0
    scene.render.filepath = path
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    return path
