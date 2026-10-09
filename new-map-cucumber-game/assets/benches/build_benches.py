"""Builds the six themed bench-press tiers (Starter, Iron, Gold, Frost, Inferno, Cosmic).
Run inside Blender:  exec(open(r"...\build_benches.py").read())
Each tier = collection <Tier>_Bench (frame, pad, decor in bench space) + <Tier>_Barbell
(bar along local X at the origin; displayed at the rack through the object matrix).
Every tier keeps the same functional anchors: floor z=0, pad top z=1.3, bar at (1.5, y, 3.5)
along Y, hooks at x=1.3..1.6 -> the LieSeat, grab detection and animation work unchanged.
"""
import bpy, bmesh, json, math, os
from mathutils import Vector, Matrix

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\assets\benches"
exec(open(os.path.join(ROOT, "benchlib.py")).read())

# ---------------------------------------------------------------- tier configs
SCALE = 1.12  # every tier is built at design size then scaled about the floor origin (seat + rack move with it)
RACK_OFFSET = (1.5 * SCALE, 3.5 * SCALE)  # bar centre from the bench origin after scaling (x along the bench, z up)
TIERS = [
    dict(name="Starter", tier=1, post=0.24, pad_w=0.95, pad_t=0.22, plate_r=0.62, plate_t=0.16, plates=2, bar_r=0.05,
         plate_style="stone", feet_part="Frame",
         mats={"Frame": ("8a5a2b", "WoodPlanks"), "Pad": ("2a2a2e", "SmoothPlastic"), "Bar": ("b8bcc4", "Metal"),
               "Plates": ("8c8c88", "Slate"), "Collars": ("5a3a1c", "Wood")}),
    dict(name="Iron", tier=2, post=0.30, pad_w=1.05, pad_t=0.26, plate_r=0.70, plate_t=0.17, plates=3, bar_r=0.055,
         plate_style="rubber", feet_part="Feet",
         mats={"Frame": ("8e939c", "Metal"), "Pad": ("1f5fd6", "SmoothPlastic"), "Feet": ("232428", "SmoothPlastic"),
               "Bar": ("c4c8d0", "Metal"), "Plates": ("1b1b1e", "SmoothPlastic"), "Collars": ("9a9ea6", "Metal")}),
    dict(name="Gold", tier=3, post=0.36, pad_w=1.15, pad_t=0.30, plate_r=0.78, plate_t=0.18, plates=4, bar_r=0.06,
         plate_style="rim", feet_part="Feet",
         mats={"Frame": ("e3b526", "Metal"), "Pad": ("b8202a", "SmoothPlastic"), "Trim": ("f5d76e", "Metal"),
               "Feet": ("2a2a2e", "SmoothPlastic"), "Gems": ("f6c93c", "Metal"), "Bar": ("d7d9dd", "Metal"),
               "Plates": ("3a2a1e", "SmoothPlastic"), "Rims": ("e3b526", "Metal"), "Collars": ("e3b526", "Metal")}),
    dict(name="Frost", tier=4, post=0.42, pad_w=1.25, pad_t=0.34, plate_r=0.86, plate_t=0.20, plates=5, bar_r=0.065,
         plate_style="ice", feet_part="Frame",
         mats={"Frame": ("4fa9e6", "Ice"), "Pad": ("2f9fe0", "SmoothPlastic"), "Trim": ("f4fbff", "SmoothPlastic"),
               "Crystals": ("b6e6ff", "Ice"), "Glow": ("e6fbff", "Neon"), "Bar": ("cfd6dd", "Metal"),
               "Plates": ("8fd3fa", "Ice"), "Collars": ("2c4a60", "Metal")}),
    dict(name="Inferno", tier=5, post=0.50, pad_w=1.35, pad_t=0.38, plate_r=0.94, plate_t=0.22, plates=6, bar_r=0.07,
         plate_style="lava", feet_part="Frame",
         mats={"Frame": ("2c2c31", "Slate"), "Pad": ("c4262b", "SmoothPlastic"), "Trim": ("ff7a1a", "Neon"),
               "Lava": ("ff5a14", "Neon"), "Bowls": ("3a3a40", "Slate"), "Flames": ("ffb02e", "Neon"),
               "Bar": ("a9adb4", "Metal"), "Plates": ("35302e", "Slate"), "Glow": ("ff6a1f", "Neon"), "Collars": ("4a4a50", "Metal")}),
    dict(name="Cosmic", tier=6, post=0.58, pad_w=1.45, pad_t=0.42, plate_r=0.95, plate_t=0.30, plates=3, orb_r=1.05, bar_r=0.075,
         plate_style="orb", feet_part="Frame",
         mats={"Frame": ("2b2361", "Metal"), "Pad": ("7c3ae0", "SmoothPlastic"), "Trim": ("d9a93a", "Metal"),
               "Runes": ("8fe9ff", "Neon"), "Crystals": ("7a5cff", "Neon"), "Bar": ("b9bcc7", "Metal"),
               "Plates": ("2a1a5e", "SmoothPlastic"), "Glow": ("62e8ff", "Neon"), "Collars": ("d9a93a", "Metal")}),
]


