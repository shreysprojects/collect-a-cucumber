"""Blender helpers for the base/plot prop set (defence, lighting, garden, fun).

This is `defenses/defenselib.py` plus everything the decorative props need: a lathe,
rounded-rect and arc profiles, catenary rope, helices, barbed wire, sagging fabric,
foliage clumps and a stroke font for neon signs.  Every defenselib name is re-exported,
so a build script only ever touches `D.<something>`.

Conventions (identical to the defence set):
  * 1 Blender unit = 1 Roblox stud.  Z up, ground at z = 0.
  * Every prop FACES +Y - its front, its screen, its readable side.
  * Roblox export is a pure rotation: (x, y, z)_rbx = (x, z, -y)_blender.
  * Chunky low-poly, FLAT shaded, colour carried per object as custom props
    ("rbx_hex" / "rbx_material" / "rbx_transparency").
  * An R15 avatar is ~5 studs tall, ~2 wide, ~1 deep.
"""
import bpy, bmesh, math, random, sys, importlib.util
from mathutils import Vector, Matrix, Euler

_DEFENSELIB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\defenses\defenselib.py"


def _load_defenselib():
    spec = importlib.util.spec_from_file_location("defenselib", _DEFENSELIB)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    sys.modules["defenselib"] = m
    return m


_D = _load_defenselib()

# re-export every public defenselib name (box, cyl, prism, wedge, rock, render, report...)
for _k in dir(_D):
    if not _k.startswith("_"):
        globals()[_k] = getattr(_D, _k)

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\props"
TILE = 8.0
_base_new_obj = _D.new_obj


# ---------------------------------------------------------------- palette
PALETTE = {
    # metal
    "metal_dark": "3b4350", "metal_mid": "6c7789", "metal_light": "9aa7b8",
    "steel_bright": "d5dbe4", "iron_dark": "2f3640", "iron_mid": "4d5866",
    "iron_rust": "8c5a3c", "brass": "c9a227", "copper": "b06a3b",
    "gold": "e8b73a", "chrome": "c3ccd8",
    # wood
    "wood_light": "c08a4e", "wood_mid": "8a5a2b", "wood_dark": "6b4423",
    "bamboo": "c8a75a", "log_bark": "5b4230", "plank_grey": "9c8f7e",
    # stone / ground
    "stone_light": "b9b3a7", "stone_mid": "8f8a80", "stone_dark": "6b675f",
    "concrete": "a3a099", "dirt": "6d5138", "sand": "d8c48c", "gravel": "7d7a72",
    # plants
    "leaf_light": "78c05a", "leaf_mid": "4f9c3e", "leaf_dark": "2f6b2c",
    "leaf_blue": "3f7f57", "grass": "5f9e42", "moss": "5f8f4a",
    "petal_yellow": "f5c032", "petal_orange": "eb8f2a", "seed_brown": "5a3d20",
    "stem_green": "4a8b34", "straw": "d9b45b", "hay": "c9a33f",
    "flower_pink": "e878a8", "flower_red": "d9443c", "flower_white": "f2efe4",
    # fabric / soft
    "cloth_red": "c0392b", "cloth_blue": "3d6fb5", "cloth_teal": "2f9e9e",
    "cloth_cream": "e8e0cc", "cloth_purple": "8b5cc7", "cloth_orange": "e8873a",
    "rubber_black": "2a2d33", "rope": "b99a63", "canvas": "cbb99a",
    # water / glass
    "water_shallow": "5fc8d8", "water_mid": "2f9ec4", "water_deep": "1d6f9c",
    "glass": "cfe8f2", "glass_tint": "9fd4e6", "foam": "eef7fb",
    # neon / light
    "neon_pink": "ff4fa3", "neon_cyan": "4dd2ff", "neon_lime": "9dff4d",
    "neon_orange": "ff8a3d", "neon_purple": "b45cff", "neon_yellow": "ffe14d",
    "neon_red": "ff4d4d", "neon_blue": "4d7cff", "neon_green": "3dffa0",
    "lamp_warm": "ffd98a", "flame_core": "ffe9a8", "flame_mid": "ff9c2e",
    "flame_tip": "e04a1f",
    # plastics / misc
    "plastic_red": "d9443c", "plastic_blue": "3f79d4", "plastic_yellow": "f2c13d",
    "plastic_green": "4caf50", "plastic_white": "f2f0ea", "plastic_black": "23262c",
    "screen_dark": "10141c", "screen_glow": "6fd0ff", "accent_orange": "ff8a3d",
    "warning_yellow": "f2c13d", "danger_red": "d9443c", "terracotta": "b8623f",
}


