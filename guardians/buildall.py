"""Orchestrator for the ten biome guardians: (re)load guardianlib + every build_*.py,
build each model, report, pose it, render, export FBX, dump the manifest.

Run it from a blender-mcp session:

    exec(open(r"C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\guardians\\buildall.py").read())
    print(summary(build_all()))        # build everything
    render_each(); render_states()     # hero + asleep/awake per guardian
    manifest_json(); export_all(); save()

Everything reloads from disk on every call, so editing a build script and re-running
picks the change up with no Blender restart.  `build_all("Strawman")` and
`build_all(["Strawman", "Pinch"])` work; a guardian name pulls in its seat and extras.

NOTE: each execute_blender_code call gets a FRESH namespace - re-exec this file at the
top of every call or none of these helpers exist.
"""
import bpy, sys, os, math, json, importlib.util, traceback

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\guardians"
RENDERS = os.path.join(ROOT, "renders")
os.makedirs(RENDERS, exist_ok=True)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

# guardian -> (build file, [extra collections built by the same file])
# Every guardian's script builds its own collection plus "<Name>_Seat" (and, for two of
# them, "<Name>_Extra"), because the seat is authored against the sitting pose.
MODULES = [
    ("build_strawman.py",  "Strawman",  ["Strawman_Seat", "Strawman_Extra"]),
    ("build_dune.py",      "Dune",      ["Dune_Seat"]),
    ("build_kabuto.py",    "Kabuto",    ["Kabuto_Seat"]),
    ("build_brisket.py",   "Brisket",   ["Brisket_Seat"]),
    ("build_frostbite.py", "Frostbite", ["Frostbite_Seat"]),
    ("build_pinch.py",     "Pinch",     ["Pinch_Seat"]),
    ("build_ember.py",     "Ember",     ["Ember_Seat"]),
    ("build_orbit.py",     "Orbit",     ["Orbit_Seat"]),
    ("build_tick.py",      "Tick",      ["Tick_Seat"]),
    ("build_scan.py",      "Scan",      ["Scan_Seat"]),
]
NAMES = [m[1] for m in MODULES]
EXTRAS = {m[1]: m[2] for m in MODULES}
FILE_OF = {m[1]: m[0] for m in MODULES}

# hero camera per guardian: (yaw, pitch, margin).  yaw 0 is dead-on its +Y front;
# increasing yaw orbits to the guardian's right.  +X is screen LEFT.
VIEWS = {
    "Strawman":  (24, 10, 1.10),
    "Dune":      (30, 12, 1.10),
    "Kabuto":    (22, 10, 1.10),
    "Brisket":   (28, 12, 1.10),
    "Frostbite": (22, 10, 1.10),
    "Pinch":     (26, 16, 1.10),
    "Ember":     (24, 10, 1.10),
    "Orbit":     (20, 12, 1.10),
    "Tick":      (24, 10, 1.10),
    "Scan":      (24, 12, 1.10),
}

_MODS = {}          # guardian -> the loaded build module (POSES live there)


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sys.modules[name] = mod
    return mod


def lib():
    return _load(os.path.join(ROOT, "guardianlib.py"), "guardianlib")


def _want(only):
    if only is None:
        return None
    if isinstance(only, str):
        only = [only]
    return set(only)


def built(name):
    c = bpy.data.collections.get(name)
    return bool(c and [o for o in c.objects if o.type == 'MESH'])


def colls_of(g):
    return [g] + [e for e in EXTRAS.get(g, []) if built(e)]


def build_all(only=None, quiet=True):
    """Build every guardian (or a name / list of names).  Returns a report each, or the
    traceback string for any script that blew up."""
    G = lib()
    G.build_stage()
    want = _want(only)
    out = {}
    for fname, g, extra in MODULES:
        if want and g not in want:
            continue
        path = os.path.join(ROOT, fname)
        if not os.path.exists(path):
            out[g] = "MISSING " + fname
            continue
        try:
            mod = _load(path, "build_" + g)
            _MODS[g] = mod
            mod.build(G)
            rep = G.report(g)
            rep["notes"] = getattr(mod, "NOTES", "")
            rep["poses"] = sorted(getattr(mod, "POSES", {}).keys())
            rep["rig"] = G.check_rig(g)
            rep["seats"] = {}
            for e in extra:
                if built(e):
                    r2 = G.report(e)
                    rep["seats"][e] = "%d parts %d tris %s" % (
                        r2["parts"], r2["tris"], r2["size_studs"])
            if quiet:
                rep.pop("per_part", None)
            out[g] = rep
        except Exception:
            out[g] = "ERROR\n" + traceback.format_exc()
    return out


