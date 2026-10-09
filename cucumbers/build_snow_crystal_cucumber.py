"""Snow: the Crystal Cucumber - a green cucumber with ice crystals growing up around it."""
import bmesh, math

COLLECTION = "SnowCrystalCucumber"
NOTES = ("A STANDARD GREEN CUCUMBER with pale-blue ice crystals growing up around it - "
         "the cucumber is the model, the ice is what the snow biome has done to it.  "
         "Dead centre stands the set's reference body: `cuke_green`, h 4.0, r 0.68, the "
         "usual (0.30, 0.30) stem nub, sixteen `cuke_stud` speckles laddered up it from "
         "zf 0.11 to 0.90 - none of that is hidden, the green reads from every side.  "
         "Seven `snow_crystal` ice spires (Ice, transparency 0.18) rise out of the "
         "ground around its foot on a wide height ladder - 1.20, 1.55, 1.90, 2.35, "
         "2.70, 3.05, 3.40 - radii 0.22-0.40, each at its own bearing and each leaning "
         "9-21 degrees straight OUTWARD from the body (rot_euler(lean, 0, bearing + 90)) "
         "so the cluster splays like real ice.  The two tallest sit at the SIDES "
         "(bearings 8 and 180, i.e. screen left and screen right) where they flank the "
         "cucumber in silhouette without covering it; the three across the FRONT "
         "(bearings 55, 100, 145) are the three shortest, 1.20-1.90, so they only reach "
         "the cucumber's waist and its face is never swallowed.  Each spire's foot is "
         "lifted just clear of the ground by its own lean and stands on a low hexagonal "
         "ice stump (z 0 to 0.15-0.19) turned to match that spire's own hexagon, so "
         "nothing floats and nothing dips below z = 0.  Three smaller crystals grow "
         "straight OUT of the body's upper third - off the skin at height fractions "
         "0.66, 0.74 and 0.86, leaning 22-32 degrees - the tallest of them (bearing "
         "210, screen right and slightly back) reaching z 4.94, a shade over the nub, "
         "which is what sets the model's 5.0 height.  Fourteen `snow_white` raised "
         "square speckles - the set's signature, two on each big crystal and one on "
         "every smaller one - are snapped to real facet CENTRES computed off each "
         "spire's own lathe profile, so they sit dead flat on the ice, and always on "
         "that spire's most camera-facing faces.  Footprint about 2.9 x 2.5, "
         "height 4.95.  Centred on x=0, y=0; every crystal is placed with a matrix, so "
         "dryrun's transform-blind bounding box under-reads the width.  "
         "4 parts: Body, Studs, Crystals, CrystalStuds.")

# ---------------------------------------------------------------- the crystals
SEGS = 6                      # every spire is 6-sided, like D.crystal_spire
TAPER, TIP = 0.56, 0.32

# The ground ring.  `az` is the bearing of the spire's foot measured from +X
# anticlockwise, so +Y (90) is the camera side and +X (0) is screen LEFT.  Each spire
# leans along that same bearing - outward, away from the cucumber.  The heights step
# 1.20 / 1.55 / 1.90 / 2.35 / 2.70 / 3.05 / 3.40; the three SHORT ones are the three
# across the front so the body's face stays clear, the two tall ones flank it at the
# sides.  None of them reaches the 4.0 body top.
#          az,   foot r, height, radius, lean
SPIRES = [
    (  8.0,  0.84,  3.40,  0.40,   9.0),    # screen left  - the tallest
    ( 55.0,  0.80,  1.55,  0.25,  19.0),    # front left
    (100.0,  0.78,  1.20,  0.22,  21.0),    # front centre - the runt, clears the view
    (145.0,  0.82,  1.90,  0.28,  16.0),    # front right
    (180.0,  0.84,  3.05,  0.38,  11.0),    # screen right - the second tallest
    (232.0,  0.84,  2.35,  0.32,  13.0),    # back right
    (296.0,  0.84,  2.70,  0.35,  12.0),    # back left
]

# The small crystals growing out of the body itself, higher up.  They are based ON the
# skin (sunk 0.06 into it) and lean out harder than the ground ring.
#       az,    zf,  height, radius, lean
TOP = [
    (125.0, 0.66,  1.05,  0.20,  32.0),     # front right, low on the shoulder
    (330.0, 0.74,  1.25,  0.23,  27.0),     # back left
    (210.0, 0.86,  1.62,  0.26,  22.0),     # screen right - the one that tops the model
]

# ---------------------------------------------------------------- the speckles
# (facet RANK from the camera - 0 is that spire's most front-on face -, height fraction).
# Ranking rather than naming a facet index keeps every speckle turned toward the viewer
# whatever the spire's yaw.  Only the bigger crystals carry them.
BIG_STUDS = [(0, 0.22), (1, 0.46)]      # h >= 2.3 - two of them
MID_STUDS = [(0, 0.30)]                 # 1.5 <= h < 2.3
LIL_STUDS = [(0, 0.34)]                 # the runts still get one - it is the set's mark
STUD_RISE = 0.045


