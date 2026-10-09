"""The pure-maths half of `guardianlib` - the role palettes, the per-guardian spec
table, and every helper that returns NUMBERS rather than geometry.

It imports nothing but `math` and `random`, so `dryrun.py` runs it FOR REAL outside
Blender: anything here behaves offline exactly as it will inside Blender.
`guardianlib` does `from gmath import *`, so a build script only ever sees `G.<name>`.

ROLES is the important table.  The FBX pipeline drops every material, so each part is
named `<Guardian>_<Part>_<Role>` and the installer stamps the colour back from the
role - `Frostbite_Arm_L_FurWhite` is fur white because the last underscore-separated
token says so.  Roles are therefore namespaced per guardian (every guardian has an
`EyeGlow`, and no two are the same colour).
"""
import math, random

# =================================================================== the ten
# name -> (biome, standing studs, sitting studs, footprint x, footprint y, seat part)
SPEC = {
    "Strawman":  dict(biome="Spawn",      stand=7.0,  sit=5.0,  foot=(3.0, 3.0),
                      seat="HayBale",  pace="slow, stops to shake crows out"),
    "Dune":      dict(biome="Desert",     stand=12.0, sit=2.2,  foot=(3.5, 12.0),
                      seat="SandMound", pace="fast under sand, surfaces ahead"),
    "Kabuto":    dict(biome="Samurai",    stand=9.0,  sit=6.5,  foot=(4.0, 4.0),
                      seat="Pedestal", pace="medium, slam wind-up"),
    "Brisket":   dict(biome="Farm",       stand=8.0,  sit=5.0,  foot=(5.0, 12.0),
                      seat="MudPatch", pace="line charge, slow turns"),
    "Frostbite": dict(biome="Snow",       stand=10.0, sit=6.0,  foot=(5.0, 4.0),
                      seat="IceBlock", pace="slow start, fast after"),
    "Pinch":     dict(biome="Underwater", stand=6.0,  sit=5.0,  foot=(14.0, 8.0),
                      seat="RockNook", pace="fast sideways, slow forward"),
    "Ember":     dict(biome="Volcano",    stand=11.0, sit=5.0,  foot=(5.0, 5.0),
                      seat="RockPile", pace="slow, relentless, throws"),
    "Orbit":     dict(biome="Narmek",     stand=12.0, sit=8.0,  foot=(7.0, 7.0),
                      seat="CrescentMoon", pace="blinks, gravity pull"),
    "Tick":      dict(biome="Toyland",    stand=9.0,  sit=6.0,  foot=(4.0, 3.0),
                      seat="BlockStack", pace="sprint 6 s, rewind"),
    "Scan":      dict(biome="Neon",       stand=8.0,  sit=4.0,  foot=(6.0, 6.0),
                      seat="ChargingPad", pace="scan and blink"),
}

GUARDIANS = list(SPEC.keys())


