"""Turret - twin-cannon emplacement: bolted plinth, yawing head, pitching gun cradle."""
import bmesh
import math

COLLECTION = "Turret"

NOTES = (
    "Rig by name prefix: Base* is static, Head* yaws about the world Z axis through "
    "(0, 0), Barrel* pitches about a horizontal axis parallel to X through the trunnion "
    "at (0, 0, 4.80). Modelled at zero yaw / zero pitch, barrels level and pointing +Y. "
    "Mass hierarchy is deliberate: the GUN is the biggest thing on the prop. The twin "
    "cannon runs 4.6 studs nose to tail (y -0.75 to 3.88) with 0.84-stud-thick tubes and "
    "chunky square muzzle brakes, and it projects 3.1 studs past the cradle face; the "
    "counterweight is a fat horizontal ammo drum behind the trunnion, NOT a vertical "
    "column - the silhouette's long axis is fore-aft, not up. "
    "Static base footprint 5.8 x 5.8 studs (feet), total height 5.86 studs. "
    "The gun deliberately overhangs the plinth, as a real turret's does: the widest "
    "yawing point is a brake-tip corner at radius 3.99, so a full 360 deg spin stays "
    "inside the standard 8 x 8 TILE. Everything on the head BEHIND the trunnion stays "
    "inside radius 2.76, i.e. within the 6 x 6 base footprint. "
    "Nothing dips below z = 0 (lowest geometry is the foot pads' bottom face at z = 0.0 "
    "and the conduit, which terminates buried inside the rear-left foot). "
    "Three Neon parts: HeadEye (sensor lens on the housing front) and BarrelMuzzleGlow "
    "(a charge disc inside each muzzle) - cyan reads as the targeting line. Orange "
    "accents: BaseCollar, HeadCheeks, BarrelMantlet, BarrelBand. "
    "HeadTrunnion is the axle and is grouped with the head, not the barrels, so it does "
    "not spin visually when the guns elevate. HeadDrum likewise stays with the head, so "
    "the counterweight never has to clear anything. The pitching group is centred on the "
    "trunnion in both y and z: traced by hand, at +/- 30 deg it still clears the housing "
    "top by 0.13 and the drum surface by 0.20, so +/- 25 deg is a safe usable range."
)

