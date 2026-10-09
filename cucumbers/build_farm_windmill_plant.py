"""Farm: Windmill Plant - a green cucumber stalk whose flower is a four-blade pinwheel."""
import bmesh, math

COLLECTION = "FarmWindmillPlant"
NOTES = ("A cucumber PLANT whose flower is a pinwheel - not a timber windmill tower.  "
         "One slim upright cucumber stalk (h 3.6, r 0.52, no nub) in cuke_green with 14 "
         "cuke_stud speckles stands on the ground, and three cuke_green leaves splay out "
         "low and nearly horizontal at its foot: one to each side and one toward the "
         "camera.  Where the stem nub would be, a four-blade pinwheel flower stands in "
         "the XZ plane facing +Y, hub at (0, 0.67, 4.3): four pale cuke_pale rounded "
         "squares 1.05 across arranged in a + (up, down, screen-left, screen-right), "
         "their inner edges 0.30 from the hub centre, each backed by a cuke_green border "
         "standing 0.10 proud on every side so the blades read outlined, and each "
         "carrying one cuke_stud square in the middle.  The hub is wood - a farm_bark "
         "cylinder of radius 0.34 lying along Y, with a smaller farm_wood disc on its "
         "front face - and it hides the four blade roots.  The whole fan sits on the +Y "
         "side of the stalk (blade plane y 0.62-0.84, borders 0.52-0.68) so the lower "
         "blade sweeps clear in front of the stalk head.  The five fan parts are "
         "authored in \"Plastic\" and the plant in \"SmoothPlastic\", so the spinning "
         "group (Blades, BladeBorders, BladeStuds, Hub, HubCap) stays separable from the "
         "plant even where it shares a colour with it.  Faces +Y; the stalk is centred "
         "on x = 0, y = 0 (the fan puts a little mass forward of y = 0); nothing below "
         "z = 0.  About 2.9 x 1.7 x 5.8 studs.  Eight parts: Stalk, Studs, Leaves, "
         "BladeBorders, Blades, BladeStuds, Hub, HubCap.  Spin the flower about the Y "
         "axis through FanHub.")

PIVOTS = {"FanHub": (0.0, 0.67, 4.30)}
STATES = {"Spin": 90.0}

# ---------------------------------------------------------------- the stalk
STALK_H, STALK_R = 3.60, 0.52
STUD_ROWS, STUD_PER_ROW = 7, 2
STUD_Z0, STUD_Z1 = 0.10, 0.78        # stop below the pinwheel so every speckle shows

# leaves at the foot: (root, yaw_deg, pitch_deg, length, width)
LEAVES = ((( 0.34,  0.00, 0.34), -90.0, 14.0, 1.12, 0.50),   # +x  = screen-LEFT
          ((-0.34,  0.02, 0.32),  90.0, 12.0, 1.06, 0.48),   # -x  = screen-right
          (( 0.02,  0.30, 0.30),   0.0, 26.0, 0.96, 0.46))   # forward, toward the camera

# ---------------------------------------------------------------- the pinwheel
FAN_Z = 4.30                         # hub centre, just above the stalk head (3.60)
FAN_Y = 0.73                         # blade plane, proud of the stalk's +Y skin (0.48)
BLADE_S = 1.05                       # rounded square blade, side
BLADE_CR = 0.30                      # ... and its corner radius
BLADE_IN = 0.30                      # inner edge, measured out from the hub centre
BLADE_T = 0.22                       # blade thickness (runs along Y)
BLADE_C = BLADE_IN + BLADE_S / 2.0   # blade centre out along its own arm = 0.825
BORDER_P = 0.10                      # how far the green border stands proud, every side
BORDER_T = 0.16
BORDER_BITE = 0.06                   # how far the border creeps into the blade's back
BLADE_STUD = 0.34                    # the cuke_stud square inset in each blade

HUB_R = 0.34                         # wooden hub, axis along Y, covers the blade roots
HUB_Y0, HUB_Y1 = 0.42, 0.92
CAP_R, CAP_T = 0.21, 0.09            # the paler disc on the hub's front face


def blade_matrix(D, i):
    """Swing one blade round the hub axis (+Y).

    The blade is built flat in local XY pointing along local +Y, thickness along local
    +Z.  rot_euler(-90, i*90, 0) stands that plane up into world XZ with the thickness
    along +Y (toward the camera), then spins it a quarter turn at a time:
    i = 0 down, 1 screen-right (-x), 2 up, 3 screen-left (+x)."""
    return D.place((0.0, FAN_Y, FAN_Z), D.rot_euler(-90.0, i * 90.0, 0.0))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- the cucumber stalk ------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=STALK_H, r=STALK_R, nub=None)
    D.new_obj("Stalk", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=STALK_H, r=STALK_R, rows=STUD_ROWS, per_row=STUD_PER_ROW,
                 z0=STUD_Z0, z1=STUD_Z1, size=0.24, rise=0.05, seed=5)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- three leaves splaying out at the foot ------------------------------
    bm = bmesh.new()
    for loc, yaw, pitch, length, width in LEAVES:
        D.leaf_blade(bm, length=length, width=width, thick=0.09, ridge=0.06,
                     matrix=D.place(loc, D.rot_euler(pitch, 0.0, yaw)))
    D.new_obj("Leaves", bm, c, D.C("cuke_green"), rbx_material="LeafyGrass")

    # ---- the four-blade pinwheel flower -------------------------------------
    blade_pts = D.rounded_rect_pts(BLADE_S, BLADE_S, BLADE_CR, segs=3,
                                   center=(0.0, BLADE_C))
    border_pts = D.rounded_rect_pts(BLADE_S + 2.0 * BORDER_P, BLADE_S + 2.0 * BORDER_P,
                                    BLADE_CR + BORDER_P, segs=3, center=(0.0, BLADE_C))
    bz0, bz1 = -BLADE_T / 2.0, BLADE_T / 2.0
    oz1 = bz0 + BORDER_BITE                      # border sits just BEHIND the blade face
    oz0 = oz1 - BORDER_T

    bm_blade, bm_border, bm_stud = bmesh.new(), bmesh.new(), bmesh.new()
    for i in range(4):
        m = blade_matrix(D, i)
        D.prism(bm_border, border_pts, oz0, oz1, matrix=m)
        D.prism(bm_blade, blade_pts, bz0, bz1, matrix=m)
        vs = D.stud_patch(bm_stud, (0.0, BLADE_C, bz1), (0.0, 0.0, 1.0),
                          size=BLADE_STUD, rise=0.05, bevel=0.035)
        D.xform(bm_stud, vs, m)
    D.new_obj("BladeBorders", bm_border, c, D.C("cuke_green"), rbx_material="Plastic")
    D.new_obj("Blades", bm_blade, c, D.C("cuke_pale"), rbx_material="Plastic")
    D.new_obj("BladeStuds", bm_stud, c, D.C("cuke_stud"), rbx_material="Plastic")

    # ---- the wooden hub ------------------------------------------------------
    bm = bmesh.new()
    D.cyl(bm, (0.0, HUB_Y0, FAN_Z), (0.0, HUB_Y1, FAN_Z), HUB_R, segs=10)
    D.new_obj("Hub", bm, c, D.C("farm_bark"), rbx_material="Wood")

    bm = bmesh.new()
    D.cyl(bm, (0.0, HUB_Y1 - 0.03, FAN_Z), (0.0, HUB_Y1 + CAP_T, FAN_Z), CAP_R, segs=10)
    D.new_obj("HubCap", bm, c, D.C("farm_wood"), rbx_material="Wood")

    return c