# ---------------------------------------------------------------- generic frame + barbell
def build_frame(P, cfg):
    p, w, t, tier, r = cfg["post"], cfg["pad_w"], cfg["pad_t"], cfg["tier"], cfg["bar_r"]
    tier = cfg.get("size_tier", tier)  # tiers after Cosmic reuse its footprint (size_tier=6)
    zb = 1.3 - t                       # pad bottom
    beam_w = 0.22 + (p - 0.2)
    beam_h = 0.16 + (p - 0.2) * 0.5
    frame, pad, feet = P("Frame"), P("Pad"), P(cfg["feet_part"])
    x_tail = -1.8 - 0.05 * (tier - 1)
    box(pad, (x_tail, -w / 2, zb), (1.6, w / 2, 1.3))
    box(frame, (x_tail + 0.25, -beam_w / 2, zb - beam_h), (1.5, beam_w / 2, zb))
    fh = 0.10 + (p - 0.2) * 0.4        # foot height
    for x, fl, fx in ((-1.35, 1.2 + (w - 0.9), 0.02), (1.25, 0.6 + (w - 0.9), 0.15)):
        box(frame, (x - p / 2, -p / 2, fh - 0.01), (x + p / 2, p / 2, zb - beam_h + 0.01))
        box(feet, (x - p / 2 - fx, -fl / 2, 0), (x + p / 2 + fx, fl / 2, fh))
    yu = 1.25 + p / 2                  # uprights: inner face stays at |y| = 1.25, thickness grows outward
    xu0, xu1 = 1.6, 1.6 + p            # front face stays at x = 1.6 (bar rests at x = 1.5)
    hu = 3.9 + 0.12 * (tier - 1)
    zs = 3.5 - r                       # hook shelf top = underside of the bar
    hw = 0.12 + (p - 0.2) * 0.3
    for s in (-1, 1):
        y = s * yu
        box(frame, (xu0, y - p / 2, fh - 0.01), (xu1, y + p / 2, hu))
        box(feet, (xu0 - 0.5 - (p - 0.2) * 0.5, y - p / 2 - 0.02, 0), (xu1 + 0.5 + (p - 0.2) * 0.5, y + p / 2 + 0.02, fh))
        box(frame, (1.3, y - hw, zs - 0.1), (xu0 + 0.01, y + hw, zs))          # shelf
        box(frame, (1.3, y - hw, zs - 0.1), (1.38, y + hw, zs + 0.3))          # lip
    box(frame, (xu0, -yu, 0), (xu1, yu, 0.14 + (p - 0.2) * 0.3))               # ground crossbar
    return dict(zb=zb, yu=yu, xu0=xu0, xu1=xu1, hu=hu, fh=fh, beam_h=beam_h, x_tail=x_tail)


