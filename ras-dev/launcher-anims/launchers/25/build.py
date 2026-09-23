"""25 Aurora Prism -- a magical prism: aurora crystals on a small pale frame with curly handles.

Concept: a spell focus held with both hands (right hand on the grip, left hand under the frame at
Grip2), always on the character's FRONT side (screen-right in the pad camera) so the crystals and
the figure-eight read from the game camera.
  Ready    held gently in front of the belly, crystals up, a slow magical FLOAT: the prism bobs,
           drifts and rolls softly while the body breathes.
  ChargeLo BOTH hands carry the prism along a small figure-eight while the prism swings like a
           wand, so the crystal tip traces a big flowing FIGURE-EIGHT (lying 8, in the pad
           camera's screen plane); the hips sway with the lobes.
  ChargeHi the same 8 in the same phase, WIDER and deeper (lower stance, more body sway) with a
           readable shimmer tremble of energy on top.
  Fire     gather it back (coil away, weight on the back foot, tip lifted) -> both hands THRUST
           it out down the track like casting a spell, the body turning into it and the weight
           onto the down-track foot (FireAt: the ball pops out of the crystal muzzle) -> small
           overshoot -> soft recoil (tip floats up) -> a graceful floating settle into Ready.
Ball: hidden until it comes out of the Muzzle (crystal tip).

Round 2 (elbow guard / motion audit): the grip (pivot) is now placed RELATIVE TO THE RIGHT
SHOULDER (ox, oy, oz), so the right wrist always stays ~0.2+ studs inside full reach whatever
the body does; elbow poles are UP-ish (natural down-and-out elbows, no guard mirroring).
Round 2b: Grip2 was up to 2.08 studs from the left shoulder (left arm locked straight -> 35 deg
LeftLowerArm snaps): body yaw toward the track reduced in Ready/charge (the left shoulder comes
forward) + a smooth left-reach soft clamp in apply() (LT/LW); gentler charge bow; the thrust
climbs (tip 19 -> 14 -> 17 deg, no dip) and the coil holds f3-f4 before the 3-frame cast.
Polish 2: ONE foot set for all clips (no skate in the Lo/Hi blend or the Fire settle); the HANDS
now carry the 8 (CHG_A ~0.2 / 0.3 studs, hand travel Lo 0.41 x 0.36, Hi 0.52 x 0.72 studs, see
<clip>_hand_box_zy): centre moved in toward the left shoulder, the counter body-yaw sway cut
(it was cancelling the hand travel), the 8 tilted (front lobe high = inside left reach, back lobe
low = clear of the head); Hi tremble 0.06 studs / 7 deg; Ready bob +-0.11 with the roll lagging a
quarter cycle; head swing halved; Fire gather lifts + sits further out, cast pushes out and a
little down with a harder body lean/turn (lean -16, yaw 14).
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

LID = 25
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_F = 7
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.5,
    "FireAt": round(FIRE_F / 30.0, 3),
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "spark", "Color": [170, 255, 200], "Charge": "spark", "ChargeColor": [255, 160, 230]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "aurora prism: both hands trace a figure-eight spell while charging, then a body-driven two-handed cast out of the crystal tip",
}
# ONE planted foot set for every clip (Lo/Hi blend by the live charge and the Fire settle must
# never slide the feet); Hi depth shows only through hip_drop, hip_back and lean.
FEET = {"Left": (-0.95, -0.4), "Right": (0.75, 0.5)}
ELB = (-0.3, 1.0, 0.1)
L_ELB = (0.3, 1.0, 0.1)
QREF = None
MAXW = 65.0
REACH = math.sqrt(L.ARM_SIDE_OFFSET ** 2 + (L.UPPER_ARM + L.LOWER_ARM) ** 2)
report = {}
MUZ = L.load_meta(LID)["Muzzle"]["pos"]
G2 = L.load_meta(LID)["Grip2"]["pos"]
LT, LW = 1.72, 0.08            # left shoulder -> Grip2 soft limit (studs) and its soft zone

# pivot offsets from the right shoulder (HRP axes)
RDY_O = (-0.82, -1.34, -0.88)
CHG_O = ((-0.95, -1.15, -0.9), (-0.98, -1.12, -0.96))     # Lo, Hi centre
CHG_A = ((0.22, 0.16), (0.32, 0.24))                      # hand 8: (z, y) amplitude Lo, Hi
CHG_W = ((10.0, 8.0), (15.0, 13.0))                       # wand swing: (yaw, elev) Lo, Hi

# one pose = a dict of numbers.  (ox, oy, oz) = where the grip (pivot) goes RELATIVE to the right
# shoulder; the left hand follows onto Grip2, so the whole prism moves with BOTH hands.
BASE = dict(yaw=10.0, lean=-8.0, drop=0.2, back=0.1, side=0.0, wyaw=2.0, wbend=-5.0, depth=0.0,
            ox=RDY_O[0], oy=RDY_O[1], oz=RDY_O[2], ayaw=10.0, aelev=4.0, roll=22.0,
            lx=-8.0, ly=0.5, lz=-2.0)


def lerp(a, b, t):
    return a + (b - a) * t


def P(**kw):
    d = dict(BASE)
    d.update(kw)
    return d


def apply(p):
    L.reset_pose()
    feet = FEET
    L.stance(hip_drop=p["drop"], hip_back=p["back"], hip_side=p["side"],
             root=L.ry(p["yaw"]) @ L.rx(p["lean"]), feet=feet)
    L.waist(L.ry(p["wyaw"]) @ L.rx(p["wbend"]))
    sh = L.joint("RightUpperArm")
    pv = sh + Vector((p["ox"], p["oy"], p["oz"]))
    info = L.hold(pv, yaw=p["ayaw"], elev=p["aelev"], roll=p["roll"],
                  elbow_away=ELB, grip_twist=QREF, max_wrist=MAXW)
    # LEFT REACH: Grip2 must stay ~0.15 inside the left arm's reach, or the left elbow snaps
    # between straight and bent.  A smooth (C1) soft clamp slides the whole prism toward the
    # left shoulder by the excess, so the figure-eight just flattens a little at its far end.
    lsh = L.joint("LeftUpperArm")
    for _ in range(2):
        g = L.launcher_point(G2) - lsh
        d = g.length
        if d <= LT - LW:
            break
        fd = LT - LW * math.exp(-(d - (LT - LW)) / LW)
        pv = pv - g.normalized() * (d - fd)
        info = L.hold(pv, yaw=p["ayaw"], elev=p["aelev"], roll=p["roll"],
                      elbow_away=ELB, grip_twist=QREF, max_wrist=MAXW)
    info["lgap"] = L.left_hand_to(key="Grip2", elbow_away=L_ELB)[0]
    L.head_look(target=(p["lx"], p["ly"], p["lz"]))
    info["muz"] = L.launcher_point(MUZ)
    info["sw"] = round(swing(), 1)
    info["rm"] = round(REACH - (L.joint("RightHand") - L.joint("RightUpperArm")).length - info["arm_overreach"], 3)
    info["lm"] = round(REACH - (L.joint("LeftHand") - L.joint("LeftUpperArm")).length - info["lgap"], 3)
    return info


def catmull(keys, f):
    """keys = [(frame, pose)], Catmull-Rom through the numbers, clamped ends"""
    fs = [k[0] for k in keys]
    i = 0
    while i < len(keys) - 2 and f > fs[i + 1]:
        i += 1
    f0, f1 = fs[i], fs[i + 1]
    s = (f - f0) / float(f1 - f0)
    out = {}
    for name in BASE:
        v0, v1 = keys[i][1][name], keys[i + 1][1][name]
        m0 = 0.0 if i == 0 else (v1 - keys[i - 1][1][name]) / (f1 - fs[i - 1]) * (f1 - f0)
        m1 = 0.0 if i + 2 >= len(keys) else (keys[i + 2][1][name] - v0) / (fs[i + 2] - f0) * (f1 - f0)
        s2, s3 = s * s, s * s * s
        out[name] = (2 * s3 - 3 * s2 + 1) * v0 + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * v1 + (s3 - s2) * m1
    return out


# ------------------------------------------------------------------ pose families
def charge_pose(ph, depth, tremble=True):
    """ph 0..1 around the figure-eight, depth 0 (Lo) .. 1 (Hi).
    s = lobe (+ = out toward the character's front, screen-right), v = the crossing (two ups
    per loop = the 8).  The hands move in a small 8 and the prism swings like a wand (yaw with
    the lobes, pitch with the crossing), so the crystal tip draws a big lying 8."""
    th = 2.0 * math.pi * ph
    s = math.sin(th)
    v = math.sin(2.0 * th)
    o = [lerp(CHG_O[0][i], CHG_O[1][i], depth) for i in range(3)]
    az, ay = lerp(CHG_A[0][0], CHG_A[1][0], depth), lerp(CHG_A[0][1], CHG_A[1][1], depth)
    wy, we = lerp(CHG_W[0][0], CHG_W[1][0], depth), lerp(CHG_W[0][1], CHG_W[1][1], depth)
    jy = jr = 0.0
    if tremble and depth > 0:
        jy = 0.06 * depth * math.sin(2.0 * math.pi * 6.0 * ph)
        jr = 7.0 * depth * math.sin(2.0 * math.pi * 6.0 * ph + 1.3)
    return P(yaw=-2.0 - 2.0 * depth - (3.0 + 1.0 * depth) * s, lean=-8.0 - 2.0 * depth - 1.0 * v - 2.0 * s,
             drop=0.22 + 0.28 * depth + 0.03 * v, back=0.1 + 0.08 * depth, side=-0.06 * s,
             wyaw=0.0 - 1.5 * s, wbend=-4.5 - 1.0 * depth - 1.0 * v, depth=depth,
             ox=o[0], oy=o[1] + ay * v + lerp(0.1, 0.2, depth) * s + jy, oz=o[2] - az * s,
             ayaw=5.0 + wy * s, aelev=9.0 + we * v + lerp(3.0, 6.0, depth) * s, roll=32.0 + lerp(12.0, 16.0, depth) * s + jr,
             lx=-7.0, ly=0.4 + 0.5 * v, lz=-2.6 - 1.1 * s)


def ready_pose(ph):
    """slow float: bob twice per loop, lateral drift once, a soft roll"""
    th = 2.0 * math.pi * ph
    b = math.sin(th)
    c = math.sin(2.0 * th)
    cl = -math.cos(2.0 * th)          # the bob a quarter cycle later: the roll lags the float
    return P(yaw=3.0 + 2.0 * b, lean=-7.0 + 1.5 * c, drop=0.14 + 0.03 * c, back=0.08,
             wyaw=-1.0 + 2.0 * b, wbend=-5.0 + 1.5 * c,
             ox=RDY_O[0] + 0.03 * b, oy=RDY_O[1] + 0.11 * c, oz=RDY_O[2] - 0.05 * b,
             ayaw=12.0 + 4.0 * b, aelev=2.0 + 4.0 * cl, roll=31.0 - 5.0 * b + 6.0 * cl,
             lx=-3.0, ly=-0.3 + 0.3 * c, lz=-3.5)


def avg_q(qs):
    from mathutils import Quaternion
    acc = Quaternion((0.0, 0.0, 0.0, 0.0))
    for q in qs:
        if q.dot(qs[0]) < 0:
            q = -q
        acc = Quaternion((acc.w + q.w, acc.x + q.x, acc.y + q.y, acc.z + q.z))
    acc.normalize()
    return acc


def natural_q(fn, n=12):
    """average free-grip Launcher turn over a pose family (wrist kept straight)"""
    global QREF, MAXW
    QREF, MAXW = None, 0.0
    qs = []
    for i in range(n):
        apply(fn(i / float(n)))
        qs.append(L.get_rot("Launcher").copy())
    MAXW = 65.0
    return avg_q(qs)


def swing():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


def max_swing(fn, q, n=12):
    global QREF
    QREF = q
    m = 0.0
    for i in range(n):
        apply(fn(i / float(n)))
        m = max(m, swing())
    return round(m, 1)


FAM = {"R": ready_pose, "Lo": lambda ph: charge_pose(ph, 0.0), "Hi": lambda ph: charge_pose(ph, 1.0)}
# ONE fixed grip for everything: the average natural (straight-wrist) grip over Ready, Lo and Hi,
# so the prism never turns in the hand and the wrist bends are balanced around it.
QREF = avg_q([natural_q(f) for f in FAM.values()])
report["qref_max_swing"] = {k: max_swing(f, QREF) for k, f in FAM.items()}
print("REPORT QREF", [round(v, 3) for v in QREF], report["qref_max_swing"])

# ------------------------------------------------------------------ Fire keys
c0 = charge_pose(0.0, 1.0, tremble=False)
fire_keys = [
    (0, c0),
    # 0.10 GATHER: drawn back in, tip lifted, body coiled away, weight on the back foot
    (3, P(yaw=2.0, lean=-4.0, drop=0.48, back=0.16, side=0.18, wyaw=-5.0, wbend=-2.0, depth=1.0,
          ox=-0.44, oy=-1.03, oz=-1.0, ayaw=6.0, aelev=19.0, roll=30.0, lx=-7.0, ly=1.2, lz=-2.2)),
    # 0.13 hold the coil a breath longer (the anticipation reads), tip still lifted
    (4, P(yaw=1.5, lean=-4.0, drop=0.49, back=0.17, side=0.19, wyaw=-5.5, wbend=-2.0, depth=1.0,
          ox=-0.5, oy=-1.01, oz=-1.03, ayaw=6.0, aelev=20.0, roll=30.0, lx=-7.0, ly=1.2, lz=-2.2)),
    # 0.23 CAST (FireAt): both arms thrust it out down the track, weight onto the down-track foot
    (FIRE_F, P(yaw=14.0, lean=-16.0, drop=0.45, back=0.02, side=-0.2, wyaw=4.0, wbend=-7.0, depth=1.0,
               ox=-0.86, oy=-1.12, oz=-0.9, ayaw=0.0, aelev=14.0, roll=52.0, lx=-10.0, ly=0.8, lz=-1.6)),
    # overshoot: the arms keep going a hair
    (9, P(yaw=14.5, lean=-16.5, drop=0.46, back=0.02, side=-0.22, wyaw=5.0, wbend=-8.0, depth=1.0,
          ox=-0.9, oy=-1.08, oz=-0.9, ayaw=1.0, aelev=17.0, roll=54.0, lx=-12.0, ly=1.2, lz=-1.5)),
    # soft recoil: the tip floats up, hands ease back
    (12, P(yaw=12.0, lean=-12.0, drop=0.42, back=0.05, side=-0.16, wyaw=4.0, wbend=-5.0, depth=1.0,
           ox=-0.84, oy=-1.06, oz=-0.84, ayaw=3.0, aelev=22.0, roll=46.0, lx=-13.0, ly=1.5, lz=-1.4)),
    # hang: watching the ball go, the prism held out, a graceful float
    (18, P(yaw=8.0, lean=-8.0, drop=0.32, back=0.08, side=-0.08, wyaw=3.0, wbend=-5.0, depth=0.8,
           ox=-0.86, oy=-1.2, oz=-0.8, ayaw=6.0, aelev=14.0, roll=38.0, lx=-14.0, ly=1.0, lz=-1.2)),
    # drift down, turning back toward the front
    (27, P(yaw=8.0, lean=-7.5, drop=0.2, back=0.08, side=-0.02, wyaw=1.5, wbend=-5.0, depth=0.4,
           ox=-0.8, oy=-1.32, oz=-0.76, ayaw=11.0, aelev=4.0, roll=32.0, lx=-8.0, ly=0.0, lz=-3.0)),
    (36, ready_pose(0.1)),
    (45, ready_pose(0.0)),
]

def left_diag():
    sh = L.joint("LeftUpperArm")
    Mi = L.frame_of("UpperTorso").inverted()
    d = Mi @ (L.joint("LeftHand") - sh)
    n = (d.normalized()).cross(Mi @ Vector(L_ELB))
    n.normalize()
    bend = math.degrees(L.get_rot("LeftLowerArm").angle)
    g = L.launcher_point(L.load_meta(LID)["Grip2"]["pos"]) - sh
    return round(bend, 1), tuple(round(x, 2) for x in g), round(g.length, 2)


if os.environ.get("DIAG25") == "2":
    for f in range(0, 36):
        r = apply(charge_pose(f / 36.0, 1.0))
        print("REPORT D Hi", f, left_diag(), r["lm"], r["rm"])
    for f in range(0, 46):
        r = apply(catmull(fire_keys, f))
        print("REPORT D Fire", f, left_diag(), r["lm"], r["rm"])
    raise SystemExit
if os.environ.get("DIAG25"):
    for nm, fn in FAM.items():
        for i in range(0, 12, 1):
            r = apply(fn(i / 12.0))
            hp = L.joint("RightHand")
            print("REPORT POSE D", nm, i, {k: r[k] for k in ("rm", "lm", "sw")}, "hand zy", round(hp.z, 2), round(hp.y, 2))
    for f, p in fire_keys:
        r = apply(p)
        print("REPORT POSE D Fire", f, {k: r[k] for k in ("rm", "lm", "sw", "grip_turn_deg")})
    raise SystemExit


def keyed_loop(kind, n, fn, step=2):
    L.new_clip(kind)
    zs, ys, hz, hy = [], [], [], []
    for f in range(0, n, step):
        r = apply(fn(f / float(n)))
        zs.append(r["muz"].z)
        ys.append(r["muz"].y)
        hz.append(L.joint("RightHand").z)
        hy.append(L.joint("RightHand").y)
        if f % 6 == 0:
            report["%s_%d" % (kind, f)] = {k: r[k] for k in ("arm_overreach", "lgap", "wrist_bend_deg", "rm", "lm")}
        L.key(f)
    apply(fn(0.0))
    L.key(n)
    L.make_cyclic(kind)
    report["%s_muzzle_box_zy" % kind] = (round(max(zs) - min(zs), 2), round(max(ys) - min(ys), 2))
    report["%s_hand_box_zy" % kind] = (round(max(hz) - min(hz), 2), round(max(hy) - min(hy), 2))


keyed_loop("Ready", int(SPEC["Ready"] * 30), ready_pose, step=3)
keyed_loop("ChargeLo", int(SPEC["ChargeLo"] * 30), lambda ph: charge_pose(ph, 0.0), step=2)
keyed_loop("ChargeHi", int(SPEC["ChargeHi"] * 30), lambda ph: charge_pose(ph, 1.0), step=1)

L.new_clip("Fire")
for f in range(0, 46):
    r = apply(catmull(fire_keys, f))
    if f in (0, 3, 4, FIRE_F, 9, 12, 18, 27):
        report["Fire_%d" % f] = {k: r[k] for k in ("arm_overreach", "lgap", "wrist_bend_deg", "rm", "lm")}
    L.key(f)
L.set_interpolation("Fire", 'LINEAR', 'AUTO_CLAMPED')

for k, v in report.items():
    print("REPORT POSE", k, v)
L.finish(SPEC, OUT, extra_times=[4 / 30.0, 9 / 30.0, 12 / 30.0, 18 / 30.0])
