"""itemlib.py -- Blender helpers for the New Map drop items (potions / pearls / seeds / tokens), 2026-09-23.

Every item is built from Roblox-representable PRIMITIVES ONLY - Ball, Block, Cylinder - so one
build script gives two things at once:
  (a) real Blender geometry in a collection named after the item Key (renders, items.blend, and
      fbx/<Key>.fbx for a later upload as a mesh asset when an Open Cloud key is at hand), and
  (b) fbx/<Key>.parts.json: one record per primitive (shape, name, colour, material, transparency,
      local size and the pure-rotation 4x4 in Blender world space), which the Studio installer
      (install_items.lua) turns into Parts of the same shape, size, colour and pose. That is the
      route that needs NO upload, so the items ship today.

Conventions = defenses/defenselib.py: 1 unit = 1 stud, Z up, the item stands on z = 0 with its
front toward +Y; Roblox = (x, z, -y). Cylinders are recorded with their AXIS along local X
(Roblox Cylinder parts turn about X), balls may be scaled per axis (Roblox Ball parts with a
non-uniform Size render as ellipsoids), blocks are plain boxes.

Usage in a build script:
    it = Item(D, "SpeedPotion")
    it.ball("Body", (0, 0, 0.62), 0.62, "9fe3ff", "Glass", transparency=0.35)
    it.cyl("Neck", (0, 0, 1.15), (0, 0, 1.55), 0.20, "a8e6ff", "Glass", transparency=0.3)
    it.block("Label", (0, 0.56, 0.58), (0.50, 0.12, 0.30), "f4f4f4")
    it.finish()        # -> {"parts": [...], "size": [...], "min_z": ...}
"""
import json
import math
import os
import bmesh
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.abspath(__file__))
FBX_DIR = os.path.join(ROOT, "fbx")
RENDER_DIR = os.path.join(ROOT, "renders")

_RY90 = Matrix.Rotation(math.radians(90), 4, 'Y')  # local Z -> local X (cylinder axis convention)


def _rows(m):
    return [[round(m[i][j], 5) for j in range(4)] for i in range(4)]


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Degrees -> pure 4x4 rotation, applied X then Y then Z (Blender 'XYZ' Euler)."""
    from mathutils import Euler
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_matrix().to_4x4()


def aim_x(direction):
    """Pure rotation taking local +X onto `direction`."""
    d = Vector(direction)
    if d.length < 1e-9:
        return Matrix.Identity(4)
    return Vector((1, 0, 0)).rotation_difference(d.normalized()).to_matrix().to_4x4()


class Item:
    def __init__(self, D, key):
        self.D = D
        self.key = key
        self.coll = D.coll(key)
        D.clear_collection(key)
        self.parts = []

    # ---------------------------------------------------------------- shared
    def _finish_obj(self, name, bm, hexcol, material, transparency, smooth):
        obj = self.D.new_obj(name, bm, self.coll, hexcol, rbx_material=material,
                             transparency=transparency, smooth=smooth)
        # see-through glass / neon in the render too (defenselib.material only sets the colour)
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
        return obj

    def _record(self, shape, name, pos, rotation, size, hexcol, material, transparency):
        m = Matrix.Translation(Vector(pos)) @ (rotation or Matrix.Identity(4))
        self.parts.append({
            "shape": shape, "name": name, "hex": hexcol.lstrip("#"), "material": material,
            "transparency": float(transparency), "size": [round(float(v), 4) for v in size],
            "matrix": _rows(m),
        })

    # ---------------------------------------------------------------- primitives
    def ball(self, name, center, radius, hexcol, material="SmoothPlastic", transparency=0.0,
             scale=(1, 1, 1), rotation=None, segs=16, rings=10):
        """Sphere / ellipsoid: `scale` stretches the radius per LOCAL axis, `rotation` turns it."""
        bm = bmesh.new()
        m = Matrix.Translation(Vector(center)) @ (rotation or Matrix.Identity(4))
        s = (radius * scale[0], radius * scale[1], radius * scale[2])
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0,
                                  matrix=m @ Matrix.Diagonal((s[0], s[1], s[2], 1)))
        obj = self._finish_obj(name, bm, hexcol, material, transparency, smooth=True)
        self._record("Ball", name, center, rotation, (2 * s[0], 2 * s[1], 2 * s[2]), hexcol, material, transparency)
        return obj

    def block(self, name, center, size, hexcol, material="SmoothPlastic", transparency=0.0, rotation=None):
        bm = bmesh.new()
        m = Matrix.Translation(Vector(center)) @ (rotation or Matrix.Identity(4))
        bmesh.ops.create_cube(bm, size=1.0, matrix=m @ Matrix.Diagonal((size[0], size[1], size[2], 1)))
        obj = self._finish_obj(name, bm, hexcol, material, transparency, smooth=False)
        self._record("Block", name, center, rotation, size, hexcol, material, transparency)
        return obj

    def cyl(self, name, a, b, radius, hexcol, material="SmoothPlastic", transparency=0.0, segs=20):
        """Cylinder from point a to point b (its axis is local X in the record)."""
        a, b = Vector(a), Vector(b)
        d = b - a
        length = d.length
        rotation = aim_x(d)
        mid = (a + b) / 2
        bm = bmesh.new()
        m = Matrix.Translation(mid) @ rotation @ _RY90
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=radius,
                              radius2=radius, depth=length, matrix=m)
        obj = self._finish_obj(name, bm, hexcol, material, transparency, smooth=True)
        self._record("Cylinder", name, tuple(mid), rotation, (length, 2 * radius, 2 * radius), hexcol, material, transparency)
        return obj

    def disc(self, name, center, normal, radius, thickness, hexcol, material="SmoothPlastic", transparency=0.0, segs=24):
        """Thin cylinder whose axis is `normal` (a halo ring, a coin face)."""
        n = Vector(normal).normalized() * (thickness / 2)
        return self.cyl(name, Vector(center) - n, Vector(center) + n, radius, hexcol, material, transparency, segs)

    # ---------------------------------------------------------------- output
    def finish(self):
        self.D.bpy.context.view_layer.update()
        mins, maxs = self.D.bounds(self.key)
        size = [round(v, 3) for v in (maxs - mins)]
        out = {"key": self.key, "parts": self.parts, "size_studs": size, "min_z": round(mins.z, 3),
               "tris": sum(len(o.data.polygons) for o in self.coll.objects if o.type == 'MESH')}
        return out


def write_parts(info):
    os.makedirs(FBX_DIR, exist_ok=True)
    path = os.path.join(FBX_DIR, info["key"] + ".parts.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=1)
    return path
