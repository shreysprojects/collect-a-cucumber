"""Three toy trees in one line-up: a broad Oak, a stacked Pine and a young fruit Sapling.

Every variant is built as if it were standing on its own origin and then offset along X,
so `A_*` / `B_*` / `C_*` each drop into a game independently.  All three face +Y: the
oak's sun-lit crown, the sapling's front fruit and the pine's fullest skirt are on +Y.
"""
import bmesh, math, random

COLLECTION = "Tree"
NOTES = ("Three separable trees, prefixed A_/B_/C_.  A Oak: 11.0 tall, crown ~7 wide, "
         "trunk footprint 3.1 across at the roots, centred on x=+10.  B Pine: 12.9 tall, "
         "skirt 5.6 wide, centred on x=0.  C Sapling: 6.5 tall, crown 4.4 wide, centred "
         "on x=-9.5.  Move a variant by translating every part with its letter prefix; "
         "each one already sits with its trunk axis on its own declared x and on y=0, "
         "z=0.  No moving parts, no pit - all three stand on the ground plane.")

VARIANTS = {
    "A": {"name": "Oak",     "x":  10.0, "height": 11.0},
    "B": {"name": "Pine",    "x":   0.0, "height": 12.9},
    "C": {"name": "Sapling", "x":  -9.5, "height":  6.5},
}


# ---------------------------------------------------------------- helpers
SKIRT_SEED = 4021