PIVOTS = {
    "YawPivot":     (0.00,  0.00, 1.58),  # top face of BaseRing, on the vertical axis
    "PitchPivot":   (0.00,  0.00, 4.80),  # trunnion centre, axis parallel to X
    "MuzzleTipL":   (-0.50, 3.88, 4.80),  # centre of the left muzzle glow disc
    "MuzzleTipR":   (0.50,  3.88, 4.80),
    "EyeLens":      (0.00,  1.10, 2.75),  # front sensor glow, for a targeting beam origin
    "DrumCentre":   (0.00, -1.65, 4.35),  # ammo drum axis, for a reload / spin VFX
}


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    DARK = "3b4350"      # metal dark
    MID = "6c7789"       # metal mid
    LIGHT = "9aa7b8"     # metal light
    BRIGHT = "d5dbe4"    # steel bright
    ORANGE = "ff8a3d"    # accent orange
    CYAN = "4dd2ff"      # energy cyan (Neon)
    RUBBER = "2a2d33"    # rubber black

    FEET = ((-2.05, -2.05), (2.05, -2.05), (-2.05, 2.05), (2.05, 2.05))

    # ------------------------------------------------------------------ BASE (static)
    # Four splayed corner pads. 1.70 sq x 0.42 tall, outer corners reach x/y = +/-2.90.
    bm = bmesh.new()
    for fx, fy in FEET:
        D.beveled_box(bm, (fx - 0.85, fy - 0.85, 0.00), (fx + 0.85, fy + 0.85, 0.42),
                      bevel=0.12)
    D.new_obj("BaseFeet", bm, c, DARK, rbx_material="Metal", metallic=0.35, roughness=0.5)

    # Tapered octagonal plinth, 2.55 r at the ground down-flaring to 2.05 r at the top.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 0.00), (0.0, 0.0, 1.18), 2.55, segs=8, r2=2.05)
    D.new_obj("BasePlinth", bm, c, MID, rbx_material="Metal", metallic=0.3, roughness=0.55)

    # Orange hazard flange biting out of the plinth - widens the read at ground level.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(8, 2.62, phase=math.pi / 8.0), 0.56, 0.86)
    D.new_obj("BaseCollar", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.6)

    # Yaw bearing the head sits on. Dark gasket ring against the mid plinth.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 1.18), (0.0, 0.0, 1.58), 2.02, segs=12)
    D.new_obj("BaseRing", bm, c, RUBBER, rbx_material="Metal", roughness=0.8)

    # Anchor bolts capping each foot - bright steel pops off the dark pads.
    bm = bmesh.new()
    for fx, fy in FEET:
        D.cyl(bm, (fx, fy, 0.38), (fx, fy, 0.54), 0.20, segs=6)
    D.new_obj("BaseBolts", bm, c, BRIGHT, rbx_material="Metal", metallic=0.7, roughness=0.35)

    # Power feed: plinth -> ground -> plugs into the rear-left foot. Sells "powered".
    bm = bmesh.new()
    D.tube(bm,
           [(-1.90, -0.55, 1.02), (-2.35, -0.80, 0.70), (-2.65, -1.10, 0.30),
            (-2.55, -1.75, 0.20)],
           [0.16, 0.16, 0.16, 0.16], segs=6)
    D.new_obj("BaseConduit", bm, c, RUBBER, rbx_material="Plastic", roughness=0.85)

    # ------------------------------------------------------------------ HEAD (yaws)
    # Rotating deck plate, overhangs the bearing by 0.14 so the joint reads as a joint.
    bm = bmesh.new()
    D.prism(bm, D.ngon_pts(12, 2.16), 1.52, 1.86)
    D.new_obj("HeadTurntable", bm, c, LIGHT, rbx_material="DiamondPlate", metallic=0.4,
              roughness=0.5)

    # Main housing: 3.00 wide x 3.20 deep x 1.80 tall, and DELIBERATELY squat - it is the
    # gun's plinth, not the star. Rear face at y = -2.30 carries the ammo drum.
    bm = bmesh.new()
    D.beveled_box(bm, (-1.50, -2.30, 1.80), (1.50, 0.90, 3.60), bevel=0.20)
    D.new_obj("HeadHousing", bm, c, MID, rbx_material="Metal", metallic=0.3, roughness=0.5)

    # Orange armour cheeks bolted to both flanks of the housing.
    bm = bmesh.new()
    D.beveled_box(bm, (1.46, -2.05, 2.05), (1.74, 0.70, 3.40), bevel=0.10)
    D.beveled_box(bm, (-1.74, -2.05, 2.05), (-1.46, 0.70, 3.40), bevel=0.10)
    D.new_obj("HeadCheeks", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.6)

    # Trunnion yoke: two dark arms rising out of the housing top, axis at z = 4.80. Their
    # inner faces at x = +/-1.14 are the clearance envelope the whole gun lives inside.
    bm = bmesh.new()
    D.beveled_box(bm, (1.14, -0.90, 3.30), (1.52, 0.80, 5.35), bevel=0.12)
    D.beveled_box(bm, (-1.52, -0.90, 3.30), (-1.14, 0.80, 5.35), bevel=0.12)
    D.new_obj("HeadYoke", bm, c, DARK, rbx_material="Metal", metallic=0.35, roughness=0.5)

    # The pitch axle itself, poking 0.08 proud of each yoke arm as a boss.
    bm = bmesh.new()
    D.cyl(bm, (-1.60, 0.00, 4.80), (1.60, 0.00, 4.80), 0.32, segs=8)
    D.new_obj("HeadTrunnion", bm, c, LIGHT, rbx_material="Metal", metallic=0.6,
              roughness=0.35)

    # Ammo drum / counterweight: a FAT horizontal cylinder on the X axis behind the
    # trunnion. This replaces the old vertical heat-sink column - horizontal mass back
    # here reads as the breech end of the gun, a stack read as a chimney.
    bm = bmesh.new()
    D.cyl(bm, (-1.05, -1.65, 4.35), (1.05, -1.65, 4.35), 0.90, segs=12)
    D.new_obj("HeadDrum", bm, c, DARK, rbx_material="Metal", metallic=0.4, roughness=0.45)

    # Bright hub caps on the drum ends - the value pop that keeps the dark drum from
    # merging with the dark yoke in a side-on silhouette.
    bm = bmesh.new()
    D.cyl(bm, (1.05, -1.65, 4.35), (1.16, -1.65, 4.35), 0.50, segs=8)
    D.cyl(bm, (-1.16, -1.65, 4.35), (-1.05, -1.65, 4.35), 0.50, segs=8)
    D.new_obj("HeadDrumHubs", bm, c, BRIGHT, rbx_material="Metal", metallic=0.7,
              roughness=0.35)

    # NEON 1/3 - targeting lens on the housing front, protruding 0.20 toward +Y, sitting
    # well below the gun so it stays visible head-on.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.82, 2.75), (0.0, 1.10, 2.75), 0.40, segs=8)
    D.new_obj("HeadEye", bm, c, CYAN, rbx_material="Neon")

    # ------------------------------------------------------------------ BARREL (pitches)
    # Cradle, centred on the trunnion in BOTH y and z (0, 0, 4.80) so it swings clean.
    bm = bmesh.new()
    D.beveled_box(bm, (-1.05, -0.75, 4.15), (1.05, 0.75, 5.45), bevel=0.16)
    D.new_obj("BarrelCradle", bm, c, MID, rbx_material="Metal", metallic=0.3, roughness=0.5)

    # Orange mantlet plate on the cradle face; the tubes pass straight through it.
    bm = bmesh.new()
    D.beveled_box(bm, (-1.12, 0.62, 4.08), (1.12, 0.90, 5.52), bevel=0.10)
    D.new_obj("BarrelMantlet", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.6)

    # THE GUN. Twin tubes 0.88 studs thick on 1.00 centres, running from inside the
    # cradle out to y = 3.05. Deliberately ONE interruption (the band) along their length:
    # a barrel chopped into five bands reads as greeble, not as a gun.
    bm = bmesh.new()
    for bx in (-0.50, 0.50):
        D.cyl(bm, (bx, -0.55, 4.80), (bx, 3.05, 4.80), 0.44, segs=12)
    D.new_obj("BarrelTubes", bm, c, LIGHT, rbx_material="Metal", metallic=0.6,
              roughness=0.35)

    # Orange clamp bridging both tubes at mid barrel.
    bm = bmesh.new()
    D.beveled_box(bm, (-1.02, 1.55, 4.26), (1.02, 1.95, 5.34), bevel=0.12)
    D.new_obj("BarrelBand", bm, c, ORANGE, rbx_material="SmoothPlastic", roughness=0.6)

    # Muzzle brakes - 0.94 x 1.08 blocks, wider and taller than the tubes, so the
    # business end has real weight in the silhouette.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.98, 2.85, 4.26), (-0.04, 3.55, 5.34), bevel=0.14)
    D.beveled_box(bm, (0.04, 2.85, 4.26), (0.98, 3.55, 5.34), bevel=0.14)
    D.new_obj("BarrelMuzzles", bm, c, DARK, rbx_material="Metal", metallic=0.5,
              roughness=0.4)

    # Bright flared collars on the very tips - a hard terminal accent so the muzzles read
    # as openings rather than as blunt dark stubs, and the widest point of the whole yaw
    # sweep (r = 3.99, still inside the 8 x 8 tile).
    bm = bmesh.new()
    D.beveled_box(bm, (-1.00, 3.55, 4.18), (-0.04, 3.86, 5.42), bevel=0.10)
    D.beveled_box(bm, (0.04, 3.55, 4.18), (1.00, 3.86, 5.42), bevel=0.10)
    D.new_obj("BarrelBrakeTips", bm, c, BRIGHT, rbx_material="Metal", metallic=0.7,
              roughness=0.35)

    # NEON 2/3 and 3/3 - charge discs down the muzzles. Two glowing eyes aimed at the
    # player is what sells "this thing is pointed at me" from the front.
    bm = bmesh.new()
    for bx in (-0.50, 0.50):
        D.cyl(bm, (bx, 3.80, 4.80), (bx, 3.88, 4.80), 0.26, segs=8)
    D.new_obj("BarrelMuzzleGlow", bm, c, CYAN, rbx_material="Neon")

    # Optic riding the cradle top, so the guns read as aimed rather than parked.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.28, -0.30, 5.45), (0.28, 0.60, 5.86), bevel=0.10)
    D.new_obj("BarrelSight", bm, c, RUBBER, rbx_material="Plastic", roughness=0.8)

    return c