def summary(rep, budget=(2000, 4000)):
    lines = []
    for k, v in rep.items():
        if isinstance(v, str):
            last = v.strip().splitlines()[-1][:140] if v.strip() else v
            lines.append("%-11s FAILED  %s" % (k, last))
            continue
        flag = ""
        if v["tris"] < budget[0]:
            flag = "  << UNDER %d" % budget[0]
        elif v["tris"] > budget[1]:
            flag = "  << OVER %d" % budget[1]
        if v.get("rig"):
            flag += "  RIG: " + "; ".join(v["rig"])
        seats = " ".join("%s:%s" % (n.split("_")[-1].lower(), s.split(" parts")[0])
                         for n, s in sorted(v.get("seats", {}).items()))
        lines.append("%-11s %3d parts %5d tris  %sx%sx%s  min_z %-6s %-16s%s"
                     % (k, v["parts"], v["tris"], v["size_studs"][0], v["size_studs"][1],
                        v["size_studs"][2], v["min_z"], seats, flag))
    return "\n".join(lines)


def failures(rep):
    return {k: v for k, v in rep.items() if isinstance(v, str)}


def _stage_for(G, names):
    a = None
    for n in names:
        lo, hi = G.bounds(n)
        if a is None:
            a, b = lo, hi
        else:
            a = G.Vector((min(a.x, lo.x), min(a.y, lo.y), min(a.z, lo.z)))
            b = G.Vector((max(b.x, hi.x), max(b.y, hi.y), max(b.z, hi.z)))
    G.build_stage(size=(max(18.0, (b.x - a.x) * 2.0 + 10), max(16.0, (b.y - a.y) * 1.9 + 10)),
                  ref_at=(a.x - 2.6, b.y - 0.6, 0.0))


def render_each(only=None, size=(860, 760), stage=True, with_seat=False):
    """One three-quarter hero render per guardian, in its REST pose."""
    G = lib()
    want = _want(only)
    made = []
    for g in NAMES:
        if (want and g not in want) or not built(g):
            continue
        G.rest(g)
        names = [g] + ([e for e in EXTRAS[g] if built(e) and e.endswith("_Seat")]
                       if with_seat else [])
        yaw, pitch, dist = VIEWS.get(g, (24, 12, 1.10))
        if stage:
            _stage_for(G, names)
        p = os.path.join(RENDERS, g + ".png")
        G.render(names, p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist,
                 with_stage=stage)
        made.append(p)
    G.build_stage()
    return made


def render_view(g, tag, yaw=24, pitch=12, dist=1.10, size=(860, 760), pose=None,
                with_seat=False, extra=None, **kw):
    """One arbitrary view - a back view, a detail, a posed shot."""
    G = lib()
    names = [g] + ([e for e in EXTRAS[g] if built(e)] if with_seat else [])
    if extra:
        names += [e for e in extra if built(e)]
    G.rest(g)
    if pose:
        mod = _MODS.get(g)
        poses = getattr(mod, "POSES", {}) if mod else {}
        locs = getattr(mod, "POSE_LOC", {}) if mod else {}
        G.apply_pose(g, poses.get(pose, {}), extra_loc=locs.get(pose))
    _stage_for(G, names)
    p = os.path.join(RENDERS, "%s_%s.png" % (g, tag))
    G.render(names, p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist, **kw)
    G.rest(g)
    return p


def render_states(only=None, size=(860, 760), states=("Sit", "Awake")):
    """The two states the brief demands, each on its seat: asleep and awake."""
    want = _want(only)
    made = []
    for g in NAMES:
        if (want and g not in want) or not built(g):
            continue
        yaw, pitch, dist = VIEWS.get(g, (24, 12, 1.10))
        for st in states:
            made.append(render_view(g, st, yaw=yaw, pitch=pitch, dist=dist, size=size,
                                    pose=st, with_seat=True))
    return made


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
            if o.type != 'MESH' or o.hide_render:
                continue
            n = bpy.data.objects.new("%s_i%d_%s" % (cname, len(dst.objects), o.name), o.data)
            n.matrix_world = o.matrix_world.copy()
            n.location = (n.location.x + dx, n.location.y + dy, n.location.z)
            dst.objects.link(n)
    return dst