# =================================================================== role palettes
# Every colour the concept sheets name, plus the few extra roles the art shows but the
# legend does not.  Hex, no '#'.  A role used by a build script MUST be in here.
ROLES = {
    # ---- 1. Spawn - hay scarecrow ------------------------------------------------
    "Strawman": {
        "Burlap":     "c4a46e",   # 196,164,110  sack head, hat, patches
        "BurlapDark": "a88a58",   # stitching, hat shadow, sack seam
        "Straw":      "debe50",   # 222,190,80   tufts at neck/wrist/ankle
        "StrawDark":  "c2a03a",
        "Shirt":      "8c3c32",   # 140,60,50    ragged shirt, hat band, pole ribbon
        "Denim":      "465a8c",   # 70,90,140    overalls
        "DenimDark":  "36476e",
        "Pole":       "6e5032",   # 110,80,50    wooden cross pole, arms, legs
        "PoleDark":   "563e26",
        "Boot":       "5a3e26",   # blocky boots
        "EyeGlow":    "ff8c28",   # 255,140,40   button eyes when awake
        "Stitch":     "4a3524",   # stitched X mouth, button thread
        "Crow":       "262a32",   # the crows that burst off it
        "Ground":     "8f8a80",   # the little stones on its base
    },
    # ---- 2. Desert - sand worm ----------------------------------------------------
    "Dune": {
        "Sandstone":  "d2aa6e",   # 210,170,110  plates, hood, rings
        "RingShadow": "a07846",   # 160,120,70   the gap between rings
        "Mouth":      "c85a5a",   # 200,90,90    throat
        "MouthDark":  "9c4444",
        "Teeth":      "f0e6c8",   # 240,230,200
        "EyeGlow":    "ffbe3c",   # 255,190,60
        "EyeSlit":    "4a3520",   # the slit pupil and the heavy lid line
        "Sand":       "dcc78f",   # the mound it travels as
        "SandDark":   "bda66f",
    },
    # ---- 3. Samurai - stone oni ---------------------------------------------------
    "Kabuto": {
        "Stone":      "96969b",   # 150,150,155
        "StoneDark":  "7b7b81",
        "Cracks":     "5a5a5f",   # 90,90,95     the recessed crack channels
        "Rope":       "c83228",   # 200,50,40    belt, tassels, club bands
        "RopeDark":   "962318",
        "Moss":       "6e9646",   # 110,150,70   shoulder and knee patches
        "Tusks":      "ebe1c8",   # 235,225,200
        "EyeGlow":    "ffaa32",   # 255,170,50   eyes AND the crack lines
        "Lantern":    "ffd98a",   # the pedestal lanterns
        "Grass":      "6e9646",
    },
    # ---- 4. Farm - bull -----------------------------------------------------------
    "Brisket": {
        "Chestnut":     "784628",   # 120,70,40
        "ChestnutDark": "5f371e",
        "Horn":         "ebdcbe",   # 235,220,190  horns and muzzle
        "Nose":         "d78c8c",   # 215,140,140
        "Hoof":         "282323",   # 40,35,35     hooves and tail tuft
        "Ring":         "c8a03c",   # 200,160,60   brass nose ring
        "EyeGlow":      "eb3232",   # 235,50,50
        "Steam":        "f0f0ee",   # the puffs from its nose
        "Mud":          "5f422a",   # the patch it lies in
        "MudDark":      "46301e",
        "Fence":        "8c6946",   # the broken fence corner
        "Grass":        "6e9646",
    },
    # ---- 5. Snow - yeti -----------------------------------------------------------
    "Frostbite": {
        "FurWhite":   "f0f4fa",   # 240,244,250
        "FurShadow":  "aac3e1",   # 170,195,225
        "Face":       "6e82a0",   # 110,130,160  face oval, palms, soles
        "FaceDark":   "586a86",
        "Fangs":      "fafaf5",   # 250,250,245
        "EyeGlow":    "78c8ff",   # 120,200,255
        "Ice":        "96cdeb",   # the cracked ice block it sits on
        "IceDark":    "6ea0c8",
    },
    # ---- 6. Underwater - king crab ------------------------------------------------
    "Pinch": {
        "Shell":      "dc5a3c",   # 220,90,60
        "ShellDark":  "b8462d",
        "Underside":  "f5d7b4",   # 245,215,180  belly plate, claw tips, leg tips
        "Coral":      "3caaa0",   # 60,170,160   the nubs crusted on its back
        "Barnacle":   "ebebe1",   # 235,235,225
        "Rock":       "6e6e78",   # 110,110,120  the nook
        "RockDark":   "56565f",
        "EyeGlow":    "78ff96",   # 120,255,150  the cross in each eye plate
        "EyeSocket":  "143c2d",   # the dark plate the cross sits in
        "Starfish":   "c85037",   # the little starfish on the sea floor
        "Sand":       "d8c48c",
    },
    # ---- 7. Volcano - magma golem -------------------------------------------------
    "Ember": {
        "Basalt":     "2d282a",   # 45,40,42
        "BasaltLight": "3e3833",
        "Lava":       "ff7814",   # 255,120,20   the seams in the gaps (Neon)
        "EmberGlow":  "ffc83c",   # 255,200,60
        "Ash":        "78736e",   # 120,115,110
    },
    # ---- 8. Narmek - meteor colossus ----------------------------------------------
    "Orbit": {
        "Navy":       "19143c",   # 25,20,60
        "NavyLight":  "2d2655",
        "Glow":       "aa50ff",   # 170,80,255   crack, hands (Neon)
        "Starlight":  "78dcff",   # 120,220,255  the diamonds (Neon)
        "MoonGrey":   "c8c8d7",   # 200,200,215
        "MoonShadow": "9c9caa",
    },
    # ---- 9. Toyland - wind-up soldier ---------------------------------------------
    "Tick": {
        "Red":        "dc2828",   # 220,40,40
        "RedDark":    "b01d1d",
        "Cream":      "f0e6c8",   # 240,230,200
        "Blue":       "2850c8",   # 40,80,200
        "BlueDark":   "1d3c9c",
        "Brass":      "c8a03c",   # 200,160,60
        "BrassDark":  "96762a",
        "Bulb":       "fff078",   # 255,240,120  (Neon)
        "VisorGlow":  "50e6ff",   # 80,230,255   (Neon)
        "BlockGreen": "5f965a",   # the ABC blocks it slumps on
        "BlockYellow": "ebc35a",
    },
    # ---- 10. Neon - laser sentinel ------------------------------------------------
    "Scan": {
        "Body":       "141419",   # 20,20,25
        "BodyLight":  "23232a",
        "Magenta":    "ff32c8",   # 255,50,200   (Neon)
        "Cyan":       "32e6ff",   # 50,230,255   (Neon)
        "Core":       "ffffff",   # 255,255,255  (Neon)
        "PadDark":    "23232a",   # the charging pad and its rocks
        "PadRock":    "35353f",
    },
}

