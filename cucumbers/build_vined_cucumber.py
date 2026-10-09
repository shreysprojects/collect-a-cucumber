"""Grass: Vined Cucumber - a vine spirals up the body and curls into a tendril."""
import bmesh, math

COLLECTION = "VinedCucumber"
NOTES = ("The standard 4.0-tall cucumber with a dull-green vine spiralling 1.9 turns up "
         "its skin.  At the top the vine lifts off the shoulder, hooks over the head and "
         "curls into a bright 1.4-turn tendril coil standing in the XZ plane beside the "
         "stem nub (screen-right, negative x), reaching z 4.7.  Two dark leaves sit on "
         "short petioles off the vine: one at mid height pointing up and screen-LEFT "
         "(+x), one lower pointing screen-RIGHT (-x) and slightly toward the camera.  "
         "Footprint about 2.4 x 1.6 studs, 4.7 tall, centred on x=0 y=0, facing +Y.  "
         "Five parts: Body, Studs, Vine (spiral band + hook + petioles), Tendril, Leaves.")

H, R = 4.0, 0.68                      # D.CUKE_H / D.CUKE_R, restated for the tables below

# ---- the vine wrap (exactly the brief's numbers) -------------------------------
V_Z0, V_Z1, V_TURNS = 0.10, 0.88, 1.9
V_PHASE, V_WIDTH, V_THICK, V_OFFSET = -30.0, 0.34, 0.15, 0.05
V_N = 34

# ---- the tendril coil ----------------------------------------------------------
# phase 96 deg puts the coil's OUTER end at its lower-right, so the vine can hook up
# into it from the head and the curl then winds inward to a tight tip.
T_CENTRE = (-0.55, -0.10, 4.35)
T_R0, T_R1, T_TURNS, T_N, T_PHASE = 0.06, 0.34, 1.4, 14, 96.0
T_RAD0, T_RAD1 = 0.10, 0.05

# ---- leaves: (height fraction on the vine, azimuth deg, elevation deg, length, width)
# azimuth 0 = +x = SCREEN-LEFT, 90 = +Y = toward the camera.
LEAVES = [
    (0.56, 35.0, 55.0, 0.72, 0.54),     # mid height, up and screen-left
    (0.34, 225.0, 28.0, 0.70, 0.50),    # lower, out to screen-right and forward
]
PETIOLE = 0.18                          # stub of vine between skin and leaf base


def _vine_angle(zf):
    """The wrap's angle (degrees) where it crosses height fraction `zf`."""
    return V_PHASE + 360.0 * V_TURNS * (zf - V_Z0) / (V_Z1 - V_Z0)


def _dir(az_deg, el_deg):
    """Unit vector at azimuth `az` round Z, `el` above horizontal."""
    a, e = math.radians(az_deg), math.radians(el_deg)
    return (math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    h, r = D.CUKE_H, D.CUKE_R

    # ---- body ------------------------------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=h, r=r, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the signature speckles ------------------------------------------
    bm = bmesh.new()
    D.cuke_studs(bm, h=h, r=r, rows=7, per_row=3, z0=0.11, z1=0.90,
                 size=0.28, rise=0.055, seed=11)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the tendril coil (built first: the vine hook has to land on it) --
    coil = D.spiral_pts(center=T_CENTRE, r0=T_R0, r1=T_R1, turns=T_TURNS,
                        n=T_N, plane="XZ", phase_deg=T_PHASE)
    coil = list(coil)
    coil.reverse()                       # start wide where the vine arrives, curl inward
    n_c = len(coil)
    coil_rad = [T_RAD0 + (T_RAD1 - T_RAD0) * i / float(n_c - 1) for i in range(n_c)]

    bm = bmesh.new()
    D.tube(bm, coil, coil_rad, segs=6)
    D.new_obj("Tendril", bm, c, D.C("leaf_light"), rbx_material="Grass")

    # ---- the vine: spiral band + the hook over the head + two petioles ----
    bm = bmesh.new()
    D.wrap_ribbon(bm, h=h, r=r, z0=V_Z0, z1=V_Z1, turns=V_TURNS, width=V_WIDTH,
                  thick=V_THICK, n=V_N, phase_deg=V_PHASE, offset=V_OFFSET)

    frames = D.wrap_frames(h=h, r=r, z0=V_Z0, z1=V_Z1, turns=V_TURNS, n=V_N,
                           phase_deg=V_PHASE, offset=V_OFFSET)
    top = frames[-1][0]                  # where the band leaves the body, ~(0.26,-0.59,3.52)
    hook = [(top[0], top[1], top[2]),
            (0.350, -0.540, 3.780),      # up the shoulder
            (0.150, -0.520, 3.990),      # across the front of the head, clear of the nub
            (-0.290, -0.340, 4.020),     # over to the far side
            (-0.620, -0.190, 3.900),     # dips down, then hooks back up...
            (coil[0][0], coil[0][1], coil[0][2])]   # ...into the coil's outer end
    D.tube(bm, hook, [0.135, 0.128, 0.120, 0.113, 0.106, T_RAD0], segs=6)

    leaf_bases = []
    for (zf, az, el, ln, wd) in LEAVES:
        ang = _vine_angle(zf)
        foot = D.cuke_point(h=h, r=r, zf=zf, angle_deg=ang, offset=0.02)
        dx, dy, dz = _dir(az, el)
        mid = (foot[0] + dx * PETIOLE * 0.5, foot[1] + dy * PETIOLE * 0.5,
               foot[2] + dz * PETIOLE * 0.5)
        base = (foot[0] + dx * PETIOLE, foot[1] + dy * PETIOLE, foot[2] + dz * PETIOLE)
        D.tube(bm, [foot, mid, base], [0.080, 0.068, 0.056], segs=5)
        leaf_bases.append(base)
    D.new_obj("Vine", bm, c, D.C("stem_green"), rbx_material="Grass")

    # ---- the two leaves ---------------------------------------------------
    bm = bmesh.new()
    for (zf, az, el, ln, wd), base in zip(LEAVES, leaf_bases):
        m = D.place(base, D.rot_euler(el, 0.0, az - 90.0))
        D.leaf_blade(bm, length=ln, width=wd, thick=0.085, matrix=m, ridge=0.05)
    D.new_obj("Leaves", bm, c, D.C("leaf_dark"), rbx_material="LeafyGrass")

    return c
