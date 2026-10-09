"""23 Diamond Railgun -- two long crystal rails on a grey receiver: a precision weapon.

The player stands side-on on the pad (down-track = their LEFT, away from the pad camera); the
railgun is kept on the character's FRONT side (screen-right) so the camera sees the rails.
  Ready    LOW READY: both hands on it, stock by the right hip, muzzle angled down at the snow
           ahead, very still -- one slow visible breath (chest rises, muzzle dips, weight shifts),
           the eyes drifting down-track at the end of each breath.
  ChargeLo SNIPER: shouldered, head down on the stock, eye along the rails, aimed down the track
           from a lowered stance; one calm breath per loop and a slow figure-8 float of the aim.
  ChargeHi the same aim from a half kneel (pelvis back over the rear right foot, right knee sunk),
           breath held: a fast fine tremor through the gun, the torso and the head.
  Fire     dead-still squeeze -> the ball needles out of the muzzle at FireAt -> a tiny, very fast
           snap recoil (rails flick up a few degrees, shoulder punched back, chest twisted back)
           -> 1-frame overshoot -> settle on target -> hold the aim a beat -> rise to low ready.
Ball: hidden until it leaves the muzzle; cyan spark burst, cyan spark crackle while charging.
"""
import importlib
import math
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)
from mathutils import Vector

LID = 23
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.4,
    "FireAt": 0.133,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "spark", "Color": [150, 240, 255], "Charge": "spark", "ChargeColor": [150, 240, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "diamond railgun: still low ready, shouldered sniper aim down the rails (half-kneel + tremor at full charge), needle-fast tiny snap recoil",
}
FEET = {"Left": (-0.95, -0.3), "Right": (0.65, 0.45)}
META = L.load_meta(LID)
G2 = list(META["Grip2"]["pos"])
report = {}
GT = None
_prev = {}

# ------------------------------------------------------------------ one pose = one param dict
BASE = dict(yaw=35.0, lean=-10.0, tilt=0.0, drop=0.3, back=-0.2, side=0.0, wyaw=10.0, wbend=-5.0, wtilt=8.0,
            gx=0.25, gy=-0.25, gz=-1.45, gyaw=0.0, gelev=2.0, groll=0.0,
            rex=0.6, rey=-0.6, rez=0.3, lex=0.3, ley=1.0, lez=0.3,
            hx=-14.0, hy=1.0, hz=-1.4, hroll=0.0)


def P(**kw):
    d = dict(BASE)
    d.update(kw)
    return d


def root_of(p):
    return L.ry(p["yaw"]) @ L.rx(p["lean"]) @ L.rz(p["tilt"])


def apply(p):
    L.reset_pose()
    L.stance(hip_drop=p["drop"], hip_back=p["back"], hip_side=p["side"], root=root_of(p), feet=FEET)
    L.waist(L.ry(p["wyaw"]) @ L.rx(p["wbend"]) @ L.rz(p["wtilt"]))
    info = L.hold((p["gx"], p["gy"], p["gz"]), yaw=p["gyaw"], elev=p["gelev"], roll=p["groll"], anchor="Pivot",
                  elbow_away=(p["rex"], p["rey"], p["rez"]), grip_twist=GT)
    info["left"] = L.left_hand_to(point=L.launcher_point(G2), elbow_away=(p["lex"], p["ley"], p["lez"]))
    L.head_look(target=(p["hx"], p["hy"], p["hz"]))
    if p["hroll"]:
        L.set_rot("Head", L.get_rot("Head") @ L.rz(p["hroll"]))
        L.update()
    return info


def mix(a, b, t):
    return {k: a[k] + (b[k] - a[k]) * t for k in a}


def K(f):
    """key with every quaternion kept in the previous key's hemisphere (no long-way flips)"""
    for pb in L.rig().pose.bones:
        q = pb.rotation_quaternion.copy()
        pr = _prev.get(pb.name)
        if pr is not None and q.dot(pr) < 0.0:
            q = -q
            pb.rotation_quaternion = q
        _prev[pb.name] = q
    L.key(f)


