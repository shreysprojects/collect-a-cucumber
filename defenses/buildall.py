"""Orchestrator: (re)load defenselib + every build_*.py, build each prop, render sheets.

Run from the blender-mcp session:
    exec(open(r"C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\defenses\\buildall.py").read())
    print(build_all())
Everything reloads from disk on every call, so editing a build script and re-running picks
the change up with no Blender restart.
"""
import bpy, sys, os, math, importlib.util, traceback

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\defenses"
RENDERS = os.path.join(ROOT, "renders")
os.makedirs(RENDERS, exist_ok=True)

MODULES = [
    ("build_turret.py", "Turret"),
    ("build_wooden_wall.py", "WoodenWall"),
    ("build_stone_wall.py", "StoneWall"),
    ("build_spike_trap.py", "SpikeTrap"),
    ("build_boost_pad.py", "BoostPad"),
]

# per-prop camera: (yaw, pitch, margin). yaw 0 = dead-on the prop front (+Y face),
# increasing yaw orbits to the prop right, yaw 180 = its back.
VIEWS = {
    "Turret":     (38, 20, 1.10),
    "WoodenWall": (32, 14, 1.06),
    "StoneWall":  (32, 14, 1.06),
    "SpikeTrap":  (30, 46, 1.05),
    "BoostPad":   (26, 34, 1.05),
}


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sys.modules[name] = mod
    return mod


def lib():
    return _load(os.path.join(ROOT, "defenselib.py"), "defenselib")


def build_all(only=None):
    """Build every prop (or just `only`, a collection name or list of them). Returns a
    report dict per prop, or the traceback string if that prop's script failed."""
    D = lib()
    D.build_stage()
    want = None if only is None else ({only} if isinstance(only, str) else set(only))
    out = {}
    for fname, cname in MODULES:
        if want and cname not in want:
            continue
        path = os.path.join(ROOT, fname)
        if not os.path.exists(path):
            out[cname] = "MISSING " + fname
            continue
        try:
            mod = _load(path, "build_" + cname)
            mod.build(D)
            rep = D.report(cname)
            rep["notes"] = getattr(mod, "NOTES", "")
            for extra in ("PIVOTS", "STATES"):
                if hasattr(mod, extra):
                    rep[extra] = getattr(mod, extra)
            out[cname] = rep
        except Exception:
            out[cname] = "ERROR\n" + traceback.format_exc()
    return out


def render_each(only=None, size=(960, 700)):
    """One three-quarter render per prop, at the angle that best shows it."""
    D = lib()
    want = None if only is None else ({only} if isinstance(only, str) else set(only))
    made = []
    for _, cname in MODULES:
        if (want and cname not in want) or cname not in bpy.data.collections:
            continue
        if not [o for o in bpy.data.collections[cname].objects if o.type == 'MESH']:
            continue
        yaw, pitch, dist = VIEWS.get(cname, (35, 22, 2.1))
        p = os.path.join(RENDERS, cname + ".png")
        D.render([cname], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist)
        made.append(p)
    return made


def render_view(cname, tag, yaw, pitch, dist=1.08, size=(900, 640), with_stage=True):
    """An extra angle on one prop, written to renders/<cname>_<tag>.png."""
    D = lib()
    p = os.path.join(RENDERS, "%s_%s.png" % (cname, tag))
    D.render([cname], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist, with_stage=with_stage)
    return p


# ---------------------------------------------------------------- temporary arrangements
def _clear(name):
    c = bpy.data.collections.get(name)
    if c is None:
        return
    for o in list(c.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def _instances(cname, offsets, into):
    """Link-duplicate a collection's meshes at each (dx, dy) offset into `into`."""
    c = bpy.data.collections[cname]
    dst = bpy.data.collections.get(into) or bpy.data.collections.new(into)
    if dst.name not in [ch.name for ch in bpy.context.scene.collection.children]:
        bpy.context.scene.collection.children.link(dst)
    for dx, dy in offsets:
        for o in c.objects:
            if o.type != 'MESH':
                continue
            n = bpy.data.objects.new("%s_i%d_%s" % (cname, len(dst.objects), o.name), o.data)
            n.location = (o.location.x + dx, o.location.y + dy, o.location.z)
            n.rotation_euler = o.rotation_euler
            dst.objects.link(n)
    return dst


def render_tiling(cname, n=3, spacing=8.0, tag="tiled", yaw=18, pitch=12, size=(1200, 640)):
    """Butt N copies of a wall together to prove it tiles with no gap or overlap."""
    D = lib()
    _clear("_Tmp")
    _instances(cname, [((i - (n - 1) / 2.0) * spacing, 0.0) for i in range(n)], "_Tmp")
    p = os.path.join(RENDERS, "%s_%s.png" % (cname, tag))
    D.render(["_Tmp"], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=1.06)
    _clear("_Tmp")
    return p


def render_lineup(spacing=14.0, size=(1900, 780), yaw=22, pitch=17, dist=1.03):
    """All five props in a row — the set-coherence check."""
    D = lib()
    _clear("_Tmp")
    names = [c for _, c in MODULES if c in bpy.data.collections
             and [o for o in bpy.data.collections[c].objects if o.type == 'MESH']]
    for i, cname in enumerate(names):
        _instances(cname, [((i - (len(names) - 1) / 2.0) * spacing, 0.0)], "_Tmp")
    D.build_stage(size=(spacing * len(names) + 10, 28))   # wide floor, not a vast square
    p = os.path.join(RENDERS, "_lineup.png")
    D.render(["_Tmp"], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist, with_stage=True)
    _clear("_Tmp")
    D.build_stage()
    return p


def move_spikes(dz):
    """Slide every SpikeTrap part named Spikes* by dz (preview the retracted state)."""
    n = 0
    for o in bpy.data.collections["SpikeTrap"].objects:
        if o.name.split(".", 1)[-1].startswith("Spikes"):
            o.location.z = dz
            n += 1
    bpy.context.view_layer.update()      # matrix_world is stale until this runs
    return n


def render_all():
    """Every sheet: per-prop hero, player's-eye silhouette, the extra study angles,
    the two wall tiling proofs and the line-up."""
    made = list(render_each())
    for cname in [c for _, c in MODULES]:
        made.append(render_view(cname, "eye", yaw=12, pitch=8, dist=1.10))
    made.append(render_view("Turret", "front", yaw=0, pitch=14, dist=1.10))
    made.append(render_view("Turret", "side", yaw=90, pitch=14, dist=1.10))
    made.append(render_view("Turret", "back", yaw=180, pitch=18, dist=1.10))
    made.append(render_view("SpikeTrap", "low", yaw=20, pitch=14, dist=1.10))
    made.append(render_view("BoostPad", "low", yaw=4, pitch=11, dist=1.10))
    made.append(render_tiling("WoodenWall"))
    made.append(render_tiling("StoneWall"))
    made.append(render_lineup())
    return made
