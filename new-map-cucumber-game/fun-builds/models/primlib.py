"""primlib.py -- Roblox-PART models authored in Blender (fun-builds, 2026-09-24).

Every model is built from the primitives a Roblox Part can be - so it ships as Parts with NO asset
upload (no Open Cloud key on this machine) and still renders in Blender for review:

    Block        Part (Block)                          any size
    Wedge        WedgePart                             slope RISES toward local +Z (tall face at +Z,
                                                       sharp edge at -Z = the front), like Studio's wedge
    CornerWedge  CornerWedgePart                       apex edge at local (+X, -Z)
    Cylinder     Part (Cylinder)                       AXIS = local X; Size.Y == Size.Z (diameter)
    Ball         Part (Ball)                           uniform size (a Roblox Ball can't be stretched)
    Ellipsoid    Part (Block) + SpecialMesh Sphere     any size - soft rounded shapes (cushions, bellies)

EVERYTHING IS IN ROBLOX COORDINATES: studs, +Y up, the model's FRONT faces -Z (the side a player walks
up to), +X is the viewer's LEFT when they stand in front of it (Roblox is right-handed). The origin is
the FLOOR CENTRE of the build (min y = 0). Rotations are degrees, applied like CFrame.Angles(rx, ry, rz)
(the matrix Rx * Ry * Rz). The renders view from the front (-Z side) with a 6-stud blockout avatar.

    import primlib as P
    m = P.Model(D, "Sofa")
    m.block("Base", (0, 1, 0), (7, 1.2, 3), "7a4b2c", "Wood")
    m.cyl("ArmL", (3.2, 1.9, -1.4), (3.2, 1.9, 1.4), 1.0, "c45a4a", "Fabric")  # from a to b, diameter
    m.ellipsoid("CushionL", (1.7, 2.1, 0), (3.2, 0.8, 2.6), "e46b5b", "Fabric")
    m.pivot("SeatL", (1.7, 2.3, 0))           # -> attribute Pivot_SeatL on the Roblox model
    m.attr("Cost", 500)
    return m.finish()

finish() returns the dict run_one.py writes to out/<Key>.parts.json (see install_models.lua).
"""
import math
import bmesh
from mathutils import Vector, Matrix

ROBLOX_MATERIALS = {
    "Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Slate", "Concrete", "Granite",
    "Brick", "Pebble", "Cobblestone", "Rock", "Sandstone", "Basalt", "CrackedLava", "Limestone", "Pavement",
    "CorrodedMetal", "DiamondPlate", "Foil", "Metal", "Grass", "LeafyGrass", "Sand", "Fabric", "Snow",
    "Mud", "Ground", "Asphalt", "Salt", "Ice", "Glacier", "Glass", "ForceField", "Carpet", "CeramicTiles",
    "ClayRoofTiles", "RoofShingles", "Leather", "Plaster", "Rubber", "Cardboard",
}
SHAPES = {"Block", "Wedge", "CornerWedge", "Cylinder", "Ball", "Ellipsoid"}


def angles(rx=0.0, ry=0.0, rz=0.0):
    """CFrame.Angles(rx, ry, rz) in degrees -> 3x3 (Rx * Ry * Rz)."""
    return (Matrix.Rotation(math.radians(rx), 3, 'X') @ Matrix.Rotation(math.radians(ry), 3, 'Y')
            @ Matrix.Rotation(math.radians(rz), 3, 'Z'))


def _rot(rot):
    if rot is None:
        return Matrix.Identity(3)
    if isinstance(rot, Matrix):
        return rot.to_3x3()
    return angles(*rot)


def frame_x(direction, up_hint=(0, 1, 0)):
    """Rotation whose local +X points along `direction` (cylinders, rods)."""
    x = Vector(direction).normalized()
    up = Vector(up_hint)
    if abs(x.dot(up.normalized())) > 0.98:
        up = Vector((0, 0, 1)) if abs(x.z) < 0.9 else Vector((1, 0, 0))
    z = x.cross(up).normalized()
    y = z.cross(x).normalized()
    return Matrix((x, y, z)).transposed()


def frame_z(direction, up_hint=(0, 1, 0)):
    """Rotation whose local -Z (LookVector) points along `direction` (beams, legs, planks)."""
    look = Vector(direction).normalized()
    up = Vector(up_hint)
    if abs(look.dot(up.normalized())) > 0.98:
        up = Vector((0, 0, 1)) if abs(look.z) < 0.9 else Vector((1, 0, 0))
    right = look.cross(up).normalized()
    up2 = right.cross(look).normalized()
    return Matrix((right, up2, -look)).transposed()