def new_clip(kind):
    _prev.clear()
    L.new_clip(kind)


def gap():
    return round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 3)


def wrist():
    return round(math.degrees(L.swing_twist(L.get_rot("RightHand"))[0].angle), 1)


DIAG = bool(os.environ.get("LA23_DIAG"))
_VERTS = None


def pose_audit():
    """the report's motion audit for the CURRENT pose (all launcher verts): arm / launcher depth
    inside the torso / head"""
    global _VERTS
    L.update()
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    wa, aat = 0.0, ""
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for body in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[body])
                        if d > wa:
                            wa, aat = d, "%s/%s" % (arm, body)
    lob = L.launcher_object()
    if _VERTS is None:
        _VERTS = [v.co.copy() for v in lob.data.vertices]
    mw = lob.matrix_world
    wl, lat = 0.0, ""
    for co in _VERTS:
        pt = L.b2r(mw @ co)
        for body in ("UpperTorso", "Head"):
            d = L._depth_inside(pt, *boxes[body])
            if d > wl:
                wl, lat = d, body
    return round(wa, 2), aat, round(wl, 2), lat


def guard_state(side, pole):
    """x of the IK hinge normal in the torso frame (< -0.15 = the library's elbow guard mirrors it)"""
    Mi = L.frame_of("UpperTorso").inverted()
    t = (Mi @ (L.joint(side + "Hand") - L.joint(side + "UpperArm"))).normalized()
    n = t.cross(Mi @ Vector(pole))
    return round(n.normalized().x, 2) if n.length > 1e-4 else 0.0


def diag(name, p):
    info = apply(p)
    print("REPORT diag %-8s wrist %5.1f reach %.3f gap %.3f guardR %5.2f guardL %5.2f audit %s head %s" % (
        name, wrist(), info["arm_overreach"], gap(), guard_state("Right", (p["rex"], p["rey"], p["rez"])),
        guard_state("Left", (p["lex"], p["ley"], p["lez"])), pose_audit(),
        [round(v, 2) for v in L.joint("Head")]))
    hc = [b for n, b, h in L.body_boxes() if n == "Head"][0].translation
    pi = L.pivot_cf().inverted()
    sh = L.joint("RightUpperArm")
    print("REPORT    head in gun (studs, x side / y back / z down) %s  shoulderR in gun %s  grip %s" % (
        [round(v, 2) for v in pi @ hc], [round(v, 2) for v in pi @ sh], [round(p[k], 2) for k in GKEYS]))


# ------------------------------------------------------------------ poses
AIM = dict(yaw=32.46, lean=-4.08, wyaw=-14.16, wbend=-7.99, gx=-0.63, gy=-0.27, gz=-1.7, hroll=-7.63,
           rex=-0.4, rey=1.0, rez=0.2, deep=0.7)


def aim_raw(depth):
    """depth 0 = ChargeLo sniper, 1 = ChargeHi half kneel (pelvis back over the rear right foot).
    Only the depth-0.5 grip (the reference) matters: every aim carries the arm + gun rigidly
    with the right shoulder from there (see track)"""
    A = AIM
    # the crouch only bends about the shoulder line (lean / wbend) so the left hand keeps its reach
    return P(yaw=A["yaw"], lean=A["lean"] - 6.0 * depth, tilt=0.0,
             drop=0.35 + A["deep"] * depth, back=-0.2 + 0.3 * depth, side=0.1 * depth,
             wyaw=A["wyaw"], wbend=A["wbend"] - 3.0 * depth, wtilt=-5.0,
             gx=A["gx"], gy=A["gy"] - 0.5 * A["deep"] * (depth - 0.5), gz=A["gz"],
             gyaw=0.0, gelev=2.0, rex=A["rex"], rey=A["rey"], rez=A["rez"],
             hx=-14.0, hy=0.9 - A["deep"] * depth, hz=A["gz"] - 0.3, hroll=A["hroll"])


