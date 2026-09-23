"""20 Blizzard Launcher -- silver cannon with blue fins: SWIRL a blizzard, then thrust it down the track.

The player stands side-on on the pad (down-track = their LEFT, away from the pad camera); the
cannon is carried well out on the character's FRONT side (screen-right) so the camera sees it
end-on and clear of the head / chest.
  Ready    carried low at the right hip with both hands (right on the pistol grip, left under the
           barrel), muzzle angled a little down the track; breathing + a slow weight shift.
  ChargeLo BLIZZARD SWIRL: raised and roughly aimed down the track, the muzzle draws a slow small
           circle in the air (one per loop); the torso / hips sway with the circle.
  ChargeHi the same circle (same phase), much wider -- driven by the arms and the body -- in a
           deeper crouch, with a fast whirl riding on top (3 per loop) + a 6x shake: a wilder storm.
  Fire     the gun is drawn back (wind-up) -> a sweeping THRUST with a hip lunge along the track,
           the ball blasts out of the muzzle at FireAt -> heavy recoil rocks the upper body back
           -> a late kick up -> settle to the hip carry.
Ball: hidden until it pops out of the Muzzle.  Snow burst, snow swirling at the muzzle while charging.
"""
import importlib
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)

LID = 20
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.4,
    "FireAt": 0.20,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "snow", "Color": [235, 245, 255], "Charge": "snow", "ChargeColor": [190, 225, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "blizzard cannon: the muzzle swirls circles (wider + a fast whirl at full charge), then a sweeping thrust down the track",
}
FEET = {"Left": (-1.0, -0.45), "Right": (0.75, 0.25)}
TRACK_LOOK = (-12.0, 0.5, -1.8)
R_ELBOW = (-0.3, 1.0, 0.3)
L_ELBOW = (0.3, 1.0, 0.2)
THR_ELBOW = (-0.3, 1.0, 0.3)
report = {}

GRIP = {"q": None}      # the cannon sits rigidly in the hand: one grip rotation for every pose


def cannon(at, yaw, elev, roll=0.0, elbow=R_ELBOW, give=25.0):
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow)
    if GRIP["q"] is None:
        GRIP["q"] = L.get_rot("Launcher").copy()
        return info
    g0, gn = GRIP["q"], L.get_rot("Launcher").copy()
    if g0.dot(gn) < 0.0:
        gn = -gn
    d = math.degrees(g0.rotation_difference(gn).angle)
    gq = g0.slerp(gn, min(1.0, give / d)) if d > 1e-3 else g0
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow, grip_twist=gq)
    info["grip_vs_ready"] = round(min(d, give), 1)
    return info


PREV = {}


def key(frame):
    """L.key with every bone's quaternion kept in one hemisphere (no long-way spins)"""
    r = L.rig()
    for name in L.BONES:
        pb = r.pose.bones[name]
        q = pb.rotation_quaternion.copy()
        ref = PREV.get(name)
        if ref is not None and q.dot(ref) < 0.0:
            pb.rotation_quaternion = -q
        PREV[name] = pb.rotation_quaternion.copy()
    L.update()
    L.key(frame)


