"""Orchestrator for the plot prop set: (re)load proplib + every build_*.py, build each
prop, report, render the sheets.

Run it from a blender-mcp session:

    exec(open(r"C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\props\\buildall.py").read())
    print(build_all())          # build every prop -> report / traceback per prop
    print(render_all())         # every render sheet

Everything reloads from disk on each call, so editing a build script and re-running picks
the change up with no Blender restart.  `build_all("Tree")` and `render_each("Tree")` do
one prop; both also take a list.
"""
import bpy, sys, os, math, importlib.util, traceback

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\props"
RENDERS = os.path.join(ROOT, "renders")
os.makedirs(RENDERS, exist_ok=True)

GROUPS = {
    "defence": ["IronWall", "BarbedStoneWall", "GlassCase", "Catapult"],
    "lighting": ["Lantern", "TikiTorch", "NeonSign"],
    "garden": ["Sunflower", "Bush", "Tree", "Scarecrow", "Wheelbarrow", "WateringCan",
               "HayBale", "Fountain", "Pond"],
    "fun": ["Trampoline", "Slide", "Seesaw", "HotTub", "DJBooth", "DanceFloor", "Hammock",
            "BeanBag", "TV", "VendingMachine", "ArcadeCabinet"],
}

MODULES = [
    ("build_iron_wall.py", "IronWall"),
    ("build_barbed_stone_wall.py", "BarbedStoneWall"),
    ("build_glass_case.py", "GlassCase"),
    ("build_catapult.py", "Catapult"),
    ("build_lantern.py", "Lantern"),
    ("build_tiki_torch.py", "TikiTorch"),
    ("build_neon_sign.py", "NeonSign"),
    ("build_sunflower.py", "Sunflower"),
    ("build_bush.py", "Bush"),
    ("build_tree.py", "Tree"),
    ("build_scarecrow.py", "Scarecrow"),
    ("build_wheelbarrow.py", "Wheelbarrow"),
    ("build_watering_can.py", "WateringCan"),
    ("build_hay_bale.py", "HayBale"),
    ("build_fountain.py", "Fountain"),
    ("build_pond.py", "Pond"),
    ("build_trampoline.py", "Trampoline"),
    ("build_slide.py", "Slide"),
    ("build_seesaw.py", "Seesaw"),
    ("build_hot_tub.py", "HotTub"),
    ("build_dj_booth.py", "DJBooth"),
    ("build_dance_floor.py", "DanceFloor"),
    ("build_hammock.py", "Hammock"),
    ("build_bean_bag.py", "BeanBag"),
    ("build_tv.py", "TV"),
    ("build_vending_machine.py", "VendingMachine"),
    ("build_arcade_cabinet.py", "ArcadeCabinet"),
]

# per-prop hero camera: (yaw, pitch, margin).  yaw 0 = dead-on the prop FRONT (+Y face),
# increasing yaw orbits to the prop's right, yaw 180 = its back.
VIEWS = {
    "IronWall":        (32, 14, 1.06),
    "BarbedStoneWall": (32, 14, 1.06),
    "GlassCase":       (30, 16, 1.08),
    "Catapult":        (40, 18, 1.06),
    "Lantern":         (26, 14, 1.06),
    "TikiTorch":       (26, 12, 1.06),
    "NeonSign":        (16, 12, 1.06),
    "Sunflower":       (24, 12, 1.06),
    "Bush":            (28, 18, 1.08),
    "Tree":            (24, 10, 1.06),
    "Scarecrow":       (28, 12, 1.08),
    "Wheelbarrow":     (38, 22, 1.10),
    "WateringCan":     (38, 20, 1.12),
    "HayBale":         (30, 20, 1.08),
    "Fountain":        (30, 22, 1.06),
    "Pond":            (26, 34, 1.04),
    "Trampoline":      (30, 24, 1.06),
    "Slide":           (42, 20, 1.06),
    "Seesaw":          (34, 18, 1.08),
    "HotTub":          (30, 26, 1.06),
    "DJBooth":         (26, 16, 1.06),
    "DanceFloor":      (24, 38, 1.04),
    "Hammock":         (34, 18, 1.08),
    "BeanBag":         (30, 24, 1.08),
    "TV":              (26, 14, 1.08),
    "VendingMachine":  (28, 12, 1.08),
    "ArcadeCabinet":   (28, 14, 1.08),
}


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sys.modules[name] = mod
    return mod


