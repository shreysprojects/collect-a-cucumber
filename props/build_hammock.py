"""Slung hammock: two timber A-frames splayed along the hammock's OWN axis so the triangle
reads from the front and the outboard leg braces the pull, joined by a foot sled, a knee
rail and an apex cap.  The teal cloth bed is cut as transverse slices so its two long rims
sag on a catenary of their own and its plan narrows to a throat at each end; five of the
slices are cream, so the stripes are the surface and cost nothing in silhouette.  Each
throat is lashed through a chunky wooden spreader bar and roped from a steel ring up to an
eye on the post.  Runs along X.  The single pillow at the -X end is the deliberate
asymmetry."""
import bmesh

COLLECTION = "Hammock"
NOTES = ("10.64 wide (x) x 2.18 deep (y) x 3.16 tall, centred on the origin, sitting flat "
         "on z=0 via two foot sleds at x +/-2.48..5.32.  The bed is a slung sheet: its two "
         "long edges hang on their own catenary from z=2.14 at the throats (x +/-2.60) "
         "down to z=1.55 amidships, while the centreline drops further to z=1.25, so every "
         "cross-section is a shallow crescent and the underside bottoms at z=1.20 - a "
         "player drops into it from standing height and their feet still clear the ground. "
         "In plan the sheet is a lens: 2.18 wide at x=0, narrowing to 0.35 at the throats. "
         "Usable lie-down area is x -2.2..2.2, y -0.9..0.9 amidships.  The pillow is at the "
         "-X end only (x -2.15..-1.35) - that end is the head end, orient the sit/lie "
         "animation so the avatar's head goes to -X.  One rigid prop, no moving parts: if "
         "anyone wants a swinging version, hang the Bed/Weave/Cords objects off the two "
         "ring pivots below and leave Timber + Rails static.  Nothing sits below z=0.")