def body(yaw=15.0, lean=-9.0, drop=0.25, back=0.1, waist_yaw=4.0, waist_bend=-8.0, side=0.0, roll=0.0, waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def left(offset=(0.0, 0.0, 0.0)):
    return L.left_hand_to(key="Grip2", elbow_away=L_ELBOW, offset=offset)


# ------------------------------------------------------------------ measuring (body clipping)
def _boxes():
    return {n: (b, h) for n, b, h in L.body_boxes()}


def _depth(pts, box, half):
    """max depth of points inside a box (<= 0 = outside by that much, approx for outside)"""
    Bi = np.array(box.inverted())
    q = pts @ Bi[:3, :3].T + Bi[:3, 3]
    d = np.min(np.array(half)[None, :] - np.abs(q), axis=1)
    return float(d.max()), int((d > 0.0).sum())


def pen_launcher():
    """(Head depth, Head count, UpperTorso depth, count) of launcher vertices inside those blocks"""
    ob = L.launcher_object()
    L.update()
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    M = np.array(ob.matrix_world)
    W = co @ M[:3, :3].T + M[:3, 3]
    R = np.stack([W[:, 0], W[:, 2], -W[:, 1]], axis=1)
    bx = _boxes()
    hd, hn = _depth(R, *bx["Head"])
    td, tn = _depth(R, *bx["UpperTorso"])
    return hd, hn, td, tn


def pen_arm(side="Right"):
    """how deep the arm's centre line (elbow half of the upper arm .. wrist) sits inside UpperTorso"""
    a, b, c = L.joint(side + "UpperArm"), L.joint(side + "LowerArm"), L.joint(side + "Hand")
    pts = [a.lerp(b, t) for t in (0.75, 1.0)] + [b.lerp(c, t) for t in (0.25, 0.5, 0.75)]
    box, half = _boxes()["UpperTorso"]
    d, _ = _depth(np.array([tuple(p) for p in pts]), box, half)
    return d


def headax():
    """distance from the head centre to the barrel axis (>= 1.3 = face clearly visible)"""
    h = L.joint("Head") + L.frame_of("Head") @ L.Vector((0.0, 0.6, 0.0))
    a = L.launcher_point((0.0, 0.0, -0.853)); b = L.launcher_point((0.0, -2.035, -0.853))
    ax = (b - a).normalized(); t = max(0.0, min((h - a).dot(ax), (b - a).length))
    return (h - (a + ax * t)).length


def _bend():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


LAST = {"pole": None}


def guard_nx(side, pole):
    """x of the raw elbow hinge axis (UpperTorso frame) for this pole; the library's elbow guard
    mirrors it below -0.15, so keep it well above (> 0.15) to never sit on that switch"""
    sh, w = L.joint(side + "UpperArm"), L.joint(side + "Hand")
    Mi = L.frame_of("UpperTorso").inverted()
    t = Mi @ (w - sh)
    if t.length < 1e-6:
        return 1.0
    n = t.normalized().cross(Mi @ L.Vector(pole))
    return n.normalized().x if n.length > 1e-4 else 0.0


def lbend(side):
    """elbow bend in degrees (0 = straight = at full reach; keep >= ~45 = 0.15 studs inside reach)"""
    a = math.degrees(L.get_rot(side + "LowerArm").angle)
    return min(a, 360.0 - a)


def clip_score(info, arm_margin=0.15):
    """lower = better: wrist bend + penalties (left hand off Grip2, anchor miss, arm in the chest,
    an elbow pole near the guard's mirror switch)"""
    nr = guard_nx("Right", LAST["pole"]) if LAST["pole"] is not None else 1.0
    nl = guard_nx("Left", L_ELBOW)
    return (_bend() + 100.0 * max(0.0, info["left"][0] - 0.12) + 200.0 * max(0.0, info["anchor_err"] - 0.01)
            + 300.0 * max(0.0, pen_arm() + arm_margin) + 300.0 * max(0.0, pen_arm("Left") + arm_margin)
            + 400.0 * max(0.0, 0.25 - nr) + 400.0 * max(0.0, 0.25 - nl)
            + 2.0 * max(0.0, 45.0 - lbend("Right")) + 2.0 * max(0.0, 45.0 - lbend("Left")))


def score_parts(info):
    nr = guard_nx("Right", LAST["pole"]) if LAST["pole"] is not None else 1.0
    return "b%.0f g%.2f a%.3f arm%.2f/%.2f nx%.2f/%.2f lb%.0f rb%.0f" % (_bend(), info["left"][0], info["anchor_err"], pen_arm(),
                                                        pen_arm("Left"), nr, guard_nx("Left", L_ELBOW), lbend("Left"), lbend("Right"))


# ------------------------------------------------------------------ pose sets
BODY_KEYS = ("yaw", "lean", "drop", "back", "waist_yaw", "waist_bend", "side", "roll", "waist_roll")


def _fp(m):
    body(**{k: m[k] for k in BODY_KEYS})
    LAST["pole"] = m["elbow"]
    if m.get("grip") is not None:
        # an explicit, smoothly varying grip: the cannon never jumps around in the hand
        info = L.hold(m["at"], yaw=m["cyaw"], elev=m["celev"], roll=m.get("croll", 0.0), anchor="Pivot",
                      elbow_away=m["elbow"], grip_twist=m["grip"])
        info["grip_vs_ready"] = round(qang(GRIP["q"], m["grip"]), 1)
    else:
        info = cannon(m["at"], yaw=m["cyaw"], elev=m["celev"], roll=m.get("croll", 0.0), elbow=m["elbow"], give=m["give"])
    info["left"] = left()
    L.head_look(target=m["look"])
    return info


def qang(a, b):
    b = -b if a.dot(b) < 0.0 else b
    return math.degrees(a.rotation_difference(b).angle)


def qslerp(a, b, u):
    b = -b if a.dot(b) < 0.0 else b
    return a.slerp(b, u)


def natural_grip(m, limit):
    """the grip rotation the free solve wants for pose m, limited to `limit` deg from the Ready grip"""
    m = dict(m); m["grip"] = None; m["give"] = 180.0
    _fp(m)
    return qslerp(GRIP["q"], L.get_rot("Launcher").copy(), 1.0)


def clamp_grip(q, limit):
    d = qang(GRIP["q"], q)
    return qslerp(GRIP["q"], q, min(1.0, limit / d)) if d > 1e-3 else GRIP["q"].copy()


def _mix(a, b, u):
    if a is None or b is None:
        return a if b is None else b
    if isinstance(a, L.Quaternion):
        return qslerp(a, b, u)
    if isinstance(a, tuple):
        return tuple(x + (y - x) * u for x, y in zip(a, b))
    return a + (b - a) * u


CROLL = 20.0     # the cannon rolled toward the character's front: hopper / fins tilt away from the cheek / chest
RZ = -1.58       # carry distance in front of the body (was -1.35: the breech sat in the head)


def ready_params(b, s=0.0):
    """b 0..1 = breathing, s -1..1 = weight shift"""
    return dict(yaw=10.0 + 2.0 * s, lean=-7.0 + 2.5 * b, drop=0.22 - 0.04 * b, back=0.08, side=0.05 * s,
                waist_yaw=3.0 + 1.0 * b, waist_bend=-4.0 + 2.0 * b, roll=1.5 * s, waist_roll=0.0,
                at=(0.42, -1.0 + 0.08 * b, RZ), cyaw=5.0 - 1.0 * b + 1.5 * s, celev=-6.0 + 2.0 * b,
                croll=CROLL, elbow=R_ELBOW, give=25.0, look=(-8.0, -0.5 + 0.5 * b, -3.0))


N_CH = 36       # one key per frame over the 1.2 s loop (the in-betweens stay on the IK'd circle)
GIVE_CH = 60.0
SW = {"elbow": R_ELBOW, "grip": None}
OFF = {0.0: (0.0, 0.0, 0.0, 0.0), 1.0: (0.0, 0.0, 0.0, 0.0)}   # per-depth (dx, dy, dz, waist yaw) found by pose_search
CH_GRIP_LIMIT = 40.0
SW_Y = -0.8


def swirl_params(i, depth):
    """i = frame over the loop; depth 0 = ChargeLo, 1 = ChargeHi (same phase)"""
    th = 2.0 * math.pi * i / N_CH
    c, s = math.cos(th), math.sin(th)
    A = 8.0 + 5.0 * depth                          # angular circle (deg)
    th3, th6 = 4.0 * th, 6.0 * th                  # fast whirl: 4 small loops per circle
    wy = 5.5 * depth * math.cos(th3) + 1.5 * depth * math.sin(th6)
    we = 5.5 * depth * math.sin(th3) + 1.5 * depth * math.cos(th6)
    dy = A * (1.0 + 0.35 * depth) * c + wy         # yaw offset (+ = toward the front); Hi = clearly wider sideways
    de = A * s + we                                # elevation offset
    R = 0.1 + 0.2 * depth                          # the grip itself circles (arms + body)
    k = 1.0 + 1.5 * depth
    ox, oy, oz, ow = OFF[depth]
    return dict(yaw=12.0 + 1.0 * depth + 0.8 * k * c - 1.5 * k * s,        # hips steady; the sway is in the side / roll
                lean=-6.0 - 2.0 * depth + (1.5 - 0.3 * depth) * k * s,  # and rocks back as it rises (head clear)
                drop=0.34 + 0.3 * depth - 0.05 * k * s,
                back=0.1 + 0.05 * depth,
                side=0.05 * k * c,
                waist_yaw=2.0 - 4.0 * depth + ow - 1.2 * k * c - 1.0 * k * s,
                waist_bend=-4.0 - 1.0 * depth + 1.5 * k * s,
                roll=-2.0 * k * c,
                waist_roll=-2.5 * k * c,
                at=(0.45 + 0.1 * depth + (0.1 + 0.3 * depth) * R * c + ox, SW_Y - 0.2 * depth + (0.7 - 0.3 * depth) * R * s + oy,
                    -1.64 - 0.02 * depth + 0.2 * R * c + oz),
                cyaw=8.0 + 5.0 * depth + dy, celev=3.0 + 3.0 * depth + de, croll=CROLL + 1.5 * k * c,
                elbow=SW["elbow"], give=GIVE_CH, grip=SW["grip"],
                look=(TRACK_LOOK[0], TRACK_LOOK[1] + 0.8 * de / 6.0, TRACK_LOOK[2] - 0.8 * dy / 6.0))


# ------------------------------------------------------------------ audit helpers
AUD = []


def audit(tag, info=None):
    hd, hn, td, tn = pen_launcher()
    ra, la = pen_arm("Right"), pen_arm("Left")
    ha = headax()
    AUD.append((tag, hd, hn, td, tn, ra, la, ha))
    return hd, td, ra, ha


def audit_clip(kind, n):
    L.use_clip(kind)
    worst = [-9, -9, -9, 9]
    wf = [None] * 4
    rows = []
    for f in range(0, n + 1):
        L.goto(f / 30.0)
        hd, hn, td, tn = pen_launcher()
        ra = pen_arm("Right")
        ha = headax()
        for j, v in enumerate((hd, td, ra)):
            if v > worst[j]:
                worst[j], wf[j] = v, f
        if ha < worst[3]:
            worst[3], wf[3] = ha, f
        rows.append("%d:h%.2f/t%.2f/a%.2f/x%.2f/w%.0f" % (f, hd, td, ra, ha, _bend()))
    print("REPORT_AUDIT", kind, "head_in %.2f@%s torso_in %.2f@%s arm_in %.2f@%s headax %.2f@%s" %
          (worst[0], wf[0], worst[1], wf[1], worst[2], wf[2], worst[3], wf[3]))
    print("REPORT_ROWS", kind, " ".join(rows))


def muzzle_track(kind, n):
    L.use_clip(kind)
    g = L.load_meta(LID)["Muzzle"]["pos"]
    out = []
    prev = None
    for f in range(0, n + 1):
        L.goto(f / 30.0)
        p = L.launcher_point(g)
        d = L.launcher_dir((0.0, -1.0, 0.0))
        el = math.degrees(math.asin(max(-1.0, min(1.0, d.y))))
        sp = (p - prev).length if prev is not None else 0.0
        prev = p
        out.append("%d:(%.2f,%.2f,%.2f)e%.1f v%.2f" % (f, p.x, p.y, p.z, el, sp))
    print("REPORT_MUZZLE", kind, " ".join(out))


# ------------------------------------------------------------------ Ready
L.new_clip("Ready"); PREV.clear()
report["ready0"] = _fp(ready_params(0.0, 0.0)); key(0)
report["ready1"] = _fp(ready_params(1.0, 0.6)); key(24)
_fp(ready_params(0.3, 1.0)); key(42)
_fp(ready_params(0.8, -0.4)); key(58)
_fp(ready_params(0.0, 0.0)); key(72)
L.make_cyclic("Ready")
READY_PREV = dict(PREV)


# ------------------------------------------------------------------ charge loops
def _sw_score():
    worst = 0.0
    for depth in (0.0, 1.0):
        for i in range(0, N_CH, 3):
            info = _fp(swirl_params(i, depth))
            worst = max(worst, clip_score(info))
    return worst


# one constant grip for both charge loops (the mean of what the free solve wants, <= 40 deg off
# Ready): the circle is made by the arm / wrist / body, the cannon never slides in the hand
_qs = []
for _d in (0.0, 1.0):
    for _i in range(0, N_CH, 2):
        _qs.append(natural_grip(swirl_params(_i, _d), 180.0))
_acc = L.Quaternion((0.0, 0.0, 0.0, 0.0))
for _q in _qs:
    _q = -_q if _q.dot(GRIP["q"]) < 0.0 else _q
    _acc = L.Quaternion([a + b for a, b in zip(_acc, _q)])
_acc.normalize()
print("REPORT_CH_GRIP mean %.1f deg off Ready, spread %.1f" % (qang(GRIP["q"], _acc), max(qang(_acc, q) for q in _qs)))
SW["grip"] = clamp_grip(_acc, CH_GRIP_LIMIT)

def pose_score(info):
    """comfort of one swirl frame: both elbows >= 0.15 studs inside reach, wrist <= 60, arms and
    launcher clear of the chest / head, the face clear of the barrel"""
    hd, _, td, _ = pen_launcher()
    return (2.0 * max(0.0, _bend() - 60.0) + 2.0 * max(0.0, 45.0 - lbend("Left")) + 2.0 * max(0.0, 45.0 - lbend("Right"))
            + 300.0 * max(0.0, pen_arm() + 0.12) + 300.0 * max(0.0, pen_arm("Left") + 0.12)
            + 300.0 * max(0.0, hd + 0.1) + 300.0 * max(0.0, td + 0.1) + 100.0 * max(0.0, info["left"][0])
            + 50.0 * max(0.0, 1.5 - headax()))


for _d in (0.0, 1.0):
    _pb = None
    for _ox in (-0.1, 0.0, 0.1):
        for _oy in (-0.05, 0.05, 0.15):
            for _oz in (-0.05, 0.05, 0.15):
                for _ow in (-2.0, 1.5, 5.0):
                    OFF[_d] = (_ox, _oy, _oz, _ow)
                    _sc = sum(pose_score(_fp(swirl_params(_i, _d))) for _i in range(0, N_CH, 3))
                    if _pb is None or _sc < _pb[0]:
                        _pb = (_sc, OFF[_d])
    OFF[_d] = _pb[1]
    print("REPORT_OFF", _d, _pb)

_best = None
for _ex in (-0.6, -0.3, 0.0, 0.3):
    for _ey in (1.0, 0.6):
        for _ez in (-0.2, 0.1, 0.4, 0.7):
            SW["elbow"] = (_ex, _ey, _ez)
            _sc = _sw_score()
            if _best is None or _sc < _best[0]:
                _best = (_sc, SW["elbow"])
SW["elbow"] = _best[1]
print("REPORT_SW_ELBOW", _best)
for _d in (0.0, 1.0):
    for _i in range(0, N_CH, 3):
        _inf = _fp(swirl_params(_i, _d)); print("REPORT_SWP", _d, _i, score_parts(_inf), "grip", _inf.get("grip_vs_ready"), round(headax(), 2), [round(v, 2) for v in pen_launcher()])

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind); PREV.clear(); PREV.update(READY_PREV)
    for i in range(N_CH):
        r = _fp(swirl_params(i, depth))
        if i in (0, 9, 18, 27):
            report["%s_%d" % (kind, i)] = r
        key(i)
    _fp(swirl_params(0, depth)); key(N_CH)
    L.make_cyclic(kind)

