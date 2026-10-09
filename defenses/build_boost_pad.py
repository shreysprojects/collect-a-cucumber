"""Boost pad: an 8 x 12 launch chute whose rails climb to a lit gate at the +Y exit."""
import bmesh, math
from mathutils import Matrix

COLLECTION = "BoostPad"
NOTES = (
    "Friendly / helpful read, never a hazard: no yellow-black stripes, no spikes, no red. "
    "Travel is +Y and the SILHOUETTE carries it: the two side rails start as knee-high "
    "kerbs at the -Y mouth and climb steadily to a pair of 2.94-stud lit gate posts at the "
    "+Y exit, so from every angle the prop is a wedge pointing +Y. Five cues agree: "
    "(1) the rail tops rise 0.62 -> 1.80 toward +Y with orange caps riding the rising line; "
    "(2) the cyan glow panel on each inner rail face is a taper - 0.10 tall at the mouth, "
    "0.85 tall at the exit; (3) three cyan chevrons grow 2.8 / 3.9 / 5.0 studs wide and get "
    "brighter (rbx_transparency 0.30 / 0.15 / 0.00 - Roblox only, Blender's preview does not "
    "wire transparency into the material, which is why the SIZE ramp was made big enough to "
    "carry the read on its own); (4) the -Y entrance is a full-lane orange on-ramp with a "
    "cyan chevron laid into its slope - the first thing an approaching player sees, and the "
    "only direction cue that is not foreshortened from that angle; (5) the two ends differ "
    "utterly in mass - 1.06-stud kerb bollards at the entry, 2.94-stud dark posts with a "
    "cyan lamp collar and an orange cap at the exit - so a player who walks up to the +Y end "
    "knows at a glance they are at the wrong end.\n"
    "Footprint is exactly x -4..+4, y -6..+6; the top of the prop is z = 2.94 (the exit post "
    "caps). Running surface (TreadDeck top) is z = 0.52. The middle 6.2 studs of width "
    "(|x| <= 3.10) are a clean flat run: the only things above 0.52 inside it are the three "
    "chevrons at 0.66 (0.14 proud). Everything structural lives at |x| >= 3.10; the only "
    "thing that ever reaches over the lane is the exit lamp collar / cap at |x| >= 3.01 and "
    "z >= 2.02 - a player runs under it.\n"
    "Nothing dips below z = 0 - min_z is exactly 0.0 (DeckSlab, EntryRamp, RailBodies, "
    "ExitPosts and EntryBollards all bottom out on the ground plane). Nothing floats: the "
    "chevrons and the ramp arrow are sunk into the surfaces they sit on, the rail caps are "
    "embedded 0.07 into the rail bodies, the glow panels 0.04 into the inner rail faces, the "
    "post caps 0.06 into the posts, the tread 0.04 into the chassis slab, and each rail runs "
    "0.10 into the bollard / post it springs from. Coincident faces are avoided throughout: "
    "the post and bollard BODIES stop "
    "at x 3.96 / y +-5.96 so the collars and caps that reach the 4.00 / 6.00 footprint edge "
    "never share a plane with them, and the chassis slab is inset to 3.98 for the same "
    "reason.\n"
    "Neon parts use roughness 0.85 so a specular sheen does not stack on top of the emission "
    "and blow the cyan out to white. defenselib has no 'Rubber' Enum.Material, so the tread "
    "deck uses 'Plastic' with the Rubber-black hex (2a2d33) at roughness 0.92. Fully "
    "deterministic - the build uses no randomness at all, so no seed is needed."
)