def build_barbell(P, cfg, g):
    r, R, T, n, tier = cfg["bar_r"], cfg["plate_r"], cfg["plate_t"], cfg["plates"], cfg["tier"]
    tier = cfg.get("size_tier", tier)
    style = cfg["plate_style"]
    xc = g["yu"] + cfg["post"] / 2 + 0.22          # collar centre, outside the upright's outer face
    x0 = xc + 0.10 + T / 2
    positions = [x0 + i * (T + 0.03) for i in range(n)]
    end = positions[-1] + T / 2
    orb_x = None
    if style == "orb":                              # Cosmic: galaxy plates, then the big orb on the end
        orb_w = cfg["orb_r"] * 0.6
        orb_x = end + 0.06 + orb_w
        end = orb_x + orb_w
    end_x = None
    if style in ("halo", "void"):                   # Celestial gold cap / Void red crystal on each end
        end_x = end + 0.12
        end = end_x + (0.10 if style == "halo" else 0.26)
    L = 2 * (end + 0.35)
    disc(P("Bar"), (0, 0, 0), r, L, normal=(1, 0, 0), segs=8)
    for s in (-1, 1):
        disc(P("Collars"), (s * xc, 0, 0), r * 2.2 + 0.05, 0.12 + (tier - 1) * 0.01, normal=(1, 0, 0), segs=10)
        if orb_x is not None:
            uvsphere(P("Plates"), (s * orb_x, 0, 0), cfg["orb_r"], segs=12, rings=6, scale=(0.6, 1, 1))
            disc(P("Glow"), (s * orb_x, 0, 0), cfg["orb_r"] + 0.04, 0.07, (1, 0, 0), segs=14)
            disc(P("Glow"), (s * orb_x, 0, 0), cfg["orb_r"] + 0.12, 0.05, (0.94, 0.0, 0.34), segs=14)
        for i, x in enumerate(positions):
            xx = s * x
            if style == "stone":
                rough_disc(P("Plates"), (xx, 0, 0), R, T, (1, 0, 0), segs=10, jitter=0.12, seed=i * 7 + s)
            elif style == "rubber":
                disc(P("Plates"), (xx, 0, 0), R, T, (1, 0, 0), segs=14)
            elif style == "rim":
                disc(P("Plates"), (xx, 0, 0), R, T, (1, 0, 0), segs=14)
                disc(P("Rims"), (xx, 0, 0), R + 0.05, T * 0.4, (1, 0, 0), segs=14)
            elif style == "ice":
                rough_disc(P("Plates"), (xx, 0, 0), R, T, (1, 0, 0), segs=8, jitter=0.16, seed=i * 5 + s)
            elif style == "lava":
                for h in (-1, 1):
                    rough_disc(P("Plates"), (xx + h * T * 0.3, 0, 0), R, T * 0.4, (1, 0, 0), segs=10, jitter=0.07, seed=i * 3 + s + h)
                disc(P("Glow"), (xx, 0, 0), R + 0.02, T * 0.22, (1, 0, 0), segs=10)
            elif style == "orb":
                disc(P("Plates"), (xx, 0, 0), R, T, (1, 0, 0), segs=14)
                disc(P("Glow"), (xx, 0, 0), R + 0.03, T * 0.25, (1, 0, 0), segs=14)
            elif style == "halo":                   # white plate, gold rim, glowing inner ring, gold hub
                disc(P("Plates"), (xx, 0, 0), R, T, (1, 0, 0), segs=10)
                disc(P("Rims"), (xx, 0, 0), R + 0.04, T * 0.35, (1, 0, 0), segs=10)
                disc(P("Glow"), (xx, 0, 0), R * 0.68, T + 0.02, (1, 0, 0), segs=10)
            elif style == "void":                   # dark plate, red glowing ring, dark hub, gold edge
                disc(P("Plates"), (xx, 0, 0), R, T, (1, 0, 0), segs=10)
                disc(P("Collars"), (xx, 0, 0), R + 0.03, T * 0.3, (1, 0, 0), segs=10)
                disc(P("Glow"), (xx, 0, 0), R * 0.74, T + 0.02, (1, 0, 0), segs=10)
        if end_x is not None:
            if style == "halo":
                disc(P("Collars"), (s * end_x, 0, 0), r * 2.6, 0.2, (1, 0, 0), segs=10)
            else:
                octahedron(P("Glow"), (s * (end_x + 0.1), 0, 0), 0.13, scale=(2.0, 1, 1))
    return L


