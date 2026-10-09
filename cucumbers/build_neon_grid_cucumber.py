"""Neon: the Grid Cucumber - a dark see-through cucumber drawn in glowing wireframe."""
import bmesh, math

COLLECTION = "NeonGridCucumber"
NOTES = (
    "A see-through cucumber drawn in glowing WIREFRAME.  The body is the set's standard "
    "8-sided pillar (h 4.0, r 0.68, no nub) in dark neo_night Glass at transparency 0.35, "
    "lifted 0.06 so it rests on a small lime tip; nothing else carries its weight.  Over "
    "it runs a grid of Neon strips (emit 0.6): EIGHT lengthwise lines, one down the "
    "CENTRE of every facet (angles 0, 45 .. 315; facet 1 = +Y, the front, so the index "
    "card shows a line straight down the middle and one on each silhouette edge, the way "
    "the tile reads), zf 0.03 -> 0.97, 0.07 wide, 0.03 proud, with frames on every "
    "profile knot so they follow both chamfers; and SIX rings round the body at zf 0.16, "
    "0.30, 0.44, 0.58, 0.72, 0.86, 0.07 tall, drawn vertex-to-vertex round the octagon so "
    "every ring segment lies flat on its facet, 0.05 proud at the ridges (0.046 over the "
    "facets) so each ring sits clearly OVER the lengthwise lines where they cross.  "
    "Colours follow the tile: its outline, top ring and bottom ring glow cyan and only the "
    "middle rings are purple - so the 8 lengthwise lines plus the top (zf 0.86) and bottom "
    "(zf 0.16) rings are neo_cyan (part GridCyan) and the four middle rings are neo_purple "
    "(part GridPurple).  A neo_lime Neon stem 0.30 x 0.30 x 0.40 stands on the flat top "
    "(z 4.03 - 4.46, sunk 0.03) and a lime tip 0.20 x 0.20 x 0.10 sits under the bottom "
    "centre (z 0 - 0.10, 0.04 of it inside the body): one part, Lime.  Rotationally "
    "symmetric, centred on x = 0, y = 0, lowest point exactly z = 0 (the tip).  Footprint "
    "~1.35 x 1.35 (1.46 across the ring corners), height 4.46.  4 parts: Body, GridCyan, "
    "GridPurple, Lime; ~1120 tris.  Deviations from the REV3 brief, all to match the tile "
    "or to fix geometry the dry run cannot see: (1) lengthwise lines on facet CENTRES, not "
    "facet edges - the tile shows three inner lines between two outline lines, which is "
    "the facet-centre layout seen from the front; (2) the brief's ring points (0..360 "
    "step 45 at the facet plane) are facet centres, whose straight chords would sink ~0.10 "
    "under every ridge and leave each ring dashed, so the rings run through the eight "
    "ridge vertices at the true (circumscribed) radius instead, and rise 0.05 rather than "
    "0.035 so they do not z-fight the 0.03-proud lines at the crossings; (3) the top and "
    "bottom rings are cyan and the parts are named GridCyan / GridPurple rather than "
    "GridLong / GridRings; (4) no raised speckles - the tile has none, the grid is this "
    "model's pattern.  The strips are laid in the body's own frame and lifted with it by "
    "D.translate, so dryrun's bounding box sits 0.06 low for them."
)

LIFT = 0.06                     # the body rests on the lime tip, 0.06 off the ground

# lengthwise lines: one per facet CENTRE.  With the lib's cuke phase the facet centres
# sit at exact multiples of 45 degrees (facet 7 = +X = 0, facet 1 = +Y = 90).
LONG_ANGLES = [45.0 * k for k in range(8)]
# height fractions: the two ends plus every CUKE_PROFILE knot in between, so each strip
# bends with the chamfers instead of cutting a straight chord through them (the 0.032
# knot sits only 0.002 above the start, so the first frame stands in for it)
LONG_ZF = [0.03, 0.082, 0.25, 0.66, 0.858, 0.922, 0.964, 0.97]
LONG_W, LONG_RISE = 0.07, 0.03

# rings: closed loops through the eight lathe VERTICES (the ridges, 22.5 + 45k) at the
# circumscribed radius, so the straight run between two of them lies ON the facet
RING_ZF = [0.16, 0.30, 0.44, 0.58, 0.72, 0.86]
RING_CYAN = (0.16, 0.86)        # the tile's end rings glow cyan like its outline
RING_ANGLES = [22.5 + 45.0 * k for k in range(9)]       # 9 points: the loop closes
RING_W, RING_RISE = 0.07, 0.05

NUB_W, NUB_H, NUB_SINK = 0.30, 0.40, 0.03      # lime stem on the flat top
TIP_W, TIP_H = 0.20, 0.10                      # lime tip under the bottom centre


def _long_lines(D, bm, H, R):
    vs = []
    for ang in LONG_ANGLES:
        vs += D.surface_line(bm, [(zf, ang) for zf in LONG_ZF], h=H, r=R,
                             width=LONG_W, rise=LONG_RISE, flat=True)
    return vs


def _ring(D, bm, H, R, zf):
    return D.surface_line(bm, [(zf, ang) for ang in RING_ANGLES], h=H, r=R,
                          width=RING_W, rise=RING_RISE, flat=False)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- the dark glass body, no nub, lifted onto the tip -----------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=None, matrix=D.place((0.0, 0.0, LIFT)))
    D.new_obj("Body", bm, c, D.C("neo_night"), rbx_material="Glass", transparency=0.35)

    # ---- cyan: the eight lengthwise lines + the top and bottom rings -------
    bm = bmesh.new()
    vs = _long_lines(D, bm, H, R)
    for zf in RING_ZF:
        if zf in RING_CYAN:
            vs += _ring(D, bm, H, R, zf)
    D.translate(bm, vs, (0.0, 0.0, LIFT))
    D.new_obj("GridCyan", bm, c, D.C("neo_cyan"), rbx_material="Neon", emit=0.6)

    # ---- purple: the four middle rings -------------------------------------
    bm = bmesh.new()
    vs = []
    for zf in RING_ZF:
        if zf not in RING_CYAN:
            vs += _ring(D, bm, H, R, zf)
    D.translate(bm, vs, (0.0, 0.0, LIFT))
    D.new_obj("GridPurple", bm, c, D.C("neo_purple"), rbx_material="Neon", emit=0.6)

    # ---- lime: the stem on top and the little tip underneath ---------------
    top = H * D.CUKE_PROFILE[-1][1] + LIFT
    bm = bmesh.new()
    D.beveled_box(bm, (-NUB_W / 2.0, -NUB_W / 2.0, top - NUB_SINK),
                  (NUB_W / 2.0, NUB_W / 2.0, top + NUB_H), bevel=0.045)
    D.beveled_box(bm, (-TIP_W / 2.0, -TIP_W / 2.0, 0.0),
                  (TIP_W / 2.0, TIP_W / 2.0, TIP_H), bevel=0.03)
    D.new_obj("Lime", bm, c, D.C("neo_lime"), rbx_material="Neon", emit=0.6)

    return c
