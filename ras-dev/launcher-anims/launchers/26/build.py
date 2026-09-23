"""26 Meteor Launcher -- a black spiked cannon with gold fins, thrown like a SHOT PUT.

The player stands side-on on the pad (down-track = their LEFT, away from the camera; the camera
sees their right side / back).  The cannon lives on the RIGHT shoulder / above the head, where the
pad camera sees it, and the ball blasts out of the muzzle high INTO the screen.
  Ready    the cannon carried on the right shoulder (muzzle forward and up), right fist on the
           pistol grip, the left arm easy at the side; slow heavy breathing + weight shift.
  ChargeLo the GATHER: squat, the cannon hoisted up against the neck over the right shoulder,
           muzzle aimed up and toward the track like a shot put; the weight rocks back over the
           right (back) leg and forward again, the cannon riding with the shoulder; the free left arm
           reaches out toward the track (the shot-putter's balance arm), swaying with the rock.
  ChargeHi the same rock COILED: deeper squat, torso wound further away from the track, bigger
           rock, straining tremor.
  Fire     COIL (0.10: drop 0.9, cannon cocked back behind the shoulder, balance arm reaching) ->
           DRIVE (0.17: hips whip round, the hand still low at the neck, elbow ~105, cannon cocked,
           balance arm swept wide) -> PUNCH (0.20-0.23: the elbow opens 105 -> 83 -> 58) -> HEAVE
           (0.27: tall over the left leg, the right arm punched up and out, 17 deg short of straight,
           hand 0.5 above the shoulder, wrist straight -- the grip is DERIVED from this pose; the
           meteor leaves the muzzle at elev 36; balance arm blocked in) -> KICK (0.30: muzzle +19 deg,
           hand driven back along the arm, chest knocked back) -> RECOIL (0.37) -> FOLLOW-THROUGH (0.50: the cannon's weight drags the arm down, the torso rolls
           over the LEFT leg) -> HANG (0.63: cannon by the front of the right hip, elbow bent) ->
           GATHER (0.77: knee dip, the left hand grabs under the barrel) -> HOIST (0.87: knees
           drive up, both arms swing it up past the shoulder) -> LOWER (0.97) -> free arm released.
           Feet stay planted: body() sinks the hips wherever a leg would over-extend.
The cannon is ONE-handed like a shot (TwoHanded False): the left arm is the balance arm, except
during the two-handed hoist back onto the shoulder (LSUP = support point under the barrel).
Ball: hidden until it blasts out of the muzzle; fire burst, fire flicker while charging.
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
from mathutils import Vector, Quaternion

LID = 26
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_FRAME = 8
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.5,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Never", "start": "Muzzle", "grow": 1.0},
    "Fx": {"Style": "fire", "Color": [255, 120, 40], "Charge": "fire", "ChargeColor": [255, 170, 60]},
    "TwoHanded": False,
    "AllowFootLift": False,
    "Notes": "meteor cannon as a shot put: shoulder carry, squat + rock with the cannon hoisted at the neck and the free arm reaching to the track, explode up and heave the meteor out of the muzzle in a high arc",
}
FEET = {"Left": (-1.0, -0.2), "Right": (0.9, 0.4)}
LOOK_TRACK = (-14.0, 2.0, -2.0)
META = L.load_meta(LID)
G2 = META["Grip2"]["pos"]
BARREL_LOW = [(0.0, 0.6 - 0.45 * i, -0.3) for i in range(0, 7)]
BARREL_AXIS = [(0.0, 0.6 - 0.45 * i, -0.85) for i in range(0, 7)]
HAND_PARTS = ("RightHand", "LeftHand")
ARM_PARTS = ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand")
ELBOWS = [Vector(v).normalized() for v in (
    (1.0, -0.4, 0.3), (1.0, -1.0, 0.0), (1.0, 0.0, 0.6), (0.6, -1.0, 0.6), (1.0, -0.4, -0.5),
    (1.0, 0.4, 0.2), (0.5, -0.5, 1.0), (1.0, 0.8, -0.2), (0.0, 1.0, 0.0), (-0.3, 1.0, 0.3))]
L_ELBOW = (-0.3, -1.0, 0.2)
GRIP = None
dbg = {}
_last = {}
PREV = {"off": Vector((0.0, 0.0, 0.0)), "roll": 0.0, "cost": 0.0}
ROLL_W = [0.4]                        # weight of launcher-roll continuity between keys


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
    PREV["off"] = Vector((0.0, 0.0, 0.0))
    L.new_clip(kind)


SHAKE = []
for i in range(24):
    sg = 1.0 if i % 2 == 0 else -1.0
    SHAKE.append((sg * (0.6 + 0.4 * abs(math.sin(i * 2.7 + 0.3))), math.sin(i * 4.1 + 1.9),
                  -sg * (0.5 + 0.5 * abs(math.sin(i * 5.3 + 0.7))), math.sin(i * 3.3 + 2.4)))
ZERO = (0.0, 0.0, 0.0, 0.0)


LEGFIX = {}


def body(yaw, lean, drop, back, side=0.0, roll=0.0, waist_yaw=0.0, waist_bend=0.0, waist_roll=0.0):
    """stance + waist; if a leg cannot reach its planted ankle the hips sink a little more
    (so the feet NEVER leave the floor)."""
    L.reset_pose()
    d0 = drop
    for _ in range(40):
        err = L.stance(hip_drop=drop, hip_back=back, hip_side=side,
                       root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=FEET)
        if max(err.values()) <= 0.0:
            break
        drop += 0.015
    if drop > d0 + 1e-6:
        drop += 0.04                                        # margin for the in-between frames
        L.stance(hip_drop=drop, hip_back=back, hip_side=side,
                 root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=FEET)
        LEGFIX[len(LEGFIX)] = (round(d0, 3), round(drop, 3), round(yaw, 1), round(side, 2))
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def wrist_swing():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


def do_left(left):
    """left = "grip2" (hand on the barrel), a launcher-local point, or ("free", world wrist, elbow)"""
    if left is None:
        return None
    if isinstance(left, tuple) and left and left[0] == "free":
        L.arm_to("Left", Vector(left[1]), left[2] if len(left) > 2 else L_ELBOW)
        return None
    if isinstance(left, tuple) and left and left[0] == "sfree":
        w = L.joint("LeftUpperArm") + L.frame_of("UpperTorso") @ Vector(left[1])
        L.arm_to("Left", w, L.frame_of("UpperTorso") @ Vector(left[2]))
        return None
    tgt = L.launcher_point(G2) if left == "grip2" else L.launcher_point(left)
    L.left_hand_to(point=tgt, elbow_away=L_ELBOW)
    return (L.hand_cf("Left").translation - tgt).length


_LV = []
DEEP = [None]
AUDIT_BODIES = ("UpperTorso", "Head", "LowerTorso")


def pen(n_verts=70):
    """audit-style penetration (realistic avatar boxes): (launcher depth in torso/head, worst arm
    part depth in torso/head, where)"""
    lob = L.launcher_object()
    if not _LV:
        vs = [v.co.copy() for v in lob.data.vertices]
        _LV.extend(vs[::max(1, len(vs) // 120)])
    L.update()
    boxes = {}
    for n, b, h in L.body_boxes():
        half = Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h
        boxes[n] = (b, b.inverted(), half)

    def depth(p, body):
        _, bi, half = boxes[body]
        q = bi @ p
        dx, dy, dz = half.x - abs(q.x), half.y - abs(q.y), half.z - abs(q.z)
        return min(dx, dy, dz) if (dx > 0 and dy > 0 and dz > 0) else 0.0

    mw = lob.matrix_world
    wl, wl_at = 0.0, ""
    step = max(1, len(_LV) // n_verts)
    for co in _LV[::step]:
        p = L.b2r(mw @ co)
        for body in ("UpperTorso", "Head"):
            d = depth(p, body)
            if d > wl:
                wl, wl_at = d, "L>" + body
                DEEP[0] = [round(v, 2) for v in (L.pivot_cf().inverted() @ p) / L.LAUNCHER_SCALE] \
                    + [round(v, 2) for v in p]
    wa, wa_at = 0.0, ""
    for arm in L.AUDIT_ARMS:
        ab, _, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    p = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for body in AUDIT_BODIES:
                        d = depth(p, body)
                        if d > wa:
                            wa, wa_at = d, arm + ">" + body
    return wl, wa, wl_at + " " + wa_at


def cost_now(offset, left, reach, reach_max=1.52):
    sw = wrist_swing()
    c = sw + 3.0 * max(0.0, sw - 80.0) + 60.0 * offset + 1500.0 * reach
    el = L.joint("RightLowerArm")
    ce, _ = L.clearance(el, skip=ARM_PARTS)
    c += 150.0 * max(0.0, 0.12 - ce)
    for p in BARREL_LOW:
        cs, _ = L.clearance(L.launcher_point(p), skip=HAND_PARTS + ("RightLowerArm",))
        c += 120.0 * max(0.0, 0.05 - cs)
    for p in BARREL_AXIS:
        cs, _ = L.clearance(L.launcher_point(p), skip=HAND_PARTS + ("RightLowerArm",))
        c += 120.0 * max(0.0, 0.5 - cs)
    g = do_left(left)
    if g is not None:
        c += 150.0 * g
    wl, wa, _ = pen(120)
    c += 700.0 * max(0.0, wl - 0.04) + 500.0 * max(0.0, wa - 0.08) \
        + 2000.0 * max(0.0, wl - 0.1) + 2000.0 * max(0.0, wa - 0.14)
    # keep the right arm inside full reach (no straight/bent elbow popping)
    sh = (L.joint("RightHand") - L.joint("RightUpperArm")).length
    c += 200.0 * max(0.0, sh - reach_max)
    c += 2.0 * max(0.0, math.degrees(L.get_rot("RightHand").angle) - 65.0)   # total hand turn (report: <= 70)
    return c


def solve(P, yaw, elev, roll=0.0, left="grip2", radius=0.15, step=0.15, name=None, look=LOOK_TRACK,
          rolls=None, elbows=None, reach_max=1.52, want=None):
    """rolls = candidate launcher rolls (degrees) to search; the one nearest `roll` is preferred"""
    fwd = L.direction(yaw, elev)
    n = int(round(radius / step))
    best = None
    if look is not None:
        L.head_look(target=look)                    # the head first: the search avoids it as posed
    for rl in (rolls if rolls else (roll,)):
        up = L.up_for(fwd, rl)
        for i in range(-n, n + 1):
            for j in range(-n, n + 1):
                for k in range(-n, n + 1):
                    off = Vector((i * step, j * step, k * step))
                    if off.length > radius + 1e-6:
                        continue
                    for e in (elbows if elbows else ELBOWS):
                        info = L.place_launcher(at=Vector(P) + off, forward=fwd, up=up, anchor="Pivot",
                                                elbow_away=e, grip_twist=GRIP)
                        c = cost_now(off.length, left, info["arm_overreach"], reach_max) + (want() if want else 0.0) + 90.0 * (off - PREV["off"]).length \
                            + 0.15 * abs(rl - roll) + ROLL_W[0] * abs(rl - PREV["roll"])
                        if best is None or c < best[0]:
                            best = (c, Vector(P) + off, e, rl)
    c, Pq, e, roll = best
    PREV["roll"] = roll
    PREV["cost"] = c
    up = L.up_for(fwd, roll)
    PREV["off"] = Pq - Vector(P)
    info = L.place_launcher(at=Pq, forward=fwd, up=up, anchor="Pivot", elbow_away=e, grip_twist=GRIP)
    g = do_left(left)
    if look is not None:
        L.head_look(target=look)
    if name:
        DEEP[0] = None
        wl, wa, at = pen(120)
        dbg[name] = {"pen": [round(wl, 2), round(wa, 2), at], "deep": DEEP[0],"cost": round(c, 1), "P": [round(v, 2) for v in Pq], "elbow": [round(v, 2) for v in e],
                     "swing": round(wrist_swing(), 1), "gap": None if g is None else round(g, 3),
                     "reach": info["arm_overreach"], "low": round(L.launcher_lowest_y(), 2),
                     "sh_to_wrist": round((L.hand_cf("Right").translation - L.joint("RightUpperArm")).length, 2),
                     "elbow_deg": round(math.degrees(L.get_rot("RightLowerArm").angle), 1), "roll": roll,
                     "shoulder": [round(v, 2) for v in L.joint("RightUpperArm")],
                     "fa_ang": round(math.degrees((L.joint("RightHand") - L.joint("RightLowerArm")).angle(fwd)), 1),
                     "ua_dir": [round(v, 2) for v in (L.joint("RightLowerArm") - L.joint("RightUpperArm")).normalized()],
                     "fa_dir": [round(v, 2) for v in (L.joint("RightHand") - L.joint("RightLowerArm")).normalized()],
                     "muzzle": [round(v, 2) for v in L.launcher_point(META["Muzzle"]["pos"])],
                     "g2": [round(v, 2) for v in L.launcher_point(G2)],
                     "lsh": [round(v, 2) for v in L.joint("LeftUpperArm")],
                     "hand_rot": round(math.degrees(L.get_rot("RightHand").angle), 1),
                     "hand_dy": round(L.hand_cf("Right").translation.y - L.joint("RightUpperArm").y, 2)}
    return e


# ------------------------------------------------------------------ poses
# the LEFT arm is the shot-putter's balance arm: relaxed at the side while carrying, reaching out
# toward the track while gathering, sweeping down and back at the heave.  Offsets are from the
# left shoulder in the UpperTorso frame (x right, y up, z back).
def arm_free(off, elbow=(0.0, -1.0, 0.4)):
    return ("sfree", off, elbow)


ROUT = tuple(range(-30, 151, 15))
READY_FIX = {"rolls": ROUT, "elbows": None}
RCH = (60, 75, 90, 105, 120)        # rolls tried (near the heave roll 95) for the charge (one is chosen for all keys)
CH_FIX = {"rolls": RCH, "elbows": None}


def ready(b, w=0.0, name=None, h=0.0):
    """b 0..1 breathing, w -1..1 weight shift, h 0..1 = hitching the heavy cannon up on the
    shoulder.  Cannon resting on the right shoulder."""
    body(yaw=2.0 + 2.0 * w, lean=-3.0 - 1.0 * b + 1.5 * h, drop=0.16 + 0.03 * b - 0.03 * h, back=0.06, side=0.05 * w,
         roll=-1.5 * w, waist_yaw=9.0, waist_bend=-2.0 - 2.0 * b + 2.0 * h, waist_roll=-2.0 + 1.5 * w - 2.0 * h)
    return solve((1.12 + 0.02 * w, 0.25 + 0.08 * b + 0.12 * h, -1.0), 82.0 - 2.0 * w, 24.0 + 3.0 * b - 3.0 * h,
          left=arm_free((-0.28 - 0.04 * b, -1.5, -0.12 + 0.06 * w), (0.0, -0.3, 1.0)),
          name=name, look=(-12.0, 1.0 - 0.3 * b, -5.0), rolls=READY_FIX["rolls"], elbows=READY_FIX["elbows"], radius=0.3)


def charge(depth, phase, s=ZERO, name=None):
    """depth 0..1 = Lo..Hi, phase 0..1 through the rock, s = tremor sample.
    rock +1 = the weight back over the right (back) leg, coiled away from the track."""
    rock = math.sin(2.0 * math.pi * phase)
    lag = math.sin(2.0 * math.pi * phase - 0.7)            # the cannon rides a little behind the hips
    a = 1.0 + 1.2 * depth                                  # rock amplitude (Hi 2.2)
    t = 0.25 + 1.0 * depth                                 # tremor amplitude
    drop = 0.42 + 0.5 * depth + 0.08 * a * rock
    body(yaw=-6.0 - 10.0 * depth - 4.5 * a * rock + 0.8 * t * s[3],
         lean=-6.0 - 4.0 * depth + 3.0 * a * rock + 0.8 * t * s[1],
         drop=drop, back=0.1 + 0.1 * depth,
         side=0.1 + 0.08 * depth + 0.12 * a * rock, roll=4.0 * a * rock,
         waist_yaw=8.0 - 4.0 * depth - 5.0 * a * lag + 1.2 * t * s[0],
         waist_bend=-3.0 - 2.0 * depth + 3.0 * a * lag + 1.2 * t * s[2],
         waist_roll=4.0 + 3.0 * a * lag + 1.5 * t * s[0])
    P = (0.85 + 0.08 * depth + 0.08 * a * lag + 0.04 * t * s[0], 1.0 - drop + 0.1 * a * lag + 0.04 * t * s[1],
         -1.66 - 0.06 * depth + 0.06 * a * lag + 0.04 * t * s[2])
    elev = min(55.0, 42.0 + 2.0 * depth - 4.0 * a * lag + 2.0 * t * s[1])
    kw = dict(rolls=CH_FIX["rolls"], elbows=CH_FIX["elbows"], want=lambda: 4.0 * max(0.0, 22.0 - elbow_theta()))
    e = solve(P, 76.0 + 4.0 * depth + 10.0 * a * lag + 3.0 * t * s[3], elev,
              left=arm_free((-0.95 + 0.1 * a * rock, -0.45 - 0.1 * depth + 0.16 * a * lag, -0.5 - 0.14 * a * rock),
                            (0.3, 1.0, 0.2)),
              name=name, look=(-9.0, 3.0 - 1.0 * depth + 0.3 * t * s[1], -7.0 - 1.0 * a * rock), **kw)
    return e, PREV["roll"]


RS = list(range(-90, 91, 15))
FREE_DOWN = arm_free((-0.55, -1.3, 0.55), (0.0, -0.4, 1.0))       # balance arm pulled down and back
LSUP = (0.0, -0.2, -0.2)                                          # support hand under the barrel
TUCK = arm_free((-0.1, -0.95, -0.55), (-1.0, -0.6, 0.2))             # balance arm pulled hard to the chest


def fire_pose(bd, P, yaw_l, elev, left, name=None, look=None, rolls=None, roll=0.0, **kw):
    """bd = body() keyword dict (explicit per key), then the cannon + arms"""
    body(**bd)
    solve(P, yaw_l, elev, roll=roll, left=left, name=name, look=look if look is not None else LOOK_TRACK,
          rolls=rolls, **kw)


def lerp_key(a, b, t):
    """in-between of two fire_pose argument dicts (numbers, tuples, nested tuples, dicts)"""
    def mix(x, y):
        if isinstance(x, dict):
            return {k: mix(x[k], y[k]) for k in x}
        if isinstance(x, (tuple, list)):
            if x and isinstance(x[0], str):
                return (x[0],) + tuple(mix(p, q) for p, q in zip(x[1:], y[1:]))
            return tuple(mix(p, q) for p, q in zip(x, y))
        if isinstance(x, (int, float)) and isinstance(y, (int, float)):
            return x + (y - x) * t
        return x
    out = {k: mix(a[k], b.get(k, a[k])) for k in a if k not in ("name", "rolls", "want")}
    out["rolls"] = a.get("rolls")
    return out


def B(yaw, lean, drop, back, side, roll, wy, wb, wr):
    return dict(yaw=yaw, lean=lean, drop=drop, back=back, side=side, roll=roll,
                waist_yaw=wy, waist_bend=wb, waist_roll=wr)


# ------------------------------------------------------------------ grip: probed in the gather
# The grip is derived from the HEAVE (the key beat): the right arm punched up and out ~18 deg short
# of straight, the wrist STRAIGHT (hand rotation 0), the cannon on the shot line (yaw 5, elev 38).
# Every other pose then solves the wrist against this one constant grip.
HEAVE_BD = dict(yaw=15.0, lean=2.0, drop=0.15, back=0.1, side=-0.05, roll=2.0,
                waist_yaw=38.0, waist_bend=3.0, waist_roll=0.0)      # drop 0.15 = legs straight in this stance
HEAVE_AIM = (5.0, 36.0)
HEAVE_ARM = (30.0, 14.5, 17.0)          # arm direction yaw / elev from the shoulder, elbow bend
HEAVE_POLE = Vector((0.0, 1.0, 0.1)).normalized()
PIVOT_A = L.look_frame((0.0, -1.0, 0.0), (0.0, 0.0, -1.0))


def heave_arm():
    """poses the heave body + the punched right arm (hand straight); returns the shoulder"""
    body(**HEAVE_BD)
    sh = L.joint("RightUpperArm").copy()
    d = L.direction(HEAVE_ARM[0], HEAVE_ARM[1])
    lo, hi = 0.8, 2.0
    for _ in range(30):
        m = 0.5 * (lo + hi)
        L.arm_to("Right", sh + d * m, HEAVE_POLE)
        if math.degrees(L.get_rot("RightLowerArm").angle) > HEAVE_ARM[2]:
            lo = m
        else:
            hi = m
    L.set_rot("RightHand", Quaternion())
    L.set_rot("Launcher", Quaternion())
    L.update()
    return sh


def grip_for(roll):
    heave_arm()
    R0 = L.pivot_cf().to_3x3()
    fwd = L.direction(*HEAVE_AIM)
    Wp = L.look_frame(fwd, L.up_for(fwd, roll)) @ PIVOT_A.inverted()
    return (R0.inverted() @ Wp).to_quaternion()


grips = sorted(((math.degrees(grip_for(r).angle), r) for r in range(-90, 91, 15)))
dbg["grip_angles"] = [(round(a, 1), r) for a, r in grips]
HEAVE_ROLL = 105                       # barrel beside the grip, toward the front: low enough to stay in view
GRIP = grip_for(HEAVE_ROLL)
L.set_rot("Launcher", GRIP)
L.update()
HEAVE_SH = heave_arm()
L.set_rot("Launcher", GRIP)
L.update()
HEAVE_P = tuple(L.pivot_cf().translation)
dbg["heave_grip"] = {"roll": HEAVE_ROLL, "P": [round(v, 3) for v in HEAVE_P],
                     "shoulder": [round(v, 2) for v in HEAVE_SH],
                     "hand_above_sh": round(L.hand_cf("Right").translation.y - HEAVE_SH.y, 2),
                     "muzzle": [round(v, 2) for v in L.launcher_point(META["Muzzle"]["pos"])]}

# ------------------------------------------------------------------ clips
def elbow_theta():
    return math.degrees(L.get_rot("RightLowerArm").angle)


# Ready: search the roll + elbow pole ONCE, then every key uses the same pair (no twisting)
clip("Ready")
e0 = ready(0.0, 0.0, "ready0")
READY_FIX["rolls"], READY_FIX["elbows"] = (PREV["roll"],), [e0]
READY_ROLL = PREV["roll"]
ready(0.0, 0.0, "ready0"); kf(0)
ready(1.0, 0.6, "ready1"); kf(20)
ready(0.3, 1.0, h=1.0); kf(36)                                                             # hitch the load up
ready(0.9, -0.5); kf(54)
PREV["off"] = Vector((0.0, 0.0, 0.0))
ready(0.0, 0.0); kf(72)
L.make_cyclic("Ready")

# Charge: one roll + one elbow pole for all 12 keys of BOTH ChargeLo and ChargeHi (solved at the
# middle of the blend, phase 0) -> the cannon never twists about its barrel, Lo/Hi blend cleanly
FIX_SAMPLES = ((0.0, 0.0), (0.0, 0.5), (1.0, 0.0), (1.0, 0.25), (1.0, 0.5), (1.0, 0.67), (1.0, 0.83), (1.0, 0.92))
fix_rank = []
for r in RCH:
    for e in ELBOWS:
        CH_FIX["rolls"], CH_FIX["elbows"] = (r,), [e]
        tot, worst = 0.0, 0.0
        for dep, ph in FIX_SAMPLES:
            PREV["off"] = Vector((0.0, 0.0, 0.0))
            PREV["roll"] = r
            charge(dep, ph, ZERO)
            tot += PREV["cost"]
            worst = max(worst, PREV["cost"])
        fix_rank.append((tot + 2.0 * worst, r, e))
fix_rank.sort(key=lambda x: x[0])
dbg["charge_fix_rank"] = [(round(c, 1), r, [round(v, 2) for v in e]) for c, r, e in fix_rank[:6]]
r_ch, e_ch = fix_rank[0][1], fix_rank[0][2]
CH_FIX["rolls"], CH_FIX["elbows"] = (r_ch,), [e_ch]
PREV["off"] = Vector((0.0, 0.0, 0.0))
charge(0.5, 0.0, ZERO, "charge_fix")
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    clip(kind)
    for i in range(12):
        charge(depth, i / 12.0, SHAKE[i], kind + "_%d" % i if i in (0, 3, 6, 9) else None); kf(3 * i)
    PREV["off"] = Vector((0.0, 0.0, 0.0))
    charge(depth, 0.0, SHAKE[0]); kf(36)
    L.make_cyclic(kind)

clip("Fire")
ROLL_W[0] = 1.5                                    # the cannon must not spin about its barrel mid-throw
charge(1.0, 0.0, ZERO); kf(0)                                                              # 0.00 ChargeHi
RW = tuple(range(-30, 151, 15))       # launcher rolls searched in the shot (continuity-weighted)
TUCK = arm_free((-0.05, -0.9, -0.6), (0.3, 1.0, 0.2))             # balance arm blocked in to the chest
REACH = arm_free((-0.95, -0.55, -0.5), (0.3, 1.0, 0.2))          # balance arm out toward the track
SWEEP = arm_free((-1.2, -0.35, -0.05), (0.3, 1.0, 0.2))          # ... swept wide as the hips open
hd = L.direction(HEAVE_ARM[0], HEAVE_ARM[1])


def want_bend(deg, k=1.0):
    return lambda: k * abs(elbow_theta() - deg)


K = {
    # 0.10 COIL: sink deeper than ChargeHi, wind away from the track, the cannon cocked back behind
    #      the shoulder, the balance arm reaching out toward the track
    "coil": dict(bd=B(-26.0, -12.0, 0.9, 0.2, 0.22, 5.0, -16.0, -9.0, 6.0), P=(1.2, -0.1, -1.0),
                 yaw_l=90.0, elev=46.0, left=REACH, roll=r_ch, rolls=(r_ch, r_ch + 15), look=(-10.0, 2.0, -6.0)),
    # 0.20 DRIVE: legs explode, hips whip round; the cannon still cocked at the neck, the hand low
    #      by the right shoulder, the elbow folded ~100 deg under it; the balance arm swept wide
    "drive": dict(bd=B(14.0, -4.0, 0.34, 0.08, -0.02, 1.0, 12.0, -1.0, 2.0), P=(0.5, 0.45, -1.45),
                  yaw_l=45.0, elev=46.0, left=SWEEP, roll=HEAVE_ROLL, rolls=(HEAVE_ROLL - 20, HEAVE_ROLL - 5), want=want_bend(100.0, 4.0), elbows=[HEAVE_POLE, Vector((-0.28, 0.92, 0.28))]),
    # 0.27 HEAVE: tall over the LEFT leg, the arm PUNCHED up and out (~18 deg short of straight, the
    #      hand well above the shoulder, the wrist straight) -> the meteor blasts out on the shot line;
    #      the balance arm blocked in to the chest
    "heave": dict(bd=B(**{"yaw": HEAVE_BD["yaw"], "lean": HEAVE_BD["lean"], "drop": HEAVE_BD["drop"],
                          "back": HEAVE_BD["back"], "side": HEAVE_BD["side"], "roll": HEAVE_BD["roll"],
                          "wy": HEAVE_BD["waist_yaw"], "wb": HEAVE_BD["waist_bend"], "wr": HEAVE_BD["waist_roll"]}),
                  P=HEAVE_P, yaw_l=HEAVE_AIM[0], elev=HEAVE_AIM[1], left=TUCK, roll=HEAVE_ROLL,
                  rolls=(HEAVE_ROLL,), radius=0.0, elbows=[HEAVE_POLE], reach_max=3.0, look=(-14.0, 5.0, -2.0)),
    # 0.30 KICK: the recoil slams the muzzle up ~17 deg and drives the hand back along the arm, the
    #      chest knocked back, the head snapped up
    "kick": dict(bd=B(15.0, 9.0, 0.15, 0.12, -0.03, 1.0, 38.0, 9.0, 0.0),
                 P=tuple(Vector(HEAVE_P) - hd * 0.5 + Vector((0.0, 0.05, 0.08))), yaw_l=7.0, elev=55.0,
                 left=TUCK, roll=HEAVE_ROLL, rolls=(HEAVE_ROLL - 15, HEAVE_ROLL, HEAVE_ROLL + 15), radius=0.1, reach_max=1.8, want=lambda: 3.0 * max(0.0, 24.0 - elbow_theta()), look=(-14.0, 11.0, -2.0)),
    # 0.37 RECOIL settles: the elbow gives, the muzzle comes back down, balance arm still tucked
    "recoil": dict(bd=B(20.0, 4.0, 0.3, 0.1, -0.1, 3.0, 32.0, 3.0, 2.0),
                   P=tuple(Vector(HEAVE_P) - hd * 0.3 + Vector((-0.1, -0.25, 0.0))), yaw_l=6.0, elev=42.0,
                   left=TUCK, roll=HEAVE_ROLL, rolls=(HEAVE_ROLL - 15, HEAVE_ROLL, HEAVE_ROLL + 15, HEAVE_ROLL + 30), look=(-14.0, 7.0, -1.5)),
    # 0.50 FOLLOW-THROUGH: the cannon's weight drags the arm DOWN, the torso rolls over the LEFT leg,
    #      the balance arm released back out
    "follow": dict(bd=B(40.0, -16.0, 0.65, 0.02, -0.35, 12.0, 14.0, -7.0, 8.0), P=(-1.5, -0.2, -1.4),
                   yaw_l=4.0, elev=10.0, left=arm_free((-1.1, -0.9, 0.3), (0.0, -0.6, 1.0)), roll=HEAVE_ROLL,
                   rolls=RW, look=(-18.0, 3.0, -1.0)),
    # 0.63 HANG: the cannon hangs by the front of the right hip, the elbow bent under the load
    "hang": dict(bd=B(36.0, -13.0, 0.62, 0.04, -0.3, 10.0, 12.0, -6.0, 6.0), P=(-1.1, -0.4, -1.7),
                 yaw_l=12.0, elev=3.0, left=arm_free((-0.7, -1.2, 0.2), (0.0, -0.4, 1.0)), roll=HEAVE_ROLL,
                 rolls=RW, look=(-20.0, 2.0, -1.5)),
    # 0.77 GATHER: small knee dip, the cannon swung in front of the belly, the left hand grabs the barrel
    "hang2": dict(bd=B(4.0, -12.0, 0.58, 0.06, -0.15, 5.0, -8.0, -6.0, 4.0), P=(-0.4, -0.35, -1.5),
                  yaw_l=35.0, elev=10.0, left=LSUP, roll=HEAVE_ROLL,
                  rolls=RW, look=(-16.0, 1.0, -2.5)),
    # 0.87 HOIST: the knees drive up, both arms swing the cannon up past the shoulder
    "hoist": dict(bd=B(4.0, -2.0, 0.25, 0.06, -0.02, 2.0, -8.0, 2.0, 0.0), P=(0.6, 1.1, -1.05),
                  yaw_l=62.0, elev=38.0, left=LSUP, roll=READY_ROLL,
                  rolls=RW, look=(-16.0, 3.0, -2.5)),
    # 0.97 it drops onto the shoulder (the knees take the landing)
    "lower": dict(bd=B(10.0, -4.0, 0.26, 0.06, 0.0, 2.0, 4.0, -3.0, 0.0), P=(1.1, 0.5, -0.9), roll=READY_ROLL,
                  yaw_l=66.0, elev=26.0, left=arm_free((0.1, -0.8, -0.85), (0.0, -0.4, 1.0)), rolls=RW,
                  look=(-14.0, 3.0, -4.0)),
}


def fk(name, frame):
    fire_pose(name=name, **K[name]); kf(frame)


def fk_mid(a, b, t, frame):
    fire_pose(**lerp_key(K[a], K[b], t)); kf(frame)


fk("coil", 3)
fk_mid("coil", "drive", 0.5, 4)
fk("drive", 5)
fire_pose(**dict(lerp_key(K["drive"], K["heave"], 0.33), rolls=(HEAVE_ROLL - 10,), elbows=[HEAVE_POLE], radius=0.3, want=want_bend(75.0, 6.0))); kf(6)
fire_pose(**dict(lerp_key(K["drive"], K["heave"], 0.67), rolls=(HEAVE_ROLL - 5,), elbows=[HEAVE_POLE], radius=0.3, reach_max=1.8, want=want_bend(45.0, 6.0))); kf(7)
fk("heave", FIRE_FRAME)
fk("kick", 9)
fk("recoil", 11)
fk_mid("recoil", "follow", 0.45, 13)                     # in-between keeps both feet on the floor
fk("follow", 15)
fk("hang", 18)
fk("hang2", 22)
fk("hoist", 26)
fk("lower", 30)
K["release"] = dict(K["lower"], P=(1.15, 0.45, -1.02), rolls=(READY_ROLL,), elbows=[e0],
                    left=arm_free((-0.15, -1.3, -0.4), (0.0, -0.4, 1.0)),
                    bd=B(6.0, -3.5, 0.2, 0.06, 0.0, 1.0, 6.0, -2.5, -1.0))
fk("release", 34)
ready(0.5, 0.0, "settle"); kf(39)                                                          # 1.27 on the shoulder
ready(0.0, 0.0); kf(45)                                                                    # 1.50
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in dbg.items():
    print("REPORTK %s %s" % (k, json.dumps(v, default=str)))
print("REPORTK legfix %s" % json.dumps(LEGFIX))
for kind, n in (("Ready", 72), ("Fire", 45)):
    L.use_clip(kind)
    lifts = []
    for fr in range(0, n + 1):
        L.goto(fr / 30.0)
        dv = max(abs(L.joint(sd + "Foot").y - L.ANKLE_REST[sd][1]) for sd in ("Left", "Right"))
        if dv > 0.015:
            lifts.append((fr, round(dv, 3)))
    print("REPORTK lift_%s %s" % (kind, lifts))
for kind in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
    L.use_clip(kind)
    bad = []
    for fr in range(0, int(round(SPEC[kind] * 30)) + 1):
        L.goto(fr / 30.0)
        DEEP[0] = None
        wl, wa, at = pen(120)
        if wl > 0.12 or wa > 0.15:
            bad.append((fr, round(wl, 2), round(wa, 2), at, DEEP[0] if wl > 0.12 else None))
    print("REPORTK scan_%s %s" % (kind, bad))
for kind in ("ChargeLo", "ChargeHi", "Fire"):
    L.use_clip(kind)
    rows, prevq = [], None
    for fr in range(0, int(round(SPEC[kind] * 30)) + 1):
        L.goto(fr / 30.0)
        q = L.pivot_cf().to_quaternion()
        lk = L.launcher_dir(META["Muzzle"]["look"])
        dq = 0.0 if prevq is None else math.degrees(q.rotation_difference(prevq).angle)
        prevq = q
        rows.append((fr, round(math.degrees(math.asin(max(-1.0, min(1.0, lk.y))))), round(dq if dq <= 180 else 360 - dq, 1),
                     round(math.degrees(L.get_rot("RightLowerArm").angle)), round(math.degrees(L.get_rot("RightHand").angle)),
                     round(L.hand_cf("Right").translation.y - L.joint("RightUpperArm").y, 2),
                     round(math.degrees(L.get_rot("Head").angle))))
    print("REPORTF %s %s" % (kind, rows))
L.finish(SPEC, OUT, extra_times=[0.1, 0.2, 0.3333, 0.4, 0.5, 0.6333, 0.7667, 0.8667, 0.9667])
