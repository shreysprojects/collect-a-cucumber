"""21 Golden Ballista -- a heavy golden crossbow with saw-tooth bow arms.

  Ready    stately: held UPRIGHT at the right shoulder like a rifle at parade, left hand steadying
           the fore-end, chin up, slow proud breathing + a small weight shift.
  ChargeLo a proud wide braced stance, the ballista shouldered and aimed down the track, the
           snowball sitting on the rail; slow breathing sway of the aim.
  ChargeHi the same aim from a deeper stance, the body leaning BACK against the heavy drawn
           string, the whole weapon trembling with tension (same phase as Lo).
  Fire     tiny squeeze forward -> heavy THUNK at FireAt (the ball leaves the rail straight down
           the track) -> big recoil: the ballista bucks up and back, the body rocks back on its
           heels -> a regal recovery upright -> the ballista swung back up to the shoulder.
Ball: on the rail (Seat) while charging, flies from the Seat.
Meta change: Grip2 moved up (z -0.35 -> -0.5) so the left hand holds the fore-end instead of air.
Geometry (aim spot, body turn, elbows, upright hold) found by probe.py.
Round 2: Lo breathing sway readable (seat y +-0.09, lean +-2, yaw drift +-1.5), Hi leans BACK onto the rear
foot (lean +2.5, waist bend +12) with a visible string tremor (0.14/0.12 studs, +-1.5 deg elev, +-1 deg roll),
body turned 30 deg so the stock sits on the shoulder, cheek on the stock, 12 deg more grip twist (wrist < 61),
Fire brace (hips sink, chest in, chin tucked) before the THUNK.
Round 3 (motion audit): search_hold scores the audit's avatar boxes (sink()); the recoil kick/rock push the
ballista forward (-Z 0.25-0.3) and up instead of back into the chest (forearm 0.35 -> 0.15), and the swing up
to the shoulder turns the nose out front (yaw 45, elev 25) with the left hand returning to the hip, so the
stock / bow arms pass beside the face (launcher in head 0.42 -> 0.03).
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

LID = 21
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.6,
    "FireAt": 0.17,
    "Ball": {"show": "Charge", "start": "Seat", "grow": 1.0},
    "Fx": {"Style": "spark", "Color": [255, 215, 90]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "golden ballista: upright at the shoulder, braced shouldered aim, lean back on the drawn string, heavy THUNK recoil + regal recovery",
}
HI_SIDE, HI_TILT, HI_WYAW = 0.06, 5.0, 16.0
FEET = {"Left": (-1.1, -0.35), "Right": (0.8, 0.5)}
Z_AIM, Y_AIM, X_AIM = -1.85, 2.05, -1.5
CHEEK = 10.0
AY = 18.0     # body turn toward the track in the aim: the right shoulder comes forward under the stock
AIM_TARGET = (-14.0, 1.6, Z_AIM + 0.2)
RE_AIM = (0.3, -1.0, 0.0)     # elbow down + out to the side under the shouldered stock
LE_AIM = (-0.28, -0.92, -0.28)
LE_TRY = [LE_AIM, (-0.6, -0.8, 0.2), (-0.2, -1.0, 0.5), (-0.8, -0.3, -0.3), (-0.3, -0.5, -0.8), (0.0, -1.0, 0.0)]
LAST_LE = [0]
UP_P = Vector((0.8, 0.3, -1.3))   # the grip out front-right: the ballista stands clear of the head
RE_UP = (0.15, 1.0, -0.2)
HIP = Vector((-1.35, 0.0, -0.1))   # left fist on the hip (regal, clear of the torso)
HIP_LE = (0.8, 0.6, 0.0)
LE_UP = (-0.88, -0.44, -0.18)
META = L.load_meta(LID)
G2 = META["Grip2"]["pos"]
ARM = ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand")
RE = [Vector(v).normalized() for v in ((0.6, -0.6, 0.3), (1.0, -1.0, 0.0), (0.5, -1.0, 0.6), (1.0, -0.2, 0.5),
                                        (0.3, -1.0, -0.5), (1.0, 0.3, 0.0), (0.8, -1.0, 0.4), (0.2, -1.0, 1.0),
                                        RE_AIM, RE_UP, (0.6, 0.6, 0.6), (0.2, 0.5, 1.0), (1.0, 0.5, -0.3))]
LE = [Vector(v).normalized() for v in ((-0.3, -1.0, -0.3), (-0.6, -1.0, 0.2), (-1.0, -0.5, -0.2), (-0.3, -1.0, 0.5))]
report = {}
GT = None
PREV_E = [Vector(RE_AIM).normalized()]
_prev = {}


def new_clip(kind):
    _prev.clear()
    L.new_clip(kind)


def K(f):
    """key with every quaternion kept in the previous key's hemisphere (no long-way-round flips)"""
    for pb in L.rig().pose.bones:
        q = pb.rotation_quaternion.copy()
        p = _prev.get(pb.name)
        if p is not None and q.dot(p) < 0.0:
            q = -q
            pb.rotation_quaternion = q
        _prev[pb.name] = q
    L.key(f)


