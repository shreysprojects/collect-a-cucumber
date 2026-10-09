"""Narmek: Astronaut Cucumber - a cucumber zipped into a white spacesuit."""
import bmesh, math

COLLECTION = "NarmekAstronautCucumber"
NOTES = ("A standard 4.0-stud cucumber body in white suit plastic wearing a spacesuit: a "
         "big dark wrap-around visor across the three front facets at zf 0.74 (three "
         "faceted panes that meet exactly on the body's octagon edges, so it reads as one "
         "curved bubble visor) with a pale glint bar over its top LEFT (+x), a metal neck "
         "ring at z 2.36-2.60 splitting helmet from suit, a metal chest control box on the "
         "front at z 1.47-1.81 carrying one orange button and two neon-green square "
         "lights, two orange octagonal stripe bands at zf 0.30 and 0.52 that line up with "
         "the body's own facets, and a short metal antenna leaning off the stem nub with "
         "an orange ball on its tip.  Footprint ~1.44 x 1.55, 5.01 tall, centred on "
         "x = y = 0, facing +Y, nothing below z = 0.  Speckles are placed by hand (8 of "
         "them, sparse) so none is ever buried under the visor, the bands or the collar.  "
         "Seven parts: Body, Studs, Visor, VisorGlint, Gear, Stripes, Lights.")

H, R = 4.0, 0.68
SEGS = 8

VISOR_ZF = 0.74          # height fraction the visor is built around
VISOR_HH = 0.31          # half height (0.62 tall)
VISOR_SINK = -0.06       # back face, inward from the facet plane
VISOR_OUT = 0.10         # front face, proud of the facet plane

BAND_R = 0.74            # circumscribed radius of the orange stripe octagons
COLLAR_R = 0.78          # ... and of the metal neck ring

# (height fraction, facet index) for every speckle - kept clear of visor/bands/collar
STUD_SLOTS = [
    (0.10, 7), (0.15, 0), (0.21, 2), (0.25, 3),
    (0.42, 0), (0.44, 2), (0.72, 3), (0.87, 7),
]


def _pane_pts(w, hh, rr, flip=False):
    """A visor side pane: SQUARE inner edge at local +x (so it butts flush against the
    centre pane on the octagon edge), rounded outer edge at local -x."""
    pts = [(w, -hh), (w, hh)]
    pts += _arc((-w + rr, hh - rr), rr, 90.0, 180.0, 4)
    pts += _arc((-w + rr, -hh + rr), rr, 180.0, 270.0, 4)
    return [(-x, y) for (x, y) in pts] if flip else pts


def _arc(center, radius, a0, a1, n):
    cx, cy = center
    a0, a1 = math.radians(a0), math.radians(a1)
    return [(cx + math.cos(a0 + (a1 - a0) * i / (n - 1.0)) * radius,
             cy + math.sin(a0 + (a1 - a0) * i / (n - 1.0)) * radius) for i in range(n)]


