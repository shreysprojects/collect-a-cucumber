"""export_mesh.py -- turn a primlib model (out/<Key>.parts.json) into a MERGED-MESH FBX for an Open Cloud upload.

    blender -b --factory-startup --python export_mesh.py -- <Key> [<Key> ...]

Parts a behaviour / defence rig needs stay separate (their exact names survive); every other part is merged with
the parts that share its look (colour, material, transparency, reflectance, collide, shadow) into one mesh. So a
70-part sofa becomes a handful of MeshParts and nothing that scripts touch changes name or pivot.
  KEPT = exact name or name prefix appears as a string literal (>= 3 chars) in src/behaviours/{server,client}/<Base>.lua
         or in any behaviour module there whose B.Keys lists the key (Sofa.lua serves the Armchair),
         or (category Defences) the DefenceService rig names: Orb, BasePlinth, HeadTrunnion, BarrelMuzzleGlow, Beam1..4
         exact, and the moving prefix groups Head / Barrel / Spin / Mount / Tube + the FX prefix Glow, which are merged
         per (prefix, look) into "<Prefix>_<n>" so DefenceService's prefix grouping still sees them.
Writes out/<Key>.fbx and out/<Key>.mesh.json: {key, category, objects: [{name, color, material, transparency,
reflectance, collide, shadow, parts}], pivots, attrs, parts_hash}. Object names are unique (a clash gets "_2", "_3").
Blender coords = (x, -z, y) of Roblox; the importer's 180-degree yaw is undone by the installer.
"""
import bpy, bmesh, sys, os, json, re, hashlib, math
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.abspath(__file__))
FB = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, "out")
sys.path.insert(0, ROOT)
import primlib as P  # geometry helpers (no Blender objects are made through it here)

DEF_EXACT = {"Orb", "BasePlinth", "HeadTrunnion", "BarrelMuzzleGlow"} | {"Beam%d" % i for i in range(1, 9)}  # LaserGate v2 has Beam1..6 (DefenceService LASER.MaxBeams 8)
DEF_PREFIX = ["Head", "Barrel", "Spin", "Mount", "Tube", "Glow"]


def serves(src, key):
    """True when a behaviour module's `B.Keys = {...}` lists `key` or one of its variants (`key`_A ...).
    (2026-09-24 HomeLiving fix: Sofa.lua serves the Armchair too, and there is no Armchair.lua.)"""
    m = re.search(r'\bB\.Keys\s*=\s*\{([^}]*)\}', src)
    if not m:
        return False
    for k in re.findall(r'["\']([A-Za-z0-9_]+)["\']', m.group(1)):
        if k == key or re.sub(r'_[A-Z]$', '', k) == key:
            return True
    return False


def literals_for(key):
    """String literals (>= 3 chars) of every behaviour module that serves `key`: src/behaviours/{server,client}/<key>.lua
    plus any other module there whose B.Keys lists the key (one module can serve several builds)."""
    lits = set()
    for kind in ("server", "client"):
        folder = os.path.join(FB, "src", "behaviours", kind)
        if not os.path.isdir(folder):
            continue
        for fn in sorted(os.listdir(folder)):
            if not fn.endswith(".lua"):
                continue
            src = open(os.path.join(folder, fn), encoding="utf-8").read()
            if fn != key + ".lua" and not serves(src, key):
                continue
            # a module that borrows a sibling's code (Dryer requires script.Parent.WashingMachine) needs that
            # sibling's part names too
            sources = [src]
            for dep in re.findall(r'script\.Parent:WaitForChild\(\s*["\']([A-Za-z0-9_]+)["\']', src):
                dp = os.path.join(folder, dep + ".lua")
                if os.path.exists(dp):
                    sources.append(open(dp, encoding="utf-8").read())
            for s in sources:
                for m in re.finditer(r'["\']([A-Za-z_][A-Za-z0-9_]*)["\']', s):
                    if len(m.group(1)) >= 3:
                        lits.add(m.group(1))
    return lits


def geo(p):
    s = p["size"]
    shape = p["shape"]
    if shape == "Block":
        return P._box_geo(*s)
    if shape == "Wedge":
        return P._wedge_geo(*s)
    if shape == "CornerWedge":
        return P._corner_geo(*s)
    if shape == "Cylinder":
        return P._cyl_geo(s[0], s[1], 24)
    return P._sphere_geo(*s, segs=20, rings=12)


def world_verts(p, verts):
    c = p["cf"]
    R = Matrix(((c[3], c[4], c[5]), (c[6], c[7], c[8]), (c[9], c[10], c[11])))
    t = Vector((c[0], c[1], c[2]))
    out = []
    for v in verts:
        w = R @ Vector(v) + t
        out.append(Vector((w.x, -w.z, w.y)))  # Roblox -> Blender
    return out


def look_of(p):
    return (p["color"], p["material"], round(float(p.get("transparency", 0)), 3), round(float(p.get("reflectance", 0)), 3),
            bool(p.get("collide", True)), bool(p.get("shadow", True)))