# Roles that light up.  Default (authored) look = AWAKE, because that is the hero art;
# SLEEP_LOOK is what the installer stamps while the guardian is asleep.
# role -> (hex, roblox material)
SLEEP_LOOK = {
    "Strawman": {"EyeGlow": ("5e4322", "SmoothPlastic")},
    "Dune":     {"EyeGlow": ("6b5228", "SmoothPlastic")},
    "Kabuto":   {"EyeGlow": ("5c5148", "SmoothPlastic"),
                 "Lantern": ("6b6354", "SmoothPlastic")},
    "Brisket":  {"EyeGlow": ("5e2626", "SmoothPlastic")},
    "Frostbite": {"EyeGlow": ("3f5470", "SmoothPlastic")},
    "Pinch":    {"EyeGlow": ("2a5c40", "SmoothPlastic")},
    "Ember":    {"Lava": ("332c28", "Slate"), "EmberGlow": ("3a332c", "Slate")},
    "Orbit":    {"Glow": ("3a2a55", "SmoothPlastic"),
                 "Starlight": ("50607a", "SmoothPlastic")},
    "Tick":     {"VisorGlow": ("1c2a33", "SmoothPlastic"),
                 "Bulb": ("6b6449", "SmoothPlastic")},
    "Scan":     {"Magenta": ("4a2340", "SmoothPlastic"),
                 "Cyan": ("1e4552", "SmoothPlastic"),
                 "Core": ("50505a", "SmoothPlastic")},
}

# Roles that are Neon in Roblox (and get a little emission in the Blender render).
NEON_ROLES = {
    "Strawman": ("EyeGlow",),
    "Dune":     ("EyeGlow",),
    "Kabuto":   ("EyeGlow", "Lantern"),
    "Brisket":  ("EyeGlow",),
    "Frostbite": ("EyeGlow",),
    "Pinch":    ("EyeGlow",),
    "Ember":    ("Lava", "EmberGlow"),
    "Orbit":    ("Glow", "Starlight"),
    "Tick":     ("VisorGlow", "Bulb"),
    "Scan":     ("Magenta", "Cyan", "Core"),
}


