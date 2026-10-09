"""05 Wooden Slingshot -- build script (round 4: elbow-guard / motion-audit polish).

Concept: a big Y-frame slingshot in the right hand, the snowball pinched in the LEFT hand.
The player takes an ARCHER stance on the pad: body side-on with the right shoulder toward the
track (facing screen-left), so the drawing arm is on the camera side and the whole draw line
(ball -> fork -> down-track) runs beside the head at z ~ +1.85 (screen-left of the head), clear of
the body and in full view of the pad camera.
  Ready    relaxed pre-aim carry: the right arm hangs forward toward the track with the forearm along
           the shot line (straight wrist), the fork low at the front-left (screen-left of the body) with
           its Y face toward the track; left fist by the hip; breathing + weight sway.
  ChargeLo raise + aim down the track: right arm out toward the track, fork nearly upright, the
           left hand draws the ball back to half draw; visible aim sway + breathing lean.
  ChargeHi same rhythm at FULL draw: the hand pulls back past the cheek, the body leans back into
           it, the frame and the ball tremble (keyed every 2 frames, linear).
  Fire     a last tug (extra draw, hips sink, frame dips) -> release at FireAt: the ball leaves the
           fingers straight through the fork down the track; the left hand springs back open, the
           frame kicks forward and dips, the head follows the shot, then IK-solved in-betweens (free hand
           arcs out past the chest) lower both arms back to the Ready carry.
Round 4: all right-arm poles UP-ish (aim (-0.6, 1, -0.4), Ready (0, 1, 0.2)), body yaw +10 while
aiming, the drawing elbow never locks straight (MIN_LELB pulls the draw point in), the release
hand drops below the fork instead of covering it. pm() + PROBE print per-pose audit metrics.
The runtime draws the two elastic bands from the fork tips (meta Bands) to the ball in the hand.
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
from mathutils import Vector, Quaternion

LID = 5
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

BALL_OFF = (-0.75, -0.1, 0.0)        # ball centre in the left hand part frame (in front of the palm)
FIRE_FRAME = 5
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.0, "ChargeHi": 1.0, "Fire": 1.4,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Charge", "start": "Seat", "grow": 1.0, "hand": "Left", "offset": list(BALL_OFF)},
    "Fx": {"Style": "snow", "Color": [1.0, 1.0, 1.0]},
    "TwoHanded": False,
    "AllowFootLift": False,
    "Notes": "slingshot: archer stance, left hand draws the ball back past the cheek, release through the fork",
}
# the fork = thumb side of the fist, the shot direction = along the fingers (a natural slingshot grip)
GRIP = L.angles(-80, 0, 90).inverted()
FEET = {"Left": (0.8, 0.6), "Right": (-0.8, 0.05)}
RB = 0.25                              # Ready hip shift toward +Z (screen-left, under the draw line)
ELEV = 13.0
LOOK = L.direction(0.0, ELEV)
FX, FY, FZ = -2.0, 1.90, 1.85         # fork (Muzzle) at the aim pose
ROLL = -26.0                           # fork cant while aiming
WADD = 0.0                             # extra upper-torso twist while aiming
YADD = 10.0                            # extra body yaw while aiming
APOLE = (-0.6, 1.0, -0.4)               # right elbow pole while aiming (UP-ish: the elbow hangs down and out)
MIN_LELB = 40.0                        # the drawing elbow never straightens past this (no IK pops)
TARGET = (-14.0, 1.2, FZ)
MUZ = L.load_meta(LID)["Muzzle"]["pos"]
report = {}
report_D = []

# ---------------------------------------------------------------- keying with quaternion continuity
_last = {}


def new_clip(kind):
    _last.clear()
    L.new_clip(kind)


def key(frame):
    """L.key, but every bone quaternion is flipped into the hemisphere of the previous key so the
    F-curves never interpolate the long way round (the round-1 settle flip)."""
    r = L.rig()
    for pb in r.pose.bones:
        q = pb.rotation_quaternion.copy()
        p = _last.get(pb.name)
        if p is not None and q.dot(p) < 0.0:
            pb.rotation_quaternion = -q
        _last[pb.name] = pb.rotation_quaternion.copy()
    L.key(frame)


def body(yaw, lean=0.0, drop=0.25, back=0.0, waist_yaw=0.0, waist_bend=0.0, tilt=0.0):
    """yaw: LowerTorso turn (150 = right shoulder toward the track, facing screen-left)"""
    L.reset_pose()
    lg = L.stance(hip_drop=drop, hip_back=back, root=L.ry(yaw) @ L.rx(lean) @ L.rz(tilt), feet=FEET)
    if max(lg.values()) > 0.02:
        print("REPORTK LEGS", yaw, back, lg)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend))


def ball_hand(ball, elbow=(1.0, 0.4, 0.4), palm=None):
    """left hand holds the ball centre at `ball` (hand placed so hand_cf @ BALL_OFF == ball)"""
    palm = LOOK if palm is None else palm
    ball = Vector(ball)
    err = None
    moved = 0.0
    for _try in range(10):
        p = ball - LOOK * 0.75
        for _ in range(3):
            err = L.left_hand_to(point=p, elbow_away=elbow, palm_toward=palm)
            got = (L.hand_cf("Left") @ L.cf(Vector(BALL_OFF))).translation
            p = p + (ball - got)
        bend = math.degrees(L.get_rot("LeftLowerArm").angle)
        bend = min(bend, 360.0 - bend)
        if bend >= MIN_LELB:
            break
        # never let the drawing arm lock straight (the IK would pop): pull the draw point in
        step = (L.joint("LeftUpperArm") - ball).normalized() * 0.05
        ball = ball + step
        moved += 0.05
    got = (L.hand_cf("Left") @ L.cf(Vector(BALL_OFF))).translation
    return {"left_overreach": err[0], "ball_err": round((got - ball).length, 3), "pulled_in": round(moved, 2),
            "lelb": round(bend, 1)}


def aim(F, roll=ROLL, elev=ELEV, yaw=0.0):
    return L.hold(F, yaw=yaw, elev=elev, roll=roll, anchor="Muzzle", elbow_away=APOLE, grip_twist=GRIP)


def fork():
    return [round(v, 2) for v in L.launcher_point(MUZ)]


_VERTS = None


def pm():
    """pose metrics on the audit's avatar sizes: right wrist swing, launcher depth in the
    torso/head, worst arm-part depth in the body, left elbow bend"""
    global _VERTS
    L.update()
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    lob = L.launcher_object()
    if _VERTS is None:
        _VERTS = [v.co.copy() for v in lob.data.vertices]
    mw = lob.matrix_world
    ld = 0.0
    for co in _VERTS:
        pt = L.b2r(mw @ co)
        for b in ("UpperTorso", "Head"):
            ld = max(ld, L._depth_inside(pt, *boxes[b]))
    ad, aw = 0.0, ""
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for b in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[b])
                        if d > ad:
                            ad, aw = d, arm + ">" + b
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return {"swing": round(math.degrees(sw.angle), 1), "l_in": round(ld, 2), "a_in": round(ad, 2), "a_at": aw,
            "lelb": round(min(math.degrees(L.get_rot("LeftLowerArm").angle), 360.0 - math.degrees(L.get_rot("LeftLowerArm").angle)), 1),
            "relb": round(min(math.degrees(L.get_rot("RightLowerArm").angle), 360.0 - math.degrees(L.get_rot("RightLowerArm").angle)), 1)}


# ------------------------------------------------------------------ poses
READY_YAW = 154.0
RLY, RLE, RRL, RD, RDY = -35.0, -30.0, -30.0, 1.55, -0.3   # Ready carry: look yaw/elev, cant, reach, drop
RPOLE = (0.0, 1.0, 0.2)


def ready(b, s=0.0, ly=None, le=None, rl=None, d=None, dy=None, pole=None):
    """b 0..1 breathing, s -1..1 weight sway.  Relaxed pre-aim carry: the right arm hangs forward
    toward the track with the forearm along the slingshot's shot line (a straight wrist), the fork
    low at the character's front-left (screen-left of the body) with its Y face toward the track so
    it reads from the pad camera; the left fist rests by the hip; breathing + weight sway."""
    ly = RLY if ly is None else ly
    le = RLE if le is None else le
    rl = RRL if rl is None else rl
    d = RD if d is None else d
    dy = RDY if dy is None else dy
    pole = RPOLE if pole is None else pole
    yaw = READY_YAW + 3.0 * s
    body(yaw, lean=-3.0 - 2.0 * b, drop=0.18 + 0.04 * b, back=RB, waist_yaw=4.0, waist_bend=-3.0 - 2.0 * b)
    R = L.ry(yaw)
    sh = L.joint("RightUpperArm")
    ly2, le2 = ly + 3.0 * s, le + 3.0 * b
    grip = sh + L.direction(ly2, le2) * d + Vector((0.0, dy + 0.03 * b, 0.0))
    info = L.hold(grip, yaw=ly2, elev=le2, roll=rl + 2.0 * s, anchor="Pivot", elbow_away=pole, grip_twist=GRIP)
    wrist = R @ Vector((-1.0, -0.7 + 0.04 * b, 0.35)) + Vector((0.0, 0.0, RB))
    L.arm_to("Left", wrist, elbow_away=R @ Vector((-0.6, -0.4, 0.8)))
    L.head_look(target=(-10.0, 0.5 + 0.2 * s, 2.0))
    info["fork"] = fork()
    info["grip"] = [round(v, 2) for v in grip]
    info["rsh"] = [round(v, 2) for v in sh]
    return info


def charge(c, sway=0.0, pull=0.0, trem=0.0, breath=0.0, extra=0.0, sink=0.0, dip=0.0):
    """c 0 = half draw (Lo), 1 = full draw (Hi); sway -1..1 = slow aim drift; pull -1..1 = draw
    pulse; trem -1..1 = tremble sign (only at c > 0); breath -1..1 = breathing lean;
    extra = extra draw (studs), sink = extra hip drop, dip = frame elevation change (Fire tug)"""
    yaw = 150.0 + 4.0 * c + YADD
    body(yaw, lean=-5.0 + 5.0 * c + 4.0 * breath, drop=0.22 + 0.26 * c + sink, back=0.4 + 0.1 * c,
         waist_yaw=-4.0 - 4.0 * c + WADD, waist_bend=3.0 + 5.0 * c, tilt=6.0 * c)
    t = trem * c                                   # -1..1 tremble at full draw
    F = Vector((FX + 0.16 * (1.0 - c) + 0.12 * c, FY + 0.1 * sway + 0.12 * t, FZ + 0.06 * sway - 0.06 * t))
    d = 1.05 + 0.8 * c + (0.08 + 0.06 * c) * pull + extra
    info = aim(F, roll=ROLL - 4.0 * c + 1.5 * sway + 1.5 * t, elev=ELEV + dip + 2.5 * t)
    D = F - LOOK * d + Vector((0.0, -0.12 * t, 0.18 * t))
    info.update(ball_hand(D, elbow=(1.0, 0.3 + 0.7 * c, -0.4)))
    L.head_look(target=TARGET)
    info["D"] = [round(v, 2) for v in D]
    report_D.append(D.copy())
    info["rsh"] = [round(v, 2) for v in L.joint("RightUpperArm")]
    info["fork"] = fork()
    return info


def charge_at(c, i, trem=0.0, **kw):
    ph = 2.0 * math.pi * i / 30.0
    return charge(c, sway=math.sin(ph), pull=math.sin(ph + 1.0), trem=trem,
                  breath=0.5 * (1.0 - math.cos(ph)), **kw)


# ------------------------------------------------------------------ clips
new_clip("Ready")
report["ready0"] = ready(0.0, 0.0); key(0)
report["ready1"] = ready(1.0, 1.0); key(24)
ready(0.2, 0.0); key(42)
ready(0.9, -1.0); key(60)
ready(0.0, 0.0); key(72)
L.make_cyclic("Ready")

for kind, c in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    new_clip(kind)
    for i in range(0, 31, 2):
        trem = 0.0 if i in (0, 30) else (1.0 if (i // 2) % 2 == 1 else -1.0)
        r = charge_at(c, i, trem=trem)
        if i in (0, 8):
            report[kind + "_%d" % i] = r
        key(i)
    L.make_cyclic(kind)
    if c > 0.5:
        L.set_interpolation(kind, 'LINEAR', 'AUTO_CLAMPED')

new_clip("Fire")
charge_at(1.0, 0); key(0)                                                   # 0.00 full draw (= ChargeHi start)
report["tug"] = charge_at(1.0, 0, extra=0.24, sink=0.04, dip=-2.0); key(4)  # 0.13 last tug
report["release"] = charge_at(1.0, 0, extra=0.25, sink=0.045, dip=-2.0); key(FIRE_FRAME)  # RELEASE
# 0.23 snap: the frame kicks forward + dips, the left hand springs back and out, open; body rocks
body(157.0 + YADD, lean=2.0, drop=0.45, back=0.5, waist_yaw=-10.0, waist_bend=8.0)
report["kick"] = aim(Vector((FX - 0.3, FY - 0.13, FZ + 0.05)), roll=ROLL - 9.0, elev=-4.0)
report["kick_left"] = L.left_hand_to(point=Vector((1.15, 1.0, FZ + 0.4)), elbow_away=(0.6, 1.0, 0.4), palm_toward=(-0.3, -0.2, 1.0))
L.head_look(target=TARGET); key(FIRE_FRAME + 2)
# 0.43 follow-through: frame still out, watching the shot fly, left hand open out to the side
FOLLOW_BODY = (153.0 + YADD, 0.0, 0.36, 0.45, -8.0, 5.0)
body(*FOLLOW_BODY)
report["follow"] = aim(Vector((FX + 0.2, FY - 0.19, FZ - 0.03)), roll=ROLL + 2.0, elev=3.0)
report["follow_left"] = L.left_hand_to(point=Vector((0.85, 0.5, FZ + 0.2)), elbow_away=(0.6, -0.2, 0.8), palm_toward=(-0.3, -0.6, 1.0))
L.head_look(target=(-16.0, 0.5, FZ)); key(FIRE_FRAME + 8)
f_piv = L.pivot_cf()
f_lw = L.joint("LeftHand")

# Ready target (measure)
ready(0.0, 0.0)
r_piv = L.pivot_cf()
r_lw = L.joint("LeftHand")
READY_B = (READY_YAW, -3.0, 0.18, RB, 4.0, -3.0)


def lower(u, head):
    """IK-solved in-between from the follow-through to Ready: body, grip pivot (position lerp +
    orientation slerp, so the fork stays up) and the left wrist all move by u."""
    bp = [a + (b - a) * u for a, b in zip(FOLLOW_BODY, READY_B)]
    body(*bp)
    qa = f_piv.to_3x3().to_quaternion()
    qb = r_piv.to_3x3().to_quaternion()
    if qa.dot(qb) < 0.0:
        qb = -qb
    q = qa.slerp(qb, u)
    m = q.to_matrix()
    pos = f_piv.translation.lerp(r_piv.translation, u)
    info = L.place_launcher(pos, m @ Vector((0.0, -1.0, 0.0)), m @ Vector((0.0, 0.0, -1.0)), anchor="Pivot",
                            elbow_away=RPOLE, grip_twist=GRIP)
    bulge = Vector((0.4, 0.05, 0.15)) * math.sin(math.pi * u)      # arc the free hand out past the chest
    L.arm_to("Left", f_lw.lerp(r_lw, u) + bulge, elbow_away=Vector((0.6, -0.2, 0.8)).lerp(L.ry(READY_YAW) @ Vector((-0.6, -0.4, 0.8)), u))
    L.head_look(target=head)
    info["fork"] = fork()
    return info


report["lower1"] = lower(0.4, (-14.0, 0.4, 2.0)); key(24)                   # 0.80
report["lower2"] = lower(0.78, (-11.0, 0.4, 2.3)); key(33)                  # 1.10
ready(0.0, 0.0); key(42)                                                    # 1.40 back to Ready
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in report.items():
    print("REPORTK", k, v)

PROBE = False
PROBE_ONLY = False
if PROBE:
    # metrics of every key pose as keyed
    for kind, fr in (("Ready", (0, 24, 42, 60)), ("ChargeLo", (0, 8, 16)), ("ChargeHi", (0, 2, 8, 16)),
                     ("Fire", (0, 5, 7, 13, 18, 24, 30, 33, 36, 39))):
        L.use_clip(kind)
        for f in fr:
            L.goto(f / 30.0)
            print("PROBE", kind, f, pm(), "rsh", [round(v, 2) for v in L.joint("RightUpperArm")],
                  "lsh", [round(v, 2) for v in L.joint("LeftUpperArm")], "head", [round(v, 2) for v in L.joint("Head")],
                  "fork", fork(), "piv", [round(v, 2) for v in L.pivot_cf().translation])
if not globals().get("PROBE_ONLY"):
    L.finish(SPEC, OUT, extra_times=[0.1, 0.23, 0.3, 0.6, 1.0, 1.2])
