"""Ornamental garden pond: an irregular earth-and-grass rim holding a water surface at
z 0.5, with three koi cruising just under it, lily pads, two lotus and a cattail stand.
Faces +Y.  The whole pond is a RAISED feature - it needs no hole dug for it."""
import bmesh, math, random

COLLECTION = "Pond"
NOTES = (
    "RAISED FEATURE - NOTHING SITS BELOW z = 0, so the pond drops straight onto flat "
    "ground with no excavation and no hole to dig.  A plinth slab (0 - 0.12) carries an "
    "earth rim whose crest RISES AND FALLS between 0.66 and 0.91 and is capped with turf "
    "to 0.79 - 1.04, and THAT RIM is what holds the water: the surface sits at z 0.50, "
    "about 0.8 above the ground the prop stands on.  Footprint 9.2 (x) x 6.6 (y) at the "
    "plinth from a 9-point D.ngon_pts ring jittered hard with random.Random(20260909) - "
    "ellipse-normalised radii run 0.71 to 1.18 - and then scaled back to that footprint, "
    "so the outline is a genuinely irregular shore, NOT a polygon.  ONE POINT (index "
    "BAY_AT) is hauled right in, which makes the ring CONCAVE on the +Y (camera) side: a "
    "bay in the waterline with a spit of turf reaching into it.  Open water 7.0 x 5.0; "
    "the bank between rim and water is 0.4 - 1.3 wide.  Pond mass is 1.45 tall at the "
    "crown of the tallest boulder.  "
    "THE ONE THING THAT BREAKS 1.45 is the cattail stand at the -X end (screen RIGHT "
    "from the +Y viewpoint), whose tallest whip reaches z 2.3 - delete Pond.Reeds and "
    "Pond.CattailHeads together if the prop must stay under 1.5.  "
    "The floor (Pond.Bed, water_deep) tops out at z 0.16, so the water column is 0.34 "
    "deep.  Fish2 and Fish3 are fully submerged; FISH1 IS THE EXCEPTION - its dorsal fin "
    "breaks the surface at z 0.53 on purpose, so the pond has one hard unveiled "
    "silhouette on top of the water.  "
    "ANIMATABLE PARTS: Fish1 / Fish2 / Fish3 are one object each, anchored at the "
    "PIVOTS points at z 0.34 - swim them by rotating/translating about those, keeping "
    "z between 0.30 and 0.38 (Fish1's fin then stays 0.01 - 0.07 proud of the water).  "
    "FishMarks (the two small white saddles on each orange koi) and "
    "FishEyes are shared objects; merge each fish's share into its body before "
    "animating, or animate the three fish as one group.  LilyPads and LilyLotus are "
    "separate objects so the pads can bob.  Everything else is static scenery."
)
PIVOTS = {
    "Fish1": (1.42, 0.16, 0.34),
    "Fish2": (-1.04, -1.14, 0.34),
    "Fish3": (-2.12, 0.16, 0.34),
    "WaterSurface": (0.0, 0.0, 0.50),
}

# ---------------------------------------------------------------- shape constants
N = 9                  # points around the pond outline - few enough that each shore
                       # edge is long, so the irregularity still reads at 40 studs
SEED = 20260909
RX, RY = 5.49, 3.93    # base ellipse of the OUTER rim, before jitter
SPAN_X, SPAN_Y = 8.96, 6.36   # the jittered ring is scaled back to this footprint
BAY_AT = 2             # this point is hauled in to BAY_R -> the one true concavity
BAY_R = 0.46

Z_PLINTH = 0.12        # top of the ground slab the whole thing stands on
Z_BED = 0.16           # top of the dark pond floor
Z_WATER = 0.50         # the water surface
Z_PAD = 0.492          # lily pads straddle the surface
FISH_Z = 0.34          # koi body centres, suspended just under the water

# the viewer stands on +Y, so +X is screen LEFT and the cattails at -X read right-hand


