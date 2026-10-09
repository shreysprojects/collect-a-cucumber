"""30 Galactic Rocket Launcher -- a galaxy rocket tube with fins, fired off the right shoulder from a kneel.

The player stands side-on on the pad (down-track = their LEFT, away from the camera; the pad camera
sees their right side / back).
  Ready    split stance, half turned toward the track, the tube resting ON the right shoulder and
           pointing up-forward, right fist on the rear pistol grip, left arm loose; breathing with a
           visible shoulder rise + a slow weight shift.
  ChargeLo a real one-knee kneel: the right knee + shin rest on the floor, the right heel up (toes
           tucked at the Ready foot spot), the left shin vertical with the foot flat.  The body is
           bladed ~50 deg to the track, the tube comes down level on the right shoulder and aims down
           the track, LEFT hand on the front grip, head canted to the sight; slow aim drift.
  ChargeHi the same kneel sat back and hunched down onto the tube (chest over the grip), a strong
           spooling-up tremor through the tube, the torso and the head (spark charge FX).
  Fire     brace -> WHOOSH at FireAt: the ball blasts out of the flared front, the backblast out of
           the rear -> the tube kicks back on the shoulder, the pelvis rocks back over the heel ->
           watch it fly -> let go of the front grip, push off the left knee and stand back up.
"""
import importlib
import itertools
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)
from mathutils import Vector, Quaternion
import numpy as np

LID = 30
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)
PROBE = os.environ.get("R30_PROBE", "")

FIRE_FRAME = 5
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.7,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Never", "start": "Muzzle", "grow": 1.0},
    "Fx": {"Style": "fire", "Color": [190, 120, 255], "Charge": "spark", "ChargeColor": [120, 220, 255]},
    "TwoHanded": True,
    "AllowFootLift": True,
    "Notes": "galactic bazooka: tube on the right shoulder, drop to one knee, left hand on the front grip, aim down the track, whoosh out of the front with a backblast, kick back, stand up",
}
FOOT_YAW = 62.0
FEET = {"Left": (-1.12, -0.06), "Right": (0.72, -0.12)}
TOE = L.ry(FOOT_YAW) @ Vector((0.0, 0.0, -1.0))              # toe direction on the floor
KNEEL_ANKLE = Vector((FEET["Right"][0], 0.0, FEET["Right"][1])) + TOE * 0.15
KNEEL_ANKLE_Y = -2.45                                         # heel up, toes tucked
META = L.load_meta(LID)
MUZ = META["Muzzle"]["pos"]
BACK = META["Back"]["pos"]
G2 = META["Grip2"]["pos"]
SKIP_PEN = ("RightHand", "RightLowerArm", "RightUpperArm", "LeftHand", "LeftLowerArm")
ELBOWS = [Vector(v).normalized() for v in (          # right-elbow hints in the UpperTorso frame
    (0.0, 1.0, 0.0), (-0.3, 1.0, 0.1), (0.3, 1.0, 0.0), (0.0, 1.0, 0.5), (0.0, 1.0, -0.5),
    (0.5, 1.0, 0.4), (-0.4, 1.0, -0.3), (0.3, 0.5, 0.8), (0.7, 0.7, 0.0), (-0.2, 0.6, 0.8),
    (0.4, 1.0, -0.4), (0.0, 0.4, 1.0),
    (1.0, -1.0, 0.0), (1.0, -1.0, 0.5), (1.0, -0.4, 0.3), (1.0, -1.0, -0.4), (1.0, 0.0, 0.5), (0.6, -0.6, 0.8))]
D_LO, D_HI = 0.8, 1.45    # shoulder->wrist distance band: elbow ~110..60 deg (0.5 = arm folded shut)
dbg = {}

