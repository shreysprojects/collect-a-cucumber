"""18 Thunder Coil -- blue energy gun, two copper coil rings with a zigzag lightning arc between
them; the ball is shot out through the rings.

The player stands side-on on the pad (down-track = their LEFT, away from the camera); the gun is
carried on the character's FRONT side (screen-right) so the pad camera sees it.
  Ready    a loose low carry in front of the hips (muzzle angled at the floor ahead, left palm
           under the barrel, both elbows bent); easy breathing, and three times per loop the coil
           "zaps" the holder: a quick 2-3 frame twitch (gun jerks up, shoulders flinch, the head
           pops up and cocks) that dies straight back down.
  ChargeLo raised and aimed down the track, canted 30 deg (coil tops rolled out, away from the
           face), left palm steadying under the barrel, head cocked to sight along it; the whole
           body trembles with a high-frequency buzz (keyed every frame) plus two slow surges per
           loop.  The gun is carried RIGIDLY by the trembling upper body, so body, arms and gun
           shake as one piece; both elbows stay bent (targets well inside reach -> no IK pops).
  ChargeHi the same buzz / surges, much stronger, in a deeper crouch.
  Fire     the tension squeezes down for a beat -> crisp DISCHARGE at FireAt (the ball leaves
           through both rings) -> sharp kick: the gun slides back + snaps up, the body jolts
           upright -> a short after-buzz -> relax to the hip carry.
Design rules of this script: the gun sits in the right hand with ONE fixed grip rotation in every
pose (no launcher turning in the hand), and every gun target is an offset from the RIGHT SHOULDER
of the pose (so the arms keep the same bend whatever the body does).
Ball: appears (0.08 s) in the Seat just behind the rear coil and is shot out through BOTH rings at
FireAt.  Yellow spark burst, blue sparks while charging.
"""
import importlib
import math
import os
import random
import sys

from mathutils import Vector

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)

