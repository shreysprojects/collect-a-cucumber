"""lobbylib.py -- RAS - Dev lobby models (Shop / Ascend / Gift), 2026-09-24.

Authored in Blender, shipped to Roblox as MERGED MeshParts (export_mesh.py -> FBX -> Open Cloud group asset ->
install_lobby.lua). Built on defenses/defenselib.py (loaded here as L.D), same house conventions:

  * 1 Blender unit = 1 stud. Z is up. The floor is z = 0 and nothing important goes below it.
  * The model's FRONT faces +Y (Blender) - the side the player walks up to. Roblox = (x, z, -y), so in Studio the
    front faces -Z = the model's LookVector, exactly like the models it replaces.
  * The origin is the CENTRE OF THE FOOTPRINT on the floor (x and y centred on the bounding box, z = 0).
  * +X in Blender is the viewer's LEFT when they stand in front of the model (looking toward -Y).
  * Every part is ONE Blender object with ONE flat look: rbx_hex / rbx_material / rbx_transparency / rbx_collide /
    rbx_shadow, plus a mesh label rbx_mesh. export_mesh.py merges parts sharing (label, look) into one MeshPart
    named <label> (a second look under the same label becomes <label>_2 ...). Colours + materials are re-applied
    in Studio from out/<Key>.mesh.json because FBX imports arrive grey.

    import lobbylib as L            (run_one.py does this and passes L to build(L))
    m = L.Model("Shop")
    m.box("Counter", (-6, -1.5, 0), (6, 1.5, 3.4), "9a6238", "Wood", bevel=0.15, mesh="Counter")
    m.cyl("PostL", (-7, 2.5, 0), (-7, 2.5, 9), 0.35, "c68c52", "Wood", mesh="Posts")
    m.sphere("Ball1", (0, 0, 4), 0.6, "f4f8fc", mesh="Snowballs")
    m.text("SignText", "SHOP", size=2.4, depth=0.5, loc=(0, 0.9, 11.2), hex="ffc93c", mesh="SignLetters")
    return m.finish()

Every helper takes the look as (hex, material) + keyword options:
    mesh="Label"          merge label (default = the part name); use a few meaningful labels per model
    transparency=0.0      Roblox Transparency (Neon glow panes ~0.2-0.4)
    collide=True          CanCollide in Roblox (floating decor, sparkles, halos: False)
    shadow=True           CastShadow
    smooth=None           smooth shading (default: True for spheres/lathes/tori, False otherwise)
"""
import bpy
import bmesh
import math
import os
import sys
import importlib.util
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
GAMES = os.path.dirname(os.path.dirname(HERE))  # ...\RobloxGames


def _load(path, name):
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


D = _load(os.path.join(GAMES, "defenses", "defenselib.py"), "defenselib")
D.bpy = bpy

FONTS = {
    "gill": r"C:\Windows\Fonts\GILSANUB.TTF",   # Gill Sans Ultra Bold - chunky toy lettering (default)
    "black": r"C:\Windows\Fonts\ariblk.ttf",    # Arial Black
    "segoe": r"C:\Windows\Fonts\seguibl.ttf",   # Segoe UI Black
}

# Shared palette for the set (use these unless a model has a reason not to). Hex strings, no '#'.
PALETTE = {
    "snow": "f4f8fc", "snow_shade": "d7e6f2", "ice": "9fd3ff", "frost": "c4e8ff",
    "gold": "ffc93c", "gold_dark": "e0a526", "gold_neon": "ffd54a",
    "wood": "9a6238", "wood_light": "c68c52", "wood_dark": "6b4226",
    "slate": "2c3a55", "slate_light": "3b4a66",
    "orange": "ff8c1a", "cream": "fff1d6", "red": "e8413c",
    "green": "36c45a", "green_dark": "1f9447", "blue": "3a8cf0", "purple": "a45de0",
    "marble": "f3f5fa", "white": "ffffff",
}

