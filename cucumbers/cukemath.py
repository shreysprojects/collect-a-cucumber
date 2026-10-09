"""The pure-maths half of `cucumberlib` - the palette, the body profile, and every
helper that returns NUMBERS rather than geometry.

It imports nothing but `math` and `random`, so `dryrun.py` can run it for real outside
Blender.  `cucumberlib` does `from cukemath import *`, so a build script only ever sees
`D.<name>` and never needs to know this file exists.
"""
import math, random

# ================================================================= palette
# proplib's own 79 keys stay available through cucumberlib; these are this set's.
CUKE_PALETTE = {
    # --- the cucumber itself -------------------------------------------------
    "cuke_green":   "46a831",   # body
    "cuke_mid":     "3d9429",
    "cuke_dark":    "2f7a24",   # slice rim, shadow side
    "cuke_deep":    "215c19",
    "cuke_stud":    "7fd13d",   # the raised square speckles
    "cuke_stud_dk": "5cb32e",
    "cuke_pale":    "dcefb4",   # cut face
    "cuke_seed":    "b9dd7d",
    "cuke_stem":    "3a8f27",

    # --- desert --------------------------------------------------------------
    "des_olive":     "6f8f2e",
    "des_olive_dk":  "556f22",
    "des_baked":     "7d8a3c",
    "des_baked_dk":  "5e6a2a",
    "des_crack":     "3d451c",
    "des_spike":     "ecdcad",
    "des_spike_dk":  "cbb686",
    "des_bandage":   "e6d7ae",
    "des_bandage_d": "cbb98d",
    "des_sand":      "dcc78f",
    "des_stone":     "d6c08a",
    "des_stone_dk":  "b9a069",
    "des_trunk":     "a9793f",
    "des_trunk_dk":  "8a5c2c",
    "des_frond":     "4fa83a",
    "des_frond_dk":  "3d8a2c",
    "des_coconut":   "7a4a28",
    "des_flower":    "f2d44e",
    "des_flower_c":  "8a5a2b",

    # --- volcano -------------------------------------------------------------
    "vol_char":      "2c2723",
    "vol_char_lt":   "3e3833",
    "vol_char_dk":   "1c1917",
    "vol_lava":      "ff6a1e",
    "vol_lava_hot":  "ffa42b",
    "vol_lava_core": "ffd24a",
    "vol_ember":     "e8431a",
    "vol_obsidian":  "241f2b",
    "vol_ash":       "56504a",

    # --- narmek (space) ------------------------------------------------------
    "nar_moon":      "b9bcc4",
    "nar_moon_dk":   "8b8f99",
    "nar_moon_lt":   "d6d9df",
    "nar_glow_grn":  "58e08a",
    "nar_meteor":    "463a5e",
    "nar_meteor_lt": "6d5a8f",
    "nar_glow_pur":  "b45cff",
    "nar_planet_b":  "3fa8e0",
    "nar_planet_g":  "6ec84a",
    "nar_planet_c":  "6fd8e8",
    "nar_suit":      "f0efec",
    "nar_suit_sh":   "d2d0cb",
    "nar_orange":    "e8802e",
    "nar_visor":     "1a1d2a",
    "nar_visor_lt":  "343a52",
    "nar_metal":     "8d929c",
    "nar_alien_grn": "4fc83a",
    "nar_gem":       "ff5fd0",
    "nar_gem_dk":    "d63fa8",
    "nar_ufo":       "c6c2d0",
    "nar_ufo_dk":    "9b96a9",
    "nar_teal":      "2f9e86",
    "nar_teal_dk":   "227a68",
    "nar_amber":     "f2a12e",
    "nar_amber_dk":  "d4831c",
    "nar_galaxy":    "6a3fb0",
    "nar_galaxy_dk": "4a2b80",
    "nar_galaxy_c":  "e8d8ff",
    "nar_star":      "cfe0ff",

    # --- samurai -------------------------------------------------------------
    "sam_steel":     "d8dde6",
    "sam_hilt":      "23262c",
    "sam_gold":      "e8b73a",
    "sam_gold_dk":   "b98d22",
    "sam_ribbon":    "cf3b30",
    "sam_ribbon_dk": "9e2a21",
    "sam_bamboo":    "d9bd72",
    "sam_bamboo_dk": "b89a52",
    "sam_stalk":     "57ad3c",
    "sam_stalk_dk":  "3f8c2c",
    "sam_leaf":      "5cbf3f",
    "sam_roof":      "44474f",
    "sam_roof_lt":   "5c606a",
    "sam_warm":      "ffd98a",
    "sam_paper":     "e8dcb8",
    "sam_ink":       "3a3228",
    "sam_torii":     "c8382c",
    "sam_torii_dk":  "a02a20",
    "sam_sakura":    "f7a8cc",
    "sam_sakura_dk": "e878b0",
    "sam_bark":      "6b4a32",
    "sam_bark_dk":   "513723",
    "sam_rock":      "8f8a80",
    "sam_rock_dk":   "6b675f",

    # --- farm ----------------------------------------------------------------
    "farm_basket":   "a9743c",
    "farm_basket_d": "7e5228",
    "farm_crate":    "d4a962",
    "farm_crate_d":  "b08842",
    "farm_mud":      "6b4a2a",
    "farm_mud_lt":   "8a6438",
    "farm_hay":      "e0c454",
    "farm_hay_dk":   "c2a03a",
    "farm_strap":    "7a4f2a",
    "farm_cream":    "e8e0cc",
    "farm_red":      "c8453a",
    "farm_wood":     "c79a58",
    "farm_wood_dk":  "9c7440",
    "farm_bark":     "8a5a2b",
    "farm_bark_dk":  "6b4423",

    # --- snow ----------------------------------------------------------------
    "snow_white":    "f4fafd",
    "snow_shadow":   "dcebf6",
    "snow_ice":      "4fb0e8",
    "snow_ice_lt":   "8fd4f2",
    "snow_ice_dk":   "3a8cc0",
    "snow_crystal":  "9fe0f8",
    "snow_pine":     "2f7a4a",
    "snow_pine_dk":  "22603a",
    "snow_bark":     "6b4a32",
    "snow_bark_dk":  "513723",

    # --- underwater ----------------------------------------------------------
    "sea_bubble":    "6fc8f0",
    "sea_bubble_lt": "b8e6f8",
    "sea_weed":      "3f9e3a",
    "sea_weed_dk":   "2f7d2c",
    "sea_shell":     "e8b4d8",
    "sea_shell_dk":  "c98cb8",
    "sea_shell_in":  "f4ead2",
    "sea_coral_p":   "6a4fb0",
    "sea_coral_pd":  "50398a",
    "sea_coral_r":   "f0544a",
    "sea_coral_o":   "f08a3a",
    "sea_pearl":     "f4f0e8",
    "sea_pearl_sh":  "ddd6c8",
    "sea_kelp":      "4faa4a",
    "sea_kelp_dk":   "3c8a38",
    "sea_stalk":     "3f8a7a",
    "sea_stalk_dk":  "2f6b5e",
    "sea_deep":      "3f6fb0",
    "sea_deep_dk":   "2f5490",

    # --- toyland (2026-09-18) ------------------------------------------------
    # saturated toy plastic: primary red / blue / yellow / green, a white, a brown
    "toy_red":       "e0352b",
    "toy_red_dk":    "a82620",
    "toy_blue":      "2f6fe0",
    "toy_blue_dk":   "2350b0",
    "toy_yellow":    "ffc72a",
    "toy_yellow_dk": "dca21a",
    "toy_green":     "3fb13a",   # brick green (block tree crown, pinwheel base)
    "toy_green_dk":  "2c8a2a",
    "toy_white":     "f4f2ec",
    "toy_white_sh":  "d6d4ce",
    "toy_brown":     "8a5530",   # block tree trunk bricks
    "toy_brown_dk":  "6a3f22",
    "toy_magenta":   "c23a8e",   # the train's little blocks
    "toy_orange":    "ff8a24",
    "toy_eye":       "1c1e24",   # eyes / mouths on the faced cucumbers
    "toy_eye_hl":    "ffffff",
    "toy_face_lt":   "a6e25a",   # toy slice cut face (brighter than cuke_pale)
    "toy_spoke":     "e6f7c4",   # the pale radial spokes on a cut face

    # --- neon (2026-09-18) ---------------------------------------------------
    # dark indigo bodies + glowing tubes; every glow part is rbx_material "Neon"
    "neo_night":     "1c1942",   # dark indigo plinths, trunks, pedestals
    "neo_night_dk":  "121030",
    "neo_night_lt":  "2c2866",
    "neo_trunk":     "2a2560",
    "neo_cyan":      "3fe6ff",
    "neo_magenta":   "ff3fd2",
    "neo_purple":    "a04dff",
    "neo_pink":      "ff5fb0",
    "neo_lime":      "a6ff3f",   # neon slice face, grid-cucumber stem
    "neo_holo":      "3fa8ff",   # hologram body
    "neo_holo_lt":   "9fe4ff",   # hologram pixels / scan lines
    "neo_green":     "3fae45",   # palm leaves / tree crown cubes (solid, not glowing)
    "neo_green_dk":  "2d8a36",
    "neo_goggle":    "c7a2ff",   # cyber goggles (lavender)
    "neo_goggle_dk": "8a5cd6",
    "neo_lens":      "241a48",
}


