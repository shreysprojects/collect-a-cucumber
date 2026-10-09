"""Tier 10 headband: a polished gold band, a row of pyramid studs, one big gem boss."""
import bmesh

COLLECTION = "GoldBand"
TIER = 10
DISPLAY_NAME = "Gold Band"
NOTES = (
    "Four MeshParts, grouped by colour. BandBody (gold f0b429) is the mid ring; BrightTrim "
    "(ffd966) carries the top edge ring AND all eleven pyramid studs in one mesh; DarkTrim "
    "(d99a1a) carries the bottom edge ring AND the boss's collar plate plus its four prongs; "
    "Boss (ffd966) is the single big gem, kept its own part because it is the focal point "
    "and wants its own material tuning. Everything is metallic 0.9 / roughness ~0.25, "
    "Enum.Material.Foil on the two bright parts and Metal on the two darker ones.\n"
    "The band is a STEPPED TAPER, not a cylinder: outer radius grows 0.735 -> 0.757 -> 0.775 "
    "from bottom to top, so the mid body overhangs the dark bottom ring (shadow line) and the "
    "bright top ring overhangs the body (catch line). Hard edges throughout, bulge=0 - this is "
    "cast metal, not cloth.\n"
    "HEADROOM: the boss and its prongs deliberately overhang the band, reaching z +0.295 above "
    "and z -0.275 below and radius 1.109 forward. Nothing else leaves the ring. Tightest radius "
    "anywhere is 0.633 (the band's inner wall, 0.003 outside H.R_IN and 0.033 clear of a default "
    "R15 head); the boss's buried rear point is the next tightest at 0.662. Worn with the "
    "Handle attachment at (0, H.BAND_Z_ON_HEAD, 0) like every other band in the set."
)

# ---------------------------------------------------------------------------- palette
GOLD = "f0b429"        # mid value - the body of the band
BRIGHT = "ffd966"      # bright highlight - top rim, studs, the gem itself
DEEP = "d99a1a"        # deep gold - bottom rim, the setting behind the gem

# ---------------------------------------------------------------------------- profile
SEG = 24               # 8 tris per segment per ring, three rings = 576 of the 800 budget
R_INNER = 0.633        # a hair outside H.R_IN so no vertex can ever land inside the head
R_LOW = 0.735          # outer face of the dark bottom ring   (recessed -> shadow)
R_MID = 0.757          # outer face of the gold body          (the studs sit on this)
R_HIGH = 0.775         # outer face of the bright top ring    (proud   -> highlight)
Z_BOT = -0.135         # bottom of the band
Z_B1 = -0.070          # bottom ring / body seam
Z_B2 = 0.075           # body / top ring seam
Z_TOP = 0.145          # top of the band                      (total height 0.280)

# ---------------------------------------------------------------------------- studs
STUD_N = 12            # twelve slots, front centre skipped for the boss -> 11 studs
STUD_AT = 0.745        # stud centre radius: equator sits just INSIDE R_MID, so it is seated
STUD_R = 0.092         # chunky - 0.184 wide against a 0.390 slot pitch, so gaps read tight
STUD_Z = 0.005         # centred on the body, level with the boss

# ---------------------------------------------------------------------------- gem boss
BOSS_AT = 0.850        # gem centre radius (rear point lands at 0.662 - buried, still clear)
BOSS_R = 0.235         # 2.55x the stud radius, the focal point of the whole piece
BOSS_Z = 0.010
BOSS_POINT = 1.10      # shallower than the studs' default 1.5 so the tip stays inside 1.15
BOSS_FLAT = 0.80
COLLAR_R = 0.265       # bezel plate, 0.03 proud of the gem's equator all the way round
COLLAR_Y0 = 0.710      # inner face is buried in the band (R_MID 0.757), so it reads seated
COLLAR_Y1 = 0.830
PRONG_SIZE = 0.100
PRONG_H = 0.140
PRONG_Y = 0.800        # base plane; apex ends up at y 0.940, out past the gem's shoulder