REF = None      # (S_a, P_a, E_a, R_a^T) of the straight-wrist reference aim, set below
GKEYS = ("gx", "gy", "gz", "rex", "rey", "rez")


def aim(depth, b=0.0, drift=(0.0, 0.0), tr=(0.0,) * 6):
    """b = breath -1..1 (scaled down at full charge: breath held); drift = (yaw, elev) degrees of
    the slow figure-8 float (scaled down at full charge); tr = tremor components -1..1
    (gun y, gun z, elev, yaw, torso, head), scaled up by depth"""
    r = aim_raw(depth)
    br = b * (1.0 - 0.6 * depth)
    calm = 1.0 - 0.6 * depth
    dy, de = drift[0] * calm, drift[1] * calm
    ty, tz, te, tyw, tt, th = tr
    # the tremor runs through the whole body (the shouldered gun rides it): gun y/z via the pelvis,
    # plus a torso shiver of its own
    r["drop"] += 0.035 * br + 0.04 * depth * ty
    r["back"] += 0.04 * depth * tz
    r["wbend"] += 0.8 * depth * tt
    r["wtilt"] += 0.6 * depth * th
    r["lean"] += 0.5 * br
    r["wbend"] += 1.8 * br
    e_off = 0.9 * br + de + 1.25 * depth * te
    y_off = dy + 0.75 * depth * tyw
    r["gelev"] += e_off
    r["gyaw"] += y_off
    # the eye stays on the rails: the head target follows the aim float (14 studs out)
    r["hz"] -= 14.0 * math.tan(math.radians(y_off))
    r["hy"] += 14.0 * math.tan(math.radians(e_off)) - 0.03 * br + 0.35 * depth * th
    if REF is not None:
        r = track(r)                                # the gun rides the shoulder: wrist stays straight
    return r


def ready(ph=0.0):
    """low ready: muzzle down at the snow ahead; ph = loop phase 0..1 (one breath)"""
    b = -math.cos(2.0 * math.pi * ph)                # -1 = exhaled (start), +1 = chest up
    s = math.sin(2.0 * math.pi * ph)                 # weight shift
    lead = (0.5 + 0.5 * math.cos(2.0 * math.pi * (ph - 0.9))) ** 2   # eyes drift down-track late in the breath
    return P(yaw=-4.0 + 1.5 * s, lean=-5.0 + 1.0 * b, drop=0.12 - 0.035 * b, back=0.0, side=0.07 * s,
             wyaw=-12.0 + 1.0 * s, wbend=-6.0 + 2.5 * b, wtilt=2.0 - 1.0 * s,
             gx=0.35, gy=-0.85 + 0.03 * b, gz=-1.3, gyaw=45.0, gelev=-38.0 - 2.0 * b, groll=0.0,
             rex=0.6, rey=-1.0, rez=0.3, lex=0.4, ley=1.0, lez=0.1,
             hx=-7.0 - 1.0 * lead, hy=-2.0 + 0.3 * b, hz=-3.2 + 1.2 * lead, hroll=0.0)


# the grip: seat the railgun in the SNIPER aim with a straight wrist (the gun turns in the fist
# once to fit), then keep that grip fixed in every clip -- nothing slides in the hand
GT = None
_p = aim_raw(0.5)
L.reset_pose()
L.stance(hip_drop=_p["drop"], hip_back=_p["back"], hip_side=_p["side"], root=root_of(_p), feet=FEET)
L.waist(L.ry(_p["wyaw"]) @ L.rx(_p["wbend"]) @ L.rz(_p["wtilt"]))
L.hold((_p["gx"], _p["gy"], _p["gz"]), yaw=_p["gyaw"], elev=_p["gelev"], roll=_p["groll"], anchor="Pivot",
       elbow_away=(_p["rex"], _p["rey"], _p["rez"]), max_wrist=12.0, max_twist=60.0)
GT = L.get_rot("Launcher").copy()

ARM_PARTS = ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand")


def gun_rot(p):
    fwd = L.direction(p["gyaw"], p["gelev"])
    return L.look_frame(fwd, L.up_for(fwd, p["groll"]))


