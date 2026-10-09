"""Flat-screen TV on a low media console.

A chamfered wood cabinet on four short tapered metal legs, with two slatted doors, a
drawer line and a black top slab; on it a thin black panel on a T-stand (neck + oval foot
plate), the screen lit with a blocky sunset scene.  A brushed soundbar lies on the console
in front of the stand and a white remote is left on the top, angled, over at the viewer's
right (negative x).  Faces +Y - the screen is the +Y face."""
import bmesh, math

COLLECTION = "TV"

NOTES = (
    "Footprint 6.4 x 1.8 studs (the black top slab is the widest part), 4.86 studs tall - "
    "console top surface at z 1.42, screen panel z 2.10..4.86, screen aperture "
    "x +/-2.34, z 2.37..4.73.  Stands flat on z=0 on four legs at (+/-2.58, +/-0.56); "
    "nothing dips below the ground plane.\n"
    "The screen is four Neon objects stacked a hair proud of one another between "
    "y 0.03 and y 0.116, all inside the bezel (front face y 0.13): ScreenSky is the lit "
    "backdrop, ScreenLand the ground band + hill + tower block, ScreenSun the sun disc + "
    "horizon glow strip, and RedLights holds the stand-by dot on the bezel.  To switch the "
    "set OFF, recolour ScreenSky to screen_dark and set the three Screen* objects' "
    "material to SmoothPlastic (or just raise their Transparency); to play a channel, swap "
    "or re-tint ScreenLand / ScreenSun - they are the only content geometry.\n"
    "The T-stand is meant to SHOW.  The oval foot plate is a chunky 0.24 thick (z "
    "1.42..1.66) and the neck runs z 1.42..2.35 with its front face at y 0.08, proud of the "
    "panel chassis at y 0.02, so ~0.48 studs of bright metal read in the open air between "
    "the soundbar top (z 1.62) and the panel bottom (z 2.10).  Anything you move onto the "
    "console top must stay under z 1.62 or it swallows the stand again.\n"
    "Separable sub-props, each its own object: Soundbar (+ its grille windows, the first "
    "eight slats in BlackTrim) sits loose on the console top at the front lip, y 0.54..0.88, "
    "z 1.42..1.62; Remote is a loose slab centred at (-2.48, 0.16, 1.49) yawed 24 deg, i.e. "
    "on the RIGHT as a player faces the prop, with its three dark buttons in BlackTrim and "
    "its red power button in RedLights.  "
    "Delete Remote + Soundbar for a bare console; delete Panel + Screen* + Stand for a "
    "plain media unit.\n"
    "The door fronts are TWO objects on purpose: DoorRecess is the dark timber backing "
    "plate (y 0.78..0.84) and Doors is the pale louvre slats standing proud of it (y "
    "0.84..0.90).  That value break is the only thing that makes the louvres read at 40 "
    "studs - do not merge them back into one colour.  The doors are decorative, not hinged; "
    "the carcass shows as a ~0.5-stud timber stile at each end and between the two doors.\n"
    "PIVOTS['ScreenSwivel'] is the top of the stand foot: turn Panel and the three Screen* "
    "objects about it (Z axis) by a STATES angle to swivel the picture toward a viewer.  "
    "The little metal logo bar under the screen is merged into Stand - split it off first "
    "if you want the swivel to be exact."
)

PIVOTS = {"ScreenSwivel": (0.0, -0.10, 1.66)}
STATES = {"Straight": 0.0, "TurnedLeft": 20.0, "TurnedRight": -20.0}   # degrees about Z

# ---- the numbers the whole prop hangs off ---------------------------------------
# The console is deliberately low and the soundbar deliberately flat: the 0.48-stud band of
# air between Z_BAR and Z_P0 is where the T-stand lives, and it is the whole point.
Z_LEG, Z_CAB, Z_TOP = 0.30, 1.28, 1.42          # cabinet bottom / cabinet top / top surface
Z_FOOT = 1.66                                   # stand foot plate top (0.04 over the bar)
Z_BAR = 1.62                                    # soundbar top - keep it under the stand foot
Z_P0, Z_P1 = 2.10, 4.86                         # screen panel bottom / top
Z_A0, Z_A1 = 2.37, 4.73                         # screen aperture bottom / top
Z_DOOR0, Z_DOOR1 = 0.36, 1.08                   # door front bottom / top on the carcass
X_CAB, Y_CAB = 3.00, 0.80                       # cabinet half-width / half-depth
X_TOP, Y_TOP = 3.20, 0.90                       # top slab half-width / half-depth
X_DOOR = 2.50                                   # door / drawer-line half-width (0.5 of stile)
X_P, X_A = 2.50, 2.34                           # panel / aperture half-width
Y_BACK, Y_FACE, Y_BEZ = -0.20, 0.02, 0.13       # panel back / chassis front / bezel front
Y_NECK = 0.08                                   # stand neck front - proud of Y_FACE, on show
Y_SKY, Y_LAND, Y_SUN, Y_LIT = 0.030, 0.086, 0.100, 0.116   # screen layer fronts
DOORS = ((0.20, X_DOOR), (-X_DOOR, -0.20))      # the two door spans in x