def _hex(c):
    c = c.lstrip("#").lower()
    assert len(c) == 6 and all(ch in "0123456789abcdef" for ch in c), "colour must be 6 hex digits: " + c
    return c


# ---------------------------------------------------------------- local geometry (Roblox part space)
def _box_geo(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
         (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 4, 7, 3)]
    return v, f


def _wedge_geo(sx, sy, sz):
    # tall face at +Z, sharp bottom edge at -Z (verified in Studio 2026-09-24: top y = z * h/d)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    f = [(0, 1, 2, 3), (3, 2, 4, 5), (0, 5, 4, 1), (1, 4, 2), (0, 3, 5)]
    return v, f


def _corner_geo(sx, sy, sz):
    # apex straight above the (+X, -Z) bottom corner (Studio 2026-09-24: top y = min(x*h/w, -z*h/d))
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (hx, hy, -hz)]
    f = [(0, 1, 2, 3), (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)]
    return v, f


def _cyl_geo(length, diameter, segs=20):
    r, h = diameter / 2, length / 2
    v, f = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        v.append((-h, r * math.cos(a), r * math.sin(a)))
        v.append((h, r * math.cos(a), r * math.sin(a)))
    for i in range(segs):
        j = (i + 1) % segs
        f.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
    f.append(tuple(2 * i for i in range(segs))[::-1])
    f.append(tuple(2 * i + 1 for i in range(segs)))
    return v, f


def _sphere_geo(sx, sy, sz, segs=18, rings=10):
    v, f = [], []
    for ri in range(rings + 1):
        th = math.pi * ri / rings
        for si in range(segs):
            ph = 2 * math.pi * si / segs
            v.append((sx / 2 * math.sin(th) * math.cos(ph), sy / 2 * math.cos(th), sz / 2 * math.sin(th) * math.sin(ph)))
    for ri in range(rings):
        for si in range(segs):
            a = ri * segs + si
            b = ri * segs + (si + 1) % segs
            f.append((a, b, b + segs, a + segs))
    return v, f


def _to_blender(p):
    return Vector((p[0], -p[2], p[1]))


