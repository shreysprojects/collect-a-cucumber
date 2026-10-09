"""Hay bales - three variants standing side by side along X, all facing +Y.

A_ RoundBale  (x = -6.4): a 12-sided drum lying on its side with its axis along X,
                RESTING on a flat facet, three pale net-wrap lines evenly spread round the
                barrel, and the roll where a round bale is actually read - a bullseye of
                concentric terraces stepping out of each end.
B_ SquareBale (x =  0.0): a brick cut into four chamfered flake slabs with real grooves
                between them looking down onto a dark core, pale cut panels on both ends,
                blue baler twine the short way round and straw bursting out of the edges.
C_ Stack      (x = +6.4): the SAME bale three times - two sitting square on the ground
                side by side in Y, all but touching, and a third laid across them at 90
                deg, shifted a quarter of a bale off centre so it overhangs the front.

Straw is three-tone: the sawn cut faces, the wisps and the net wrap are `sand`, the
weathered sides are `hay`, and every flake groove looks down onto a `wood_mid` core.
Blue baler twine is the accent."""
import bmesh, math, random

COLLECTION = "HayBale"
NOTES = (
    "Three separable variants in one collection, prefixed A_/B_/C_; each is built about "
    "its own origin then offset along X (see VARIANTS), so a single variant drops into a "
    "game on its own. "
    "A RoundBale at x=-6.4: 2.4 long on X, 2.54 across, axis 1.198 up - a flat facet of "
    "the 12-gon rests ON z=0 and the net wrap is pulled in over that facet so nothing "
    "reaches below it. "
    "B SquareBale at x=0: 2.6 x 1.4 x 1.4 sitting flat, long axis on X, cut ends at "
    "x=+/-1.35; the body is four flake slabs with 0.07 grooves, not one box. "
    "C Stack at x=+6.4: two bales square on the ground at y=+0.71 and y=-0.71 (a 0.02 "
    "seam between them), a third yawed 90 deg lying across the pair at z=1.40, shifted "
    "+0.50 in Y and +0.20 in X so it is a quarter of a bale off centre and overhangs "
    "the front bale by 0.44; footprint about 2.9 x 3.3, 2.80 tall to the top bale. "
    "All static decor - no moving parts, no pit, nothing below z=0."
)
VARIANTS = {
    "A": {"name": "RoundBale", "x": -6.4},
    "B": {"name": "SquareBale", "x": 0.0},
    "C": {"name": "Stack", "x": 6.4},
}

BALE = (2.6, 1.4, 1.4)      # the brick every square bale is cut from
FLAKES, FLAKE_GAP, FLAKE_BEVEL = 4, 0.07, 0.10      # slabs / groove / slab chamfer
CORE_IN = 0.07              # how far the dark core sits below the slab faces


# ---------------------------------------------------------------- local helpers
def _yaw(deg, dx, dy):
    """Rotate a local (dx, dy) offset about Z.  Everything in this file is authored in
    WORLD coordinates - sub-assemblies are positioned with this and then spun about
    their own centre with rot=, so nothing has to be built at the origin and shoved."""
    a = math.radians(deg)
    return (dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a))


def _bale_body(D, bm, center, size=BALE, yaw=0.0, n=FLAKES, gap=FLAKE_GAP,
               bevel=FLAKE_BEVEL):
    """A square bale as `n` chamfered FLAKE SLABS with a real groove between each pair:
    the grooves run right over the top face and down both long sides, so the silhouette
    is a run of ribs rather than one moulded suitcase."""
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    rot = D.rot_euler(rz=yaw) if abs(yaw) > 1e-6 else None
    span, vs = size[0] / float(n), []
    for i in range(n):
        w = (span - gap) / 2.0
        ox, oy = _yaw(yaw, -hx + span * (i + 0.5), 0.0)
        px, py = cx + ox, cy + oy
        vs += D.beveled_box(bm, (px - w, py - hy, cz - hz), (px + w, py + hy, cz + hz),
                            bevel=bevel, rot=rot)
    return vs