def lib():
    return _load(os.path.join(ROOT, "proplib.py"), "proplib")


def _want(only):
    if only is None:
        return None
    if isinstance(only, str):
        if only in GROUPS:
            return set(GROUPS[only])
        return {only}
    out = set()
    for o in only:
        out |= set(GROUPS.get(o, [o]))
    return out


def build_all(only=None, quiet=False):
    """Build every prop (or a name / list of names / a group name).  Returns a dict of
    report-per-prop, or the traceback string for any prop whose script blew up."""
    D = lib()
    D.build_stage()
    want = _want(only)
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
            for extra in ("PIVOTS", "STATES", "VARIANTS"):
                if hasattr(mod, extra):
                    rep[extra] = getattr(mod, extra)
            if not quiet:
                rep.pop("per_part", None)
            out[cname] = rep
        except Exception:
            out[cname] = "ERROR\n" + traceback.format_exc()
    return out


def summary(rep):
    """One compact line per prop from a build_all() result."""
    lines = []
    for k, v in rep.items():
        if isinstance(v, str):
            lines.append("%-16s FAILED  %s" % (k, v.strip().splitlines()[-1][:110]))
        else:
            lines.append("%-16s %3d parts %5d tris  %sx%sx%s  min_z %s"
                         % (k, v["parts"], v["tris"], v["size_studs"][0], v["size_studs"][1],
                            v["size_studs"][2], v["min_z"]))
    return "\n".join(lines)


def _stage_for(D, cname):
    """Put the 5-stud scale dummy just clear of the prop, so a small prop is not swallowed
    by a frame sized to fit an avatar parked 6 studs away."""
    a, b = D.bounds(cname)
    D.build_stage(size=(max(22.0, (b.x - a.x) * 2.2 + 12), max(20.0, (b.y - a.y) * 2.0 + 12)),
                  ref_at=(a.x - 2.2, b.y - 1.0, 0.0))


def render_each(only=None, size=(960, 700)):
    """One three-quarter hero render per prop, at the angle that best shows it."""
    D = lib()
    want = _want(only)
    made = []
    for _, cname in MODULES:
        if (want and cname not in want) or cname not in bpy.data.collections:
            continue
        if not [o for o in bpy.data.collections[cname].objects if o.type == 'MESH']:
            continue
        yaw, pitch, dist = VIEWS.get(cname, (32, 18, 1.08))
        _stage_for(D, cname)
        p = os.path.join(RENDERS, cname + ".png")
        D.render([cname], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist)
        made.append(p)
    D.build_stage()
    return made


def render_view(cname, tag, yaw, pitch, dist=1.08, size=(900, 640), with_stage=True, **kw):
    D = lib()
    if with_stage:
        _stage_for(D, cname)
    p = os.path.join(RENDERS, "%s_%s.png" % (cname, tag))
    D.render([cname], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist,
             with_stage=with_stage, **kw)
    return p


