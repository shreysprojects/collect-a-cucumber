"""Samurai: Bamboo Cucumber - a cucumber culm ringed by three tan bamboo nodes."""
import bmesh, math

COLLECTION = "SamuraiBambooCucumber"
NOTES = ("A bamboo-culm cucumber: the standard 4.0-stud body in the brighter sam_stalk "
         "green, its skin carrying a fine REGULAR grid of 32 small cuke_stud speckles - "
         "eight rows of four, no stagger, running as unbroken vertical columns up the "
         "internodes.  Three tan sam_bamboo node bands ring it at height fractions 0.22, "
         "0.50 and 0.78: each an eight-sided lathe collar 0.26 tall, chamfered top and "
         "bottom, phase-aligned with the body's facets and standing exactly 0.05 proud of "
         "them.  The speckle rows are laid out in the four internodes (1 / 3 / 3 / 1) so "
         "no speckle is buried under a band.  Four small sam_leaf blades (0.66-0.72 long, "
         "0.34 wide) sprout from the top edges of the middle and upper bands, two to each "
         "side, pitched 26-38 degrees up and out and rolled a little out of plane so the "
         "facets catch light; the upper pair reaches almost straight out along +/-X for "
         "the silhouette, the lower pair swings one forward and one back so the spray has "
         "depth.  Faces +Y, centred on x=0 y=0, footprint about 2.4 x 1.7 studs and 4.34 "
         "tall to the top of the stem nub, nothing below z = 0.  Four parts: Body, Studs, "
         "Bands, Leaves.")

# ---- the body ----------------------------------------------------------------
NUB = (0.30, 0.34)                      # stem nub: width, height -> 4.34 overall

# ---- the three node bands ----------------------------------------------------
BAND_ZF = (0.22, 0.50, 0.78)            # height fractions of the band CENTRES
BAND_H = 0.26                           # band height
BAND_PROUD = 0.05                       # how far it stands off the body's facet planes
BAND_CH = 0.07                          # chamfer at the band's top and bottom edge

# ---- the speckle grid --------------------------------------------------------
# Eight rows of four, ungeared and unjittered - but parked in the four INTERNODES
# (1 below the first band, 3 / 3 between them, 1 above the last) so none is swallowed.
STUD_ROWS = (0.14,
             0.29, 0.36, 0.43,
             0.57, 0.64, 0.71,
             0.86)
STUD_FACETS = (0, 2, 4, 6)              # four evenly spaced columns, no stagger
STUD_SIZE, STUD_RISE, STUD_BEVEL = 0.20, 0.045, 0.025

# ---- the leaves --------------------------------------------------------------
# (band height fraction, yaw about Z, pitch up from horizontal, roll, length, width)
LEAVES = (
    (0.78,   8.0, 38.0,  16.0, 0.72, 0.34),   # upper band, out to +X (screen LEFT)
    (0.78, 172.0, 34.0, -16.0, 0.68, 0.34),   # upper band, out to -X
    (0.50,  44.0, 30.0, -20.0, 0.70, 0.34),   # middle band, forward-left
    (0.50, 222.0, 26.0,  20.0, 0.66, 0.32),   # middle band, back-right
)
LEAF_T, LEAF_RIDGE = 0.07, 0.05
LEAF_LIFT = 0.06                        # base sits this far above the band centre
LEAF_SINK = 0.02                        # ... and only just proud of the body, so the
                                        #     blade's pointed root hides inside the band


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R, SEGS = D.CUKE_H, D.CUKE_R, D.CUKE_SEGS
    phase = D.cuke_phase(SEGS)
    flat = math.cos(math.pi / SEGS)     # circumscribed radius -> facet-plane distance

    # ---- the culm ----------------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=NUB)
    D.new_obj("Body", bm, c, D.C("sam_stalk"), rbx_material="SmoothPlastic")

    # ---- the fine speckle grid --------------------------------------------
    bm = bmesh.new()
    slots = [(zf, f) for zf in STUD_ROWS for f in STUD_FACETS]
    D.cuke_studs(bm, h=H, r=R, size=STUD_SIZE, rise=STUD_RISE, bevel=STUD_BEVEL,
                 slots=slots)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- three tan node bands ---------------------------------------------
    bm = bmesh.new()
    for zf in BAND_ZF:
        z0, z1 = zf * H - BAND_H / 2.0, zf * H + BAND_H / 2.0
        rr = max(D.cuke_radius(z0 / H), D.cuke_radius(zf), D.cuke_radius(z1 / H)) * R
        rb = rr + BAND_PROUD / flat     # -> exactly BAND_PROUD off every facet plane
        D.lathe(bm, [(rb - BAND_CH, z0), (rb, z0 + BAND_CH),
                     (rb, z1 - BAND_CH), (rb - BAND_CH, z1)],
                segs=SEGS, phase=phase, cap=True)
    D.new_obj("Bands", bm, c, D.C("sam_bamboo"), rbx_material="Wood")

    # ---- four leaf blades off the top edge of two of the bands -------------
    bm = bmesh.new()
    for zf, yaw, pitch, roll, length, width in LEAVES:
        zb = zf * H + LEAF_LIFT
        rad = D.cuke_radius(zb / H) * R * flat + LEAF_SINK
        a = math.radians(yaw)
        base = (math.cos(a) * rad, math.sin(a) * rad, zb)
        # local +Y (the blade's tip) -> +X -> rolled about its own axis -> pitched up
        # -> swung round to `yaw`; the blade face ends up square to the outward swing.
        m = (D.place(base, D.rot_euler(0, 0, yaw))
             @ D.rot_euler(0, -pitch, 0)
             @ D.rot_euler(roll - 90.0, 0, 0)
             @ D.rot_euler(0, 0, -90.0))
        D.leaf_blade(bm, length=length, width=width, thick=LEAF_T, matrix=m,
                     ridge=LEAF_RIDGE)
    D.new_obj("Leaves", bm, c, D.C("sam_leaf"), rbx_material="LeafyGrass")

    return c