# ================================================================= the body
# (radius fraction, height fraction).  Flat-ish caps, straight through the middle,
# chamfered at both ends - the silhouette every cucumber in the set shares.
CUKE_PROFILE = [
    (0.00, 0.000), (0.62, 0.000), (0.84, 0.032), (0.96, 0.082),
    (1.00, 0.250), (1.00, 0.660), (0.97, 0.858), (0.88, 0.922),
    (0.70, 0.964), (0.48, 1.000), (0.00, 1.000),
]

# A stubbier berry-ish body: basket / crate fruit, hanging tree cucumbers.
CUKE_PROFILE_STUB = [
    (0.00, 0.000), (0.58, 0.000), (0.86, 0.055), (1.00, 0.190),
    (1.00, 0.700), (0.94, 0.880), (0.78, 0.950), (0.46, 1.000), (0.00, 1.000),
]

CUKE_SEGS = 8
CUKE_H = 4.0        # the set's standard upright cucumber height
CUKE_R = 0.68       # ... and its radius (1.36 across, so ~2.9 : 1)

SLICE_R = 0.80      # standard slice radius
SLICE_T = 0.42      # ... and thickness
SLICE_SEGS = 10


def cuke_phase(segs=CUKE_SEGS):
    """Lathe phase that puts a FLAT FACET (not an edge) square on +Y."""
    return math.pi / float(segs)


