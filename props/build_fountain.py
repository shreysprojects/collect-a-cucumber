"""Two-tier octagonal stone garden fountain: a continuous coping rim on a panelled basin
wall, a fluted pedestal, an upper dish, a finial with a vertical plume, and five narrow
streams that arc off the dish lip and land in flat rings of splash foam.  Radially
symmetric except for one settled coping stone and the moss that has crept up beside it."""
import bmesh, math, random

COLLECTION = "Fountain"
NOTES = ("Free-standing garden centrepiece, 7.3 studs across and 4.2 tall, centred on the "
         "origin and sitting flat on z = 0 (the basin is a RAISED wall, no pit needed). "
         "The coping rim is a continuous octagonal ledge 0.96 wide - eight radial trapezoid "
         "stones with hairline joints, not loose blocks - whose top face is at z 1.06, low "
         "enough to perch on. Basin water surface is at z 0.72 (over a darker water_deep bed "
         "at 0.41-0.70); the upper bowl's water is at z 2.50. Both water objects and the Jets "
         "object are transparent, so make them non-collidable in Roblox and let players "
         "walk into the basin. The Foam object is flat splash rings lying IN the two water "
         "planes plus a few flung droplets - it is decoration, leave it non-collidable too. "
         "PIVOTS gives the anchor points for ParticleEmitters / a looping water animation. "
         "One coping stone (front, index 1) is dropped 4 hundredths and skewed with a moss "
         "clump beside it - that is deliberate.")

PIVOTS = {"BasinWaterTop": (0.0, 0.0, 0.72),      # splash / ripple emitter plane
          "BowlWaterTop": (0.0, 0.0, 2.50),       # upper dish surface
          "JetOrigin": (0.0, 0.0, 3.62),          # base of the vertical plume
          "JetTop": (0.0, 0.0, 4.20)}             # tip of the vertical plume

PHASE8 = math.pi / 8.0        # puts a flat octagon FACET (not a corner) toward +Y
PHASE10 = math.pi / 10.0
FACETS = [45.0 + 45.0 * i for i in range(8)]      # facet-centre angles, degrees
JOINTS = [67.5 + 45.0 * i for i in range(8)]      # angles of the seams between blocks
JET_ANGLES = [54.0 + 72.0 * i for i in range(5)]  # 5 jets, none dead-centre front


def _polar(deg, r, z):
    a = math.radians(deg)
    return (math.cos(a) * r, math.sin(a) * r, z)


def _coping_pts(k, r_out, r_in, gap, skew=0.0):
    """Footprint of coping stone `k`: a radial trapezoid spanning exactly one octagon
    facet, corner to corner, pulled back `gap` from each radial seam so neighbouring
    stones meet in a hairline joint instead of opening a wedge notch at the outer edge."""
    a0 = math.radians(22.5 + 45.0 * k)
    a1 = a0 + math.pi / 4.0
    n0 = (-math.sin(a0), math.cos(a0))          # seam normal, pointing into this stone
    n1 = (math.sin(a1), -math.cos(a1))

    def corner(a, r, n):
        return (math.cos(a) * r + n[0] * gap, math.sin(a) * r + n[1] * gap)

    pts = [corner(a0, r_out, n0), corner(a1, r_out, n1),
           corner(a1, r_in, n1), corner(a0, r_in, n0)]
    if skew:
        cx = sum(p[0] for p in pts) / 4.0
        cy = sum(p[1] for p in pts) / 4.0
        s, co = math.sin(math.radians(skew)), math.cos(math.radians(skew))
        pts = [(cx + co * (p[0] - cx) - s * (p[1] - cy),
                cy + s * (p[0] - cx) + co * (p[1] - cy)) for p in pts]
    return pts


