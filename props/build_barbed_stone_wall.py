"""Prison-yard wall tile: battered running-bond masonry on a plinth, a dressed capstone
course, moss in two recesses, and iron arms leaning out over +Y carrying three strands of
barbed wire.  Faces +Y and butts cleanly with copies of itself at x = +/-4."""
import bmesh, math, random

COLLECTION = "BarbedStoneWall"
NOTES = (
    "Wall tile: 8.0 wide (x -4..4), ~2.3 deep, ~7.7 tall.  Copy it every 8 studs along X. "
    "Running bond: the B courses (1, 3) and the coping carry HALF stones that run 0.14 "
    "PAST the seam - more than their 0.07 chamfer, so a neighbour's chamfered end is "
    "buried instead of meeting it as a shadow-catching V-notch - and those halves are "
    "built with a fixed depth, a fixed seed and no vertex jitter so tile N's right half "
    "and tile N+1's left half are identical geometry and merge into one stone.  The A "
    "courses (0, 2, 4) instead put a REAL 0.05 mortar joint on the seam with a tone "
    "change across it, so the bond alternates joint / whole stone / joint all the way "
    "along a run.  The plinth and the two end capstones overlap by the same 0.14.  The "
    "two boundary iron arms are HALF arms so a neighbouring pair makes one whole arm on "
    "the shared joint, and the three wire strands start and stop exactly on x = +/-4 at "
    "identical heights, sampled on an even number of spans so their barbs step across the "
    "seam at the strand's own spacing and never land inside an arm.  Stone body tops out "
    "at z 5.20, capstone at 5.62, the arms at ~7.53, the top strand at 7.34 with its "
    "barbs reaching ~7.66.  A cheap hidden dark core box "
    "behind the courses stops daylight showing through the mortar joints.  Static prop, "
    "no moving parts."
)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    HW = 4.0                 # tile half width - the tiling seam
    OVER = 0.14              # how far seam-crossing stone runs past the seam.  MUST stay
                             # clear of the 0.07 bevel below: two chamfered ends that only
                             # half overlap meet as a V-notch and print a dark line at
                             # every joint of a tiled run.
    MJ_X, MJ_Z = 0.025, 0.015   # mortar joint insets on interior block edges

    light, mid, dark = D.C("stone_light"), D.C("stone_mid"), D.C("stone_dark")
    iron, steel, green = D.C("iron_dark"), D.C("metal_mid"), D.C("moss")
    rust = D.C("iron_rust")

    # ---------------------------------------------------------------- plinth footing
    bm = bmesh.new()
    D.beveled_box(bm, (-HW - OVER, -0.74, 0.00), (HW + OVER, 0.74, 0.28), bevel=0.07)
    D.new_obj("Plinth", bm, c, dark, rbx_material="Slate", roughness=0.88)

    # ---------------------------------------------------------------- stone courses
    # Running bond: 'A' courses have a real mortar joint ON the seam (their end stones
    # stop at +/-(HW - MJ_X) like every other joint in the wall, and the tones either side
    # of it differ so it reads as a joint, not as a butted panel edge); 'B' courses are
    # offset half a block so their outermost stones are HALF stones that run past x = +/-4
    # and merge with the neighbouring tile's half into one whole stone.
    W = 8.0 / 3.0
    EDGES = {"A": [-HW, -HW + W, -HW + 2 * W, HW],
             "B": [-HW, -HW + W / 2.0, -HW + W / 2.0 + W, -HW + W / 2.0 + 2 * W, HW]}
    COURSE_Z = [0.28, 1.30, 2.28, 3.26, 4.24, 5.20]
    HALF_D = [0.70, 0.66, 0.62, 0.58, 0.54]        # the batter: each course steps back
    KIND = ["A", "B", "A", "B", "A"]
    # A-course ends must DIFFER (they meet across the seam joint); B-course ends must
    # MATCH (they are two halves of the same stone).
    TONE = [["mid", "light", "dark"],
            ["light", "mid", "dark", "light"],
            ["dark", "mid", "light"],
            ["mid", "light", "dark", "mid"],
            ["light", "mid", "dark"]]
    RECESS = {(1, 1): 0.13, (3, 2): 0.11}          # the two sunken stones that hold moss

    hexes = {"light": light, "mid": mid, "dark": dark}
    beds = {k: bmesh.new() for k in hexes}

    # hidden core so a jittered mortar joint never becomes a window
    D.box(beds["dark"], (-HW - 0.03, -0.34, 0.20), (HW + 0.03, 0.34, 5.30))

    rng = random.Random(90209)
    for ci in range(5):
        z0, z1 = COURSE_Z[ci], COURSE_Z[ci + 1]
        hd, edges = HALF_D[ci], EDGES[KIND[ci]]
        last = len(edges) - 2
        halved = KIND[ci] == "B"       # this course carries half stones over the seam
        for bi in range(last + 1):
            crosses = halved and (bi == 0 or bi == last)
            xa = edges[0] - OVER if (crosses and bi == 0) else edges[bi] + MJ_X
            xb = edges[last + 1] + OVER if (crosses and bi == last) else edges[bi + 1] - MJ_X
            za = z0 if ci == 0 else z0 + MJ_Z
            zb = z1 if ci == 4 else z1 - MJ_Z
            back = -hd - rng.uniform(0.0, 0.05)
            front = hd + rng.uniform(-0.04, 0.05) - RECESS.get((ci, bi), 0.0)
            seed, jit = 17 * ci + 5 * bi + 3, 0.04
            if crosses:
                # The two halves of a stone that straddles the seam live on different
                # tiles, so they have to be the SAME stone: identical width already, plus
                # a depth and a seed taken from the course alone and no vertex jitter at
                # all.  Any difference here shows up as a shadow line down the joint.
                back, front, seed, jit = -hd - 0.025, hd + 0.015, 17 * ci, 0.0
            D.stone_block(beds[TONE[ci][bi]], (xa, back, za), (xb, front, zb),
                          seed=seed, jitter=jit, bevel=0.07)

    D.new_obj("CoursesLight", beds["light"], c, light, rbx_material="Cobblestone", roughness=0.9)
    D.new_obj("CoursesMid", beds["mid"], c, mid, rbx_material="Cobblestone", roughness=0.9)
    D.new_obj("CoursesDark", beds["dark"], c, dark, rbx_material="Cobblestone", roughness=0.92)

    # ---------------------------------------------------------------- capstone course
    # offset from the top course so the coping breaks its joints; one stone has settled.
    bm = bmesh.new()
    cap = EDGES["B"]
    for bi in range(len(cap) - 1):
        xa = cap[bi] - OVER if bi == 0 else cap[bi] + 0.02
        xb = cap[bi + 1] + OVER if bi == len(cap) - 2 else cap[bi + 1] - 0.02
        if bi == 1:                                  # the loose, settled coping stone
            D.beveled_box(bm, (xa, -0.68, 5.16), (xb, 0.80, 5.58), bevel=0.06,
                          rot=D.rot_euler(rx=3.5))
        else:
            D.beveled_box(bm, (xa, -0.68, 5.20), (xb, 0.80, 5.62), bevel=0.06)
    D.new_obj("Capstones", bm, c, light, rbx_material="Slate", roughness=0.7)

    # ---------------------------------------------------------------- moss accents
    bm = bmesh.new()
    D.uvsphere(bm, (-1.95, 0.60, 1.34), 0.30, segs=6, rings=3, scale=(1.5, 0.55, 0.42))
    D.uvsphere(bm, (-0.85, 0.58, 1.31), 0.22, segs=6, rings=2, scale=(1.3, 0.50, 0.45))
    D.uvsphere(bm, (-2.25, 0.54, 1.76), 0.20, segs=6, rings=2, scale=(1.0, 0.35, 1.6))
    D.uvsphere(bm, (1.35, 0.52, 3.30), 0.26, segs=6, rings=3, scale=(1.6, 0.50, 0.40))
    D.new_obj("Moss", bm, c, green, rbx_material="LeafyGrass", roughness=0.95)

    # ---------------------------------------------------------------- ironwork
    # arm axis: starts inside the coping at (y -0.36, z 5.46) and rises 50 deg toward +Y.
    ARMS = [(0.0, 0.170), (HW - 0.065, 0.105), (-HW + 0.065, 0.105)]
    bm = bmesh.new()
    for (cx, hx) in ARMS:
        D.beveled_box(bm, (cx - hx, -0.60, 5.26), (cx + hx, -0.08, 5.98), bevel=0.06)
        D.beveled_box(bm, (cx - hx, 0.319, 5.158), (cx + hx, 0.619, 7.738), bevel=0.06,
                      rot=D.rot_euler(rx=-40))
    D.new_obj("Ironwork", bm, c, iron, rbx_material="Metal", metallic=0.6, roughness=0.5)

    # ---------------------------------------------------------------- anchor plate
    # One rusted tie plate, off centre - the detail that stops the tile reading as a
    # mirror of itself.  (+X is screen LEFT, so this sits on the viewer's right.)  It is
    # rust, not iron_dark: near-black on stone reads as a HOLE, and the bolts, the chamfer
    # and the ring hanging off the bottom edge are what say "iron fitting" at distance.
    px, pz = -2.30, 3.79
    bm = bmesh.new()
    D.beveled_box(bm, (px - 0.425, 0.50, pz - 0.375), (px + 0.425, 0.78, pz + 0.375),
                  bevel=0.06)
    for (bx, bz) in ((-0.30, -0.26), (0.30, -0.26), (-0.30, 0.26), (0.30, 0.26)):
        D.cyl(bm, (px + bx, 0.72, pz + bz), (px + bx, 0.90, pz + bz), 0.08, segs=6)
    D.torus(bm, (px, 0.70, pz - 0.42), 0.18, 0.055, rot=D.rot_euler(rx=90),
            seg_major=8, seg_minor=4)
    D.new_obj("AnchorPlate", bm, c, rust, rbx_material="CorrodedMetal",
              metallic=0.3, roughness=0.85)

    # ---------------------------------------------------------------- barbed wire
    # Three strands threaded through the arms and sagging hard between the supports at
    # x = -4, 0, +4.  Each strand is sampled on an EVEN number of spans, so the sample at
    # x = 0 is pinned up at the middle arm and - since barbs land on every second sample -
    # never carries a barb; the barbs step across the seam at the strand's own spacing.
    # `skew` slides the interior samples without moving the three pinned ones, so the top
    # strand's barbs do not stack on the bottom strand's.
    STRANDS = [(0.237, 6.172, 0.35, 16, 0.00, 11),   # (y, z, sag, spans, skew, seed)
               (0.751, 6.784, 0.28, 12, 0.00, 23),
               (1.215, 7.337, 0.20, 16, 0.26, 37)]
    bm = bmesh.new()
    for (wy, wz, sag, spans, skew, seed) in STRANDS:
        pts = []
        for i in range(spans + 1):
            t = i / float(spans)
            x = -HW + 2.0 * HW * t
            if 0 < i < spans:
                x += skew * math.sin(2.0 * math.pi * t)
            u = (x + HW) / HW if x < 0 else x / HW
            pts.append((x, wy, wz - sag * 4.0 * u * (1.0 - u)))
        D.barbed_wire(bm, pts, wire_r=0.09, segs=4, barb_every=2,
                      barb_len=0.32, seed=seed)
    D.new_obj("BarbedWire", bm, c, steel, rbx_material="Metal", metallic=0.7, roughness=0.35)

    return c