def cuke_radius(zf, profile=None):
    """Body radius (as a fraction of r) at height fraction `zf` in 0..1."""
    prof = profile or CUKE_PROFILE
    zf = max(0.0, min(1.0, float(zf)))
    best = 0.0
    for i in range(len(prof) - 1):
        r0, z0 = prof[i]
        r1, z1 = prof[i + 1]
        lo, hi = (z0, z1) if z0 <= z1 else (z1, z0)
        if lo - 1e-9 <= zf <= hi + 1e-9:
            if abs(z1 - z0) < 1e-9:
                best = max(best, r0, r1)
            else:
                t = (zf - z0) / (z1 - z0)
                best = max(best, r0 + (r1 - r0) * t)
    return best


def cuke_facet_angle(facet, segs=CUKE_SEGS, phase=None):
    """Outward angle (RADIANS) of the centre of facet `facet`.  facet 1 -> +Y."""
    ph = cuke_phase(segs) if phase is None else phase
    return ph + (2.0 * facet + 1.0) * math.pi / float(segs)


def cuke_point(h=CUKE_H, r=CUKE_R, zf=0.5, angle_deg=90.0, profile=None, offset=0.0,
               segs=CUKE_SEGS, flat=True):
    """A point on the body surface: `zf` up (0..1), `angle_deg` around it (+Y = 90).

    `flat` measures to the FACET plane (what a lathed 8-gon actually is) rather than to
    the circumscribed circle, so what you place with it sits on the skin instead of
    floating off it.  `offset` then pushes out along the outward normal."""
    a = math.radians(float(angle_deg))
    rad = cuke_radius(zf, profile) * r
    if flat:
        rad *= math.cos(math.pi / float(segs))
    rad += offset
    return (math.cos(a) * rad, math.sin(a) * rad, zf * h)


