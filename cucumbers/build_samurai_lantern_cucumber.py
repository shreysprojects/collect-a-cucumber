"""Samurai: Lantern Cucumber - a cucumber wearing a glowing paper lantern for a head."""
import bmesh, math

COLLECTION = "SamuraiLanternCucumber"
NOTES = (
    "A standard cucumber pillar (4.0 tall, 1.36 across, cuke_green with twenty cuke_stud "
    "speckles) carrying a JAPANESE LANTERN on its head.  The stem nub pokes up into a "
    "sam_gold_dk frame band at z 4.14-4.30, which carries a tan sam_bamboo box 0.95 x "
    "0.95 x 0.88 (z 4.22-5.10).  Warm sam_warm Neon panels (emit 1.0) glow out of the "
    "front (+Y) and both side faces, standing 0.03 proud of the tan box; four slim gold "
    "corner posts and a second gold band at the top finish the frame.  Over it sits a "
    "dark sam_roof tiled roof: an eave slab 1.76 across at z 5.16-5.27, a square pyramid "
    "1.50 across rising 0.33 to an apex at z 5.58, four sam_roof_lt hip ridges running "
    "corner-to-apex, and a small gold finial cube topping out at z 5.60.  Down the body's "
    "FRONT facet hangs a cream sam_paper tag (0.52 x 0.66, 0.07 thick, z 1.52-2.18, "
    "zf 0.46) carrying a sam_ink kanji SAMURAI (侍) standing proud of it; the one speckle "
    "that would have sat behind the tag is removed from the scatter.  About 1.8 x 1.8 x "
    "5.6 studs, centred on x = 0, y = 0, nothing below z = 0.  The speckles and the roof "
    "hips are placed with surface maths and rotations, so dryrun's bounding box is an "
    "approximation."
)

# ------------------------------------------------------------------ the lantern
BOX_HW = 0.475                      # tan body of the lantern: 0.95 across
BOX_Z0, BOX_Z1 = 4.22, 5.10

BAND_HW, BAND_T = 0.515, 0.16       # the two gold frame bands
BAND_LO_Z = 4.14                    # the lower one swallows the body's stem nub
BAND_HI_Z = 5.02

POST_HW = 0.06                      # gold corner posts of the frame
POST_Z0, POST_Z1 = 4.24, 5.08

# the three glowing paper panels: (lo, hi).  Front (+Y) then screen-left (+X), right (-X).
WINDOWS = [
    ((-0.31, 0.440, 4.37), (0.31, 0.505, 4.95)),
    ((0.440, -0.31, 4.37), (0.505, 0.31, 4.95)),
    ((-0.505, -0.31, 4.37), (-0.440, 0.31, 4.95)),
]

EAVE_HW, EAVE_Z0, EAVE_Z1 = 0.88, 5.16, 5.27        # the overhanging eave slab
ROOF_HW, ROOF_Z, ROOF_RISE = 0.75, 5.25, 0.33       # the pyramid: 1.50 across, apex 5.58
RIDGE_W, RIDGE_T = 0.11, 0.075                      # the hip ridge caps
FINIAL_HW, FINIAL_Z0, FINIAL_Z1 = 0.085, 5.44, 5.60

CORNERS = [(1, 1), (1, -1), (-1, -1), (-1, 1)]