def body_only(p):
    L.reset_pose()
    L.stance(hip_drop=p["drop"], hip_back=p["back"], hip_side=p["side"], root=root_of(p), feet=FEET)
    L.waist(L.ry(p["wyaw"]) @ L.rx(p["wbend"]) @ L.rz(p["wtilt"]))


def rigid_from(p_src, p_dst, name=None):
    """p_dst's body + gun direction, with the right arm + gun turned RIGIDLY about the shoulder
    from p_src (the IK is rotation-equivariant) -> the wrist keeps p_src's straight bend"""
    apply(p_src)
    S_a = L.joint("RightUpperArm")
    P_a = Vector((p_src["gx"], p_src["gy"], p_src["gz"]))
    body_only(p_dst)
    S_r = L.joint("RightUpperArm")
    Q = gun_rot(p_dst) @ gun_rot(p_src).transposed()
    g = S_r + Q @ (P_a - S_a)
    e = Q @ Vector((p_src["rex"], p_src["rey"], p_src["rez"]))
    q = dict(p_dst, gx=g.x, gy=g.y, gz=g.z, rex=e.x, rey=e.y, rez=e.z)
    if name:
        info = apply(q)
        print("REPORT rigid %s swing %.1f reach %.3f gap %.3f grip %s" % (
            name, wrist(), info["arm_overreach"], gap(), [round(v, 2) for v in g]))
    return q


def track(p):
    """p's body + gun direction; the right arm + gun carried rigidly with the shoulder from the
    straight-wrist reference aim (IK is rotation-equivariant -> the wrist keeps its bend)"""
    S_a, P_a, E_a, R_aT = REF
    body_only(p)
    S_r = L.joint("RightUpperArm")
    Q = gun_rot(p) @ R_aT
    g = S_r + Q @ (P_a - S_a)
    e = Q @ E_a
    return dict(p, gx=g.x, gy=g.y, gz=g.z, rex=e.x, rey=e.y, rez=e.z)


def setup_ref(pr):
    """grip (GT) = straight wrist in the reference aim pr; REF = that aim for the rigid carry"""
    global GT, REF
    GT, REF = None, None
    body_only(pr)
    L.hold((pr["gx"], pr["gy"], pr["gz"]), yaw=pr["gyaw"], elev=pr["gelev"], roll=pr["groll"], anchor="Pivot",
           elbow_away=(pr["rex"], pr["rey"], pr["rez"]), max_wrist=12.0, max_twist=60.0, iterations=12)
    GT = L.get_rot("Launcher").copy()
    apply(pr)
    REF = (L.joint("RightUpperArm").copy(), Vector((pr["gx"], pr["gy"], pr["gz"])),
           Vector((pr["rex"], pr["rey"], pr["rez"])), gun_rot(pr).transposed())


def butt_gap():
    """butt plate centre -> right shoulder joint (studs)"""
    return round((L.launcher_point((0.0, 1.0, -0.5)) - L.joint("RightUpperArm")).length, 2)


