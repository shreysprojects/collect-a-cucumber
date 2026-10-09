"""Neon: Neon Slice - one upright cucumber slice ringed by a glowing fuchsia neon halo."""
import bmesh, math

COLLECTION = "NeonNeonSlice"
NOTES = ("ONE cucumber slice standing on its edge, cut face to +Y, belted by a glowing "
         "neon ring - the Neon biome's sliced-slot cucumber.  Footprint ~1.90 (X) x 0.50 "
         "(Y) x 1.90 (Z) studs, centred on x = y = 0; Y-extent is 0.26 x the X/Z extents, "
         "well under the 0.45 the game needs to lay it flat.  "
         "Rim: 10-sided drum r 0.82 x 0.42 thick, cuke_dark.  Face: lime cut face "
         "(slice_face inset 0.10, neo_lime) on both sides.  Studs (cuke_stud, one part): "
         "ten rim speckles 0.15 square, one per rim facet, alternating front and back "
         "rows either side of the halo, PLUS the face seeds - six green teardrop pips on "
         "each face, points toward the centre, one straight up and one straight down, "
         "0.015 proud.  Spokes: six pale radial bars between the pips out to 0.78 of the "
         "face radius plus a small pale 12-gon hub r 0.12 (cuke_pale), 0.02 proud.  "
         "Halo: a 20 x 6 torus (major 0.88, tube 0.07) round the rim in the disc's own "
         "plane, #f04dff, Neon, emit 0.6.  The HALO is the only ground contact: its "
         "lowest vertex sits on z = 0, so the disc itself hovers ~0.15 above the ground "
         "inside it (per the brief).  Five parts, ~1450 tris.  "
         "Deviations: (1) the tile shows six petal seeds with pale gaps between them, so "
         "the model adds seeds the brief does not list and has SIX spokes, one in each "
         "gap, not the brief's eight; the tile's seeds sample ~#7cf93f, a bright grass "
         "green only a step darker than the face, so they are cuke_stud (the nearest key) "
         "and, sharing colour + material with the rim speckles, live in the same Studs "
         "part (the brief's RimStuds, renamed); (2) the hub is r 0.12, not the Toy "
         "Slice's 0.18: the tile's pale centre is small and a 0.18 hub would cover the "
         "pip tips at r 0.15; (3) the halo colour is the tile's fuchsia, sampled at hue "
         "~295-300 deg (#f04dff), between neo_magenta and neo_purple rather than the "
         "brief's neo_purple; (4) the rim studs are hand-placed (ten, size 0.15, two rows "
         "at +-0.125 off the mid-plane) instead of slice_studs(n=6): on a 10-gon "
         "slice_studs(n=6) steps 2 facets and puts its sixth stud on top of its first, "
         "and its random z would bury most studs under the halo belt; (5) the Y-extent "
         "is 0.50, not ~0.46, which follows from the brief's own face (0.02) + spoke "
         "(0.02) proud numbers.  Everything is placed with the slice_stand matrix, so "
         "dryrun's bbox and its min_z warning are not meaningful.")

# ---------------------------------------------------------------- dimensions
R = 0.82                    # rim radius (the 10-gon's circumradius)
THICK = 0.42
SEGS = 10                   # lib phase 18 deg: a vertex points straight down once stood up
FACE_INSET = 0.10
FACE_PROUD = 0.02           # slice_face's default: the cut face sits 0.02 proud of the rim
FACE_R = R * (1.0 - FACE_INSET)          # 0.738, the cut face's circumradius
FACE_Z = THICK / 2.0 + FACE_PROUD        # 0.23, the cut-face surface in the disc frame

HALO_MAJOR = R + 0.06       # 0.88
HALO_MINOR = 0.07
HALO_SEGS = 20              # a multiple of 4, so one ring vertex points straight down
HALO_TUBE_SEGS = 6          # ... and tube vertex 0 points straight out from it

# Stood up with slice_stand, the disc's local +Y points world DOWN, so its lowest point
# is the halo's vertex at local angle 90 deg, (HALO_MAJOR + HALO_MINOR) below the centre.
CZ = HALO_MAJOR + HALO_MINOR             # 0.95

# In the disc's own frame an angle `a` in its XY plane lands in the world at
# (x, z) = (cos a, -sin a) * r + (0, CZ): local 0 = +X (screen-LEFT), 90 = DOWN, 270 = UP.
# Both patterns below are mirror-symmetric left/right and top/bottom.
SEED_ANGLES = (30.0, 90.0, 150.0, 210.0, 270.0, 330.0)   # one pip straight up + one down
SPOKE_ANGLES = (0.0, 60.0, 120.0, 180.0, 240.0, 300.0)   # one spoke in each gap