ROBLOX_MATERIALS = {
    "Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Slate", "Concrete", "Granite",
    "Brick", "Pebble", "Cobblestone", "Rock", "Sandstone", "Basalt", "CrackedLava", "Limestone", "Pavement",
    "CorrodedMetal", "DiamondPlate", "Foil", "Metal", "Grass", "LeafyGrass", "Sand", "Fabric", "Snow",
    "Mud", "Ground", "Asphalt", "Salt", "Ice", "Glacier", "Glass", "ForceField", "Carpet", "CeramicTiles",
    "ClayRoofTiles", "RoofShingles", "Leather", "Plaster", "Rubber", "Cardboard",
}

MAX_TRIS_PER_MESH = 9000     # Roblox imports up to ~20k per MeshPart; stay well under
MAX_TRIS_TOTAL = 45000


def bm():
    return bmesh.new()


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def xf(loc=(0, 0, 0), rz=0.0, rx=0.0, ry=0.0, scale=1.0):
    """4x4: scale, then rotate X, Y, Z (degrees, in that order), then translate."""
    s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
    R = (Matrix.Rotation(math.radians(rz), 4, 'Z') @ Matrix.Rotation(math.radians(ry), 4, 'Y')
         @ Matrix.Rotation(math.radians(rx), 4, 'X'))
    return Matrix.Translation(Vector(loc)) @ R @ Matrix.Diagonal((s[0], s[1], s[2], 1))


# ---------------------------------------------------------------- 2-D profile helpers (for prism / lathe)
def circle_pts(r, n=24, center=(0, 0), phase=0.0):
    return [(center[0] + r * math.cos(phase + 2 * math.pi * i / n), center[1] + r * math.sin(phase + 2 * math.pi * i / n))
            for i in range(n)]


def rounded_rect_pts(w, h, r, segs=4, center=(0, 0)):
    """Rounded rectangle outline, w x h, corner radius r (clamped)."""
    r = max(0.0, min(r, w / 2 - 1e-4, h / 2 - 1e-4))
    cx, cy = center
    pts = []
    corners = [(w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)]
    for (x, y, a0) in corners:
        if r <= 1e-4:
            pts.append((cx + x, cy + y))
            continue
        for i in range(segs + 1):
            a = math.radians(a0 + 90.0 * i / segs)
            pts.append((cx + x + r * math.cos(a), cy + y + r * math.sin(a)))
    return pts


def star_pts(n, r_out, r_in, center=(0, 0), phase=math.pi / 2):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = phase + math.pi * i / n
        pts.append((center[0] + r * math.cos(a), center[1] + r * math.sin(a)))
    return pts


def arc_pts(r, a0, a1, n=12, center=(0, 0)):
    """Points on an arc from angle a0 to a1 (degrees), inclusive."""
    return [(center[0] + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             center[1] + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def leaf_pts(length, width, n=10, tip_sharp=1.0):
    """Feather / leaf outline along +X from (0,0) to (length,0), max width at ~40 % of the length."""
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        w = width / 2 * math.sin(math.pi * (t ** 0.8)) ** tip_sharp
        top.append((t * length, w))
        bot.append((t * length, -w))
    return top + list(reversed(bot[1:-1]))


# ---------------------------------------------------------------- geometry that appends into a bmesh
def lathe(b, profile, segs=24, matrix=None):
    """Revolve a profile [(r, z), ...] (bottom to top) about the local Z axis. r = 0 makes a pole.
    Caps the open ends. Returns the new verts."""
    rings = []
    for (r, z) in profile:
        if r <= 1e-6:
            rings.append([b.verts.new((0.0, 0.0, z))])
        else:
            rings.append([b.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z))
                          for i in range(segs)])
    for k in range(len(rings) - 1):
        a, c = rings[k], rings[k + 1]
        if len(a) == 1 and len(c) == 1:
            continue
        if len(a) == 1:
            for i in range(segs):
                b.faces.new((a[0], c[i], c[(i + 1) % segs]))
        elif len(c) == 1:
            for i in range(segs):
                b.faces.new((a[i], c[0], a[(i + 1) % segs])[::-1])
        else:
            for i in range(segs):
                b.faces.new((a[i], a[(i + 1) % segs], c[(i + 1) % segs], c[i]))
    if len(rings[0]) > 1:
        b.faces.new(tuple(reversed(rings[0])))
    if len(rings[-1]) > 1:
        b.faces.new(tuple(rings[-1]))
    out = [v for r in rings for v in r]
    if matrix is not None:
        bmesh.ops.transform(b, matrix=matrix, verts=out)
    return out


