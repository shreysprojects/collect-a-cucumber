"""Grass: Flowered Cucumber - a white five-part flower on a stem arcing off the shoulder."""
import bmesh, math

COLLECTION = "FloweredCucumber"
NOTES = ("The standard 4.0 x 1.36 cucumber in cuke_green with 21 cuke_stud speckles, and "
         "growing out of its upper RIGHT shoulder (negative x, screen right) a cuke_stem "
         "stem that arcs up and out from (-0.30, 0.10, 2.90) to (-1.28, -0.16, 4.00).  On "
         "the end of the arc a white five-part flower faces +Y: four flower_white petals "
         "in a + on a 0.30 ring, each cupped 10 degrees forward, round a petal_yellow "
         "centre cube 0.22 across; the whole head is tipped 12 degrees up and turned 16 "
         "degrees outward.  Two leaf_dark leaf blades (0.85 long, 0.55 wide) sit on short "
         "stems off the same arc - one reaching up-left over the shoulder, one drooping "
         "down-right under the flower - each rolled 25 degrees out of its own plane so the "
         "facets catch the light.  Footprint about 2.6 x 1.5, 4.6 tall, centred on the "
         "body; nothing below z = 0.  Six parts: Body, Studs, Stem, Petals, FlowerCentre, "
         "Leaves.")

# ---- the stem arc: out to negative x, rising steeply off the body, levelling at the head
ARC_X0, ARC_DX = -0.30, -0.98
ARC_Y0, ARC_DY = 0.10, -0.26
ARC_Z0, ARC_DZ = 2.90, 1.10
ARC_BOW = 1.5                       # >1 = steep out of the body, flat under the flower
ARC_T = (0.0, 0.25, 0.50, 0.75, 1.0)
ARC_R = (0.095, 0.087, 0.079, 0.070, 0.060)

# ---- the flower head
FLOWER_AT = (-1.33, -0.17, 4.02)
FLOWER_TIP, FLOWER_TURN = -78.0, 16.0    # rot_euler(rx, 0, rz): local +Z -> +Y, up and out
PETAL_RING, PETAL_L, PETAL_W = 0.30, 0.50, 0.34
PETAL_R, PETAL_T, PETAL_CUP = 0.14, 0.11, -10.0
CENTRE_W, CENTRE_T = 0.22, 0.18

# ---- leaves: (arc t, in-plane spin, roll out of plane, yaw about Z, length, width, stem)
LEAVES = (
    (0.52, -160.0,  25.0, -34.0, 0.85, 0.55, 0.16),     # up-left, over the shoulder
    (0.76,   42.0, -25.0,  38.0, 0.85, 0.55, 0.16),     # down-right, under the flower
)


def _arc(t):
    """A point on the stem arc at parameter `t` in 0..1."""
    return (ARC_X0 + ARC_DX * t,
            ARC_Y0 + ARC_DY * t,
            ARC_Z0 + ARC_DZ * (1.0 - (1.0 - t) ** ARC_BOW))


def _leaf_dir(spin, yaw):
    """The world direction a blade tip points under build()'s rotation chain:
    Rz(yaw) @ Rx(-90) @ Rz(spin) applied to the blade's local +Y."""
    s, y = math.radians(spin), math.radians(yaw)
    dx, dz = -math.sin(s), -math.cos(s)
    return (dx * math.cos(y), dx * math.sin(y), dz)


def _leaf_base(t, spin, yaw, stem):
    """Where the short leaf stem lifts the blade off the arc."""
    a, d = _arc(t), _leaf_dir(spin, yaw)
    return (a[0] + d[0] * stem, a[1] + d[1] * stem, a[2] + d[2] * stem)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- body + speckles ---------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=7, per_row=3, z0=0.11, z1=0.90,
                 size=0.28, rise=0.055, seed=7)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the arcing stem, and the two short stems the leaves sit on --------
    bm = bmesh.new()
    D.tube(bm, [_arc(t) for t in ARC_T], list(ARC_R), segs=6)
    for (t, spin, roll, yaw, ln, wd, stem) in LEAVES:
        D.tube(bm, [_arc(t), _leaf_base(t, spin, yaw, stem)], [0.062, 0.050], segs=5)
    D.new_obj("Stem", bm, c, D.C("cuke_stem"), rbx_material="Grass")

    # ---- the flower: four petals in a +, then the yellow centre ------------
    flower = D.place(FLOWER_AT, D.rot_euler(FLOWER_TIP, 0.0, FLOWER_TURN))

    bm = bmesh.new()
    for (u, v) in D.ring_xy(4, PETAL_RING):
        pts = D.rounded_rect_pts(PETAL_L, PETAL_W, PETAL_R, segs=3,
                                 center=(math.hypot(u, v), 0.0))
        spin = math.degrees(math.atan2(v, u))
        D.prism(bm, pts, -PETAL_T / 2.0, PETAL_T / 2.0,
                matrix=flower @ D.rot_euler(0, 0, spin) @ D.rot_euler(0, PETAL_CUP, 0))
    D.new_obj("Petals", bm, c, D.C("flower_white"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    vs = D.beveled_box(bm, (-CENTRE_W / 2.0, -CENTRE_W / 2.0, 0.0),
                       (CENTRE_W / 2.0, CENTRE_W / 2.0, CENTRE_T), bevel=0.045)
    D.xform(bm, vs, flower @ D.place((0.0, 0.0, 0.02)))
    D.new_obj("FlowerCentre", bm, c, D.C("petal_yellow"), rbx_material="SmoothPlastic")

    # ---- leaves ------------------------------------------------------------
    bm = bmesh.new()
    for (t, spin, roll, yaw, ln, wd, stem) in LEAVES:
        m = (D.place(_leaf_base(t, spin, yaw, stem), D.rot_euler(0, 0, yaw))
             @ D.rot_euler(-90, 0, 0) @ D.rot_euler(0, 0, spin) @ D.rot_euler(0, roll, 0))
        D.leaf_blade(bm, length=ln, width=wd, thick=0.085, matrix=m, ridge=0.06)
    D.new_obj("Leaves", bm, c, D.C("leaf_dark"), rbx_material="LeafyGrass")

    return c
