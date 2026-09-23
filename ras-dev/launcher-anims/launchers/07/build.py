"""07 Spring Scoop -- a cup on a spring arm with a wooden handle.

Concept:
  Ready    held upright in the right fist at chest height like a torch, the cup (with the ball) up
           out in front of the right shoulder, the whole scoop bobbing on its spring (2 bobs per
           loop, out of phase with the breathing, a small roll wobble); free left arm relaxed.
  ChargeLo the handle drops out to the right hip and the scoop tips forward (the lever passes clear of
           the chest); the LEFT palm comes down
           ON the cup rim from above (elbow up) and pumps it DOWN on its spring: the cup dips, the
           knees bend, it rebounds up past the start -- a steady pump rhythm.
  ChargeHi the same rhythm, deeper presses (cup ~1 stud down), lower crouch, higher rebounds.
  Fire     one last deep press held for a beat (anticipation) -> let go: the scoop POPS up and
           forward, the right arm flicks toward the track and the ball lifts off the cup (elev ~32)
           -> the body springs up onto its toes, the left hand flies up and out -> the scoop wobbles
           on its spring with the fist steady -> settle to the torch hold.
Ball: sits in the cup the whole time (show Always), leaves from the Seat.
"""
import importlib
import itertools
import math
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)
from mathutils import Vector

LID = 7
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.0, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.4,
    "FireAt": 0.23,
    "Ball": {"show": "Always", "start": "Seat", "grow": 1.0},
    "Fx": {"Style": "snow", "Color": [235, 245, 255]},
    "TwoHanded": False,
    "AllowFootLift": True,
    "Notes": "spring scoop: left palm pumps the cup down on its spring while charging, let go -> the scoop pops up and flings the ball",
}
FEET = {"Left": (-0.75, -0.4), "Right": (0.6, 0.45)}
PRESS = (0.0, -1.35, -1.62)      # back rim of the cup (template, pivot frame): where the left palm presses
SEAT = (0.0, -1.86, -1.9335)
report = {}
GREF = [None]


def off(yaw, elev, roll, pt):
    """world offset pivot -> launcher point pt for a hold(yaw, elev, roll)"""
    f = L.direction(yaw, elev)
    u = L.up_for(f, roll)
    return f * (-pt[1] * L.LAUNCHER_SCALE) + u * (-pt[2] * L.LAUNCHER_SCALE)


def gturn(info):
    """grip turn vs the Ready pose (the report warns above 60)"""
    g = L.get_rot("Launcher")
    if GREF[0] is None:
        GREF[0] = g.copy()
    info["vsReady"] = round(math.degrees((GREF[0].inverted() @ g).angle), 1)
    return info


def body(yaw=-10.0, lean=-4.0, drop=0.12, back=0.1, wy=-5.0, wb=-3.0, feet=None, wr=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, root=L.ry(yaw) @ L.rx(lean), feet=feet or FEET)
    L.waist(L.ry(wy) @ L.rx(wb) @ L.rz(wr))


