"""28 Nebula Accelerator -- purple galaxy gun, three ring frames on a rail: the ball ACCELERATES
through the rings, so the whole motion is a SPIRAL that tightens onto the aim line.

The player stands side-on on the pad (down-track = their LEFT, away from the pad camera); the gun
is carried LOW and well out in FRONT of the body (screen-right) so the tall ring rail stays clear
of the face and the camera sees it.
  Ready    gun at the right hip, muzzle raised toward the track, left hand under the rail; a slow
           weightless DRIFT (lissajous float of the muzzle, a lazy roll) + two breaths.
  ChargeLo the snowball appears hovering in ring 1 and swells; aimed down the track at chest
           height, the muzzle SPIRALS INWARD: two shrinking circles around the aim line (the gun
           rolls with the spiral like a turning galaxy), then drifts back out and is reeled in again.
  ChargeHi the same spiral (same phase), wider, braced lower with the gun pushed down and
           forward with the crouch, a fast tight wobble riding on it + a tremor: tension.
  Fire     the spiral snaps to dead centre -> ACCELERATING PUSH: both arms drive the gun forward
           along the aim line -> the ball shoots from ring 1 through rings 2 and 3 at FireAt ->
           a short hold, then a HARD kick back (gun thrown up, torso shoved back) with an
           overshoot + settle -> a couple of fading spiral drifts -> the Ready hip carry.
Ball: shown from charge start in the Seat inside ring 1 (grows from 0.6), leaves from the Seat
along the rail; violet spark burst + a violet spark charge effect.
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

LID = 28
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)
PROBE = os.environ.get("PROBE") == "1"

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.6, "ChargeHi": 1.6, "Fire": 1.6,
    "FireAt": 0.17,
    "Ball": {"show": "Charge", "start": "Seat", "grow": 0.6},
    "Fx": {"Style": "spark", "Color": [200, 140, 255], "Charge": "spark", "ChargeColor": [200, 140, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "nebula accelerator: hip carry drifting weightless, ball hovers in ring 1 while the muzzle spirals inward onto the aim line, accelerating forward push shoots it through the rings, then a hard kick back",
}
FEET = {"Left": (-1.05, -0.5), "Right": (0.7, 0.3)}
TRACK_LOOK = (-12.0, 1.2, -2.2)
# UP-ish poles (the brief's elbow rule): elbows hang down and out
R_ELBOW = (-0.7, 1.0, -0.4)
L_ELBOW = (1.0, 0.8, -0.2)
PIN_K = 0.6            # 1 = the gun turns exactly about the left hand, 0 = about the grip
report = {}

GRIP = {"q": None}      # the gun sits rigidly in the hand: one grip rotation (with a little give)
GIVE = 12.0             # max deg the grip may turn vs the reference (seeded from the aim pose)


G2 = L.load_meta(LID)["Grip2"]["pos"]
A0 = L.look_frame((0.0, -1.0, 0.0), (0.0, 0.0, -1.0))


def g2_off(yaw, elev, roll=0.0):
    """world offset pivot -> Grip2 for the gun aimed (yaw, elev, roll)"""
    f = L.direction(yaw, elev)
    R = L.look_frame(f, L.up_for(f, roll)) @ A0.inverted()
    return R @ (L.Vector(G2) * L.LAUNCHER_SCALE)


REACH0, REACH_CAP = 1.36, 1.5    # shoulder -> wrist: soft-clamped so targets stay ~0.15 inside reach


def _soft(d):
    if d <= REACH0:
        return d
    w = REACH_CAP - REACH0
    return REACH0 + w * math.tanh((d - REACH0) / w)


def _hold(at, **kw):
    """L.hold with a SOFT reach clamp: the gun is pulled toward the shoulder (orientation kept) so
    the right arm never straightens fully (no straight <-> bent elbow pops between keys)"""
    at0 = L.Vector(at)
    info = L.hold(tuple(at0), **kw)
    sh = L.joint("RightUpperArm")
    off = L.joint("RightHand") - L.pivot_cf().translation          # wrist relative to the grip
    v = at0 + off - sh
    d = v.length
    if d <= REACH0 + 1e-3:
        return info
    want_w = sh + v.normalized() * _soft(d)                        # the wrist point we accept
    for _ in range(3):
        at = want_w - off
        info = L.hold(tuple(at), **kw)
        off_n = L.joint("RightHand") - L.pivot_cf().translation
        if (off_n - off).length < 0.004:
            break
        off = off_n
    return info


def gun(at, yaw, elev, roll=0.0, elbow=R_ELBOW, give=None, pin=None, pin_k=None):
    """pin = (yaw0, elev0, roll0): `at` is the pivot at that reference aim, and the gun turns about
    the LEFT hand (Grip2) instead of the grip, so the support hand stays put while the muzzle moves"""
    give = GIVE if give is None else give
    if pin is not None:
        k = PIN_K if pin_k is None else pin_k
        at = tuple(L.Vector(at) + k * (g2_off(*pin) - g2_off(yaw, elev, roll)))
    info = _hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow)
    if GRIP["q"] is None:
        GRIP["q"] = L.get_rot("Launcher").copy()
        return info
    g0, gn = GRIP["q"], L.get_rot("Launcher").copy()
    if g0.dot(gn) < 0.0:
        gn = -gn
    d = math.degrees(g0.rotation_difference(gn).angle)
    gq = g0.slerp(gn, min(1.0, give / d)) if d > 1e-3 else g0
    info = _hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow, grip_twist=gq)
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


def gap():
    return round((L.hand_cf("Left").translation - L.launcher_point(L.load_meta(LID)["Grip2"]["pos"])).length, 3)


def smoothstep(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


# ------------------------------------------------------------------ diagnostics
def _verts():
    ob = L.launcher_object()
    L.update()
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    M = np.array(ob.matrix_world)
    w = co @ M[:3, :3].T + M[:3, 3]
    return np.stack([w[:, 0], w[:, 2], -w[:, 1]], 1)


def _inside(pts, box, half):
    inv = np.array(box.inverted())
    q = pts @ inv[:3, :3].T + inv[:3, 3]
    d = np.array(half) - np.abs(q)
    ins = (d > 0).all(1)
    return int(ins.sum()), (float(d[ins].min(1).max()) if ins.any() else 0.0)


def _seg(a, b, t0=0.0, t1=1.0, n=9):
    a, b = np.array(a), np.array(b)
    return np.array([a + (b - a) * (t0 + (t1 - t0) * i / (n - 1)) for i in range(n)])


def diag():
    """penetration depths (studs) of the launcher / forearms into the body blocks + right arm fold"""
    boxes = {n: (bx, h) for n, bx, h in L.body_boxes()}
    V = _verts()
    out = {}
    for part in ("Head", "UpperTorso", "LowerTorso", "RightUpperArm", "LeftUpperArm", "LeftLowerArm"):
        c, d = _inside(V, *boxes[part])
        out["L>" + part] = round(d, 2)
    j = {n: np.array(L.joint(n)) for n in ("RightUpperArm", "RightLowerArm", "RightHand",
                                            "LeftUpperArm", "LeftLowerArm", "LeftHand")}
    lh = np.array(L.hand_cf("Left").translation)
    out["lfore>Head"] = round(_inside(_seg(j["LeftLowerArm"], lh), *boxes["Head"])[1], 2)
    out["rfore>UT"] = round(_inside(_seg(j["RightLowerArm"], j["RightHand"], 0.3), *boxes["UpperTorso"])[1], 2)
    out["lup>UT"] = round(_inside(_seg(j["LeftUpperArm"], j["LeftLowerArm"], 0.35), *boxes["UpperTorso"])[1], 2)
    u, f = j["RightUpperArm"] - j["RightLowerArm"], j["RightHand"] - j["RightLowerArm"]
    out["r_elbow"] = round(math.degrees(math.acos(max(-1, min(1, u.dot(f) / np.linalg.norm(u) / np.linalg.norm(f))))), 0)
    out["r_sw"] = round(float(np.linalg.norm(j["RightHand"] - j["RightUpperArm"])), 2)
    out["wrist"] = round(math.degrees(L.swing_twist(L.get_rot("RightHand"))[0].angle), 0)
    out["lsh"] = [round(float(v), 2) for v in j["LeftUpperArm"]]
    out["g2w"] = [round(float(v), 2) for v in L.launcher_point(G2)]
    out["head"] = [round(float(v), 2) for v in L.joint("Head")]
    return out


def clip_diag(kind, length):
    L.use_clip(kind)
    worst = {}
    for i in range(0, int(round(length * 30)) + 1, 2):
        L.goto(i / 30.0)
        d = diag()
        d["gap"] = gap()
        for k, v in d.items():
            if k in ("lsh", "g2w", "head"):
                continue
            lo = k in ("r_elbow", "r_sw")
            if k not in worst or (v < worst[k][0] if lo else v > worst[k][0]):
                worst[k] = (v, round(i / 30.0, 2))
    print("REPORT_DIAG", kind, " ".join("%s=%s@%s" % (k, v[0], v[1]) for k, v in worst.items()))


# ------------------------------------------------------------------ poses
def ready(ph):
    """ph 0..1 around the loop: a weightless lissajous drift (1:2) + two breaths"""
    a = 2.0 * math.pi * ph
    c, s, s2 = math.cos(a), math.sin(a), math.sin(2.0 * a)
    b = 0.5 - 0.5 * math.cos(2.0 * a)                  # breathing
    body(yaw=12.0 + 2.0 * c, lean=-2.0 + 1.5 * b, drop=0.14 - 0.03 * b, back=0.05, side=0.05 * c,
         waist_yaw=4.0 + 2.0 * c, waist_bend=2.0 + 2.0 * b + 1.0 * s2, roll=1.5 * c, waist_roll=-2.0 * c)
    at = (0.84 + 0.04 * c, -0.74 + 0.04 * b + 0.04 * s2, -1.42 - 0.02 * c)
    info = gun(at, yaw=11.0 + 7.0 * c, elev=17.0 + 4.0 * s2 + 1.5 * b, roll=6.0 * s, pin=(11.0, 17.0, 0.0))
    info["left"] = left()
    L.head_look(target=(-9.0 + 0.5 * c, 2.5 + 0.3 * b, -3.5 + 0.8 * c))
    return info


N_CH = 24       # keys per charge loop (every 2 frames, 48 frames = 1.6 s)
TURNS = 2.0     # spiral turns per loop


def spiral_r(p):
    """spiral radius over the loop: reels in 1 -> 0.12 over the first 78 %, drifts back out after"""
    if p <= 0.78:
        return 1.0 - 0.88 * smoothstep(p / 0.78)
    return 0.12 + 0.88 * smoothstep((p - 0.78) / 0.22)


SP = dict(drop=0.62, lean=-12.0)   # Hi crouch (tuned so the rail clears the face)


def spiral(i, depth):
    """i = key index over the loop; depth 0 = ChargeLo, 1 = ChargeHi (same phase)."""
    p = i / N_CH
    th = 2.0 * math.pi * TURNS * p + math.pi      # starts on the back side of the circle
    r = spiral_r(p) * (1.0 + 1.0 * depth)             # Hi: a spiral twice as wide (+-17 deg)
    c, s = r * math.cos(th), r * math.sin(th)
    wob = depth * 0.6                                 # Hi: a fast tight wobble (6 per loop)
    wc, ws = wob * math.cos(12.0 * math.pi * p), wob * math.sin(12.0 * math.pi * p)
    tr = depth * (math.sin(2.0 * math.pi * 7.0 * p) + 0.5 * math.sin(2.0 * math.pi * 11.0 * p + 1.0))
    body(yaw=10.0 + 2.0 * depth + 2.0 * c,
         lean=-6.0 + (SP["lean"] + 6.0) * depth + 2.0 * s,
         drop=0.3 + (SP["drop"] - 0.3) * depth + 0.03 * s + 0.035 * tr,
         back=0.06 + 0.08 * depth,
         side=-0.1 - 0.08 * depth + 0.06 * c,
         waist_yaw=5.0 + 2.0 * depth + 2.0 * c,
         waist_bend=1.0 - 3.0 * depth + 3.0 * s + 0.8 * ws,
         roll=2.0 * c,
         waist_roll=-3.0 * c - 1.0 * wc)
    at = (0.56 - 0.03 * depth + 0.05 * c,
          -0.62 - 0.37 * depth + 0.08 * s + 0.03 * ws + 0.035 * tr,
          -1.86 - 0.42 * depth + (0.07 * depth - 0.04 * (1.0 - depth)) * c + 0.03 * wc + 0.02 * tr)
    info = gun(at, yaw=3.5 + 8.5 * c + 2.0 * wc + 1.8 * tr,
               elev=6.0 + 8.5 * s + 2.0 * ws + 1.8 * tr,
               roll=-14.0 * math.sin(th) * spiral_r(p), pin=(3.5, 6.0, 0.0),
               pin_k=PIN_K - 0.2 * depth)     # Hi: the seat circles too (spiral reads end-on)
    info["left"] = left()
    L.head_look(target=TRACK_LOOK)
    return info


def drift(ph, amp):
    """fading spiral drift after the kick: phase ph (turns), amp 1 = a charge-size circle"""
    c, s = amp * math.cos(2.0 * math.pi * ph), amp * math.sin(2.0 * math.pi * ph)
    body(yaw=14.0 + 2.5 * c, lean=-3.0 + 2.0 * s, drop=0.22 + 0.03 * s, back=0.1,
         side=-0.04 + 0.06 * c, waist_yaw=4.0 + 2.0 * c, waist_bend=3.0 + 3.0 * s,
         roll=1.5 * c, waist_roll=-2.5 * c)
    at = (0.82 + 0.05 * c, -0.72 + 0.07 * s, -1.45 - 0.03 * c)
    info = gun(at, yaw=13.0 + 7.0 * c, elev=16.0 + 7.0 * s, roll=-10.0 * s, pin=(13.0, 16.0, 0.0))
    info["left"] = left()
    L.head_look(target=(-11.0, 3.0, -2.5))
    return info


LOCK = dict(b=dict(yaw=10.0, lean=-6.0, drop=0.5, back=0.24, side=0.12, waist_yaw=4.0, waist_bend=0.0, roll=2.0, waist_roll=0.0),
            at=(0.9, -0.92, -2.05), yaw=4.0, elev=4.0, look=TRACK_LOOK)
PUSH = dict(b=dict(yaw=17.0, lean=-13.0, drop=0.52, back=0.04, side=-0.62, waist_yaw=9.0, waist_bend=-6.0, roll=-3.0, waist_roll=0.0),
            at=(0.25, -0.84, -2.35), yaw=4.0, elev=5.0, look=TRACK_LOOK)
# 0.20: the thrust carries on past the shot (linear through FireAt = fastest when the ball leaves)
THRUST = dict(b=dict(yaw=18.0, lean=-14.0, drop=0.52, back=0.02, side=-0.7, waist_yaw=10.0, waist_bend=-7.0, roll=-3.5, waist_roll=0.0),
              at=(0.1, -0.83, -2.4), yaw=4.0, elev=5.0, look=TRACK_LOOK)
KICK = dict(b=dict(yaw=13.0, lean=9.0, drop=0.42, back=0.3, side=0.1, waist_yaw=0.0, waist_bend=8.0, roll=-5.0, waist_roll=-5.0),
            at=(0.78, -0.42, -1.42), yaw=8.0, elev=40.0, look=(-8.0, 5.5, -2.4))
SETTLE = dict(b=dict(yaw=15.0, lean=-5.0, drop=0.36, back=0.16, side=-0.04, waist_yaw=4.0, waist_bend=1.0, roll=-1.0, waist_roll=-1.0),
              at=(0.5, -0.76, -1.95), yaw=7.0, elev=12.0, look=(-10.0, 3.0, -2.4))


def mix(a, b, t):
    """parameter blend of two fire key poses (IK re-solved, so the hands stay on the gun)"""
    lerp = lambda x, y: x + (y - x) * t
    return dict(b={k: lerp(a["b"][k], b["b"][k]) for k in a["b"]},
                at=tuple(lerp(x, y) for x, y in zip(a["at"], b["at"])),
                yaw=lerp(a["yaw"], b["yaw"]), elev=lerp(a["elev"], b["elev"]),
                look=tuple(lerp(x, y) for x, y in zip(a["look"], b["look"])))


def fire_pose(p):
    body(**p["b"])
    info = gun(p["at"], yaw=p["yaw"], elev=p["elev"], pin=(4.0, 5.0, 0.0))
    info["left"] = left()
    L.head_look(target=p["look"])
    return info


def lock_pose():
    """0.10 LOCK: the spiral snaps to dead centre, a small draw back + squeeze into the brace"""
    return fire_pose(LOCK)


def push_pose():
    """0.17 PUSH (FireAt): both arms thrust the gun forward along the aim line, body lunges in"""
    return fire_pose(PUSH)


def kick_pose():
    """0.30 HARD KICK: the gun is thrown up and back, torso shoved back, hips back"""
    return fire_pose(KICK)


# ------------------------------------------------------------------ one grip for every pose
POSES = [lambda: ready(0.0), lambda: ready(0.5), lambda: spiral(0, 0.0), lambda: spiral(3, 1.0),
         lambda: spiral(6, 1.0), lambda: spiral(9, 1.0), lambda: spiral(18, 0.0), lock_pose, push_pose, kick_pose,
         lambda: fire_pose(THRUST),
         lambda: drift(0.25, 1.2), lambda: ready(0.25), lambda: ready(0.75)]
free = []
GRIP["q"] = None
for pf in POSES:
    GRIP["q"] = None
    pf()
    free.append(GRIP["q"].copy() if GRIP["q"] is not None else L.get_rot("Launcher").copy())
cands = list(free)
for i in range(len(free)):
    for j in range(i + 1, len(free)):
        a, b = free[i], free[j]
        if a.dot(b) < 0.0:
            b = -b
        cands.append(a.slerp(b, 0.5))
best = None
GIVE_SAVE = GIVE
for q in cands:
    GRIP["q"] = q
    GIVE = 0.0
    worst, cost = 0.0, 0.0
    for pf in POSES:
        info = pf()
        sw, _ = L.swing_twist(L.get_rot("RightHand"))
        bend = math.degrees(sw.angle)
        worst = max(worst, bend)
        cost += max(0.0, bend - 55.0) + 300.0 * info["arm_overreach"] + 60.0 * gap()
    cost += 2.0 * max(0.0, worst - 75.0)
    if best is None or cost < best[0]:
        best = (cost, q, worst)
GIVE = GIVE_SAVE
GRIP["q"] = best[1]
print("REPORT_GRIP cost %.1f worst %.1f of %d" % (best[0], best[2], len(cands)))


def run_key(fn, frame, name=None):
    info = fn()
    info["mz"] = [round(v, 2) for v in L.launcher_point(L.load_meta(LID)["Muzzle"]["pos"])]
    info["gap"] = gap()
    if name:
        info.update(diag())
        report[name] = info
    key(frame)


# ------------------------------------------------------------------ clips
L.new_clip("Ready"); PREV.clear()
NR = 18
for i in range(NR):
    run_key(lambda: ready(i / NR), i * 72 // NR, "ready_%d" % i if i in (0, 4, 9, 13) else None)
run_key(lambda: ready(0.0), 72)
L.make_cyclic("Ready")
READY_PREV = dict(PREV)

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind); PREV.clear(); PREV.update(READY_PREV)
    for i in range(N_CH):
        run_key(lambda: spiral(i, depth), i * 2, "%s_%d" % (kind, i) if i in (0, 6, 12, 18) else None)
    run_key(lambda: spiral(0, depth), N_CH * 2)
    L.make_cyclic(kind)

L.new_clip("Fire"); PREV.clear(); PREV.update(READY_PREV)
run_key(lambda: spiral(0, 1.0), 0)                                # 0.00 the ChargeHi pose
run_key(lock_pose, 3, "lock")                                     # 0.10 lock on
run_key(push_pose, 5, "push")                                     # 0.17 push = FireAt (still moving)
run_key(lambda: fire_pose(THRUST), 6, "thrust")                   # 0.20 the thrust carries through
run_key(lambda: fire_pose(mix(THRUST, KICK, 0.05)), 7, "hold")    # 0.23 aim held till ring 3 is cleared
SNAP = mix(THRUST, KICK, 0.55)
SNAP["look"] = (-7.0, 7.0, -1.4)                                  # the head snaps back with the kick
run_key(lambda: fire_pose(SNAP), 8, "kick_mid")                   # 0.27 the kick + head snap
run_key(kick_pose, 10, "kick")                                    # 0.33 hard kick peak
run_key(lambda: fire_pose(SETTLE), 14, "settle")                  # 0.47 recoil settles forward
run_key(lambda: drift(0.3, 1.0), 20, "drift1")                    # fading spiral drifts
run_key(lambda: drift(0.6, 0.65), 26, "drift2")
run_key(lambda: drift(0.9, 0.35), 32, "drift3")
run_key(lambda: drift(1.15, 0.12), 38, "drift4")
run_key(lambda: ready(0.0), 44, "back")
run_key(lambda: ready(0.0), 48)                                   # 1.60 the Ready carry
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
# lock -> push -> thrust LINEAR: the gun accelerates out of the draw-back and is moving fastest
# when the ball leaves (no ease into the shot)
L.set_interpolation("Fire", 'LINEAR', 'AUTO_CLAMPED', frames=[3, 5])

for k, v in report.items():
    print("REPORT_POSE", k, {kk: vv for kk, vv in v.items()
                             if kk in ("arm_overreach", "gap", "mz", "r_elbow", "r_sw", "wrist") or (kk[:2] in ("L>", "lf", "rf") and vv)})
for kind in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
    clip_diag(kind, SPEC[kind])
L.use_clip("Fire")
L.goto(SPEC["FireAt"])
_mz = L.pivot_cf() @ L._meta_frame(L.load_meta(LID), "Muzzle")
_look = (_mz.to_3x3() @ L.Vector((0.0, 0.0, -1.0))).normalized()
_st = L.seat_point(SPEC)
_fl = []
for _i in range(0, 9):
    _c, _who = L.clearance(_st + _look * (0.5 * _i))
    _fl.append("%.1f:%s/%.2f" % (0.5 * _i, _who, _c - L.BALL_RADIUS))
print("REPORT_FLIGHT", " ".join(_fl))
if not PROBE:
    L.finish(SPEC, OUT, extra_times=[0.1, 0.2, 0.23, 0.27, 0.33, 0.47, 0.67, 0.87, 1.07, 1.27])