REMOTE = (-2.48, 0.16)                          # remote centre on the console top
REMOTE_YAW = 24.0                               # degrees of casual yaw


def _rp(lx, ly):
    """A point on the remote's top face, given in remote-local (across, along) studs."""
    a = math.radians(REMOTE_YAW)
    return (REMOTE[0] + lx * math.cos(a) - ly * math.sin(a),
            REMOTE[1] + lx * math.sin(a) + ly * math.cos(a))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    bright = D.C("metal_light")      # legs, stand, soundbar shell, cabinet trim
    timber = D.C("wood_mid")         # cabinet carcass - the mid value of the prop
    recess = D.C("wood_dark")        # the door backing the louvres are read against
    pale = D.C("plastic_white")      # louvre slats, remote
    black = D.C("plastic_black")     # top slab, bezel + chassis, grille, buttons
    sky = D.C("screen_glow")
    land = D.C("neon_lime")
    sun = D.C("neon_yellow")
    red = D.C("neon_red")

    METAL = dict(rbx_material="Metal", metallic=0.62, roughness=0.38)
    SHELL = dict(rbx_material="SmoothPlastic", roughness=0.48)

    # ============================================================ console cabinet
    # Carcass: one chamfered box.  Doors sit ON its front face, so the carcass reads as a
    # solid timber block behind them.
    bm = bmesh.new()
    D.beveled_box(bm, (-X_CAB, -Y_CAB, Z_LEG), (X_CAB, Y_CAB, Z_CAB), bevel=0.09)
    D.new_obj("Cabinet", bm, c, timber, rbx_material="Wood", roughness=0.70)

    # The recessed backing plate the louvres sit in - dark timber, so the pale slats have
    # something to read against and the carcass keeps a wide stile at each end.
    bm = bmesh.new()
    for (x0, x1) in DOORS:
        D.box(bm, (x0, 0.78, Z_DOOR0), (x1, 0.84, Z_DOOR1))
    D.new_obj("DoorRecess", bm, c, recess, rbx_material="Wood", roughness=0.68)

    # The louvres themselves: four pale slats per door standing proud of the dark recess.
    bm = bmesh.new()
    for (x0, x1) in DOORS:
        D.slat_run(bm, (x0 + 0.06, 0.84, Z_DOOR0 + 0.08), (x1 - 0.06, 0.90, Z_DOOR1 - 0.08),
                   4, gap_frac=0.34, axis='z', bevel=0.0)
    D.new_obj("Doors", bm, c, pale, **SHELL)

    # Legs, the drawer line above the doors, and the two door pulls - one bright metal set.
    bm = bmesh.new()
    for (lx, ly) in D.grid_positions(2, 2, 5.16, 1.12):
        D.cyl(bm, (lx, ly, 0.00), (lx, ly, Z_LEG + 0.02), 0.13, segs=6, r2=0.19)
    D.box(bm, (-X_DOOR, 0.80, Z_DOOR1 + 0.06), (X_DOOR, 0.86, Z_DOOR1 + 0.14))
    for (x0, x1) in ((0.26, 0.40), (-0.40, -0.26)):
        D.box(bm, (x0, 0.90, 0.54), (x1, 0.96, 0.90))
    D.new_obj("Metalwork", bm, c, bright, **METAL)

    # The black top slab overhangs the carcass on every side and caps the doors.
    bm = bmesh.new()
    D.beveled_box(bm, (-X_TOP, -Y_TOP, Z_CAB), (X_TOP, Y_TOP, Z_TOP), bevel=0.06)
    D.new_obj("ConsoleTop", bm, c, black, **SHELL)

    # ============================================================ T-stand
    # A chunky oval foot plate whose rim clears the soundbar, a chamfered neck standing
    # PROUD of the panel chassis (Y_NECK > Y_FACE) so its front face takes the key light,
    # and the little logo bar on the bottom bezel (same bright metal, so one object).
    # arc_pts(0..330, n=12) is a closed regular 12-gon once prism wraps it - the last edge
    # is the same 30 deg step as the rest.  Do NOT "close" it to 0..360: that repeats the
    # first point and hands prism a degenerate polygon.
    bm = bmesh.new()
    D.prism(bm, D.arc_pts((0.0, -0.10), 1.45, 0, 330, n=12, ry=0.42), Z_TOP, Z_FOOT)
    D.beveled_box(bm, (-0.55, Y_BACK + 0.02, Z_TOP), (0.55, Y_NECK, Z_P0 + 0.25), bevel=0.06)
    D.box(bm, (0.62, Y_BEZ, Z_P0 + 0.06), (1.42, Y_BEZ + 0.03, Z_P0 + 0.17))
    D.new_obj("Stand", bm, c, bright, **METAL)

    # ============================================================ screen panel
    # Chassis slab + a slim four-bar bezel standing proud of its front face.
    bm = bmesh.new()
    D.beveled_box(bm, (-X_P, Y_BACK, Z_P0), (X_P, Y_FACE, Z_P1), bevel=0.07)
    D.box(bm, (-X_P, Y_FACE, Z_P0), (-X_A, Y_BEZ, Z_P1))
    D.box(bm, (X_A, Y_FACE, Z_P0), (X_P, Y_BEZ, Z_P1))
    D.box(bm, (-X_A, Y_FACE, Z_A1), (X_A, Y_BEZ, Z_P1))
    D.box(bm, (-X_A, Y_FACE, Z_P0), (X_A, Y_BEZ, Z_A0))
    D.new_obj("Panel", bm, c, black, **SHELL)

    # The lit backdrop: fills the whole aperture, everything else stacks in front of it.
    bm = bmesh.new()
    D.box(bm, (-X_A, Y_SKY, Z_A0), (X_A, Y_LAND, Z_A1))
    D.new_obj("ScreenSky", bm, c, sky, rbx_material="Neon", emit=0.8)

    # Ground band + a trapezoid hill on the LEFT of the view (+x) and one tower block.
    # Everything on the screen hangs off Z_HOR so the picture rides with the panel.
    Z_HOR = Z_A0 + 0.63                          # the horizon line inside the aperture
    bm = bmesh.new()
    D.box(bm, (-X_A, Y_LAND, Z_A0), (X_A, Y_SUN, Z_HOR))
    D.prism(bm, [(0.55, 0.00), (2.15, 0.00), (1.62, 0.82), (1.05, 0.82)], -Y_SUN, -Y_LAND,
            matrix=D.place((0.0, 0.0, Z_HOR - 0.06), D.rot_euler(rx=90)))
    D.box(bm, (-1.02, Y_LAND, Z_HOR), (-0.58, Y_SUN, Z_HOR + 0.42))
    D.new_obj("ScreenLand", bm, c, land, rbx_material="Neon", emit=0.85)

    # Sun disc high on the RIGHT of the view (-x) plus the horizon glow strip under it.
    bm = bmesh.new()
    D.cyl(bm, (-1.30, Y_SUN, Z_HOR + 1.06), (-1.30, Y_LIT, Z_HOR + 1.06), 0.40, segs=10)
    D.box(bm, (-X_A, Y_SUN, Z_HOR), (0.20, Y_LIT - 0.002, Z_HOR + 0.10))
    D.new_obj("ScreenSun", bm, c, sun, rbx_material="Neon", emit=0.95)

    # ============================================================ soundbar + remote
    # Flat, and pushed out to the front lip: it has to stay clear of the stand behind it.
    bm = bmesh.new()
    D.beveled_box(bm, (-2.00, 0.54, Z_TOP), (2.00, 0.88, Z_BAR), bevel=0.05)
    D.new_obj("Soundbar", bm, c, bright, rbx_material="Metal", metallic=0.55, roughness=0.42)

    # Everything small and black: the soundbar grille, then the remote's three dark keys.
    bm = bmesh.new()
    D.slat_run(bm, (-1.80, 0.88, Z_TOP + 0.035), (1.80, 0.915, Z_BAR - 0.035), 8,
               gap_frac=0.42, axis='x', bevel=0.0)
    for (lx, ly) in ((0.00, 0.12), (-0.10, -0.06), (0.10, -0.06)):
        bx, by = _rp(lx, ly)
        D.cyl(bm, (bx, by, Z_TOP + 0.125), (bx, by, Z_TOP + 0.175), 0.055, segs=4)
    D.new_obj("BlackTrim", bm, c, black, rbx_material="SmoothPlastic", roughness=0.55)

    # The remote itself: a chamfered slab dropped on the top at a lazy angle.
    bm = bmesh.new()
    D.beveled_box(bm, (REMOTE[0] - 0.21, REMOTE[1] - 0.47, Z_TOP),
                  (REMOTE[0] + 0.21, REMOTE[1] + 0.47, Z_TOP + 0.14), bevel=0.05,
                  rot=D.rot_euler(rz=REMOTE_YAW))
    D.new_obj("Remote", bm, c, pale, **SHELL)

    # Stand-by dot under the bezel (viewer's right) and the remote's power key.
    bm = bmesh.new()
    D.cyl(bm, (-1.75, Y_BEZ, Z_P0 + 0.13), (-1.75, Y_BEZ + 0.035, Z_P0 + 0.13), 0.075, segs=5)
    px, py = _rp(0.0, 0.36)
    D.cyl(bm, (px, py, Z_TOP + 0.125), (px, py, Z_TOP + 0.18), 0.060, segs=5)
    D.new_obj("RedLights", bm, c, red, rbx_material="Neon", emit=1.1)

    return c