# ---------------------------------------------------------------- outline
def _rings(D):
    """A jittered D.ngon_pts ring -> (outer, inner, per-point crest height).

    Each point gets a WIDE radial stretch (0.70 - 1.20 of the base ellipse) and a small
    angular nudge - well under the 40 deg point spacing, so the ring stays star-shaped
    about its centre and every polygon built from it stays simple.  The inner waterline
    is each point pulled back toward the centre by its own fraction, so the bank is wide
    in some places and narrow in others rather than a constant-width doughnut, and the
    crest height is drawn per point over a 0.36 band so the bank visibly rises and falls
    instead of sitting level (the low points still clear the water at 0.50 by 0.16).

    The point at BAY_AT is hauled in to BAY_R, well inside the line joining its
    neighbours: that is the one genuine CONCAVITY, a bay bitten out of the near shore
    with the turf between its two edges reaching into the water as a spit.  A regular
    polygon is exactly what this outline must not be.

    Because the jitter is wide the raw ring would swing wildly in size, so it is scaled
    back onto SPAN_X x SPAN_Y and centred - the shape is random, the footprint is not."""
    rng = random.Random(SEED)
    base = D.ngon_pts(N, 1.0, phase=0.13)
    outer, inner, ptop = [], [], []
    for k, (bx, by) in enumerate(base):
        a = math.atan2(by, bx) + rng.uniform(-0.15, 0.15)
        r = rng.uniform(0.70, 1.20)
        f = rng.uniform(0.72, 0.81)
        if k == BAY_AT:
            r = BAY_R
        ox, oy = math.cos(a) * RX * r, math.sin(a) * RY * r
        outer.append((ox, oy))
        inner.append((ox * f, oy * f))
        ptop.append(0.58 + rng.uniform(0.0, 0.36))
    xs = [p[0] for p in outer]
    ys = [p[1] for p in outer]
    cx, cy = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5
    sx, sy = SPAN_X / (max(xs) - min(xs)), SPAN_Y / (max(ys) - min(ys))
    outer = [((x - cx) * sx, (y - cy) * sy) for (x, y) in outer]
    inner = [((x - cx) * sx, (y - cy) * sy) for (x, y) in inner]
    return outer, inner, ptop


def _scaled(ring, f):
    return [(p[0] * f, p[1] * f) for p in ring]


def _along(a, b, u):
    """A point u of the way from a to b (u > 1 overshoots past b)."""
    return tuple(a[k] + (b[k] - a[k]) * u for k in range(3))


def _crest(rings, t, f):
    """(x, y, z) on the rim.  `t` is a float index around the ring, `f` crosses the bank:
    0 = the waterline, 1 = the outer edge, negative = out over the water."""
    outer, inner, ptop = rings
    i = int(math.floor(t)) % N
    j = (i + 1) % N
    u = t - math.floor(t)
    ix = inner[i][0] + (inner[j][0] - inner[i][0]) * u
    iy = inner[i][1] + (inner[j][1] - inner[i][1]) * u
    ox = outer[i][0] + (outer[j][0] - outer[i][0]) * u
    oy = outer[i][1] + (outer[j][1] - outer[i][1]) * u
    z = ptop[i] + (ptop[j] - ptop[i]) * u
    return (ix + (ox - ix) * f, iy + (oy - iy) * f, z)


# ---------------------------------------------------------------- content tables
# boulders on the rim.  f < 0 leans them out over the water; three are twice the size
# of the rest so the ring never reads as a bead necklace.
# every `t` below is an index into the N-point ring, so they were all rescaled by 9/12
# when the ring dropped from 12 points to 9 - the bank positions are unchanged, the
# gap at t 3.8 - 5.6 is still the stretch of shore the cattails own.
ROCKS = [
    # t      f      r    seed  scale                rot(deg)        big    dark
    (0.22,  0.40, 0.46,   3, (1.20, 0.95, 0.68), (6, -9, 22),    True,  False),
    (0.82,  0.08, 0.30,  11, (1.00, 1.15, 0.85), (-8, 5, 61),    False, True),
    (1.46, -0.12, 0.34,  17, (1.25, 0.90, 0.70), (10, 12, -34),  False, False),
    (2.02,  0.52, 0.27,  23, (0.95, 1.05, 0.95), (4, -6, 15),    False, True),
    (2.62,  0.22, 0.44,  29, (1.15, 1.00, 0.70), (-5, 8, 128),   True,  False),
    (3.26,  0.46, 0.25,  31, (1.10, 0.85, 0.90), (12, -4, 77),   False, True),
    (3.78, -0.16, 0.31,  37, (1.30, 0.88, 0.68), (7, 10, -52),   False, False),
    (5.58,  0.34, 0.28,  41, (0.92, 1.20, 0.86), (-9, 3, 96),    False, True),
    (6.00,  0.14, 0.42,  43, (1.10, 1.05, 0.66), (5, -7, 41),    True,  False),
    (7.42, -0.10, 0.33,  53, (1.22, 0.92, 0.70), (8, -11, 63),   False, False),
    (8.25,  0.30, 0.29,  59, (0.98, 1.12, 0.88), (-4, 6, 112),   False, True),
]