def C(key):
    """PALETTE lookup that fails loudly on a typo (returns a hex string)."""
    if key in PALETTE:
        return PALETTE[key]
    raise KeyError("no palette colour %r - keys: %s" % (key, ", ".join(sorted(PALETTE))))


# ---------------------------------------------------------------- objects
def new_obj(name, bm, c, hexcol, rbx_material="SmoothPlastic", transparency=0.0,
            metallic=0.0, roughness=0.55, smooth=False, emit=None):
    """defenselib.new_obj + real alpha in the viewport/render for see-through parts and
    an optional emission-strength override for Neon.

    `transparency` is the ROBLOX convention: 0 = solid, 1 = invisible."""
    obj = _base_new_obj(name, bm, c, hexcol, rbx_material=rbx_material,
                        transparency=transparency, metallic=metallic,
                        roughness=roughness, smooth=smooth)
    mat = obj.data.materials[0]
    alpha = max(0.0, min(1.0, 1.0 - float(transparency)))
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
    if bsdf is not None:
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        if emit is not None and "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = float(emit)
            if "Emission Color" in bsdf.inputs:
                r, g, b = _D.hex_to_rgb(hexcol)
                bsdf.inputs["Emission Color"].default_value = (r, g, b, 1)
        if "IOR" in bsdf.inputs and transparency > 0.05:
            bsdf.inputs["IOR"].default_value = 1.05      # keep glass from lensing
    mat.diffuse_color = (mat.diffuse_color[0], mat.diffuse_color[1], mat.diffuse_color[2], alpha)
    if transparency > 0.001:
        # Blender 4.2+ (EEVEE Next) renamed blend_method -> surface_render_method
        try:
            mat.surface_render_method = 'BLENDED'
        except (AttributeError, TypeError):
            pass
        try:
            mat.blend_method = 'BLEND'
            mat.show_transparent_back = False
        except (AttributeError, TypeError):
            pass
        try:
            mat.use_transparent_shadow = True
        except (AttributeError, TypeError):
            pass
    return obj


# ---------------------------------------------------------------- extra transforms
def translate(bm, verts, offset):
    """Move verts a primitive returned by (dx, dy, dz)."""
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(offset)), verts=verts)
    return verts


def place(loc=(0, 0, 0), rot=None, scale=1.0):
    """4x4 = translate @ rotate @ scale, for the `rot=`/`matrix=` argument of a primitive."""
    s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
    return (Matrix.Translation(Vector(loc)) @ (rot or Matrix.Identity(4))
            @ Matrix.Diagonal((s[0], s[1], s[2], 1)))


def mirror_x(bm, verts):
    """Duplicate `verts`' geometry mirrored across x = 0.  Returns the new verts."""
    geom = bmesh.ops.duplicate(bm, geom=[v for v in verts]
                               + [e for e in bm.edges if all(x in set(verts) for x in e.verts)]
                               + [f for f in bm.faces if all(x in set(verts) for x in f.verts)])
    new = [g for g in geom["geom"] if isinstance(g, bmesh.types.BMVert)]
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((-1, 1, 1, 1)), verts=new)
    bmesh.ops.reverse_faces(bm, faces=[g for g in geom["geom"] if isinstance(g, bmesh.types.BMFace)])
    return new


