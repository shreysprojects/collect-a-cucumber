"""Plain walls (2026-09-10, user: "remove the spikes / gaps from each wall - make them just normal
walls of whatever material, e.g. the wooden wall wouldn't have those triangles at the top; make each
wall 12 studs high").

Four 8-wide x 12-tall tiling wall segments in the proplib house style (1 unit = 1 stud, Z up, faces
+Y, tiling planes at x = +/-4 kept dead flat, min z = 0, per-part rbx_hex / rbx_material props for the
installer). They are built into the OPEN props.blend as NEW collections - PlainWoodenWall,
PlainStoneWall, PlainIronWall, PlainBarbedStoneWall - so the spiky originals are left untouched; the
Roblox installer names the models WoodenWall / StoneWall / IronWall / BarbedStoneWall again.

Run inside a blender-mcp session:
    exec(open(r"C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\plainwalls\\build_plain_walls.py").read())
    print(build_walls())      # builds all four, exports fbx/<Name>.fbx, writes manifest.json
    print(render_walls())     # one hero render each into renders/
"""
import bpy, bmesh, os, sys, json, importlib.util

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames"
HERE = os.path.join(ROOT, "plainwalls")
FBX = os.path.join(HERE, "fbx")
RENDERS = os.path.join(HERE, "renders")
H = 12.0   # BuildCatalog.LEVEL_HEIGHT: the next floor's tiles rest on the wall tops
X = 4.0    # half width: the tiling planes
NAMES = ["PlainWoodenWall", "PlainStoneWall", "PlainIronWall", "PlainBarbedStoneWall"]
ROBLOX_NAMES = {"PlainWoodenWall": "WoodenWall", "PlainStoneWall": "StoneWall",
                "PlainIronWall": "IronWall", "PlainBarbedStoneWall": "BarbedStoneWall"}