def _pine_skirt(D, bm, rng, R, H, phase_deg):
    """One conifer skirt built about the origin: a cone whose underside is hollowed up
    into the mass (so the rim is the lowest edge) with the lower rim jittered so it never
    reads as a clean geometric cone.  64 tris at segs=8.

    The rim ring is the only jittered one, and a tight collar ring sits 0.07*H above it,
    so a displaced rim vert only bends that thin band - shear it across the whole flank
    and the cone side tears into a flat rectangular flap that reads as broken geometry."""
    prof = [(0.00, 0.26 * H),        # recessed underside apex - gives the droop
            (R,    0.00),            # the wide rim (jittered below)
            (0.95 * R, 0.07 * H),    # collar: keeps the jitter inside a 0.07*H band
            (0.80 * R, 0.36 * H),
            (0.44 * R, 0.68 * H),
            (0.00, H)]
    vs = D.lathe(bm, prof, segs=8, phase=math.radians(phase_deg))
    for v in vs[1:9]:                # profile point 1 is the rim ring: 8 verts
        f = rng.uniform(0.95, 1.04)
        v.co.x *= f
        v.co.y *= f
        v.co.z += rng.uniform(-0.06, 0.05)
    return vs


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    bark = D.C("log_bark")        # dark trunk
    root = D.C("wood_mid")        # lighter, sun-bleached root flare - clear value step
    young = D.C("wood_mid")       # the sapling's whole trunk is young bark
    mid = D.C("leaf_mid")
    light = D.C("leaf_light")
    dark = D.C("leaf_dark")
    blue = D.C("leaf_blue")
    fruit = D.C("flower_red")

    # ============================================================ A - OAK  (x = +10)
    ax = VARIANTS["A"]["x"]

    # trunk: a tapering 8-sided tube that wanders a little, forking into three stubs,
    # plus ONE snapped-off low limb on -x (screen right) so the tree is not symmetric.
    bm = bmesh.new()
    D.tube(bm, [(ax + 0.00,  0.00, 0.10),
                (ax + 0.10,  0.05, 1.75),
                (ax - 0.08,  0.00, 3.30),
                (ax + 0.12, -0.05, 4.60),
                (ax + 0.02,  0.05, 5.60)],
           [0.92, 0.74, 0.61, 0.50, 0.42], segs=8)
    for pts, radii in (
        ([(ax + 0.02,  0.02, 5.05), (ax + 0.72,  0.30, 6.15), (ax + 1.28,  0.48, 6.95)],
         [0.34, 0.23, 0.13]),
        ([(ax - 0.02,  0.00, 5.15), (ax - 0.62, -0.32, 6.25), (ax - 1.10, -0.52, 7.15)],
         [0.32, 0.22, 0.12]),
        ([(ax + 0.00,  0.06, 5.45), (ax + 0.14,  0.72, 6.45), (ax + 0.22,  1.18, 7.30)],
         [0.30, 0.20, 0.11]),
        ([(ax - 0.30,  0.05, 3.20), (ax - 1.30,  0.35, 3.85), (ax - 2.15,  0.55, 4.15)],
         [0.30, 0.20, 0.16]),                      # the broken limb - blunt, no leaves
    ):
        D.tube(bm, pts, radii, segs=5)
    D.new_obj("A_Trunk", bm, c, bark, rbx_material="Wood", roughness=0.85)

    # flared root base: an octagonal skirt plus four uneven surface roots
    bm = bmesh.new()
    D.cyl(bm, (ax, 0.0, 0.00), (ax, 0.0, 0.90), 1.55, segs=8, r2=0.98)
    for ang, L in ((22, 2.10), (108, 1.75), (196, 2.30), (292, 1.90)):
        ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        D.tube(bm, [(ax + ca * 0.80, sa * 0.80, 0.72),
                    (ax + ca * L * 0.60, sa * L * 0.60, 0.38),
                    (ax + ca * L, sa * L, 0.20)],
               [0.40, 0.28, 0.15], segs=4)
    D.new_obj("A_Roots", bm, c, root, rbx_material="Wood", roughness=0.9)

    # crown: ~7 wide and sitting down over the fork so it reads as a broad round oak and
    # not a lollipop - a main mass of four blobs plus a lower, wider skirt of three that
    # swallows every upper branch tip (6.95 - 7.30), then a lighter cap on the +Y face
    bm = bmesh.new()
    D.foliage(bm, (ax + 0.05, -0.15, 7.95), 2.80, seed=7, blobs=4, spread=0.46,
              jitter=0.24, subdiv=1, scale=(1.12, 1.00, 0.90), flatten=0.90)
    D.foliage(bm, (ax + 0.00, -0.20, 6.75), 2.10, seed=11, blobs=3, spread=0.58,
              jitter=0.24, subdiv=1, scale=(1.15, 1.00, 0.85), flatten=0.85)
    D.new_obj("A_CrownBody", bm, c, mid, rbx_material="LeafyGrass", roughness=0.9)

    bm = bmesh.new()
    D.foliage(bm, (ax + 0.20, 1.35, 9.05), 1.55, seed=13, blobs=2, spread=0.50,
              jitter=0.22, subdiv=1, scale=(1.05, 1.00, 0.90), flatten=0.90)
    D.new_obj("A_CrownSun", bm, c, light, rbx_material="LeafyGrass", roughness=0.9)

    # ============================================================ B - PINE  (x = 0)
    bx = VARIANTS["B"]["x"]

    bm = bmesh.new()
    D.cyl(bm, (bx, 0.0, 0.00), (bx, 0.0, 0.55), 1.15, segs=6, r2=0.86)
    D.tube(bm, [(bx + 0.00, 0.00, 0.10),
                (bx + 0.05, 0.00, 3.40),
                (bx - 0.04, 0.00, 7.00),
                (bx + 0.02, 0.00, 9.70)],
           [0.82, 0.58, 0.40, 0.26], segs=6)   # stops inside the canopy: a bare pole
    for a, b, r in (((bx + 0.28,  0.12, 1.55), (bx + 0.95,  0.40, 1.20), 0.13),
                    ((bx - 0.32, -0.10, 0.95), (bx - 0.85, -0.30, 0.70), 0.11),
                    ((bx + 0.05,  0.34, 1.95), (bx + 0.10,  0.85, 1.75), 0.10)):
        D.cone(bm, a, b, r, segs=4)          # dead nubs on the bare lower trunk
    D.new_obj("B_Trunk", bm, c, bark, rbx_material="Wood", roughness=0.85)

    # five stacked skirts of falling radius, alternating dark / blue-green, each tipped a
    # degree or two off vertical and phase-rotated so no two rims line up.  The fifth
    # closes the top in foliage and carries the green leader cone up to the declared
    # 12.85 - the trunk must never show above the canopy or it reads as a lightning rod.
    skirts = ((2.05, 2.80, 2.85,  1.8, -1.2,  0.0, "dark"),
              (4.35, 2.28, 2.60, -1.5,  1.6, 22.0, "blue"),
              (6.35, 1.78, 2.35,  1.4,  1.0, 12.0, "dark"),
              (8.25, 1.25, 2.10, -1.2, -1.5, 30.0, "blue"),
              (9.55, 0.88, 2.20,  1.1,  0.8,  7.0, "dark"))
    for tone, part, hexcol in (("dark", "B_CanopyDark", dark), ("blue", "B_CanopyBlue", blue)):
        bm = bmesh.new()
        for i, (z0, R, H, rx, ry, ph, which) in enumerate(skirts):
            if which != tone:
                continue
            # a per-skirt stream: the rim jitter of one skirt must not correlate with the
            # next, or the same angular position gets displaced all the way up the stack
            vs = _pine_skirt(D, bm, random.Random(SKIRT_SEED + 37 * i), R, H, ph)
            D.xform(bm, vs, D.place((bx, 0.0, z0), D.rot_euler(rx=rx, ry=ry)))
        if tone == "dark":                       # the leader, in the top skirt's own tone
            D.cone(bm, (bx + 0.02, 0.01, 11.05), (bx + 0.05, 0.02, 12.85), 0.46, segs=6)
        D.new_obj(part, bm, c, hexcol, rbx_material="LeafyGrass", roughness=0.9)

    # ============================================================ C - SAPLING  (x = -9.5)
    cx = VARIANTS["C"]["x"]

    bm = bmesh.new()
    D.cyl(bm, (cx, 0.0, 0.00), (cx, 0.0, 0.42), 0.70, segs=6, r2=0.46)
    D.tube(bm, [(cx + 0.00,  0.00, 0.06),
                (cx + 0.06,  0.03, 1.10),
                (cx - 0.05,  0.00, 2.20),
                (cx + 0.08, -0.04, 3.10),
                (cx + 0.04,  0.02, 3.80)],
           [0.42, 0.34, 0.28, 0.24, 0.20], segs=6)
    for pts, radii in (
        ([(cx + 0.05, 0.02, 3.10), (cx + 0.55, 0.20, 3.85), (cx + 0.95, 0.32, 4.35)],
         [0.17, 0.12, 0.07]),
        ([(cx + 0.02, 0.00, 3.35), (cx - 0.45, -0.22, 4.05), (cx - 0.80, -0.38, 4.55)],
         [0.16, 0.11, 0.06]),
    ):
        D.tube(bm, pts, radii, segs=4)
    D.new_obj("C_Trunk", bm, c, young, rbx_material="Wood", roughness=0.85)

    bm = bmesh.new()
    D.foliage(bm, (cx + 0.10, -0.10, 4.65), 1.22, seed=21, blobs=2, spread=0.55,
              jitter=0.24, subdiv=1, scale=(1.10, 1.00, 0.95), flatten=0.90)
    D.new_obj("C_CrownBody", bm, c, mid, rbx_material="LeafyGrass", roughness=0.9)

    bm = bmesh.new()
    D.foliage(bm, (cx + 0.20, 0.62, 5.25), 0.85, seed=29, blobs=1, spread=0.50,
              jitter=0.22, subdiv=1, scale=(1.05, 1.00, 0.92), flatten=0.90)
    D.new_obj("C_CrownSun", bm, c, light, rbx_material="LeafyGrass", roughness=0.9)

    # fruit: every one sits ~0.86 of the way out of the leaf blob it grows from, so it is
    # buried well past its equator and only its outer cap breaks the leaves.  Hang one in
    # open air and it reads as a red pin floating beside the crown, not an apple.
    # Crown blobs (relative to cx): body (0.10, -0.10, 4.65) r 1.22 and its second lump
    # (0.35, 0.08, 4.78) r 0.76; sun lobe (0.20, 0.62, 5.25) r 0.85.
    bm = bmesh.new()
    for (fx, fy, fz, fr) in ((cx + 0.50,  0.79, 4.29, 0.27),   # front, low
                             (cx - 0.45,  0.78, 4.89, 0.25),   # front, screen right
                             (cx + 1.21,  0.17, 4.51, 0.28),   # screen-left edge
                             (cx - 0.98,  0.12, 4.93, 0.26),   # screen-right edge
                             (cx + 0.01,  0.94, 5.75, 0.24),   # top, on the sun lobe
                             (cx - 0.40, -1.02, 4.85, 0.24)):  # back
        D.uvsphere(bm, (fx, fy, fz), fr, segs=8, rings=4)
    D.new_obj("C_Fruit", bm, c, fruit, rbx_material="SmoothPlastic", roughness=0.35)

    return c
