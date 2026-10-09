"""Farm: Crate Cucumber - a slatted wooden crate bedded with straw, four cucumbers in it."""
import bmesh, math

COLLECTION = "FarmCrateCucumber"
NOTES = ("A slatted farm crate holding four cucumbers.  The crate walls are 2.9 x 2.4 and "
         "the rim tops out at 1.76: three horizontal farm_crate slats a side, four "
         "farm_crate_d corner posts 0.28 square straddling the corners, a rim lip that "
         "overhangs them by 0.08 all round, and a dark farm_bark_dk deck on two skids.  "
         "Inside, a farm_hay straw bed is mounded up to z 1.10 with five wisps poking over "
         "the rim, and four CUKE_PROFILE_STUB cucumbers (h 2.1, r 0.44, small stem nubs) "
         "are bedded into that mound leaning 9-24 degrees in four different directions, "
         "their heads 1.3-1.6 studs clear of the rim.  Their cuke_stud speckles are placed "
         "by hand on whichever facets end up facing the viewer once each cucumber has been "
         "spun.  Footprint ~3.34 x 2.84, height ~3.35, centred on x=0 y=0, nothing below "
         "z = 0.  Six parts: Slats, Frame, Floor, Straw, Cukes, CukeStuds.")

# ---------------------------------------------------------------- the crate
HW, HD = 1.45, 1.20          # half width / half depth of the slat walls (2.9 x 2.4)
ST = 0.14                    # slat thickness, straddling the wall plane
SLAT_Z0, SLAT_Z1 = 0.18, 1.56
PW = 0.28                    # corner post, square
POST_Z1 = 1.60               # posts run up into the rim
RIM_Z0, RIM_Z1 = 1.56, 1.76  # the overhanging rim lip
RIM_W = 0.30                 # how wide (across) the rim bars are
RIM_OUT = 0.08               # how far the lip overhangs the posts

DECK_Z0, DECK_Z1 = 0.16, 0.32
SKID_Z1 = 0.16
SKID_Y = (-0.92, -0.62, 0.62, 0.92)     # two skids: |y| bands

# ---------------------------------------------------------------- the straw
BED = (-1.30, -1.05, 0.30, 1.30, 1.05, 0.92)        # the flat bed on the deck
MOUND = (-1.00, -0.85, 0.60, 0.92, 0.80, 1.10)      # the heap the cucumbers sit in
WISP_L, WISP_W, WISP_Z = 1.20, 0.10, 1.44           # length, square section, centre z
# (x, y, tilt about X, tilt about Y) - straw sticking up over the rim
WISPS = [
    (1.00, 0.35, -16.0, 22.0),
    (-1.02, 0.28, -14.0, -20.0),
    (0.30, -0.88, 24.0, 6.0),
    (-0.86, -0.70, 18.0, -18.0),
    (0.70, 0.84, -20.0, 14.0),
]

# ---------------------------------------------------------------- the fruit
CH, CR = 2.1, 0.44           # the crate cucumbers are stubby: h 2.1, r 0.44
# (x, y, base z, lean degrees, spin degrees) - base z is inside the straw mound
CUKES = [
    (0.62, -0.30, 0.98, 20.0, 34.0),     # forward and screen-LEFT (+x)
    (-0.58, -0.18, 1.02, 17.0, -42.0),   # forward and screen-right (-x)
    (0.10, 0.46, 1.08, 9.0, 168.0),      # the tall one, leaning back
    (-0.22, -0.52, 0.94, 24.0, -120.0),  # the lazy one, right and back
]
STUD_TARGETS = (52.0, 92.0, 132.0)       # world angles we want speckles to face
STUD_ZF = (0.32, 0.54, 0.76, 0.90)       # heights of the four speckles per cucumber


