"""17 Toxic Lobber -- black barrel with a bubbling green orb on top, swung UNDERARM, one-handed.

The player stands side-on on the pad (down-track = their LEFT, away from the camera; the camera
sees their right side / back).  The lobber hangs from the right hand on the character's right /
front side (screen-right), so the pad camera sees every swing.
  Ready    carried one-handed at the right side like a lantern; the toxic load sloshes: the
           barrel wobbles (roll + a lagging pitch sway), easy breathing.  Free left arm.
  ChargeLo pendulum: the arm swings the lobber back and forth low beside the hip (underarm), the
           knees dip at the bottom of every swing, the body rocks against the swing.
  ChargeHi the same pendulum, much bigger arcs (the lobber comes up to near horizontal behind and
           in front), deeper dips, the torso rocking and twisting with it, the slosh wobble wilder.
  Fire     last big back-swing (coil) -> the body turns to the track and the arm whips through the
           bottom -> RELEASE at FireAt: the barrel points down-track ~40 deg up and the ball arcs
           out of the muzzle -> the arm follows through high over the front -> watch -> lower.
The whole swing is a rigid pendulum: the barrel stays perpendicular to the arm (pistol grip in the
fist), so the launcher never slides in the hand.
"""
import importlib
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)
from mathutils import Vector

LID = 17
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.4,
    "FireAt": 0.333,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "toxic", "Color": [120, 255, 60], "Charge": "toxic", "ChargeColor": [140, 255, 70]},
    "TwoHanded": False,
    "Notes": "toxic lobber: sloshing one-handed carry, underarm pendulum swings while charging, underarm lob out of the barrel at ~40 deg",
}
FEET = {"Left": (-0.95, -0.2), "Right": (0.7, 0.3)}
R_ARM = 1.8          # shoulder -> grip pivot distance along the swing
OUT_SIDE = 0.45      # swing plane offset outward from the shoulder
REACH = math.sqrt(0.25 + (L.UPPER_ARM + L.LOWER_ARM) ** 2)   # shoulder -> wrist, arm straight
SLACK = 0.15         # the swinging arm stays this far inside full reach (relaxed ~35 deg elbow)
report = {}
READY_Q = [None]


