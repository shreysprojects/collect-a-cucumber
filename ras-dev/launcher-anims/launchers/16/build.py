"""16 Frostbite Cannon -- an icy, spiky crystal cannon, held at the hip with both hands.

The player stands side-on on the pad (down-track = their LEFT, away from the camera).  The cannon
is carried across the character's FRONT (screen-right) so the pad camera sees it end-on, the icy
muzzle pointing into the screen.
  Ready    cannon at the right hip, muzzle sagging toward the snow, slow breathing; once per loop
           a quick COLD SHIVER runs through the shoulders (the frost bites).
  ChargeLo FROST CHARGING: hunched over the cannon, aimed down the track, fast small shivers
           through the arms / upper body, steam curling at the muzzle.
  ChargeHi the same rhythm crouched deeper, head tucked, violent shivering (teeth-gritting).
  Fire     a stiff brace, then the sharp CRACK at FireAt: a quick stiff recoil (muzzle kicks up,
           body jolts back), a beat frozen, then a full-body SHUDDER (shake it off: shoulders
           roll side to side, hips wobble, decaying) and the cannon settles back to the hip.
Ball: hidden until it pops out of the muzzle (barrel launcher), icy steam burst.
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

LID = 16
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_FRAME = 6
SPEC = {
    "Ready": 3.0, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.5,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Never", "start": "Muzzle", "grow": 1.0},
    "Fx": {"Style": "steam", "Color": [200, 235, 255], "Charge": "steam", "ChargeColor": [200, 235, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "frost cannon: hip carry with a cold shiver, hunched frost-charge shivering, sharp crack + stiff recoil, full-body shudder to shake it off",
}
FEET = {"Left": (-1.0, -0.3), "Right": (0.85, 0.4)}
_E = os.environ.get
LOOK_TRACK = (-14.0, 0.3, -1.8)
R_ELBOW = tuple(float(v) for v in _E("R16_RE", "-0.3,1.0,0.3").split(","))
L_ELBOW = tuple(float(v) for v in _E("R16_LE", "0.3,1.0,0.1").split(","))

AT_OFF = (float(_E("R16_X", 0.0)), float(_E("R16_Y", 0.0)), float(_E("R16_Z", 0.0)))   # tuning hooks
ROLL = float(_E("R16_ROLL", 20.0))
YAW = float(_E("R16_YAW", -12.0))
report = {}
GRIP = None
_last = {}
SH = {}
SW = float(_E("R16_SW", 1.0))       # shoulder weight (1 = the right shoulder carries the cannon)
G2 = L.load_meta(LID)["Grip2"]["pos"]


def kf(frame):
    """keys with quaternion sign continuity (no flips between keys)"""
    for b in L.BONES:
        q = L.get_rot(b)
        if b in _last and q.dot(_last[b]) < 0.0:
            q = -q
            L.set_rot(b, q)
        _last[b] = q.copy()
    L.key(frame)


def clip(kind):
    _last.clear()
    L.new_clip(kind)


# deterministic shiver table: alternating-sign values so consecutive keys jitter against each other
SHAKE = []
for i in range(16):
    sg = 1.0 if i % 2 == 0 else -1.0
    SHAKE.append((sg * (0.6 + 0.4 * abs(math.sin(i * 2.7 + 0.3))),
                  math.sin(i * 4.1 + 1.9),
                  -sg * (0.5 + 0.5 * abs(math.sin(i * 5.3 + 0.7))),
                  math.sin(i * 3.3 + 2.4),
                  sg * (0.5 + 0.5 * abs(math.sin(i * 6.1 + 1.1)))))
ZERO = (0.0, 0.0, 0.0, 0.0, 0.0)
# the charge tremble: every term alternates with a near-constant size, so the shiver has the same
# energy all through the loop (no half where terms add and half where they cancel)
CSHAKE = []
for i in range(12):
    sg = 1.0 if i % 2 == 0 else -1.0
    CSHAKE.append((sg * (0.85 + 0.15 * math.sin(i * 2.7 + 0.3)),
                   -sg * (0.6 + 0.15 * math.sin(i * 4.1 + 1.9)),
                   -sg * (0.85 + 0.15 * math.sin(i * 5.3 + 0.7)),
                   sg * (0.5 + 0.15 * math.sin(i * 3.3 + 2.4)),
                   sg * (0.85 + 0.15 * math.sin(i * 6.1 + 1.1))))


def _dir_angles(v):
    """inverse of L.direction: (yaw, elev) of a unit vector (yaw 0 = -X, +90 = -Z)"""
    return math.degrees(math.atan2(-v[2], -v[0])), math.degrees(math.asin(max(-1.0, min(1.0, v[1]))))


RIGID_AIM = float(_E("R16_RA", 0.75))   # share of the torso's shiver rotation the cannon's aim takes
HEAD_FOLLOW = float(_E("R16_HF", 0.5))  # share of the torso's shiver the head's look target takes


def pose(yaw, lean, drop, back, waist_yaw, waist_bend, at, aim_yaw, aim_elev, look=LOOK_TRACK,
         side=0.0, waist_roll=0.0, roll=0.0, head=None, ref=None, tref=None, rigid_aim=None, **kw):
    at = (at[0] + AT_OFF[0], at[1] + AT_OFF[1], at[2] + AT_OFF[2])
    roll = roll + ROLL
    yaw = yaw + YAW
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))
    S = SW * L.joint("RightUpperArm") + (1.0 - SW) * L.joint("LeftUpperArm")
    SH["last"] = S.copy()
    SH["T"] = L.world_cf("UpperTorso").copy()
    if ref is not None:          # the cannon rides the shoulders: same offset from them as unshaken
        d = S - ref
        at = (at[0] + d[0], at[1] + d[1], at[2] + d[2])
    SH["at"] = tuple(at[i] - AT_OFF[i] for i in range(3))
    if tref is not None:
        # the cannon rides the UPPER TORSO rigidly through the shiver (both shoulders, so both
        # arms keep their bend); the aim takes only part of the torso's rotation
        M = SH["T"] @ tref.inverted()
        p = M @ Vector(at)
        at = (p[0], p[1], p[2])
        f0 = Vector(L.direction(aim_yaw, aim_elev))
        f1 = M.to_3x3() @ f0
        ra = RIGID_AIM if rigid_aim is None else rigid_aim
        f = (f0 * (1.0 - ra) + f1 * ra).normalized()
        # the head half rides the shiver too (a fully stabilised head counter-snaps every frame)
        lk = M @ Vector(look)
        look = tuple(look[i] * (1.0 - HEAD_FOLLOW) + lk[i] * HEAD_FOLLOW for i in range(3))
        # the launcher's roll rides the torso too (a world-level up would twist the right wrist)
        u0 = Vector(L.up_for(f0, roll))
        u = u0 * (1.0 - ra) + (M.to_3x3() @ u0) * ra
        u = (u - u.dot(f) * f).normalized()
        # the elbow poles turn with the torso too (a world-fixed pole twists the upper arms)
        re = tuple(M.to_3x3() @ Vector(R_ELBOW))
        le = tuple(M.to_3x3() @ Vector(L_ELBOW))
        info = L.place_launcher(at=at, forward=tuple(f), up=tuple(u), anchor="Pivot", elbow_away=re,
                                grip_twist=GRIP, **kw)
    else:
        le = L_ELBOW
        info = L.hold(at, yaw=aim_yaw, elev=aim_elev, roll=roll, elbow_away=R_ELBOW, grip_twist=GRIP, **kw)
    info["left"] = L.left_hand_to(key="Grip2", elbow_away=le)
    info["gap"] = round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 3)
    info["elb"] = tuple(int(round(math.degrees(L.get_rot(s + "LowerArm").angle))) for s in ("Right", "Left"))
    info["head"] = [round(v, 2) for v in L.joint("Head")]
    info["reach"] = tuple(round((L.joint(s + "Hand") - L.joint(s + "UpperArm")).length, 2) for s in ("Right", "Left"))
    if head is None:
        L.head_look(target=look)
    else:
        L.head_look(yaw=head[0], pitch=head[1])
    return info


# ------------------------------------------------------------------ poses
RX, RY, RZ = (float(v) for v in _E("R16_READY", "0.6,-0.9,-1.26").split(","))


RROLL = float(_E("R16_RROLL", 4.0))
RYAW = float(_E("R16_RYAW", 2.0))


def ready(b, w=0.0, lift=0.0, sh=ZERO, amp=0.0, tref=None):
    """b 0..1 breathing, w -1..1 weight shift, lift 0..1 part way toward the charge hold,
    sh/amp = a cold shiver (shoulders hunch + fast jitter; the cannon rides the upper torso so the
    elbows keep their bend)"""
    if amp > 0.0 and tref is None:
        ready(b, w, lift, ZERO, amp, tref=False)  # unshaken hunch -> torso reference
        tref = SH["T"].copy()
    if tref is False:
        tref = None
    s = sh
    return pose(tref=tref, yaw=10.0 + 2.0 * w + 3.0 * amp * s[3], lean=-6.0 - 1.5 * b + 1.0 * lift - 3.0 * amp + 2.0 * amp * s[4],
                drop=0.28 + 0.04 * b + 0.05 * lift + 0.08 * amp + 0.03 * amp * s[1], back=0.14, side=0.03 * w + 0.05 * amp * s[0],
                waist_yaw=-3.0 + RYAW * amp * s[0], waist_bend=-2.0 - 2.5 * b - 1.0 * lift - 5.0 * amp,
                waist_roll=RROLL * amp * s[2],
                at=(RX + 0.03 * w + 0.02 * amp * s[0], RY - 0.05 * b - 0.1 * amp + 0.02 * amp * s[1],
                    RZ - 0.3 * lift + 0.02 * amp * s[2]),
                aim_yaw=13.0 + 2.0 * w - 3.0 * lift + 3.0 * amp * s[3],
                aim_elev=-13.0 - 2.5 * b + 12.0 * lift + 4.0 * amp * s[4],
                look=(-9.0, -2.0 + 0.8 * amp, -3.0 + 1.1 * amp * s[0]))


A_LO = float(_E("R16_ALO", 0.7))
A_HI = float(_E("R16_AHI", 2.3))
CIN = tuple(float(v) for v in _E("R16_CIN", "-0.08,0.1,0.0").split(","))   # Hi: cannon in/up (left reach)


def charge(depth, s=ZERO, phase=0.0, tref=None, **kw):
    """depth 0..1 = Lo..Hi, s = shiver sample, phase 0..1 through the loop (slow breathing bob).
    The shiver lives in the lean / waist bend / shoulder roll / hunch (NO spine-twist jitter, which
    scissored the shoulders and pumped the left elbow); the cannon rides the upper torso rigidly,
    so both arms keep their bend, plus its own small tremble."""
    if s is not ZERO and tref is None:
        charge(depth, ZERO, phase, tref=False, **kw)
        tref = SH["T"].copy()
    if tref is False:
        tref = None
    a = A_LO + (A_HI - A_LO) * depth    # shiver amplitude: fine tremble (Lo) .. violent (Hi)
    bob = math.sin(2.0 * math.pi * phase)
    return pose(tref=tref, yaw=12.0, lean=-9.0 - 4.0 * depth + 2.2 * a * s[4],
                drop=0.38 + 0.42 * depth + 0.02 * bob + 0.03 * a * abs(s[2]), back=0.18 + 0.12 * depth,
                side=0.02 * a * s[0],
                waist_yaw=-3.0 + 0.6 * a * s[0], waist_bend=-6.0 - 1.0 * depth + 2.2 * a * s[2],
                waist_roll=4.0 * a * s[4],
                at=(0.55 + CIN[0] * depth + 0.02 * a * s[0],
                    -0.96 - 0.28 * depth + CIN[1] * depth + 0.02 * a * s[1] + 0.02 * bob,
                    -1.65 + CIN[2] * depth + 0.02 * a * s[2]),
                aim_yaw=6.0 + 6.0 * depth + 0.6 * a * s[3], aim_elev=2.0 + 0.8 * a * s[4] + 1.0 * bob,
                look=(-14.0, 0.2 - 0.6 * depth + 0.3 * a * s[1], 0.4 + 0.3 * a * s[0]), **kw)


KZ = float(_E("R16_KZ", 0.15))
KY = float(_E("R16_KY", 0.0))
HUGY = float(_E("R16_HY", 0.15))
HUGZ = float(_E("R16_HZ", 0.2))


FIRE_REF = {"S": None}


LOWER = float(_E("R16_LOW", 0.2))
FZ = float(_E("R16_FZ", -0.15))     # Fire: cannon carried a little further to the front (ball reads sooner)


def fire_pose(kick, climb, sh=ZERO, amp=0.0, rise=0.0, squeeze=0.0, hug=0.0, lower=0.0):
    """kick 0..1 recoil impulse (the cannon driven back into the body), climb deg of muzzle rise,
    sh/amp = the shake-it-off shudder, rise 0..1 = standing up out of the crouch,
    squeeze 0..1 = anticipation (sink, lean in, muzzle dips), hug 0..1 = cannon pulled in toward
    the right shoulder during the shudder (elbows keep their bend)"""
    k = max(kick, 0.0)
    # every Fire pose is placed relative to the shoulders of the CRACK pose: the recoil drives the
    # cannon into the body (elbows compress).  The shudder is then layered on top with the cannon
    # riding the upper torso rigidly (both elbows keep their bend, no IK pumping).
    rise_at = 0.0 if FIRE_REF["S"] is not None else 1.0

    def args(s, amp):
        sway = 0.18 * amp * s[0]                       # hips / shoulders sway side to side
        wob = 0.04 * amp * abs(s[1])                   # drop wobble
        return dict(
            yaw=12.0 + 3.0 * kick + 6.0 * amp * s[3], lean=-12.0 + 7.0 * kick + 6.0 * rise + 3.0 * amp * s[2] - 3.0 * squeeze,
            drop=0.78 - 0.12 * kick - 0.35 * rise + wob + 0.05 * squeeze, back=0.22 + 0.05 * kick,
            side=sway,
            waist_yaw=-3.0 + 3.0 * kick + 6.0 * amp * s[0], waist_bend=-7.0 + 12.0 * kick + 4.0 * rise + 6.0 * amp * s[2],
            waist_roll=14.0 * amp * s[4],
            at=(0.55 + 0.08 * k,
                -1.22 + KY * k + 0.12 * rise * rise_at + HUGY * hug - 0.05 * squeeze - LOWER * lower,
                -1.65 + FZ + KZ * k + 0.1 * rise * rise_at + HUGZ * hug),
            aim_yaw=4.0 + 1.0 * kick + 4.0 * amp * s[3], aim_elev=1.0 + climb + 3.0 * amp * s[4] - 2.0 * squeeze,
            look=(-14.0, 0.5 + 1.5 * kick + 1.5 * amp * s[1], 0.4 - 3.0 * amp * s[0]))

    if amp <= 0.0 or sh is ZERO:
        return pose(ref=FIRE_REF["S"], **args(ZERO, 0.0))
    pose(ref=FIRE_REF["S"], **args(ZERO, 0.0))             # unshaken -> torso + cannon reference
    T0, at0 = SH["T"].copy(), SH["at"]
    a = args(sh, amp)
    a["at"] = (at0[0] + 0.02 * amp * sh[0], at0[1] + 0.02 * amp * sh[1], at0[2] + 0.02 * amp * sh[2])
    return pose(tref=T0, rigid_aim=1.0, **a)       # after the shot the cannon simply rides the body


# ------------------------------------------------------------------ clips
report["grip_probe"] = charge(0.5, max_wrist=25.0)
GRIP = L.get_rot("Launcher").copy()

clip("Ready")
report["ready0"] = ready(0.0, 0.0); kf(0)
report["ready1"] = ready(1.0, 1.0); kf(22)                     # slow calm breath / weight shift
ready(0.2, 0.2); kf(40)
ready(0.3, 0.3); kf(50)
ready(0.33, 0.2, sh=SHAKE[1], amp=0.45); kf(52)            # the shiver creeps in
# the cold shiver (once per 3 s loop): shoulders hunch, fast jitter for ~0.4 s
for n, f in enumerate((54, 56, 58, 60, 62, 64)):
    ready(0.35, 0.1, sh=SHAKE[n + 2], amp=(1.0, 1.0, 0.85, 0.7, 0.5, 0.3)[n]); kf(f)
ready(0.8, -1.0); kf(74)
ready(0.0, 0.0); kf(90)
L.make_cyclic("Ready")

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    report[kind + "_rest"] = charge(depth)
    clip(kind)
    for i in range(12):
        info = charge(depth, CSHAKE[i], i / 12.0)
        if i == 0:
            report[kind + "_0"] = info
        kf(2 * i)
    charge(depth, CSHAKE[0], 0.0); kf(24)
    L.make_cyclic(kind)

clip("Fire")
C0 = float(_E("R16_C0", 9.0))       # crack elevation lift (muzzle higher on screen)
fire_pose(-0.1, C0)                                                          # probe: crack-pose shoulders
FIRE_REF["S"] = SH["last"].copy()
charge(1.0, ZERO, 0.0); kf(0)                                               # 0.00 ChargeHi pose (still)
fire_pose(-0.08, C0 - 1.0, squeeze=0.45); kf(2)                             # 0.07 the brace starts: sink, lean in
report["brace"] = fire_pose(-0.15, C0 - 2.5, squeeze=1.0); kf(5)          # 0.17 squeeze peak: muzzle dips
report["crack"] = fire_pose(-0.1, C0); kf(FIRE_FRAME)                      # 0.20 CRACK: the ball leaves
report["kick"] = fire_pose(0.75, C0 + 8.0); kf(FIRE_FRAME + 1)            # 0.23 the cannon slams back into the body
report["recoil"] = fire_pose(1.0, C0 + 11.0); kf(FIRE_FRAME + 2)           # 0.27 recoil peak, elbows compressed
report["frozen"] = fire_pose(0.95, C0 + 10.0, SHAKE[3], 0.15, rise=0.1, lower=0.2); kf(10)   # 0.33 frozen stiff, trembling
report["frozen2"] = fire_pose(0.85, C0 + 7.0, SHAKE[4], 0.15, rise=0.2, lower=0.45); kf(12)  # 0.40
# 0.47 .. 0.97 shake it off: full-body shudder, decaying; the cannon sinks back toward the hip
AMPS = (0.55, 1.0, 0.95, 0.8, 0.65, 0.5, 0.35, 0.22, 0.12)   # ramp in, then decay
FR = (14, 16, 18, 20, 22, 24, 26, 28, 31)
HUG0 = float(_E("R16_HUG", -0.15))
SC = float(_E("R16_SC", 2.4))       # shudder climb decay (deg per shudder key)
RISE0 = float(_E("R16_R0", 0.25))  # standing up out of the crouch through the shudder
RISE1 = float(_E("R16_R1", 0.06))


def shud(m, sh, amp):
    m = m * 7.0 / 8.0
    return fire_pose(0.5 - 0.06 * m, C0 + 5.0 - SC * m, sh, amp, rise=RISE0 + RISE1 * m,
                     hug=HUG0 * min(1.0, 0.5 + 0.25 * m), lower=min(1.0, 0.6 + 0.1 * m))


for n, f in enumerate(FR):
    report["shud%d" % n] = shud(n, SHAKE[n + 5], AMPS[n]); kf(f)
    if n + 1 < len(FR):          # in-between frames solved by IK too (keeps the hands on the cannon)
        for g in range(f + 1, FR[n + 1]):
            u = (g - f) / float(FR[n + 1] - f)
            sh = tuple((1.0 - u) * a + u * b for a, b in zip(SHAKE[n + 5], SHAKE[n + 6]))
            shud(n + u, sh, (1.0 - u) * AMPS[n] + u * AMPS[n + 1]); kf(g)
report["settle"] = ready(0.5, 0.0, 0.5); kf(38)                # 1.27 lowering to the hip
ready(0.0, 0.0); kf(45)                                        # 1.50 Ready
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
L.set_interpolation("Fire", 'LINEAR', 'VECTOR', frames=(FIRE_FRAME, FIRE_FRAME + 1))   # fast-out crack


def _ang(b):
    return int(round(math.degrees(L.get_rot(b).angle)))


for _kind, _n in (("Fire", 45), ("Ready", 90), ("ChargeLo", 24), ("ChargeHi", 24)):
    L.use_clip(_kind)
    _g = []
    for _f in range(_n + 1):
        L.goto(_f / 30.0)
        gap = (L.hand_cf("Left").translation - L.launcher_point(G2)).length
        _g.append("%d:R%d/L%d/g%.2f" % (_f, _ang("RightLowerArm"), _ang("LeftLowerArm"), gap))
    print("REPORTE", _kind, " ".join(_g))
for k, v in report.items():
    print("REPORTP", k, v)
L.finish(SPEC, OUT, extra_times=[0.1, 0.1667, 0.2333, 0.2667, 0.3333, 0.4, 0.4667, 0.5333, 0.6, 0.8, 1.2667])