# Every guardian also gets the two structural roles the rig needs.
for _g in ROLES:
    ROLES[_g].setdefault("Invisible", "808080")   # Hitbox / Root, transparency 1


def role_hex(guardian, role):
    """Colour for a role, failing loudly on a typo."""
    table = ROLES.get(guardian)
    if table is None:
        raise KeyError("no guardian %r - known: %s" % (guardian, ", ".join(sorted(ROLES))))
    if role not in table:
        raise KeyError("guardian %s has no role %r - roles: %s"
                       % (guardian, role, ", ".join(sorted(table))))
    return table[role]


def is_neon(guardian, role):
    return role in NEON_ROLES.get(guardian, ())


def sleep_look(guardian, role):
    """(hex, material) this role wears while the guardian is asleep, or None."""
    return SLEEP_LOOK.get(guardian, {}).get(role)


# =================================================================== numeric helpers
def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def add3(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub3(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul3(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def norm3(v):
    L = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return (0.0, 0.0, 0.0) if L < 1e-12 else (v[0] / L, v[1] / L, v[2] / L)


def dist3(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def mid3(a, b):
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0, (a[2] + b[2]) / 2.0)


def chain_points(a, b, n, sag=0.0, bow=(0.0, 0.0, 0.0)):
    """`n` points from a to b, optionally bowed sideways and sagging in the middle."""
    out = []
    for i in range(n):
        t = i / float(n - 1)
        p = lerp3(a, b, t)
        k = 4.0 * t * (1.0 - t)
        out.append((p[0] + bow[0] * k, p[1] + bow[1] * k, p[2] + bow[2] * k - sag * k))
    return out


def taper(r0, r1, n, power=1.0):
    """`n` radii from r0 to r1; power > 1 keeps it fat then drops away at the end."""
    return [r0 + (r1 - r0) * ((i / float(n - 1)) ** power) for i in range(n)]


def sphere_dirs(n, seed=1, up_bias=0.0, cone_deg=180.0, axis=(0.0, 0.0, 1.0)):
    """`n` evenly-ish scattered unit directions inside a cone about `axis`.

    Fibonacci sphere, so it is deterministic and never clumps: fur tufts, coral nubs,
    barnacles, boulder satellites."""
    ax = norm3(axis)
    # a frame with ax as its z
    tmp = (0.0, 0.0, 1.0) if abs(ax[2]) < 0.9 else (1.0, 0.0, 0.0)
    ux = norm3((ax[1] * tmp[2] - ax[2] * tmp[1], ax[2] * tmp[0] - ax[0] * tmp[2],
                ax[0] * tmp[1] - ax[1] * tmp[0]))
    uy = (ax[1] * ux[2] - ax[2] * ux[1], ax[2] * ux[0] - ax[0] * ux[2],
          ax[0] * ux[1] - ax[1] * ux[0])
    rng = random.Random(seed)
    phase = rng.random() * 2.0 * math.pi
    cos_min = math.cos(math.radians(max(1.0, min(180.0, cone_deg))))
    out = []
    for i in range(n):
        t = (i + 0.5) / float(n)
        cz = 1.0 - t * (1.0 - cos_min)
        cz = min(1.0, cz + up_bias * (1.0 - cz))
        r = math.sqrt(max(0.0, 1.0 - cz * cz))
        a = phase + i * 2.399963229728653          # golden angle
        out.append((ux[0] * math.cos(a) * r + uy[0] * math.sin(a) * r + ax[0] * cz,
                    ux[1] * math.cos(a) * r + uy[1] * math.sin(a) * r + ax[1] * cz,
                    ux[2] * math.cos(a) * r + uy[2] * math.sin(a) * r + ax[2] * cz))
    return out


def ellipsoid_points(center, radii, dirs):
    """Push unit directions onto an ellipsoid surface - where to root a tuft/nub."""
    return [(center[0] + d[0] * radii[0], center[1] + d[1] * radii[1],
             center[2] + d[2] * radii[2]) for d in dirs]


def crescent_profile(r_out=1.0, r_in=0.80, offset=0.42, n=14, open_deg=150.0):
    """2-D outline of a crescent moon opening upward (+Y), for `prism`.

    The outer arc is a circle of `r_out`; the inner arc is a circle of `r_in` pushed
    `offset` up, and the horns close where they meet.  `open_deg` is how much of the
    outer circle is kept (150 = a fat crescent, 200 = thin horns)."""
    half = math.radians(open_deg) / 2.0
    a0, a1 = -math.pi / 2.0 - half, -math.pi / 2.0 + half   # sweep round the bottom
    out = [(math.cos(a0 + (a1 - a0) * i / (n - 1.0)) * r_out,
            math.sin(a0 + (a1 - a0) * i / (n - 1.0)) * r_out) for i in range(n)]
    for i in range(n):
        t = 1.0 - i / (n - 1.0)
        a = a0 + (a1 - a0) * t
        out.append((math.cos(a) * r_in, math.sin(a) * r_in + offset))
    return out


def ring_slots(n, radius, phase_deg=0.0, center=(0.0, 0.0), squash=1.0):
    """n (x, y) points round an ellipse - orbit rocks, bolts, legs, pedestal lanterns."""
    out = []
    for i in range(n):
        a = math.radians(phase_deg) + 2.0 * math.pi * i / float(n)
        out.append((center[0] + math.cos(a) * radius,
                    center[1] + math.sin(a) * radius * squash))
    return out


def leg_slots(n_per_side, y0, y1, x, splay=0.0):
    """Crab / bull leg roots: n per side, marching back along y, mirrored in x.
    Returns [(x, y, side)] with side +1 for screen-left (+x) and -1 for -x."""
    out = []
    for i in range(n_per_side):
        t = i / float(max(1, n_per_side - 1))
        y = y0 + (y1 - y0) * t
        dx = x + splay * abs(t - 0.5) * 2.0
        out.append((dx, y, +1))
        out.append((-dx, y, -1))
    return out


def segment_chain(start, end, n, r0, r1, droop=0.0, power=1.0):
    """Centres + radii for a tapering chain of rings (the worm body, a tail).
    Returns [(point, radius)]."""
    pts = chain_points(start, end, n, sag=droop)
    rs = taper(r0, r1, n, power=power)
    return list(zip(pts, rs))


def boulder_slots(n, center, radii, seed=1, spread=1.0):
    """Scattered boulder centres inside an ellipsoid - Ember's body, a rock pile."""
    rng = random.Random(seed)
    out = []
    for i in range(n):
        d = sphere_dirs(n, seed=seed)[i]
        k = spread * (0.45 + 0.55 * rng.random())
        out.append((center[0] + d[0] * radii[0] * k,
                    center[1] + d[1] * radii[1] * k,
                    center[2] + d[2] * radii[2] * k))
    return out


def zigzag(a, b, n=5, amp=0.18, axis=(0.0, 0.0, 1.0)):
    """Points zig-zagging between a and b - a lightning crack, a stitched seam."""
    out = []
    for i in range(n):
        t = i / float(n - 1)
        p = lerp3(a, b, t)
        s = amp * (1 if i % 2 else -1) * (0.0 if i in (0, n - 1) else 1.0)
        out.append((p[0] + axis[0] * s, p[1] + axis[1] * s, p[2] + axis[2] * s))
    return out


def fan_angles(n, spread_deg, center_deg=0.0):
    """n angles spread evenly over `spread_deg`, centred on `center_deg`."""
    if n == 1:
        return [center_deg]
    return [center_deg - spread_deg / 2.0 + spread_deg * i / float(n - 1) for i in range(n)]


def pose_blend(a, b, t):
    """Blend two pose dicts (part -> (rx, ry, rz)) - handy for a half-wake preview."""
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k, (0, 0, 0)), b.get(k, (0, 0, 0))
        out[k] = tuple(va[i] + (vb[i] - va[i]) * t for i in range(3))
    return out