if DIAG and os.environ.get("LA23_SEARCH"):
    import random
    random.seed(int(os.environ.get("LA23_SEED", "1")))
    RANGES = dict(yaw=(0.0, 50.0), lean=(-24.0, -4.0), wyaw=(-25.0, 20.0), wbend=(-30.0, -4.0),
                  gx=(-1.8, 0.6), gy=(-0.9, 0.3), gz=(-2.6, -1.2), hroll=(-16.0, 16.0),
                  g2y=(-1.05, -0.4), g2z=(-0.5, -0.35))
    _A0 = dict(AIM)
    _res = []
    STARTS = [dict(yaw=36.4, lean=-20.41, wyaw=-14.85, wbend=-13.2, gx=-0.99, gy=-0.5, gz=-2.13, hroll=16.0, g2y=-0.4, g2z=-0.48),
              dict(yaw=28.91, lean=-4.93, wyaw=-18.97, wbend=-5.68, gx=0.08, gy=-0.06, gz=-1.79, hroll=15.36, g2y=-0.56, g2z=-0.35),
              dict(yaw=27.4, lean=-5.34, wyaw=-12.58, wbend=-11.22, gx=-0.61, gy=-0.29, gz=-1.79, hroll=-1.95, g2y=-0.73, g2z=-0.5)]
    NS = len(STARTS)
    _best = [None] * NS
    STEP = dict(yaw=5.0, lean=3.0, wyaw=5.0, wbend=3.0, gx=0.15, gy=0.1, gz=0.12, hroll=4.0, g2y=0.08, g2z=0.04)
    NIT = int(os.environ.get("LA23_N", "300"))
    for _it in range(NIT):
        _k = _it % NS
        if _best[_k] is None:
            _s = dict(STARTS[_k])
        else:
            sc = max(0.2, 1.0 - _it / float(NIT))
            _s = {}
            for k in RANGES:
                v = _best[_k][1][k] + random.gauss(0.0, STEP[k] * sc) * (random.random() < 0.45)
                _s[k] = min(RANGES[k][1], max(RANGES[k][0], v))
        AIM.update(_A0)
        AIM.update({k: v for k, v in _s.items() if not k.startswith("g2")})
        G2[1], G2[2] = _s["g2y"], _s["g2z"]
        setup_ref(aim_raw(0.5))
        _c, _o = 0.0, []
        for _d in (0.0, 1.0):
            _i = apply(aim(_d))
            eR = (L.joint("RightHand") - L.joint("RightUpperArm")).length
            eL = (L.joint("LeftHand") - L.joint("LeftUpperArm")).length
            a = pose_audit()
            g = gap()
            # cheek: the neck joint's sideways distance from the rail axis (eye on the rails)
            _pi = L.pivot_cf().inverted()
            hn = (_pi @ L.joint("Head")) / L.LAUNCHER_SCALE
            gl = L.guard_state if hasattr(L, "guard_state") else None
            _c += (8.0 * max(0.0, a[2] - 0.1) + 8.0 * max(0.0, a[0] - 0.14) + 8.0 * max(0.0, g - 0.08) + 0.5 * g
                   + 10.0 * max(0.0, eR - 1.43) + 10.0 * max(0.0, eL - 1.42) + wrist() / 60.0
                   + 1.5 * max(0.0, butt_gap() - 0.75) + 0.6 * max(0.0, abs(hn.x) - 0.55))
            _o.append("w%.0f eR%.2f eL%.2f g%.3f b%.2f hx%.2f %s" % (wrist(), eR, eL, g, butt_gap(), hn.x, a))
        _res.append((_c, {k: round(_s[k], 2) for k in RANGES}, _o))
        if _best[_k] is None or _c < _best[_k][0]:
            _best[_k] = (_c, dict(_s))
    _res.sort(key=lambda r: r[0])
    for r in _res[:10]:
        print("REPORT S %.3f %s | %s" % (r[0], r[1], " | ".join(r[2])))
    for b in _best:
        print("REPORT BEST %.3f %s" % (b[0], {k: round(v, 2) for k, v in b[1].items()}))
    sys.exit(0)

_ref = aim_raw(0.5)
apply(_ref)
REF = (L.joint("RightUpperArm").copy(), Vector((_ref["gx"], _ref["gy"], _ref["gz"])),
       Vector((_ref["rex"], _ref["rey"], _ref["rez"])), gun_rot(_ref).transposed())
for _d in (0.0, 1.0):
    _inf = apply(aim(_d))
    print("REPORT aim%.0f wrist %.1f reach %.3f gap %.3f ext %.3f/%.3f" % (_d, wrist(), _inf["arm_overreach"], gap(),
          (L.joint("RightHand") - L.joint("RightUpperArm")).length, L.UPPER_ARM + L.LOWER_ARM))
    print("REPORT knees%.0f" % _d, {b: [round(v, 2) for v in L.joint(b)] for b in (
        "LeftLowerLeg", "RightLowerLeg", "LeftUpperLeg", "RightUpperLeg", "LeftFoot", "RightFoot", "Head")})