def body(yaw=12.0, lean=-4.0, drop=0.18, back=0.05, side=0.0, waist_yaw=0.0, waist_bend=-4.0, waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


GRIP = [None]        # fixed pistol grip in the fist (Launcher bone), found from the Ready pose


def elev_of(a, A=60.0):
    """barrel elevation for arm angle a: the wrist cocks the barrel up on the back-swing
    (-0.45 A at the back) and it lines up with the arm going forward (+0.85 A in front)"""
    return 0.65 * a + 0.2 * a * a / A


ELBOW_TRY = ["plane"]   # the bent (slack) arm needs the in-plane pole; the old straight-arm triples flip it


def swing_best(*a, **kw):
    """swing() trying a few elbow directions (back, out, up in the swing frame); keeps the one
    with the most natural wrist"""
    best = None
    for eb in ELBOW_TRY:
        info = swing(*a, elbow=eb, **kw)
        c = info["wrist_swing"] + 1.3 * info["wrist_twist"] + 300.0 * info["arm_overreach"]
        if best is None or c < best[0]:
            best = (c, eb)
    info = swing(*a, elbow=best[1], **kw)
    info["elbow"] = best[1]
    return info


def swing(a, yaw_d, tilt=0.0, roll=0.0, r=R_ARM, out=OUT_SIDE, elbow="plane", elev=None, fyaw=None, A=60.0,
          slack=None):
    """pendulum: the arm hangs from the right shoulder and is swung `a` degrees forward (-back)
    in the vertical plane heading yaw_d (L.direction yaw).  The barrel points along fyaw (default
    yaw_d) at elevation elev (default elev_of(a)) + tilt.  elbow "plane" = the pole leads the arm in
    its swing plane (the elbow tip trails behind the arm, bending naturally, never flipping), else
    an (back, out, up) triple in the swing frame.  slack = keep the wrist that far inside full
    reach (the swing radius r is refitted; a slightly bent, relaxed arm).  Returns the place_launcher info."""
    S = L.joint("RightUpperArm")
    d = L.direction(yaw_d, 0.0)
    right = d.cross(Vector((0.0, 1.0, 0.0))).normalized()
    ar = math.radians(a)
    up = Vector((0.0, 1.0, 0.0))
    e = elev_of(a, A) if elev is None else elev
    fwd = L.direction(yaw_d if fyaw is None else fyaw, e + tilt)
    if elbow == "plane":
        pole = (up * math.sin(ar) + d * math.cos(ar) + right * 0.25).normalized()
    else:
        pole = (-d * elbow[0] + right * elbow[1] + up * elbow[2]).normalized()
    for it in range(4 if slack is not None else 1):
        P = S + right * out + (up * -math.cos(ar) + d * math.sin(ar)) * r
        if GRIP[0] is None:
            info = L.place_launcher(at=P, forward=fwd, up=L.up_for(fwd, roll), anchor="Pivot", elbow_away=pole,
                                    max_wrist=0.1, max_twist=0.1)
        else:
            info = L.place_launcher(at=P, forward=fwd, up=L.up_for(fwd, roll), anchor="Pivot", elbow_away=pole,
                                    grip_twist=GRIP[0])
        if slack is not None:
            s_now = REACH - (L.joint("RightHand") - S).length - info["arm_overreach"]
            if abs(s_now - slack) < 0.01:
                break
            r += (s_now - slack) * 1.05
    sw, tw = L.swing_twist(L.get_rot("RightHand"))
    ta = math.degrees(tw.angle)
    info["wrist_swing"] = round(math.degrees(sw.angle), 1)
    info["wrist_twist"] = round(360.0 - ta if ta > 180.0 else ta, 1)
    info["P"] = [round(v, 2) for v in P]
    info["r"] = round(r, 3)
    return info

def free_left(swing_z=0.0, out=0.0, lift=0.0):
    """relaxed left arm beside the body (torso-relative); swing_z + = back"""
    T = L.frame_of("UpperTorso")
    sh = L.joint("LeftUpperArm")
    wrist = sh + T @ Vector((-0.25 - out, -1.48 + lift, 0.1 + swing_z))
    L.arm_to("Left", wrist, elbow_away=T @ Vector((-0.2, 0.0, 1.0)))


PROBE = {}
VERTS = []


def probe(tag):
    """tuning aid: the motion-audit measures for the CURRENT pose (launcher / arm depth inside the
    torso + head on the audit's avatar proportions) and how far inside full reach each wrist is"""
    L.update()
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    lob = L.launcher_object()
    mw = lob.matrix_world
    wl, wl_at = 0.0, ""
    if not VERTS:
        vs = [v.co.copy() for v in lob.data.vertices]
        VERTS.extend(vs[::max(1, len(vs) // 400)])
    for co in VERTS:
        pt = L.b2r(mw @ co)
        for bn in ("UpperTorso", "Head"):
            d = L._depth_inside(pt, *boxes[bn])
            if d > wl:
                wl, wl_at = d, bn
    wa, wa_at = 0.0, ""
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for bn in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[bn])
                        if d > wa:
                            wa, wa_at = d, "%s/%s" % (arm, bn)
    slack = {s: round(REACH - (L.joint(s + "Hand") - L.joint(s + "UpperArm")).length, 2) for s in ("Left", "Right")}
    PROBE[tag] = {"L": round(wl, 2), "L_at": wl_at, "A": round(wa, 2), "A_at": wa_at, "slack": slack}
    return PROBE[tag]


PREV = [None]


def keyc(frame):
    """key with quaternion hemisphere continuity"""
    r = L.rig()
    if PREV[0] is not None:
        for pb in r.pose.bones:
            q = pb.rotation_quaternion
            if q.dot(PREV[0][pb.name]) < 0.0:
                pb.rotation_quaternion = -q
    PREV[0] = {pb.name: pb.rotation_quaternion.copy() for pb in r.pose.bones}
    probe("%s@%d" % (CUR[0], frame))
    L.key(frame)


CUR = [""]


def clip(kind):
    CUR[0] = kind
    PREV[0] = None
    L.new_clip(kind)


# ------------------------------------------------------------------ poses
def calib_pose():
    """the round-1 Ready(0) pose: defines the fixed pistol grip in the fist (kept so the hand /
    launcher relation of every pose stays what was reviewed)"""
    body(yaw=12.0, lean=-3.0, drop=0.18, side=0.0, waist_yaw=-3.0, waist_bend=-3.0, waist_roll=0.0)
    return swing(6.0 + 4.0 * math.sin(0.6), 76.0, tilt=-10.0, roll=8.0 * math.sin(1.2), elbow=(1.0, 0.5, -0.3))


def ready(t):
    """t 0..1 over the Ready loop: two breaths, one weight sway, a heavy sloshing load: the lobber
    hangs low, the torso leans away from it, the barrel wobbles in pitch + roll (3x and 5x)"""
    w = 2.0 * math.pi * t
    b = 0.5 - 0.5 * math.cos(2.0 * w)
    s = math.sin(w)
    body(yaw=12.0 + 2.0 * s, lean=-3.0 - 1.5 * b, drop=0.2 + 0.04 * b, side=-0.04 + 0.05 * s,
         waist_yaw=-3.0 - 2.0 * s, waist_bend=-3.0 - 2.0 * b, waist_roll=RD_ROLL + 1.5 * s)
    info = swing(RD_A + 4.0 * math.sin(w + 0.6), 90.0 - 14.0, out=RD_OUT, r=RD_R, slack=SLACK,
                 tilt=RD_TILT + 7.0 * math.sin(3.0 * w) + 2.5 * math.sin(5.0 * w + 0.7),
                 roll=5.0 + 11.0 * math.sin(3.0 * w + 1.2) + 3.0 * math.sin(5.0 * w + 2.0))
    free_left(swing_z=-0.06 * s, out=0.04 * b)
    L.head_look(target=(-9.0, 0.2, -2.5 + 1.0 * s))
    return info


RD_A, RD_TILT, RD_ROLL, RD_OUT, RD_R = 1.0, -23.0, 3.5, 0.55, 1.78

def charge(t, depth):
    """t 0..1 = one pendulum cycle starting at the BACK of the swing; depth 0 = Lo, 1 = Hi"""
    w = 2.0 * math.pi * t
    A = 38.0 + 30.0 * depth
    u = -math.cos(w)                      # -1 back .. +1 front
    a = A * u
    bottom = 1.0 - u * u                  # 1 at the bottom of the swing (twice per cycle)
    body(yaw=14.0 + 5.0 * depth + (2.0 + 5.0 * depth) * u,
         lean=-7.0 - 5.0 * depth + (2.0 + 7.0 * depth) * u,
         drop=0.26 + 0.14 * depth + (0.05 + 0.1 * depth) * bottom,
         back=0.08 + 0.05 * depth - (0.03 + 0.07 * depth) * u,
         side=-0.03 * u * depth,
         waist_yaw=(3.0 + 8.0 * depth) * u, waist_bend=-6.0 - 4.0 * depth + 3.0 * depth * u,
         waist_roll=-(1.0 + 3.0 * depth) * u)
    slosh = math.sin(w - 1.0)             # the load lags the swing
    info = swing(a, 90.0 - 16.0 - 4.0 * depth, A=A, r=CH_R - 0.08 * depth, out=CH_OUT + 0.05 * depth * (1.0 - u) * 0.5,
                 tilt=-2.0 + (5.0 + 5.0 * depth) * slosh,
                 roll=(4.0 + 8.0 * depth) + (5.0 + 7.0 * depth) * math.sin(2.0 * w + 0.8), slack=SLACK)
    free_left(swing_z=-(0.12 + 0.2 * depth) * u, out=0.05 + 0.15 * depth, lift=0.05 * depth)
    L.head_look(target=(-9.0, -0.2 - 0.6 * depth, -2.4))
    return info


CH_OUT, CH_R = 0.64, 1.74

# ------------------------------------------------------------------ clips
calib_pose()
GRIP[0] = L.get_rot("Launcher").copy()
report["grip_calibration"] = calib_pose()
clip("Ready")
N = 72
for i in range(0, 25):
    t = i / 24.0
    info = ready(t)
    if i % 6 == 0:
        report["ready%d" % i] = info
    keyc(int(round(t * N)))
L.make_cyclic("Ready")

NC = 36
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    clip(kind)
    for i in range(0, 13):
        t = i / 12.0
        info = charge(t, depth)
        if i % 3 == 0:
            report["%s_%d" % (kind, i)] = info
        keyc(int(round(t * NC)))
    L.make_cyclic(kind)

# ------------------------------------------------------------------ Fire
clip("Fire")
charge(0.0, 1.0); keyc(0)                                   # 0.00 = ChargeHi, back of the swing
# 0.13 COIL: the last, highest back-swing (well past the ChargeHi back), body wound away + sunk
body(yaw=2.0, lean=-19.0, drop=0.56, back=0.24, side=0.08, waist_yaw=-22.0, waist_bend=-12.0, waist_roll=6.0)
report["coil"] = swing_best(-96.0, 74.0, tilt=10.0, roll=10.0, r=1.66, A=94.0, out=0.7, slack=SLACK)
free_left(swing_z=-0.45, out=0.25, lift=0.15)
L.head_look(target=(-9.0, -0.5, -2.4)); keyc(4)
# 0.23 WHIP through the bottom: the body turns toward the track, knees deepest
body(yaw=32.0, lean=-12.0, drop=0.6, back=0.12, side=-0.1, waist_yaw=10.0, waist_bend=-8.0)
report["whip"] = swing(0.0, 38.0, tilt=0.0, roll=6.0, out=0.66, r=1.74, slack=SLACK)
free_left(swing_z=0.1, out=0.25, lift=0.1)
L.head_look(target=(-9.0, 0.5, -2.0)); keyc(7)
# 0.33 RELEASE (FireAt): arm up in front, barrel down the track ~40 deg up, weight onto the left foot
body(yaw=48.0, lean=-4.0, drop=0.38, back=0.02, side=-0.2, waist_yaw=22.0, waist_bend=-2.0, waist_roll=-4.0)
report["release"] = swing(40.0, 0.0, elev=40.0, out=0.9, slack=SLACK)
free_left(swing_z=0.35, out=0.3, lift=0.15)
L.head_look(target=(-10.0, 3.0, -1.6)); keyc(10)
# 0.47 follow-through OVERSHOOT: the arm whips on past vertical-ish, up on the toes of the swing
body(yaw=55.0, lean=4.0, drop=0.2, back=-0.03, side=-0.25, waist_yaw=28.0, waist_bend=5.0, waist_roll=-6.0)
report["follow"] = swing_best(104.0, -6.0, out=0.82, A=104.0, elev=80.0, slack=SLACK)
free_left(swing_z=0.45, out=0.32, lift=0.22)
L.head_look(target=(-12.0, 5.5, -1.4)); keyc(14)
# 0.63 settle back: the weight of the lobber pulls the arm down past the hold
body(yaw=48.0, lean=-1.0, drop=0.27, back=0.0, side=-0.18, waist_yaw=21.0, waist_bend=-1.0, waist_roll=-4.0)
report["dip"] = swing_best(68.0, 2.0, out=0.72, A=88.0, slack=SLACK)
free_left(swing_z=0.3, out=0.22, lift=0.12)
L.head_look(target=(-14.0, 4.0, -1.4)); keyc(19)
# 0.80 small rebound, watching the lob
body(yaw=47.0, lean=0.0, drop=0.24, back=0.0, side=-0.17, waist_yaw=20.0, waist_bend=0.0, waist_roll=-3.0)
report["hang"] = swing_best(76.0, 4.0, out=0.72, A=88.0, slack=SLACK)
free_left(swing_z=0.25, out=0.2, lift=0.1)
L.head_look(target=(-15.0, 3.0, -1.4)); keyc(24)
# 1.10 lowering: the lobber swings back down to the side
body(yaw=24.0, lean=-3.0, drop=0.22, back=0.04, side=-0.04, waist_yaw=4.0, waist_bend=-3.0, waist_roll=2.0)
report["lower"] = swing(16.0, 55.0, tilt=-10.0, roll=4.0, out=0.6, r=1.76, slack=SLACK)
free_left(swing_z=0.05, out=0.08)
L.head_look(target=(-10.0, 0.5, -2.2)); keyc(33)
ready(0.0); keyc(42)                                        # 1.40 = Ready
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in PROBE.items():
    if v["L"] > 0.08 or v["A"] > 0.08 or min(v["slack"].values()) < 0.15:
        print("PROBE %s %s" % (k, json.dumps(v)))
for k, v in report.items():
    print("REPORT_POSE %s %s" % (k, json.dumps({q: v.get(q) for q in ("arm_overreach", "anchor_err", "wrist_bend_deg", "r")})))
L.finish(SPEC, OUT, extra_times=[0.133, 0.233, 0.467, 0.633, 0.8, 1.1])