def _stack_bale(D, bm, center, yaw=0.0, size=BALE, n=3, gap=FLAKE_GAP, bevel=FLAKE_BEVEL):
    """The same bale as `_bale_body`, but each flake is ONE prism extruded along the
    bale's own long axis with the chamfer carried in its profile instead of a beveled
    box: same ribbed silhouette, 20 tris a flake instead of 44.  That is what lets the
    stack carry three whole bales inside the budget."""
    cx, cy, cz = center
    hy, hz = size[1] / 2.0, size[2] / 2.0
    # cross-section in the bale's own (y, z) plane - chamfered along the two top edges,
    # square underneath where the bale meets the ground or the bale below it
    prof = [(-hy, -hz), (hy, -hz), (hy, hz - bevel),
            (hy - bevel, hz), (-hy + bevel, hz), (-hy, hz - bevel)]
    pts = [(-v, u) for (u, v) in prof]          # prism extrudes +Z; ry=90 lays that on X
    mat = D.place((cx, cy, cz), D.rot_euler(rz=yaw) @ D.rot_euler(ry=90))
    span, w, vs = size[0] / float(n), (size[0] / float(n) - gap) / 2.0, []
    for i in range(n):
        a_x = -size[0] / 2.0 + span * (i + 0.5)
        vs += D.prism(bm, pts, a_x - w, a_x + w, matrix=mat)
    return vs


def _bale_core(D, bm, center, size=BALE, yaw=0.0, inset=CORE_IN):
    """The dark plug the flake grooves look down onto - it is the only thing that makes
    a groove read as a shadowed seam instead of a slot cut clean through the bale."""
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2.0 - 0.06, size[1] / 2.0 - inset, size[2] / 2.0 - inset
    return D.box(bm, (cx - hx, cy - hy, cz - hz), (cx + hx, cy + hy, cz + hz),
                 rot=(D.rot_euler(rz=yaw) if abs(yaw) > 1e-6 else None))


def _bale_ends(D, bm, center, size=BALE, yaw=0.0, thick=0.09, out=0.05, inset=0.16):
    """Pale sawn panels let into both cut ends of a square bale - the light half of the
    two-tone.  Sized to sit inside the body chamfer so a dark border frames each one."""
    cx, cy, cz = center
    hx = size[0] / 2.0
    pw, ph = size[1] / 2.0 - inset, size[2] / 2.0 - inset
    rot = D.rot_euler(rz=yaw) if abs(yaw) > 1e-6 else None
    vs = []
    for s in (-1.0, 1.0):
        ox, oy = _yaw(yaw, s * (hx + out - thick / 2.0), 0.0)
        px, py = cx + ox, cy + oy
        vs += D.box(bm, (px - thick / 2.0, py - pw, cz - ph),
                    (px + thick / 2.0, py + pw, cz + ph), rot=rot)
    return vs


def _straps(D, bm, center, at, size=BALE, yaw=0.0, half_w=0.075, out=0.02,
            bevel=FLAKE_BEVEL):
    """Baler twine taken the short way round the bale at the given local x offsets.  The
    cross-section is the bale's own chamfered outline pushed out by `out`, so the cord
    HUGS the chamfer instead of arching over it with daylight underneath, and it stops
    where the bottom chamfer starts instead of reaching the ground."""
    cx, cy, cz = center
    hy, hz = size[1] / 2.0, size[2] / 2.0
    cb = bevel - 0.414 * out                    # chamfer of the offset outline
    ey, ez = hy + out, hz + out
    z0 = -hz + cb
    prof = [(-ey, z0), (-ey, hz - cb), (-hy + cb, ez),
            (hy - cb, ez), (ey, hz - cb), (ey, z0)]
    pts = [(-v, u) for (u, v) in prof]          # prism extrudes +Z; ry=90 lays that on X
    mat = D.place((cx, cy, cz), D.rot_euler(rz=yaw) @ D.rot_euler(ry=90))
    vs = []
    for a_x in at:
        vs += D.prism(bm, pts, a_x - half_w, a_x + half_w, matrix=mat)
    return vs