# launcher vertices in the pivot frame (scaled), for the body-penetration test
L.reset_pose()
_ob = L.launcher_object()
L.update()
_Pi = L.pivot_cf().inverted()
VERTS = np.array([list(_Pi @ L.b2r(_ob.matrix_world @ v.co)) for v in _ob.data.vertices])[::2]
PARTS = {}
AVERTS = VERTS[::max(1, len(VERTS) // 150)]
_G = np.array([(i, j, k) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1)], dtype=float) * 0.8


def audit_sink(arms=("RightUpperArm", "RightLowerArm", "RightHand"), launcher=True):
    """the library's motion audit, now: deepest arm point / launcher vertex inside the torso / head
    on realistic avatar proportions (studs)"""
    bx = {}
    for n, b, h in L.body_boxes():
        hh = np.array(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else np.array(h)
        bx[n] = (np.array(b), hh)
    bodies = []
    for n in ("UpperTorso", "Head", "LowerTorso"):
        B, hh = bx[n]
        Bi = np.linalg.inv(B)
        bodies.append((n, Bi, hh))

    def depth(pts, names):
        worst = 0.0
        for n, Bi, hh in bodies:
            if n not in names:
                continue
            q = pts @ Bi[:3, :3].T + Bi[:3, 3]
            d = np.min(hh - np.abs(q), axis=1)
            if len(d):
                worst = max(worst, float(d.max()))
        return worst

    wa = 0.0
    for a in arms:
        A, ah = bx[a]
        pts = (_G * ah) @ A[:3, :3].T + A[:3, 3]
        wa = max(wa, depth(pts, ("UpperTorso", "Head", "LowerTorso")))
    wl = 0.0
    if launcher:
        P = np.array(L.pivot_cf())
        W = AVERTS @ P[:3, :3].T + P[:3, 3]
        wl = depth(W, ("UpperTorso", "Head"))
    return wa, wl


def penetration(skip=SKIP_PEN):
    P = np.array(L.pivot_cf())
    W = VERTS @ P[:3, :3].T + P[:3, 3]
    tot, worst = 0.0, 0.0
    PARTS.clear()
    for name, box, half in L.body_boxes():
        if name in skip:
            continue
        B = np.array(box.inverted())
        q = W @ B[:3, :3].T + B[:3, 3]
        d = np.min(np.array(half) - np.abs(q), axis=1)
        inside = d > 0.0
        d = d[inside]
        if len(d):
            w = 1.0 if name != "Head" else 1.5
            tot += w * float(d.sum())
            worst = max(worst, float(d.max()))
            v = VERTS[inside] / L.LAUNCHER_SCALE
            PARTS[name] = (round(float(d.sum()), 2), round(float(d.max()), 2),
                           [round(float(a), 2) for a in v.min(axis=0)], [round(float(a), 2) for a in v.max(axis=0)])
    return tot, worst


def torso():
    return L.frame_of("UpperTorso")


def shoulder_top():
    """top of the right shoulder where the tube rests (UpperTorso box corner, rest coords)"""
    m = L.world_cf("UpperTorso")
    return m @ (Vector((1.0, 1.0, 0.0)) - Vector(L.REST["UpperTorso"]))


TUBE_R = 0.86          # tube skin radius over the shoulder (scaled studs)
S_MIN, S_MAX = -0.9, 1.2


def rest_cost():
    """the tube's underside should sit ON the shoulder top (axis TUBE_R above it), the shoulder
    somewhere between the front grip and the rear block"""
    T = shoulder_top()
    a = L.launcher_point((0.0, 0.0, -0.88))
    d = L.launcher_dir((0.0, 1.0, 0.0))                    # toward the rear end
    s = (T - a).dot(d)
    dist = (T - (a + d * s)).length
    s_t = s / L.LAUNCHER_SCALE
    c = 150.0 * (dist - TUBE_R) ** 2 + 60.0 * max(0.0, TUBE_R - 0.05 - dist)
    c += 20.0 * max(0.0, S_MIN - s_t) + 20.0 * max(0.0, s_t - S_MAX)
    return c, dist, s_t


GREF = [None]          # reference grip (Launcher bone) the solver keeps close to
SIGNREF = [None]


def gref_cost():
    if GREF[0] is None:
        return 3.0 * max(0.0, gturn() - 20.0)
    q, lim, w = GREF[0]
    a = math.degrees(q.rotation_difference(L.get_rot("Launcher")).angle)
    a = min(a, 360.0 - a)
    return w * max(0.0, a - lim)


def wrist_swing():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


def gturn():
    a = math.degrees(L.get_rot("Launcher").angle)
    return 360.0 - a if a > 180.0 else a


GFIX = [None]          # once set: the launcher sits in the fist at this fixed grip in every pose


POLE_NX = 0.06        # keep the right-arm hinge axis at least this far on the torso's +X side
POLE_SOFT = 30.0      # degrees of soft-clamp before the limit (no hard mirror = no one-frame snap)
POLE_DBG = {"adj": 0.0}


def smooth_pole(e_world):
    """The library's elbow guard MIRRORS a pole whose hinge axis points into the chest (n.x < -0.15),
    a hard switch that pops the elbow when an interpolated pole crosses it.  Instead, rotate the
    hinge axis continuously (about the shoulder->wrist line) so it never reaches the guard: poles
    well inside the allowed arc are untouched, near its edge they are compressed smoothly."""
    Mt = torso()
    Mi = Mt.inverted()
    t = Mi @ (L.joint("RightHand") - L.joint("RightUpperArm"))
    if t.length < 1e-4:
        return e_world
    t.normalize()
    f = Mi @ Vector(e_world)
    n0 = t.cross(f)
    if n0.length < 1e-5:
        return e_world
    n0.normalize()
    x = Vector((1.0, 0.0, 0.0))
    uu = x - t * x.dot(t)
    if uu.length < 0.2:
        return e_world
    u = uu.normalized()
    w = t.cross(u)
    phi = math.atan2(n0.dot(w), n0.dot(u))
    pmax = math.acos(min(1.0, POLE_NX / uu.length))
    p1 = max(0.0, pmax - math.radians(POLE_SOFT))
    a = abs(phi)
    if a <= p1:
        return e_world
    a2 = p1 + (pmax - p1) * math.tanh((a - p1) / max(1e-6, pmax - p1))
    POLE_DBG["adj"] = max(POLE_DBG["adj"], math.degrees(a - a2))
    ph2 = math.copysign(a2, phi)
    n = u * math.cos(ph2) + w * math.sin(ph2)
    return Mt @ n.cross(t)


LASTPOLE = [None]


def place(Pw, yaw, elev, roll, e_local):
    fwd = L.direction(yaw, elev)
    up = L.up_for(fwd, roll)
    e = torso() @ Vector(e_local)
    info = L.place_launcher(at=Pw, forward=fwd, up=up, anchor="Pivot",
                            elbow_away=e, max_wrist=55.0, grip_twist=GFIX[0])
    e2 = smooth_pole(e)
    LASTPOLE[0] = (Vector(e), Vector(e2))
    if (e2 - e).length > 1e-6:
        for _ in range(2):
            info = L.place_launcher(at=Pw, forward=fwd, up=up, anchor="Pivot",
                                    elbow_away=e2, max_wrist=55.0, grip_twist=GFIX[0])
            LASTPOLE[0] = (Vector(e), Vector(e2))
            e2 = smooth_pole(e)
    return info


def wrist_twist():
    _, tw = L.swing_twist(L.get_rot("RightHand"))
    a = math.degrees(tw.angle)
    return 360.0 - a if a > 180.0 else a


# ------------------------------------------------------------------ pose parameters
BODY_DEF = dict(yaw=40.0, lean=-4.0, roll=0.0, drop=0.15, side=0.0, back=0.0, wyaw=15.0, wbend=-2.0, wroll=0.0,
                ox=0.0, oy=0.1, oz=-0.5, tyaw=55.0, telev=35.0, troll=40.0,
                lx=-14.0, ly=1.0, lz=-2.0, hroll=0.0, hpitch=0.0, look_tube=0.0,
                kneel=0.0, gw=0.0, kw=0.0, hx=-0.2, hy=-1.55, hz=0.1, lex=-0.3, ley=-1.0, lez=0.6,
                gex=-0.3, gey=-1.0, gez=0.1, ex=1.0, ey=-1.0, ez=0.0)
NAMES = list(BODY_DEF)


def K(f, name=None, search=True, radius=0.3, **kw):
    p = dict(BODY_DEF)
    p.update(kw)
    return {"f": f, "p": p, "name": name, "search": search, "radius": radius}


LEG_BLOCKS = ("RightUpperLeg", "RightLowerLeg", "LeftUpperLeg", "LeftLowerLeg")
FOOT_C = Vector((0.0, 2.85 - 2.9304, 0.0))            # RightFoot block centre rel. to the ankle
FOOT_H = Vector((0.5, 0.15, 0.5))


LOW_WHO = [None]


def lowest_leg():
    lo = 9.0
    for name, box, half in L.body_boxes():
        if name in LEG_BLOCKS:
            for s in itertools.product((-1, 1), repeat=3):
                if "LowerLeg" in name and s[1] < 0:
                    continue                       # the ankle end overlaps the foot (flat feet)
                c = box @ Vector((s[0] * half[0], s[1] * half[1], s[2] * half[2]))
                if c.y < lo:
                    lo = c.y
                    LOW_WHO[0] = name
    return lo


def right_leg(k):
    """right leg with the kneel weight k: 0 = foot flat at FEET, 1 = heel up, toes tucked, ankle raised"""
    fr = Vector((FEET["Right"][0], -2.9304, FEET["Right"][1]))
    ka = Vector((KNEEL_ANKLE.x, KNEEL_ANKLE_Y, KNEEL_ANKLE.z))
    s = k * k * (3.0 - 2.0 * k)
    target = fr.lerp(ka, s)
    hip = L.joint("RightUpperLeg")
    Mi = L.frame_of("LowerTorso").inverted()
    qu, ql, err = L.solve_limb(Mi @ (target - hip), L.THIGH, L.SHIN, Mi @ TOE, bend=-1.0)
    L.set_rot("RightUpperLeg", qu)
    L.set_rot("RightLowerLeg", ql)
    L.update()
    ank = L.joint("RightFoot")

    def foot_low(a):
        R = (L.ry(FOOT_YAW) @ L.rx(-a)).to_matrix()
        lo = 9.0
        for sg in itertools.product((-1, 1), repeat=3):
            c = R @ (FOOT_C + Vector((sg[0] * FOOT_H.x, sg[1] * FOOT_H.y, sg[2] * FOOT_H.z)))
            lo = min(lo, ank.y + c.y)
        return lo

    a0, a1 = 0.0, 89.0
    if foot_low(0.0) <= L.FLOOR_Y + 1e-4:
        a = 0.0
    else:
        for _ in range(24):
            m = 0.5 * (a0 + a1)
            if foot_low(m) > L.FLOOR_Y:
                a0 = m
            else:
                a1 = m
        a = 0.5 * (a0 + a1)
    want = (L.ry(FOOT_YAW) @ L.rx(-a)).to_matrix()
    L.set_rot("RightFoot", (L.frame_of("RightLowerLeg").inverted() @ want).to_quaternion())
    L.update()
    return a, err


def body(p):
    L.reset_pose()
    root = L.ry(p["yaw"]) @ L.rx(p["lean"]) @ L.rz(p["roll"])

    def legs(drop):
        L.stance(hip_drop=drop, hip_back=p["back"], hip_side=p["side"], root=root, feet=FEET, foot_yaw=FOOT_YAW)
        return right_leg(max(0.0, min(1.0, p["kneel"])))

    d = p["drop"]
    fa = legs(d)
    if lowest_leg() < L.FLOOR_Y:
        lo, hi = 0.0, d
        for _ in range(22):
            m = 0.5 * (lo + hi)
            legs(m)
            if lowest_leg() < L.FLOOR_Y:
                hi = m
            else:
                lo = m
        d = lo
        fa = legs(d)
    p["_drop"] = d
    p["_foot"] = fa[0]
    L.waist(L.ry(p["wyaw"]) @ L.rx(p["wbend"]) @ L.rz(p["wroll"]))


def head(p):
    tgt = Vector((p["lx"], p["ly"], p["lz"]))
    if p["look_tube"] > 0.0:
        m = L.launcher_point(MUZ) + L.launcher_dir((0.0, -1.0, 0.0)) * 12.0
        tgt = tgt.lerp(m, p["look_tube"])
    L.head_look(target=tgt)
    L.set_rot("Head", L.get_rot("Head") @ L.rx(p["hpitch"]) @ L.rz(p["hroll"]))
    L.update()


def pivot_target(p):
    return L.joint("RightUpperArm") + torso() @ Vector((p["ox"], p["oy"], p["oz"]))


def hand_to(side, point, elbow):
    """hand CENTRE on a point, straight wrist"""
    wrist = Vector(point) - Vector(L.HAND_CENTER)
    r = L.arm_to(side, wrist, elbow, None)
    for _ in range(2):
        wrist = Vector(point) - L.frame_of(side + "Hand") @ Vector(L.HAND_CENTER)
        r = L.arm_to(side, wrist, elbow, None)
    return r


def left_arm(p):
    sh = L.joint("LeftUpperArm")
    Mt = torso()
    free = sh + Mt @ Vector((p["hx"], p["hy"], p["hz"]))
    knee = L.joint("LeftLowerLeg")
    kdir = L.frame_of("LeftUpperLeg") @ Vector((0.0, -1.0, 0.0))
    on_knee = knee + Vector((0.0, 0.72, 0.0)) - kdir * 0.15
    w = max(0.0, min(1.0, p["kw"]))
    tgt = free.lerp(on_knee, w)
    g = max(0.0, min(1.0, p["gw"]))
    grip = L.launcher_point(G2)
    tgt = tgt.lerp(grip, g)
    e = (Mt @ Vector((p["lex"], p["ley"], p["lez"]))).lerp(Mt @ Vector((p["gex"], p["gey"], p["gez"])), g)
    r = hand_to("Left", tgt, e)
    gap = (L.hand_cf("Left").translation - grip).length
    return r, gap


def cost_now(off_len, p):
    pen, worst = penetration()
    rc, dist, s_t = rest_cost()
    sw = wrist_swing()
    c = 30.0 * pen + 200.0 * max(0.0, worst - 0.08) + 3.0 * max(0.0, sw - 35.0) + 20.0 * max(0.0, sw - 60.0) \
        + 3.0 * max(0.0, wrist_twist() - 80.0) + 30.0 * off_len + rc + gref_cost()
    el = L.joint("RightLowerArm")
    ce, _ = L.clearance(el, skip=("RightUpperArm", "RightLowerArm", "RightHand"))
    c += 150.0 * max(0.0, 0.1 - ce)
    D = arm_d()
    c += 100.0 * max(0.0, D_LO - D) + 150.0 * max(0.0, D - D_HI)
    wa, wl = audit_sink()
    c += 500.0 * max(0.0, wa - 0.1) + 500.0 * max(0.0, wl - 0.06)
    return c, pen, worst, dist, s_t, sw


def arm_d():
    return (L.joint("RightHand") - L.joint("RightUpperArm")).length


def solve_key(k, prev_e=None):
    p = k["p"]
    body(p)
    head(p)
    base = pivot_target(p)
    Mt = torso()
    best = None
    step = 0.15
    n = int(round(k["radius"] / step)) if k["search"] else 0
    elbows = ELBOWS if k["search"] else [Vector((p["ex"], p["ey"], p["ez"]))]
    rolls = [p["troll"] + r for r in k.get("rolls", (0.0,))] if k["search"] else [p["troll"]]
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            for m in range(-n, n + 1):
                off = Vector((i, j, m)) * step
                if off.length > k["radius"] + 1e-6:
                    continue
                for e in elbows:
                    for rl in rolls:
                        info = place(base + Mt @ off, p["tyaw"], p["telev"], rl, e)
                        c = cost_now(off.length, p)[0] + 300.0 * info["arm_overreach"] + 0.3 * abs(rl - p["troll"])
                        if p["gw"] > 0.5:
                            head(p)
                            (over, _), gap = left_arm(p)
                            c += p["gw"] * (250.0 * max(0.0, gap - 0.04) + 200.0 * over)
                            la, _ = audit_sink(("LeftUpperArm", "LeftLowerArm", "LeftHand"), False)
                            c += 500.0 * max(0.0, la - 0.1)
                        if prev_e is not None:
                            c += 20.0 * (e - prev_e).length
                        if best is None or c < best[0]:
                            best = (c, off, e, rl)
    c, off, e, rl = best
    p["troll"] = rl
    p["ox"] += off.x
    p["oy"] += off.y
    p["oz"] += off.z
    p["ex"], p["ey"], p["ez"] = e.x, e.y, e.z
    info = apply(p)
    if k["search"]:
        # cant the head away from the tube until it clears (cheek on the tube, not inside it)
        hr0 = p["hroll"]
        for dh in (0.0, 5.0, 10.0, 15.0, 20.0, 25.0):
            p["hroll"] = hr0 + dh
            head(p)
            penetration()
            if PARTS.get("Head", (0.0, 0.0))[1] < 0.04:
                break
        info = apply(p)
    if k["name"]:
        _, pen, worst, dist, s_t, sw = cost_now(0.0, p)
        (over, _), gap = left_arm(p)
        cb, who = L.clearance(L.launcher_point(BACK))
        dbg[k["name"]] = {"cost": round(c, 1), "off": [round(p["ox"], 2), round(p["oy"], 2), round(p["oz"], 2)],
                          "reach": info["arm_overreach"], "pen": round(pen, 2), "worst": round(worst, 2),
                          "parts": dict(PARTS), "rest_d": round(dist, 2), "rest_s": round(s_t, 2),
                          "swing": round(sw, 1), "armD": round(arm_d(), 3), "sink": [round(v, 2) for v in audit_sink()], "twist": round(wrist_twist(), 1), "gturn": round(gturn(), 1), "lgap": round(gap, 3),
                          "lover": over, "drop": round(p["_drop"], 3), "foot": round(p["_foot"], 1),
                          "legs_low": round(lowest_leg(), 3), "low_who": LOW_WHO[0],
                          "kneeR": [round(v, 2) for v in L.joint("RightLowerLeg")],
                          "kneeL": [round(v, 2) for v in L.joint("LeftLowerLeg")],
                          "back_clear": round(cb, 2), "back_near": who,
                          "muzzle": [round(v, 2) for v in L.launcher_point(MUZ)]}
    return e


def solve_keys(keys):
    prev = None
    for k in keys:
        if k.get("same_as") is not None:
            k["p"] = dict(keys[k["same_as"]]["p"])
            continue
        src = k.get("inherit_from")
        if src is not None:
            for nm in ("ox", "oy", "oz", "troll", "ex", "ey", "ez"):
                k["p"][nm] = src[nm]
        if k.get("gref") is not None:
            GREF[0] = k["gref"]
        prev = solve_key(k, prev)


def _hermite(keys, f, name, cyclic, period):
    n = len(keys)
    fs = [k["f"] for k in keys]
    i = 0
    while i < n - 2 and f > fs[i + 1]:
        i += 1
    f0, f1 = fs[i], fs[i + 1]
    get = lambda j: keys[j]["p"][name]

    def tangent(j):
        if j == 0 or j == n - 1:
            if not cyclic:
                return 0.0
            return (get(1) - get(n - 2)) / (fs[1] + period - fs[n - 2])
        return (get(j + 1) - get(j - 1)) / (fs[j + 1] - fs[j - 1])

    m0, m1 = tangent(i), tangent(i + 1)
    h = f1 - f0
    s = (f - f0) / h
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * get(i) + (s3 - 2 * s2 + s) * h * m0 + (-2 * s3 + 3 * s2) * get(i + 1) + (s3 - s2) * h * m1


def params_at(keys, f, cyclic):
    period = keys[-1]["f"] - keys[0]["f"]
    for k in keys:
        if k["f"] == f:
            return dict(k["p"])
    return {nm: _hermite(keys, f, nm, cyclic, period) for nm in NAMES}


def apply(p):
    body(p)
    head(p)
    e = Vector((p["ex"], p["ey"], p["ez"])).normalized()
    info = place(pivot_target(p), p["tyaw"], p["telev"], p["troll"], e)
    head(p)
    left_arm(p)
    return info


def build_clip(kind, keys, cyclic, tremor=None):
    solve_keys(keys)
    L.new_clip(kind)
    last = {}
    worst = {"pen": 0.0, "low": 9.0, "swing": 0.0, "reach": 0.0, "lgap": 0.0, "legs_low": 9.0}
    for f in range(keys[0]["f"], keys[-1]["f"] + 1):
        p = params_at(keys, f, cyclic)
        if tremor:
            tremor(p, f)
        info = apply(p)
        pen, _ = penetration()
        worst["pen"] = max(worst["pen"], round(pen, 2))
        worst["low"] = min(worst["low"], round(L.launcher_lowest_y(), 2))
        worst["legs_low"] = min(worst["legs_low"], round(lowest_leg(), 3))
        for name, box, half in L.body_boxes():          # every corner of the shins (incl. the ankle end)
            if name in ("RightLowerLeg", "LeftLowerLeg"):
                for s in itertools.product((-1, 1), repeat=3):
                    c = box @ Vector((s[0] * half[0], s[1] * half[1], s[2] * half[2]))
                    worst["shin_low"] = min(worst.get("shin_low", 9.0), round(c.y, 3))
        worst["swing"] = max(worst["swing"], round(wrist_swing(), 1))
        for sd in ("Left", "Right"):
            worst["ank_" + sd] = max(worst.get("ank_" + sd, 0.0), round(abs(L.joint(sd + "Foot").y - L.ANKLE_REST[sd][1]), 3))
        worst["pole_adj"] = round(POLE_DBG["adj"], 1)
        worst["armD_min"] = min(worst.get("armD_min", 9.0), round(arm_d(), 3))
        _wa, _wl = audit_sink()
        _la, _ = audit_sink(("LeftUpperArm", "LeftLowerArm", "LeftHand"), False)
        worst["sinkR"] = max(worst.get("sinkR", 0.0), round(_wa, 2))
        worst["sinkL"] = max(worst.get("sinkL", 0.0), round(_la, 2))
        worst["sinkLauncher"] = max(worst.get("sinkLauncher", 0.0), round(_wl, 2))
        worst["armD_max"] = max(worst.get("armD_max", 0.0), round(arm_d(), 3))
        if os.environ.get("R30_TRACE") == kind:
            Mi = torso().inverted()
            t = (Mi @ (L.joint("RightHand") - L.joint("RightUpperArm"))).normalized()
            e0, e1 = LASTPOLE[0]
            fv = (Mi @ e1).normalized()
            n = t.cross(fv)
            qa = L.get_rot("RightUpperArm")
            da = math.degrees(qa.rotation_difference(TRACE.get("q", qa)).angle)
            TRACE["q"] = qa.copy()
            print("REPORTT f=%d t=%s pole=%s tf=%.1f n=%s |n|=%.3f dUA=%.1f ex=%s" % (
                f, [round(v, 2) for v in t], [round(v, 2) for v in fv], math.degrees(t.angle(fv)),
                [round(v, 2) for v in n.normalized()], n.length, min(da, 360 - da),
                [round(p[k], 2) for k in ("ex", "ey", "ez")]))
            print("REPORTU f=%d UA=%s LA=%.1f H=%s D=%.3f e0=%s kneel=%.2f drop=%.2f yaw=%.1f" % (f,
                [round(v, 3) for v in qa], math.degrees(L.get_rot("RightLowerArm").angle),
                [round(v, 3) for v in L.get_rot("RightHand")],
                (L.joint("RightHand") - L.joint("RightUpperArm")).length, [round(v, 2) for v in (Mi @ e0)],
                p["kneel"], p["drop"], p["yaw"]))
        worst["reach"] = max(worst["reach"], info["arm_overreach"])
        if p["gw"] > 0.99:
            worst["lgap"] = max(worst["lgap"], round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 3))
        for b in L.BONES:                                  # quaternion sign continuity
            q = L.get_rot(b)
            if b == "Launcher" and SIGNREF[0] is not None:
                if q.dot(SIGNREF[0]) < 0.0:          # one sign for the grip in every clip (checker vs Ready)
                    q = -q
                    L.set_rot(b, q)
            elif b in last and q.dot(last[b]) < 0.0:
                q = -q
                L.set_rot(b, q)
            last[b] = q.copy()
        L.key(f)
    if cyclic:
        L.make_cyclic(kind)
    dbg[kind + "_frames"] = worst


# ------------------------------------------------------------------ clips
def ready_params(b, w):
    """b 0..1 breathing (shoulder rise), w -1..1 weight shift.  Tube on the shoulder pointing up-forward."""
    return dict(yaw=36.0 + 3.0 * w, lean=-3.0 - 1.5 * b, roll=-2.5 * w, drop=0.28 + 0.03 * b + 0.03 * abs(w),
                side=0.08 * w, back=0.0, wyaw=16.0 - 1.5 * w, wbend=-1.0 - 2.5 * b, wroll=-2.0 + 1.5 * w,
                ox=0.65, oy=-0.4 + 0.05 * b, oz=-0.55,
                tyaw=62.0 - 2.0 * w, telev=26.0 + 3.0 * b, troll=40.0,
                lx=-14.0, ly=1.0 - 0.3 * b, lz=-2.5, look_tube=0.0, hroll=0.0, hpitch=-2.0 * b,
                kneel=0.0, gw=0.0, kw=0.0, hx=-0.25 - 0.04 * b, hy=-1.5, hz=0.05 + 0.08 * w,
                lex=-0.3, ley=-0.2, lez=1.0)


# the kneeling aim: depth 0 = ChargeLo (upright kneel), 1 = ChargeHi (sat back, hunched on the tube)
AIM = dict(yaw=26.0, wyaw=4.0, wroll=-4.0, tyaw=4.0, telev=7.0, troll=30.0, ox=0.1, oy=-0.45, oz=-0.85,
           hroll=6.0, hpitch=0.0)


def aim_params(depth, ph=0.0):
    s1 = math.sin(2.0 * math.pi * ph)
    c1 = math.cos(2.0 * math.pi * ph)
    s2 = math.sin(4.0 * math.pi * ph + 0.6)
    drift = 1.0 - 0.55 * depth
    a = AIM
    return dict(yaw=a["yaw"] + 1.5 * drift * s1, lean=-4.0 - 9.0 * depth - 1.0 * s1, roll=0.0,
                drop=1.8, side=0.0, back=0.02 + 0.16 * depth,                # Hi sits back, lower
                wyaw=a["wyaw"] + 1.0 * drift * c1, wbend=-2.0 - 8.0 * depth - 1.5 * s1,
                wroll=a["wroll"] - 3.0 * depth,
                ox=a["ox"], oy=a["oy"], oz=a["oz"],
                tyaw=a["tyaw"] + 2.2 * drift * s1, telev=a["telev"] - 1.0 * depth + 1.6 * drift * s2, troll=a["troll"],
                lx=-14.0, ly=1.5, lz=-1.5, look_tube=1.0, hroll=a["hroll"] + 3.0 * depth,
                hpitch=a["hpitch"] - 8.0 * depth,
                kneel=1.0, gw=1.0, kw=0.0, hx=-0.2, hy=-1.55, hz=0.1, lex=-0.6, ley=-0.2, lez=1.0)


if PROBE == "prof":
    ax = np.array([0.0, 0.0, -0.88 * L.LAUNCHER_SCALE])
    V = VERTS - ax
    r = np.hypot(V[:, 0], V[:, 2])
    ys = np.round(V[:, 1], 1)
    for y in sorted(set(ys.tolist())):
        m = ys == y
        print("REPORTR y=%.1f n=%d rmin=%.2f rmax=%.2f" % (y, int(m.sum()), float(r[m].min()), float(r[m].max())))
    raise SystemExit
# the front (left) foot sits right under the left knee in the ChargeLo kneel (vertical shin)
for _ in range(4):
    _p = dict(BODY_DEF)
    _p.update(aim_params(0.0))
    body(_p)
    hp = L.joint("LeftUpperLeg")
    kn_y = -2.9304 + L.SHIN
    h = math.sqrt(max(0.0, L.THIGH ** 2 - (hp.y - kn_y) ** 2))
    FEET["Left"] = (round(hp.x + TOE.x * h, 3), round(hp.z + TOE.z * h, 3))
body(_p)
dbg["feet"] = {"feet": FEET, "kneeL": [round(v, 2) for v in L.joint("LeftLowerLeg")],
               "kneeR": [round(v, 2) for v in L.joint("RightLowerLeg")], "drop": _p["_drop"],
               "low": round(lowest_leg(), 3), "who": LOW_WHO[0]}

if PROBE:
    res = []
    for yaw, troll, oz in itertools.product((26, 33, 40), (30.0, 45.0), (-0.3, 0.0)):
        p = dict(BODY_DEF)
        p.update(aim_params(0.0, 0.0))
        p.update(yaw=yaw, wyaw=4.0, oz=oz, ox=0.35, oy=-0.2, lean=-4.0, wroll=-4.0, hroll=6.0, troll=troll)
        k = {"f": 0, "p": p, "name": "probe", "search": True, "radius": 0.3, "rolls": (-10.0, 0.0, 10.0)}
        solve_key(k)
        d = dbg["probe"]
        res.append((d["cost"], yaw, troll, oz, p["troll"], round(p["hroll"], 1), d["off"], d["pen"], d["worst"],
                    {kk: vv[:2] for kk, vv in d["parts"].items()}, d["lgap"], d["rest_d"], d["rest_s"], d["swing"],
                    d["gturn"], d["kneeR"]))
    res.sort(key=lambda r: r[0])
    for r in res:
        print("REPORTP " + json.dumps(r))
    print("REPORTK feet " + json.dumps(dbg["feet"], default=str))
    raise SystemExit


def make_tremor(depth):
    def tr(p, f):
        if depth <= 0.0:
            return
        a = depth
        w = 2.0 * math.pi * f / 36.0
        p["tyaw"] += a * 1.6 * math.sin(4.0 * w + 0.4)
        p["telev"] += a * 1.5 * math.sin(6.0 * w + 1.3)
        p["wroll"] += a * 2.2 * math.sin(4.0 * w + 2.0)
        p["wbend"] += a * 2.0 * math.sin(6.0 * w)
        p["lean"] += a * 1.0 * math.sin(6.0 * w + 2.9)
        p["hroll"] += a * 2.2 * math.sin(6.0 * w + 2.4)
        p["hpitch"] += a * 2.0 * math.sin(4.0 * w + 0.9)
        p["oz"] += a * 0.05 * math.sin(6.0 * w + 0.7)
    return tr


SOLVED = {}
TRACE = {}
GRIPS = {}


def charge_clip(kind, depth):
    ks = [K(6 * i, (kind + "_%d" % i) if i in (0, 3) else None, radius=0.15, **aim_params(depth, i / 6.0))
          for i in range(7)]
    if kind == "ChargeLo":
        ks[0]["inherit_from"] = PRE["p"]
        ks[0]["rolls"] = (-10.0, 0.0, 10.0)
    else:
        ks[0]["inherit_from"] = SOLVED["ChargeLo"]
        ks[0]["gref"] = (GRIPS["ChargeLo"], 6.0, 4.0)
    for _k in ks[1:-1]:
        _k["inherit_from"] = ks[0]["p"]
    ks[-1]["same_as"] = 0
    build_clip(kind, ks, True, tremor=make_tremor(depth))
    SOLVED[kind] = dict(ks[0]["p"])
    apply(dict(ks[0]["p"]))
    GRIPS[kind] = L.get_rot("Launcher")
    GREF[0] = None


# the kneeling aim is the pose that matters most: solve it first with a free grip, then every pose
# holds the launcher with exactly that grip (no sliding in the fist; the arm + wrist do the work)
PRE = K(0, "lo_pre", radius=0.3, rolls=(-15.0, 0.0, 15.0), **aim_params(0.0, 0.0))
solve_key(PRE)
GFIX[0] = L.get_rot("Launcher")
charge_clip("ChargeLo", 0.0)
SIGNREF[0] = GRIPS["ChargeLo"]

ready_keys = [K(0, "ready0", radius=0.3, rolls=(-25.0, 0.0, 25.0), **ready_params(0.0, 0.0)),
              K(18, "ready1", radius=0.15, **ready_params(1.0, 0.6)),
              K(36, radius=0.15, **ready_params(0.2, 1.0)), K(54, radius=0.15, **ready_params(1.0, -0.6)),
              K(72, **ready_params(0.0, 0.0))]
ready_keys[0]["gref"] = (GRIPS["ChargeLo"], 15.0, 3.0)
for _k in ready_keys[1:-1]:
    _k["inherit_from"] = ready_keys[0]["p"]
ready_keys[-1]["same_as"] = 0
build_clip("Ready", ready_keys, True)
GREF[0] = None
READY0 = dict(ready_keys[0]["p"])
apply(dict(READY0))
READY_GRIP = L.get_rot("Launcher")

charge_clip("ChargeHi", 1.0)

HI0 = dict(SOLVED["ChargeHi"])
LO0 = dict(SOLVED["ChargeLo"])
_d = math.degrees(GRIPS["ChargeLo"].rotation_difference(GRIPS["ChargeHi"]).angle)
dbg["lo_hi_grip_deg"] = round(min(_d, 360.0 - _d), 1)
_d = math.degrees(GRIPS["ChargeLo"].rotation_difference(READY_GRIP).angle)
dbg["lo_ready_grip_deg"] = round(min(_d, 360.0 - _d), 1)


def fire_p(**kw):
    p = dict(HI0)
    p.update(kw)
    return p


FT = -2.5          # tube yaw at the shot: a touch across the pad-camera ray so the mouth shows
fire_keys = [
    K(0, "fire0", search=False, **HI0),                                                              # 0.00 ChargeHi
    # 0.10 BRACE: tuck in behind the tube, squeeze
    K(3, "brace", radius=0.15, **fire_p(lean=HI0["lean"] - 3.0, wbend=HI0["wbend"] - 2.0, back=HI0["back"] + 0.04,
                                        tyaw=FT, telev=7.0, hpitch=HI0["hpitch"] - 2.0, oz=HI0["oz"] - 0.06)),
    # 0.167 WHOOSH (FireAt): dead on the line
    K(FIRE_FRAME, "fire", radius=0.15, **fire_p(lean=HI0["lean"] - 2.5, wbend=HI0["wbend"] - 2.0, back=HI0["back"] + 0.04,
                                                tyaw=FT, telev=8.0, hpitch=HI0["hpitch"] - 2.0, oz=HI0["oz"] - 0.08)),
    # 0.23 KICK: tube slams back along the shoulder, muzzle jumps, pelvis rocks back over the heel
    K(7, "kick", radius=0.15, **fire_p(lean=HI0["lean"] + 6.5, back=HI0["back"] + 0.10, side=HI0["side"],
                                       wbend=HI0["wbend"] + 4.0, wroll=HI0["wroll"] + 3.0, wyaw=HI0["wyaw"] + 1.0,
                                       tyaw=FT + 1.0, telev=20.0, oz=HI0["oz"] + 0.17, oy=HI0["oy"] + 0.06,
                                       hpitch=HI0["hpitch"] + 10.0, look_tube=0.6, ly=3.0)),
    # 0.37 recoil settles, still on the grip, watching it fly
    K(11, "settle", radius=0.15, **fire_p(lean=-9.0, back=HI0["back"] + 0.04, side=HI0["side"], wbend=-5.0,
                                          tyaw=FT + 1.5, telev=13.0, oz=HI0["oz"] + 0.05, look_tube=0.5,
                                          lx=-16.0, ly=1.5, lz=-1.0, hpitch=HI0["hpitch"] + 4.0)),
    # 0.60 gather: let go of the front grip, hand onto the left knee, tube dips a touch
    K(19, "gather", radius=0.15, **fire_p(lean=-15.0, back=0.12, side=0.0, wbend=-6.0, tyaw=8.0, telev=9.0,
                                          look_tube=0.0, lx=-16.0, ly=1.0, lz=-1.5, hpitch=0.0, hroll=6.0,
                                          gw=0.0, kw=1.0, lex=-0.6, ley=-0.2, lez=1.0)),
    # 0.93 rising: push off the knee, the tube swings up onto the carry
    K(33, "rise", **fire_p(yaw=38.0, drop=0.55, kneel=0.4, lean=-9.0, back=0.04, side=0.0, wyaw=14.0, wbend=-3.0,
                           wroll=-3.0, tyaw=36.0, telev=22.0, ox=READY0["ox"], oy=READY0["oy"], oz=READY0["oz"],
                           troll=READY0["troll"], look_tube=0.0, lx=-14.0, ly=1.0, lz=-2.0, hpitch=0.0, hroll=2.0,
                           gw=0.0, kw=0.6, hx=-0.25, hy=-1.5, hz=0.05)),
    K(45, "stand", radius=0.15, **ready_params(0.6, 0.0)),                             # 1.27 standing
    K(51, search=False, **READY0),                                                     # 1.50 = Ready
]
fire_keys[1]["gref"] = (GRIPS["ChargeHi"], 8.0, 3.0)
fire_keys[5]["gref"] = (READY_GRIP, 30.0, 2.0)
fire_keys[7]["inherit_from"] = READY0
fire_keys[7]["gref"] = (READY_GRIP, 10.0, 2.0)
build_clip("Fire", fire_keys, False)

for k, v in dbg.items():
    print("REPORTK %s %s" % (k, json.dumps(v, default=str)))
L.finish(SPEC, OUT, extra_times=[0.1, 0.2333, 0.3667, 0.6333, 1.1])
if os.environ.get("R30_DBG"):
    DBG_DIR = os.environ["R30_DBG"]
    L.VIEWS["side"] = ((4.2, -1.9, -7.9), (-0.4, -2.3, -0.4), 30.0, None)      # the legs from the right-front, low
    L.VIEWS["back"] = ((3.0, 4.0, 9.0), (-0.6, 1.2, -0.6), 30.0, None)        # over the shoulders from behind
    L.VIEWS["left"] = ((-6.0, 2.5, 9.0), (-0.3, 0.8, -0.8), 30.0, None)       # head / left hand / front grip
    for v in ("side", "back", "left"):
        L.render_sheet(SPEC, os.path.join(DBG_DIR, "dbg_%s.png" % v), view=v, per_clip=4,
                       extra_times=[0.2333, 0.6, 0.9333])