# ---------------------------------------------------------------- 2-D profiles
def arc_pts(center, radius, a0, a1, n=8, ry=None):
    """`n` points along an arc (degrees, CCW).  `ry` makes it elliptical."""
    cx, cy = center
    ry = radius if ry is None else ry
    a0, a1 = math.radians(a0), math.radians(a1)
    return [(cx + math.cos(a0 + (a1 - a0) * i / (n - 1.0)) * radius,
             cy + math.sin(a0 + (a1 - a0) * i / (n - 1.0)) * ry) for i in range(n)]


def rounded_rect_pts(w, h, r, segs=3, center=(0, 0)):
    """Rounded-rectangle profile, w x h, corner radius r.  Feed to prism().
    `segs` is points per corner - 2 is a chamfer, 3-4 reads as a radius."""
    cx, cy = center
    r = max(0.0, min(r, 0.499 * min(w, h)))
    hw, hh = w / 2.0 - r, h / 2.0 - r
    out = []
    for (ox, oy, a0) in ((hw, hh, 0), (-hw, hh, 90), (-hw, -hh, 180), (hw, -hh, 270)):
        if r <= 1e-6:
            out.append((cx + ox, cy + oy))
        else:
            out += [(cx + p[0], cy + p[1]) for p in arc_pts((ox, oy), r, a0, a0 + 90, max(2, segs))]
    return out


def star_pts(n, r_out, r_in, phase=0.0, center=(0, 0)):
    """2n-point star profile."""
    out = []
    for i in range(2 * n):
        a = phase + math.pi * i / n
        r = r_out if i % 2 == 0 else r_in
        out.append((center[0] + math.cos(a) * r, center[1] + math.sin(a) * r))
    return out


def teardrop_pts(w, h, n=10, center=(0, 0)):
    """Leaf / petal / flame outline: round at the base, pointed at +Y."""
    out = []
    for i in range(n):
        t = math.pi * i / (n - 1.0)
        x = math.sin(t) * (w / 2.0) * (1.0 - 0.85 * (i / (n - 1.0)) ** 2)
        y = -h / 2.0 + h * (i / (n - 1.0))
        out.append((center[0] + x, center[1] + y))
    for i in range(n - 2, 0, -1):
        t = math.pi * i / (n - 1.0)
        x = math.sin(t) * (w / 2.0) * (1.0 - 0.85 * (i / (n - 1.0)) ** 2)
        y = -h / 2.0 + h * (i / (n - 1.0))
        out.append((center[0] - x, center[1] + y))
    return out


# ---------------------------------------------------------------- 3-D paths
def catenary_pts(a, b, sag, n=10):
    """`n` points from a to b hanging with `sag` studs of droop at the middle."""
    a, b = Vector(a), Vector(b)
    out = []
    for i in range(n):
        t = i / (n - 1.0)
        p = a.lerp(b, t)
        p.z -= sag * 4.0 * t * (1.0 - t)      # parabola: 0 at both ends, `sag` mid
        out.append(tuple(p))
    return out


def helix_pts(base, top, radius, turns=3.0, n=24, phase=0.0, radius2=None):
    """Points on a helix from `base` to `top` (both (x, y, z)); radius may taper."""
    a, b = Vector(base), Vector(top)
    r2 = radius if radius2 is None else radius2
    out = []
    for i in range(n):
        t = i / (n - 1.0)
        c = a.lerp(b, t)
        ang = phase + 2 * math.pi * turns * t
        r = radius + (r2 - radius) * t
        out.append((c.x + math.cos(ang) * r, c.y + math.sin(ang) * r, c.z))
    return out


def rope(bm, a, b, sag=0.5, radius=0.06, n=10, segs=5):
    """Hanging rope / cable / wire between two points."""
    pts = catenary_pts(a, b, sag, n)
    return tube(bm, pts, [radius] * len(pts), segs=segs)