# ------------------------------------------------------------------ Fire
CH0 = swirl_params(0, 1.0)
WIND = dict(yaw=6.0, lean=-3.0, drop=0.62, back=0.22, waist_yaw=-6.0, waist_bend=-2.0, side=0.14, roll=3.0, waist_roll=0.0,
            at=(0.9, -0.95, -1.5), cyaw=20.0, celev=-2.0, croll=CROLL, elbow=THR_ELBOW, give=55.0, look=TRACK_LOOK)
THRUST = dict(yaw=27.0, lean=-9.0, drop=0.7, back=-0.02, waist_yaw=5.0, waist_bend=-4.0, side=-0.3, roll=0.0, waist_roll=0.0,
              at=(0.12, -0.92, -1.9), cyaw=4.0, celev=10.0, croll=CROLL, elbow=THR_ELBOW, give=55.0, look=TRACK_LOOK)
# heavy recoil: the cannon slides straight back along the barrel and the upper body rocks back
RECOIL = dict(yaw=16.0, lean=-2.0, drop=0.55, back=0.35, waist_yaw=3.0, waist_bend=0.0, side=0.02, roll=-2.0, waist_roll=-1.0,
              at=(0.6, -0.85, -1.62), cyaw=6.0, celev=11.0, croll=CROLL, elbow=(-0.3, 1.0, 0.3), give=55.0, look=TRACK_LOOK)