# ------------------------------------------------------------------ the tag
TAG_HW = 0.26                       # 0.52 wide - exactly the width of the front facet
TAG_Z0, TAG_Z1 = 1.52, 2.18         # 0.66 tall, centred on zf 0.4625
TAG_Y0, TAG_Y1 = 0.625, 0.700       # 0.075 thick, biting into the skin at y = 0.628
KANJI_ORIGIN, KANJI_SIZE = (0.0, 0.72, 1.85), 0.42


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- the cucumber -----------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # standard speckles, minus the one that would sit behind the paper tag
    slots = [(zf, facet) for (zf, facet)
             in D.cuke_stud_slots(rows=7, per_row=3, z0=0.11, z1=0.90, seed=7)
             if not (facet == 1 and 0.30 <= zf <= 0.62)]
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, size=0.28, rise=0.055, slots=slots)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the paper tag on the front facet ---------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, (-TAG_HW, TAG_Y0, TAG_Z0), (TAG_HW, TAG_Y1, TAG_Z1), bevel=0.035)
    D.new_obj("Tag", bm, c, D.C("sam_paper"), rbx_material="Plaster", roughness=0.80)

    bm = bmesh.new()
    D.kanji_samurai(bm, origin=KANJI_ORIGIN, size=KANJI_SIZE, thick=0.05, face="+y")
    D.new_obj("Kanji", bm, c, D.C("sam_ink"), rbx_material="SmoothPlastic")

    # ---- the lantern's tan body -------------------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, (-BOX_HW, -BOX_HW, BOX_Z0), (BOX_HW, BOX_HW, BOX_Z1), bevel=0.06)
    D.new_obj("Lantern", bm, c, D.C("sam_bamboo"), rbx_material="Wood")

    # ---- the glowing paper panels -----------------------------------------
    bm = bmesh.new()
    for lo, hi in WINDOWS:
        D.beveled_box(bm, lo, hi, bevel=0.03)
    D.new_obj("Windows", bm, c, D.C("sam_warm"), rbx_material="Neon", emit=0.65)

    # ---- the gold frame: two bands, four corner posts, the finial ----------
    bm = bmesh.new()
    for z0 in (BAND_LO_Z, BAND_HI_Z):
        D.beveled_box(bm, (-BAND_HW, -BAND_HW, z0), (BAND_HW, BAND_HW, z0 + BAND_T),
                      bevel=0.045)
    for sx, sy in CORNERS:
        cx, cy = sx * BOX_HW, sy * BOX_HW
        D.beveled_box(bm, (cx - POST_HW, cy - POST_HW, POST_Z0),
                      (cx + POST_HW, cy + POST_HW, POST_Z1), bevel=0.022)
    D.beveled_box(bm, (-FINIAL_HW, -FINIAL_HW, FINIAL_Z0),
                  (FINIAL_HW, FINIAL_HW, FINIAL_Z1), bevel=0.03)
    D.new_obj("Frame", bm, c, D.C("sam_gold_dk"), rbx_material="Metal",
              metallic=0.0, roughness=0.38)

    # ---- the tiled roof ---------------------------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, (-EAVE_HW, -EAVE_HW, EAVE_Z0), (EAVE_HW, EAVE_HW, EAVE_Z1),
                  bevel=0.05)
    D.pyramid(bm, (0.0, 0.0, ROOF_Z), ROOF_HW * 2.0, ROOF_RISE)
    D.new_obj("Roof", bm, c, D.C("sam_roof"), rbx_material="Slate", roughness=0.72)

    # hip ridges: corner -> apex, each a slim cap laid along the roof's own diagonal
    span = math.hypot(ROOF_HW, ROOF_HW)
    hip = math.hypot(span, ROOF_RISE)
    pitch = math.degrees(math.atan2(ROOF_RISE, span))
    bm = bmesh.new()
    for sx, sy in CORNERS:
        mx, my = sx * ROOF_HW / 2.0, sy * ROOF_HW / 2.0
        mz = ROOF_Z + ROOF_RISE / 2.0
        yaw = math.degrees(math.atan2(-sy, -sx))
        D.box(bm, (mx - hip / 2.0, my - RIDGE_W / 2.0, mz - RIDGE_T / 2.0),
              (mx + hip / 2.0, my + RIDGE_W / 2.0, mz + RIDGE_T / 2.0),
              rot=D.rot_euler(0.0, -pitch, yaw))
    D.new_obj("RoofRidge", bm, c, D.C("sam_roof_lt"), rbx_material="Slate", roughness=0.72)

    return c