# ---------------------------------------------------------------- themed decor
def decor_starter(P, cfg, g):
    frame = P("Frame")
    for z in (1.1, 2.4):
        box(frame, (g["xu0"], -g["yu"], z - 0.08), (g["xu1"], g["yu"], z + 0.08))


def decor_iron(P, cfg, g):
    frame, p = P("Frame"), cfg["post"]
    for s in (-1, 1):
        y = s * g["yu"]
        for x in (g["xu0"] - 0.17, g["xu1"] + 0.17):
            cube(frame, (x, y, g["fh"] + 0.12), (0.28, p * 0.8, 0.28), rot_euler(0, 45, 0))
    box(frame, (g["xu0"], -g["yu"], 2.2), (g["xu1"], g["yu"], 2.36))


def decor_gold(P, cfg, g):
    w, p, zb = cfg["pad_w"], cfg["post"], g["zb"]
    box(P("Trim"), (g["x_tail"] - 0.06, -w / 2 - 0.05, zb - 0.07), (1.66, w / 2 + 0.05, zb))
    gems = P("Gems")
    xo = g["xu0"] + p / 2
    for s in (-1, 1):
        y = s * g["yu"]
        for z in (1.5, 2.6):
            octahedron(gems, (xo, s * (g["yu"] + p / 2 + 0.03), z), 0.15, scale=(1, 0.45, 1.5))
        octahedron(gems, (g["xu0"] - 0.03, y, 3.05), 0.12, scale=(0.45, 1, 1.5))
        octahedron(gems, (xo, y, g["hu"] + 0.3), 0.24, scale=(1, 1, 1.4))
    octahedron(gems, (-1.35, 0, zb - g["beam_h"] - 0.02), 0.13, scale=(1, 1, 1.3))


def decor_frost(P, cfg, g):
    w, p, zb = cfg["pad_w"], cfg["post"], g["zb"]
    box(P("Trim"), (g["x_tail"] - 0.05, -w / 2 - 0.04, zb - 0.07), (1.65, w / 2 + 0.04, zb))
    cr, glow = P("Crystals"), P("Glow")
    xo = g["xu0"] + p / 2
    for s in (-1, 1):
        yo = s * (g["yu"] + p / 2)
        for (z, dx, dy, dz, r) in ((0.5, 0.35, 0.9, 0.8, 0.2), (1.7, -0.2, 0.75, 1.1, 0.17), (2.9, 0.3, 0.6, 1.0, 0.15)):
            crystal(cr, (xo, yo, z), (xo + dx, yo + s * dy, z + dz), r)
        base = Vector((xo, s * g["yu"], g["hu"] - 0.1))
        tip = Vector((xo, s * g["yu"], g["hu"] + 1.25))
        crystal(cr, base, base + (tip - base) * 0.78, 0.27, tip_ratio=0.5)
        crystal(glow, base + (tip - base) * 0.76, tip, 0.27 * 0.5, tip_ratio=0.15)
    for (x, y, h, r) in ((-2.0, 0.85, 0.9, 0.2), (-2.0, -0.85, 0.7, 0.17), (0.2, w / 2 + 0.55, 0.8, 0.19), (0.3, -w / 2 - 0.55, 0.6, 0.16), (2.5, 0.0, 0.75, 0.2)):
        crystal(cr, (x, y, 0), (x + 0.1, y * 1.15, h), r)