# ------------------------------------------------------------------ Ready (very still: breath only)
RG_X = (0.5, 0.75, 1.0)
RG_Y = (-0.35, -0.6, -0.85)
RG_Z = (-0.6, -0.9, -1.2)
RG_E = (-38.0, -30.0)
RG_POLES = ((0.0, 1.0, 0.0), (0.3, 1.0, 0.3), (-0.3, 1.0, 0.1), (0.6, 1.0, 0.2), (0.3, 1.0, -0.4), (0.8, 0.5, 0.4))
_R0 = rigid_from(aim(0.0), ready(0.0))
# low ready: the grip low in front of the right hip, the stock BELOW the head (not up by the ear),
# an UP-ish elbow pole (the aim's pole family, so the Fire rise interpolates without a pole flip)
_best = None
for _gx in RG_X:
    for _gy in RG_Y:
        for _gz in RG_Z:
            for _ge in RG_E:
                for _e in RG_POLES:
                    _q = dict(_R0, gx=_gx, gy=_gy, gz=_gz, gelev=_ge, rex=_e[0], rey=_e[1], rez=_e[2])
                    _inf = apply(_q)
                    _sw = wrist()
                    _au = pose_audit()
                    _gs = guard_state("Right", _e)
                    _ext = (L.joint("RightHand") - L.joint("RightUpperArm")).length
                    _c = (_sw + 200.0 * _inf["arm_overreach"] + 100.0 * gap() + 400.0 * max(0.0, _au[0] - 0.1)
                          + 400.0 * max(0.0, _au[2] - 0.05) + 100.0 * max(0.0, -0.1 - _gs)
                          + 100.0 * max(0.0, _ext - 1.42) + 0.5 * abs(_ge + 36.0))
                    if _best is None or _c < _best[0]:
                        _best = (_c, _q, _au, _sw, _gs)
_R0 = _best[1]
print("REPORT ready search cost %.2f audit %s wrist %.1f guard %.2f grip %s elev %.1f" % (
    _best[0], _best[2], _best[3], _best[4], [round(_R0[k], 2) for k in GKEYS], _R0["gelev"]))
# share the wrist bend between the sniper aim and the low ready: the fixed grip is taken halfway
# between the straight-wrist grip of each (still ONE grip for every clip)
body_only(_R0)
L.hold((_R0["gx"], _R0["gy"], _R0["gz"]), yaw=_R0["gyaw"], elev=_R0["gelev"], roll=_R0["groll"], anchor="Pivot",
       elbow_away=(_R0["rex"], _R0["rey"], _R0["rez"]), max_wrist=12.0, max_twist=60.0)
_GR = L.get_rot("Launcher").copy()
if _GR.dot(GT) < 0.0:
    _GR = -_GR
GT = GT.slerp(_GR, 0.45)
_i = apply(_R0); print("REPORT ready base", [round(_R0[k], 2) for k in GKEYS], wrist(), _i, gap())
READY_D = {k: _R0[k] - ready(0.0)[k] for k in _R0}
_ready_raw = ready


def ready(ph=0.0):
    r = _ready_raw(ph)
    return {k: r[k] + READY_D[k] for k in r}


NC = int(round(SPEC["ChargeLo"] * 30))


def tremor(i, n):
    """six tremor channels, 6-10 whole cycles per loop (5-8.3 Hz at 1.2 s): the ends meet"""
    t = 2.0 * math.pi * i / n
    return (0.6 * math.sin(7 * t) + 0.4 * math.sin(10 * t + 1.0),
            0.6 * math.cos(9 * t) + 0.4 * math.sin(6 * t + 2.0),
            0.55 * math.sin(8 * t + 0.5) + 0.45 * math.cos(10 * t + 0.3),
            0.6 * math.sin(6 * t + 1.3) + 0.4 * math.cos(9 * t + 0.7),
            0.6 * math.sin(8 * t + 2.2) + 0.4 * math.sin(7 * t + 0.4),
            0.6 * math.cos(7 * t + 1.1) + 0.4 * math.sin(9 * t + 2.6))