def _pane_matrix(D, angle_deg, along, zc, rad):
    """4x4 laying a flat panel ON the body facet whose outward angle is `angle_deg`.

    Local +z becomes the outward normal, local +y becomes world +z (upright) and local
    +x runs anticlockwise along the facet.  `along` slides the panel sideways on its
    facet, `rad` is the facet plane's distance from the axis."""
    a = math.radians(angle_deg)
    fx, fy = math.cos(a), math.sin(a)
    tx, ty = -math.sin(a), math.cos(a)
    loc = (rad * fx + along * tx, rad * fy + along * ty, zc)
    return D.place(loc, D.rot_euler(90.0, 0.0, angle_deg + 90.0))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    phase = D.cuke_phase(SEGS)
    cos8 = math.cos(math.pi / SEGS)
    sin8 = math.sin(math.pi / SEGS)

    # body geometry the suit details hang off
    zc = VISOR_ZF * H                                   # 2.96
    r_circ = R * D.cuke_radius(VISOR_ZF)                # circumscribed radius there
    r_flat = r_circ * cos8                              # facet plane distance
    half_facet = r_circ * sin8                          # half width of one facet

    # ---- the suit ----------------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("nar_suit"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, size=0.22, rise=0.05, slots=STUD_SLOTS)
    D.new_obj("Studs", bm, c, D.C("nar_suit_sh"), rbx_material="SmoothPlastic")

    # ---- the visor ---------------------------------------------------------
    # centre pane spans the whole front facet; the two side panes start exactly on the
    # octagon edges and run halfway over facets 0 and 2, so the three read as one curve.
    side_w = 0.135
    side_along = half_facet - side_w
    bm = bmesh.new()
    D.prism(bm, [(-half_facet, -VISOR_HH), (half_facet, -VISOR_HH),
                 (half_facet, VISOR_HH), (-half_facet, VISOR_HH)],
            VISOR_SINK, VISOR_OUT, matrix=_pane_matrix(D, 90.0, 0.0, zc, r_flat))
    D.prism(bm, _pane_pts(side_w, VISOR_HH, 0.13), VISOR_SINK, VISOR_OUT,
            matrix=_pane_matrix(D, 45.0, side_along, zc, r_flat))
    D.prism(bm, _pane_pts(side_w, VISOR_HH, 0.13, flip=True), VISOR_SINK, VISOR_OUT,
            matrix=_pane_matrix(D, 135.0, -side_along, zc, r_flat))
    D.new_obj("Visor", bm, c, D.C("nar_visor"), rbx_material="SmoothPlastic")

    # the glint, across the visor's TOP LEFT - screen left is +x, so on facet 1 it has to
    # sit at NEGATIVE local x (local +x runs anticlockwise, i.e. toward -x world there).
    bm = bmesh.new()
    D.prism(bm, D.rounded_rect_pts(0.27, 0.075, 0.03, segs=2, center=(-0.10, 0.195)),
            VISOR_OUT - 0.005, VISOR_OUT + 0.033,
            matrix=_pane_matrix(D, 90.0, 0.0, zc, r_flat))
    D.prism(bm, D.rounded_rect_pts(0.17, 0.075, 0.03, segs=2, center=(0.0, 0.185)),
            VISOR_OUT - 0.005, VISOR_OUT + 0.033,
            matrix=_pane_matrix(D, 45.0, side_along, zc, r_flat))
    D.new_obj("VisorGlint", bm, c, D.C("nar_visor_lt"), rbx_material="SmoothPlastic")

    # ---- metal gear: neck ring, chest box, antenna mast --------------------
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(SEGS, COLLAR_R, phase=phase), 2.36, 2.60)
    D.beveled_box(bm, (-0.275, 0.55, 1.47), (0.275, 0.79, 1.81), bevel=0.05)
    D.cyl(bm, (0.08, 0.0, 4.10), (0.26, 0.02, 4.80), 0.06, segs=8)
    D.new_obj("Gear", bm, c, D.C("nar_metal"), rbx_material="Metal")

    # ---- orange: stripe bands, chest button, antenna ball ------------------
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(SEGS, BAND_R, phase=phase), 0.30 * H - 0.11, 0.30 * H + 0.11)
    D.prism(bm, D.ngon_pts(SEGS, BAND_R, phase=phase), 0.52 * H - 0.11, 0.52 * H + 0.11)
    D.cyl(bm, (0.12, 0.77, 1.645), (0.12, 0.87, 1.645), 0.085, segs=8)
    D.uvsphere(bm, (0.28, 0.02, 4.88), 0.13, segs=8, rings=6)
    D.new_obj("Stripes", bm, c, D.C("nar_orange"), rbx_material="SmoothPlastic")

    # ---- two tiny neon status squares on the chest box ---------------------
    bm = bmesh.new()
    for x in (-0.10, -0.20):
        D.stud_patch(bm, (x, 0.79, 1.645), (0.0, 1.0, 0.0), size=0.085, rise=0.03,
                     sink=0.06, bevel=0.018)
    D.new_obj("Lights", bm, c, D.C("nar_glow_grn"), rbx_material="Neon", emit=0.65)

    return c
