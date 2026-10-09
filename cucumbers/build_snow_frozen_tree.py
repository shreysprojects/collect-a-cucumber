"""Snow: Frozen Tree - a brown tree whose foliage is big cut-cucumber slices, under snow."""
import bmesh, math

COLLECTION = "SnowFrozenTree"
NOTES = ("An 11.4-stud winter tree whose FOLIAGE IS CUT CUCUMBER.  A two-step brown "
         "snow_bark plinth and a tapering blocky bark trunk, speckled with cuke_stud "
         "green squares, throw out THREE cuke_green boughs, and on the end of each "
         "stands a big cut-slice disc facing +Y: cuke_green rim with green speckles, "
         "cuke_pale cut face, cuke_seed pips.  Two large discs read as the crown - "
         "r 1.58 high and central, r 1.42 low on the screen-left bough - with a smaller "
         "r 1.08 one set back on the screen-right.  A snow_white band of snow caps the "
         "top arc of every disc and spills tongues over both of its faces, another slab "
         "sits on the trunk head and a drift gathers on the plinth, and pale snow_ice_lt "
         "icicles (Ice, transparency 0.18) hang in a row under each disc.  No blue "
         "cucumber anywhere: the fruit is green, the ice and snow only sit on it.  "
         "Footprint ~6.2 x 4.7, top of the highest snow cap ~11.4.  Faces +Y.  Seven "
         "parts: Trunk, BranchesRims, Studs, Faces, Seeds, Snow, Icicles.")

# ---- trunk -------------------------------------------------------------------
BASE_TOP_W, BASE_H, BASE_STEPS, BASE_GROW = 1.50, 1.35, 2, 1.38
TRUNK_Z0, TRUNK_Z1 = 1.35, 6.30
TRUNK_W0, TRUNK_W1, TRUNK_BLOCKS = 1.34, 0.96, 3

# ---- the slice foliage -------------------------------------------------------
# x, y, z, radius, thick, lean, turn, bough z0, bough w0, bough w1, icicles, ic len, seed
DISCS = [
    (0.18, -0.20, 9.62, 1.58, 0.52, -4.0, -10.0, 5.15, 0.64, 0.44, 4, 0.72, 3),
    (1.84, -1.30, 6.72, 1.42, 0.50, 6.0, -27.0, 4.30, 0.58, 0.40, 4, 0.66, 7),
    (-1.96, 1.70, 7.74, 1.08, 0.44, -5.0, 25.0, 4.95, 0.52, 0.36, 3, 0.58, 11),
]

SLICE_SEGS = 12                 # a 12-sided rim reads round at r 1.5

# snow tongues hanging off a disc's cap: (local angle, width, length)
TONGUES = ((232.0, 0.30, 0.46), (272.0, 0.26, 0.62), (310.0, 0.32, 0.40))


def _trunk_blocks():
    """The (lo, hi) corners blocky_trunk builds, so the speckles land on them."""
    sh = (TRUNK_Z1 - TRUNK_Z0) / float(TRUNK_BLOCKS)
    out = []
    for i in range(TRUNK_BLOCKS):
        t = (i + 0.5) / float(TRUNK_BLOCKS)
        w = TRUNK_W0 + (TRUNK_W1 - TRUNK_W0) * t
        z0 = TRUNK_Z0 + i * sh
        out.append(((-w / 2.0, -w / 2.0, z0), (w / 2.0, w / 2.0, z0 + sh + 0.014)))
    return out


def _bough(d):
    """Trunk-side and disc-side ends of the bough carrying disc `d` (ends INSIDE it)."""
    x, y, z, r, bz0 = d[0], d[1], d[2], d[3], d[7]
    return (0.0, 0.0, bz0), (x * 0.96, y * 0.94, z - r * 0.62)


def _norm(v):
    L = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return (0.0, 0.0, 1.0) if L < 1e-9 else (v[0] / L, v[1] / L, v[2] / L)


def _perp(d, ref):
    """`ref` with the component along `d` removed - None when the two are near-parallel."""
    k = d[0] * ref[0] + d[1] * ref[1] + d[2] * ref[2]
    v = (ref[0] - k * d[0], ref[1] - k * d[1], ref[2] - k * d[2])
    L = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return None if L < 0.18 else (v[0] / L, v[1] / L, v[2] / L)