def decor_inferno(P, cfg, g):
    w, p, zb = cfg["pad_w"], cfg["post"], g["zb"]
    box(P("Trim"), (g["x_tail"] - 0.04, -w / 2 - 0.03, zb - 0.05), (1.64, w / 2 + 0.03, zb))
    lava, bowls, flames, frame = P("Lava"), P("Bowls"), P("Flames"), P("Frame")
    xo = g["xu0"] + p / 2
    for s in (-1, 1):
        yo = s * (g["yu"] + p / 2)
        for i, z in enumerate((0.9, 2.0, 3.1)):
            cube(lava, (xo, yo, z), (0.07, 0.05, 0.55), rot_euler(0, 22 if i % 2 == 0 else -22, 0))
        for i, z in enumerate((1.4, 2.6)):
            cube(lava, (g["xu0"], s * g["yu"], z), (0.05, 0.07, 0.5), rot_euler(20 if i % 2 == 0 else -20, 0, 0))
        cone(frame, (xo, s * g["yu"], g["hu"]), (xo, s * g["yu"], g["hu"] + 0.6), p * 0.45, 0.0, segs=6)
        bx, by = g["xu1"] + 0.6, s * (g["yu"] + 0.8)
        cone(bowls, (bx, by, 0), (bx, by, 0.36), 0.2, 0.36, segs=8)
        cone(flames, (bx, by, 0.3), (bx, by, 0.98), 0.16, 0.0, segs=6)
        cone(flames, (bx + 0.1, by + 0.08, 0.3), (bx + 0.12, by + 0.1, 0.74), 0.1, 0.0, segs=5)
        cone(flames, (bx - 0.1, by - 0.07, 0.3), (bx - 0.13, by - 0.09, 0.66), 0.09, 0.0, segs=5)
    cube(lava, (-1.35, -p / 2, 0.75), (0.05, 0.05, 0.4), rot_euler(0, 0, 0))
    cube(lava, (1.25, p / 2, 0.7), (0.05, 0.05, 0.36), rot_euler(0, 0, 0))


def decor_cosmic(P, cfg, g):
    w, p, zb = cfg["pad_w"], cfg["post"], g["zb"]
    trim, runes, cr = P("Trim"), P("Runes"), P("Crystals")
    box(trim, (g["x_tail"] - 0.06, -w / 2 - 0.05, zb - 0.07), (1.66, w / 2 + 0.05, zb))
    xo = g["xu0"] + p / 2
    for s in (-1, 1):
        y = s * g["yu"]
        box(trim, (g["xu0"] - 0.03, y - p * 0.2, 0.3), (g["xu0"], y + p * 0.2, g["hu"] - 0.3))
        box(trim, (g["xu0"] - 0.04, y - p / 2 - 0.04, g["hu"]), (g["xu1"] + 0.04, y + p / 2 + 0.04, g["hu"] + 0.12))
        for z in (1.4, 2.5):
            octahedron(runes, (xo, s * (g["yu"] + p / 2 + 0.01), z), 0.14, scale=(1, 0.25, 1.6))
        octahedron(cr, (xo, y, g["hu"] + 0.12 + 0.45), 0.26, scale=(1, 1, 1.8))
        # drifting crystals: one object each (Float1..Float6) so the client can animate them
        base = 0 if s < 0 else 3
        for k, (pos, r) in enumerate((((2.7, s * (g["yu"] + 1.1), 2.3), 0.2), ((-2.3, s * 0.9, 1.9), 0.16), ((0.3, s * (w / 2 + 1.0), 3.5), 0.18))):
            name = "Float%d" % (base + k + 1)
            cfg["mats"][name] = cfg["mats"]["Crystals"]
            octahedron(P(name), pos, r, scale=(1, 1, 1.6))
    box(trim, (-1.35 - p / 2 - 0.05, -p / 2 - 0.05, g["fh"]), (-1.35 + p / 2 + 0.05, p / 2 + 0.05, g["fh"] + 0.1))


DECOR = {"Starter": decor_starter, "Iron": decor_iron, "Gold": decor_gold, "Frost": decor_frost, "Inferno": decor_inferno, "Cosmic": decor_cosmic}