# one koi per object so a game can swim them independently.  `sail` is the height of the
# dorsal fin above the body centre line: Fish1's is tall enough to CUT THE SURFACE at
# z 0.53, which is the one koi silhouette that survives being read through the water.
FISH = [
    # name    x      y     heading  pitch  roll  scale  colour          saddles  sail
    ("Fish1",  1.42,  0.16,  -34,     3,     7,  1.00, "accent_orange", True,  0.145),
    ("Fish2", -1.04, -1.14,  152,    -2,    -6,  0.94, "flower_white",  False, 0.090),
    ("Fish3", -2.12,  0.16,   68,     3,    -7,  0.84, "accent_orange", True,  0.090),
]

TAIL = [(0.02, 0.0), (-0.30, 0.14), (-0.20, 0.02), (-0.30, -0.12)]   # (fore-aft, up)

# the two white saddles, as (fore-aft, up, radius).  They are DELIBERATELY small - the
# body's own half-extents are 0.187 (across) x 0.52 (long) x 0.127 (deep), so at x-scale
# MARK_XS these cover about a quarter of the back and the koi still reads as orange.
MARKS = [(0.16, 0.101, 0.09), (-0.14, 0.107, 0.07)]
MARK_XS = 0.55

PADS = [
    # cx     cy     r    notch facing (deg)
    (-2.00,  1.20, 0.68,  34),
    (-0.55,  1.76, 0.46, 152),
    (2.25,   0.92, 0.52, 268),
    (0.65,  -1.53, 0.58, 205),
    (-2.10, -0.45, 0.40,  96),
]

# x, y, r, phase, base z (the one sitting on a pad has to clear that pad's raised heart)
LOTUS = [(-2.00, 1.32, 0.36, 0.20, 0.575), (1.15, -1.84, 0.30, 1.10, 0.520)]

# spread along the -X shore, no two heads at the same height, one stem left bare
CATTAILS = [
    # t     f     height  lean_x  lean_y  head    head top
    (4.02, 0.30, 1.27,  0.10,  0.14, True),    # 1.87
    (4.26, 0.55, 0.93, -0.08,  0.10, True),    # 1.59
    (4.52, 0.20, 1.06,  0.14, -0.06, True),    # 1.74
    (4.72, 0.44, 0.70,  0.06,  0.16, False),   # bare stem
    (4.96, 0.62, 1.31, -0.12, -0.10, True),    # 2.01
    (5.18, 0.34, 0.66,  0.16,  0.04, True),    # 1.45
]
HEAD_R = 0.055         # a cattail is a SLENDER sausage: 0.11 across, 0.4 - 0.6 long
HEAD_TOP = 0.90        # the brown head ends here (the stem dies inside its base)...
WHIP_TOP = 1.12        # ...and a thin green whip carries on out of its tip to here

TUFTS = [(1.16, 0.55), (3.05, 0.44), (7.05, 0.44)]
BLADE = [(0.10, 0.06, 0.42), (-0.09, 0.12, 0.36), (0.04, -0.13, 0.48),
         (-0.14, -0.05, 0.30)]


