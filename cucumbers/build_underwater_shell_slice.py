"""Underwater: Shell Slice - an open clam, one ribbed valve lying open, one standing."""
import bmesh, math

COLLECTION = "UnderwaterShellSlice"
NOTES = (
    "An open clam shell, built to read like a cut slice.  The lower valve lies on the "
    "ground tilted back 20 deg, hinged at the BACK (-y) through a dark umbo block, and "
    "shows its cream pearl lining with five pearl pips (the 'slice' read); the upper "
    "valve stands up behind it, opened past the vertical, so the camera sees its ribbed "
    "outside.  Each valve is a 160-degree fan with seven sea_shell_dk ribs radiating "
    "from the hinge, 0.10 studs proud of the shell.  About 2.8 x 2.2 x 2.0 studs, "
    "centred on x=0 / y=0, facing +Y, nothing below z=0.  5 parts: Shells, Ribs (the "
    "14 ribs plus the hinge block), Lining, Pips, Speckles."
)

# the hinge line runs along X at the back; a game could swing the upper valve on it
PIVOTS = {"Hinge": (0.0, -0.57, 0.70)}
STATES = {"Open": 100.0, "Shut": -20.0}        # upper-valve elevation, degrees above +Y

FAN_A0, FAN_A1, FAN_N = -80.0, 80.0, 9
RIB_ANGLES = (-72.0, -48.0, -24.0, 0.0, 24.0, 48.0, 72.0)
RIB_PROUD, RIB_SINK = 0.10, 0.03

# hinge point, elevation of the fan above +Y, fan depth, fan half-width, plate thickness
LOWER = dict(hinge=(0.0, -0.52, 0.70), elev=-20.0, depth=1.70, half=1.42, thick=0.26,
             rib_w=0.22, rib_r0=0.46)
UPPER = dict(hinge=(0.0, -0.62, 0.70), elev=100.0, depth=1.32, half=1.36, thick=0.26,
             rib_w=0.20, rib_r0=0.40)

# lining fan (inside the lower valve): depth, half-width, arc span, hinge-edge x/y
LINING = (1.46, 1.18, -74.0, 74.0, 0.40, 0.13)
# five pips on the lining - four in a ring plus one in the middle
PIP_CENTRE, PIP_RING = (0.84, 0.0), 0.46
# speckles on the lower valve's exposed rim margin: (fan angle, inset from the rim)
RIM_SPOTS = ((0.0, 0.13), (40.0, 0.13), (-40.0, 0.13), (68.0, 0.13), (-68.0, 0.13))
# speckles between the ribs on the upper valve's outside: (fan angle, fraction of reach)
BACK_SPOTS = ((13.0, 0.86), (-13.0, 0.68), (36.0, 0.74), (-36.0, 0.90), (60.0, 0.70),
              (-60.0, 0.84))


def _fan_pts(D, depth, half, a0=FAN_A0, a1=FAN_A1, hx=0.03, hy=0.15, n=FAN_N):
    """The valve outline: an arc closed back to a short flat hinge edge at the origin."""
    return list(D.arc_pts((0.0, 0.0), depth, a0, a1, n=n, ry=half)) + [(hx, hy), (hx, -hy)]


def _ray(depth, half, a_deg):
    """Unit direction, reach and heading (deg) of the fan outline at fan angle `a_deg`."""
    a = math.radians(a_deg)
    px, py = depth * math.cos(a), half * math.sin(a)
    r = math.hypot(px, py) or 1e-6
    return px / r, py / r, r, math.degrees(math.atan2(py, px))


def _valve_m(D, v):
    """Place a valve: the fan is built opening along local +X, lining in local XY, its
    inside on local +Z.  rz=90 swings the fan round to +Y, ry tilts it about the hinge."""
    return D.place(v["hinge"], D.rot_euler(0.0, -v["elev"], 90.0))


def _patch(D, bm, m, point, normal, size, rise=0.05):
    """One raised square speckle built in a valve's local frame, then placed with it."""
    vs = D.stud_patch(bm, point, normal, size=size, rise=rise, bevel=0.03)
    D.xform(bm, vs, m)
    return vs


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    valves = (LOWER, UPPER)
    mats = [_valve_m(D, v) for v in valves]

    # ------------------------------------------------------------ the two halves
    bm = bmesh.new()
    for v, m in zip(valves, mats):
        D.prism(bm, _fan_pts(D, v["depth"], v["half"]), 0.0, v["thick"], matrix=m)
    D.new_obj("Shells", bm, c, D.C("sea_shell"), rbx_material="SmoothPlastic",
              roughness=0.32)

    # --------------------------------------- seven ribs a half, plus the umbo block
    bm = bmesh.new()
    for v, m in zip(valves, mats):
        for a in RIB_ANGLES:
            ux, uy, reach, head = _ray(v["depth"], v["half"], a)
            r0, r1 = v["rib_r0"], reach * 0.985
            length, mid = r1 - r0, (r0 + r1) / 2.0
            w = v["rib_w"] / 2.0
            vs = D.beveled_box(bm, (-length / 2.0, -w, -RIB_PROUD),
                               (length / 2.0, w, RIB_SINK), bevel=0.04,
                               rot=D.rot_euler(0.0, 0.0, head))
            D.xform(bm, vs, m @ D.place((ux * mid, uy * mid, 0.0)))
    D.beveled_box(bm, (-0.30, -0.98, 0.44), (0.30, -0.40, 0.88), bevel=0.09)
    D.new_obj("Ribs", bm, c, D.C("sea_shell_dk"), rbx_material="SmoothPlastic",
              roughness=0.32)

    # ------------------------------------- the pearly lining inside the lower valve
    low, lm = LOWER, mats[0]
    ldepth, lhalf, la0, la1, lhx, lhy = LINING
    bm = bmesh.new()
    D.prism(bm, _fan_pts(D, ldepth, lhalf, a0=la0, a1=la1, hx=lhx, hy=lhy),
            low["thick"] - 0.02, low["thick"] + 0.04, matrix=lm)
    D.new_obj("Lining", bm, c, D.C("sea_shell_in"), rbx_material="Marble", roughness=0.32)

    # ------------------------------------------------- five pips on that cut face
    bm = bmesh.new()
    z_face = low["thick"] + 0.04
    spots = [PIP_CENTRE]
    for i in range(4):
        a = math.radians(45.0 + 90.0 * i)
        spots.append((PIP_CENTRE[0] + math.cos(a) * PIP_RING,
                      PIP_CENTRE[1] + math.sin(a) * PIP_RING))
    for x, y in spots:
        _patch(D, bm, lm, (x, y, z_face), (0.0, 0.0, 1.0), 0.20, rise=0.05)
    D.new_obj("Pips", bm, c, D.C("sea_pearl"), rbx_material="SmoothPlastic",
              roughness=0.32)

    # -------------------------------- speckles: the lower rim, and between the ribs
    bm = bmesh.new()
    for a, inset in RIM_SPOTS:
        ux, uy, reach, _h = _ray(low["depth"], low["half"], a)
        r = reach - inset
        _patch(D, bm, lm, (ux * r, uy * r, low["thick"]), (0.0, 0.0, 1.0), 0.17)
    up, um = UPPER, mats[1]
    for a, frac in BACK_SPOTS:
        ux, uy, reach, _h = _ray(up["depth"], up["half"], a)
        r = reach * frac
        _patch(D, bm, um, (ux * r, uy * r, 0.0), (0.0, 0.0, -1.0), 0.17)
    D.new_obj("Speckles", bm, c, D.C("sea_bubble_lt"), rbx_material="SmoothPlastic",
              roughness=0.32)

    return c