# ---------------------------------------------------------------- assemble
def build_tier(cfg):
    name = cfg["name"]
    cb = coll(name + "_Bench")
    clear_collection(cb.name)
    cbar = coll(name + "_Barbell")
    clear_collection(cbar.name)
    parts = {}

    def P(n):
        if n not in parts:
            parts[n] = bmesh.new()
        return parts[n]

    def scale_all():
        for bm in parts.values():
            bmesh.ops.scale(bm, vec=(SCALE, SCALE, SCALE), verts=bm.verts)

    g = build_frame(P, cfg)
    DECOR[name](P, cfg, g)
    scale_all()                                 # bigger bench about the floor origin
    cube(P("Anchor"), (0, 0, 0), 0.1)          # origin marker (unscaled): the install script aligns on it, then deletes it
    cfg["mats"]["Anchor"] = ("000000", "SmoothPlastic")
    bench_parts = dict(parts)
    parts.clear()
    L = build_barbell(P, cfg, g) * SCALE
    scale_all()                                 # barbell scaled about the bar centre
    bar_parts = dict(parts)
    for n, bm in bench_parts.items():
        hexcol, mat = cfg["mats"][n]
        new_obj(n, bm, cb, hexcol, mat)
    display = Matrix.Translation((RACK_OFFSET[0], 0, RACK_OFFSET[1])) @ rot_euler(0, 0, 90)   # barbell space -> rack (bar along Y)
    for n, bm in bar_parts.items():
        hexcol, mat = cfg["mats"][n]
        o = new_obj(n, bm, cbar, hexcol, mat)
        o.matrix_world = display
    return L


def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.actions, bpy.data.cameras, bpy.data.lights):
        for d in list(block):
            if d.users == 0:
                block.remove(d)


def build_all():
    reset_scene()
    lengths = {}
    for cfg in TIERS:
        lengths[cfg["name"]] = build_tier(cfg)
    bpy.context.view_layer.update()
    stats = {}
    for cfg in TIERS:
        n = cfg["name"]
        stats[n] = {"bench": tri_count(n + "_Bench"), "barbell": tri_count(n + "_Barbell"), "bar_length": round(lengths[n], 2)}
    return stats, lengths


def export_all(lengths):
    """FBX per tier + manifest.json (needs the bar lengths returned by build_all())."""
    out = {"tiers": [], "scale": SCALE, "rack_offset": list(RACK_OFFSET)}
    for cfg in TIERS:
        n = cfg["name"]
        export_fbx(n + "_Bench", os.path.join(ROOT, n + "_Bench.fbx"))
        export_fbx(n + "_Barbell", os.path.join(ROOT, n + "_Barbell.fbx"), identity=True)
        out["tiers"].append({"name": n, "tier": cfg["tier"], "bar_length": round(lengths[n], 3),
                             "bench": manifest([n + "_Bench"]), "barbell": manifest([n + "_Barbell"])})
    with open(os.path.join(ROOT, "manifest.json"), "w") as f:
        json.dump(out, f, indent=1)
    return out


def export_data(lengths):
    """Runtime geometry ModuleScripts (<Theme>.lua) for BenchRuntimeMesh."""
    stats = {}
    for cfg in TIERS:
        n = cfg["name"]
        stats[n] = export_luau(n, cfg["tier"], lengths[n], os.path.join(ROOT, n + ".lua"), scale=SCALE, rack_offset=RACK_OFFSET)
    return stats


def previews():
    paths = []
    for cfg in TIERS:
        n = cfg["name"]
        paths.append(render_preview([n + "_Bench", n + "_Barbell"], os.path.join(ROOT, n + "_preview.png"), yaw_deg=215, pitch_deg=22, dist_mul=2.1))
    return paths