# ---------------------------------------------------------------- build
def build(D):
    """D is the imported proplib module.  Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    rings = _rings(D)
    outer, inner, ptop = rings

    # ---- bank: the ground slab plus the earth rim wall, one dirt object -----------
    # The slab is 3 % wider than the rim so the pond stands on a small ledge instead of
    # a dead-vertical wall, and it doubles as the mud under the water.
    bm = bmesh.new()
    D.prism(bm, _scaled(outer, 1.03), 0.0, Z_PLINTH)
    for i in range(N):
        j = (i + 1) % N
        top = (ptop[i] + ptop[j]) * 0.5
        D.prism(bm, [inner[i], inner[j], outer[j], outer[i]], 0.0, top)
    D.new_obj("Bank", bm, c, D.C("dirt"), rbx_material="Ground", roughness=0.92)

    # ---- pond floor: the dark value the translucent water is read against ---------
    bm = bmesh.new()
    D.prism(bm, _scaled(inner, 1.02), 0.10, Z_BED)
    D.new_obj("Bed", bm, c, D.C("water_deep"), rbx_material="Slate", roughness=0.75)

    # ---- water: one flat sheet, tucked a hair under the muddy lip ----------------
    # roughness 0.5, not a mirror: a glossy sheet catches the whole sky in one specular
    # lobe and that veil is what greys out the koi underneath it.
    bm = bmesh.new()
    D.ngon_face(bm, _scaled(inner, 1.008), Z_WATER)
    D.new_obj("Water", bm, c, D.C("water_mid"), rbx_material="Glass",
              transparency=0.50, roughness=0.50)

    # ---- turf cap + three grass tufts --------------------------------------------
    # Held back from the waterline so a strip of bare earth shows as a muddy bank lip.
    bm = bmesh.new()
    gi, go = _scaled(inner, 1.055), _scaled(outer, 1.008)
    for i in range(N):
        j = (i + 1) % N
        top = (ptop[i] + ptop[j]) * 0.5
        D.prism(bm, [gi[i], gi[j], go[j], go[i]], top - 0.07, top + 0.13)
    for (t, f) in TUFTS:
        bx, by, bz = _crest(rings, t, f)
        for (dx, dy, h) in BLADE:
            D.spike(bm, (bx + dx * 0.35, by + dy * 0.35, bz + 0.10),
                    (bx + dx, by + dy, bz + 0.10 + h), 0.055, segs=3)
    D.new_obj("RimGrass", bm, c, D.C("grass"), rbx_material="LeafyGrass", roughness=0.8)

    # ---- boulders, split by value so the ring has light and shade ----------------
    bm_mid, bm_dark = bmesh.new(), bmesh.new()
    for (t, f, r, seed, sc, rot, big, dark) in ROCKS:
        x, y, z = _crest(rings, t, f)
        z += (0.11 if f > 0.05 else 0.0) + r * sc[2] * 0.30
        D.rock(bm_dark if dark else bm_mid, (x, y, z), r, seed=seed,
               jitter=0.28, subdiv=(1 if big else 0), scale=sc,
               rot=D.rot_euler(rx=rot[0], ry=rot[1], rz=rot[2]))
    D.new_obj("RocksMid", bm_mid, c, D.C("stone_mid"), rbx_material="Slate", roughness=0.85)
    D.new_obj("RocksDark", bm_dark, c, D.C("stone_dark"), rbx_material="Slate", roughness=0.88)

    # ---- three koi -----------------------------------------------------------------
    fin = D.rot_euler(rx=90, rz=90)          # lays a (fore-aft, up) profile in the YZ plane
    bm_mark, bm_eye = bmesh.new(), bmesh.new()
    for (name, fx, fy, head, pitch, roll, s, colour, saddles, sail) in FISH:
        mf = D.place((fx, fy, FISH_Z),
                     D.rot_euler(rx=pitch, ry=roll, rz=head), scale=s)
        bm = bmesh.new()
        D.xform(bm, D.ico(bm, (0, 0, 0), 0.52, subdiv=1, scale=(0.36, 1.0, 0.245)), mf)
        D.prism(bm, TAIL, -0.035, 0.035, matrix=mf @ D.place((0.0, -0.50, 0.0), fin))
        D.prism(bm, [(0.24, 0.0), (-0.28, 0.0), (-0.11, sail)], -0.03, 0.03,
                matrix=mf @ D.place((0.0, 0.0, 0.05), fin))
        D.new_obj(name, bm, c, D.C(colour), roughness=0.34)
        for ex in (0.155, -0.155):
            D.xform(bm_eye, D.ico(bm_eye, (ex, 0.34, 0.045), 0.055, subdiv=0), mf)
        if saddles:
            for (my, mz, mr) in MARKS:
                D.xform(bm_mark, D.ico(bm_mark, (0.0, my, mz), mr, subdiv=0,
                                       scale=(MARK_XS, 1.35, 0.30)), mf)
    D.new_obj("FishMarks", bm_mark, c, D.C("flower_white"), roughness=0.34)
    D.new_obj("FishEyes", bm_eye, c, D.C("plastic_black"), roughness=0.28)

    # ---- lily pads: a disc with a wedge notch bitten out of it -------------------
    # leaf_DARK at a matte 0.8, so a pad reads as a hole punched in the water rather
    # than a white paper cut-out: a flat up-facing plane at roughness 0.4 catches the
    # whole key-light lobe and blows out to pure white.  Each pad also carries a raised
    # heart so its top is not one unbroken specular plane.
    bm = bmesh.new()
    for k, (cx, cy, r, notch) in enumerate(PADS):
        pts = D.arc_pts((cx, cy), r, notch + 26, notch + 334, n=7) + [(cx, cy)]
        lift = 0.008 * (k % 3)
        D.prism(bm, pts, Z_PAD + lift, Z_PAD + lift + 0.046)
        D.prism(bm, D.ngon_pts(6, r * 0.34, phase=math.radians(notch), center=(cx, cy)),
                Z_PAD + lift + 0.040, Z_PAD + lift + 0.074)
    D.new_obj("LilyPads", bm, c, D.C("leaf_dark"), rbx_material="Grass", roughness=0.8)

    # ---- two lotus: a six-petal star with a tighter bud stacked on top -----------
    bm = bmesh.new()
    for (lx, ly, r, ph, z0) in LOTUS:
        D.prism(bm, D.star_pts(6, r, r * 0.40, phase=ph, center=(lx, ly)), z0, z0 + 0.08)
        D.prism(bm, D.star_pts(4, r * 0.54, r * 0.22, phase=ph + 0.6, center=(lx, ly)),
                z0 + 0.06, z0 + 0.19)
    D.new_obj("LilyLotus", bm, c, D.C("flower_pink"), roughness=0.42)

    # ---- cattail stand at the -X end (one stem deliberately left bare) -----------
    # A cattail's whole signature is proportion: a slender brown sausage roughly five
    # times as long as it is wide, with a thin green whip carrying on above it.  The
    # stem STOPS at the base of the head - run it to the tip and it pokes a green nub
    # out of the top and the head reads as a fence-post cap.
    bm_stem, bm_head = bmesh.new(), bmesh.new()
    for (t, f, h, lx, ly, head) in CATTAILS:
        bx, by, bz = _crest(rings, t, f)
        base = (bx, by, bz + 0.06)
        tip = (bx + lx, by + ly, bz + 0.06 + h)
        if not head:
            D.cyl(bm_stem, base, tip, 0.048, segs=5, r2=0.026)
            continue
        length = math.sqrt((lx * lx) + (ly * ly) + (h * h))
        hl = (0.16 + 0.32 * h) / length              # head length as a fraction of the stem
        u0 = HEAD_TOP - hl
        # the stem dies inside the bottom of the head - 0.027 against the head's 0.042,
        # clear even facet-to-facet - and the whip starts inside its tip, so no green
        # nub can ever show through the brown
        D.cyl(bm_stem, base, _along(base, tip, u0 + hl * 0.14), 0.048, segs=5, r2=0.024)
        D.tube(bm_head, [_along(base, tip, u0),
                         _along(base, tip, u0 + hl * 0.14),
                         _along(base, tip, HEAD_TOP - hl * 0.12),
                         _along(base, tip, HEAD_TOP)],
               [0.042, HEAD_R, HEAD_R, 0.018], segs=5)
        D.spike(bm_stem, _along(base, tip, HEAD_TOP - hl * 0.05),
                _along(base, tip, WHIP_TOP), 0.018, segs=4)
    D.new_obj("Reeds", bm_stem, c, D.C("stem_green"), rbx_material="Grass", roughness=0.7)
    D.new_obj("CattailHeads", bm_head, c, D.C("seed_brown"), rbx_material="Fabric",
              roughness=0.85)

    return c