def _front_facets(spin, segs=8):
    """The body facets that end up pointing at STUD_TARGETS once the cucumber has been
    spun by `spin` degrees about Z.  Facet f faces (f + 1) * 45 degrees locally, and
    +Y (90 degrees) is the camera."""
    step = 360.0 / float(segs)
    return [int(round((t - spin) / step) - 1) % segs for t in STUD_TARGETS]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- slatted walls: three horizontal slats a side ----------------------
    bm = bmesh.new()
    for sy in (-1.0, 1.0):                                   # front and back
        y = sy * HD
        D.slat_run(bm, (-HW, y - ST / 2, SLAT_Z0), (HW, y + ST / 2, SLAT_Z1),
                   3, gap_frac=0.34, axis='z', bevel=0.035)
    for sx in (1.0, -1.0):                                   # the two sides
        x = sx * HW
        D.slat_run(bm, (x - ST / 2, -HD, SLAT_Z0), (x + ST / 2, HD, SLAT_Z1),
                   3, gap_frac=0.34, axis='z', bevel=0.035)
    D.new_obj("Slats", bm, c, D.C("farm_crate"), rbx_material="WoodPlanks")

    # ---- corner posts + the rim lip ----------------------------------------
    bm = bmesh.new()
    h = PW / 2.0
    for sx in (1.0, -1.0):
        for sy in (1.0, -1.0):
            px, py = sx * HW, sy * HD
            D.beveled_box(bm, (px - h, py - h, 0.0), (px + h, py + h, POST_Z1), bevel=0.05)
    rx = HW + h + RIM_OUT                                    # outer x of the lip
    ry = HD + h + RIM_OUT                                    # outer y of the lip
    for sy in (-1.0, 1.0):                                   # front / back rim bars
        y1 = sy * ry
        y0 = y1 - sy * RIM_W
        D.beveled_box(bm, (-rx, min(y0, y1), RIM_Z0), (rx, max(y0, y1), RIM_Z1), bevel=0.05)
    for sx in (1.0, -1.0):                                   # side rim bars, between them
        x1 = sx * rx
        x0 = x1 - sx * RIM_W
        D.beveled_box(bm, (min(x0, x1), -(ry - RIM_W), RIM_Z0),
                      (max(x0, x1), ry - RIM_W, RIM_Z1), bevel=0.05)
    D.new_obj("Frame", bm, c, D.C("farm_crate_d"), rbx_material="Wood")

    # ---- deck and skids ----------------------------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, (-HW, -HD, DECK_Z0), (HW, HD, DECK_Z1), bevel=0.05)
    for i in (0, 2):
        D.beveled_box(bm, (-HW + 0.05, SKID_Y[i], 0.0), (HW - 0.05, SKID_Y[i + 1], SKID_Z1),
                      bevel=0.04)
    D.new_obj("Floor", bm, c, D.C("farm_bark_dk"), rbx_material="Wood")

    # ---- straw bed, mound and wisps ---------------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, BED[:3], BED[3:], bevel=0.16)
    D.beveled_box(bm, MOUND[:3], MOUND[3:], bevel=0.20)
    hw, hl = WISP_W / 2.0, WISP_L / 2.0
    for (wx, wy, trx, try_) in WISPS:
        D.beveled_box(bm, (wx - hw, wy - hw, WISP_Z - hl), (wx + hw, wy + hw, WISP_Z + hl),
                      bevel=0.02, rot=D.rot_euler(trx, try_, 0.0))
    D.new_obj("Straw", bm, c, D.C("farm_hay"), rbx_material="Sand")

    # ---- the four cucumbers -----------------------------------------------
    bm = bmesh.new()
    bm2 = bmesh.new()
    for i, (x, y, z, lean, spin) in enumerate(CUKES):
        m = D.place((x, y, z), D.rot_euler(lean, 0.0, spin))
        D.cuke_body(bm, h=CH, r=CR, profile=D.CUKE_PROFILE_STUB, nub=(0.18, 0.18), matrix=m)
        f = _front_facets(spin)
        slots = [(STUD_ZF[0], f[0]), (STUD_ZF[1], f[1]),
                 (STUD_ZF[2], f[2]), (STUD_ZF[3], f[1])]
        D.cuke_studs(bm2, h=CH, r=CR, profile=D.CUKE_PROFILE_STUB, slots=slots,
                     size=0.21, rise=0.045, bevel=0.025, seed=40 + i, matrix=m)
    D.new_obj("Cukes", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")
    D.new_obj("CukeStuds", bm2, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