# ------------------------------------------------------------------ dimensions (studs)
HX        =  4.00   # half width - hard edge of the footprint
Y_BACK    = -6.00   # entrance edge (-Y, where the player runs on)
Y_FRONT   =  6.00   # exit edge (+Y)
RAMP_Y1   = -4.60   # crest of the on-ramp == start of the running surface
SLAB_X    =  3.98   # chassis inset 0.02 so it never shares a plane with the rails
SLAB_Y0   = -4.62   # chassis slab starts 0.02 under the ramp crest
SLAB_TOP  =  0.36
DECK_TOP  =  0.52   # THE running surface
LANE_HX   =  3.40   # tread / on-ramp half width
TREAD_Y1  =  5.90   # tread stops short so a mid-grey chassis lip shows at the exit
RAIL_IN   =  3.46   # rail body inner face
CAP_IN    =  3.38   # orange cap overhangs the rail 0.08 inward
GLOW_IN   =  3.36   # cyan panel protrudes 0.10 off the rail's inner face ...
GLOW_OUT  =  3.50   # ... and is embedded 0.04 into it
RAIL_Y0   = -5.00   # rail body springs from inside the entry bollard ...
RAIL_Y1   =  4.40   # ... and dies inside the exit post
RAIL_Z0   =  0.62   # rail top at the mouth
RAIL_Z1   =  1.80   # rail top at the gate - the rise IS the arrow
POST_IN   =  3.10   # posts / bollards reach this far in - outside the clean middle 6
POST_OUT  =  3.96
POST_Y0   =  4.30
POST_TOP  =  2.70
CAP_TOP   =  2.94   # highest point of the prop
BOLL_Y0   = -5.96
BOLL_Y1   = -4.90
BOLL_TOP  =  0.86
BOLL_CAP  =  1.06
CHEV_Z0   =  0.40   # chevrons are sunk 0.12 into the tread ...
CHEV_Z1   =  0.66   # ... and stand 0.14 proud of DECK_TOP

# ------------------------------------------------------------------ palette (STYLE.md)
MID    = "6c7789"   # Metal mid      - chassis slab
DARK   = "3b4350"   # Metal dark     - rail bodies, gate posts, entry bollards
ORANGE = "ff8a3d"   # Accent orange  - on-ramp, rail caps, post / bollard caps
RUBBER = "2a2d33"   # Rubber black   - tread deck
CYAN   = "4dd2ff"   # Energy cyan    - chevrons, rail glow, lamp collars (Neon)

