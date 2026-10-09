"""Samurai: Torii Gate - a CUCUMBER-GREEN torii hung with a straw rope and a slice medallion."""
import bmesh, math

COLLECTION = "SamuraiToriiGate"
NOTES = ("A myojin-style torii built out of CUCUMBER, 9.5 wide x 1.9 deep x 9.5 tall, "
         "centred on x=0 y=0 and facing +Y.  Both pillars, the nuki crossbeam, the "
         "shimaki band and the upturned kasagi lintel are cucumber-green (cuke_green) "
         "and speckled all over with the set's raised cuke_stud squares - one on each "
         "face of each of the four pillar blocks, four along each side of the nuki, and "
         "five along each side of the kasagi, hand-placed so they follow its curve.  Two "
         "grey stepped stone bases (sam_rock_dk footing pad 1.9 square, sam_rock block "
         "1.26 square with its top at z 1.12) at x = +/-3.40 carry the pillars, which "
         "taper 0.86 -> 0.72 and run up to z 8.20 into the shimaki.  The nuki (8.6 x 0.52 "
         "x 0.52) passes through both pillars at z 5.30 and pokes 0.52 past each of them.  "
         "The kasagi's ends sweep UP so its tips reach z 9.50 - that upturn is the "
         "silhouette that says 'torii'.  Slung across the gate just under the shimaki is a "
         "tan shimenawa ROPE (sam_bamboo): a catenary tube from (3.4, 0, 7.4) to "
         "(-3.4, 0, 7.4) sagging 0.55, radius 0.12 at the ends swelling to 0.24 in the "
         "middle, tied off with a collar round each pillar at z 7.22-7.62, with two "
         "tapered tassels hanging from it at x = +/-1.9.  Hung on the middle of the rope "
         "and standing 0.44 proud of the gate plane is a CUCUMBER-SLICE MEDALLION - a "
         "cuke_green rim disc of radius 0.80 with cuke_stud rim speckles, a cuke_pale cut "
         "face and six cuke_seed pips on each side - centred at (0, 0.44, 6.40) and facing "
         "+Y, so the rope passes behind its upper third.  There is no plaque and no kanji, "
         "and no gold anywhere.  Walk-through opening ~5.9 wide, 5.0 clear under the nuki.  "
         "Nothing sits below z = 0.  Seven parts: Footings, Plinths, Gate, Studs, Rope, "
         "SliceFace, SliceSeeds.")

# ---------------------------------------------------------------- geometry table
PILLAR_X = 3.40                        # pillar centres
PILLAR_Z0, PILLAR_Z1 = 0.92, 8.20
PILLAR_W0, PILLAR_W1 = 0.86, 0.72
PILLAR_BLOCKS = 4

FOOT_HW, FOOT_TOP = 0.95, 0.26         # dark stone footing pad
PLINTH_HW, PLINTH_TOP = 0.63, 1.12     # stone plinth block

NUKI_HALF, NUKI_Z, NUKI_HT, NUKI_DP = 4.30, 5.30, 0.26, 0.26     # crossbeam

KASAGI_HALF, KASAGI_MID = 4.58, 8.44   # top lintel (centreline z at x = 0)
KASAGI_W, KASAGI_D = 0.80, 1.00        # W = how tall the strip is, D = how deep in Y
SHIMAKI_HALF, SHIMAKI_MID = 4.15, 7.89
SHIMAKI_W, SHIMAKI_D = 0.30, 0.86

RISE, RISE_POW = 0.70, 3.2             # how hard the kasagi's ends turn up

ROPE_X, ROPE_Z, ROPE_SAG = 3.40, 7.40, 0.55      # the shimenawa
ROPE_R, ROPE_BELLY = 0.12, 0.12                  # radius at the ends / extra in the middle
TASSEL_X, TASSEL_LEN = 1.90, 0.56
COLLAR_Z0, COLLAR_Z1, COLLAR_HW = 7.22, 7.62, 0.41

MEDAL_R, MEDAL_T = 0.80, 0.42          # the cucumber-slice medallion
MEDAL_Z, MEDAL_Y = 6.40, 0.44          # MEDAL_Y is measured along the disc's own axis

STUD_SIZE = 0.34
# one stud per face per pillar block, in a z window that keeps clear of the rope collar
STUD_WINDOWS = ((1.25, 2.55), (2.95, 4.40), (4.75, 6.20), (6.55, 7.15))
NUKI_STUD_X = (-4.02, -1.34, 1.34, 4.02)
KASAGI_STUD_X = (-4.05, -2.03, 0.0, 2.03, 4.05)


def _rise(x):
    """How far the beams have swept up by the time they reach x."""
    return RISE * (abs(x) / KASAGI_HALF) ** RISE_POW


def _beam_frames(half, mid_z, n):
    """Frames for a lofted beam along the upturned curve, flat face toward +Y."""
    out = []
    for i in range(n):
        x = -half + 2.0 * half * i / (n - 1.0)
        out.append(((x, 0.0, mid_z + _rise(x)), (0.0, 1.0, 0.0)))
    return out


def _pillar_hw(i):
    """Half-width of pillar block `i` - blocky_trunk tapers block by block."""
    t = (i + 0.5) / float(PILLAR_BLOCKS)
    return 0.5 * (PILLAR_W0 + (PILLAR_W1 - PILLAR_W0) * t)