_LOB = L.launcher_object()
VERTS = [v.co.copy() for v in _LOB.data.vertices]
VERTS = VERTS[::max(1, len(VERTS) // 240)]


def inbody():
    """(depth, part) of the launcher sunk into the torso / head (audit sizes) in the current pose"""
    L.update()
    boxes = [(n, b, Vector(L.AUDIT_SIZE[n]) * 0.5) for n, b, h in L.body_boxes() if n in ("UpperTorso", "Head")]
    mw = _LOB.matrix_world
    worst = (0.0, "")
    for co in VERTS:
        pt = L.b2r(mw @ co)
        for n, b, h in boxes:
            d = L._depth_inside(pt, b, h)
            if d > worst[0]:
                worst = (round(d, 3), n)
    return worst


def arm_inbody():
    L.update()
    boxes = {n: (b, Vector(L.AUDIT_SIZE[n]) * 0.5) for n, b, h in L.body_boxes() if n in L.AUDIT_SIZE}
    worst = (0.0, "")
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for bn in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[bn])
                        if d > worst[0]:
                            worst = (round(d, 3), arm + ">" + bn)
    return worst


def cup():
    return L.launcher_point(SEAT)


def rim():
    return L.launcher_point(PRESS)


def free_left(swing=0.0):
    """relaxed free left arm (swing -1..1 = small sway back/forward)"""
    L.arm_to("Left", (-1.3, -0.72, -0.15 - 0.12 * swing), elbow_away=(-0.4, -0.2, 1.0))


def look(yaw, pitch):
    L.head_look(yaw=yaw, pitch=max(-28.0, min(28.0, pitch)))


def toes(deg):
    """up on the toes: pitch both feet toes-down (after stance)"""
    for side in ("Left", "Right"):
        L.set_rot(side + "Foot", L.get_rot(side + "Foot") @ L.rx(-deg))
    L.update()


# ------------------------------------------------------------------ poses
R_EA = (-0.6, 1.0, 0.0)          # right elbow hangs down / out


def ready(b, bob, wob):
    """b 0..1 breathing, bob -1..1 = the scoop bouncing on its spring, wob -1..1 = roll wobble"""
    body(yaw=-10.0, lean=-4.0 - 1.5 * b, drop=0.12 + 0.05 * b, wy=-5.0, wb=-3.0 - 2.5 * b)
    info = L.hold((0.75, 0.1 + 0.03 * b - 0.06 * bob, -1.0), yaw=80.0, elev=-12.0 - 7.0 * bob, roll=15.0 + 4.0 * wob,
                  elbow_away=R_EA)
    free_left(b - 0.5)
    look(18.0, -4.0 + 3.0 * b)
    return gturn(info)


CH = {"roll": 30.0, "ea": (0.0, 1.0, 0.0), "yaw": 70.0, "px": 0.7, "pz": -2.2, "py": 0.0, "by": -44.0, "lea": (0.3, -1.0, 0.2)}   # elbow UP over the cup (palm presses down; the guard keeps it off the chest)


def charge(p, depth):
    """p 0 = spring up, 1 = pressed all the way (can overshoot < 0 on the rebound); depth 0..1 = charge"""
    a = p * (0.55 + 0.45 * depth) if p >= 0.0 else p * (0.6 + 1.2 * depth)   # Hi rebounds higher too
    drop = 0.25 + 0.3 * a + 0.12 * depth
    body(yaw=CH["by"], lean=-4.0 - 4.0 * a - 3.0 * depth, drop=drop, back=0.15 + 0.05 * a,
         wy=-15.0, wb=-6.0 - 5.0 * a - 2.0 * depth)
    ly, le = CH["yaw"], -32.0 - 14.0 * a
    P = Vector((CH["px"], CH["py"] - (drop - 0.25) - 0.95 * a, CH["pz"] - 0.1 * a))
    fist = P - off(ly, le, CH["roll"], PRESS)
    info = L.hold(tuple(fist), yaw=ly, elev=le, roll=CH["roll"], elbow_away=CH["ea"])
    info["left"] = L.left_hand_to(point=tuple(rim() + Vector((0.0, 0.25, 0.0))), elbow_away=CH["lea"],
                                  palm_toward=(0.0, -1.0, 0.0))
    look(26.0, -1.0 - 4.0 * a)
    info["cup"] = tuple(round(c, 2) for c in cup())
    info["lelbow_up"] = round(L.joint("LeftLowerArm").y - L.joint("LeftHand").y, 2)
    return gturn(info)


PRESS_KEYS = ((0, 0.0), (9, 1.0), (16, -0.3), (20, 0.06), (24, 0.0))


def press_curve(f):
    """press amount over the 24-frame pump: down in 0.3 s, spring rebound overshoot, settle"""
    for (f0, p0), (f1, p1) in zip(PRESS_KEYS, PRESS_KEYS[1:]):
        if f0 <= f <= f1:
            t = (f - f0) / float(f1 - f0)
            return p0 + (p1 - p0) * (0.5 - 0.5 * math.cos(math.pi * t))
    return 0.0


# ------------------------------------------------------------------ clips
L.new_clip("Ready")
for f in range(0, 61, 5):
    t = f / 60.0
    b = 0.5 - 0.5 * math.cos(2.0 * math.pi * t)
    bob = math.sin(4.0 * math.pi * t + 1.1)
    wob = math.sin(2.0 * math.pi * t + 2.3)
    info = ready(b, bob, wob); L.key(f)
    if f in (0, 15, 30):
        report["ready_%02d" % f] = info
L.make_cyclic("Ready")

# pick the charge grip that keeps the launcher + arms OUT of the torso (audit sizes), the right arm
# 0.15 inside full reach and the grip close to the Ready grip.  The long spring arm (~4 studs pivot ->
# cup) means the fist sits out at the right hip while the left palm presses the cup in front: the
# lever runs past the right side of the chest (a wide search chose yaw ~70, roll ~15, cup x 0.7-0.8,
# body yaw -44; this refines around it).
_best = None


def rslack():
    """shoulder -> wrist distance of the right arm beyond 1.5 studs (0.15 inside full reach)"""
    return max(0.0, (L.joint("RightHand") - L.joint("RightUpperArm")).length - 1.5)


for _yaw, _roll, _ea, _px, _pz, _py, _by in itertools.product(
        (64.0, 68.0, 72.0), (7.5, 15.0, 22.5), ((-0.3, 1.0, 0.4), (-0.3, 1.0, 0.8)),
        (0.7, 0.8), (-2.2, -2.05), (0.0, 0.15), (-44.0,)):
    CH["roll"], CH["ea"], CH["yaw"], CH["px"], CH["pz"], CH["py"], CH["by"] = _roll, _ea, _yaw, _px, _pz, _py, _by
    worst = 0.0
    for _p, _d in ((0.0, 0.0), (1.3, 1.0), (-0.3, 1.0), (1.0, 0.0), (0.5, 1.0)):
        _i = charge(_p, _d)
        worst = max(worst, 3.0 * max(0.0, _i["vsReady"] - 45.0) + 300.0 * (_i["arm_overreach"] + _i["left"][0])
                    + 300.0 * rslack() + 3.0 * max(0.0, _i["wrist_bend_deg"] - 66.0)
                    + 400.0 * max(0.0, inbody()[0] - 0.05) + 300.0 * max(0.0, arm_inbody()[0] - 0.1))
    if _best is None or worst < _best[0]:
        _best = (worst, _roll, _ea, _yaw, _px, _pz, _py, _by)
CH["roll"], CH["ea"], CH["yaw"], CH["px"], CH["pz"], CH["py"], CH["by"] = _best[1:]
print("REPORT charge grip", _best)
if os.environ.get("PROBE"):
    for _d in (0.0, 1.0):
        for _p in (-0.3, 0.0, 0.5, 1.0, 1.25):
            _i = charge(_p, _d)
            v = lambda n: tuple(round(c, 2) for c in L.joint(n))
            print("PROBE or=%s sl=%.2f d%.0f p%.2f in=%s arm=%s fist=%s cup=%s rsh=%s lsh=%s gt=%s wb=%s left=%s" % (
                _i["arm_overreach"], rslack(), _d, _p, inbody(), arm_inbody(), v("RightHand"), _i["cup"], v("RightUpperArm"), v("LeftUpperArm"),
                _i["vsReady"], _i["wrist_bend_deg"], _i["left"]))
    sys.exit(0)

def rec(name, info):
    """adds the body-intrusion / reach numbers of the finished key pose to the report"""
    info["inb"], info["arm"], info["sl"] = inbody(), arm_inbody(), round(rslack(), 2)
    report[name] = info

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind)
    for f in range(0, 25, 2):
        info = charge(press_curve(f), depth); L.key(f)
        if f in (0, 10, 16):
            rec("%s_%02d" % (kind, f), info)
    L.make_cyclic(kind)