def cuke_normal(angle_deg):
    """Outward unit normal of the body at `angle_deg` (+Y = 90)."""
    a = math.radians(float(angle_deg))
    return (math.cos(a), math.sin(a), 0.0)


def cuke_facet_point(h=CUKE_H, r=CUKE_R, zf=0.5, facet=1, profile=None, offset=0.0,
                     segs=CUKE_SEGS, phase=None):
    """(surface point, outward normal) at the centre of facet `facet`."""
    a = cuke_facet_angle(facet, segs, phase)
    rad = cuke_radius(zf, profile) * r * math.cos(math.pi / float(segs)) + offset
    return ((math.cos(a) * rad, math.sin(a) * rad, zf * h),
            (math.cos(a), math.sin(a), 0.0))


def cuke_stud_slots(rows=6, per_row=3, z0=0.14, z1=0.88, segs=CUKE_SEGS, stagger=True,
                    seed=1, jitter=0.018, skip=0.0):
    """Deterministic (height fraction, facet index) pairs for a body's speckles.

    Studs snap to facet CENTRES so they lie flat on the skin.  Consecutive rows are
    rolled round by half a step so the pattern reads scattered rather than gridded."""
    rng = random.Random(seed)
    step = max(1, int(round(segs / float(max(1, per_row)))))
    out = []
    for i in range(rows):
        zf = z0 + (z1 - z0) * (i / float(max(1, rows - 1)))
        zf += rng.uniform(-jitter, jitter)
        base = (i * (step // 2 + 1)) if stagger else 0
        for j in range(per_row):
            if skip > 0.0 and rng.random() < skip:
                continue
            out.append((min(1.0, max(0.0, zf)), (base + j * step) % segs))
    return out


def wrap_frames(h=CUKE_H, r=CUKE_R, z0=0.10, z1=0.92, turns=1.6, n=34, phase_deg=-40.0,
                profile=None, offset=0.10, segs=CUKE_SEGS, flat=True):
    """(point, outward normal) frames spiralling up a body - feed to `ribbon` / `tube`."""
    out = []
    for i in range(n):
        t = i / float(n - 1)
        zf = z0 + (z1 - z0) * t
        ang = phase_deg + 360.0 * turns * t
        out.append((cuke_point(h, r, zf, ang, profile, offset, segs, flat),
                    cuke_normal(ang)))
    return out


def spiral_pts(center=(0, 0, 0), r0=0.05, r1=0.40, turns=1.6, n=16, plane="XZ",
               phase_deg=0.0, rise=0.0):
    """A flat spiral - the curled tendril at the end of a vine, a galaxy arm."""
    cx, cy, cz = center
    out = []
    for i in range(n):
        t = i / float(n - 1)
        a = math.radians(phase_deg) + 2 * math.pi * turns * t
        rr = r0 + (r1 - r0) * t
        u, v = math.cos(a) * rr, math.sin(a) * rr
        w = rise * t
        if plane == "XZ":
            out.append((cx + u, cy + w, cz + v))
        elif plane == "YZ":
            out.append((cx + w, cy + u, cz + v))
        else:
            out.append((cx + u, cy + v, cz + w))
    return out


def ring_xy(n, radius, phase_deg=0.0, center=(0.0, 0.0)):
    """n points evenly round a circle in XY - petals, pearls, bolts, fence posts."""
    out = []
    for i in range(n):
        a = math.radians(phase_deg) + 2 * math.pi * i / float(n)
        out.append((center[0] + math.cos(a) * radius, center[1] + math.sin(a) * radius))
    return out
