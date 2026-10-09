"""Orchestrator for the cucumber set: (re)load cucumberlib + every build_*.py, build
each model, report, render the sheets, export FBX, dump the manifest.

Run it from a blender-mcp session:

    exec(open(r"C:\\Users\\shrey\\OneDrive\\Documents\\RobloxGames\\cucumbers\\buildall.py").read())
    print(summary(build_all()))      # build everything
    render_each(); render_all()      # the sheets
    manifest_json(); export_all(); save()

Everything reloads from disk on every call, so editing a build script and re-running
picks the change up with no Blender restart.  `build_all("Cucumber")`,
`build_all("volcano")` and `render_each(["Cucumber", "CucumberTree"])` all work.

NOTE: each execute_blender_code call gets a FRESH namespace - re-exec this file at the
top of every call or none of these helpers exist.
"""
import bpy, sys, os, math, importlib.util, traceback

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\cucumbers"
RENDERS = os.path.join(ROOT, "renders")
os.makedirs(RENDERS, exist_ok=True)

# (module file, collection name, archetype) - archetype drives the hero camera
MODULES = [
    # ---- grass (the base biome) -------------------------------------------
    ("build_sliced_cucumber.py",            "SlicedCucumber",            "slice"),
    ("build_sliced_cucumber_stack.py",      "SlicedCucumberStack",       "slice"),
    ("build_cucumber.py",                   "Cucumber",                  "cuke"),
    ("build_flowered_cucumber.py",          "FloweredCucumber",          "cuke"),
    ("build_vined_cucumber.py",             "VinedCucumber",             "cuke"),
    ("build_cucumber_tree.py",              "CucumberTree",              "tree"),
    # ---- desert ------------------------------------------------------------
    ("build_desert_sun_dried_slice.py",     "DesertSunDriedSlice",       "slice"),
    ("build_desert_prickly_cucumber.py",    "DesertPricklyCucumber",     "cuke"),
    ("build_desert_sun_baked_cucumber.py",  "DesertSunBakedCucumber",    "cuke"),
    ("build_desert_wrapped_cucumber.py",    "DesertWrappedCucumber",     "cuke"),
    ("build_desert_cactus_cucumber.py",     "DesertCactusCucumber",      "cuke"),
    ("build_desert_palm.py",                "DesertPalm",                "tree"),
    ("build_desert_sandstone_tree.py",      "DesertSandstoneTree",       "tree"),
    # ---- volcano -----------------------------------------------------------
    ("build_volcano_molten_slice.py",       "VolcanoMoltenSlice",        "slice"),
    ("build_volcano_charred_cucumber.py",   "VolcanoCharredCucumber",    "cuke"),
    ("build_volcano_molten_cucumber.py",    "VolcanoMoltenCucumber",     "cuke"),
    ("build_volcano_flame_cucumber.py",     "VolcanoFlameCucumber",      "cuke"),
    ("build_volcano_obsidian_tree.py",      "VolcanoObsidianTree",       "tree"),
    ("build_volcano_volcano_cucumber.py",   "VolcanoVolcanoCucumber",    "cuke"),
    ("build_volcano_magma_tree.py",         "VolcanoMagmaTree",          "tree"),
    # ---- narmek ------------------------------------------------------------
    ("build_narmek_moon_slice.py",          "NarmekMoonSlice",           "slice"),
    ("build_narmek_meteor_cucumber.py",     "NarmekMeteorCucumber",      "cuke"),
    ("build_narmek_planet_slice.py",        "NarmekPlanetSlice",         "slice"),
    ("build_narmek_astronaut_cucumber.py",  "NarmekAstronautCucumber",   "cuke"),
    ("build_narmek_neon_alien_cucumber.py", "NarmekNeonAlienCucumber",   "cuke"),
    ("build_narmek_moon_tree.py",           "NarmekMoonTree",            "tree"),
    ("build_narmek_alien_tree.py",          "NarmekAlienTree",           "tree"),
    ("build_narmek_galaxy_tree.py",         "NarmekGalaxyTree",          "tree"),
    # ---- samurai -----------------------------------------------------------
    ("build_samurai_katana_cucumber.py",    "SamuraiKatanaCucumber",     "cuke"),
    ("build_samurai_bamboo_cucumber.py",    "SamuraiBambooCucumber",     "cuke"),
    ("build_samurai_lantern_cucumber.py",   "SamuraiLanternCucumber",    "cuke"),
    ("build_samurai_bamboo_grove.py",       "SamuraiBambooGrove",        "tree"),
    ("build_samurai_torii_gate.py",         "SamuraiToriiGate",          "gate"),
    ("build_samurai_sakura_tree.py",        "SamuraiSakuraTree",         "tree"),
    ("build_samurai_sliced_cucumber.py",    "SamuraiSlicedCucumber",     "slice"),
    # ---- farm --------------------------------------------------------------
    ("build_farm_cucumber_basket.py",       "FarmCucumberBasket",        "prop"),
    ("build_farm_muddy_cucumber.py",        "FarmMuddyCucumber",         "cuke"),
    ("build_farm_crate_cucumber.py",        "FarmCrateCucumber",         "prop"),
    ("build_farm_windmill_plant.py",        "FarmWindmillPlant",         "tree"),
    ("build_farm_hay_bale.py",              "FarmHayBale",               "prop"),
    ("build_farm_cucumber_tree.py",         "FarmCucumberTree",          "tree"),
    # ---- snow --------------------------------------------------------------
    ("build_snow_frozen_slice.py",          "SnowFrozenSlice",           "slice"),
    ("build_snow_snowcap_cucumber.py",      "SnowSnowcapCucumber",       "cuke"),
    ("build_snow_snowball_slice.py",        "SnowSnowballSlice",         "slice"),
    ("build_snow_crystal_cucumber.py",      "SnowCrystalCucumber",       "cuke"),
    ("build_snow_frozen_cucumber.py",       "SnowFrozenCucumber",        "cuke"),
    ("build_snow_snow_tree.py",             "SnowSnowTree",              "tree"),
    ("build_snow_icicle_tree.py",           "SnowIcicleTree",            "tree"),
    ("build_snow_frozen_tree.py",           "SnowFrozenTree",            "tree"),
    # ---- underwater --------------------------------------------------------
    ("build_underwater_bubble_slice.py",    "UnderwaterBubbleSlice",     "slice"),
    ("build_underwater_seaweed_cucumber.py", "UnderwaterSeaweedCucumber", "cuke"),
    ("build_underwater_shell_slice.py",     "UnderwaterShellSlice",      "slice"),
    ("build_underwater_coral_cucumber.py",  "UnderwaterCoralCucumber",   "cuke"),
    ("build_underwater_pearl_cucumber.py",  "UnderwaterPearlCucumber",   "cuke"),
    ("build_underwater_kelp_tree.py",       "UnderwaterKelpTree",        "tree"),
    ("build_underwater_bubble_tree.py",     "UnderwaterBubbleTree",      "tree"),
    ("build_underwater_coral_tree.py",      "UnderwaterCoralTree",       "tree"),
    # ---- toyland (2026-09-18, CUCUMBERS-REV3.md) --------------------------------
    ("build_toyland_toy_slice.py",          "ToylandToySlice",           "slice"),
    ("build_toyland_lego_cucumber.py",      "ToylandLegoCucumber",       "cuke"),
    ("build_toyland_jack_in_the_box_cucumber.py", "ToylandJackInTheBoxCucumber", "cuke"),
    ("build_toyland_toy_rocket_cucumber.py", "ToylandToyRocketCucumber", "cuke"),
    ("build_toyland_pinwheel_plant.py",     "ToylandPinwheelPlant",      "cuke"),
    ("build_toyland_building_block_tree.py", "ToylandBuildingBlockTree", "tree"),
    ("build_toyland_toy_train_cucumber.py", "ToylandToyTrainCucumber",   "prop"),
    # ---- neon (2026-09-18, CUCUMBERS-REV3.md) -----------------------------------
    ("build_neon_neon_slice.py",            "NeonNeonSlice",             "slice"),
    ("build_neon_electro_cucumber.py",      "NeonElectroCucumber",       "cuke"),
    ("build_neon_grid_cucumber.py",         "NeonGridCucumber",          "cuke"),
    ("build_neon_hologram_cucumber.py",     "NeonHologramCucumber",      "cuke"),
    ("build_neon_palm.py",                  "NeonPalm",                  "tree"),
    ("build_neon_tree.py",                  "NeonTree",                  "tree"),
    ("build_neon_cyber_cucumber.py",        "NeonCyberCucumber",         "cuke"),
]