def coil(bm, base, top, radius, turns=3.0, wire_r=0.05, n=28, segs=5, phase=0.0):
    """A helical wire (spring, barbed-wire roll, slide rail)."""
    pts = helix_pts(base, top, radius, turns=turns, n=n, phase=phase)
    return tube(bm, pts, [wire_r] * len(pts), segs=segs)


def barbed_wire(bm, points, wire_r=0.05, segs=4, barb_every=2, barb_len=0.22, seed=1):
    """A wire along `points` with little 4-armed barbs clamped on at intervals."""
    out = list(tube(bm, points, [wire_r] * len(points), segs=segs))
    rng = random.Random(seed)
    for i in range(1, len(points) - 1, max(1, int(barb_every))):
        p = Vector(points[i])
        d = (Vector(points[i + 1]) - Vector(points[i - 1]))
        d = d.normalized() if d.length > 1e-6 else Vector((1, 0, 0))
        u = d.cross(Vector((0, 0, 1)))
        u = u.normalized() if u.length > 1e-6 else Vector((1, 0, 0))
        v = d.cross(u).normalized()
        ph = rng.uniform(0, math.pi)
        for k in range(4):
            a = ph + math.pi * k / 2.0
            arm = (u * math.cos(a) + v * math.sin(a)) * barb_len + d * (0.35 * barb_len * (1 if k % 2 else -1))
            out += spike(bm, tuple(p - arm * 0.15), tuple(p + arm), wire_r * 1.5, segs=3)
    return out


# ---------------------------------------------------------------- solids
def lathe(bm, profile, segs=12, matrix=None, cap=True, phase=0.0):
    """Revolve a 2-D (radius, z) profile about the Z axis.

    A profile point with radius 0 becomes a pole (cone tip / bowl bottom).  Ends with a
    non-zero radius are capped when `cap`.  The workhorse for pots, bowls, lanterns,
    watering cans, fountain tiers, bollards, drums."""
    pts = [(max(0.0, float(r)), float(z)) for r, z in profile]
    rings, poles, out = [], [], []
    for (r, z) in pts:
        if r <= 1e-6:
            v = bm.verts.new((0.0, 0.0, z))
            rings.append(None)
            poles.append(v)
            out.append(v)
        else:
            ring = []
            for i in range(segs):
                a = phase + 2 * math.pi * i / segs
                ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
            rings.append(ring)
            poles.append(None)
            out += ring
    for i in range(len(pts) - 1):
        lo, hi = rings[i], rings[i + 1]
        plo, phi = poles[i], poles[i + 1]
        if lo and hi:
            for j in range(segs):
                k = (j + 1) % segs
                if abs(pts[i][1] - pts[i + 1][1]) < 1e-9 and abs(pts[i][0] - pts[i + 1][0]) < 1e-9:
                    continue
                bm.faces.new((lo[j], lo[k], hi[k], hi[j]))
        elif lo and phi is not None:
            for j in range(segs):
                bm.faces.new((lo[j], lo[(j + 1) % segs], phi))
        elif hi and plo is not None:
            for j in range(segs):
                bm.faces.new((plo, hi[(j + 1) % segs], hi[j]))
    if cap:
        if rings[0]:
            bm.faces.new(tuple(reversed(rings[0])))
        if rings[-1]:
            bm.faces.new(tuple(rings[-1]))
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=out)
    return out


def ngon_face(bm, pts2d, z, matrix=None, flip=False):
    """A single flat n-gon face at height z - the cheapest possible water/glass surface."""
    vs = [bm.verts.new((p[0], p[1], z)) for p in pts2d]
    bm.faces.new(tuple(reversed(vs)) if flip else tuple(vs))
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


