"""Blender helpers for the Collect-a-Cucumber house-style pets.
Units: 1 Blender unit = 1 Roblox stud. Blender Z-up, pet FRONT faces +Y.
Roblox export: (x, y, z)_rbx = (x, z, -y)_blender  (a pure rotation, winding preserved).
"""
import bpy, bmesh, json, math
from mathutils import Vector, Matrix, Euler


def hex_to_rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def material(name, hexcol):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    r, g, b = hex_to_rgb(hexcol)
    m.diffuse_color = (r, g, b, 1)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
        bsdf.inputs["Roughness"].default_value = 0.6
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


def new_obj(name, bm, c, hexcol, rbx_material="Plastic"):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    # object names are namespaced per pet ("PurpleHydra.Body") so two pets can share part names
    obj = bpy.data.objects.new(c.name + "." + name, me)
    me.name = c.name + "." + name
    c.objects.link(obj)
    me.materials.append(material(c.name + "_" + name, hexcol))
    obj["rbx_hex"] = hexcol
    obj["rbx_material"] = rbx_material
    return obj


# ---------- primitives (all append into an existing bmesh) ----------
def _mat(loc, rot, scale):
    s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
    return Matrix.Translation(Vector(loc)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((s[0], s[1], s[2], 1))


def rot_euler(rx=0, ry=0, rz=0):
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_matrix().to_4x4()


def ico(bm, loc, radius, subdiv=2, rot=None):
    return bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0, matrix=_mat(loc, rot, radius))['verts']


def uvsphere(bm, loc, radius, segs=12, rings=8, rot=None):
    return bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, matrix=_mat(loc, rot, radius))['verts']


def cone(bm, base, tip, r_base, r_tip=0.0, segs=8):
    base = Vector(base)
    tip = Vector(tip)
    d = tip - base
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(base + d / 2) @ rot
    return bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r_base, radius2=r_tip, depth=d.length, matrix=mat)['verts']


def disc(bm, loc, radius, thick, normal=(0, 1, 0), segs=12):
    n = Vector(normal).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix().to_4x4()
    mat = Matrix.Translation(Vector(loc)) @ rot
    return bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius, radius2=radius, depth=thick, matrix=mat)['verts']


def torus(bm, loc, major, minor, rot=None, seg_major=16, seg_minor=8):
    mat = Matrix.Translation(Vector(loc)) @ (rot or Matrix.Identity(4))
    ring = []
    for i in range(seg_major):
        a = 2 * math.pi * i / seg_major
        c = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        row = []
        for j in range(seg_minor):
            b = 2 * math.pi * j / seg_minor
            p = c + Vector((math.cos(a) * math.cos(b) * minor, math.sin(a) * math.cos(b) * minor, math.sin(b) * minor))
            row.append(bm.verts.new(mat @ p))
        ring.append(row)
    for i in range(seg_major):
        for j in range(seg_minor):
            a = ring[i][j]
            b = ring[(i + 1) % seg_major][j]
            c = ring[(i + 1) % seg_major][(j + 1) % seg_minor]
            d = ring[i][(j + 1) % seg_minor]
            bm.faces.new((a, b, c, d))
    return ring


def tube(bm, points, radii, segs=8, cap=True):
    """Lofted capped tube along a polyline; radii per point (0 at an end makes a tip)."""
    n = len(points)
    rings = []
    for i, p in enumerate(points):
        p = Vector(p)
        if i == 0:
            t = Vector(points[1]) - p
        elif i == n - 1:
            t = p - Vector(points[i - 1])
        else:
            t = Vector(points[i + 1]) - Vector(points[i - 1])
        t.normalize()
        rot = Vector((0, 0, 1)).rotation_difference(t).to_matrix()
        r = max(radii[i], 0.0)
        if r < 1e-4:
            tip = bm.verts.new(p)
            rings.append([tip] * segs)
            continue
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            ring.append(bm.verts.new(p + rot @ Vector((math.cos(a) * r, math.sin(a) * r, 0))))
        rings.append(ring)
    for i in range(n - 1):
        for j in range(segs):
            quad = (rings[i][j], rings[i][(j + 1) % segs], rings[i + 1][(j + 1) % segs], rings[i + 1][j])
            vs = []
            for v in quad:
                if v not in vs:
                    vs.append(v)
            if len(vs) >= 3:
                bm.faces.new(tuple(vs))
    if cap:
        if len(set(map(id, rings[0]))) > 2:
            bm.faces.new(tuple(reversed(rings[0])))
        if len(set(map(id, rings[-1]))) > 2:
            bm.faces.new(tuple(rings[-1]))
    return rings


