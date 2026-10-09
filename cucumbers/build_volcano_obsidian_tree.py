"""Volcano: Obsidian Tree - a black glass tree with GREEN cucumbers hanging off it."""
import bmesh, math

COLLECTION = "VolcanoObsidianTree"
NOTES = ("An 11.4-stud obsidian tree carrying green cucumbers.  A three-step black-glass "
         "plinth with four sharp splinters bursting out of it, a tapering blocky trunk "
         "whose blocks shear a few degrees against each other, and four straight square "
         "branches forking out to carry the crown.  The crown is NOT cubes: six angular "
         "obsidian boulders (D.rock, jitter 0.22) piled on the forks so it reads as a heap "
         "of shattered black glass.  Orange lava cracks (Neon) glow across those rocks, up "
         "two corners and the front of the trunk, and along the tops of two branches.  "
         "Hanging under the branches are THREE ordinary cucumber-green cucumbers "
         "(CUKE_PROFILE_STUB, h 2.0, r 0.36) with cuke_stud speckles - the green fruit is "
         "the point of the model.  Faces +Y, centred on x=0/y=0, footprint about "
         "6.9 x 5.7, 11.4 tall.  Five parts: Trunk, Rocks, Cracks, Cukes, CukeStuds.")

# ---- trunk ---------------------------------------------------------------
BASE_TOP_W, BASE_H = 1.55, 1.55
TRUNK_Z0, TRUNK_Z1 = 1.55, 6.15
TRUNK_W0, TRUNK_W1 = 1.36, 0.98

# (end x, end y, end z, start z) for each fork
BRANCHES = [
    (-1.80, 0.30, 8.05, 5.25),
    (1.90, -0.25, 8.35, 5.05),
    (-0.95, -1.55, 7.80, 5.55),
    (1.05, 1.45, 7.95, 5.55),
]

# obsidian splinters out of the plinth: (base, tip, radius)
SHARDS = [
    ((0.95, 0.85, 0.62), (1.58, 1.36, 1.88), 0.17),
    ((-1.02, 0.76, 0.55), (-1.74, 1.20, 1.70), 0.15),
    ((0.86, -0.98, 0.58), (1.36, -1.70, 1.96), 0.16),
    ((-0.90, -0.94, 0.50), (-1.46, -1.52, 1.58), 0.14),
]

# ---- crown: angular obsidian rock, not cubes ------------------------------
# (x, y, z, radius, seed, scale, rot, [crack polylines as [(azimuth, elevation), ...]])
# azimuth 90 = +Y (the front), elevation 90 = straight up.  Each rock is a 12-vert
# icosahedron with 22% radial jitter: hard flat facets, like a broken glass boulder.
ROCKS = [
    (0.05, 0.05, 9.80, 1.42, 11, (1.06, 0.94, 0.96), (0.0, 0.0, 24.0),
     [[(70, 46), (88, 22), (72, -2), (92, -28)],
      [(146, 34), (126, 12), (140, -12)],
      [(14, 28), (-4, 6), (10, -18)]]),
    (1.90, -0.30, 8.86, 1.24, 23, (0.96, 1.08, 0.92), (12.0, -9.0, -38.0),
     [[(30, 34), (10, 12), (26, -12), (6, -34)],
      [(102, 20), (84, -2)]]),
    (-1.95, 0.32, 8.58, 1.26, 37, (1.04, 0.94, 1.00), (-10.0, 14.0, 62.0),
     [[(160, 36), (176, 14), (156, -10)],
      [(118, 10), (102, -14), (116, -34)]]),
    (-0.85, -1.42, 8.26, 1.15, 51, (1.00, 1.02, 0.94), (16.0, 8.0, -74.0),
     [[(278, 30), (298, 8), (284, -16)]]),
    (0.95, 1.38, 8.44, 1.18, 67, (0.98, 0.96, 1.06), (-14.0, -12.0, 108.0),
     [[(78, 30), (96, 6), (76, -18)]]),
    (0.15, -0.18, 7.92, 1.10, 83, (1.08, 0.96, 0.86), (9.0, 15.0, 150.0),
     [[(58, 22), (42, -4)],
      [(126, 16), (144, -8)]]),
]

# ---- glowing cracks up the trunk: (points, radii) -------------------------
TRUNK_VEINS = [
    ([(0.12, 0.70, 1.80), (-0.10, 0.66, 2.80), (0.14, 0.62, 3.80),
      (-0.08, 0.58, 4.80), (0.10, 0.55, 5.72)],
     [0.078, 0.068, 0.062, 0.055, 0.046]),
    ([(-0.70, 0.18, 1.78), (-0.66, -0.12, 2.74), (-0.62, 0.10, 3.72),
      (-0.58, -0.10, 4.70)],
     [0.072, 0.062, 0.055, 0.044]),
    ([(0.63, -0.14, 3.56), (0.60, 0.10, 4.34), (0.57, -0.10, 5.12),
      (0.54, 0.06, 5.86)],
     [0.066, 0.058, 0.050, 0.040]),
]