def export(key):
    info = json.load(open(os.path.join(OUT, key + ".parts.json"), encoding="utf-8"))
    category = info.get("category", "Home")
    lits = literals_for(key)
    groups = {}  # group key -> {"name", "look", "parts"}
    order = []
    for p in info["parts"]:
        name = p["name"]
        look = look_of(p)
        gk = None
        if category == "Defences":
            if name in DEF_EXACT:
                gk = ("exact", name, look)
            else:
                for pre in DEF_PREFIX:
                    if name.startswith(pre):
                        gk = ("prefix", pre, look)
                        break
                if gk is None:
                    gk = ("static", "Base", look)
        else:
            kept = any(name == l or (name.startswith(l)) for l in lits)
            gk = ("exact", name, look) if kept else ("static", None, look)
        if gk not in groups:
            groups[gk] = {"parts": [], "look": look, "kind": gk[0], "base": gk[1]}
            order.append(gk)
        groups[gk]["parts"].append(p)
    # names
    taken = set()
    objects = []
    for gk in order:
        g = groups[gk]
        if g["kind"] == "exact":
            stem, name = g["base"], g["base"]
        elif g["kind"] == "prefix":
            stem = g["base"]
            name = stem + "_1"
        elif g["base"]:  # defence static
            stem, name = "Base", "Base_1"
        else:
            stem = g["parts"][0]["name"] + "_m"
            name = stem
        i = 2
        while name in taken:
            name = "%s_%d" % (stem, i)
            i += 1
        taken.add(name)
        g["name"] = name
        objects.append(g)
    # build Blender objects
    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = bpy.data.collections.new(key)
    bpy.context.scene.collection.children.link(coll)
    for g in objects:
        bm = bmesh.new()
        for p in g["parts"]:
            v, f = geo(p)
            wv = world_verts(p, v)
            bv = [bm.verts.new(x) for x in wv]
            # curved surfaces shade smooth, flat faces (blocks, wedges, cylinder CAPS) stay flat: a smooth cap
            # would average into the side walls and render as a dark smear (_cyl_geo lists the side quads first)
            nside = len(f) - 2 if p["shape"] == "Cylinder" else (len(f) if p["shape"] in ("Ball", "Ellipsoid") else 0)
            for fi, face in enumerate(f):
                try:
                    nf = bm.faces.new([bv[i] for i in face])
                    nf.smooth = fi < nside
                except ValueError:
                    pass
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        # box-projected UVs (2 studs per tile) so Roblox material textures have something to map onto
        uv = bm.loops.layers.uv.new("UVMap")
        for face in bm.faces:
            n = face.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for loop in face.loops:
                co = loop.vert.co
                a, b = [(co.y, co.z), (co.x, co.z), (co.x, co.y)][ax]
                loop[uv].uv = (a / 2.0, b / 2.0)
        me = bpy.data.meshes.new(g["name"])
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(g["name"], me)
        coll.objects.link(obj)
        # origin at the geometry centre (Roblox puts a MeshPart's CFrame at its bounds centre anyway)
        bbmin = Vector((min(v.co.x for v in me.vertices), min(v.co.y for v in me.vertices), min(v.co.z for v in me.vertices)))
        bbmax = Vector((max(v.co.x for v in me.vertices), max(v.co.y for v in me.vertices), max(v.co.z for v in me.vertices)))
        centre = (bbmin + bbmax) / 2
        me.transform(Matrix.Translation(-centre))
        obj.location = centre
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        o.select_set(o.name in coll.objects)
    bpy.context.view_layer.objects.active = coll.objects[0]
    fbx = os.path.join(OUT, key + ".fbx")
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL',
                             global_scale=1.0, axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE',
                             use_mesh_modifiers=True, path_mode='COPY', embed_textures=False, bake_anim=False,
                             use_custom_props=False)
    raw = open(os.path.join(OUT, key + ".parts.json"), "rb").read()
    meta = {"key": key, "category": category, "parts_hash": hashlib.sha1(raw).hexdigest()[:12],
            "pivots": info.get("pivots", {}), "attrs": info.get("attrs", {}), "size_studs": info.get("size_studs"),
            "objects": [{"name": g["name"], "color": g["look"][0], "material": g["look"][1], "transparency": g["look"][2],
                         "reflectance": g["look"][3], "collide": g["look"][4], "shadow": g["look"][5],
                         "parts": len(g["parts"])} for g in objects]}
    json.dump(meta, open(os.path.join(OUT, key + ".mesh.json"), "w", encoding="utf-8"), indent=1)
    print("MESH %s: %d parts -> %d meshes (%d kept names) fbx %d KB" % (key, len(info["parts"]), len(objects),
          sum(1 for g in objects if g["kind"] != "static"), os.path.getsize(fbx) // 1024))


keys = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for k in keys:
    try:
        export(k)
    except Exception:
        import traceback
        print("MESH ERROR " + k + "\n" + traceback.format_exc())