def sag_sheet(bm, lo, hi, sag=0.35, nx=5, ny=5, thickness=0.08, matrix=None):
    """A rectangular sheet pinned at its rim and drooping in the middle: trampoline mat,
    hammock, bean-bag top, sagging canvas.  `lo`/`hi` are (x, y, z) rim corners."""
    lo, hi = Vector(lo), Vector(hi)
    top, bot = [], []
    for j in range(ny + 1):
        vt, vb = [], []
        for i in range(nx + 1):
            u, w = i / float(nx), j / float(ny)
            x = lo.x + (hi.x - lo.x) * u
            y = lo.y + (hi.y - lo.y) * w
            z = lo.z + (hi.z - lo.z) * w
            d = sag * (1.0 - (2 * u - 1) ** 2) * (1.0 - (2 * w - 1) ** 2)
            vt.append(bm.verts.new((x, y, z - d)))
            vb.append(bm.verts.new((x, y, z - d - thickness)))
        top.append(vt)
        bot.append(vb)
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((top[j][i], top[j][i + 1], top[j + 1][i + 1], top[j + 1][i]))
            bm.faces.new((bot[j][i + 1], bot[j][i], bot[j + 1][i], bot[j + 1][i + 1]))
    for i in range(nx):                                  # rim skirt
        bm.faces.new((top[0][i + 1], top[0][i], bot[0][i], bot[0][i + 1]))
        bm.faces.new((top[ny][i], top[ny][i + 1], bot[ny][i + 1], bot[ny][i]))
    for j in range(ny):
        bm.faces.new((top[j][0], top[j + 1][0], bot[j + 1][0], bot[j][0]))
        bm.faces.new((top[j + 1][nx], top[j][nx], bot[j][nx], bot[j + 1][nx]))
    out = [v for row in top for v in row] + [v for row in bot for v in row]
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=out)
    return out


def foliage(bm, loc, radius, seed=1, blobs=4, spread=0.55, jitter=0.26, subdiv=1,
            scale=(1, 1, 1), flatten=1.0):
    """A clump of jittered ico-blobs - a bush, a tree crown, a hedge lump."""
    rng = random.Random(seed)
    out = []
    for k in range(blobs):
        rr = radius * rng.uniform(0.55, 1.0) if k else radius
        off = (0, 0, 0) if k == 0 else (rng.uniform(-1, 1) * radius * spread,
                                        rng.uniform(-1, 1) * radius * spread,
                                        rng.uniform(-0.5, 1.0) * radius * spread * flatten)
        out += rock(bm, (loc[0] + off[0], loc[1] + off[1], loc[2] + off[2]), rr,
                    seed=seed * 31 + k, jitter=jitter, subdiv=subdiv,
                    scale=(scale[0], scale[1], scale[2] * flatten))
    return out


def slat_run(bm, lo, hi, count, gap_frac=0.35, axis='x', bevel=0.03):
    """`count` evenly spaced slats filling the box lo..hi across `axis` - fence pickets,
    bench slats, crate sides, radiator grilles, vent louvres."""
    lo, hi = Vector(lo), Vector(hi)
    idx = 0 if axis == 'x' else (1 if axis == 'y' else 2)
    span = (hi[idx] - lo[idx]) / float(count)
    w = span * (1.0 - gap_frac)
    out = []
    for i in range(count):
        c = lo[idx] + span * (i + 0.5)
        a, b = list(lo), list(hi)
        a[idx], b[idx] = c - w / 2.0, c + w / 2.0
        out += beveled_box(bm, tuple(a), tuple(b), bevel=bevel)
    return out