def charge_pose(depth, f):
    ph = f / NC
    b = -math.cos(2.0 * math.pi * ph)                              # one calm breath per loop
    drift = (0.5 * math.sin(2.0 * math.pi * ph), 0.35 * math.sin(4.0 * math.pi * ph))   # figure-8 float
    return aim(depth, b, drift, tremor(f % NC, NC))


HI0 = charge_pose(1.0, 0)
HI = aim(1.0, -0.3)
SQZ = dict(HI, drop=HI["drop"] + 0.02)                                  # exhale, dead still
# the recoil is the SHOULDER punched back (the gun rides it, see track) + the rails flicking up;
# the gun itself slides back only a hair so the stock never drives into the cheek
# (the flick turns the gun about the shoulder, so the gun also drops a touch: the receiver stays under the eye;
#  the head jerks up with the shot)
KICK = track(dict(HI, gelev=HI["gelev"] + 5.0, back=HI["back"] + 0.1, lean=HI["lean"] + 3.0, wbend=HI["wbend"] + 2.5,
                  drop=HI["drop"] - 0.03, hy=HI["hy"] + 1.2))
KICK.update(gy=KICK["gy"] - 0.10)
SETTLE = dict(HI, gelev=HI["gelev"] - 0.4)
OVER = dict(HI, gelev=HI["gelev"] - 1.0, drop=HI["drop"] + 0.015)       # 1-frame overshoot below the aim
WATCH = dict(aim(0.7), hy=aim(0.7)["hy"] + 0.3)
READY0 = ready(0.0)
RISE_OFF = (0.12, 0.35)
RISE = track(mix(aim(0.2), READY0, 0.35))
RISE.update(gy=RISE["gy"] - RISE_OFF[0], gz=RISE["gz"] - RISE_OFF[1], hx=WATCH["hx"], hy=WATCH["hy"] - 0.6, hz=WATCH["hz"])  # eyes stay down-track          # lead with the gun low: the stock clears the head


def dip(p, f0, t):
    """the muzzle drops on the way to low ready: keep the stock low + away from the face"""
    if f0 < 21:
        return p
    s = math.sin(math.pi * t)
    if f0 < 31:                          # leaving the aim: the gun rides the shoulder, sinking as it goes
        q = track(p)
        u = math.sin(0.5 * math.pi * t)       # the gun drops early, before the chest turns away
        return dict(q, gy=q["gy"] - RISE_OFF[0] * u, gz=q["gz"] - RISE_OFF[1] * u)
    return dict(p, gy=p["gy"] - DIP[0] * s, gz=p["gz"] - DIP[1] * s)


DIP = (0.25, 0.15)
FIRE_KEYS = [(0, HI0), (2, SQZ), (3, SQZ), (4, SQZ), (5, mix(SQZ, KICK, 0.8)), (6, KICK),
             (7, mix(KICK, SETTLE, 0.6)), (8, OVER), (9, SETTLE), (15, dict(SETTLE, hy=SETTLE["hy"] + 0.1)),
             (21, WATCH), (31, RISE), (42, READY0)]

