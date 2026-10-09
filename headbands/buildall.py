"""Orchestrator for the 12-tier headband set: build, report fit, render, export FBX.

    exec(open(r"C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\headbands\\buildall.py").read())
    print(build_all())
    print(render_all())
    print(export_all())
"""
import bpy, sys, os, json, math, importlib.util, traceback

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\headbands"
RENDERS = os.path.join(ROOT, "renders")
FBX = os.path.join(ROOT, "fbx")
for d in (RENDERS, FBX):
    os.makedirs(d, exist_ok=True)

MODULES = [
    ("build_sweatband.py",      "Sweatband"),
    ("build_red_bandana.py",    "RedBandana"),
    ("build_camo_band.py",      "CamoBand"),
    ("build_cucumber_band.py",  "CucumberBand"),
    ("build_straw_band.py",     "StrawBand"),
    ("build_leaf_crown.py",     "LeafCrown"),
    ("build_steel_band.py",     "SteelBand"),
    ("build_cactus_band.py",    "CactusBand"),
    ("build_frost_band.py",     "FrostBand"),
    ("build_gold_band.py",      "GoldBand"),
    ("build_lava_band.py",      "LavaBand"),
    ("build_champion_band.py",  "ChampionBand"),
]


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sys.modules[name] = mod
    return mod


def lib():
    return _load(os.path.join(ROOT, "headbandlib.py"), "headbandlib")


def build_all(only=None, head=True):
    H = lib()
    H.build_head_stage(show_head=head)
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
            mod = _load(path, "hb_" + cname)
            mod.build(H)
            rep = H.report_fit(cname)
            rep["tier"] = getattr(mod, "TIER", None)
            rep["display_name"] = getattr(mod, "DISPLAY_NAME", cname)
            rep["notes"] = getattr(mod, "NOTES", "")
            out[cname] = rep
        except Exception:
            out[cname] = "ERROR\n" + traceback.format_exc()
    return out


def problems(rep):
    """Fit violations worth fixing: anything intruding inside the head, or absurd size."""
    bad = {}
    for k, v in rep.items():
        if isinstance(v, str):
            bad[k] = v.strip().splitlines()[-1] if "ERROR" in v else v
            continue
        msgs = []
        if v.get("head_clearance") is not None and v["head_clearance"] < -0.005:
            msgs.append("INTRUDES head by %.3f (min radius %.3f, head %.2f)"
                        % (-v["head_clearance"], v["min_radius_at_band_height"], 0.60))
        w = v["size_studs"]
        if max(w[0], w[1]) > 2.6:
            msgs.append("too wide: %.2f x %.2f studs" % (w[0], w[1]))
        if v["z_range"][1] > 1.1 or v["z_range"][0] < -0.6:
            msgs.append("z out of range: %s" % (v["z_range"],))
        if msgs:
            bad[k] = "; ".join(msgs)
    return bad


def render_all(only=None, size=(620, 620), head=True):
    """Three-quarter front view of each headband on the head proxy."""
    H = lib()
    H.build_head_stage(show_head=head)
    want = None if only is None else ({only} if isinstance(only, str) else set(only))
    made = []
    for _, cname in MODULES:
        if (want and cname not in want) or cname not in bpy.data.collections:
            continue
        if not [o for o in bpy.data.collections[cname].objects if o.type == 'MESH']:
            continue
        p = os.path.join(RENDERS, cname + ".png")
        _render(H, [cname], p, size=size, yaw=26, pitch=14)
        made.append(p)
    return made


def _render(H, names, path, size, yaw, pitch, margin=1.16):
    saved = H.coll("_Head")
    show = set(names) | {"_Head"}
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = (lc.name not in show)
    H.render(names + ["_Head"], path, size=size, yaw_deg=yaw, pitch_deg=pitch,
             margin=margin, with_stage=False)
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = False
    return path


def render_sheet(path=None, cols=4, size=(560, 560)):
    """One PNG per headband plus a combined contact sheet position map (the caller can
    stitch them); Blender has no compositor-free montage, so this just renders each."""
    return render_all(size=size)


def export_all(only=None):
    """One FBX per headband, ready for the Open Cloud Assets upload as a Model."""
    H = lib()
    want = None if only is None else ({only} if isinstance(only, str) else set(only))
    out = {}
    for _, cname in MODULES:
        if (want and cname not in want) or cname not in bpy.data.collections:
            continue
        meshes = [o for o in bpy.data.collections[cname].objects if o.type == 'MESH']
        if not meshes:
            continue
        p = os.path.join(FBX, cname + ".fbx")
        try:
            H.export_fbx(cname, p)
            out[cname] = (p, os.path.getsize(p))
        except Exception:
            out[cname] = "ERROR\n" + traceback.format_exc()
    return out


def write_manifest(path=None):
    """Per-part Roblox appearance + per-headband metadata, for the Studio installer."""
    H = lib()
    path = path or os.path.join(ROOT, "manifest.json")
    entries = []
    for fname, cname in MODULES:
        if cname not in bpy.data.collections:
            continue
        mod = sys.modules.get("hb_" + cname)
        if mod is None:
            fp = os.path.join(ROOT, fname)
            if os.path.exists(fp):
                mod = _load(fp, "hb_" + cname)
        parts = []
        for o in sorted(bpy.data.collections[cname].objects, key=lambda o: o.name):
            if o.type != 'MESH':
                continue
            parts.append({
                "object": o.name,                       # "<Collection>.<Part>" - the FBX name
                "part": o.name.split(".", 1)[1] if "." in o.name else o.name,
                "hex": o.get("rbx_hex", "ffffff"),
                "material": o.get("rbx_material", "SmoothPlastic"),
                "transparency": float(o.get("rbx_transparency", 0.0)),
                "tris": len(o.data.polygons),
            })
        rep = H.report_fit(cname)
        entries.append({
            "collection": cname,
            "tier": getattr(mod, "TIER", None) if mod else None,
            "displayName": getattr(mod, "DISPLAY_NAME", cname) if mod else cname,
            "notes": getattr(mod, "NOTES", "") if mod else "",
            "tris": rep["tris"],
            "sizeStuds": rep["size_studs"],
            "zRange": rep["z_range"],
            "minRadius": rep["min_radius_at_band_height"],
            "bandZOnHead": H.BAND_Z_ON_HEAD,
            "parts": parts,
        })
    with open(path, "w") as f:
        json.dump({"bandZOnHead": H.BAND_Z_ON_HEAD, "headRadius": H.HEAD_R,
                   "headbands": entries}, f, indent=1)
    return path, len(entries)