# which forks get a vein running out along them
VEINED_BRANCHES = (1, 2)

# ---- hanging cucumbers: (x, y, top z, height, radius, lean deg, turn deg) --
HANGING = [
    (-1.68, 0.16, 7.52, 2.05, 0.36, 6.0, 14.0),
    (1.74, -0.46, 7.74, 1.95, 0.35, -7.0, -22.0),
    (-0.92, -1.42, 7.34, 2.00, 0.36, 4.0, 40.0),
]

# taper of a crack tube, point by point
CRACK_TAPER = (0.086, 0.074, 0.060, 0.046)


def _sph(center, radius, az_deg, el_deg):
    """A point on the sphere of `radius` about `center` at (azimuth, elevation)."""
    az, el = math.radians(az_deg), math.radians(el_deg)
    return (center[0] + radius * math.cos(el) * math.cos(az),
            center[1] + radius * math.cos(el) * math.sin(az),
            center[2] + radius * math.sin(el))


def _rock_crack(D, bm, ctr, rr, line):
    """One glowing seam laid over a crown boulder, following its surface."""
    pts = [_sph(ctr, rr * 1.05, az, el) for az, el in line]
    k = rr / 1.30
    radii = [CRACK_TAPER[min(i, len(CRACK_TAPER) - 1)] * k for i in range(len(pts))]
    D.tube(bm, pts, radii, segs=5)


def _branch_vein(D, bm, end, z0):
    """A seam running out along the outer face of one fork."""
    bx, by, bz = end
    hx, hy = bx, by
    L = math.hypot(hx, hy) or 1.0
    hx, hy = hx / L, hy / L
    pts, radii = [], []
    for t in (0.32, 0.62, 0.94):
        off = 0.30 - 0.10 * t + 0.03
        pts.append((bx * t + hx * off, by * t + hy * off, z0 + (bz - z0) * t))
        radii.append(0.070 - 0.024 * t)
    D.tube(bm, pts, radii, segs=5)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- black glass: plinth, shards, trunk, forks -------------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=BASE_TOP_W, h=BASE_H, steps=3, grow=1.30, bevel=0.07)
    for a, b, rr in SHARDS:
        D.spike(bm, a, b, rr, segs=4)
    D.blocky_trunk(bm, TRUNK_Z0, TRUNK_Z1, TRUNK_W0, TRUNK_W1, blocks=3, bevel=0.07,
                   twist=7.0)
    for (bx, by, bz, z0) in BRANCHES:
        D.branch_box(bm, (0.0, 0.0, z0), (bx, by, bz), 0.60, 0.40, bevel=0.05)
    D.new_obj("Trunk", bm, c, D.C("vol_obsidian"), rbx_material="Basalt", roughness=0.32)

    # ---- crown of shattered obsidian boulders ------------------------------
    bm = bmesh.new()
    for (x, y, z, rr, seed, scale, rot, _cracks) in ROCKS:
        D.rock(bm, (x, y, z), rr, seed=seed, jitter=0.22, subdiv=1, scale=scale,
               rot=D.rot_euler(*rot))
    D.new_obj("Rocks", bm, c, D.C("vol_obsidian"), rbx_material="Slate", roughness=0.32,
              metallic=0.0)

    # ---- orange lava glowing through the glass -----------------------------
    bm = bmesh.new()
    for (x, y, z, rr, _seed, _scale, _rot, cracks) in ROCKS:
        for line in cracks:
            _rock_crack(D, bm, (x, y, z), rr, line)
    for pts, radii in TRUNK_VEINS:
        D.tube(bm, pts, radii, segs=5)
    for i in VEINED_BRANCHES:
        bx, by, bz, z0 = BRANCHES[i]
        _branch_vein(D, bm, (bx, by, bz), z0)
    D.new_obj("Cracks", bm, c, D.C("vol_lava"), rbx_material="Neon", emit=0.65)

    # ---- the green cucumbers hanging under the branches --------------------
    bm = bmesh.new()
    bm2 = bmesh.new()
    for i, (x, y, ztop, hh, rr, lean, turn) in enumerate(HANGING):
        m = D.place((x, y, ztop - hh), D.rot_euler(lean, 0.0, turn))
        D.cuke_body(bm, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, nub=(0.17, 0.16),
                    matrix=m)
        D.cuke_studs(bm2, h=hh, r=rr, profile=D.CUKE_PROFILE_STUB, rows=3, per_row=2,
                     z0=0.20, z1=0.82, size=0.16, rise=0.038, seed=30 + i, matrix=m)
    D.new_obj("Cukes", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")
    D.new_obj("CukeStuds", bm2, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