def render_contact(names, path, cols=None, gap=3.0, size=(1800, 1100), yaw=24, pitch=20):
    """Several props laid out in one frame - the set-coherence check.

    Rows are PACKED by each prop's own footprint rather than spaced by the widest one,
    so a 23-stud tree line-up next to a 2-stud watering can does not blow the whole
    sheet out to a grid of mostly empty floor."""
    D = lib()
    names = [n for n in names if n in bpy.data.collections
             and [o for o in bpy.data.collections[n].objects if o.type == 'MESH']]
    if not names:
        return None
    dims = {}
    for n in names:
        a, b = D.bounds(n)
        dims[n] = (b.x - a.x, b.y - a.y, (a.x + b.x) / 2.0, (a.y + b.y) / 2.0)
    cols = cols or max(1, int(round(math.sqrt(len(names)))))
    rows = [names[i:i + cols] for i in range(0, len(names), cols)]
    row_w = [sum(dims[n][0] for n in r) + gap * (len(r) - 1) for r in rows]
    row_d = [max(dims[n][1] for n in r) for r in rows]
    total_d = sum(row_d) + gap * (len(rows) - 1)
    _clear("_Tmp")
    y = total_d / 2.0
    for ri, r in enumerate(rows):
        y -= row_d[ri] / 2.0
        x = -row_w[ri] / 2.0
        for n in r:
            w, d, cx, cy = dims[n]
            x += w / 2.0
            _instances(n, [(x - cx, y - cy)], "_Tmp")
            x += w / 2.0 + gap
        y -= row_d[ri] / 2.0 + gap
    W, Dep = max(row_w), total_d
    D.build_stage(size=(W + 12, Dep + 12), ref_at=(-W / 2 - 3.0, Dep / 2 + 1.5, 0))
    p = os.path.join(RENDERS, path)
    D.render(["_Tmp"], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=1.02)
    _clear("_Tmp")
    D.build_stage()
    return p


# ---------------------------------------------------------------- temp arrangements
def _clear(name):
    c = bpy.data.collections.get(name)
    if c is None:
        return
    for o in list(c.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def _instances(cname, offsets, into):
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
            n.scale = o.scale
            dst.objects.link(n)
    return dst


def render_tiling(cname, n=3, spacing=8.0, tag="tiled", yaw=18, pitch=12, size=(1200, 640)):
    """Butt N copies of a wall together to prove it tiles with no gap or overlap."""
    D = lib()
    _clear("_Tmp")
    _instances(cname, [((i - (n - 1) / 2.0) * spacing, 0.0) for i in range(n)], "_Tmp")
    p = os.path.join(RENDERS, "%s_%s.png" % (cname, tag))
    D.render(["_Tmp"], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=1.05)
    _clear("_Tmp")
    return p


def render_all(size=(960, 700)):
    """Every sheet: a hero per prop, a player's-eye angle per prop, the wall tiling
    proofs and one contact sheet per group."""
    made = list(render_each(size=size))
    for _, cname in MODULES:
        if cname in bpy.data.collections and [o for o in bpy.data.collections[cname].objects if o.type == 'MESH']:
            made.append(render_view(cname, "eye", yaw=10, pitch=7, dist=1.10))
    for w in ("IronWall", "BarbedStoneWall"):
        if w in bpy.data.collections:
            made.append(render_tiling(w))
    for g, names in GROUPS.items():
        p = render_contact(names, "_group_%s.png" % g,
                           cols=(2 if len(names) <= 4 else 3),
                           size=(1700, 1050), yaw=24, pitch=(30 if g == "garden" else 22))
        if p:
            made.append(p)
    return made


def manifest_json(path=None):
    """Dump every part's Roblox appearance to props/manifest.json."""
    import json
    D = lib()
    names = [c for _, c in MODULES if c in bpy.data.collections
             and [o for o in bpy.data.collections[c].objects if o.type == 'MESH']]
    rows = D.manifest(names)
    reps = {n: D.report(n) for n in names}
    for n in reps:
        reps[n].pop("per_part", None)
    data = {"props": reps, "parts": rows,
            "total_parts": len(rows), "total_tris": sum(r["tris"] for r in rows)}
    p = path or os.path.join(ROOT, "manifest.json")
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    return p


def export_all(subdir="fbx", only=None):
    """One FBX per prop into props/fbx/."""
    D = lib()
    out = os.path.join(ROOT, subdir)
    os.makedirs(out, exist_ok=True)
    want = _want(only)
    made = []
    for _, cname in MODULES:
        if (want and cname not in want) or cname not in bpy.data.collections:
            continue
        if not [o for o in bpy.data.collections[cname].objects if o.type == 'MESH']:
            continue
        made.append(D.export_fbx(cname, os.path.join(out, cname + ".fbx")))
    return made


def save(path=None):
    bpy.ops.wm.save_as_mainfile(filepath=path or os.path.join(ROOT, "props.blend"))
    return bpy.data.filepath