KICK = dict(yaw=17.0, lean=-1.0, drop=0.44, back=0.3, waist_yaw=4.0, waist_bend=2.0, side=0.08, roll=-4.0, waist_roll=-3.0,
            at=(0.5, -0.6, -1.6), cyaw=8.0, celev=25.0, croll=CROLL, elbow=(0.0, 1.0, 0.3), give=45.0, look=(-10.0, 2.0, -1.5))
RIDE = dict(yaw=15.0, lean=-4.0, drop=0.36, back=0.18, waist_yaw=4.0, waist_bend=-1.0, side=0.05, roll=-2.5, waist_roll=-1.5,
            at=(0.45, -0.8, -1.6), cyaw=10.0, celev=10.0, croll=CROLL, elbow=(0.0, 1.0, 0.3), give=40.0, look=(-11.0, 1.0, -1.8))
RECOVER = dict(yaw=12.0, lean=-7.5, drop=0.3, back=0.1, waist_yaw=4.0, waist_bend=-5.0, side=0.0, roll=0.0, waist_roll=0.0,
               at=(0.42, -1.04, -1.6), cyaw=11.0, celev=-8.0, croll=CROLL, elbow=R_ELBOW, give=25.0, look=(-10.0, 0.0, -2.0))
SETTLE = dict(ready_params(0.0, 0.0))
SETTLE.update(lean=-7.5, celev=-6.5, at=(0.42, -1.01, RZ))