def _rope_z(x):
    """Height of the sagging rope at x (the same parabola catenary_pts draws)."""
    t = (ROPE_X - x) / (2.0 * ROPE_X)
    return ROPE_Z - ROPE_SAG * 4.0 * t * (1.0 - t)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    medal = D.slice_stand((0.0, 0.0, MEDAL_Z))      # local +Z ends up pointing at +Y
    medal_kw = dict(center=(0.0, 0.0, MEDAL_Y), radius=MEDAL_R, thick=MEDAL_T,
                    matrix=medal)

    # ---- dark stone footing pads ------------------------------------------
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        cx = sx * PILLAR_X
        D.beveled_box(bm, (cx - FOOT_HW, -FOOT_HW, 0.0),
                      (cx + FOOT_HW, FOOT_HW, FOOT_TOP), bevel=0.07)
    D.new_obj("Footings", bm, c, D.C("sam_rock_dk"), rbx_material="Slate", roughness=0.82)

    # ---- the lighter stone blocks the pillars stand on ---------------------
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        cx = sx * PILLAR_X
        D.beveled_box(bm, (cx - PLINTH_HW, -PLINTH_HW, FOOT_TOP - 0.04),
                      (cx + PLINTH_HW, PLINTH_HW, PLINTH_TOP), bevel=0.09)
    D.new_obj("Plinths", bm, c, D.C("sam_rock"), rbx_material="Slate", roughness=0.74)

    # ---- the green gate: pillars, nuki, shimaki, kasagi, medallion rim -----
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        D.blocky_trunk(bm, PILLAR_Z0, PILLAR_Z1, PILLAR_W0, PILLAR_W1,
                       blocks=PILLAR_BLOCKS, bevel=0.075, center=(sx * PILLAR_X, 0.0))
    D.beveled_box(bm, (-NUKI_HALF, -NUKI_DP, NUKI_Z - NUKI_HT),
                  (NUKI_HALF, NUKI_DP, NUKI_Z + NUKI_HT), bevel=0.07)
    D.ribbon(bm, _beam_frames(SHIMAKI_HALF, SHIMAKI_MID, 13), SHIMAKI_W, SHIMAKI_D)
    D.ribbon(bm, _beam_frames(KASAGI_HALF, KASAGI_MID, 19), KASAGI_W, KASAGI_D)
    D.slice_disc(bm, bevel=0.05, **medal_kw)
    D.new_obj("Gate", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the speckles: pillars, both beams, and the medallion's rim --------
    bm = bmesh.new()
    for i, sx in enumerate((-1.0, 1.0)):
        cx = sx * PILLAR_X
        for j, (wz0, wz1) in enumerate(STUD_WINDOWS):
            hw = _pillar_hw(j)
            D.box_studs(bm, (cx - hw, -hw, wz0), (cx + hw, hw, wz1),
                        faces=("-y", "+y", "+x", "-x"), grid=(1, 1), size=STUD_SIZE,
                        rise=0.05, margin=0.18, bevel=0.04, seed=13 + i * 7 + j)
    for x in NUKI_STUD_X:                           # four along each side of the nuki
        for sy in (-1.0, 1.0):
            D.stud_patch(bm, (x, sy * NUKI_DP, NUKI_Z), (0.0, sy, 0.0),
                         size=STUD_SIZE, rise=0.05, bevel=0.04)
    for x in KASAGI_STUD_X:                         # five a side, riding the upturn
        z = KASAGI_MID + _rise(x)
        for sy in (-1.0, 1.0):
            D.stud_patch(bm, (x, sy * KASAGI_D / 2.0, z), (0.0, sy, 0.0),
                         size=STUD_SIZE, rise=0.05, bevel=0.04)
    D.slice_studs(bm, n=5, size=0.17, rise=0.04, seed=7, **medal_kw)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the shimenawa rope, its tassels and its pillar collars ------------
    bm = bmesh.new()
    pts = D.catenary_pts((ROPE_X, 0.0, ROPE_Z), (-ROPE_X, 0.0, ROPE_Z), ROPE_SAG, 9)
    radii = [ROPE_R + ROPE_BELLY * math.sin(math.pi * i / 8.0) for i in range(9)]
    D.tube(bm, pts, radii, segs=6)
    for sx in (-1.0, 1.0):
        tx = sx * TASSEL_X
        zt = _rope_z(tx)
        D.cyl(bm, (tx, 0.0, zt + 0.04), (tx, 0.0, zt + 0.04 - TASSEL_LEN), 0.18,
              segs=8, r2=0.10)
        cx = sx * PILLAR_X
        D.beveled_box(bm, (cx - COLLAR_HW, -COLLAR_HW, COLLAR_Z0),
                      (cx + COLLAR_HW, COLLAR_HW, COLLAR_Z1), bevel=0.05)
    D.new_obj("Rope", bm, c, D.C("sam_bamboo"), rbx_material="Fabric", roughness=0.80)

    # ---- the medallion's pale cut face and its pips ------------------------
    bm = bmesh.new()
    D.slice_face(bm, inset=0.12, proud=0.025, **medal_kw)
    D.new_obj("SliceFace", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.slice_seeds(bm, n=5, size=0.17, ring=0.42, **medal_kw)
    D.new_obj("SliceSeeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    return c