def build(H):
    """H is the imported headbandlib module (it also has every defenselib primitive)."""
    H.clear_collection(COLLECTION)
    c = H.coll(COLLECTION)

    # --- band body ---------------------------------------------------------------------
    # The middle step of the taper. bulge=0 keeps the outer face dead cylindrical and both
    # of its edges hard, which is the whole point of a metal band next to the cloth tiers.
    bm = bmesh.new()
    H.band(bm, r_in=R_INNER, r_out=R_MID, z0=Z_B1, z1=Z_B2, segs=SEG, bulge=0.0)
    H.new_obj("BandBody", bm, c, GOLD, rbx_material="Metal", metallic=0.9, roughness=0.28)

    # --- bright top rim + the stud row ---------------------------------------------------
    # Same colour, so one mesh. The rim steps OUT to R_HIGH, leaving a 0.018 shelf on top of
    # the body that catches the key light. The studs are octa_gem, whose local +Y is radially
    # outward, so each one is a pyramid pointing straight off the head. Slot 0 is the forehead
    # centre and is skipped - the boss lives there.
    bm = bmesh.new()
    H.stripe(bm, R_INNER, R_HIGH, Z_B2, Z_TOP, segs=SEG)
    for a in H.ring_angles(STUD_N, 360.0, 0.0)[1:]:
        H.octa_gem(bm, H.on_ring(STUD_AT, a, STUD_Z), STUD_R, a)
    H.new_obj("BrightTrim", bm, c, BRIGHT, rbx_material="Foil", metallic=0.9, roughness=0.22)

    # --- dark bottom rim + the gem's setting -----------------------------------------------
    # Also one colour, one mesh. The rim steps IN to R_LOW so the body overhangs it by 0.022
    # and it sits in permanent shadow - that is the bottom of the value ladder.
    bm = bmesh.new()
    H.stripe(bm, R_INNER, R_LOW, Z_BOT, Z_B1, segs=SEG)
    # Collar: a shallow ten-sided plate lying flat against the forehead, axis running radially
    # outward (+Y at angle 0). Its rear face is inside the band, its front face is 0.02 behind
    # the gem's equator, so the gem reads as SET INTO it rather than glued on.
    H.cyl(bm, (0.0, COLLAR_Y0, BOSS_Z), (0.0, COLLAR_Y1, BOSS_Z), COLLAR_R, segs=10)
    # Four prongs at the gem's four equator vertices. pyramid() builds standing on +Z, so
    # rot_euler(-90, 0, 0) lays each one over to point +Y; the base square ends up in the
    # x/z plane at y = PRONG_Y and the apex at y = PRONG_Y + PRONG_H, out past the gem face.
    lay = H.rot_euler(-90, 0, 0)
    for px, pz in ((BOSS_R, BOSS_Z), (-BOSS_R, BOSS_Z),
                   (0.0, BOSS_Z + BOSS_R), (0.0, BOSS_Z - BOSS_R)):
        H.pyramid(bm, (px, PRONG_Y, pz), PRONG_SIZE, PRONG_H, rot=lay)
    H.new_obj("DarkTrim", bm, c, DEEP, rbx_material="Metal", metallic=0.9, roughness=0.34)

    # --- the gem boss ------------------------------------------------------------------------
    # One octa_gem at angle 0 (dead front), 2.55x the stud radius. Its rear point buries at
    # radius 0.662 inside the band, its tip reaches 1.109 - clearly proud, and the brightest
    # thing on the piece.
    bm = bmesh.new()
    H.octa_gem(bm, H.on_ring(BOSS_AT, 0.0, BOSS_Z), BOSS_R, 0.0,
               point=BOSS_POINT, flat=BOSS_FLAT)
    H.new_obj("Boss", bm, c, BRIGHT, rbx_material="Foil", metallic=0.9, roughness=0.18)

    return c


# -------------------------------------------------------------------------------------------
# PARTS                                       COLOUR   MATERIAL  TRIS
#   BandBody    mid ring, r_out 0.757         f0b429   Metal      192   (24 segs x 4 quads)
#   BrightTrim  top ring r_out 0.775          ffd966   Foil       192   (24 segs x 4 quads)
#               + 11 pyramid studs                                 88   (11 x 8)
#   DarkTrim    bottom ring r_out 0.735       d99a1a   Metal      192   (24 segs x 4 quads)
#               + collar plate (10-gon)                            36   (20 side + 16 cap)
#               + 4 prongs                                         24   (4 x 6)
#   Boss        the big faceted gem           ffd966   Foil         8
#                                                               -----
#                                                                 732   of an 800 budget
#
# FIT   min radius 0.633  (band inner wall; boss rear point 0.662, stud rear points 0.676)
#       max radius 1.109  (boss tip; prong apexes 0.969, stud tips 0.883)
#       z range   -0.275 .. +0.295  (band alone is -0.135 .. +0.145; the overhang is the
#                                    boss and its lower/upper prongs, as the brief allows)
# -------------------------------------------------------------------------------------------