class Model:
    def __init__(self, D, key, category="Home"):
        self.D = D
        self.key = key
        self.category = category
        self.coll = D.coll(key)
        D.clear_collection(key)
        self.parts = []
        self.pivots = {}
        self.attrs = {}
        self._names = {}

    # ---------------------------------------------------------------- core
    def _add(self, shape, name, pos, size, color, material, transparency=0.0, rot=None, reflectance=0.0,
             collide=True, shadow=True, smooth=None, segs=20):
        assert shape in SHAPES, shape
        assert material in ROBLOX_MATERIALS, "unknown Roblox material " + material
        color = _hex(color)
        size = tuple(float(s) for s in size)
        assert all(s >= 0.05 for s in size), "%s: Roblox parts are at least 0.05 studs per side (%s)" % (name, size)
        if shape == "Ball":
            assert abs(size[0] - size[1]) < 1e-6 and abs(size[1] - size[2]) < 1e-6, name + ": a Ball must be uniform - use ellipsoid()"
        if shape == "Cylinder":
            assert abs(size[1] - size[2]) < 1e-6, name + ": a Cylinder needs Size.Y == Size.Z (axis = X)"
        R = _rot(rot)
        t = Vector(pos)
        # unique part names are not required by Roblox, but behaviours find parts by name - warn on clashes
        self._names[name] = self._names.get(name, 0) + 1
        if shape in ("Block",):
            v, f = _box_geo(*size)
        elif shape == "Wedge":
            v, f = _wedge_geo(*size)
        elif shape == "CornerWedge":
            v, f = _corner_geo(*size)
        elif shape == "Cylinder":
            v, f = _cyl_geo(size[0], size[1], segs)
        else:  # Ball / Ellipsoid
            v, f = _sphere_geo(*size)
        bm = bmesh.new()
        verts = [bm.verts.new(_to_blender(R @ Vector(p) + t)) for p in v]
        for face in f:
            try:
                bm.faces.new([verts[i] for i in face])
            except ValueError:
                pass
        obj = self.D.new_obj(name, bm, self.coll, color, rbx_material=material, transparency=transparency,
                             metallic=0.6 if material in ("Metal", "DiamondPlate", "Foil", "CorrodedMetal") else 0.0,
                             roughness=0.25 if material in ("Glass", "Ice", "Glacier", "Marble", "Foil") else 0.6,
                             smooth=(shape in ("Cylinder", "Ball", "Ellipsoid")) if smooth is None else smooth)
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
        cf = [t.x, t.y, t.z, R[0][0], R[0][1], R[0][2], R[1][0], R[1][1], R[1][2], R[2][0], R[2][1], R[2][2]]
        self.parts.append({
            "name": name, "shape": shape, "size": [round(s, 4) for s in size],
            "cf": [round(float(c), 5) for c in cf], "color": color, "material": material,
            "transparency": float(transparency), "reflectance": float(reflectance),
            "collide": bool(collide), "shadow": bool(shadow),
        })
        return obj

    # ---------------------------------------------------------------- primitives
    def block(self, name, pos, size, color, material="SmoothPlastic", **kw):
        return self._add("Block", name, pos, size, color, material, **kw)

    def wedge(self, name, pos, size, color, material="SmoothPlastic", **kw):
        """Slope rises toward local +Z; turn it with rot (e.g. rot=(0, 180, 0) to rise toward -Z)."""
        return self._add("Wedge", name, pos, size, color, material, **kw)

    def corner(self, name, pos, size, color, material="SmoothPlastic", **kw):
        return self._add("CornerWedge", name, pos, size, color, material, **kw)

    def ball(self, name, pos, diameter, color, material="SmoothPlastic", **kw):
        return self._add("Ball", name, pos, (diameter, diameter, diameter), color, material, **kw)

    def ellipsoid(self, name, pos, size, color, material="SmoothPlastic", **kw):
        return self._add("Ellipsoid", name, pos, size, color, material, **kw)

    def cylx(self, name, pos, length, diameter, color, material="SmoothPlastic", rot=None, **kw):
        """Cylinder centred at pos with its axis along the part's local X (turn it with rot)."""
        return self._add("Cylinder", name, pos, (length, diameter, diameter), color, material, rot=rot, **kw)

    def cyl(self, name, a, b, diameter, color, material="SmoothPlastic", **kw):
        """Cylinder from point a to point b."""
        a, b = Vector(a), Vector(b)
        return self._add("Cylinder", name, tuple((a + b) / 2), ((b - a).length, diameter, diameter), color, material,
                         rot=frame_x(b - a), **kw)

    def disc(self, name, pos, axis, diameter, thickness, color, material="SmoothPlastic", **kw):
        """Flat cylinder (a plate, a dial, a burner) whose flat faces look along `axis`."""
        n = Vector(axis).normalized() * (thickness / 2)
        return self.cyl(name, tuple(Vector(pos) - n), tuple(Vector(pos) + n), diameter, color, material, **kw)

    def beam(self, name, a, b, width, height, color, material="SmoothPlastic", up=(0, 1, 0), **kw):
        """Block from point a to point b (length along its local Z), width along local X, height along local Y."""
        a, b = Vector(a), Vector(b)
        return self._add("Block", name, tuple((a + b) / 2), (width, height, (b - a).length), color, material,
                         rot=frame_z(b - a, up), **kw)

    # ---------------------------------------------------------------- data
    def pivot(self, name, pos):
        """Authored point -> Pivot_<name> Vector3 attribute (FunBuildKit.Pivot maps it onto a placed copy)."""
        self.pivots[name] = [round(float(c), 4) for c in pos]

    def attr(self, name, value):
        self.attrs[name] = value

    def finish(self):
        self.D.bpy.context.view_layer.update() if hasattr(self.D, "bpy") else None
        mins = [min(p["cf"][i] - _half_extent(p, i) for p in self.parts) for i in range(3)]
        maxs = [max(p["cf"][i] + _half_extent(p, i) for p in self.parts) for i in range(3)]
        dupes = sorted(n for n, c in self._names.items() if c > 1)
        return {"key": self.key, "category": self.category, "parts": self.parts, "pivots": self.pivots,
                "attrs": self.attrs, "size_studs": [round(maxs[i] - mins[i], 3) for i in range(3)],
                "min": [round(v, 3) for v in mins], "max": [round(v, 3) for v in maxs],
                "part_count": len(self.parts), "duplicate_names": dupes}


def _half_extent(p, axis):
    """Half extent of a part's oriented box along world axis `axis` (0 x, 1 y, 2 z)."""
    s = p["size"]
    c = p["cf"]
    row = (c[3 + axis * 3], c[4 + axis * 3], c[5 + axis * 3])
    return 0.5 * (abs(row[0]) * s[0] + abs(row[1]) * s[1] + abs(row[2]) * s[2])
