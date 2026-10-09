"""Toyland: Toy Train Cucumber - a chunky toy steam engine with a big cucumber riding in its tub."""
import bmesh, math

COLLECTION = "ToylandToyTrainCucumber"
NOTES = ("The Toyland landmark: a chunky toy-brick steam engine seen side-on, with a fat "
         "cucumber riding in the open tub on its back.  The long axis is X and the chimney is "
         "at the FRONT = +X (the render's left); the side faces +Y.  Footprint 4.60 x 2.20 "
         "(x -2.30..+2.30, y -1.10..+1.10 across the hubs), 4.70 tall to the stem nub, centred "
         "on x = 0 / y = 0, mirror-symmetric about y = 0 apart from the cucumber's face and "
         "speckles, nothing below "
         "z = 0.  "
         "WHEELS: six toy_yellow 12-sided wheels, r 0.54 and 0.30 thick, three a side at "
         "x +0.48 / -0.62 / -1.72 (almost touching, like the tile), a flat facet resting "
         "exactly on z = 0 (centre z 0.522), y 0.72..1.02 and mirrored; each carries a "
         "toy_yellow_dk 8-sided hub r 0.22 standing 0.08 proud of its outer face.  Their inner "
         "faces are sunk 0.02 into the red undercarriage so nothing floats.  "
         "UNDER (toy_red): a long red brick x -2.05..+2.05, y +-0.74, z 0.25..1.30 that shows "
         "as the red bumper under the front overhang and as a red strip above the rear "
         "wheels; the square red chimney column 0.88 x 0.88, x +0.66..+1.54, z 1.74..2.92; and "
         "a small red cube at the chimney foot on each side face (x +0.72..+1.04).  "
         "CHASSIS (toy_blue): the front slab x -0.60..+2.30, y +-0.95, z 1.05..1.78 (its "
         "underside just clears the wheel tops at 1.043); the cab block x -2.12..-0.20, "
         "y +-0.82, z 1.28..2.12 standing on the red brick; a small blue brick x -0.22..+0.36 "
         "on the slab that carries the tub's front overhang; and the open tub on top: a floor "
         "(z 2.12..2.22) inside four 0.18-thick walls, outer x -2.30..+0.40, y +-1.00, "
         "z 2.10..2.62.  WINDOW: a toy_blue_dk panel 0.70 x 0.56 on each side of the cab "
         "block, toward its rear as in the tile (x -1.82..-1.12, z 1.36..1.92), 0.03 proud.  "
         "CAP: the wide toy_yellow cap block 1.24 x 1.24 x 0.48 on the chimney (z 2.90..3.38), "
         "merged into Wheels.  BLOCKS: two toy_magenta slabs 0.64 x 0.58 x 0.32 butted "
         "against the chimney foot, one in front of each side face, poking 0.32 past its "
         "+X face (x +1.22..+1.86).  "
         "CUKE: a squat CUKE_PROFILE_STUB body h 2.2, r 0.86 standing in the tub at "
         "(-0.72, 0), base z 2.20, top 4.40, with a 0.44-wide stem nub to 4.70; like the tile "
         "it sits toward the tub's front wall (0.15 clear of it, 0.61 clear of the back "
         "wall), its flats clear the side walls by 0.025, it rises 1.78 above the rim.  16 raised "
         "cuke_stud_dk speckles above the rim (zf 0.28-0.82) and two small dark toy_eye eyes "
         "(0.20 x 0.16, 0.045 proud) on the two FRONT DIAGONAL facets (0 and 2, +-45 deg from "
         "+Y) at zf 0.50 (z 3.30), wide-set like the tile.  "
         "DEVIATIONS from the brief (the tile wins): (1) three wheels a side, not two at "
         "x +-1.35 - the tile shows three in a row on the near side, rear-weighted, with the "
         "red undercarriage bare under the front overhang (the fourth wheel it shows is a "
         "far-side wheel peeking past the front); (2) the wheels sit BELOW the chassis (tops "
         "touching its underside) instead of half-covering its side, and the cab is a "
         "windowed block under a shallow 2.70 x 2.00 open tub (not one 1.9-cube tub), so the "
         "engine stands 4.70 tall rather than ~3.9, in the tile's proportions; (3) the chimney "
         "is a square brick column centred at x +1.10 with a 1.24 cap, like the tile, not an "
         "8-sided r 0.42 column at x +1.45; (4) the undercarriage is 1.48 wide (not 1.3) so "
         "the wheels bear on it; (5) the cucumber is the tile's darker green (cuke_dark body, "
         "cuke_stud_dk speckles), a STUB profile h 2.2 r 0.86 based at z 2.20, not cuke_green "
         "h 2.4 r 0.82 at z 1.45; (6) its eyes sit wide-set on the two front diagonal facets "
         "at zf 0.50, as in the tile, not side by side on the +Y facet at zf 0.45; (7) the "
         "tile's chimney-foot blocks are one magenta slab and one red cube, so the magenta "
         "slabs (0.64 x 0.58 x 0.32, not 0.45 cubes) are mirrored onto both sides and the red "
         "cubes live in Under.  Nine parts: Chassis, Under, Wheels, Hubs, Blocks, Window, "
         "Cuke, CukeStuds, Eyes; ~2130 triangles (~1140 faces).")