def _knot(D, bm, center, a_x, size=BALE, yaw=0.0, side=-0.22):
    """The little knotted lump where a strap is tied off, sat on the top face."""
    cx, cy, cz = center
    ox, oy = _yaw(yaw, a_x, side)
    return D.cube(bm, (cx + ox, cy + oy, cz + size[2] / 2.0 + 0.03), (0.12, 0.12, 0.09),
                  rot=D.rot_euler(rz=yaw + 34.0))


def _lumps(D, bm, center, rng, n, size=BALE, yaw=0.0, sides=(-1.0, 1.0),
           x_range=(-0.85, 0.85), dz=-0.03):
    """Chunky loose clumps straddling the top long edges - the thing that stops a bale
    reading as a moulded box at 40 studs.  Each one breaks the top edge AND the side."""
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    vs = []
    for i in range(n):
        side = sides[i % len(sides)]
        s = rng.uniform(0.20, 0.30)
        ox, oy = _yaw(yaw, rng.uniform(*x_range) * hx, side * (hy - 0.04))
        vs += D.cube(bm, (cx + ox, cy + oy, cz + hz + dz),
                     (s, s * rng.uniform(0.8, 1.2), s * 0.8),
                     rot=D.rot_euler(rx=rng.uniform(-24, 24), rz=yaw + rng.uniform(-40, 40)))
    return vs


def _tufts(D, bm, base, out_dir, n, rng, spread=(0.32, 0.32), length=0.27, r=0.115,
           droop=0.6):
    """A tight CLUSTER of `n` short fat straw wisps on the face centred at `base`, all
    pushing out along `out_dir` and, unless that already points up, sagging outward-and-
    DOWN.  Stubby and splayed on purpose: long thin spikes read as skewers, a low fringe
    of stubs hugging the cut end reads as straw."""
    ox, oy, oz = out_dir
    if abs(ox) >= max(abs(oy), abs(oz)):
        u, v = (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)
    elif abs(oy) >= abs(oz):
        u, v = (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)
    else:
        u, v = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)
    vs = []
    for _ in range(n):
        a, b = rng.uniform(-spread[0], spread[0]), rng.uniform(-spread[1], spread[1])
        p = (base[0] + u[0] * a + v[0] * b,
             base[1] + u[1] * a + v[1] * b,
             base[2] + u[2] * a + v[2] * b)
        L = length * rng.uniform(0.65, 1.20)
        ja, jb = rng.uniform(-0.10, 0.10), rng.uniform(-0.08, 0.10)
        sag = droop * L * (1.0 - max(0.0, oz)) * rng.uniform(0.45, 1.0)
        tip = (p[0] + ox * L + u[0] * ja + v[0] * jb,
               p[1] + oy * L + u[1] * ja + v[1] * jb,
               p[2] + oz * L + u[2] * ja + v[2] * jb - sag)
        root = (p[0] - ox * 0.14, p[1] - oy * 0.14, p[2] - oz * 0.14)
        vs += D.spike(bm, root, tip, r * rng.uniform(0.8, 1.2), segs=3)
    return vs


def _end_rings(D, bm, rings, base, matrix, phase):
    """Concentric terraces stepping out of BOTH ends of the round bale.  `rings` is
    [(radius, how far out along the axis, segments)]; run two interleaved sets in the two
    straw tones and the end reads as the rolled spiral, which is where a round bale is
    recognised - a barrel wrap never survives the 12-gon's facets.  The terraces run at 8
    segments, not the drum's 12: at this radius the two are the same shape."""
    vs = []
    for s in (-1.0, 1.0):
        for (r, out, segs) in rings:
            z0, z1 = sorted((s * base, s * out))
            vs += D.prism(bm, D.ngon_pts(segs, r, phase=phase), z0, z1, matrix=matrix)
    return vs