# ---------------------------------------------------------------- stroke font (neon signs)
# Each glyph is a list of polylines in a 1.0-tall, ~1.0-wide box, origin bottom-left.
FONT = {
    " ": [],
    "A": [[(0, 0), (0, .62), (.5, 1), (1, .62), (1, 0)], [(0, .42), (1, .42)]],
    "B": [[(0, 0), (0, 1), (.68, 1), (1, .8), (.7, .56), (0, .56)],
          [(0, .56), (.78, .56), (1, .3), (.7, 0), (0, 0)]],
    "C": [[(1, .84), (.7, 1), (.3, 1), (0, .74), (0, .26), (.3, 0), (.7, 0), (1, .16)]],
    "D": [[(0, 0), (0, 1), (.58, 1), (1, .68), (1, .32), (.58, 0), (0, 0)]],
    "E": [[(1, 1), (0, 1), (0, 0), (1, 0)], [(0, .5), (.76, .5)]],
    "F": [[(1, 1), (0, 1), (0, 0)], [(0, .52), (.76, .52)]],
    "G": [[(1, .84), (.7, 1), (.3, 1), (0, .74), (0, .26), (.3, 0), (.7, 0), (1, .2), (1, .46), (.54, .46)]],
    "H": [[(0, 1), (0, 0)], [(1, 1), (1, 0)], [(0, .5), (1, .5)]],
    "I": [[(.5, 1), (.5, 0)], [(.14, 1), (.86, 1)], [(.14, 0), (.86, 0)]],
    "J": [[(.82, 1), (.82, .26), (.52, 0), (.22, 0), (0, .2)]],
    "K": [[(0, 1), (0, 0)], [(1, 1), (.04, .48)], [(.16, .56), (1, 0)]],
    "L": [[(0, 1), (0, 0), (1, 0)]],
    "M": [[(0, 0), (0, 1), (.5, .48), (1, 1), (1, 0)]],
    "N": [[(0, 0), (0, 1), (1, 0), (1, 1)]],
    "O": [[(0, .26), (.3, 0), (.7, 0), (1, .26), (1, .74), (.7, 1), (.3, 1), (0, .74), (0, .26)]],
    "P": [[(0, 0), (0, 1), (.7, 1), (1, .8), (.7, .5), (0, .5)]],
    "Q": [[(0, .26), (.3, 0), (.7, 0), (1, .26), (1, .74), (.7, 1), (.3, 1), (0, .74), (0, .26)],
          [(.62, .26), (1, -.08)]],
    "R": [[(0, 0), (0, 1), (.7, 1), (1, .8), (.7, .5), (0, .5)], [(.48, .5), (1, 0)]],
    "S": [[(1, .84), (.7, 1), (.24, 1), (0, .8), (.26, .55), (.76, .5), (1, .26), (.7, 0), (.24, 0), (0, .16)]],
    "T": [[(0, 1), (1, 1)], [(.5, 1), (.5, 0)]],
    "U": [[(0, 1), (0, .26), (.3, 0), (.7, 0), (1, .26), (1, 1)]],
    "V": [[(0, 1), (.5, 0), (1, 1)]],
    "W": [[(0, 1), (.24, 0), (.5, .58), (.76, 0), (1, 1)]],
    "X": [[(0, 1), (1, 0)], [(0, 0), (1, 1)]],
    "Y": [[(0, 1), (.5, .5), (1, 1)], [(.5, .5), (.5, 0)]],
    "Z": [[(0, 1), (1, 1), (0, 0), (1, 0)]],
    "0": [[(0, .26), (.3, 0), (.7, 0), (1, .26), (1, .74), (.7, 1), (.3, 1), (0, .74), (0, .26)],
          [(.18, .26), (.82, .74)]],
    "1": [[(.16, .78), (.5, 1), (.5, 0)], [(.14, 0), (.86, 0)]],
    "2": [[(0, .78), (.26, 1), (.7, 1), (1, .74), (0, 0), (1, 0)]],
    "3": [[(0, 1), (1, 1), (.4, .56)], [(.4, .56), (.86, .5), (1, .26), (.7, 0), (.24, 0), (0, .16)]],
    "4": [[(.74, 0), (.74, 1), (0, .34), (1, .34)]],
    "5": [[(1, 1), (.2, 1), (.1, .56), (.6, .6), (1, .4), (.86, .06), (.34, 0), (0, .16)]],
    "6": [[(.9, .9), (.5, 1), (.14, .74), (0, .3), (.3, 0), (.7, 0), (1, .26), (.74, .55), (.3, .55), (.05, .36)]],
    "7": [[(0, 1), (1, 1), (.4, 0)]],
    "8": [[(.3, .55), (0, .76), (.26, 1), (.74, 1), (1, .76), (.7, .55), (.3, .55),
           (0, .3), (.26, 0), (.74, 0), (1, .3), (.7, .55)]],
    "9": [[(.1, .1), (.5, 0), (.86, .26), (1, .7), (.7, 1), (.3, 1), (0, .74), (.26, .45), (.7, .45), (.95, .64)]],
    "!": [[(.5, 1), (.5, .3)], [(.5, .14), (.5, .02)]],
    "?": [[(0, .78), (.26, 1), (.72, 1), (1, .78), (.56, .48), (.5, .3)], [(.5, .14), (.5, .02)]],
    ".": [[(.5, .1), (.5, 0)]],
    ",": [[(.55, .12), (.35, -.12)]],
    "-": [[(.12, .5), (.88, .5)]],
    "+": [[(.5, .82), (.5, .18)], [(.18, .5), (.82, .5)]],
    "'": [[(.5, 1), (.42, .74)]],
    "$": [[(.5, 1.06), (.5, -.06)],
          [(1, .84), (.7, .96), (.24, .96), (0, .78), (.26, .55), (.76, .5), (1, .26), (.7, .04), (.24, .04), (0, .16)]],
    "%": [[(0, 0), (1, 1)], [(0, .78), (.22, 1), (.44, .78), (.22, .56), (0, .78)],
          [(.56, .22), (.78, .44), (1, .22), (.78, 0), (.56, .22)]],
    "&": [[(1, 0), (.2, .74), (.36, 1), (.62, .84), (0, .28), (.24, 0), (.6, .1), (1, .5)]],
    "*": [[(.5, .86), (.5, .14)], [(.18, .32), (.82, .68)], [(.18, .68), (.82, .32)]],
    "/": [[(.1, 0), (.9, 1)]],
    ":": [[(.5, .72), (.5, .6)], [(.5, .26), (.5, .14)]],
}
FONT_GAP = 0.30      # gap between glyph boxes, in glyph widths
FONT_W = 1.0         # glyph box width, in glyph heights