# a teardrop pip in (radial u, tangential v): point toward the hub, broad round outer end
SEED_UV = [(0.150, 0.000), (0.280, 0.080), (0.370, 0.095), (0.430, 0.070),
           (0.455, 0.000), (0.430, -0.070), (0.370, -0.095), (0.280, -0.080)]
SEED_PROUD = 0.015
SEED_SINK = 0.01

SPOKE_R0 = 0.05                          # starts under the hub
SPOKE_R1 = 0.78 * FACE_R                 # 0.576
SPOKE_W = 0.07
SPOKE_PROUD = 0.02
SPOKE_SINK = 0.01
HUB_R = 0.12
HUB_SEGS = 12                            # 6-fold, like the spokes

STUD_SIZE = 0.15
STUD_RISE = 0.04
STUD_SINK = 0.05
STUD_Z = 0.125               # the rows sit either side of the halo belt (|z| < 0.061)


def _turn(uv, theta_deg):
    """Rotate a (u, v) outline so its +u axis points along `theta_deg` in the disc plane."""
    t = math.radians(theta_deg)
    c, s = math.cos(t), math.sin(t)
    return [(u * c - v * s, u * s + v * c) for u, v in uv]


def _face_band(side, sink, proud):
    """(z_lo, z_hi) of a thin inlay sitting on the cut face on `side` (+1 front, -1 back)."""
    return tuple(sorted((side * (FACE_Z - sink), side * (FACE_Z + proud))))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    m = D.slice_stand((0.0, 0.0, CZ), lean_deg=0.0)      # upright, cut face to +Y

    # --- the dark green rind ---------------------------------------------------
    bm = bmesh.new()
    D.slice_disc(bm, radius=R, thick=THICK, segs=SEGS, matrix=m)
    D.new_obj("Rim", bm, c, D.C("cuke_dark"), rbx_material="SmoothPlastic")

    # --- the set's speckles on the rind: one per facet, rows alternating front/back,
    #     kept clear of the halo that belts the rim's middle -------------------------
    bm = bmesh.new()
    vs = []
    rr = R * math.cos(math.pi / SEGS)                    # rim facet-centre radius, 0.78
    for k in range(SEGS):
        a = 2.0 * math.pi * k / SEGS                     # facet centres: multiples of 36
        side = 1.0 if k % 2 == 0 else -1.0
        n = (math.cos(a), math.sin(a), 0.0)
        p = (n[0] * rr, n[1] * rr, side * STUD_Z)
        vs += D.stud_patch(bm, p, n, size=STUD_SIZE, rise=STUD_RISE, sink=STUD_SINK,
                           bevel=0.025)

    # --- ... and six green teardrop pips on each face.  Same colour + material as the
    #     rim speckles (the tile's pips are a bright grass green, ~#7cf93f, only a step
    #     darker than the lime face), so they share the one Studs part --------------
    for side in (1.0, -1.0):
        z0, z1 = _face_band(side, SEED_SINK, SEED_PROUD)
        for th in SEED_ANGLES:
            vs += D.prism(bm, _turn(SEED_UV, th), z0, z1)
    D.xform(bm, vs, m)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # --- the lime cut faces ------------------------------------------------------
    bm = bmesh.new()
    D.slice_face(bm, radius=R, thick=THICK, segs=SEGS, inset=FACE_INSET,
                 proud=FACE_PROUD, matrix=m)
    D.new_obj("Face", bm, c, D.C("neo_lime"), rbx_material="SmoothPlastic")

    # --- pale spokes in the gaps between the pips + a pale hub, each face ---------
    bm = bmesh.new()
    vs = []
    hw = SPOKE_W / 2.0
    bar = [(SPOKE_R0, -hw), (SPOKE_R1, -hw), (SPOKE_R1, hw), (SPOKE_R0, hw)]
    for side in (1.0, -1.0):
        z0, z1 = _face_band(side, SPOKE_SINK, SPOKE_PROUD)
        for th in SPOKE_ANGLES:
            vs += D.prism(bm, _turn(bar, th), z0, z1)
        vs += D.prism(bm, D.ngon_pts(HUB_SEGS, HUB_R), z0, z1)
    D.xform(bm, vs, m)
    D.new_obj("Spokes", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    # --- the neon halo: a ring hugging the rim in the disc's own plane ------------
    bm = bmesh.new()
    vs = D.torus(bm, (0.0, 0.0, 0.0), HALO_MAJOR, HALO_MINOR,
                 seg_major=HALO_SEGS, seg_minor=HALO_TUBE_SEGS)
    D.xform(bm, vs, m)
    D.new_obj("Halo", bm, c, "f04dff", rbx_material="Neon", emit=0.6)

    return c