def prism_bevel(b, pts2d, z0, z1, matrix=None, bevel=0.0, segments=1):
    """defenselib.prism (extrude a simple closed 2-D outline from z0 to z1) with optional bevelled edges."""
    pre = set(b.verts)
    vs = D.prism(b, pts2d, z0, z1)
    if bevel > 1e-5:
        vset = set(vs)
        edges = [e for e in b.edges if e.verts[0] in vset and e.verts[1] in vset]
        bmesh.ops.bevel(b, geom=list(vset) + edges, offset=bevel, segments=segments, profile=0.5,
                        affect='EDGES', clamp_overlap=True)
        b.verts.ensure_lookup_table()
        vs = [v for v in b.verts if v not in pre]
    if matrix is not None:
        bmesh.ops.transform(b, matrix=matrix, verts=vs)
    return vs


def text_bm(body, size=2.0, depth=0.4, font="gill", bevel=0.03, spacing=1.0, resolution=3, align="CENTER"):
    """3-D lettering as a new bmesh: letters stand upright, face +Y (readable from the front), centred on the
    origin horizontally and vertically, `depth` thick along Y."""
    cu = bpy.data.curves.new("_txt", 'FONT')
    cu.body = body
    path = FONTS.get(font, font)
    try:
        cu.font = bpy.data.fonts.load(path, check_existing=True)
    except Exception:
        pass
    cu.size = size
    cu.extrude = max(0.0, depth / 2 - bevel)
    cu.bevel_depth = bevel
    cu.bevel_resolution = 1 if bevel > 0 else 0
    cu.resolution_u = resolution
    cu.space_character = spacing
    cu.align_x = align
    cu.align_y = 'CENTER'
    ob = bpy.data.objects.new("_txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    b = bmesh.new()
    b.from_mesh(me)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.curves.remove(cu)
    bpy.data.meshes.remove(me)
    bmesh.ops.remove_doubles(b, verts=b.verts, dist=1e-4)
    # letters lie in XY facing +Z -> stand them up facing +Y, reading toward the viewer's right (-X)
    R = Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Rotation(math.pi / 2, 4, 'X')
    bmesh.ops.transform(b, matrix=R, verts=b.verts)
    return b


# ---------------------------------------------------------------- the model
class Model:
    def __init__(self, key, kept=()):
        self.key = key
        self.coll = D.coll(key)
        D.clear_collection(key)
        self.objs = []
        self.attrs = {}
        self.kept = list(kept)       # names that must exist as mesh labels (scripts look them up)
        self._names = set()

    # core ---------------------------------------------------------------------------------------------
    def add(self, name, b, hex, material="SmoothPlastic", mesh=None, transparency=0.0, collide=True, shadow=True,
            smooth=False, reflectance=0.0):
        hex = hex.lstrip("#").lower()
        assert len(hex) == 6 and all(c in "0123456789abcdef" for c in hex), name + ": bad colour " + hex
        assert material in ROBLOX_MATERIALS, name + ": unknown Roblox material " + material
        assert name not in self._names, "duplicate part name " + name
        assert len(b.verts) > 0, name + ": empty geometry"
        self._names.add(name)
        metallic = 0.6 if material in ("Metal", "DiamondPlate", "Foil", "CorrodedMetal") else 0.0
        rough = 0.25 if material in ("Glass", "Ice", "Glacier", "Marble", "Foil") else 0.55
        obj = D.new_obj(name, b, self.coll, hex, rbx_material=material, transparency=transparency,
                        metallic=metallic, roughness=rough, smooth=smooth)
        # defenselib feeds the sRGB hex straight in as LINEAR colour, which the Standard view transform then lifts
        # to pastel; give the renders the real Roblox colour instead (render-only, the export reads rbx_hex)
        lin = tuple(_srgb_to_linear(int(hex[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)
        mat = obj.data.materials[0]
        bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf:
            bsdf.inputs["Base Color"].default_value = lin
            if material == "Neon" and "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = lin
                bsdf.inputs["Emission Strength"].default_value = 1.2
        if smooth:
            # smooth curved walls, but keep caps / creases sharp (a smooth cap averages into the side walls and
            # renders as a dark wedge); the FBX carries these split normals into Roblox
            me = obj.data
            fn = getattr(me, "set_sharp_from_angle", None) or getattr(me, "set_sharpness_by_angle", None)  # 5.2 renamed it
            if fn is not None:
                fn(angle=math.radians(40))
        obj["rbx_mesh"] = mesh or name
        obj["rbx_collide"] = bool(collide)
        obj["rbx_shadow"] = bool(shadow)
        obj["rbx_reflectance"] = float(reflectance)
        obj["rbx_part"] = name
        if transparency > 0:
            mat = obj.data.materials[0]
            bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
            if bsdf and "Alpha" in bsdf.inputs:
                bsdf.inputs["Alpha"].default_value = max(0.05, 1.0 - transparency)
            for attr, value in (("surface_render_method", 'BLENDED'), ("blend_method", 'BLEND')):
                try:
                    setattr(mat, attr, value)
                    break
                except Exception:
                    pass
        self.objs.append(obj)
        return obj

    # convenience primitives -----------------------------------------------------------------------------
    def box(self, name, lo, hi, hex, material="SmoothPlastic", bevel=0.12, segments=1, matrix=None, **kw):
        """Box from corner lo to hi (bevelled edges). `matrix` (from L.xf) is applied after."""
        b = bm()
        vs = D.beveled_box(b, lo, hi, bevel=bevel, segments=segments)
        if matrix is not None:
            bmesh.ops.transform(b, matrix=matrix, verts=b.verts)
        return self.add(name, b, hex, material, **kw)

    def cyl(self, name, a, c, r, hex, material="SmoothPlastic", segs=16, r2=None, smooth=True, **kw):
        """Cylinder (cone when r2 is given) from point a to point c."""
        b = bm()
        D.cyl(b, a, c, r, segs=segs, r2=r2)
        return self.add(name, b, hex, material, smooth=smooth, **kw)

    def sphere(self, name, loc, r, hex, material="SmoothPlastic", scale=(1, 1, 1), subdiv=2, smooth=True, **kw):
        b = bm()
        D.ico(b, loc, r, subdiv=subdiv, scale=scale)
        return self.add(name, b, hex, material, smooth=smooth, **kw)

    def prism(self, name, pts2d, z0, z1, hex, material="SmoothPlastic", matrix=None, bevel=0.0, **kw):
        """Extrude a closed 2-D outline (x, y) from z0 to z1, bevel the edges, then apply `matrix`."""
        b = bm()
        prism_bevel(b, pts2d, z0, z1, matrix=matrix, bevel=bevel)
        return self.add(name, b, hex, material, **kw)

    def lathe(self, name, profile, hex, material="SmoothPlastic", matrix=None, segs=24, smooth=True, **kw):
        b = bm()
        lathe(b, profile, segs=segs, matrix=matrix)
        return self.add(name, b, hex, material, smooth=smooth, **kw)

    def torus(self, name, loc, major, minor, hex, material="SmoothPlastic", rot=None, seg_major=32, seg_minor=10,
              smooth=True, **kw):
        """rot: a 4x4 (e.g. L.xf(rx=90)) - the default ring lies flat in XY."""
        b = bm()
        D.torus(b, loc, major, minor, rot=rot, seg_major=seg_major, seg_minor=seg_minor)
        return self.add(name, b, hex, material, smooth=smooth, **kw)

    def tube(self, name, points, radii, hex, material="SmoothPlastic", segs=10, smooth=True, **kw):
        b = bm()
        D.tube(b, points, radii, segs=segs)
        return self.add(name, b, hex, material, smooth=smooth, **kw)

    def text(self, name, body, size, depth, hex, material="SmoothPlastic", loc=(0, 0, 0), rz=0.0, font="gill",
             bevel=0.03, spacing=1.0, **kw):
        """Upright 3-D letters facing +Y, centred at `loc` (rz turns them about Z, e.g. 180 for the back)."""
        b = text_bm(body, size=size, depth=depth, font=font, bevel=bevel, spacing=spacing)
        bmesh.ops.transform(b, matrix=xf(loc, rz=rz), verts=b.verts)
        return self.add(name, b, hex, material, **kw)

    def custom(self, name, fn, hex, material="SmoothPlastic", **kw):
        """fn(bmesh) appends any geometry (use L.D.* / L.lathe / L.prism_bevel ...)."""
        b = bm()
        fn(b)
        return self.add(name, b, hex, material, **kw)

    def attr(self, name, value):
        self.attrs[name] = value

    # report -----------------------------------------------------------------------------------------------
    def finish(self):
        bpy.context.view_layer.update()
        mins, maxs = D.bounds(self.key)
        groups = {}
        parts = []
        for o in self.objs:
            look = (o["rbx_mesh"], o["rbx_hex"], o["rbx_material"], round(float(o["rbx_transparency"]), 3),
                    bool(o["rbx_collide"]), bool(o["rbx_shadow"]), round(float(o["rbx_reflectance"]), 3))
            tris = len(o.data.polygons)
            groups.setdefault(look, 0)
            groups[look] += tris
            parts.append({"name": o["rbx_part"], "mesh": o["rbx_mesh"], "hex": o["rbx_hex"], "material": o["rbx_material"],
                          "transparency": float(o["rbx_transparency"]), "collide": bool(o["rbx_collide"]), "tris": tris})
        labels = sorted({g[0] for g in groups})
        total = sum(groups.values())
        problems = []
        for look, t in groups.items():
            if t > MAX_TRIS_PER_MESH:
                problems.append("mesh %s (%s %s) has %d tris > %d" % (look[0], look[1], look[2], t, MAX_TRIS_PER_MESH))
        if total > MAX_TRIS_TOTAL:
            problems.append("total %d tris > %d" % (total, MAX_TRIS_TOTAL))
        for k in self.kept:
            if k not in labels:
                problems.append("required mesh label missing: " + k)
        if mins.z < -0.35:
            problems.append("geometry goes %.2f studs below the floor" % mins.z)
        cx, cy = (mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2
        if abs(cx) > 0.25 or abs(cy) > 0.25:
            problems.append("footprint not centred on the origin: centre (%.2f, %.2f)" % (cx, cy))
        return {
            "key": self.key,
            "size_studs": {"width_x": round(maxs.x - mins.x, 2), "depth_y": round(maxs.y - mins.y, 2),
                           "height_z": round(maxs.z - mins.z, 2)},
            "min": [round(v, 3) for v in mins], "max": [round(v, 3) for v in maxs],
            "parts": len(self.objs), "meshes_after_merge": len(groups), "labels": labels, "tris_total": total,
            "meshes": [{"label": g[0], "hex": g[1], "material": g[2], "transparency": g[3], "collide": g[4],
                        "tris": t} for g, t in sorted(groups.items())],
            "attrs": self.attrs, "problems": problems, "part_list": parts,
        }