F_EAS = ((-0.3, 1.0, 0.3), (-1.0, 0.3, 0.0), (0.0, 1.0, -0.5), (-0.6, 0.6, 0.6), (0.5, 0.5, 0.5), (1.0, -0.6, 0.4))


def fire_hold(pose, fist, seat_elev, yaw=0.0, rolls=(-40.0, -25.0, -10.0, 0.0, 10.0, 25.0), eas=F_EAS):
    """right fist near `fist`, the ball's seat look along direction(yaw, seat_elev): the seat is
    anchored where the fist would put it at roll 0, then the roll about the look axis + the elbow
    are searched for the most natural wrist / smallest grip turn"""
    S = Vector(fist) + off(yaw, seat_elev - 55.0, 0.0, SEAT)
    best = None
    for roll in rolls:
        for ea in eas:
            pose()
            i = gturn(L.hold(tuple(S), yaw=yaw, elev=seat_elev, roll=roll, anchor="Seat", elbow_away=ea))
            score = 0.5 * i["vsReady"] + 300.0 * i["arm_overreach"] + 150.0 * rslack() + 2.0 * max(0.0, i["wrist_bend_deg"] - 65.0)
            if best is None or score < best[0]:
                best = (score, roll, ea)
    pose()
    i = gturn(L.hold(tuple(S), yaw=yaw, elev=seat_elev, roll=best[1], anchor="Seat", elbow_away=best[2]))
    i["roll"], i["ea"] = best[1], best[2]
    i["fist"] = tuple(round(c, 2) for c in L.joint("RightHand"))
    return i