LID = 18
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.2,
    "FireAt": 0.13, "BallAppearAt": 0.08,
    "Ball": {"show": "Fire", "start": "Seat"},     # charges up behind the rear coil, shot through both rings
    "Fx": {"Style": "spark", "Color": [255, 240, 120], "Charge": "spark", "ChargeColor": [140, 200, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "thunder coil: low two-handed hip carry with electric twitches, aimed + whole-body buzzing tremble while charging, crisp discharge kick + jolt",
}
FEET = {"Left": (-0.95, -0.4), "Right": (0.7, 0.25)}
TRACK_LOOK = (-12.0, 0.3, -1.6)
R_POLE = (-0.3, 1.0, 0.1)       # UP-ish poles: elbows hang down and out
L_POLE = (0.3, 1.0, 0.1)
report = {}


def body(yaw=15.0, lean=-8.0, drop=0.25, back=0.1, waist_yaw=4.0, waist_bend=-8.0, side=0.0, roll=0.0,
         waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def shoulder():
    return L.joint("RightUpperArm").copy()


def torso():
    """UpperTorso (joint position, rotation) -- to carry the gun with a trembling body"""
    return L.joint("UpperTorso").copy(), L.frame_of("UpperTorso").copy()


# ------------------------------------------------------------------ the one grip
# the launcher's turn in the right hand, solved once in the calm ChargeLo aim (wrist <= 40 deg)
# and then used for EVERY pose: the gun never slides around in the hand
CALM_LO = dict(yaw=8.0, lean=-10.0, drop=0.35, back=0.12, waist_yaw=-8.0, waist_bend=-10.0)
body(**CALM_LO)
_f = L.direction(6.0, 4.0)
L.place_launcher(at=shoulder() + Vector((-0.4, -1.3, -1.15)), forward=_f, up=L.up_for(_f, 30.0), anchor="Pivot",
                 elbow_away=R_POLE, max_wrist=40.0)
GQ = L.get_rot("Launcher").copy()


def gun(off, yaw, elev, roll=0.0, carry=None, sh=None):
    """grip (Pivot) at right shoulder + off, looking along direction(yaw, elev), rolled.
    carry = (torso() of the calm pose, torso() of the shaking pose): the target and the aim move
    rigidly with the upper body, so the buzz shakes body + arms + gun as one piece"""
    fwd = L.direction(yaw, elev)
    up = L.up_for(fwd, roll)
    at = (sh if sh is not None else shoulder()) + Vector(off)
    if carry is not None:
        (j0, R0), (j1, R1) = carry
        R = R1 @ R0.inverted()
        at = j1 + R @ (at - j0)
        fwd, up = R @ fwd, R @ up
    info = L.place_launcher(at=at, forward=fwd, up=up, anchor="Pivot", elbow_away=R_POLE, grip_twist=GQ)
    info["r_elbow"] = round(math.degrees(L.get_rot("RightLowerArm").angle))
    return info


G2 = L.load_meta(LID)["Grip2"]["pos"]
PALM = (0.0, 1.0, 0.0)       # left palm up under the barrel (steadying hand)


def left(offset=(0.0, 0.0, 0.0)):
    """left palm up under the barrel at Grip2; the palm turn moves the hand centre, so the
    target is corrected a few times until the hand really sits on the grip point"""
    tgt = L.launcher_point(G2) + Vector(offset)
    fix = Vector((0.0, 0.0, 0.0))
    for _ in range(4):
        err = L.left_hand_to(point=tgt + fix, elbow_away=L_POLE, palm_toward=PALM)
        fix -= L.hand_cf("Left").translation - tgt
    gap = (L.hand_cf("Left").translation - L.launcher_point(G2)).length
    elbow = math.degrees(L.get_rot("LeftLowerArm").angle)
    return {"over": err[0], "gap": round(gap, 3), "l_elbow": round(elbow)}


def look(target, tilt=0.0):
    """head toward target, then cocked sideways by tilt degrees (- = toward the gun)"""
    L.head_look(target=target)
    if tilt:
        L.set_rot("Head", L.get_rot("Head") @ L.rz(tilt))


# ------------------------------------------------------------------ poses
R_OFF = (-0.5, -1.2, -1.4)       # Ready carry: grip below / in front of the right shoulder
R_WY = -16.0                     # chest turned a little to the right: the left hand reaches the barrel


def ready(b, z=0.0):
    """b 0..1 = breathing; z 0..1 = an electric twitch (gun jerks up, shoulders flinch)"""
    body(yaw=6.0 + 1.0 * z, lean=-9.5 + 1.0 * b + 2.5 * z, drop=0.24 - 0.03 * b - 0.015 * z, back=0.08,
         waist_yaw=R_WY + 1.0 * b, waist_bend=-5.0 + 2.5 * b + 5.0 * z, waist_roll=-3.0 * z)
    info = gun((R_OFF[0], R_OFF[1] + 0.02 * b + 0.07 * z, R_OFF[2]), yaw=12.0 - 1.0 * b + 3.0 * z,
               elev=-20.0 + 2.0 * b + 12.0 * z, roll=12.0 - 5.0 * z)
    info["left"] = left()
    look((-8.0 + 1.5 * z, -0.5 + 0.5 * b + 1.2 * z, -3.0 - 0.4 * z), tilt=-7.0 * z)
    return info


# deterministic high-frequency buzz: one value set per FRAME, sign alternating every frame (15 Hz)
N = 24                              # ChargeLo/Hi length in frames (0.8 s)
rnd = random.Random(18)
BUZZ = []
for i in range(N):
    s = 1.0 if i % 2 == 0 else -1.0
    acc = (1.0, 0.7, 1.0, 0.35)[i % 4]          # a pulse rhythm: every 4th frame the buzz dips
    BUZZ.append((acc * s * rnd.uniform(0.5, 1.0), -acc * s * rnd.uniform(0.3, 1.0), acc * rnd.uniform(-1.0, 1.0)))


def surge(i):
    """slow component: two build-ups per loop (0..1), smooth and cyclic"""
    return 0.5 - 0.5 * math.cos(2.0 * math.pi * 2.0 * i / N)


C_OFF = (-0.4, -1.4, -1.4)       # aim: grip in front of / below the right shoulder (both elbows ~40 deg)
C_ROLL = 30.0                    # canted: the rear coil ring clears the jaw
C_WY = -15.0


def charge_body(i, depth, k):
    bx, by, bz = BUZZ[i % N]
    amp = 1.4 + 1.6 * depth             # buzz intensity (Lo 1.4, Hi 3.0: Lo readable, Hi ~2x)
    sg = surge(i) * (0.5 + 0.5 * depth)  # surges (shoulders tighten, gun presses forward)
    body(yaw=8.0 + 1.0 * depth + k * 1.0 * amp * bx,
         lean=-10.0 - 2.0 * depth + k * 1.5 * amp * by - 3.0 * sg,
         drop=0.35 + 0.25 * depth + k * 0.015 * amp * bz + 0.03 * sg,
         back=0.12 + 0.08 * depth,
         waist_yaw=C_WY + k * 1.2 * amp * bz,
         waist_bend=-10.0 - 3.0 * depth + k * 1.8 * amp * bx + 3.0 * sg,
         roll=k * 1.0 * amp * by, waist_roll=k * 1.2 * amp * bz)
    return amp, sg


def charge(i, depth):
    """i = frame 0..N-1 over the loop; depth 0 = ChargeLo, 1 = ChargeHi"""
    bx, by, bz = BUZZ[i % N]
    charge_body(i, depth, 0.0)
    calm, sh = torso(), shoulder()
    amp, sg = charge_body(i, depth, 1.0)
    shake = torso()
    # the gun's own buzz on top of the body's is tiny: body, arms and gun shake as ONE piece
    off = (C_OFF[0] + 0.004 * amp * bx, C_OFF[1] + 0.004 * amp * by + 0.03 * sg,
           C_OFF[2] + 0.004 * amp * bz - 0.06 * sg)
    info = gun(off, yaw=6.0 + 0.3 * amp * bz, elev=4.0 + 1.0 * depth + 0.3 * amp * bx,
               roll=C_ROLL + 0.4 * amp * by, carry=(calm, shake), sh=sh)
    info["left"] = left()
    look(TRACK_LOOK, tilt=-9.0 - 4.0 * depth + 1.5 * amp * bx)
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


# ------------------------------------------------------------------ clips
L.new_clip("Ready"); PREV.clear()
report["ready0"] = ready(0.0); key(0)
ready(0.35); key(14)
ready(0.55); key(24)
report["twitch"] = ready(0.6, 1.0); key(26)      # zap!
ready(0.61, 0.8); key(27)
ready(0.62, 0.25); key(30)
ready(0.8); key(34)
ready(0.97); key(40)
report["twitch3"] = ready(1.0, 0.8); key(43)     # a second zap, sharp
ready(0.97, 0.1); key(46)
ready(0.6); key(54)
ready(0.45, 0.6); key(56)                        # a smaller zap
ready(0.4); key(59)
ready(0.15); key(64)
ready(0.0); key(72)
L.make_cyclic("Ready")
READY_PREV = dict(PREV)

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind); PREV.clear(); PREV.update(READY_PREV)
    for i in range(N):
        r = charge(i, depth)
        if i in (0, 6, 12):
            report["%s_%d" % (kind, i)] = r
        key(i)
    charge(0, depth); key(N)
    L.make_cyclic(kind)

# Fire: every pose is a parameter set (body, grip offset from the shoulder, aim, head) and the
# frames between the keys are IK-solved too, so the arms keep their bend and the left hand
# stays on Grip2 all the way from the aim to the hip carry
HI = dict(yaw=9.0, lean=-12.0, drop=0.6, back=0.2, waist_yaw=C_WY, waist_bend=-13.0, roll=0.0, waist_roll=0.0)


def B(**kw):
    d = dict(HI)
    d.update(kw)
    return d


FIRE = [
    # 0.07 squeeze: the tension draws in, the gun steadies dead on the track
    (2, B(lean=-13.0, drop=0.64, waist_bend=-14.0),
     dict(off=(-0.4, -1.43, -1.42), yaw=5.0, elev=4.0, roll=C_ROLL), (TRACK_LOOK, -12.0)),
    # 0.13 DISCHARGE (FireAt): aimed down the track, the ball leaves through the rings
    (4, B(lean=-12.0, drop=0.62, waist_bend=-13.0),
     dict(off=(-0.4, -1.42, -1.42), yaw=4.0, elev=5.0, roll=C_ROLL), (TRACK_LOOK, -12.0)),
    # 0.20 KICK: the gun slides back along the barrel + snaps up, the body jolts upright
    (6, B(yaw=8.0, lean=-8.0, drop=0.4, waist_yaw=C_WY - 2.0, waist_bend=2.0, waist_roll=-3.0),
     dict(off=(-0.26, -1.24, -1.32), yaw=6.0, elev=20.0, roll=C_ROLL - 4.0), ((-9.0, 4.0, -1.5), -4.0)),
    # 0.30 after-buzz: a small counter-jolt down
    (9, B(yaw=9.0, lean=-11.0, drop=0.5, back=0.22, waist_yaw=C_WY - 1.0, waist_bend=-8.0, waist_roll=2.0),
     dict(off=(-0.34, -1.34, -1.38), yaw=8.0, elev=10.0, roll=C_ROLL + 3.0), ((-10.0, 1.2, -1.5), -6.0)),
    # 0.40 last flicker up
    (12, B(yaw=9.0, lean=-9.0, drop=0.45, back=0.2, waist_yaw=C_WY - 1.0, waist_bend=-5.0, waist_roll=-1.0),
     dict(off=(-0.33, -1.3, -1.36), yaw=9.0, elev=13.0, roll=C_ROLL - 2.0), ((-10.0, 1.2, -1.5), -4.0)),
    # 0.50 the gun first drops forward and down (the rear coil passes UNDER the chin)
    (15, B(yaw=8.0, lean=-10.0, drop=0.38, back=0.16, waist_yaw=C_WY - 1.0, waist_bend=-7.0),
     dict(off=(-0.45, -1.32, -1.45), yaw=10.0, elev=0.0, roll=24.0), ((-10.0, 0.4, -2.0), -2.0)),
    # 0.63 relax: the gun sinks toward the hip, weight comes back over the feet
    (19, B(yaw=7.0, lean=-10.0, drop=0.3, back=0.1, waist_yaw=R_WY, waist_bend=-6.0),
     dict(off=(-0.48, -1.24, -1.42), yaw=12.0, elev=-12.0, roll=16.0), ((-9.0, 0.0, -2.2), 0.0)),
    # 0.87 settle
    (26, B(yaw=6.2, lean=-9.6, drop=0.25, back=0.08, waist_yaw=R_WY, waist_bend=-5.2),
     dict(off=(-0.5, -1.2, -1.4), yaw=12.5, elev=-18.5, roll=12.0), ((-8.1, -0.5, -3.0), 0.0)),
    # 1.20 = ready(0.0)
    (36, B(yaw=6.0, lean=-9.5, drop=0.24, back=0.08, waist_yaw=R_WY, waist_bend=-5.0),
     dict(off=R_OFF, yaw=12.0, elev=-20.0, roll=12.0), ((-8.0, -0.5, -3.0), 0.0)),
]


def mix(a, b, t):
    if isinstance(a, (tuple, list)):
        return tuple(mix(x, y, t) for x, y in zip(a, b))
    return a + (b - a) * t


def fire_pose(A, Bk, t):
    s = L.smooth(t)
    body(**{k: mix(A[1][k], Bk[1][k], s) for k in A[1]})
    gd = {k: mix(A[2][k], Bk[2][k], s) for k in A[2]}
    info = gun(gd.pop("off"), **gd)
    info["left"] = left()
    look(mix(A[3][0], Bk[3][0], s), tilt=mix(A[3][1], Bk[3][1], s))
    return info


L.new_clip("Fire"); PREV.clear(); PREV.update(READY_PREV)
report["fire0"] = charge(0, 1.0); key(0)                      # 0.00 the ChargeHi pose
for (A, Bk) in zip(FIRE[:-1], FIRE[1:]):
    f0, f1 = A[0], Bk[0]
    step = 1 if f1 - f0 <= 3 else 2
    for f in range(f0, f1, step):
        r = fire_pose(A, Bk, (f - f0) / float(f1 - f0))
        if f == f0:
            report["fire_%d" % f] = r
        key(f)
ready(0.0); key(36)                                           # 1.20 back to the Ready carry
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in report.items():
    print("REPORT_POSE", k, v)
for kind in ("Ready", "ChargeHi", "Fire"):      # tuning aid: left-hand gap between the keys
    L.use_clip(kind)
    n = int(round(SPEC[kind] * 30))
    gaps = []
    for f in range(n + 1):
        L.goto(f / 30.0)
        gaps.append(round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 2))
    print("REPORT_GAP", kind, max(gaps), gaps)
L.finish(SPEC, OUT, extra_times=[0.07, 0.2, 0.3, 0.4])