# ---------------------------------------------------------------- wheels
WR = 0.54                                  # wheel circumradius (12-gon)
WSEG = 12
WPH = math.pi / WSEG                       # 15 deg: flats at top / bottom / front / back
WZ = WR * math.cos(math.pi / WSEG)         # 0.5216: centre height, bottom flat on z = 0
WX = (0.48, -0.62, -1.72)                  # three a side, 1.10 apart (0.06 gaps)
W_IN, W_T = 0.72, 0.30                     # inner face |y| and thickness (-> |y| 1.02)
HR, HSEG = 0.22, 8                         # hub circumradius, sides
H_IN, H_T = 1.00, 0.10                     # hub from |y| 1.00 (0.02 into the wheel) to 1.10

# ---------------------------------------------------------------- body blocks
SLAB = (-0.60, 2.30, 0.95, 1.05, 1.78)     # x0, x1, half y, z0, z1   front chassis slab
CAB = (-2.12, -0.20, 0.82, 1.28, 2.12)     # cab block under the tub
NOSE = (-0.22, 0.36, 0.62, 1.76, 2.12)     # small brick carrying the tub's front overhang
UNDER = (-2.05, 2.05, 0.74, 0.25, 1.30)    # red undercarriage brick
CHIM = (0.66, 1.54, 0.44, 1.74, 2.92)      # square chimney column
CAP = (0.48, 1.72, 0.62, 2.90, 3.38)       # wide yellow cap

TUB_X0, TUB_X1, TUB_HY = -2.30, 0.40, 1.00
TUB_Z0, TUB_Z1, TUB_WALL = 2.10, 2.62, 0.18
FLOOR_Z0, FLOOR_Z1 = 2.12, 2.22

WIN_X0, WIN_X1, WIN_Z0, WIN_Z1 = -1.82, -1.12, 1.36, 1.92   # rear of the cab, like the tile

# ---------------------------------------------------------------- the cucumber
CX, CZ = -0.72, 2.20                       # base centre (0.02 into the tub floor); the tile
                                           # sits it toward the tub's FRONT wall
CH, CR = 2.2, 0.86
# (zf, facet): facet 1 = +Y, 0 / 2 = the front diagonals (the eyes), 5 = the back.
# Staggered even/odd rows, all above the tub rim (rim = zf 0.19), none near the eyes.
STUD_SLOTS = ([(0.28, f) for f in (0, 2, 4, 6)]
              + [(0.42, f) for f in (3, 5, 7)]
              + [(0.57, f) for f in (4, 6)]
              + [(0.70, f) for f in (1, 3, 5, 7)]
              + [(0.82, f) for f in (0, 2, 6)])
EYE_FACETS, EYE_ZF = (0, 2), 0.50