GROUPS = {
    "grass":      [m[1] for m in MODULES[0:6]],
    "desert":     [m[1] for m in MODULES[6:13]],
    "volcano":    [m[1] for m in MODULES[13:20]],
    "narmek":     [m[1] for m in MODULES[20:28]],
    "samurai":    [m[1] for m in MODULES[28:35]],
    "farm":       [m[1] for m in MODULES[35:41]],
    "snow":       [m[1] for m in MODULES[41:49]],
    "underwater": [m[1] for m in MODULES[49:57]],
    "toyland":    [m[1] for m in MODULES[57:64]],
    "neon":       [m[1] for m in MODULES[64:71]],
}
ARCHETYPE = {m[1]: m[2] for m in MODULES}

# hero camera per archetype: (yaw, pitch, margin).  yaw 0 = dead on the +Y front.
VIEWS = {
    "cuke":  (22, 12, 1.10),
    "slice": (24, 26, 1.10),
    "tree":  (20, 10, 1.08),
    "gate":  (16, 10, 1.08),
    "prop":  (26, 18, 1.10),
}


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    sys.modules[name] = mod
    return mod


def lib():
    return _load(os.path.join(ROOT, "cucumberlib.py"), "cucumberlib")


def _want(only):
    if only is None:
        return None
    if isinstance(only, str):
        return set(GROUPS[only]) if only in GROUPS else {only}
    out = set()
    for o in only:
        out |= set(GROUPS.get(o, [o]))
    return out


