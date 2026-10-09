"""27 Orbital Cannon -- silver cannon, orbit rings around a blue crystal core: the whole body ORBITS.

The player stands side-on on the pad (down-track = their LEFT, away from the pad camera); the
cannon is carried well out on the character's FRONT side (screen-right) so the camera sees it and
the big core + rings stay clear of the head and chest.
  Ready    cannon at the right hip, muzzle raised, left hand under the core; a slow ORBITAL sway:
           the muzzle traces one slow circle per loop while the body circles with it (+ two breaths).
  ChargeLo aimed down the track; the upper body and cannon swing through one big, slow planet-like
           orbit in the camera's screen plane (lean/bend circling front-back, hips rising/sinking,
           the cannon translating and the muzzle circling the aim line with them).
  ChargeHi the same orbit (same phase), wider, faster-feeling and braced lower, with a small fast
           epicycle riding on it (the core spinning up) + a tremor.
  Fire     the orbit tightens to dead centre (anticipation) -> the ball leaves the muzzle at FireAt
           -> a strong PUSH-BACK recoil (cannon and body driven back up-track, muzzle only climbing
           a little, staying under the ball's path) -> the orbit damps out in shrinking circles ->
           settle to the Ready carry.
Ball: hidden until it pops out of the Muzzle; blue spark burst + a spark charge effect.
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

LID = 27
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 3.0, "ChargeLo": 1.6, "ChargeHi": 1.6, "Fire": 1.8,
    "FireAt": 0.2,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "spark", "Color": [120, 170, 255], "Charge": "spark", "ChargeColor": [120, 170, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "orbital cannon: hip carry with a slow orbital sway, planet-like orbit of body+cannon while charging, big push-back recoil whose orbit damps out",
}
FEET = {"Left": (-1.05, -0.5), "Right": (0.7, 0.3)}
TRACK_LOOK = (-12.0, 1.2, -2.4)
R_ELBOW = (-0.9, 1.0, -0.15)
L_ELBOW = (0.2, 1.0, -0.1)
report = {}
# the cannon is canted a little outward (top toward the front) and carried well out in front, the
# left hand steadying the core from its near side (meta Grip2): the core + orbit rings (1.2 studs
# around a barrel 1.3 above the grip) then clear the head and chest
ROLL = 25.0

GRIP = {"q": None}      # the cannon sits rigidly in the hand: one grip rotation for every pose
# (first pass: forearm roll left unclamped, max_twist 179, so the grip solution stays on one branch;
#  the 100-degree roll clamp flipped branches mid-loop and snapped the hand ~70 deg in one frame)


def cannon(at, yaw, elev, roll=0.0, elbow=R_ELBOW, give=25.0):
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow, max_twist=179.0)
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
    info["d_raw"] = round(d, 1)
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


def gap():
    return round((L.hand_cf("Left").translation - L.launcher_point(L.load_meta(LID)["Grip2"]["pos"])).length, 3)


G2 = L.load_meta(LID)["Grip2"]["pos"]


def grab(at, yaw, elev, roll=None, elbow=R_ELBOW, give=25.0, tol=0.06):
    """cannon + left hand on Grip2; when the left hand falls short, the whole cannon slides toward
    it (orientation kept) until the hand reaches"""
    if roll is None:
        roll = ROLL
    at0 = Vector(at)
    at = Vector(at)
    for _ in range(6):
        info = cannon(at, yaw, elev, roll=roll, elbow=elbow, give=give)
        info["left"] = left()
        d = L.hand_cf("Left").translation - L.launcher_point(G2)
        if d.length <= tol:
            break
        at = at + 0.9 * d
    info["shift"] = round((at - at0).length, 3)
    return info


# ------------------------------------------------------------------ poses
def ready(ph):
    """ph 0..1 around the loop: one slow orbital circle (screen plane) of body + muzzle + two breaths"""
    c, s = math.cos(2.0 * math.pi * ph), math.sin(2.0 * math.pi * ph)
    b = 0.5 - 0.5 * math.cos(4.0 * math.pi * ph)     # breathing
    body(yaw=12.0 + 1.5 * c, lean=-4.0 + 1.0 * b + 2.5 * c, drop=0.2 - 0.03 * b - 0.04 * s, back=0.05, side=0.04 * c,
         waist_yaw=3.0 + 1.5 * c, waist_bend=1.0 + 2.0 * b + 2.0 * c, roll=1.0 * c, waist_roll=-1.5 * c)
    at = (0.3, -0.88 + 0.03 * b + 0.11 * s, -1.62 + 0.13 * c)
    info = grab(at, yaw=24.0 - 8.0 * c, elev=22.0 + 8.0 * s + 1.5 * b, give=20.0)
    L.head_look(target=(-9.0 + 0.5 * c, 2.6 + 0.3 * b, -3.8 + 0.6 * c))
    return info


N_CH = 48       # keys per charge loop (every frame, 48 frames = 1.6 s)


def orbit(i, depth, amp=1.0, ph0=0.0):
    """i = key index over the loop; depth 0 = ChargeLo, 1 = ChargeHi. One big orbit per loop in the
    camera's screen plane (z = left/right on screen, y = up): lean/bend + cannon z on cos, hip
    drop + cannon y + elevation on sin (same phase in Lo and Hi). Hi adds a fast epicycle (3 per
    loop) + a tremor. amp scales the orbit (Fire uses it to wind the circle down)."""
    th = 2.0 * math.pi * i / N_CH + ph0
    c, s = math.cos(th), math.sin(th)
    A = (1.4 + 0.8 * depth) * amp                     # orbit size
    ec, es = depth * amp * math.cos(3.0 * th), depth * amp * math.sin(3.0 * th)   # epicycle
    tr = depth * amp * math.sin(6.0 * th)             # tremor (6 per loop, keyed every frame)
    body(yaw=13.0 + 2.0 * depth + 1.5 * A * c,
         lean=-6.0 - 2.0 * depth + 4.5 * A * c + 0.4 * tr,
         drop=0.34 + 0.2 * depth - 0.14 * A * s + 0.01 * tr,
         back=0.06 + 0.08 * depth,
         side=-0.1 - 0.06 * depth + 0.04 * A * c,
         waist_yaw=4.0 + 2.0 * depth + 1.0 * A * c,
         waist_bend=1.0 - 1.0 * depth + 3.5 * A * c + 0.8 * es,
         roll=1.0 * A * c,
         waist_roll=-1.5 * A * c - 1.0 * ec)
    at = (0.36 - 0.04 * depth,
          -0.85 - 0.08 * depth + 0.17 * A * s + 0.04 * es + 0.01 * tr,
          -1.88 - 0.06 * depth + 0.17 * A * c + 0.04 * ec)
    info = grab(at, yaw=8.0 - 5.5 * A * c - 1.5 * ec + 0.4 * tr,
                elev=8.0 + 6.0 * A * s + 1.5 * es + 0.4 * tr, give=36.0)
    L.head_look(target=(TRACK_LOOK[0], TRACK_LOOK[1] + 0.5 * s, TRACK_LOOK[2] + 0.5 * c))
    return info


# ------------------------------------------------------------------ clips
L.new_clip("Ready"); PREV.clear()
NR = 15
for i in range(NR):
    r = ready(i / NR)
    if i in (0, 4, 8, 12):
        report["ready_%d" % i] = r
    key(i * 90 // NR)
ready(0.0); key(90)
L.make_cyclic("Ready")
READY_PREV = dict(PREV)

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind); PREV.clear(); PREV.update(READY_PREV)
    for i in range(N_CH):
        r = orbit(i, depth)
        if i % 6 == 0:
            print("REPORT_W %s %d over=%s bend=%.0f err=%.3f shift=%.2f d=%s gn=%s" % (kind, i, r["arm_overreach"], r["wrist_bend_deg"], r["wrist_err"], r["shift"], r.get("d_raw"), r.get("gn")))
        if i in (0, 12, 24, 36):
            report["%s_%d" % (kind, i)] = r
        key(i)
    orbit(0, depth); key(N_CH)
    L.make_cyclic(kind)


def settle(ph, amp, frame, name=None):
    """damped orbit after the recoil: phase ph (turns), amp 1 = a charge-size circle, 0 = still
    (the same screen-plane circle as the charge orbit, winding down)"""
    c, s = math.cos(2.0 * math.pi * ph), math.sin(2.0 * math.pi * ph)
    body(yaw=13.0 + 1.5 * amp * c, lean=-5.0 + 6.0 * amp * c, drop=0.28 - 0.12 * amp * s, back=0.1,
         side=-0.05 + 0.04 * amp * c, waist_yaw=3.0 + 1.5 * amp * c, waist_bend=2.0 + 4.0 * amp * c,
         roll=1.0 * amp * c, waist_roll=-1.5 * amp * c)
    at = (0.32, -0.86 + 0.2 * amp * s, -1.75 + 0.2 * amp * c)
    info = grab(at, yaw=16.0 - 6.0 * amp * c, elev=16.0 + 7.0 * amp * s, give=32.0)
    L.head_look(target=(-11.0, 2.6, -3.0))
    if name:
        report[name] = info
    key(frame)


L.new_clip("Fire"); PREV.clear(); PREV.update(READY_PREV)
orbit(0, 1.0); key(0)                                              # 0.00 the ChargeHi pose
# 0.07 the orbit tightens: a quarter turn at half size, sinking into the brace
orbit(N_CH // 4, 1.0, amp=0.45); key(2)
# 0.13 LOCK ON: dead centre, squeezed down into the brace
body(yaw=15.0, lean=-11.0, drop=0.5, back=0.16, side=-0.18, waist_yaw=6.0, waist_bend=-3.0)
report["lock"] = grab((0.28, -1.02, -1.95), yaw=9.0, elev=11.0, give=32.0)
L.head_look(target=TRACK_LOOK); key(4)
# 0.20 FIRE: level down the track
body(yaw=15.0, lean=-11.0, drop=0.48, back=0.15, side=-0.18, waist_yaw=6.0, waist_bend=-2.0)
report["fire"] = grab((0.28, -0.98, -1.95), yaw=9.5, elev=14.0, give=32.0)
L.head_look(target=TRACK_LOOK); key(6)
# 0.27 the shove: the whole cannon is driven BACK up-track (toward the camera) and down a touch
body(yaw=12.0, lean=-3.0, drop=0.46, back=0.28, side=-0.02, waist_yaw=3.0, waist_bend=5.0, roll=-2.0, waist_roll=-2.0)
report["shove"] = grab((0.72, -0.96, -1.72), yaw=12.0, elev=22.0, give=40.0)
L.head_look(target=(-10.0, 2.6, -2.6)); key(8)
# 0.33 PUSH-BACK peak: body rocked back, hips back, muzzle only partly up (below the ball's path)
body(yaw=10.0, lean=5.0, drop=0.42, back=0.34, side=0.06, waist_yaw=0.0, waist_bend=9.0, roll=-3.0, waist_roll=-3.0)
report["kick"] = grab((0.8, -0.86, -1.6), yaw=14.0, elev=29.0, give=45.0)
L.head_look(target=(-9.0, 3.4, -2.6)); key(10)
# the orbit damps out: shrinking circles around the settle pose
settle(0.0, 1.1, 16, "damp1")
settle(0.25, 0.9, 20, "damp1b")
settle(0.5, 0.7, 24, "damp2")
settle(0.75, 0.45, 29, "damp3")
settle(1.0, 0.25, 35, "damp4")
settle(1.25, 0.08, 41, "damp5")
ready(0.0); report["back"] = {"left_gap": gap()}; key(48)
ready(0.0); key(54)                                                # 1.80 the Ready carry
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

L.use_clip("Fire")
_diag = []
for _i in range(0, 55, 2):
    L.goto(_i / 30.0)
    _diag.append("%d:%.2f/%.2f" % (_i, gap(), L.launcher_lowest_y()))
print("REPORT_GAP", " ".join(_diag))
for k, v in report.items():
    print("REPORT_POSE", k, v)
L.finish(SPEC, OUT, extra_times=[0.07, 0.13, 0.27, 0.33, 0.43, 0.57, 0.73, 0.97, 1.17])