def body(yaw, lean, drop, back=0.1, side=0.0, waist_yaw=0.0, waist_bend=0.0, waist_tilt=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_tilt))


def gap():
    return round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 3)


def bend():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


def summary(info, **extra):
    d = {"reach": round(info.get("arm_overreach", 0.0), 3), "bend": round(bend(), 1), "gap": gap(),
         "low": round(L.launcher_lowest_y(), 2)}
    d.update(extra)
    return d


_VS = []


def sink(launcher=False):
    """static motion-audit check of the current pose: (arm depth in the torso/head, launcher depth)"""
    L.update()
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    wa = 0.0
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for bn in ("UpperTorso", "Head", "LowerTorso"):
                        wa = max(wa, L._depth_inside(pt, *boxes[bn]))
    wl = 0.0
    if launcher:
        lob = L.launcher_object()
        if not _VS:
            vs = [v.co.copy() for v in lob.data.vertices]
            _VS.extend(vs[::max(1, len(vs) // 200)])
        mw = lob.matrix_world
        for co in _VS:
            pt = L.b2r(mw @ co)
            for bn in ("UpperTorso", "Head"):
                wl = max(wl, L._depth_inside(pt, *boxes[bn]))
    return wa, wl


def search_hold(at, yaw, elev, roll=0.0, anchor="Pivot", lcheck=False):
    """transitional poses: pick the right / left elbow that keeps the wrist natural + both hands on
    + no forearm sunk in the chest (the motion audit's avatar boxes)"""
    best = None
    for e in RE:
        info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor=anchor, elbow_away=e, grip_twist=GT)
        for le in LE:
            L.left_hand_to(key="Grip2", elbow_away=le)
            hits = 0.0
            for p in (L.joint("RightLowerArm"), L.joint("LeftLowerArm")):
                cl, _ = L.clearance(p, skip=ARM)
                hits += max(0.0, 0.15 - cl)
            wa, wl = sink(lcheck)
            c = bend() + 300 * info["arm_overreach"] + 150 * gap() + 200 * hits + 25.0 * (e - PREV_E[0]).length \
                + 400 * max(0.0, wa - 0.1) + 400 * max(0.0, wl - 0.05)
            if best is None or c < best[0]:
                best = (c, e, le)
    _, e, le = best
    PREV_E[0] = e
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor=anchor, elbow_away=e, grip_twist=GT)
    L.left_hand_to(key="Grip2", elbow_away=le)
    wa, wl = sink(True)
    return summary(info, re=[round(v, 2) for v in e], le=[round(v, 2) for v in le], sink=[round(wa, 2), round(wl, 2)])


# ------------------------------------------------------------------ poses
def upright(b=0.0, s=0.0, bkw=None, head=None):
    """the ballista upright at the right shoulder; b breathing 0..1, s weight shift -1..1"""
    kw = dict(yaw=8.0 + 4.0 * s, lean=1.5 + 2.5 * b, drop=0.12 + 0.05 * b, back=0.02, side=0.1 * s,
              waist_yaw=4.0 - 2.0 * s, waist_bend=2.0 + 2.5 * b, waist_tilt=-1.5 * s)
    if bkw:
        kw.update(bkw)
    body(**kw)
    P = UP_P + Vector((0.04 * s, 0.1 * b, 0.0))
    info = L.hold(P, yaw=-10.0 + 3.0 * s, elev=69.0 - 1.5 * b, roll=2.0 * s, elbow_away=RE_UP, grip_twist=GT)
    L.arm_to("Left", HIP + Vector((0.0, 0.04 * b, 0.0)), HIP_LE)
    L.head_look(target=head or (-8.0, 1.9 + 0.3 * b, -4.0 - 2.0 * s))
    return summary(info)


def aim_body(depth, b=0.0, extra=None):
    kw = dict(yaw=AY + 2.0 * depth, lean=-8.0 + 10.5 * depth - 4.0 * b, drop=0.32 + 0.3 * depth + 0.10 * b,
              back=-0.15 - 0.05 * depth, side=HI_SIDE * depth, waist_yaw=4.0 - HI_WYAW * depth, waist_bend=-3.0 + 15.0 * depth,
              waist_tilt=8.0 - HI_TILT * depth)
    if extra:
        kw.update(extra)
    body(**kw)


def aim(depth, b=0.0, s=0.0, tr=(0.0, 0.0), body_kw=None, head=None, roll=0.0, pull=0.0):
    """depth 0 = ChargeLo, 1 = ChargeHi; b breathing 0..1, s sway -1..1, tr tremor (y, z)"""
    aim_body(depth, b, body_kw)
    seat = (X_AIM + 0.03 * s, Y_AIM - 0.2 * depth + 0.18 * b + tr[0], Z_AIM + (0.25 + pull) * depth + 0.05 * s + tr[1])
    elev = 3.0 + 2.0 * depth + 1.0 * b + 11.0 * tr[0]
    info = L.hold(seat, yaw=0.0 + 1.5 * s, elev=elev, roll=roll, anchor="Seat", elbow_away=RE_AIM, grip_twist=GT)
    res = []
    for n, le in enumerate(LE_TRY):
        L.left_hand_to(key="Grip2", elbow_away=le)
        res.append((gap(), n))
    LAST_LE[0] = 0 if res[0][0] <= min(res)[0] + 0.03 else min(res)[1]   # keep LE_AIM unless it cannot reach
    L.left_hand_to(key="Grip2", elbow_away=LE_TRY[LAST_LE[0]])
    L.head_look(target=head or AIM_TARGET)
    L.set_rot("Head", L.get_rot("Head") @ L.rz(-CHEEK))   # cheek laid onto the stock (tilt to the right)
    return summary(info, le=LAST_LE[0], gaps=[round(g, 2) for g, _ in res])


# one fixed grip for every clip (solved in the aim pose), so nothing slides in the hand
body(yaw=21.0, lean=-6.0, drop=0.47, back=-0.175, waist_yaw=14.0, waist_bend=2.0, waist_tilt=8.0)  # the round-1 reference body
L.hold((-1.5, Y_AIM, -1.7), yaw=0.0, elev=3.0, anchor="Seat", elbow_away=(0.14, -0.7, 0.7))
GT = L.get_rot("Launcher") @ L.ry(12.0)   # a little more grip twist: keeps the right wrist under ~60 deg

# ------------------------------------------------------------------ Ready
new_clip("Ready")
N = int(round(SPEC["Ready"] * 30))
for f in range(0, N, 6):
    ph = f / N
    b = 0.5 - 0.5 * math.cos(2.0 * math.pi * 2.0 * ph)
    s = math.sin(2.0 * math.pi * ph)
    report["ready_%d" % f] = upright(b, s)
    K(f)
upright(0.0, 0.0); K(N)
L.make_cyclic("Ready")

# ------------------------------------------------------------------ charge loops (same keys, same phase)
NC = int(round(SPEC["ChargeLo"] * 30))


def tremor(i):
    a = 0.7 * math.sin(2.0 * math.pi * 6.0 * i / 18.0) + 0.3 * math.sin(2.0 * math.pi * 3.0 * i / 18.0 + 1.0)
    c = 0.6 * math.cos(2.0 * math.pi * 5.0 * i / 18.0) + 0.4 * math.sin(2.0 * math.pi * 7.0 * i / 18.0)
    r = math.sin(2.0 * math.pi * 4.0 * i / 18.0 + 0.5)
    return a, c, r


def trem(depth, i):
    a, c, r = tremor(i)
    return (0.14 * depth * a, 0.12 * depth * c), 1.0 * depth * r


for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    new_clip(kind)
    for i in range(18):
        f = i * 2
        ph = f / NC
        b = 0.5 - 0.5 * math.cos(2.0 * math.pi * ph)
        s = math.sin(2.0 * math.pi * ph)
        amp = 1.0 + 0.4 * depth
        tr, rl = trem(depth, i)
        report["%s_%d" % (kind, f)] = aim(depth, b * amp, s * amp, tr, roll=rl, pull=0.07)
        if i in (0, 4, 9, 13):
            print("REPORT pose head %s %d %s %s" % (kind, f, [round(v, 2) for v in L.joint("Head")], report["%s_%d" % (kind, f)]))
        K(f)
    tr, rl = trem(depth, 0)
    aim(depth, 0.0, 0.0, tr, roll=rl, pull=0.07); K(NC)
    L.make_cyclic(kind)

# ------------------------------------------------------------------ Fire
new_clip("Fire")
tr, rl = trem(1.0, 0)
report["f0"] = aim(1.0, 0.0, 0.0, tr, roll=rl, pull=0.07); K(0)                             # 0.00 the charge pose
SQ = dict(lean=-7.0, drop=0.66, back=-0.12, side=0.0, waist_yaw=4.0, waist_bend=-3.0, waist_tilt=9.0)
CHIN = (-14.0, 0.9, Z_AIM + 0.2)
report["f3"] = aim(1.0, body_kw=SQ, head=CHIN); K(3)                             # 0.10 brace: sink, chest in, chin tucked
report["f5"] = aim(1.0, body_kw=SQ, head=CHIN); K(5)                             # 0.17 THUNK: the ball leaves
P0 = L.pivot_cf().translation.copy()
G0 = L.launcher_point(G2)
Seat0 = L.launcher_point(META["Seat"]["pos"])


def shoulders():
    return (L.joint("RightUpperArm") + L.joint("LeftUpperArm")) * 0.5


S0 = shoulders()
# 0.27 RECOIL: the ballista bucks up and back, the weight drives back onto the rear (right) foot, hips stay low
aim_body(1.0, 0.0, dict(yaw=AY + 2.0, lean=8.0, drop=0.62, back=0.2, side=0.14, waist_yaw=4.0, waist_bend=10.0, waist_tilt=4.0))
report["kick"] = search_hold(G0 + (shoulders() - S0) + Vector((0.14, 0.5, -0.25)), 0.0, 20.0, anchor="Grip2")
L.head_look(target=(-12.0, 5.0, -1.0)); K(8)
# 0.43 furthest back
aim_body(1.0, 0.0, dict(yaw=AY + 2.0, lean=11.0, drop=0.6, back=0.26, side=0.2, waist_yaw=4.0, waist_bend=12.0, waist_tilt=3.0))
report["rock"] = search_hold(G0 + (shoulders() - S0) + Vector((0.16, 0.62, -0.3)), 0.0, 25.0, anchor="Grip2")
L.head_look(target=(-12.0, 5.5, -1.0)); K(13)
# 0.67 regal recovery: upright, proud, the aim comes back level, watching the ball go
aim_body(0.5, 0.0, dict(lean=-3.0, drop=0.3, back=-0.08, side=0.0, waist_yaw=4.0, waist_bend=1.0, waist_tilt=8.0))
report["recover"] = search_hold(G0 + (shoulders() - S0) + Vector((0.05, 0.05, 0.0)), 0.0, 7.0, anchor="Grip2")
L.head_look(target=(-14.0, 2.0, -1.0)); K(20)
# 1.07 swinging the ballista up toward the shoulder
body(yaw=(AY + 8.0) * 0.5, lean=-2.0, drop=0.2, back=0.0, waist_yaw=9.0, waist_bend=0.0)
# the left hand lets go and returns to the hip; the ballista turns its nose out front so the stock
# and bow arms swing past the face instead of through it
best = None
for e in RE:
    info = L.hold((P0 + UP_P) * 0.5 + Vector((0.0, 0.15, 0.0)), yaw=45.0, elev=25.0, elbow_away=e, grip_twist=GT)
    L.arm_to("Left", HIP + Vector((0.1, 0.15, -0.2)), HIP_LE)
    wa, wl = sink(True)
    c = bend() + 300 * info["arm_overreach"] + 400 * max(0, wa - 0.1) + 400 * max(0, wl - 0.05) + 25.0 * (e - PREV_E[0]).length
    if best is None or c < best[0]:
        best = (c, e)
info = L.hold((P0 + UP_P) * 0.5 + Vector((0.0, 0.15, 0.0)), yaw=45.0, elev=25.0, elbow_away=best[1], grip_twist=GT)
L.arm_to("Left", HIP + Vector((0.1, 0.15, -0.2)), HIP_LE)
report["swing"] = summary(info, re=[round(v, 2) for v in best[1]], sink=[round(v, 2) for v in sink(True)])
L.head_look(target=(-10.0, 2.0, -2.0)); K(32)
report["near"] = upright(0.3, 0.0); K(40)                                       # 1.33
upright(0.0, 0.0); K(48)                                                         # 1.60 back to Ready
# in-betweens: keep the left hand on the fore-end while the ballista swings back up
L.use_clip("Fire")
for f in (2, 24):
    L.goto(f / 30.0)
    q0 = {pb.name: pb.rotation_quaternion.copy() for pb in L.rig().pose.bones}
    L.left_hand_to(key="Grip2", elbow_away=(-0.6, -0.8, -0.2))
    for pb in L.rig().pose.bones:          # stay in the sampled hemisphere (no long-way-round flips)
        if pb.rotation_quaternion.dot(q0[pb.name]) < 0.0:
            pb.rotation_quaternion = -pb.rotation_quaternion
    L.key(f)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in report.items():
    if not k[-1].isdigit() or k.endswith("_0") or k in ("f0", "f3", "f5"):
        print("REPORT pose %s %s" % (k, json.dumps(v)))
L.finish(SPEC, OUT, extra_times=[0.1, 0.27, 0.43, 0.67, 1.07])

# diagnostics: left-hand gap / wrist over the Fire clip
L.use_clip("Fire")
row = []
for i in range(0, int(round(SPEC["Fire"] * 30)) + 1, 2):
    L.goto(i / 30.0)
    row.append("%d:%.2f/%.0f" % (i, gap(), bend()))
print("REPORT pose firegap " + " ".join(row))