def render_contact(names=None, path="_lineup.png", cols=5, gap=3.0, size=(2000, 1100),
                   yaw=18, pitch=12, pose=None):
    """Every guardian in one frame, packed by footprint - the coherence check."""
    G = lib()
    names = [n for n in (names or NAMES) if built(n)]
    if not names:
        return None
    for n in names:
        G.rest(n)
        if pose:
            mod = _MODS.get(n)
            G.apply_pose(n, getattr(mod, "POSES", {}).get(pose, {}) if mod else {})
    dims = {}
    for n in names:
        a, b = G.bounds(n)
        dims[n] = (b.x - a.x, b.y - a.y, (a.x + b.x) / 2.0, (a.y + b.y) / 2.0)
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
    G.build_stage(size=(W + 12, Dep + 12), ref_at=(-W / 2 - 3.0, Dep / 2 + 1.5, 0))
    p = os.path.join(RENDERS, path)
    G.render(["_Tmp"], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=1.03)
    _clear("_Tmp")
    G.build_stage()
    for n in names:
        G.rest(n)
    return p


def manifest_json(path=None):
    """Every part's Roblox appearance, pivot and rig parent, plus the poses."""
    G = lib()
    models = {}
    for g in NAMES:
        if not built(g):
            continue
        mod = _MODS.get(g)
        rep = G.report(g)
        rep.pop("per_part", None)
        spec = G.SPEC[g]
        models[g] = {
            "guardian": g, "biome": spec["biome"], "spec": spec,
            "report": rep,
            "notes": getattr(mod, "NOTES", "") if mod else "",
            "rig": G.rig_tree(g),
            "poses": getattr(mod, "POSES", {}) if mod else {},
            "pose_loc": getattr(mod, "POSE_LOC", {}) if mod else {},
            "seats": {e: {"report": G.report(e), "rig": G.rig_tree(e)}
                      for e in EXTRAS[g] if built(e)},
        }
        for e in models[g]["seats"].values():
            e["report"].pop("per_part", None)
    data = {"models": models, "total_models": len(models),
            "total_parts": sum(m["report"]["parts"] for m in models.values()),
            "total_tris": sum(m["report"]["tris"] for m in models.values()),
            "roles": G.ROLES, "sleep_look": G.SLEEP_LOOK,
            # every pivot, size and pose in this file is in BLENDER space.  The Roblox
            # installer loads the FBX, yaws it 180 degrees about Y (which the importer
            # has already applied the other way), and after that correction a Blender
            # point lands at (bx, bz, -by).  Convert every pivot with that before
            # building a Motor6D, and remember a pose's (rx, ry, rz) is in Blender axes
            # too: Blender +X -> Roblox +X, Blender +Y -> Roblox -Z, Blender +Z -> +Y.
            "space": {
                "point": "(bx, by, bz)_blender -> (bx, bz, -by)_roblox",
                "front": "+Y in Blender is -Z in Roblox, which is the model's LookVector",
                "axis": {"blender_x": "roblox_x", "blender_y": "roblox_-z",
                         "blender_z": "roblox_y"},
                "unit": "1 blender unit = 1 stud",
                "pose_units": "degrees, XYZ order, about the part's own pivot, in the "
                              "part's REST world frame, inherited by children",
            }}
    p = path or os.path.join(ROOT, "manifest.json")
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    return p


def export_all(subdir="fbx", only=None):
    """One FBX per collection (guardian, seat, extras) into guardians/fbx/."""
    G = lib()
    out = os.path.join(ROOT, subdir)
    os.makedirs(out, exist_ok=True)
    want = _want(only)
    made = []
    for g in NAMES:
        if want and g not in want:
            continue
        for cn in colls_of(g):
            if not built(cn):
                continue
            G.rest(cn) if cn == g else None
            made.append(G.export_fbx(cn, os.path.join(out, cn + ".fbx")))
    return made


def save(path=None):
    bpy.ops.wm.save_as_mainfile(filepath=path or os.path.join(ROOT, "guardians.blend"))
    return bpy.data.filepath
