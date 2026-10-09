"""Blender helpers for the base-defence prop set (turret / walls / traps / pads).

House style matches assets/benches/benchlib.py and pets-remake/petlib.py:
  * 1 Blender unit = 1 Roblox stud.  Blender is Z-up, the floor is z = 0.
  * Every prop FACES +Y (a turret barrel, a boost pad's arrows and a wall's outer face
    all point toward +Y, i.e. "toward the attackers").
  * Roblox export is a pure rotation: (x, y, z)_rbx = (x, z, -y)_blender.
  * Chunky low-poly, FLAT shaded, per-object colour carried as custom props
    ("rbx_hex" / "rbx_material" / "rbx_transparency") so a later installer can rebuild
    the prop out of Roblox parts or MeshParts without re-deriving the look.

Scale contract for this set (an R15 avatar is ~5 studs tall, ~2 studs wide):
  * footprint tile = 8 x 8 studs, walls are 8 wide and 8 tall,
  * turret sits on a 6 x 6 base and reaches ~7 studs,
  * traps / pads are flat plates a player runs over.
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, Euler

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\defenses"
TILE = 8.0          # standard footprint tile, studs
STUDS_TILE = 2.0    # studs per UV tile for box-projected UVs


# ---------------------------------------------------------------- materials / objects
def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def material(name, hexcol, emissive=False, metallic=0.0, roughness=0.55):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    r, g, b = hex_to_rgb(hexcol)
    m.diffuse_color = (r, g, b, 1)
    m.metallic = metallic
    m.roughness = roughness
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
        bsdf.inputs["Roughness"].default_value = roughness
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if emissive and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (r, g, b, 1)
            # keep this low: anything above ~2 clips to white and the hue is lost
            bsdf.inputs["Emission Strength"].default_value = 0.8
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


def box_project_uvs(bm, tile=STUDS_TILE):
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
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
            loop[uv].uv = (u / tile, v / tile)


def new_obj(name, bm, c, hexcol, rbx_material="SmoothPlastic", transparency=0.0,
            metallic=0.0, roughness=0.55, smooth=False):
    """Finish a bmesh into a flat-shaded object named "<Collection>.<name>"."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    box_project_uvs(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    full = c.name + "." + name
    obj = bpy.data.objects.new(full, me)
    me.name = full
    c.objects.link(obj)
    me.materials.append(material(full, hexcol, emissive=(rbx_material == "Neon"),
                                 metallic=metallic, roughness=roughness))
    obj["rbx_hex"] = hexcol.lstrip("#")
    obj["rbx_material"] = rbx_material
    obj["rbx_transparency"] = transparency
    return obj