# ---------------------------------------------------------------- tiers after Cosmic (2026-09-06): same footprint (size_tier=6)
def decor_celestial(P, cfg, g):
    """White marble + gold: gold pad trim and bands, gold spires, glowing white diamond insets and
    three-feather gold wings fanning up/outward from the top of each upright."""
    w, p, zb = cfg["pad_w"], cfg["post"], g["zb"]
    trim, wings, glow = P("Trim"), P("Wings"), P("Glow")
    box(trim, (g["x_tail"] - 0.06, -w / 2 - 0.05, zb - 0.07), (1.66, w / 2 + 0.05, zb))
    xo = g["xu0"] + p / 2
    for s in (-1, 1):
        y = s * g["yu"]
        yo = s * (g["yu"] + p / 2)                        # upright outer face
        box(trim, (g["xu0"] - 0.03, y - p * 0.22, 0.3), (g["xu0"], y + p * 0.22, g["hu"] - 0.25))   # gold front stripe
        for z in (0.8, 2.9):                                                                           # gold bands
            box(trim, (g["xu0"] - 0.03, y - p / 2 - 0.03, z - 0.06), (g["xu1"] + 0.03, y + p / 2 + 0.03, z + 0.06))
        box(trim, (g["xu0"] - 0.04, y - p / 2 - 0.04, g["hu"]), (g["xu1"] + 0.04, y + p / 2 + 0.04, g["hu"] + 0.12))  # cap
        octahedron(trim, (xo, y, g["hu"] + 0.62), 0.26, scale=(1, 1, 2.2))                             # gold spire
        octahedron(glow, (xo, y, g["hu"] + 0.55), 0.13, scale=(2.1, 2.1, 1.4))                         # glowing core pokes through
        for z in (1.5, 2.4):                                                                           # glowing diamonds, outer faces
            octahedron(glow, (xo, yo + s * 0.01, z), 0.13, scale=(1, 0.25, 1.7))
        octahedron(glow, (g["xu0"] - 0.03, y, 3.55), 0.11, scale=(0.3, 1, 1.6))                        # front-face diamond
        base = Vector((xo, yo + s * 0.02, g["hu"]))                                                    # wings from the top edge
        for ang, ln, wd in ((20, 1.3, 0.28), (42, 1.1, 0.26), (64, 0.9, 0.24)):
            th = math.radians(ang)
            d = Vector((0, s * math.sin(th), math.cos(th)))
            c = base + d * (ln / 2)
            rot = rot_euler(-s * ang, 0, 0)
            cube(wings, tuple(c), (0.12, wd, ln), rot)
            cube(glow, tuple(c + d * 0.06), (0.14, wd * 0.42, ln * 0.68), rot)
        fx = g["xu0"] - 0.5 - (p - 0.2) * 0.5                                                          # upright foot front
        octahedron(glow, (fx - 0.01, y, g["fh"] / 2), 0.07, scale=(0.3, 1.4, 1))
    box(trim, (-1.35 - p / 2 - 0.05, -p / 2 - 0.05, g["fh"]), (-1.35 + p / 2 + 0.05, p / 2 + 0.05, g["fh"] + 0.1))
    octahedron(glow, (-1.35 - p / 2 - 0.02, 0, zb - g["beam_h"] - 0.3), 0.1, scale=(0.3, 1, 1.5))