def tune_elbow(P, name, zs=(-0.3, 0.0, 0.3, 0.6)):
    """pick the right-elbow direction that keeps the wrist straightest (and out of the chest)"""
    best = None
    for ex in (-0.6, -0.3, 0.0, 0.3, 0.6):
        for ez in zs:
            P["elbow"] = (ex, 1.0, ez)
            info = _fp(P)
            score = clip_score(info)
            if best is None or score < best[0]:
                best = (score, P["elbow"])
    P["elbow"] = best[1]
    print("REPORT_ELBOW", name, best, score_parts(_fp(P)))


def fpose(A, B=None, u=0.0):
    """key pose (A) or an IK-solved in-between from blended parameters; the elbow stays near the
    blended one (a heavy distance cost) so the wrist does not snap between frames"""
    if B is None:
        return _fp(A)
    m = {k: _mix(A[k], B[k], u) for k in A}
    e0 = m["elbow"]
    best = None
    for ex in (-0.6, -0.3, 0.0, 0.3, 0.6, None):
        for ez in (-0.3, 0.0, 0.3, 0.6):
            e = e0 if ex is None else (ex, 1.0, ez)
            m["elbow"] = e
            info = _fp(m)
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(e, e0)))
            score = clip_score(info) + 45.0 * dist
            if best is None or score < best[0]:
                best = (score, e)
            if ex is None:
                break
    m["elbow"] = best[1]
    _r = _fp(m)
    print("REPORT_FP u%.2f e%s %s grip%s" % (u, best[1], score_parts(_r), _r.get("grip_vs_ready")))
    return _r