# ---------------------------------------------------------------- transforms
def _mat(loc, rot, scale):
    s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
    return Matrix.Translation(Vector(loc)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal((s[0], s[1], s[2], 1))


def rot_euler(rx=0, ry=0, rz=0):
    """Degrees -> 4x4 rotation (XYZ order)."""
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_matrix().to_4x4()


def aim(direction, up=(0, 0, 1)):
    """4x4 rotation taking local +Z onto `direction` (used to point cylinders/cones)."""
    d = Vector(direction)
    if d.length < 1e-9:
        return Matrix.Identity(4)
    return Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()


def xform(bm, verts, matrix):
    """Apply a 4x4 to a vert list already in the bmesh (returned by any primitive)."""
    bmesh.ops.transform(bm, matrix=matrix, verts=verts)
    return verts


# ---------------------------------------------------------------- primitives
# Every primitive APPENDS into an existing bmesh and returns its new verts.
def cube(bm, loc, size, rot=None):
    s = size if isinstance(size, (tuple, list)) else (size, size, size)
    return bmesh.ops.create_cube(bm, size=1.0, matrix=_mat(loc, rot, s))['verts']


def box(bm, lo, hi, rot=None):
    """Axis-aligned box from corner `lo` to corner `hi` (rot applied about its centre)."""
    lo, hi = Vector(lo), Vector(hi)
    return cube(bm, (lo + hi) / 2, tuple(hi - lo), rot)


def beveled_box(bm, lo, hi, bevel=0.1, segments=1, rot=None):
    """Box with chamfered edges - the chunky toy-plastic look.  `bevel` is clamped so it
    can never exceed 40% of the smallest dimension."""
    lo, hi = Vector(lo), Vector(hi)
    dim = hi - lo
    b = max(0.0, min(bevel, 0.4 * min(abs(dim.x), abs(dim.y), abs(dim.z))))
    pre = set(bm.verts)
    verts = cube(bm, (lo + hi) / 2, tuple(dim), rot)
    if b <= 1e-5:
        return verts
    vset = set(verts)
    edges = [e for e in bm.edges if e.verts[0] in vset and e.verts[1] in vset]
    faces = [f for f in bm.faces if all(v in vset for v in f.verts)]
    bmesh.ops.bevel(bm, geom=verts + edges + faces, offset=b, segments=segments,
                    profile=0.5, affect='EDGES', clamp_overlap=True)
    # bevel FREES the source verts, so `verts` is full of dead references - rebuild the
    # live list by diffing against the pre-existing geometry.
    bm.verts.ensure_lookup_table()
    return [v for v in bm.verts if v not in pre]


def cyl(bm, a, b, radius, segs=12, r2=None, cap=True):
    """Cylinder (or truncated cone when r2 is given) from point a to point b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-9:
        return []
    mat = Matrix.Translation(a + d / 2) @ aim(d)
    return bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=segs,
                                 radius1=radius, radius2=(radius if r2 is None else r2),
                                 depth=d.length, matrix=mat)['verts']


def cone(bm, base, tip, r_base, r_tip=0.0, segs=8):
    return cyl(bm, base, tip, r_base, segs=segs, r2=r_tip)


def spike(bm, base, tip, r, segs=6, tip_r=0.0):
    """Tapered spike - `segs=4` gives a hard pyramid-ish spike, 6-8 a rounder one."""
    return cyl(bm, base, tip, r, segs=segs, r2=tip_r)


def pyramid(bm, center, size, height, rot=None):
    """Square pyramid standing on z=center.z, base `size` x `size`, apex `height` above."""
    cx, cy, cz = center
    h = size / 2
    pts = [(cx - h, cy - h, cz), (cx + h, cy - h, cz), (cx + h, cy + h, cz), (cx - h, cy + h, cz)]
    vs = [bm.verts.new(p) for p in pts]
    apex = bm.verts.new((cx, cy, cz + height))
    bm.faces.new(tuple(reversed(vs)))
    for i in range(4):
        bm.faces.new((vs[i], vs[(i + 1) % 4], apex))
    out = vs + [apex]
    if rot is not None:
        bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(center)) @ rot @ Matrix.Translation(-Vector(center)), verts=out)
    return out


def uvsphere(bm, loc, radius, segs=12, rings=8, rot=None, scale=(1, 1, 1)):
    s = (radius * scale[0], radius * scale[1], radius * scale[2])
    return bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0,
                                     matrix=_mat(loc, rot, s))['verts']


def ico(bm, loc, radius, subdiv=1, rot=None, scale=(1, 1, 1)):
    s = (radius * scale[0], radius * scale[1], radius * scale[2])
    return bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0,
                                      matrix=_mat(loc, rot, s))['verts']


def torus(bm, loc, major, minor, rot=None, seg_major=16, seg_minor=6):
    mat = Matrix.Translation(Vector(loc)) @ (rot or Matrix.Identity(4))
    rings = []
    for i in range(seg_major):
        a = 2 * math.pi * i / seg_major
        c = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        row = []
        for j in range(seg_minor):
            t = 2 * math.pi * j / seg_minor
            p = c + Vector((math.cos(a) * math.cos(t) * minor, math.sin(a) * math.cos(t) * minor, math.sin(t) * minor))
            row.append(bm.verts.new(mat @ p))
        rings.append(row)
    for i in range(seg_major):
        for j in range(seg_minor):
            bm.faces.new((rings[i][j], rings[(i + 1) % seg_major][j],
                          rings[(i + 1) % seg_major][(j + 1) % seg_minor], rings[i][(j + 1) % seg_minor]))
    return [v for row in rings for v in row]


def prism(bm, pts2d, z0, z1, matrix=None):
    """Extrude a SIMPLE closed polygon (list of (x, y), any winding) from z0 to z1,
    then optionally apply a 4x4.  The workhorse for chevrons, hex plates, wall
    cross-sections, wedges - anything with a profile."""
    pts = list(pts2d)
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
               for i in range(len(pts)))
    if area < 0:
        pts.reverse()
    bot = [bm.verts.new((p[0], p[1], z0)) for p in pts]
    top = [bm.verts.new((p[0], p[1], z1)) for p in pts]
    bm.faces.new(tuple(reversed(bot)))
    bm.faces.new(tuple(top))
    n = len(pts)
    for i in range(n):
        bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]))
    out = bot + top
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=out)
    return out


def wedge(bm, lo, hi, rise='+Y', matrix=None):
    """Right-triangle ramp filling the box lo..hi.  `rise` says which horizontal edge is
    the TALL one: '+Y' means the face at max-Y is full height and it slopes down to min-Y."""
    lo, hi = Vector(lo), Vector(hi)
    if rise in ('+Y', '-Y'):
        prof = ([(lo.y, lo.z), (hi.y, lo.z), (hi.y, hi.z)] if rise == '+Y'
                else [(lo.y, lo.z), (hi.y, lo.z), (lo.y, hi.z)])
        m = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # (y,z,x) -> (x,y,z)
        vs = prism(bm, prof, lo.x, hi.x, matrix=m)
    else:
        prof = ([(lo.x, lo.z), (hi.x, lo.z), (hi.x, hi.z)] if rise == '+X'
                else [(lo.x, lo.z), (hi.x, lo.z), (lo.x, hi.z)])
        m = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))  # (x,z,y) -> (x,y,z)
        vs = prism(bm, prof, lo.y, hi.y, matrix=m)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


def rock(bm, loc, radius, seed=1, jitter=0.30, subdiv=1, scale=(1, 1, 1), rot=None):
    """Chunky faceted boulder: an icosphere with deterministic per-vertex radial jitter."""
    vs = ico(bm, (0, 0, 0), 1.0, subdiv=subdiv)
    rng = random.Random(seed)
    for v in vs:
        v.co *= (1.0 + rng.uniform(-jitter, jitter))
    bmesh.ops.transform(bm, matrix=_mat(loc, rot, (radius * scale[0], radius * scale[1], radius * scale[2])), verts=vs)
    return vs


def stone_block(bm, lo, hi, seed=1, jitter=0.06, bevel=0.06, rot=None):
    """A masonry block: bevelled box with every corner nudged so no two read identical."""
    vs = beveled_box(bm, lo, hi, bevel=bevel, rot=rot)
    rng = random.Random(seed)
    for v in vs:
        v.co += Vector((rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter)))
    return vs


def tube(bm, points, radii, segs=8, cap=True):
    """Lofted tube along a polyline; `radii` is per point (0 at an end makes a point)."""
    pts = [Vector(p) for p in points]
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            d = pts[1] - pts[0]
        elif i == len(pts) - 1:
            d = pts[-1] - pts[-2]
        else:
            d = pts[i + 1] - pts[i - 1]
        rot = aim(d)
        ring = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            off = Vector((math.cos(a) * radii[i], math.sin(a) * radii[i], 0))
            ring.append(bm.verts.new(p + (rot.to_3x3() @ off)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(segs):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % segs],
                          rings[i + 1][(j + 1) % segs], rings[i + 1][j]))
    if cap:
        bm.faces.new(tuple(reversed(rings[0])))
        bm.faces.new(tuple(rings[-1]))
    return [v for r in rings for v in r]


def chevron_pts(width, depth, thickness, tip_at=+1):
    """2-D profile of a '>' arrow chevron pointing along +Y (tip_at=+1) or -Y (-1),
    spanning x in [-width/2, +width/2].  Feed straight into prism()."""
    w, d, t = width / 2.0, depth, thickness
    s = 1 if tip_at >= 0 else -1
    return [(-w, 0.0), (0.0, s * d), (w, 0.0), (w, -s * t), (0.0, s * (d - t)), (-w, -s * t)]


def ngon_pts(n, radius, phase=0.0, center=(0, 0)):
    return [(center[0] + math.cos(phase + 2 * math.pi * i / n) * radius,
             center[1] + math.sin(phase + 2 * math.pi * i / n) * radius) for i in range(n)]


def ring_positions(n, radius, phase=0.0, center=(0, 0)):
    """N evenly spaced (x, y) points on a circle - bolt heads, spike rings, lights."""
    return ngon_pts(n, radius, phase, center)


def grid_positions(nx, ny, sx, sy, center=(0, 0), stagger=False):
    """Centred nx*ny lattice of (x, y); `stagger` offsets odd rows by half a cell."""
    out = []
    for j in range(ny):
        y = center[1] + (j - (ny - 1) / 2.0) * sy
        off = (sx / 2.0 if (stagger and j % 2) else 0.0)
        for i in range(nx):
            out.append((center[0] + (i - (nx - 1) / 2.0) * sx + off, y))
    return out


# ---------------------------------------------------------------- stage / render / stats
def build_stage(size=26.0, ref_at=(-6.5, 5.0, 0.0)):
    """Neutral floor + a 5-stud blockout avatar so renders read at true scale.  `size` is a
    scalar or an (x, y) pair, so a wide line-up gets a wide floor rather than a vast square
    one that swallows the framing.  Lives in '_Stage'; never exported."""
    sx, sy = size if isinstance(size, (tuple, list)) else (size, size)
    c = coll("_Stage")
    clear_collection("_Stage")
    bm = bmesh.new()
    box(bm, (-sx / 2, -sy / 2, -0.25), (sx / 2, sy / 2, 0.0))
    new_obj("Floor", bm, c, "5c6672", roughness=0.95)
    bm = bmesh.new()                      # R15 blockout: 5 studs tall, 2 wide
    box(bm, (-1.0, -0.5, 0.0), (1.0, 0.5, 3.5))      # legs + torso block
    box(bm, (-0.6, -0.4, 3.5), (0.6, 0.4, 5.0))      # head
    box(bm, (-1.5, -0.35, 1.9), (-1.0, 0.35, 3.5))   # arms
    box(bm, (1.0, -0.35, 1.9), (1.5, 0.35, 3.5))
    o = new_obj("ScaleRef", bm, c, "d94f4f", roughness=0.8)
    o.location = tuple(ref_at)
    return c


def tri_count(coll_name):
    c = bpy.data.collections[coll_name]
    return {o.name: len(o.data.polygons) for o in c.objects if o.type == 'MESH'}


def bounds(coll_name):
    # matrix_world is stale until the depsgraph re-evaluates, so freshly moved objects
    # would otherwise report their pre-move bounds.
    bpy.context.view_layer.update()
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for o in bpy.data.collections[coll_name].objects:
        if o.type != 'MESH':
            continue
        for corner in o.bound_box:
            p = o.matrix_world @ Vector(corner)
            mins = Vector((min(mins.x, p.x), min(mins.y, p.y), min(mins.z, p.z)))
            maxs = Vector((max(maxs.x, p.x), max(maxs.y, p.y), max(maxs.z, p.z)))
    return mins, maxs


def report(coll_name):
    mins, maxs = bounds(coll_name)
    tris = tri_count(coll_name)
    return {"collection": coll_name, "parts": len(tris), "tris": sum(tris.values()),
            "size_studs": [round(v, 2) for v in (maxs - mins)],
            "min_z": round(mins.z, 3), "per_part": tris}


def manifest(coll_names):
    out = []
    for cn in coll_names:
        for o in sorted(bpy.data.collections[cn].objects, key=lambda o: o.name):
            if o.type != 'MESH':
                continue
            out.append({"collection": cn, "name": o.name, "hex": o.get("rbx_hex", "ffffff"),
                        "material": o.get("rbx_material", "SmoothPlastic"),
                        "transparency": float(o.get("rbx_transparency", 0.0)),
                        "tris": len(o.data.polygons)})
    return out


def _setup_world(scene, bg=(0.13, 0.15, 0.19)):
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    node = world.node_tree.nodes.get("Background")
    if node:
        node.inputs[0].default_value = (bg[0], bg[1], bg[2], 1)
        node.inputs[1].default_value = 1.0


def _lights():
    sun = bpy.data.objects.get("PreviewSun")
    if sun is None:
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", 'SUN'))
        bpy.context.scene.collection.objects.link(sun)
    sun.data.energy = 3.2
    sun.data.angle = math.radians(12)
    sun.rotation_euler = (math.radians(52), math.radians(12), math.radians(-35))
    fill = bpy.data.objects.get("PreviewFill")
    if fill is None:
        fill = bpy.data.objects.new("PreviewFill", bpy.data.lights.new("PreviewFill", 'SUN'))
        bpy.context.scene.collection.objects.link(fill)
    fill.data.energy = 1.1
    fill.rotation_euler = (math.radians(62), math.radians(-18), math.radians(145))


def render(coll_names, path, size=(960, 700), yaw_deg=35, pitch_deg=22, margin=1.12,
           with_stage=True, focus=None, engine=None, show_ref=True, lens=52):
    """Render just `coll_names` (+ the stage) to `path`.

    Props face +Y, so the camera sits on the +Y side: yaw 0 is dead-on the prop's FRONT,
    increasing yaw orbits to the prop's right, yaw 180 shows its back.  The distance is
    solved from the real field of view so the subject always fits; `margin` is the slack."""
    scene = bpy.context.scene
    names = set(coll_names) | ({"_Stage"} if with_stage else set())
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = (lc.name not in names)
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for cn in coll_names:
        a, b = bounds(cn)
        mins = Vector((min(mins.x, a.x), min(mins.y, a.y), min(mins.z, a.z)))
        maxs = Vector((max(maxs.x, b.x), max(maxs.y, b.y), max(maxs.z, b.z)))
    ref = bpy.data.objects.get("_Stage.ScaleRef")
    if with_stage and show_ref and ref is not None:
        for corner in ref.bound_box:                    # keep the avatar in shot for scale
            p = ref.matrix_world @ Vector(corner)
            mins = Vector((min(mins.x, p.x), min(mins.y, p.y), min(mins.z, p.z)))
            maxs = Vector((max(maxs.x, p.x), max(maxs.y, p.y), max(maxs.z, p.z)))
    center = Vector(focus) if focus else (mins + maxs) / 2
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    sensor = cam.data.sensor_width                      # 36 mm default
    half_h = math.atan(0.5 * sensor / lens)
    half_v = math.atan(0.5 * sensor * (size[1] / float(size[0])) / lens)
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    toward = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    # Exact fit rather than a bounding sphere: a sphere wastes most of the frame on a long
    # thin subject (a line-up of props), so solve the distance per bbox corner instead.
    # A corner at v fits horizontally when |v.right| <= (d - v.toward) * tan(half_h).
    right = toward.cross(Vector((0, 0, 1)))
    right = right.normalized() if right.length > 1e-6 else Vector((1, 0, 0))
    up = right.cross(toward).normalized()
    dist = 1.0
    for cx in (mins.x, maxs.x):
        for cy in (mins.y, maxs.y):
            for cz in (mins.z, maxs.z):
                v = Vector((cx, cy, cz)) - center
                d_along = v.dot(toward)
                dist = max(dist,
                           abs(v.dot(right)) / math.tan(half_h) + d_along,
                           abs(v.dot(up)) / math.tan(half_v) + d_along)
    dist *= margin
    off = toward * dist
    cam.location = center + off
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    _lights()
    _setup_world(scene)
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
    scene.render.engine = engine or ('BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in engines
                                     else ('BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_WORKBENCH'))
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    # Blender 4.x/5.x default to the AgX view transform, which desaturates hard and makes
    # a saturated toy palette render as pastel. These props are authored as flat Roblox
    # part colours, so render them straight.
    try:
        scene.view_settings.view_transform = 'Standard'
        scene.view_settings.look = 'None'
        scene.view_settings.exposure = 0.0
        scene.view_settings.gamma = 1.0
    except (AttributeError, TypeError):
        pass
    scene.render.filepath = path
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    return path


def render_sheet(coll_names, path, size=(1500, 1000), **kw):
    """One render containing several collections at once (the line-up shot)."""
    return render(coll_names, path, size=size, **kw)


def export_fbx(coll_name, path):
    c = bpy.data.collections[coll_name]
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    win = bpy.context.window_manager.windows[0]
    area = next((a for a in win.screen.areas if a.type == 'VIEW_3D'), win.screen.areas[0])
    region = next((r for r in area.regions if r.type == 'WINDOW'), area.regions[0])
    objs = [o for o in c.objects if o.type == 'MESH']
    with bpy.context.temp_override(window=win, area=area, region=region,
                                   selected_objects=objs, active_object=objs[0], object=objs[0]):
        for o in bpy.data.objects:
            o.select_set(False)
        for o in objs:
            o.select_set(True)
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True, apply_unit_scale=True,
                                 apply_scale_options='FBX_SCALE_ALL', global_scale=1.0,
                                 axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE',
                                 use_mesh_modifiers=True, path_mode='COPY', embed_textures=False,
                                 bake_anim=False, use_custom_props=False)
    return path
