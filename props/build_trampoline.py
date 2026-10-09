"""Round backyard trampoline: a steel frame ring on three W-legs, sixteen springs left out
in the open, a narrow blue rim collar and a deep-dished black jump mat.  Faces +Y - the
safety label sits on the front-right of the pad (negative x = screen right)."""
import bmesh, math

COLLECTION = "Trampoline"
NOTES = ("8.0 studs across (the pad rim is the widest thing, r = 4.00) and 1.62 tall at the "
         "pad; the six rubber feet plant flat on z = 0 inside that footprint so it drops "
         "straight onto a plot with no overhang.  The jump surface is MatSurface: a dish "
         "whose rim sits at z 1.20 (r 2.95) and drops to z 0.68 in the middle - stand-on "
         "height is ~0.7 at the centre, ~1.2 at the edge.  The pad is only a 0.70-wide "
         "collar (r 3.30 -> 4.00), so a 0.35-stud ring of daylight is left open between the "
         "mat rim and the pad's inner lip: the sixteen springs and the lower half of the "
         "frame tube read through it from any above-horizon angle, which is what makes it a "
         "trampoline and not a paddling pool.  DO NOT widen the pad inwards or sink the prop "
         "into the ground - both close that gap.  THE GAME ANIMATES THE Mat* PARTS: drop "
         "them straight down and spring them back for the bounce (see STATES; the frame, "
         "pad, springs and feet never move).  Bottom is -0.50, which leaves the mat's "
         "underside at z 0.09 - do not push it deeper or the mat goes through the floor.")
PIVOTS = {"MatCentre": (0.0, 0.0, 0.68)}
STATES = {"Rest": 0.0, "Bottom": -0.50}      # z offset applied to every Mat* part


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    SEG = 16            # radial facets on frame / pad / mat - chunky but round enough
    R_FRAME = 3.55      # frame-tube centreline radius
    Z_FRAME = 1.24
    Z_MAT_C = 0.68      # mat centre (matches PIVOTS)
    R_MAT = 2.95        # mat rim - the inner edge of the open spring band
    R_PAD_IN = 3.30     # pad inner lip - the outer edge of the open spring band

    steel = D.C("metal_mid")
    bright = D.C("steel_bright")
    padcol = D.C("plastic_blue")
    black = D.C("rubber_black")

    def polar(a_deg, r, z):
        a = math.radians(a_deg)
        return (math.cos(a) * r, math.sin(a) * r, z)

    LEGS = (90.0, 210.0, 330.0)          # azimuth of each W-shaped leg pair
    FOOT_A = 24.0                        # +/- azimuth of the two feet in a pair
    FOOT_R = 3.72

    # ---- frame ring + the three W-legs, one welded steel object -------------
    bm = bmesh.new()
    D.torus(bm, (0.0, 0.0, Z_FRAME), R_FRAME, 0.19, seg_major=SEG, seg_minor=5)
    for a in LEGS:
        # attach - down to foot 1 - short flat run - back up to the frame - foot 2 - attach
        pts = [polar(a - 46, R_FRAME, Z_FRAME),
               polar(a - FOOT_A, 3.84, 0.24),
               polar(a - FOOT_A, 3.60, 0.24),
               polar(a, R_FRAME, Z_FRAME),
               polar(a + FOOT_A, 3.60, 0.24),
               polar(a + FOOT_A, 3.84, 0.24),
               polar(a + 46, R_FRAME, Z_FRAME)]
        D.tube(bm, pts, [0.14] * len(pts), segs=5)
    D.new_obj("Frame", bm, c, steel, rbx_material="Metal", metallic=0.5, roughness=0.40)

    # ---- rubber foot pads: the only thing touching z = 0 --------------------
    bm = bmesh.new()
    for a in LEGS:
        for s in (-FOOT_A, FOOT_A):
            fx, fy, _ = polar(a + s, FOOT_R, 0.0)
            D.cyl(bm, (fx, fy, 0.0), (fx, fy, 0.26), 0.26, segs=6)
    D.new_obj("Feet", bm, c, black, rbx_material="Rubber", roughness=0.88)

    # ---- 16 springs bridging the open band, mat rim -> inside the frame tube -
    # They sit on the facet midpoints of the 16-seg ring, so each one spans the widest
    # part of the gap; the inner cap bites into the mat's rim skirt and the outer, fatter
    # end buries itself in the frame tube, so neither end floats.  Fat enough (0.11-0.14)
    # to hold a couple of pixels at 40 studs.
    bm = bmesh.new()
    for i in range(16):
        a = 11.25 + i * 22.5
        D.cyl(bm, polar(a, 2.90, 1.21), polar(a, 3.40, 1.27), 0.11, r2=0.14, segs=5)
    D.new_obj("Springs", bm, c, bright, rbx_material="Metal", metallic=0.75, roughness=0.28)

    # ---- padded rim cover: a narrow closed lathe collar over the frame ------
    # profile is a closed (radius, z) loop: inner lip, up the inner wall, over the top,
    # down the outside, then back along the underside.  It swallows only the TOP half of
    # the frame tube - the underside sits at z 1.28-1.38, above the springs and above the
    # frame's lower half, so both stay in view.
    bm = bmesh.new()
    D.lathe(bm, [(R_PAD_IN, 1.38), (3.36, 1.54), (3.42, 1.62), (3.90, 1.55),
                 (4.00, 1.36), (3.60, 1.28), (R_PAD_IN, 1.38)], segs=SEG, cap=False)
    D.new_obj("Pad", bm, c, padcol, rbx_material="Fabric", roughness=0.72)

    # ---- the jump mat: a stepped dish, rim 2.95 @ 1.20 -> centre 0.68 -------
    # The slope of each band is what shades it, so the four rings step 2 / 10 / 18 / 31
    # degrees on the way out: under flat shading that is four distinct concentric values
    # instead of one grey lid, and the 0.52-stud drop reads as a sprung membrane.
    bm = bmesh.new()
    D.lathe(bm, [(0.00, Z_MAT_C), (1.30, 0.72), (2.10, 0.86), (2.70, 1.05), (R_MAT, 1.20),
                 (2.90, 1.09), (2.62, 0.94), (2.05, 0.77), (1.28, 0.635), (0.00, 0.595)],
            segs=SEG)
    D.new_obj("MatSurface", bm, c, black, rbx_material="Rubber", roughness=0.85)

    # ---- asymmetric detail: a safety label stitched to the pad, front-RIGHT -
    # 120 deg is 30 deg round from +Y toward -x, i.e. the right of the render.  The patch
    # is sized to sit inside the narrower pad top (r 3.42 -> 3.90) with a margin.
    LAB_A = 120.0
    lab_at = polar(LAB_A, 3.66, 1.52)
    lab_m = D.place(lab_at, D.rot_euler(rx=-10, rz=LAB_A - 90.0))

    bm = bmesh.new()
    D.prism(bm, D.rounded_rect_pts(1.20, 0.40, 0.11, segs=2), 0.0, 0.07, matrix=lab_m)
    D.new_obj("LabelPatch", bm, c, D.C("plastic_white"), rbx_material="Fabric", roughness=0.62)

    bm = bmesh.new()
    D.box(bm, (-0.44, 0.02, 0.05), (0.44, 0.12, 0.10))       # header rule
    D.box(bm, (-0.14, -0.13, 0.05), (0.44, -0.04, 0.10))     # short second line, left-set
    D.xform(bm, list(bm.verts), lab_m)
    D.new_obj("LabelMarks", bm, c, D.C("danger_red"), rbx_material="Fabric", roughness=0.62)

    return c