def _disc_pt(x, y, z, r, turn, ang_deg, k=1.0):
    """A world point on a STANDING disc: local angle 90 is its bottom, 270 its top.

    slice_stand maps the disc's local +X onto world X (swung by `turn`) and its local
    +Y onto world -Z, so `ang` runs clockwise seen from the camera."""
    t, a = math.radians(turn), math.radians(ang_deg)
    lx, ly = math.cos(a) * r * k, math.sin(a) * r * k
    return (x + lx * math.cos(t), y + lx * math.sin(t), z - ly)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    blocks = _trunk_blocks()
    mats = [D.slice_stand((d[0], d[1], d[2]), lean_deg=d[5], turn_deg=d[6]) for d in DISCS]

    # ---- plinth + bark trunk ----------------------------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=BASE_STEPS, grow=BASE_GROW,
                   bevel=0.08)
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=TRUNK_BLOCKS,
                   bevel=0.08)
    D.new_obj("Trunk", bm, c, D.C("snow_bark"), rbx_material="Wood")

    # ---- green boughs + the slice rims they carry (same colour -> one object)
    bm = bmesh.new()
    for d in DISCS:
        a, b = _bough(d)
        D.branch_box(bm, a, b, d[8], d[9], bevel=0.05)
    for m, d in zip(mats, DISCS):
        D.slice_disc(bm, radius=d[3], thick=d[4], segs=SLICE_SEGS, matrix=m, bevel=0.06)
    D.new_obj("BranchesRims", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the set's speckle: on the bark, on the boughs, on the rims --------
    bm = bmesh.new()
    for i, (lo, hi) in enumerate(blocks):
        D.box_studs(bm, lo, hi, faces=("-y", "+x", "-x"), grid=(1, 2), size=0.30,
                    rise=0.06, seed=21 + i, margin=0.30, bevel=0.0)
    for i, d in enumerate(DISCS):
        a, b = _bough(d)
        dd = _norm((b[0] - a[0], b[1] - a[1], b[2] - a[2]))
        for j, t in enumerate((0.34, 0.62, 0.86)):
            ref = (0.0, 0.0, 1.0) if (i + j) % 2 else (0.0, -1.0, 0.0)
            n = _perp(dd, ref) or _perp(dd, (0.0, -1.0, 0.0)) or (1.0, 0.0, 0.0)
            w = d[8] + (d[9] - d[8]) * t
            p = (a[0] + (b[0] - a[0]) * t + n[0] * w * 0.48,
                 a[1] + (b[1] - a[1]) * t + n[1] * w * 0.48,
                 a[2] + (b[2] - a[2]) * t + n[2] * w * 0.48)
            D.stud_patch(bm, p, n, size=0.22, rise=0.05, bevel=0.0)
    for m, d in zip(mats, DISCS):
        D.slice_studs(bm, radius=d[3], thick=d[4], segs=SLICE_SEGS, matrix=m, n=5,
                      size=0.26, rise=0.05, seed=d[12], bevel=0.0)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the pale cut faces (both sides - this is foliage, seen from behind too)
    bm = bmesh.new()
    for m, d in zip(mats, DISCS):
        D.slice_face(bm, radius=d[3], thick=d[4], segs=SLICE_SEGS, matrix=m, inset=0.12,
                     proud=0.035, both=True)
    D.new_obj("Faces", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    # ---- pips, on the camera side only ------------------------------------
    bm = bmesh.new()
    for m, d in zip(mats, DISCS):
        D.slice_seeds(bm, radius=d[3], thick=d[4], matrix=m, n=5, size=0.20 * d[3],
                      ring=0.42, rise=0.03, proud=0.055, both=False, phase_deg=18.0,
                      bevel=0.02)
    D.new_obj("Seeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    # ---- snow: a band over every disc, the trunk head, a drift at the foot --
    bm = bmesh.new()
    for m, d in zip(mats, DISCS):
        r, th = d[3], d[4]
        out = D.arc_pts((0.0, 0.0), r + 0.13, 214.0, 326.0, n=7)
        inn = D.arc_pts((0.0, 0.0), r - 0.34, 214.0, 326.0, n=7)
        D.prism(bm, out + list(reversed(inn)), -(th / 2.0 + 0.08), th / 2.0 + 0.08,
                matrix=m)
        for (ang, w, L) in TONGUES:
            ax = math.cos(math.radians(ang)) * (r - 0.26)
            ay = math.sin(math.radians(ang)) * (r - 0.26)
            D.prism(bm, D.rounded_rect_pts(w, L, 0.09, segs=2, center=(ax, ay + L / 2.0)),
                    -(th / 2.0 + 0.055), th / 2.0 + 0.055, matrix=m)
    lo, hi = blocks[-1]
    D.snow_slab(bm, lo, hi, thick=0.30, overhang=0.11, drips=3, drip_len=0.44, seed=5,
                bevel=0.07, sides=("-y",))
    bw = BASE_TOP_W * BASE_GROW / 2.0 - 0.03
    D.snow_slab(bm, (-bw, -bw, 0.0), (bw, bw, BASE_H / float(BASE_STEPS)), thick=0.17,
                overhang=0.09, drips=2, drip_len=0.26, seed=9, bevel=0.06, sides=("-y",))
    D.new_obj("Snow", bm, c, D.C("snow_white"), rbx_material="Snow")

    # ---- icicles hanging under each disc ----------------------------------
    bm = bmesh.new()
    for d in DISCS:
        x, y, z, r, turn = d[0], d[1], d[2], d[3], d[6]
        a = _disc_pt(x, y, z, r, turn, 46.0, 0.96)
        b = _disc_pt(x, y, z, r, turn, 134.0, 0.96)
        D.icicle_row(bm, a, b, count=d[10], length=d[11], radius=0.115, seed=d[12],
                     vary=0.38, segs=5)
    D.new_obj("Icicles", bm, c, D.C("snow_ice_lt"), rbx_material="Ice", transparency=0.18,
              roughness=0.32)

    return c