if DIAG:
    apply(_ref)
    _lob = L.launcher_object()
    _pinv = L.pivot_cf().inverted()
    for _d in (0.0, 1.0):
        apply(aim(_d))
        _pi = L.pivot_cf().inverted()
        print("REPORT aim%.0f shoulderL in meta %s  shoulderR %s  head %s" % (_d, [round(v, 2) for v in (_pi @ L.joint("LeftUpperArm")) / L.LAUNCHER_SCALE],
              [round(v, 2) for v in (_pi @ L.joint("RightUpperArm")) / L.LAUNCHER_SCALE],
              [round(v, 2) for v in (_pi @ L.joint("Head")) / L.LAUNCHER_SCALE]))
    apply(_ref)
    _loc = [(_pinv @ L.b2r(_lob.matrix_world @ v.co)) / L.LAUNCHER_SCALE for v in _lob.data.vertices]
    print("REPORT bbox min", [round(min(v[i] for v in _loc), 3) for i in range(3)],
          "max", [round(max(v[i] for v in _loc), 3) for i in range(3)])
    _yb = max(v.y for v in _loc)
    _butt = [v for v in _loc if v.y > _yb - 0.12]
    print("REPORT butt verts y>%.2f: x %.2f..%.2f z %.2f..%.2f" % (_yb - 0.12, min(v.x for v in _butt), max(v.x for v in _butt),
          min(v.z for v in _butt), max(v.z for v in _butt)))
    for _lvl in (-0.2, -0.4, -0.6, -0.8, -1.0):
        _sl = [v for v in _loc if abs(v.z - _lvl) < 0.06]
        if _sl:
            print("REPORT slice z=%.1f: y %.2f..%.2f x %.2f..%.2f" % (_lvl, min(v.y for v in _sl), max(v.y for v in _sl),
                  min(v.x for v in _sl), max(v.x for v in _sl)))
    for _n, _p in [("ready0", ready(0.0)), ("ready.25", ready(0.25)), ("ready.5", ready(0.5)), ("ready.75", ready(0.75)),
                   ("lo0", charge_pose(0.0, 0)), ("lo12", charge_pose(0.0, 12)), ("lo24", charge_pose(0.0, 24)),
                   ("hi0", charge_pose(1.0, 0)), ("hi12", charge_pose(1.0, 12)), ("hi24", charge_pose(1.0, 24)),
                   ("kick", KICK), ("hi", HI), ("sqz", SQZ), ("k5", mix(SQZ, KICK, 0.8)), ("watch", WATCH), ("rise", RISE),
                   ("f25", mix(WATCH, RISE, 0.4)), ("f28", mix(WATCH, RISE, 0.7)), ("f35", mix(RISE, READY0, 0.33)),
                   ("f39", mix(RISE, READY0, 0.67))]:
        diag(_n, _p)
    sys.exit(0)

new_clip("Ready")
NR = int(round(SPEC["Ready"] * 30))
for f in range(0, NR, 3):
    info = apply(ready(f / NR))
    if f % 24 == 0:
        info["gap"] = gap()
        info["wrist"] = wrist()
        report["ready_%d" % f] = info
    K(f)
apply(ready(0.0)); K(NR)
L.make_cyclic("Ready")

# ------------------------------------------------------------------ charge loops (same keys / phase)
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    new_clip(kind)
    for f in range(0, NC):                                       # every frame: the tremor must not alias
        info = apply(charge_pose(depth, f))
        if f % 12 == 0:
            info["gap"] = gap()
            info["wrist"] = wrist()
            report["%s_%d" % (kind, f)] = info
        K(f)
    apply(charge_pose(depth, 0)); K(NC)
    L.make_cyclic(kind)

# ------------------------------------------------------------------ Fire
new_clip("Fire")
_wmax = []
for i, (f, p) in enumerate(FIRE_KEYS):
    if i > 0 and f - FIRE_KEYS[i - 1][0] > 4:
        f0, p0 = FIRE_KEYS[i - 1]
        for g in range(f0 + 1, f, 1 if f0 >= 21 else 2):      # the rise is IK-solved every frame                          # IK-solved in-betweens (eased)
            t = L.smooth((g - f0) / (f - f0))
            apply(dip(mix(p0, p, t), f0, (g - f0) / (f - f0))); K(g)
            _wmax.append((g, wrist(), pose_audit()[2]))
    info = apply(p)
    info["gap"] = gap()
    info["wrist"] = wrist()
    _wmax.append((f, info["wrist"], pose_audit()[2]))
    report["fire_%d" % f] = info
    K(f)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
print("REPORT fire wrists", _wmax)

for k, v in report.items():
    print("REPORT pose %s %s" % (k, v))
L.finish(SPEC, OUT, extra_times=[0.067, 0.167, 0.2, 0.233, 0.3, 0.7, 1.03])