def _lib():
    spec = importlib.util.spec_from_file_location("proplib", os.path.join(ROOT, "props", "proplib.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sys.modules["proplib"] = mod
    return mod


def _coll(D, name):
    if name in bpy.data.collections:
        D.clear_collection(name)
    return D.coll(name)


def _yz(D):
    """(y, z) cross-sections extruded ALONG x: flat, un-chamfered end faces on the seams."""
    MYZ = D.rot_euler(rx=90, rz=90)
    return lambda bm, pts, x0, x1: D.prism(bm, pts, x0, x1, matrix=MYZ)


# ---------------------------------------------------------------- wooden: flat-topped planks
def wooden(D):
    name = "PlainWoodenWall"
    c = _coll(D, name)
    yz = _yz(D)
    dark, light, mid = "6b4423", "c08a4f", "a87343"
    # back slab + sill + flat cap: one dark carcass with flat ends on the seams
    bm = bmesh.new()
    D.box(bm, (-X, -0.55, 0.0), (X, -0.20, H))
    yz(bm, [(-0.60, 0.0), (0.55, 0.0), (0.55, 0.40), (-0.60, 0.40)], -X, X)
    yz(bm, [(-0.60, H - 0.30), (0.60, H - 0.30), (0.60, H), (-0.60, H)], -X, X)
    D.new_obj("Frame", bm, c, dark, rbx_material="Wood", roughness=0.7)
    # eight vertical planks on a 1.0 pitch, square tops, 0.06 grooves that show only the dark slab behind
    bm = bmesh.new()
    for i in range(8):
        x0 = -X + i * 1.0 + 0.03
        D.beveled_box(bm, (x0, -0.20, 0.40), (x0 + 0.94, 0.30, H - 0.30), bevel=0.03)
    D.new_obj("Planks", bm, c, light, rbx_material="WoodPlanks", roughness=0.65)
    # two horizontal rails across the front, full width
    bm = bmesh.new()
    for z0 in (2.4, 8.8):
        yz(bm, [(0.30, z0), (0.48, z0), (0.48, z0 + 0.6), (0.30, z0 + 0.6)], -X, X)
    D.new_obj("Rails", bm, c, mid, rbx_material="Wood", roughness=0.7)
    return name


# ---------------------------------------------------------------- stone: coursed blocks, flat top
def _stone(D, name, a, b, mortar, depth, coping=False):
    c = _coll(D, name)
    course_h, n = 2.0, 6
    bw = 8.0 / 3.0                      # three blocks per tile, half blocks on the seams every other course
    bm = bmesh.new()
    D.box(bm, (-X, -depth, 0.0), (X, depth - 0.10, H))           # the mortar core the joints show
    D.new_obj("Core", bm, c, mortar, rbx_material="Concrete", roughness=0.9)
    bmA, bmB = bmesh.new(), bmesh.new()
    seed = 1
    top = H - (0.6 if coping else 0.0)
    for ci in range(n):
        z0, z1 = ci * course_h, min((ci + 1) * course_h, top)
        if z1 - z0 < 0.3:
            continue
        offset = 0.0 if ci % 2 == 0 else bw * 0.5
        k = 0
        x0 = -X - bw + offset
        while x0 < X:
            x1 = x0 + bw
            lo, hi = max(x0, -X), min(x1, X)
            if hi - lo > 0.3:
                bm = bmA if (ci + k) % 2 == 0 else bmB
                D.stone_block(bm, (lo, -depth + 0.04, z0 + 0.04), (hi, depth, z1 - 0.04),
                              seed=seed, jitter=0.03, bevel=0.05)
                seed += 1
            k += 1
            x0 += bw
    D.new_obj("StonesA", bmA, c, a, rbx_material="Slate", roughness=0.85)
    D.new_obj("StonesB", bmB, c, b, rbx_material="Slate", roughness=0.85)
    if coping:
        bm = bmesh.new()
        D.beveled_box(bm, (-X, -depth - 0.12, top), (X, depth + 0.12, H), bevel=0.04)
        D.new_obj("Coping", bm, c, a, rbx_material="Slate", roughness=0.8)
        bm = bmesh.new()
        D.box(bm, (-X, -depth - 0.12, 0.0), (X, depth + 0.12, 0.6))
        D.new_obj("Plinth", bm, c, b, rbx_material="Slate", roughness=0.85)
    return name


def stone(D):
    return _stone(D, "PlainStoneWall", "8f8b84", "9c988f", "5f5b55", 1.0)


def barbed(D):
    return _stone(D, "PlainBarbedStoneWall", "7a7670", "86827b", "4e4a45", 1.15, coping=True)


# ---------------------------------------------------------------- iron: riveted plates, flat rail
def iron(D):
    name = "PlainIronWall"
    c = _coll(D, name)
    yz = _yz(D)
    dark, mid, bright = "2d3138", "5a6068", "b8bec8"
    bm = bmesh.new()
    D.box(bm, (-X, -0.42, 0.0), (X, -0.06, H))                                        # back web
    for s in (1, -1):                                                                   # half posts on the seams
        lo, hi = sorted((s * 3.55, s * X))
        D.box(bm, (lo, -0.42, 0.0), (hi, 0.46, H))
    yz(bm, [(-0.52, 0.0), (0.58, 0.0), (0.58, 0.34), (-0.52, 0.34)], -X, X)            # sill
    yz(bm, [(-0.44, H - 0.44), (0.52, H - 0.44), (0.52, H), (-0.44, H)], -X, X)        # flat top rail
    D.new_obj("Frame", bm, c, dark, rbx_material="Metal", metallic=0.6, roughness=0.45)
    bm = bmesh.new()
    for (z0, z1) in ((3.0, 3.6), (8.4, 9.0)):                                          # two straps
        yz(bm, [(-0.06, z0), (0.52, z0), (0.52, z1), (-0.06, z1)], -X, X)
    D.new_obj("Straps", bm, c, dark, rbx_material="Metal", metallic=0.65, roughness=0.4)
    bm = bmesh.new()
    n, gap = 5, 0.04
    pw = (7.10 - gap * (n - 1)) / n
    for i in range(n):
        x0 = -3.55 + i * (pw + gap)
        D.beveled_box(bm, (x0, -0.06, 0.34), (x0 + pw, 0.30, H - 0.44), bevel=0.05)
    D.new_obj("Plates", bm, c, mid, rbx_material="DiamondPlate", metallic=0.5, roughness=0.5)
    bm = bmesh.new()
    for (z0, z1) in ((3.0, 3.6), (8.4, 9.0)):
        zc = (z0 + z1) / 2.0
        for rx in (-3.5, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5, 3.5):
            D.cyl(bm, (rx, 0.50, zc), (rx, 0.64, zc), 0.15, segs=6, r2=0.10)
    D.new_obj("Rivets", bm, c, bright, rbx_material="Metal", metallic=0.8, roughness=0.3)
    return name


# ---------------------------------------------------------------- driver
def build_walls():
    D = _lib()
    names = [wooden(D), stone(D), iron(D), barbed(D)]
    bpy.context.view_layer.update()
    os.makedirs(FBX, exist_ok=True)
    reps = {}
    for n in names:
        rep = D.report(n)
        rep.pop("per_part", None)
        rep["roblox_name"] = ROBLOX_NAMES[n]
        reps[n] = rep
        D.export_fbx(n, os.path.join(FBX, n + ".fbx"))
    manifest = {"set": "plainwalls", "convention": "1 unit = 1 stud, Z up, faces +Y; Roblox = (x, z, -y) after the importer's 180 yaw fix",
                "roblox_names": ROBLOX_NAMES, "props": reps, "parts": D.manifest(names)}
    with open(os.path.join(HERE, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    return reps


def render_walls(size=(900, 640)):
    D = _lib()
    os.makedirs(RENDERS, exist_ok=True)
    made = []
    for n in NAMES:
        if n not in bpy.data.collections:
            continue
        p = os.path.join(RENDERS, n + ".png")
        D.render([n], p, size=size, yaw_deg=32, pitch_deg=14, margin=1.06)
        made.append(p)
    return made