def _wrap_pts(r, r_flat, phase, n=12):
    """Profile of one net-wrap line round the barrel: proud of the drum everywhere except
    the two verts of the ground-contact facet, which are pulled in to `r_flat` so the
    wrap can never dip below z = 0 or prop the bale up like a foot."""
    pts = []
    for i in range(n):
        a = phase + 2.0 * math.pi * i / n
        rr = r_flat if math.cos(a) > 0.9 else r      # local +x is world DOWN under MA
        pts.append((math.cos(a) * rr, math.sin(a) * rr))
    return pts


# ---------------------------------------------------------------- build
def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    BODY = D.C("hay")            # weathered straw sides / barrel
    LIGHT = D.C("sand")          # pale sawn ends, net wrap and every loose wisp
    SEAM = D.C("wood_mid")       # the dark core a flake groove looks down onto
    TWINE = D.C("cloth_blue")    # blue baler twine on the square bales
    M_HAY, M_STRAW, M_CORD = "Grass", "LeafyGrass", "Fabric"

    # =============================================================== A: round bale
    # The 12-gon is phased half a facet so a FLAT facet rests on z=0 - the axis therefore
    # sits at the apothem, not the radius, and nothing has to prop the bale up.
    ax = VARIANTS["A"]["x"]
    rng = random.Random(7)
    PH = math.pi / 12.0
    R_DRUM, R_NET = 1.24, 1.27
    AZ = R_DRUM * math.cos(PH)                          # = 1.198, the apothem
    MA = D.place((ax, 0.0, AZ), D.rot_euler(ry=90))     # local +Z -> world +X

    bm = bmesh.new()
    D.lathe(bm, [(R_DRUM - 0.05, -0.98), (R_DRUM, -0.52),
                 (R_DRUM, 0.52), (R_DRUM - 0.05, 0.98)], segs=12, phase=PH, matrix=MA)
    _end_rings(D, bm, [(0.86, 1.10, 8)], 0.90, MA, PH)      # dark centre terrace
    D.new_obj("A_Drum", bm, c, BODY, rbx_material=M_HAY)

    bm = bmesh.new()
    _end_rings(D, bm, [(1.18, 1.02, 8)], 0.90, MA, PH)      # pale outer terrace
    for wz in (-0.62, 0.0, 0.62):                       # three even net-wrap lines
        D.prism(bm, _wrap_pts(R_NET, R_DRUM - 0.02, PH), wz - 0.055, wz + 0.055, matrix=MA)
    # fringes on both round ends and a scruff off the top of the barrel
    _tufts(D, bm, (ax + 1.16, 0.0, AZ), (1.0, 0.0, 0.0), 5, rng, spread=(0.44, 0.44))
    _tufts(D, bm, (ax - 1.16, 0.0, AZ), (-1.0, 0.0, 0.0), 4, rng, spread=(0.44, 0.44))
    _tufts(D, bm, (ax + 0.10, 0.60, AZ + 0.92), (0.0, 0.42, 0.91), 3, rng, spread=(0.46, 0.10))
    # a frayed wisp of wrap tucked down the barrel side - the one asymmetric detail
    D.tube(bm, [(ax + 0.36, 1.21, 1.24), (ax + 0.41, 1.20, 0.86), (ax + 0.38, 1.09, 0.55)],
           [0.06, 0.05, 0.02], segs=3)
    D.new_obj("A_Straw", bm, c, LIGHT, rbx_material=M_STRAW)

    # =============================================================== B: square bale
    bx = VARIANTS["B"]["x"]
    rng = random.Random(21)
    B_C = (bx, 0.0, 0.70)

    bm = bmesh.new()
    _bale_body(D, bm, B_C)
    D.new_obj("B_Body", bm, c, BODY, rbx_material=M_HAY)

    bm = bmesh.new()
    _bale_core(D, bm, B_C)
    D.new_obj("B_Core", bm, c, SEAM, rbx_material=M_HAY)

    bm = bmesh.new()
    _bale_ends(D, bm, B_C)
    _lumps(D, bm, B_C, rng, 5)
    _tufts(D, bm, (bx + 1.33, 0.0, 0.74), (1.0, 0.0, 0.0), 6, rng)
    _tufts(D, bm, (bx - 1.33, 0.0, 0.74), (-1.0, 0.0, 0.0), 5, rng)
    D.new_obj("B_Straw", bm, c, LIGHT, rbx_material=M_STRAW)

    bm = bmesh.new()
    _straps(D, bm, B_C, (-0.94, 0.90))
    _knot(D, bm, B_C, 0.90, side=0.24)
    D.new_obj("B_Twine", bm, c, TWINE, rbx_material=M_CORD)

    # =============================================================== C: stack
    cx = VARIANTS["C"]["x"]
    rng = random.Random(43)
    # two square on the ground with a 0.02 seam, one laid ACROSS them at 90 deg and
    # shifted a quarter of a bale off centre so the stack is not a symmetric tower
    HB = BALE[1] / 2.0                    # 0.70 - half a bale's depth AND its height
    C1 = (cx, HB + 0.01, HB)              # ground bale, +Y side (the front one)
    C2 = (cx, -HB - 0.01, HB)             # ground bale, -Y side
    C3 = (cx + 0.20, 0.50, 3.0 * HB)      # crossways on top, overhanging the front bale
    Y3 = 90.0

    bm = bmesh.new()
    _stack_bale(D, bm, C1)
    _stack_bale(D, bm, C2)
    _stack_bale(D, bm, C3, yaw=Y3)
    D.new_obj("C_Body", bm, c, BODY, rbx_material=M_HAY)

    bm = bmesh.new()
    _bale_core(D, bm, C1)
    _bale_core(D, bm, C2)
    _bale_core(D, bm, C3, yaw=Y3)
    D.new_obj("C_Core", bm, c, SEAM, rbx_material=M_HAY)

    bm = bmesh.new()
    _bale_ends(D, bm, C1)
    _bale_ends(D, bm, C2)
    _bale_ends(D, bm, C3, yaw=Y3)
    # clumps only on edges the bale above does not sit on, and kept low on the top bale
    # so the scruff breaks the corner without raising the stack
    _lumps(D, bm, C1, rng, 1, sides=(1.0,), x_range=(-0.90, -0.40))
    _lumps(D, bm, C3, rng, 2, yaw=Y3, dz=-0.16)
    for (px, py, ang) in ((-1.80, 1.05, 18.0), (1.15, -1.80, -34.0)):
        D.box(bm, (cx + px - 0.34, py - 0.05, 0.0), (cx + px + 0.34, py + 0.05, 0.07),
              rot=D.rot_euler(rz=ang))
    # fringes on the four cut ends that face out of the stack
    _tufts(D, bm, (C3[0], C3[1] + 1.33, C3[2]), (0.0, 1.0, 0.0), 5, rng)
    _tufts(D, bm, (C3[0], C3[1] - 1.33, C3[2]), (0.0, -1.0, 0.0), 3, rng)
    _tufts(D, bm, (cx + 1.33, C1[1], 0.74), (1.0, 0.0, 0.0), 4, rng)
    _tufts(D, bm, (cx - 1.33, C2[1], 0.74), (-1.0, 0.0, 0.0), 3, rng)
    D.new_obj("C_Straw", bm, c, LIGHT, rbx_material=M_STRAW)

    bm = bmesh.new()
    _straps(D, bm, C1, (-0.92, 0.88))
    _straps(D, bm, C2, (-0.92, 0.88))
    _straps(D, bm, C3, (-0.90, 0.86), yaw=Y3)
    D.new_obj("C_Twine", bm, c, TWINE, rbx_material=M_CORD)

    return c