PIVOTS = {"RingPlusX": (3.04, 0.0, 2.10),     # steel ring at the +X (foot) end
          "RingMinusX": (-3.04, 0.0, 2.10),   # steel ring at the -X (pillow/head) end
          "BedLow": (0.0, 0.0, 1.20)}         # lowest point of the sag - the sit spot


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    post_c = D.C("wood_mid")        # A-frame legs + spreader bars (mid value)
    rail_c = D.C("wood_light")      # foot sleds, knee rails, apex caps (light value)
    bed_c = D.C("cloth_teal")       # the sheet
    trim_c = D.C("cloth_cream")     # woven stripes + pillow (highest value)
    rope_c = D.C("rope")            # lashings and tie ropes
    ring_c = D.C("metal_light")     # rings + the eye bosses on the posts

    # ---- the numbers the whole prop hangs off -----------------------------------
    BX, BZ = 2.60, 2.14                 # bed half-length, height of the two throats
    W0, W_END = 1.10, 0.175             # sheet half-width amidships / at the throat
    TH = 0.05                           # cloth thickness - a sheet, not a plank
    SX, LEG_T = 3.90, 0.17              # A-frame centre in x, half thickness of the timber
    SPLAY, APEX = 1.28, 0.20            # leg spread at the ground / half the apex width
    RING = (3.04, 0.0, 2.10)            # +X ring centre; the -X one mirrors
    EYE = (3.72, 0.0, 2.72)             # where the tie rope lands on the post
    BAR = (2.72, 2.96, 1.96, 2.24)      # spreader bar: x0, x1, z0, z1 (y is +/-0.50)

    # The bed is cut into transverse slices in x.  Each slice carries its own plan width
    # and its own crescent section, which is how the long rims get to sag instead of
    # running dead level.  Five slices are cream - the stripe IS the surface.
    XS = [-2.60, -2.42, -2.20, -1.60, -1.25, -0.65, -0.30,
          0.30, 0.65, 1.25, 1.60, 2.20, 2.42, 2.60]
    STRIPE = (2, 4, 6, 8, 10)           # cream slices: centres -1.90 -0.95 0 0.95 1.90

    # Sags are scaled so the deepest slice (the one cut at |x| = 0.30) lands the rim on
    # z 1.55 and the centreline on z 1.25 - i.e. the underside bottoms out at 1.20.
    F_DEEP = 1.0 - (0.30 / BX) ** 2
    MID_SAG, EDGE_SAG = 0.89 / F_DEEP, 0.59 / F_DEEP

    def sect(x):
        """(half-width, centreline z, rim z) the sheet is cut to at |x|."""
        f = max(0.0, 1.0 - (x / BX) ** 2)
        return (W_END + (W0 - W_END) * f ** 0.75,
                BZ - MID_SAG * f, BZ - EDGE_SAG * f)

    def slice_sect(i):
        """A slice is cut to the section of its OUTER end, so the taper stays monotone."""
        return sect(max(abs(XS[i]), abs(XS[i + 1])))

    def bed_top(x, y):
        """Top of the sheet at (x, y) - used to sit the lashings on the cloth."""
        for i in range(len(XS) - 1):
            if XS[i] <= x <= XS[i + 1]:
                w, mid, rim = slice_sect(i)
                t = min(1.0, abs(y) / w)
                return mid + (rim - mid) * t * t
        return BZ

    def span(a, b):
        """Ordered pair, so the same expression works mirrored to -X."""
        return (a, b) if a <= b else (b, a)

    # D.prism always extrudes along +Z.  Two mappings are used:
    #   SLICE_M = rot_euler(rx=90, rz=90) maps local (lx, ly, lz) to world (lz, lx, ly):
    #     the profile plane becomes (y, z) and the extrusion axis becomes world X - one
    #     transverse slice of the bed.
    #   rot_euler(rx=90) maps (lx, ly, lz) to (lx, -lz, ly): the profile plane becomes
    #     (x, z) and the extrusion axis becomes world Y - an A-frame that splays along X,
    #     with its 0.34 of timber thickness spanning y.
    SLICE_M = D.rot_euler(rx=90, rz=90)

    # ---- the two A-frames: legs splayed fore-and-aft, plus the spreader bars -----
    # Traced inboard foot -> up -> flat apex -> down -> outboard foot -> knee notch.
    aframe = [(-SPLAY, 0.00), (-APEX, 3.00), (APEX, 3.00), (SPLAY, 0.00),
              (SPLAY - 0.34, 0.00), (0.12, 2.34), (-0.12, 2.34), (0.34 - SPLAY, 0.00)]
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        D.prism(bm, aframe, -LEG_T, LEG_T,
                matrix=D.place(loc=(sx * SX, 0.0, 0.0), rot=D.rot_euler(rx=90)))
        # spreader bar - chunky and stood well outboard of the lashings, so it is the
        # readable element at each end instead of one more strand in the bundle
        bx0, bx1 = span(sx * BAR[0], sx * BAR[1])
        D.beveled_box(bm, (bx0, -0.50, BAR[2]), (bx1, 0.50, BAR[3]), bevel=0.06)
    D.new_obj("Timber", bm, c, post_c, rbx_material="Wood", roughness=0.74)

    # ---- foot sleds, knee rails and apex caps: the light timber -----------------
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        f0, f1 = span(sx * (SX - SPLAY - 0.14), sx * (SX + SPLAY + 0.14))
        D.beveled_box(bm, (f0, -0.35, 0.00), (f1, 0.35, 0.26), bevel=0.08)
        r0, r1 = span(sx * (SX - 0.62), sx * (SX + 0.62))
        D.beveled_box(bm, (r0, -0.26, 1.16), (r1, 0.26, 1.44), bevel=0.07)
        a0, a1 = span(sx * (SX - 0.34), sx * (SX + 0.34))
        D.beveled_box(bm, (a0, -0.26, 3.00), (a1, 0.26, 3.16), bevel=0.06)
    D.new_obj("Rails", bm, c, rail_c, rbx_material="Wood", roughness=0.70)

    # ---- the bed: a lens in plan, a crescent in section, rims on their own sag ---
    bm_bed, bm_trim = bmesh.new(), bmesh.new()
    for i in range(len(XS) - 1):
        w, mid, rim = slice_sect(i)
        d = rim - mid
        top = [(y, mid + d * (y / w) ** 2) for y in (-w, -w / 3.0, w / 3.0, w)]
        prof = top + [(y, z - TH) for (y, z) in reversed(top)]
        D.prism(bm_trim if i in STRIPE else bm_bed, prof, XS[i], XS[i + 1], matrix=SLICE_M)
    D.new_obj("Bed", bm_bed, c, bed_c, rbx_material="Fabric", roughness=0.88)

    # the one pillow, tilted to lie along the local slope of the sag, rides in the
    # cream bmesh: same cloth, same material, no extra part
    D.beveled_box(bm_trim, (-2.15, -0.33, 1.81), (-1.35, 0.33, 2.07), bevel=0.09,
                  rot=D.rot_euler(ry=25))
    D.new_obj("Weave", bm_trim, c, trim_c, rbx_material="Fabric", roughness=0.86)

    # ---- cordage: four lashings gathering each throat, one thick tie rope --------
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        for y in (-0.28, -0.095, 0.095, 0.28):
            p0 = (sx * 2.30, y, bed_top(2.30, y) + 0.035)   # bitten into the cloth
            p1 = (sx * 2.58, y * 0.45, 2.205)               # over the gathered throat
            p2 = (sx * 2.82, y * 0.16, 2.135)               # stopped inside the bar
            D.tube(bm, [p0, p1, p2], [0.075, 0.073, 0.068], segs=4)
        D.rope(bm, (sx * (BAR[1] + 0.02), 0.0, RING[2]), (sx * (EYE[0] - 0.06), 0.0, EYE[2]),
               sag=0.02, radius=0.11, n=4, segs=5)
    D.new_obj("Cords", bm, c, rope_c, rbx_material="Fabric", roughness=0.82)

    # ---- steel: the two gather rings and the eye bosses they tie back to --------
    bm = bmesh.new()
    for sx in (1.0, -1.0):
        D.torus(bm, (sx * RING[0], RING[1], RING[2]), 0.22, 0.07,
                rot=D.rot_euler(rx=90), seg_major=8, seg_minor=4)
        D.cyl(bm, (sx * EYE[0], -0.26, EYE[2]), (sx * EYE[0], 0.26, EYE[2]), 0.11, segs=6)
    D.new_obj("Rings", bm, c, ring_c, rbx_material="Metal", metallic=0.70, roughness=0.35)

    return c