L.new_clip("Fire")
charge(0.6, 1.0); L.key(0)                                      # 0.00 the charge pose
rec("deep", charge(1.2, 1.0)); L.key(2)                        # 0.07 one last deep press
charge(1.25, 1.0); L.key(3)                                    # 0.10 ...held (anticipation beat)


def pb(yaw, lean, drop, wy, wb, toe=0.0, back=0.05):
    def f():
        body(yaw=yaw, lean=lean, drop=drop, back=back, wy=wy, wb=wb)
        if toe:
            toes(toe)
    return f


# 0.23 POP (FireAt): let go, the scoop flicks up and forward, the ball lifts off the cup
report["pop"] = fire_hold(pb(16.0, 3.0, -0.05, 8.0, 5.0, 10.0), (0.6, -0.4, -1.35), 32.0, yaw=2.0)
R0, E0 = report["pop"]["roll"], report["pop"]["ea"]
L.arm_to("Left", (-0.5, 0.9, -1.5), elbow_away=(0.4, 1.0, 0.3))
look(10.0, 12.0); rec("pop", report["pop"]); L.key(7)
# 0.30 overshoot: up on the toes, the scoop keeps rising
report["over"] = fire_hold(pb(24.0, 7.0, -0.25, 10.0, 7.0, 26.0, 0.0), (0.55, -0.2, -1.45), 48.0, yaw=8.0,
                           rolls=(R0 - 10.0, R0, R0 + 10.0), eas=(E0,))
L.arm_to("Left", (-0.9, 1.5, -1.2), elbow_away=(0.4, 1.0, 0.3))
look(5.0, 16.0); rec("over", report["over"]); L.key(9)
# 0.50 spring wobble back
report["wob1"] = fire_hold(pb(26.0, 2.0, -0.02, 8.0, 3.0, 8.0), (0.58, -0.4, -1.5), 28.0, yaw=16.0,
                           rolls=(R0 - 10.0, R0, R0 + 10.0), eas=(E0,))
L.arm_to("Left", (-1.1, 0.5, -1.0), elbow_away=(0.4, 1.0, 0.3))
look(8.0, 8.0); rec("wob1", report["wob1"]); L.key(15)
# 0.73 wobble forward
report["wob2"] = fire_hold(pb(26.0, -1.0, 0.08, 4.0, 0.0), (0.6, -0.4, -1.5), 40.0, yaw=26.0,
                           rolls=(R0 - 10.0, R0, R0 + 10.0), eas=(E0,))
L.arm_to("Left", (-1.25, -0.2, -0.6), elbow_away=(-0.4, -0.2, 1.0))
look(10.0, 6.0); rec("wob2", report["wob2"]); L.key(22)
# 0.90 settle
report["wob3"] = fire_hold(pb(14.0, -2.0, 0.1, 0.0, -2.0), (0.65, -0.45, -1.4), 34.0, yaw=36.0,
                           rolls=(R0 - 10.0, R0, R0 + 10.0), eas=(E0,))
free_left(0.3)
look(12.0, 2.0); rec("wob3", report["wob3"]); L.key(27)
# 1.13 lowering toward the torch hold
body(yaw=-4.0, lean=-3.0, drop=0.12, wy=-3.0, wb=-2.0)
report["lower"] = gturn(L.hold((0.75, 0.0, -1.05), yaw=78.0, elev=-9.0, roll=10.0, elbow_away=R_EA))
free_left(0.1)
look(16.0, -2.0); L.key(34)
ready(0.0, math.sin(1.1), math.sin(2.3)); L.key(42)            # 1.40 back to Ready (its first pose)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in report.items():
    print("REPORT pose", k, v)
L.finish(SPEC, OUT, extra_times=[0.07, 0.13, 0.3, 0.5])
if os.environ.get("DBG"):
    for view in os.environ["DBG"].split(","):
        for kind, pc, ex in (("Ready", 4, None), ("ChargeLo", 4, None), ("ChargeHi", 4, None),
                             ("Fire", 1, [0.07, 0.13, 0.3]), ("Fire", 1, [0.5, 0.73, 0.9, 1.13, 1.4])):
            name = "dbg_%s_%s%s.png" % (view, kind, "b" if ex and len(ex) > 3 else "")
            L.render_sheet(SPEC, os.path.join(OUT, name), view=view, kinds=[kind], per_clip=pc,
                           size=(480, 300), extra_times=ex)