def fire_search(P, name):
    """nudge a Fire key pose (grip point in toward the body / chest turned to the front) until both
    elbows sit >= 0.15 studs inside reach -- the aim (cyaw / celev) is never changed"""
    base_at, base_wy = P["at"], P["waist_yaw"]
    best = None
    for dx in (-0.15, 0.0, 0.15):
        for dz in (0.0, 0.12, 0.24):
            for wy in (-10.0, -5.0, 0.0):
                P["at"] = (base_at[0] + dx, base_at[1], base_at[2] + dz)
                P["waist_yaw"] = base_wy + wy
                sc = pose_score(_fp(P)) + 3.0 * (abs(dx) + dz) + 0.3 * abs(wy)
                if best is None or sc < best[0]:
                    best = (sc, P["at"], P["waist_yaw"])
    P["at"], P["waist_yaw"] = best[1], best[2]
    print("REPORT_FSEARCH", name, round(best[0], 1), tuple(round(v, 2) for v in best[1]), best[2], score_parts(_fp(P)))


for _n, _P in (("wind", WIND), ("thrust", THRUST), ("recoil", RECOIL), ("kick", KICK), ("ride", RIDE), ("recover", RECOVER)):
    fire_search(_P, _n)
    tune_elbow(_P, _n, zs=(0.0, 0.3, 0.6) if _n in ("wind", "thrust") else (-0.3, 0.0, 0.3, 0.6))