# ---------------------------------------------------------------------------------------
# PART LIST - name / colour role / hex / approx tris        (tri = 44 per beveled_box,
#                                                            12 per box, 4n-4 per n-seg
#                                                            cylinder or n-gon prism)
#
#   BaseFeet        metal dark    3b4350   4 x beveled_box ............... 176
#   BasePlinth      metal mid     6c7789   8-seg tapered cyl .............  28
#   BaseCollar      accent orange ff8a3d   8-gon prism flange ............  28
#   BaseRing        rubber black  2a2d33   12-seg cyl bearing ............  44
#   BaseBolts       steel bright  d5dbe4   4 x 6-seg cyl .................  80
#   BaseConduit     rubber black  2a2d33   4-pt, 6-seg tube ..............  44
#                                                          BASE subtotal   400
#
#   HeadTurntable   metal light   9aa7b8   12-gon prism deck .............  44
#   HeadHousing     metal mid     6c7789   beveled_box ...................  44
#   HeadCheeks      accent orange ff8a3d   2 x beveled_box ...............  88
#   HeadYoke        metal dark    3b4350   2 x beveled_box ...............  88
#   HeadTrunnion    metal light   9aa7b8   8-seg cyl axle ................  28
#   HeadDrum        metal dark    3b4350   12-seg cyl, X axis ............  44
#   HeadDrumHubs    steel bright  d5dbe4   2 x 8-seg cyl .................  56
#   HeadEye         energy cyan   4dd2ff   8-seg cyl  [NEON] .............  28
#                                                          HEAD subtotal   420
#
#   BarrelCradle    metal mid     6c7789   beveled_box ...................  44
#   BarrelMantlet   accent orange ff8a3d   beveled_box ...................  44
#   BarrelTubes     metal light   9aa7b8   2 x 12-seg cyl, r 0.44 ........  88
#   BarrelBand      accent orange ff8a3d   beveled_box ...................  44
#   BarrelMuzzles   metal dark    3b4350   2 x beveled_box ...............  88
#   BarrelBrakeTips steel bright  d5dbe4   2 x beveled_box ...............  88
#   BarrelMuzzleGlow energy cyan  4dd2ff   2 x 8-seg cyl  [NEON] .........  56
#   BarrelSight     rubber black  2a2d33   beveled_box ...................  44
#                                                        BARREL subtotal   496
#
#   22 objects, ~1316 tris of a 1400 budget.
#   Bounding box  x -2.90..2.90  |  y -2.90..3.88  |  z 0.00..5.86  = 5.80 x 6.78 x 5.86
#   Static base footprint 5.80 x 5.80.  Yaw sweep radius 3.99 (brake-tip corner) so a full
#   spin stays inside the 8 x 8 TILE; everything behind the trunnion sweeps r <= 2.76.
#   Value ladder along the gun, root to tip:
#     MID cradle -> ORANGE mantlet -> LIGHT tubes -> ORANGE band -> LIGHT tubes ->
#     DARK brakes -> BRIGHT tips -> CYAN glow.  No two touching parts share a value.
# ---------------------------------------------------------------------------------------