def _slots_for(height):
    if height >= 2.3:
        return BIG_STUDS
    if height >= 1.5:
        return MID_STUDS
    return LIL_STUDS


def _stud_size(radius):
    return max(0.13, min(0.22, radius * 0.55))


def _spire_profile(height, radius, taper=TAPER, tip=TIP):
    """D.crystal_spire's own (radius, z) lathe profile, so the speckles can be put on
    the skin it actually builds instead of a guess at it."""
    shaft = height * (1.0 - tip)
    return [(0.0, 0.0), (radius * 0.92, 0.0), (radius, shaft * 0.22),
            (radius * taper, shaft),
            (radius * taper * 0.62, shaft + tip * height * 0.45),
            (0.0, height)]


def _front_facets(yaw_deg, segs=SEGS):
    """That spire's facet indices, most camera-facing (+Y) first.

    crystal_spire lathes with phase = pi/segs, which puts its facet CENTRES at exact
    multiples of 360/segs in the spire's own frame; `yaw_deg` swings them into world."""
    return sorted(range(segs),
                  key=lambda f: -math.cos(math.radians(yaw_deg + 360.0 * f / segs - 90.0)))


def _skin_point(profile, facet, zf, segs=SEGS):
    """(point, outward normal) at a facet's CENTRE, in the spire's own frame.

    `zf` is a fraction of the spire's height.  A facet centre sits at the band's
    INRADIUS, and its normal carries the band's slope, so a square dropped here lies
    dead flat on the crystal."""
    z = profile[-1][1] * float(zf)
    bands = [(profile[i], profile[i + 1]) for i in range(len(profile) - 1)
             if profile[i + 1][1] > profile[i][1] + 1e-9]
    lo, hi = bands[0]
    for lo, hi in bands:
        if z <= hi[1]:
            break
    dr, dz = hi[0] - lo[0], hi[1] - lo[1]
    t = max(0.0, min(1.0, (z - lo[1]) / dz))
    ring = lo[0] + dr * t
    k = math.cos(math.pi / segs)
    a = 2.0 * math.pi * facet / segs
    nx, ny, nz = math.cos(a) * dz, math.sin(a) * dz, -dr * k
    n = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return ((math.cos(a) * ring * k, math.sin(a) * ring * k, z),
            (nx / n, ny / n, nz / n))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ------------------------------------------------------------ the cucumber
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=8, per_row=2, z0=0.11, z1=0.90,
                 size=0.28, rise=0.055, seed=7)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ------------------------------------------------------------ plan the ice
    # (base, rot, height, radius, yaw, stump) - stump is None for the ones growing
    # out of the body, a (x, y, top_z) for the ones standing on the ground.
    plan = []
    for az, foot, h, r, lean in SPIRES:
        a, la = math.radians(az), math.radians(lean)
        yaw = az + 90.0                       # tips the spire along its own bearing
        dip = r * 0.92 * math.sin(la)         # how far the tilted foot disc drops
        bz = dip + 0.02                       # ... so its low edge just clears z = 0
        x, y = math.cos(a) * foot, math.sin(a) * foot
        plan.append(((x, y, bz), D.rot_euler(lean, 0.0, yaw), h, r, yaw,
                     (x, y, bz + dip + 0.02)))
    for az, zf, h, r, lean in TOP:
        yaw = az + 90.0
        base = D.cuke_point(h=H, r=R, zf=zf, angle_deg=az, offset=-0.06)
        plan.append((base, D.rot_euler(lean, 0.0, yaw), h, r, yaw, None))

    # ------------------------------------------------------------ the ice spires
    bm = bmesh.new()
    for base, rot, h, r, yaw, stump in plan:
        if stump is not None:                 # a low hex stump so nothing floats,
            sx, sy, sz = stump                # turned to match this spire's hexagon
            D.prism(bm, D.ngon_pts(SEGS, r * 0.97,
                                   phase=math.pi / SEGS + math.radians(yaw),
                                   center=(sx, sy)), 0.0, sz)
        D.crystal_spire(bm, base=base, height=h, radius=r, segs=SEGS,
                        taper=TAPER, tip=TIP, rot=rot)
    D.new_obj("Crystals", bm, c, D.C("snow_crystal"), rbx_material="Ice",
              transparency=0.18, roughness=0.32)

    # ------------------------------------------------------------ the speckles
    bm = bmesh.new()
    for base, rot, h, r, yaw, _stump in plan:
        slots = _slots_for(h)
        if not slots:
            continue
        prof = _spire_profile(h, r)
        facets = _front_facets(yaw)
        size = _stud_size(r)
        vs = []
        for rank, zf in slots:
            p, n = _skin_point(prof, facets[rank], zf)
            vs += D.stud_patch(bm, p, n, size=size, rise=STUD_RISE, bevel=0.026)
        D.xform(bm, vs, D.place(base, rot))    # the spire's own matrix, so they ride it
    D.new_obj("CrystalStuds", bm, c, D.C("snow_white"), rbx_material="Snow",
              roughness=0.6)

    return c