for _n, _P, _lim in (("wind", WIND, 45.0), ("thrust", THRUST, 45.0), ("recoil", RECOIL, 45.0), ("kick", KICK, 40.0),
                     ("ride", RIDE, 35.0), ("recover", RECOVER, 25.0), ("settle", SETTLE, 25.0)):
    _P["grip"] = clamp_grip(natural_grip(_P, 180.0), _lim)
    print("REPORT_FIRE_GRIP", _n, round(qang(GRIP["q"], _P["grip"]), 1))

L.new_clip("Fire"); PREV.clear(); PREV.update(READY_PREV)
_fp(CH0); key(0)                                                # 0.00 the ChargeHi pose
fpose(CH0, WIND, 0.4); key(1)
fpose(CH0, WIND, 0.8); key(2)
report["windup"] = fpose(WIND); key(3)                          # 0.10 drawn back
fpose(WIND, THRUST, 0.45); key(4)
fpose(WIND, THRUST, 0.85); key(5)
report["thrust"] = fpose(THRUST); key(6)                        # 0.20 FireAt: the ball leaves the muzzle
fpose(THRUST, RECOIL, 0.6); key(7)
report["recoil"] = fpose(RECOIL); key(8)                        # 0.27 slid back, body rocked back
fpose(RECOIL, KICK, 0.3); key(9)
fpose(RECOIL, KICK, 0.7); key(10)
report["kick"] = fpose(KICK); key(11)                           # 0.37 the late upward kick
fpose(KICK, RIDE, 0.25); key(12)
fpose(KICK, RIDE, 0.5); key(13)
fpose(KICK, RIDE, 0.75); key(14)
report["ride"] = fpose(RIDE); key(16)                           # 0.53 riding the kick back
fpose(RIDE, RECOVER, 0.3); key(18)
fpose(RIDE, RECOVER, 0.65); key(20)
report["recover"] = fpose(RECOVER); key(23)                     # 0.77 recover, small overshoot down
fpose(RECOVER, SETTLE, 0.5); key(27)
fpose(SETTLE); key(31)                                          # 1.03 settle
_fp(ready_params(0.0, 0.0)); key(42)                            # 1.40 back to the Ready carry
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

# ------------------------------------------------------------------ diagnostics
for _kind, _n in (("Ready", 72), ("ChargeLo", 36), ("ChargeHi", 36), ("Fire", 42)):
    audit_clip(_kind, _n)
muzzle_track("ChargeLo", 36)
muzzle_track("ChargeHi", 36)
muzzle_track("Fire", 14)
L.use_clip("Fire")
_g2 = L.load_meta(LID)["Grip2"]["pos"]
_diag = []
for _i in range(0, 43, 1):
    L.goto(_i / 30.0)
    _diag.append("%d:%.2f/%.2f/w%.0f" % (_i, (L.hand_cf("Left").translation - L.launcher_point(_g2)).length, L.launcher_lowest_y(), _bend()))
print("REPORT_GAP", " ".join(_diag))
for k, v in report.items():
    print("REPORT_POSE", k, v)
L.finish(SPEC, OUT, extra_times=[0.1, 0.23, 0.27, 0.3, 0.37, 0.53])