# (y, z) profiles are extruded along X: prism() builds (p0, p1, t) and this permutation
# rewrites it as (t, p0, p1).  Same trick defenselib.wedge() uses internally.
YZ = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def _rail_top(y):
    """z of the rail body's top edge at station y - a straight climb toward +Y."""
    t = (y - RAIL_Y0) / (RAIL_Y1 - RAIL_Y0)
    return RAIL_Z0 + t * (RAIL_Z1 - RAIL_Z0)


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # --- 1. chassis slab: the mid-value frame the dark lane sits inside -------------
    bm = bmesh.new()
    D.beveled_box(bm, (-SLAB_X, SLAB_Y0, 0.0), (SLAB_X, Y_FRONT, SLAB_TOP), bevel=0.10)
    D.new_obj("DeckSlab", bm, c, MID, rbx_material="Metal", metallic=0.55, roughness=0.42)

    # --- 2. entrance on-ramp: full lane width, ground -> running surface ------------
    bm = bmesh.new()
    D.wedge(bm, (-LANE_HX, Y_BACK, 0.0), (LANE_HX, RAMP_Y1, DECK_TOP), rise='+Y')
    D.new_obj("EntryRamp", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.50)

    # --- 3. chevron laid INTO the ramp slope: the approach-angle direction cue ------
    run, rise = RAMP_Y1 - Y_BACK, DECK_TOP
    ang = math.degrees(math.atan2(rise, run))          # 20.4 deg
    s, k = math.sin(math.radians(ang)), math.cos(math.radians(ang))
    off = 0.04                                          # slide out along the face normal
    seat = Matrix.Translation((0.0, (Y_BACK + RAMP_Y1) / 2.0 - s * off,
                               rise / 2.0 + k * off))
    bm = bmesh.new()
    D.prism(bm, D.chevron_pts(3.20, 0.80, 0.44, tip_at=+1), -0.06, 0.06,
            matrix=seat @ D.rot_euler(rx=ang) @ Matrix.Translation((0.0, -0.18, 0.0)))
    D.new_obj("RampArrow", bm, c, CYAN, rbx_material="Neon", roughness=0.85)

    # --- 4. tread deck: the dark run the glow sits on -------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, (-LANE_HX, SLAB_Y0, SLAB_TOP - 0.04), (LANE_HX, TREAD_Y1, DECK_TOP),
                  bevel=0.05)
    D.new_obj("TreadDeck", bm, c, RUBBER, rbx_material="Plastic", roughness=0.92)

    # --- 5. side rails: a straight climb from the mouth to the gate -----------------
    bm = bmesh.new()
    prof = [(RAIL_Y0, 0.0), (RAIL_Y1, 0.0), (RAIL_Y1, RAIL_Z1), (RAIL_Y0, RAIL_Z0)]
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * RAIL_IN, sx * HX))
        D.prism(bm, prof, lo_x, hi_x, matrix=YZ)
    D.new_obj("RailBodies", bm, c, DARK, rbx_material="Metal", metallic=0.55, roughness=0.45)

    # --- 6. orange caps riding the rising rail line ---------------------------------
    bm = bmesh.new()
    prof = [(RAIL_Y0, RAIL_Z0 - 0.07), (RAIL_Y1, RAIL_Z1 - 0.07),
            (RAIL_Y1, RAIL_Z1 + 0.15), (RAIL_Y0, RAIL_Z0 + 0.15)]
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * CAP_IN, sx * HX))
        D.prism(bm, prof, lo_x, hi_x, matrix=YZ)
    D.new_obj("RailCaps", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.50)

    # --- 7. cyan glow panel: a taper that swells toward the exit --------------------
    gy0, gy1 = -4.20, RAIL_Y1
    t0, t1 = _rail_top(gy0) - 0.14, _rail_top(gy1) - 0.14     # clear of the cap underside
    bm = bmesh.new()
    prof = [(gy0, t0 - 0.10), (gy1, t1 - 0.85), (gy1, t1), (gy0, t0)]
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * GLOW_IN, sx * GLOW_OUT))
        D.prism(bm, prof, lo_x, hi_x, matrix=YZ)
    D.new_obj("RailGlow", bm, c, CYAN, rbx_material="Neon", roughness=0.85)

    # --- 8. exit gate posts: the tall end, and the whole reason the prop reads ------
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * POST_IN, sx * POST_OUT))
        D.beveled_box(bm, (lo_x, POST_Y0, 0.0), (hi_x, Y_FRONT - 0.04, POST_TOP), bevel=0.10)
    D.new_obj("ExitPosts", bm, c, DARK, rbx_material="Metal", metallic=0.55, roughness=0.45)

    # --- 9. cyan lamp collar around each gate post ---------------------------------
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * (POST_IN - 0.05), sx * HX))
        D.box(bm, (lo_x, POST_Y0 - 0.05, 2.02), (hi_x, Y_FRONT, 2.46))
    D.new_obj("PostLights", bm, c, CYAN, rbx_material="Neon", roughness=0.85)

    # --- 10. orange caps on the gate posts (highest point of the prop) --------------
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * (POST_IN - 0.09), sx * HX))
        D.beveled_box(bm, (lo_x, POST_Y0 - 0.09, POST_TOP - 0.06), (hi_x, Y_FRONT, CAP_TOP),
                      bevel=0.07)
    D.new_obj("PostCaps", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.50)

    # --- 11. entry bollards: the same form, one third the height --------------------
    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * POST_IN, sx * POST_OUT))
        D.beveled_box(bm, (lo_x, BOLL_Y0, 0.0), (hi_x, BOLL_Y1, BOLL_TOP), bevel=0.10)
    D.new_obj("EntryBollards", bm, c, DARK, rbx_material="Metal", metallic=0.55, roughness=0.45)

    bm = bmesh.new()
    for sx in (-1.0, 1.0):
        lo_x, hi_x = sorted((sx * (POST_IN - 0.05), sx * HX))
        D.beveled_box(bm, (lo_x, Y_BACK, BOLL_TOP - 0.06), (hi_x, BOLL_Y1 + 0.04, BOLL_CAP),
                      bevel=0.07)
    D.new_obj("BollardCaps", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.50)

    # --- 12. three chevrons, growing AND brightening toward +Y ----------------------
    #      (name,      width, depth, thick,  y offset, rbx transparency)
    chevrons = (
        ("Chevron1", 2.80, 1.05, 0.52, -3.38, 0.30),
        ("Chevron2", 3.90, 1.45, 0.62, -0.28, 0.15),
        ("Chevron3", 5.00, 1.85, 0.72,  3.32, 0.00),
    )
    for name, width, depth, thick, yoff, transp in chevrons:
        bm = bmesh.new()
        D.prism(bm, D.chevron_pts(width, depth, thick, tip_at=+1), CHEV_Z0, CHEV_Z1,
                matrix=Matrix.Translation((0.0, yoff, 0.0)))
        D.new_obj(name, bm, c, CYAN, rbx_material="Neon", transparency=transp,
                  roughness=0.85)

    return c