def _arc_points(deg, n=6, r0=1.50, dr=0.88, z0=2.52, rise=0.32, z1=0.74):
    """One jet as a real parabola: it leaves the dish lip moving OUTWARD and still
    CLIMBING, crests `rise` above the lip about a third of the way out, then falls
    away into the basin - so the stream reads as a curve in silhouette, not a fin."""
    d = z1 - z0                                  # net fall, negative
    tc = (rise - math.sqrt(rise * rise - d * rise)) / d      # crest parameter
    v, g = 2.0 * rise / tc, rise / (tc * tc)
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for i in range(n):
        t = i / (n - 1.0)
        r = r0 + dr * t                          # starts buried in the rim stone
        pts.append((ca * r, sa * r, z0 + v * t - g * t * t))
    return pts


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    rng = random.Random(1704)

    # Value ladder, dark base -> bright rim: the plinth and wall panels are the
    # darkest course, the basin wall and pedestal sit a clear step above them, and
    # stone_light is spent ONLY on the coping rim and the upper bowl.
    light = D.C("stone_light")
    mid = D.C("gravel")
    dark = "56524b"

    # ---------------------------------------------------------------- basin wall
    # A hollow octagonal vessel: up the outside, across the wall top, down the inside,
    # in along a raised floor at z 0.40.  Nothing dips below the ground plane.
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 0.14), (3.45, 0.14), (3.42, 0.80),
                 (2.78, 0.80), (2.82, 0.40), (0.00, 0.40)], segs=8, phase=PHASE8)
    D.new_obj("BasinWall", bm, c, mid, rbx_material="Slate", roughness=0.72)

    # ---------------------------------------------------------------- dark stonework
    # ground plinth + the eight recessed wall panels + pedestal flutes + the bowl rib
    # + the nozzle collar the vertical plume springs from.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 3.72, PHASE8), 0.0, 0.15)
    for k, ang in enumerate(FACETS):
        cx, cy, _ = _polar(ang, 3.13, 0.0)
        D.box(bm, (cx - 0.90, cy - 0.09, 0.28), (cx + 0.90, cy + 0.09, 0.72),
              rot=D.rot_euler(rz=ang + 90.0))
    for ang in [60.0 * i for i in range(6)]:
        fx, fy, _ = _polar(ang, 0.58, 0.0)
        D.box(bm, (fx - 0.09, fy - 0.12, 1.04), (fx + 0.09, fy + 0.12, 1.52),
              rot=D.rot_euler(rz=ang + 90.0))
    D.lathe(bm, [(1.48, 2.40), (1.66, 2.47), (1.52, 2.54)], segs=10, phase=PHASE10, cap=False)
    D.cyl(bm, (0.0, 0.0, 3.48), (0.0, 0.0, 3.62), 0.205, segs=8)
    D.new_obj("DarkStonework", bm, c, dark, rbx_material="Slate", roughness=0.8)

    # ---------------------------------------------------------------- coping
    # Eight radial trapezoids cut to the octagon, so every seam is a true radial joint
    # 0.05 wide and the outer silhouette stays a clean octagon - not eight tangential
    # blocks with wedge notches between them.  0.26 thick against the 0.64 wall, laid as
    # a 0.19 course with a 0.07 chamfer course inset 0.03 on top for the highlight, and
    # overhanging the wall ~0.15 in and out to throw a shadow line.
    # Stone 1 has settled 0.04 and skewed - deliberate.
    bm = bmesh.new()
    for k, ang in enumerate(FACETS):
        drop = 0.04 if k == 1 else 0.0
        skew = 1.6 if k == 1 else 0.0
        D.prism(bm, _coping_pts(k, 3.58, 2.62, 0.025, skew), 0.80 - drop, 0.99 - drop)
        D.prism(bm, _coping_pts(k, 3.55, 2.65, 0.055, skew), 0.99 - drop, 1.06 - drop)
        # a light diamond boss centred on each dark wall panel
        bx, by, _ = _polar(ang, 3.14, 0.0)
        tx, ty, _ = _polar(ang, 3.34, 0.0)
        D.cone(bm, (bx, by, 0.50), (tx, ty, 0.50), 0.17, r_tip=0.0, segs=4)
    D.new_obj("Coping", bm, c, light, rbx_material="Concrete", roughness=0.6)

    # ---------------------------------------------------------------- pedestal
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 0.34), (1.05, 0.34), (1.05, 0.52), (0.80, 0.66),
                 (0.66, 0.95), (0.60, 1.00), (0.56, 1.55), (0.62, 1.68),
                 (0.46, 1.80), (0.88, 2.08), (0.86, 2.22), (0.00, 2.22)],
            segs=8, phase=PHASE8)
    D.new_obj("Pedestal", bm, c, mid, rbx_material="Concrete", roughness=0.66)

    # ---------------------------------------------------------------- upper dish + finial
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 2.00), (0.40, 2.00), (0.90, 2.10), (1.40, 2.32),
                 (1.58, 2.46), (1.58, 2.60), (1.32, 2.60), (1.14, 2.40),
                 (0.52, 2.26), (0.00, 2.26)], segs=10, phase=PHASE10)
    D.lathe(bm, [(0.00, 2.30), (0.36, 2.30), (0.32, 2.62), (0.24, 2.78),
                 (0.40, 2.92), (0.22, 3.08), (0.30, 3.26), (0.12, 3.48),
                 (0.17, 3.58), (0.00, 3.76)], segs=8, phase=PHASE8)
    D.new_obj("BowlAndFinial", bm, c, light, rbx_material="Concrete", roughness=0.6)

    # ---------------------------------------------------------------- water body
    # A dark bed under the basin surface so the transparent sheet reads as having depth.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 2.70, PHASE8), 0.41, 0.70)
    D.new_obj("WaterBed", bm, c, D.C("water_deep"), rbx_material="Glass",
              transparency=0.12, roughness=0.2)

    bm = bmesh.new()
    D.ngon_face(bm, D.ngon_pts(8, 2.785, PHASE8), 0.72)
    D.ngon_face(bm, D.ngon_pts(10, 1.235, PHASE10), 2.50)
    D.new_obj("WaterSurface", bm, c, D.C("water_mid"), rbx_material="Glass",
              transparency=0.42, roughness=0.15)

    # ---------------------------------------------------------------- jets
    # Narrow round streams so the arc, not the thickness, is what reads in silhouette.
    # Jet 3 is thrown shorter and flatter than its neighbours, off the radial spokes.
    bm = bmesh.new()
    for k, ang in enumerate(JET_ANGLES):
        if k == 3:
            pts = _arc_points(ang + 8.0, 6, dr=0.70, rise=0.17)
            D.tube(bm, pts, [0.115, 0.12, 0.115, 0.105, 0.10, 0.115], segs=5)
        else:
            pts = _arc_points(ang, 6)
            D.tube(bm, pts, [0.125, 0.13, 0.125, 0.115, 0.105, 0.12], segs=5)
    D.tube(bm, [(0.0, 0.0, 3.62), (0.0, 0.0, 3.86), (0.0, 0.0, 4.06), (0.0, 0.0, 4.20)],
           [0.18, 0.12, 0.085, 0.03], segs=6)
    D.new_obj("Jets", bm, c, D.C("water_shallow"), rbx_material="Glass",
              transparency=0.35, roughness=0.15)

    # ---------------------------------------------------------------- splash foam
    # Flat rings lying IN the water plane where each stream lands - a wide one, a smaller
    # one shouldered off to one side, and two flung droplets - so the foam reads as splash
    # spreading on the surface rather than boulders floating in the pool.
    bm = bmesh.new()
    for k, ang in enumerate(JET_ANGLES):
        px, py, _ = _polar(ang, 2.18, 0.0)
        D.prism(bm, D.ngon_pts(8, 0.34 * rng.uniform(0.88, 1.10), 0.4 * k,
                               center=(px, py)), 0.715, 0.755)
        sx, sy, _ = _polar(ang + 7.5, 2.06, 0.0)
        D.prism(bm, D.ngon_pts(7, 0.22 * rng.uniform(0.85, 1.12), 0.9 * k,
                               center=(sx, sy)), 0.712, 0.748)
        for j, (off, rr, zz, sz) in enumerate(((-9.0, 2.30, 0.84, 0.075),
                                               (6.0, 2.18, 0.95, 0.06))):
            dx, dy, _ = _polar(ang + off, rr, 0.0)
            D.cube(bm, (dx, dy, zz), sz, rot=D.rot_euler(rz=ang + 34.0 * j))
    # where the vertical plume falls back into the upper dish
    bx, by, _ = _polar(120.0, 0.56, 0.0)
    D.prism(bm, D.ngon_pts(8, 0.30, PHASE8, center=(bx, by)), 2.492, 2.528)
    D.new_obj("Foam", bm, c, D.C("foam"), rbx_material="Plaster", roughness=0.85)

    # ---------------------------------------------------------------- moss
    # Weighted to the front-right quarter, in the joints around the stone that settled.
    bm = bmesh.new()
    for (ang, r, z, rad, sc) in ((JOINTS[0], 3.40, 0.88, 0.17, (1.5, 0.32, 0.85)),
                                 (JOINTS[1], 3.40, 0.86, 0.20, (1.5, 0.38, 1.0)),
                                 (JOINTS[2], 3.38, 0.90, 0.13, (1.4, 0.30, 0.75)),
                                 (120.0, 3.16, 1.055, 0.19, (1.1, 1.0, 0.30)),
                                 (150.0, 3.50, 0.17, 0.32, (1.25, 1.0, 0.28)),
                                 (108.0, 3.58, 0.16, 0.24, (1.1, 1.0, 0.26))):
        D.rock(bm, _polar(ang, r, z), rad, seed=int(ang) + 5, jitter=0.26, subdiv=0,
               scale=sc, rot=D.rot_euler(rz=ang))
    D.new_obj("Moss", bm, c, D.C("leaf_dark"), rbx_material="Grass", roughness=0.9)

    return c