def text_width(text, height=1.0, gap=FONT_GAP, width=FONT_W):
    n = len(text)
    return height * (n * width + max(0, n - 1) * gap) if n else 0.0


def stroke_text(bm, text, origin=(0, 0, 0), height=1.0, radius=0.06, segs=5,
                plane='XZ', gap=FONT_GAP, width=FONT_W, center=True, matrix=None,
                flip=False):
    """Loft a neon tube along a stroke font, laid out so it READS THE RIGHT WAY ROUND to
    a player standing in front of the prop (on the +Y side).

    Props face +Y and the camera looks back along -Y, so screen-right is -X: the layout
    therefore advances along -X.  `plane='XZ'` writes on a wall (letters stand up in z);
    `plane='XY'` writes flat on the floor (letters run away from the viewer, -y is up).
    `flip=True` mirrors it for the BACK face of a double-sided sign.
    Returns the new verts; size the backing panel with `text_width()`."""
    total = text_width(text, height, gap, width)
    s = -1.0 if flip else 1.0
    x0 = origin[0] + s * (total / 2.0 if center else 0.0)
    out = []
    for ch in text.upper():
        glyph = FONT.get(ch, FONT[" "])
        for poly in glyph:
            pts = []
            for (gx, gy) in poly:
                px = x0 - s * gx * width * height
                py = gy * height
                if plane == 'XZ':
                    pts.append((px, origin[1], origin[2] + py))
                else:
                    pts.append((px, origin[1] - s * py, origin[2]))
            if len(pts) >= 2:
                out += tube(bm, pts, [radius] * len(pts), segs=segs)
        x0 -= s * (width + gap) * height
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=out)
    return out


# ---------------------------------------------------------------- stage / reporting
def build_stage(size=26.0, ref_at=(-6.5, 5.0, 0.0)):
    return _D.build_stage(size=size, ref_at=ref_at)


def report(coll_name):
    return _D.report(coll_name)