def decor_void(P, cfg, g):
    """Obsidian + gold: gold edge stripes with a red glowing slot on each upright, crown spikes with a
    red gem, red diamond insets, obsidian fins at the bases and six drifting crystals (Float1..6)."""
    w, p, zb = cfg["pad_w"], cfg["post"], g["zb"]
    trim, glow, frame, cr = P("Trim"), P("Glow"), P("Frame"), P("Crystals")
    box(trim, (g["x_tail"] - 0.06, -w / 2 - 0.05, zb - 0.07), (1.66, w / 2 + 0.05, zb))
    xo = g["xu0"] + p / 2
    for s in (-1, 1):
        y = s * g["yu"]
        yo = s * (g["yu"] + p / 2)
        box(trim, (g["xu0"] - 0.03, y - p / 2, 0.25), (g["xu0"], y - p / 2 + 0.08, g["hu"] - 0.2))      # gold edge stripes
        box(trim, (g["xu0"] - 0.03, y + p / 2 - 0.08, 0.25), (g["xu0"], y + p / 2, g["hu"] - 0.2))
        box(glow, (g["xu0"] - 0.02, y - 0.05, 0.6), (g["xu0"] + 0.01, y + 0.05, g["hu"] - 0.5))         # red slot
        box(trim, (g["xu0"] - 0.04, y - p / 2 - 0.04, g["hu"]), (g["xu1"] + 0.04, y + p / 2 + 0.04, g["hu"] + 0.12))  # cap
        cone(frame, (xo, y, g["hu"] + 0.1), (xo, y, g["hu"] + 1.15), p * 0.32, 0.0, segs=4)               # crown centre spike
        for k in (-1, 1):
            cone(trim, (xo, y + k * p * 0.36, g["hu"] + 0.1), (xo, y + k * p * 0.5, g["hu"] + 0.65), p * 0.16, 0.0, segs=4)
        octahedron(glow, (xo, y, g["hu"] + 0.42), 0.12, scale=(1.5, 1.5, 1.8))                            # gem in the crown
        for z in (1.2, 2.2, 3.2):                                                                          # red diamonds, outer faces
            octahedron(glow, (xo, yo + s * 0.01, z), 0.13, scale=(1, 0.25, 1.7))
        for dx, ln in ((-0.3, 0.5), (0.0, 0.7), (0.3, 0.5)):                                             # obsidian fins at the base
            cone(cr, (xo + dx, yo, g["fh"] + 0.05), (xo + dx, yo + s * 0.45, g["fh"] + ln), 0.11, 0.0, segs=4)
        fx = g["xu0"] - 0.5 - (p - 0.2) * 0.5
        octahedron(glow, (fx - 0.01, y, g["fh"] / 2), 0.07, scale=(0.3, 1.4, 1))
        base = 0 if s < 0 else 3                                                                            # drifting crystals
        for k, (pos, r) in enumerate((((2.7, s * (g["yu"] + 1.1), 2.3), 0.2), ((-2.3, s * 0.9, 1.9), 0.16), ((0.3, s * (w / 2 + 1.0), 3.5), 0.18))):
            name = "Float%d" % (base + k + 1)
            cfg["mats"][name] = cfg["mats"]["Floats"]
            octahedron(P(name), pos, r, scale=(1, 1, 1.6))
    box(trim, (-1.35 - p / 2 - 0.05, -p / 2 - 0.05, g["fh"]), (-1.35 + p / 2 + 0.05, p / 2 + 0.05, g["fh"] + 0.1))
    octahedron(glow, (-1.35 - p / 2 - 0.02, 0, zb - g["beam_h"] - 0.3), 0.1, scale=(0.3, 1, 1.5))
    for x in (-2.0, 2.6):
        cone(cr, (x, 0.9, 0), (x + 0.1, 1.05, 0.55), 0.14, 0.0, segs=4)
        cone(cr, (x, -0.9, 0), (x + 0.1, -1.05, 0.5), 0.13, 0.0, segs=4)


TIERS += [
    dict(name="Celestial", tier=7, size_tier=6, post=0.58, pad_w=1.45, pad_t=0.42, plate_r=0.95, plate_t=0.30, plates=3, bar_r=0.075,
         plate_style="halo", feet_part="Frame",
         mats={"Frame": ("f3efe6", "SmoothPlastic"), "Pad": ("f7f7f9", "SmoothPlastic"), "Trim": ("e6b422", "Metal"),
               "Wings": ("e6b422", "Metal"), "Glow": ("fff1b8", "Neon"), "Bar": ("c9ccd3", "Metal"),
               "Plates": ("f2eee6", "SmoothPlastic"), "Rims": ("e6b422", "Metal"), "Collars": ("e6b422", "Metal")}),
    dict(name="VoidEmperor", tier=8, size_tier=6, post=0.58, pad_w=1.45, pad_t=0.42, plate_r=0.95, plate_t=0.30, plates=3, bar_r=0.075,
         plate_style="void", feet_part="Frame",
         mats={"Frame": ("1a171f", "Slate"), "Pad": ("b0161e", "SmoothPlastic"), "Trim": ("d4a11e", "Metal"),
               "Glow": ("ff2233", "Neon"), "Crystals": ("2a0f1c", "Slate"), "Floats": ("9a1426", "Neon"), "Bar": ("b4b7c0", "Metal"),
               "Plates": ("1b1520", "SmoothPlastic"), "Collars": ("d4a11e", "Metal")}),
]
DECOR.update({"Celestial": decor_celestial, "VoidEmperor": decor_void})