# ---------------------------------------------------------------------------------
# AUDIT - 15 parts, ~624 tris (budget 700), bbox 8.00 x 12.00 x 2.94, min_z = 0.000
#
#  part           colour role          hex      material  prims                    tris
#  DeckSlab       Metal mid            6c7789   Metal     1 beveled_box              44
#  EntryRamp      Accent orange        ff8a3d   Smooth..  1 wedge                     8
#  RampArrow      Energy cyan (glow)   4dd2ff   Neon      1 prism (6-gon)            20
#  TreadDeck      Rubber black         2a2d33   Plastic   1 beveled_box              44
#  RailBodies     Metal dark           3b4350   Metal     2 prism (4-gon)            24
#  RailCaps       Accent orange        ff8a3d   Smooth..  2 prism (4-gon)            24
#  RailGlow       Energy cyan (glow)   4dd2ff   Neon      2 prism (4-gon)            24
#  ExitPosts      Metal dark           3b4350   Metal     2 beveled_box              88
#  PostLights     Energy cyan (glow)   4dd2ff   Neon      2 box                      24
#  PostCaps       Accent orange        ff8a3d   Smooth..  2 beveled_box              88
#  EntryBollards  Metal dark           3b4350   Metal     2 beveled_box              88
#  BollardCaps    Accent orange        ff8a3d   Smooth..  2 beveled_box              88
#  Chevron1/2/3   Energy cyan (glow)   4dd2ff   Neon      3 prism (6-gon)            60
#                                                                            total  624
#  (prism n-gon = 2*(n-2) + 2n tris; beveled_box = 44; box = 12; wedge = 8.)
#
# value ladder (adjacent parts always jump a step):
#   TreadDeck 2a2d33  <  RailBodies / ExitPosts / EntryBollards 3b4350  <  DeckSlab
#   6c7789  <  every orange cap ff8a3d  <  cyan Neon 4dd2ff
# The black lane sits inside a mid-grey frame; every dark mass is capped bright orange;
# the only cyan is the energy read, so the glow never competes with the structure.
#
# key z levels: 0.00 ground | 0.36 chassis top | 0.52 RUNNING SURFACE | 0.66 chevron tops
#   rail top 0.62 -> 1.80 climbing toward +Y, its orange cap 0.15 above that
#   entry bollards 0.86, their caps 1.06 | gate posts 2.70, lamp collar 2.02-2.46,
#   post caps 2.94 (highest point)
# ---------------------------------------------------------------------------------