def built(name):
    c = bpy.data.collections.get(name)
    return bool(c and [o for o in c.objects if o.type == 'MESH'])


def build_all(only=None, quiet=True):
    """Build every model (or a name / list of names / a biome name).  Returns a report
    per model, or the traceback string for any script that blew up."""
    D = lib()
    D.build_stage()
    want = _want(only)
    out = {}
    for fname, cname, _arch in MODULES:
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
            if quiet:
                rep.pop("per_part", None)
            out[cname] = rep
        except Exception:
            out[cname] = "ERROR\n" + traceback.format_exc()
    return out


def summary(rep, show_ok=True):
    lines = []
    for k, v in rep.items():
        if isinstance(v, str):
            last = v.strip().splitlines()[-1][:120] if v.strip() else v
            lines.append("%-27s FAILED  %s" % (k, last))
        elif show_ok:
            lines.append("%-27s %3d parts %5d tris  %sx%sx%s  min_z %s"
                         % (k, v["parts"], v["tris"], v["size_studs"][0],
                            v["size_studs"][1], v["size_studs"][2], v["min_z"]))
    return "\n".join(lines)


def failures(rep):
    return {k: v for k, v in rep.items() if isinstance(v, str)}


def _stage_for(D, cname):
    a, b = D.bounds(cname)
    D.build_stage(size=(max(16.0, (b.x - a.x) * 2.1 + 9), max(14.0, (b.y - a.y) * 2.0 + 9)),
                  ref_at=(a.x - 2.0, b.y - 0.8, 0.0))


def render_each(only=None, size=(760, 620), stage=True):
    """One three-quarter hero render per model."""
    D = lib()
    want = _want(only)
    made = []
    for _f, cname, arch in MODULES:
        if (want and cname not in want) or not built(cname):
            continue
        yaw, pitch, dist = VIEWS.get(arch, (22, 14, 1.10))
        if stage:
            _stage_for(D, cname)
        p = os.path.join(RENDERS, cname + ".png")
        D.render([cname], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist,
                 with_stage=stage)
        made.append(p)
    D.build_stage()
    return made


def render_view(cname, tag, yaw, pitch, dist=1.10, size=(760, 620), with_stage=True, **kw):
    D = lib()
    if with_stage:
        _stage_for(D, cname)
    p = os.path.join(RENDERS, "%s_%s.png" % (cname, tag))
    D.render([cname], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=dist,
             with_stage=with_stage, **kw)
    return p


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


def render_contact(names, path, cols=None, gap=2.6, size=(1800, 1050), yaw=20, pitch=16):
    """Several models in one frame, packed by their own footprints - the coherence check."""
    D = lib()
    names = [n for n in names if built(n)]
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
    D.build_stage(size=(W + 10, Dep + 10), ref_at=(-W / 2 - 2.5, Dep / 2 + 1.2, 0))
    p = os.path.join(RENDERS, path)
    D.render(["_Tmp"], p, size=size, yaw_deg=yaw, pitch_deg=pitch, margin=1.02)
    _clear("_Tmp")
    D.build_stage()
    return p


def render_groups(only=None, size=(1800, 1000)):
    """One contact sheet per biome."""
    made = []
    for g, names in GROUPS.items():
        if only and g not in ([only] if isinstance(only, str) else only):
            continue
        p = render_contact(names, "_biome_%s.png" % g, cols=4, size=size, yaw=20, pitch=16)
        if p:
            made.append(p)
    return made


def render_all(size=(760, 620)):
    made = list(render_each(size=size))
    made += render_groups()
    return made


def manifest_json(path=None):
    """Dump every part's Roblox appearance to cucumbers/manifest.json."""
    import json
    D = lib()
    names = [c for _f, c, _a in MODULES if built(c)]
    rows = D.manifest(names)
    reps = {}
    for n in names:
        r = D.report(n)
        r.pop("per_part", None)
        r["biome"] = next((g for g, ns in GROUPS.items() if n in ns), "?")
        r["archetype"] = ARCHETYPE.get(n, "?")
        try:
            mod = sys.modules.get("build_" + n)
            r["notes"] = getattr(mod, "NOTES", "") if mod else ""
        except Exception:
            r["notes"] = ""
        reps[n] = r
    data = {"models": reps, "parts": rows, "total_models": len(names),
            "total_parts": len(rows), "total_tris": sum(r["tris"] for r in rows)}
    p = path or os.path.join(ROOT, "manifest.json")
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    return p


def export_all(subdir="fbx", only=None):
    """One FBX per model into cucumbers/fbx/."""
    D = lib()
    out = os.path.join(ROOT, subdir)
    os.makedirs(out, exist_ok=True)
    want = _want(only)
    made = []
    for _f, cname, _a in MODULES:
        if (want and cname not in want) or not built(cname):
            continue
        made.append(D.export_fbx(cname, os.path.join(out, cname + ".fbx")))
    return made


def save(path=None):
    bpy.ops.wm.save_as_mainfile(filepath=path or os.path.join(ROOT, "cucumbers.blend"))
    return bpy.data.filepath