def _bbox(D, bm, x0, x1, y0, y1, z0, z1, bevel):
    """beveled_box from possibly unordered extents (keeps mirrored copies right-side out)."""
    lo = (min(x0, x1), min(y0, y1), min(z0, z1))
    hi = (max(x0, x1), max(y0, y1), max(z0, z1))
    return D.beveled_box(bm, lo, hi, bevel=bevel)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    rot_y = D.rot_euler(-90.0, 0.0, 0.0)   # local +Z -> world +Y, local Y -> world -Z

    # ---- Chassis: front slab, cab block, nose brick, open tub -------------------
    bm = bmesh.new()
    x0, x1, hy, z0, z1 = SLAB
    _bbox(D, bm, x0, x1, -hy, hy, z0, z1, 0.08)
    x0, x1, hy, z0, z1 = CAB
    _bbox(D, bm, x0, x1, -hy, hy, z0, z1, 0.08)
    x0, x1, hy, z0, z1 = NOSE
    _bbox(D, bm, x0, x1, -hy, hy, z0, z1, 0.06)
    # tub floor, tucked inside the walls so no faces are shared
    _bbox(D, bm, TUB_X0 + 0.02, TUB_X1 - 0.02, -(TUB_HY - 0.02), TUB_HY - 0.02,
          FLOOR_Z0, FLOOR_Z1, 0.03)
    for s in (1.0, -1.0):                  # the two long side walls
        _bbox(D, bm, TUB_X0, TUB_X1, s * (TUB_HY - TUB_WALL), s * TUB_HY,
              TUB_Z0, TUB_Z1, 0.05)
    iy = TUB_HY - TUB_WALL + 0.08          # end walls reach into the side walls
    _bbox(D, bm, TUB_X1 - TUB_WALL, TUB_X1, -iy, iy, TUB_Z0, TUB_Z1, 0.05)
    _bbox(D, bm, TUB_X0, TUB_X0 + TUB_WALL, -iy, iy, TUB_Z0, TUB_Z1, 0.05)
    D.new_obj("Chassis", bm, c, D.C("toy_blue"), rbx_material="SmoothPlastic")

    # ---- Under: red undercarriage brick, chimney column, chimney-foot cubes -----
    bm = bmesh.new()
    x0, x1, hy, z0, z1 = UNDER
    _bbox(D, bm, x0, x1, -hy, hy, z0, z1, 0.08)
    x0, x1, hy, z0, z1 = CHIM
    _bbox(D, bm, x0, x1, -hy, hy, z0, z1, 0.08)
    for s in (1.0, -1.0):
        _bbox(D, bm, 0.72, 1.04, s * 0.30, s * 0.64, 1.76, 2.06, 0.05)
    D.new_obj("Under", bm, c, D.C("toy_red"), rbx_material="SmoothPlastic")

    # ---- Wheels (+ the chimney cap, same colour + material) ---------------------
    bm = bmesh.new()
    wheel = D.ngon_pts(WSEG, WR, phase=WPH)
    for wx in WX:
        for y0 in (W_IN, -(W_IN + W_T)):   # +Y side: 0.72..1.02, -Y side: -1.02..-0.72
            D.prism(bm, wheel, 0.0, W_T, matrix=D.place((wx, y0, WZ), rot_y))
    x0, x1, hy, z0, z1 = CAP
    _bbox(D, bm, x0, x1, -hy, hy, z0, z1, 0.08)
    D.new_obj("Wheels", bm, c, D.C("toy_yellow"), rbx_material="SmoothPlastic")

    # ---- Hubs: a darker 8-sided boss on each wheel's outer face ----------------
    bm = bmesh.new()
    hub = D.ngon_pts(HSEG, HR, phase=math.pi / HSEG)
    for wx in WX:
        for y0 in (H_IN, -(H_IN + H_T)):   # +Y: 1.00..1.10, -Y: -1.10..-1.00
            D.prism(bm, hub, 0.0, H_T, matrix=D.place((wx, y0, WZ), rot_y))
    D.new_obj("Hubs", bm, c, D.C("toy_yellow_dk"), rbx_material="SmoothPlastic")

    # ---- Blocks: the magenta slabs butted against the chimney foot -------------
    bm = bmesh.new()
    for s in (1.0, -1.0):
        _bbox(D, bm, 1.22, 1.86, s * 0.30, s * 0.88, 1.76, 2.08, 0.06)
    D.new_obj("Blocks", bm, c, D.C("toy_magenta"), rbx_material="SmoothPlastic")

    # ---- Window: a darker panel on each side of the cab block ------------------
    bm = bmesh.new()
    cy = CAB[2]
    for s in (1.0, -1.0):
        _bbox(D, bm, WIN_X0, WIN_X1, s * (cy - 0.02), s * (cy + 0.03), WIN_Z0, WIN_Z1, 0.02)
    D.new_obj("Window", bm, c, D.C("toy_blue_dk"), rbx_material="SmoothPlastic")

    # ---- Cuke: the squat cucumber riding in the tub -----------------------------
    m = D.place((CX, 0.0, CZ))
    bm = bmesh.new()
    D.cuke_body(bm, h=CH, r=CR, profile=D.CUKE_PROFILE_STUB, nub=(0.44, 0.30), matrix=m)
    D.new_obj("Cuke", bm, c, D.C("cuke_dark"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=CH, r=CR, profile=D.CUKE_PROFILE_STUB, slots=STUD_SLOTS,
                 size=0.26, rise=0.05, bevel=0.03, matrix=m)
    D.new_obj("CukeStuds", bm, c, D.C("cuke_stud_dk"), rbx_material="SmoothPlastic")

    # ---- Eyes: two small dark squares on the front diagonal facets --------------
    bm = bmesh.new()
    for f in EYE_FACETS:
        p, n = D.cuke_facet_point(h=CH, r=CR, zf=EYE_ZF, facet=f,
                                  profile=D.CUKE_PROFILE_STUB)
        D.stud_patch(bm, (p[0] + CX, p[1], p[2] + CZ), n, size=0.20, aspect=0.80,
                     rise=0.045, sink=0.05, bevel=0.025)
    D.new_obj("Eyes", bm, c, D.C("toy_eye"), rbx_material="SmoothPlastic")

    return c