def slab(bm, outline, thick, mat=None):
    """Extrude a 2D outline (u,v) drawn in the local XZ plane by thick along local Y (centred)."""
    mat = mat or Matrix.Identity(4)
    front = [bm.verts.new(mat @ Vector((u, -thick / 2, v))) for u, v in outline]
    back = [bm.verts.new(mat @ Vector((u, thick / 2, v))) for u, v in outline]
    bm.faces.new(tuple(front))
    bm.faces.new(tuple(reversed(back)))
    n = len(outline)
    for i in range(n):
        bm.faces.new((back[i], back[(i + 1) % n], front[(i + 1) % n], front[i]))
    return front, back


def mirror_x(bm):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.mirror(bm, geom=geom, axis='X', merge_dist=0.0)


def cube(bm, loc, size, rot=None):
    s = size if isinstance(size, (tuple, list)) else (size, size, size)
    return bmesh.ops.create_cube(bm, size=1.0, matrix=_mat(loc, rot, s))['verts']


# ---------- export ----------
def export_collection(coll_name, path):
    c = bpy.data.collections[coll_name]
    parts = []
    for obj in sorted(c.objects, key=lambda o: o.name):
        if obj.type != 'MESH':
            continue
        part_name = obj.name.split(".", 1)[1] if obj.name.startswith(c.name + ".") else obj.name
        me = obj.data
        mw = obj.matrix_world
        verts = []
        for v in me.vertices:
            p = mw @ v.co
            verts.extend([round(p.x, 3), round(p.z, 3), round(-p.y, 3)])
        me.calc_loop_triangles()
        tris = []
        for lt in me.loop_triangles:
            a, b, c_ = lt.vertices
            tris.extend([a + 1, b + 1, c_ + 1])
        parts.append({"name": part_name, "hex": obj.get("rbx_hex", "ffffff"), "material": obj.get("rbx_material", "Plastic"), "verts": verts, "tris": tris})
    with open(path, "w") as f:
        json.dump({"pet": coll_name, "parts": parts}, f)
    return [(p["name"], len(p["verts"]) // 3, len(p["tris"]) // 3) for p in parts]


def export_luau(coll_name, pet_name, path, prefix):
    """Writes a Roblox ModuleScript: per part, vertices centred on the part's bbox (Roblox coords),
    1-based triangle indices, bbox Size and the Offset of the bbox centre from the pet origin (= Root)."""
    c = bpy.data.collections[coll_name]
    lines = ["-- Generated from pets-remake/%s.blend (Blender %s) by petlib.export_luau. Do not hand-edit." % (coll_name, bpy.app.version_string),
             "-- Geometry for the runtime-built pet meshes; see ReplicatedStorage.Modules.PetRuntimeMesh.",
             "return {", "\tPet = %s," % json.dumps(pet_name), "\tPrefix = %s," % json.dumps(prefix), "\tParts = {"]
    stats = []
    for obj in sorted(c.objects, key=lambda o: o.name):
        if obj.type != 'MESH':
            continue
        part_name = obj.name.split(".", 1)[1] if obj.name.startswith(c.name + ".") else obj.name
        me = obj.data
        mw = obj.matrix_world
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
            vflat.extend(("%.3g" % (p[i] - center[i]) if abs(p[i] - center[i]) < 1 else "%.4g" % (p[i] - center[i])) for i in range(3))
        lines.append("\t\t[%s] = {" % json.dumps(part_name))
        lines.append("\t\t\tColor = %s, Material = %s," % (json.dumps(obj.get("rbx_hex", "ffffff")), json.dumps(obj.get("rbx_material", "Plastic"))))
        lines.append("\t\t\tSize = {%.4g, %.4g, %.4g}, Offset = {%.4g, %.4g, %.4g}," % (size[0], size[1], size[2], center[0], center[1], center[2]))
        lines.append("\t\t\tV = {" + ",".join(vflat) + "},")
        lines.append("\t\t\tT = {" + ",".join(str(t) for t in tris) + "},")
        lines.append("\t\t},")
        stats.append((part_name, len(pts), len(tris) // 3))
    lines.append("\t},")
    lines.append("}")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return stats


def export_fbx(coll_name, path):
    c = bpy.data.collections[coll_name]
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    bpy.ops.object.select_all(action='DESELECT')
    for o in c.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = c.objects[0]
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True, global_scale=1.0,
                             axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE', use_mesh_modifiers=True,
                             path_mode='COPY', embed_textures=False, bake_anim=False)
    return path


def render_preview(coll_name, path, size=(1000, 750), yaw_deg=35, pitch_deg=18):
    c = bpy.data.collections[coll_name]
    scene = bpy.context.scene
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = (lc.name != coll_name)
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for o in c.objects:
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
    dist = radius * 2.7
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
        bg.inputs[0].default_value = (0.55, 0.65, 0.85, 1)
        bg.inputs[1].default_value = 1.0
    scene.render.filepath = path
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    return path
