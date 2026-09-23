"""19 Lava Lobber -- a heavy black-and-gold cannon with a spiked rim, lava themed.

The player stands side-on on the pad (down-track = their LEFT, away from the camera; the camera
sees their right side / back).  Everything happens on the character's right side / FRONT
(screen-right) so the pad camera sees it; the ball then flies INTO the screen.
  Ready    the cannon carried on the front of the right shoulder, bazooka-style (grip ~0.7 from the shoulder so the arm never folds shut; rolled outward, clear of
           the head, muzzle up and forward), the right fist on the pistol grip, the left hand
           steadying the barrel; slow heavy breathing, a small weight shift.
  ChargeLo heaved off the shoulder into a two-handed LOW HOLD out in front (right hand on the grip,
           left hand under the barrel), knees bent, head up looking down-track, the body ROCKING
           with the weight (the cannon swings like a pendulum, lagging the hips).
  ChargeHi the same rock in a DEEP SQUAT (depth in the knees, not the spine), bigger swing,
           straining tremor through the arms.
  Fire     wind-up (sink lower, the cannon swung back and down toward the shins) -> the HEAVE-LOB:
           the whole body drives up, the cannon swings up to ~38 deg and the ball blasts out of the
           spiked muzzle at FireAt -> the kick tips the torso BACK, the head jerks back, the muzzle
           kicks to ~56 deg and the right foot stumbles back half a step -> knee-buckle landing ->
           regains balance, lowers the cannon, steps back in, hoists it back onto the shoulder.
Ball: hidden until it blasts out of the muzzle; lava fire burst, fire flicker while charging.
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
import numpy as np

LID = 19
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_FRAME = 11
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.8,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Never", "start": "Muzzle", "grow": 1.0},
    "Fx": {"Style": "fire", "Color": [255, 110, 30], "Charge": "fire", "ChargeColor": [255, 140, 40]},
    "TwoHanded": True,
    "AllowFootLift": True,
    "Notes": "lava cannon: shoulder carry, heave into a low two-handed hold rocking with the weight, deep straining squat, wind-up + full-body heave-lob up, recoil tips the body back + stumble",
}
FEET = {"Left": (-0.95, -0.3), "Right": (0.85, 0.45)}
LOOK_TRACK = (-14.0, 0.5, -1.8)
META = L.load_meta(LID)
G2 = META["Grip2"]["pos"]
HAND_PARTS = ("RightHand", "LeftHand")
ARM_PARTS = ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand")
ELBOWS = [Vector(v).normalized() for v in (
    (0.7, -1.0, 0.5), (1.0, -1.0, 0.0), (1.0, -0.3, 0.6), (0.4, -1.0, 0.8), (1.0, -0.6, -0.5),
    (0.3, -1.0, -0.3), (1.0, 0.2, 0.3), (0.6, -0.5, 1.0))]
L_ELBOW = (0.3, 1.0, 0.1)


def guard_nx(side, target, pole):
    """the elbow-guard hinge x the library would see for this arm target / pole (< -0.15 = mirrored)"""
    Mi = L.frame_of("UpperTorso").inverted()
    d = Mi @ (Vector(target) - L.joint(side + "UpperArm"))
    n = d.normalized().cross(Mi @ Vector(pole))
    return round(n.normalized().x, 2) if n.length > 1e-4 else 0.0
# one fixed right-elbow pole: continuous swivel.  UP-ish (= the old (0.4, -1, 0.8) pole, which the
# library's elbow guard mirrored in every key anyway -- same elbows, no reliance on the guard)
FIX_EL = [Vector((-0.4, 1.0, -0.8)).normalized()]
READY_EL = [Vector((-0.3, 1.0, 0.1)).normalized()]  # the pole for the hoist onto the shoulder
# the shouldered carry folds the arm tight (wrist ~0.5 from the shoulder), so one fixed pole's hinge
# sits near the guard's threshold and flips between keys: every Ready key picks from these UP-ish
# poles the one that keeps the elbow where the first carry key put it (READY_ELB, torso-local)
READY_POLES = [Vector(v).normalized() for v in (
    (-0.3, 1.0, 0.1), (-0.3, 1.0, 0.4), (-0.3, 1.0, -0.2), (0.0, 0.4, 1.0), (-0.5, 0.8, 0.5),
    (0.2, 1.0, 0.3), (-0.6, 0.6, 0.0), (0.0, 1.0, 0.8))]
READY_ELB = None
CONT = [None]
KICK_EL = [Vector((-0.6, 0.5, -1.0)).normalized()]   # UP-ish: the hinge the guard used to mirror (0.6, -0.5, 1) into
FREE_POLE = (0.15, 0.3, -1.0)                        # torso-local: a hanging left arm, elbow bent forward-ish
GRIP = None
dbg = {}
_last = {}

# ------------------------------------------------------------------ launcher mesh in the pivot frame
L.reset_pose()
L.update()
_ob = L.launcher_object()
_mw = _ob.matrix_world
_piv_inv = L.pivot_cf().inverted()
_loc = [tuple(_piv_inv @ L.b2r(_mw @ v.co)) for v in _ob.data.vertices]
MESH_LOCAL = np.array(_loc)                         # (N, 3) pivot-frame, scaled
if len(MESH_LOCAL) > 1500:
    MESH_LOCAL = MESH_LOCAL[::max(1, len(MESH_LOCAL) // 1500)]
# parts the cannon must never enter (weights); hands / forearms hold it
PEN_PARTS = {"Head": 1.0, "UpperTorso": 1.0, "LowerTorso": 0.8, "RightUpperArm": 0.6,
             "LeftUpperArm": 0.4, "LeftUpperLeg": 0.6, "RightUpperLeg": 0.6,
             "LeftLowerLeg": 0.4, "RightLowerLeg": 0.4}


def mesh_world():
    P = np.array(L.pivot_cf())
    return MESH_LOCAL @ P[:3, :3].T + P[:3, 3]


def mesh_pen(margin=0.06):
    """worst launcher-vertex depth inside the guarded body boxes (grown by margin);
    returns (weighted sum, worst depth, worst part, push direction world)"""
    W = mesh_world()
    total, worst, who, push = 0.0, 0.0, None, None
    for name, box, half in L.body_boxes():
        if name not in PEN_PARTS:
            continue
        inv = np.array(box.inverted())
        Q = W @ inv[:3, :3].T + inv[:3, 3]
        h = np.array(half) + margin
        inside = np.all(np.abs(Q) < h, axis=1)
        if not inside.any():
            continue
        depth = float(np.min(h - np.abs(Q[inside]), axis=1).max())
        total += PEN_PARTS[name] * depth
        if depth > worst:
            worst, who = depth, name
            c = np.array(tuple(box.translation))
            d = W[inside].mean(axis=0) - c
            push = Vector(tuple(d)).normalized() if np.linalg.norm(d) > 1e-6 else Vector((1.0, 0.0, 0.0))
    return total, worst, who, push


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


# deterministic tremor table (alternating signs so neighbouring keys jitter against each other)
SHAKE = []
for i in range(24):
    sg = 1.0 if i % 2 == 0 else -1.0
    SHAKE.append((sg * (0.6 + 0.4 * abs(math.sin(i * 2.7 + 0.3))), math.sin(i * 4.1 + 1.9),
                  -sg * (0.5 + 0.5 * abs(math.sin(i * 5.3 + 0.7))), math.sin(i * 3.3 + 2.4)))
ZERO = (0.0, 0.0, 0.0, 0.0)


# ------------------------------------------------------------------ helpers
def leg(side, x, z, lift=0.0, yaw=None):
    """re-solves one leg to an ankle spot (x, z) raised `lift` studs off the floor (a step)"""
    q_root = L.get_rot("LowerTorso")
    yaw_root = math.degrees(2.0 * math.atan2(q_root.y, q_root.w)) if abs(q_root.w) > 1e-6 else 0.0
    yaw = yaw_root if yaw is None else yaw
    target = Vector((x, L.ANKLE_REST[side][1] + lift, z))
    toe = L.ry(yaw) @ Vector((0.0, 0.0, -1.0))
    hip = L.joint(side + "UpperLeg")
    Mi = L.frame_of("LowerTorso").inverted()
    qu, ql, err = L.solve_limb(Mi @ (target - hip), L.THIGH, L.SHIN, Mi @ toe, bend=-1.0)
    L.set_rot(side + "UpperLeg", qu)
    L.set_rot(side + "LowerLeg", ql)
    L.update()
    want = (L.ry(yaw) @ L.rx(-12.0 * min(1.0, lift / 0.3))).to_matrix()
    L.set_rot(side + "Foot", (L.frame_of(side + "LowerLeg").inverted() @ want).to_quaternion())
    L.update()
    return err


def body(yaw, lean, drop, back, side=0.0, roll=0.0, waist_yaw=0.0, waist_bend=0.0, waist_roll=0.0,
         feet=None, step=None):
    """step = (side, x, z, lift) to move one foot"""
    L.reset_pose()
    f = dict(FEET if feet is None else feet)
    if step is not None:
        f[step[0]] = (step[1], step[2])
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=f)
    if step is not None and step[3] > 0.0:
        leg(step[0], step[1], step[2], step[3])
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def wrist_swing():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


UNDERSIDE = [(0.0, -0.15 * i, -0.3) for i in range(0, 10)]
# + the rear T-handle (a free hand can grab it on a shouldered cannon)
NEAR_PTS = UNDERSIDE + [(0.0, 0.92, -0.6), (0.0, 0.92, -0.42), (0.0, 0.92, -0.78), (0.0, 0.6, -0.6)]


def left_target(mode):
    if mode == "grip2":
        return L.launcher_point(G2)
    if mode == "under":
        # a hand under the barrel, the spot nearest the left shoulder (the low swing of the wind-up)
        sh = L.joint("LeftUpperArm")
        return min((L.launcher_point(p) for p in UNDERSIDE), key=lambda v: (v - sh).length)
    if mode == "near":
        # the spot under the barrel nearest the left shoulder (steadying a shouldered cannon)
        sh = L.joint("LeftUpperArm")
        return min((L.launcher_point(p) for p in NEAR_PTS), key=lambda v: (v - sh).length)
    return L.launcher_point(mode)


def free_left(fwd=0.0, out=0.0, lift=0.0):
    """the left arm off the cannon: hanging relaxed beside the body (fwd = forearm swung forward,
    out = away from the hip, lift = hand raised), well inside reach, elbow bent forward"""
    Mt = L.frame_of("UpperTorso")
    sh = L.joint("LeftUpperArm")
    tgt = sh + Mt @ Vector((-0.6 - out, -1.25 + lift, -0.22 - fwd))
    pole = Mt @ Vector(FREE_POLE)
    L.arm_to("Left", tgt, elbow_away=tuple(pole))
    return tgt, pole


def elbow_local():
    return L.frame_of("UpperTorso").inverted() @ (L.joint("RightLowerArm") - L.joint("RightUpperArm"))


def cost_now(offset, left, reach):
    c = wrist_swing() + 60.0 * offset + 300.0 * reach
    el = L.joint("RightLowerArm")
    ce, _ = L.clearance(el, skip=ARM_PARTS)
    c += 150.0 * max(0.0, 0.12 - ce)
    pen, _, _, _ = mesh_pen()
    c += 600.0 * pen
    c += 12.0 * max(0.0, wrist_swing() - 72.0)                      # spare the wrist
    c += 400.0 * max(0.0, -2.9 - float(mesh_world()[:, 1].min()))  # keep it off the floor
    dw = (L.joint("RightHand") - L.joint("RightUpperArm")).length    # arm neither folded shut
    c += 400.0 * max(0.0, 0.72 - dw) + 400.0 * max(0.0, dw - 1.55)  # nor locked straight
    if CONT[0] is not None:                                          # elbow continuity (Ready carry)
        c += 400.0 * (elbow_local() - CONT[0]).length
    if left is not None:
        tgt = left_target(left)
        L.left_hand_to(point=tgt, elbow_away=L_ELBOW)
        c += 350.0 * (L.hand_cf("Left").translation - tgt).length
    return c


def do_head(look, tilt):
    if look is not None:
        L.head_look(target=look)
    if tilt:
        L.set_rot("Head", L.get_rot("Head") @ L.rz(tilt))
        L.update()


def search(P, fwd, up, left, radius, step, elbows):
    n = int(round(radius / step))
    best = None
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            for k in range(-n, n + 1):
                off = Vector((i * step, j * step, k * step))
                if off.length > radius + 1e-6:
                    continue
                for e in (elbows or ELBOWS):
                    info = L.place_launcher(at=Vector(P) + off, forward=fwd, up=up, anchor="Pivot",
                                            elbow_away=e, grip_twist=GRIP)
                    c = cost_now(off.length, left, info["arm_overreach"])
                    if best is None or c < best[0]:
                        best = (c, Vector(P) + off, e)
    return best


def solve(P, yaw, elev, roll=0.0, left="grip2", radius=0.15, step=0.15, name=None, look=LOOK_TRACK,
          elbows=None, tilt=0.0, push=True, free=(0.0, 0.0, 0.0)):
    """launcher forward along (yaw, elev); the grip searched around P (fixed GRIP) for a natural
    wrist, the elbow / cannon out of the body and the left hand on its spot.  If the cannon mesh
    still sits in the head / torso / upper arm, the grip target is pushed out and re-searched."""
    fwd = L.direction(yaw, elev)
    up = L.up_for(fwd, roll)
    do_head(look, tilt)
    P = Vector(P)
    pushed = Vector((0.0, 0.0, 0.0))
    sleft = None if left == "free" else left
    for it in range(5):
        c, Pq, e = search(P, fwd, up, sleft, radius, step, elbows)
        info = L.place_launcher(at=Pq, forward=fwd, up=up, anchor="Pivot", elbow_away=e, grip_twist=GRIP)
        _, worst, who, pdir = mesh_pen(margin=0.0)
        if not push or worst < 0.05 or pdir is None:
            break
        mv = pdir * (worst + 0.06)
        P = P + mv
        pushed += mv
    if left == "free":
        ftgt, fpole = free_left(*free)
        dbg["_lr"] = (0.0, 0.0)
        lnx = guard_nx("Left", ftgt, fpole)
        gap = -1.0
    elif left is not None:
        tgt = left_target(left)
        lr = L.left_hand_to(point=tgt, elbow_away=L_ELBOW)
        dbg["_lr"] = lr
        lnx = guard_nx("Left", L.joint("LeftHand"), L_ELBOW)
        gap = (L.hand_cf("Left").translation - tgt).length
    else:
        gap = -1.0
        lnx = None
    rnx = guard_nx("Right", L.joint("RightHand"), e)
    dbg["_Pq"] = Pq.copy()
    do_head(look, tilt)
    _, worst, who, _ = mesh_pen(margin=0.0)
    if name:
        dbg[name] = {"cost": round(c, 1), "P": [round(v, 2) for v in Pq], "pushed": [round(v, 2) for v in pushed],
                     "pen": [round(worst, 2), who], "elbow": [round(v, 2) for v in e],
                     "swing": round(wrist_swing(), 1), "gap": round(gap, 3), "reach": info["arm_overreach"],
                     "lreach": dbg["_lr"][0] if left is not None else None, "nx": [rnx, lnx],
                     "low": round(L.launcher_lowest_y(), 2),
                     "D": round((L.joint("RightHand") - L.joint("RightUpperArm")).length, 2),
                     "elb": [round(v, 2) for v in (L.frame_of("UpperTorso").inverted() @ (L.joint("RightLowerArm") - L.joint("RightUpperArm")))],
                     "wr": [round(v, 2) for v in (L.frame_of("UpperTorso").inverted() @ (L.joint("RightHand") - L.joint("RightUpperArm")))],
                     "muzzle": [round(v, 2) for v in L.launcher_point(META["Muzzle"]["pos"])]}
    return e


# ------------------------------------------------------------------ poses
R_T = 32.0      # the carry turned toward the track: the head shows screen-left of the cannon
READY_OFF = None


def ready(b, w=0.0, name=None):
    """b 0..1 breathing, w -1..1 weight shift.  Cannon resting out on top of the right shoulder."""
    # the body turns toward the track (half in the hips, half in the waist) so from the pad camera
    # the head stays in view beside the cannon; the cannon sits out on top of the right shoulder,
    # rolled outward, clear of the head
    body(yaw=R_T * 0.5 + 4.0 * w, lean=-3.0 - 3.5 * b, drop=0.18 + 0.1 * b, back=0.08, side=0.1 * w,
         roll=-1.5 * w, waist_yaw=R_T * 0.5, waist_bend=-2.0 - 2.0 * b, waist_roll=-3.0 + 1.5 * w)
    P = L.ry(R_T) @ Vector((1.38 + 0.03 * w, 0.36 + 0.05 * b, -1.1))
    # the left arm hangs relaxed (the cannon sits out of its reach), swaying with the breath / weight;
    # the grip offset is searched ONCE (rest pose) and reused: the cannon rides the breath instead
    # of hopping between grips from key to key
    global READY_OFF, READY_ELB
    first = READY_OFF is None
    CONT[0] = READY_ELB
    solve(tuple(P if first else P + READY_OFF), 86.0 - R_T - 3.0 * w, 28.0 + 4.0 * b, roll=12.0, left="free",
          elbows=READY_EL if first else READY_POLES, radius=0.15 if first else 0.0, push=first,
          free=(0.06 * b + 0.04 * w, 0.03 * b, 0.0),
          name=name, look=(-12.0, 1.0 - 0.3 * b, -3.0), tilt=7.0)
    CONT[0] = None
    if first:
        READY_OFF = dbg["_Pq"] - P
        READY_ELB = elbow_local().copy()


CH_YAW = 44.0
CH_X, CH_Y, CH_YD, CH_Z = 0.8, -0.8, 0.22, -1.3
GRIP_WRIST = 25.0
CH_ROLL = 16.0      # the barrel rolled off the right upper arm


def charge(depth, phase, s=ZERO, name=None):
    """depth 0..1 = Lo..Hi, phase 0..1 through the rock, s = tremor sample"""
    rock = math.sin(2.0 * math.pi * phase)                 # + = weight rocking forward
    lag = math.sin(2.0 * math.pi * phase - 0.9)            # the cannon swings behind the hips
    bob = math.cos(4.0 * math.pi * phase)                  # dips as the weight passes the middle
    a = 2.4 + 0.9 * depth                                 # rock amplitude (big enough to read from the pad camera)
    t = 0.3 + 1.0 * depth                                  # tremor amplitude
    body(yaw=12.0 + 1.5 * a * lag + 0.6 * t * s[3],
         lean=-10.0 - 3.0 * depth - 0.8 * a * rock - 2.0 * a * lag + 0.6 * t * s[1],
         drop=0.55 + 0.5 * depth + 0.03 * a * bob + 0.01 * t * s[1],
         back=0.18 + 0.14 * depth - 0.05 * a * rock, side=0.03 * a * lag, roll=-2.0 * a * lag,
         waist_yaw=-14.0 - 4.0 * depth + 0.8 * a * lag + 0.8 * t * s[0],
         waist_bend=-4.0 - 4.0 * depth + 2.0 * a * lag + 0.8 * t * s[2],
         waist_roll=1.5 * a * lag + 0.8 * t * s[0])
    solve((CH_X + 0.012 * t * s[0],
           CH_Y - CH_YD * depth - 0.03 * a * bob + 0.06 * a * lag + 0.012 * t * s[1],
           CH_Z - 0.1 * depth - 0.02 * a * lag - 0.035 * a * rock + 0.01 * t * s[2]),
          CH_YAW + 1.1 * a * lag + 0.8 * t * s[3], -14.0 - 6.0 * depth + 2.4 * a * lag + 0.8 * t * s[1],
          roll=CH_ROLL + 2.0 * a * lag, name=name, elbows=FIX_EL, radius=0.0, push=False,
          look=(-14.0, 0.5 - 0.5 * depth + 0.3 * t * s[1], -2.2 - 0.4 * a * rock))


def fire_pose(drive, elev, recoil=0.0, step=None, name=None, look=None, feet=None,
              lean_add=0.0, bend_add=0.0, drop_add=0.0, back_add=0.0, P_add=(0.0, 0.0, 0.0), yaw=None, elbows=None, left="grip2", twist_add=0.0):
    """drive 0 = crouched low (ChargeHi depth), 1 = fully driven up; elev = muzzle elevation;
    recoil 0..1 = the kick back toward the camera side (+X)"""
    body(yaw=12.0 - 2.0 * drive - 6.0 * recoil, lean=-13.0 + 21.0 * drive - 2.0 * recoil + lean_add,
         drop=1.05 - 0.95 * drive + 0.1 * recoil + drop_add,
         back=0.32 - 0.2 * drive + 0.05 * recoil + back_add,
         side=0.28 * recoil, roll=-6.0 * recoil,
         waist_yaw=-14.0 + 16.0 * drive + twist_add,waist_bend=-8.0 + 14.0 * drive + 6.0 * recoil + bend_add,
         waist_roll=-4.0 * recoil, feet=feet, step=step)
    P = (0.9 - 0.5 * drive + 0.25 * recoil + P_add[0], -1.5 + 1.55 * drive + 0.15 * recoil + P_add[1],
         -1.55 + 0.45 * drive + 0.05 * recoil + P_add[2])
    solve(P, yaw if yaw is not None else 6.0 + (CH_YAW - 6.0) * (1.0 - drive), elev, name=name, elbows=elbows, left=left,
          look=look if look is not None else (-14.0, 0.5 + 5.0 * drive + 2.0 * recoil, -1.8))


# ------------------------------------------------------------------ grip: probed in the low hold
GRIP = None
body(yaw=12.0, lean=-11.5, drop=0.8, back=0.25, waist_yaw=-14.0, waist_bend=-6.0)   # the mid charge body
info = L.hold((1.05, -1.0, -1.35), yaw=CH_YAW, elev=-17.0, elbow_away=tuple(FIX_EL[0]), max_wrist=GRIP_WRIST)
dbg["grip_probe"] = info
GRIP = L.get_rot("Launcher").copy()

# ------------------------------------------------------------------ clips
clip("Ready")
ready(0.0, 0.0, "ready0"); kf(0)
ready(1.0, 0.6, "ready1"); kf(20)
ready(0.3, 1.0, "ready2"); kf(36)
ready(0.9, -0.5, "ready3"); kf(54)
ready(0.0, 0.0); kf(72)
L.make_cyclic("Ready")

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    clip(kind)
    for i in range(12):
        charge(depth, i / 12.0, SHAKE[i], kind + "_%d" % i); kf(3 * i)
    charge(depth, 0.0, SHAKE[0]); kf(36)
    L.make_cyclic(kind)

LF = FEET["Left"]
clip("Fire")
charge(1.0, 0.0, ZERO); kf(0)                                                    # 0.00 ChargeHi pose
# 0.20 WIND-UP: sink lower, the cannon swung back and down toward the shins
fire_pose(0.0, -29.0, drop_add=0.38, lean_add=-9.0, bend_add=-6.0, P_add=(0.12, 0.3, 0.35), yaw=57.0,
          name="windup", look=(-8.0, -2.5, -2.5), elbows=FIX_EL, twist_add=-10.0); kf(5)          # 0.17 coiled
fire_pose(0.55, 14.0, name="drive", elbows=FIX_EL); kf(8)                        # 0.27 driving up
fire_pose(1.0, 34.0, name="lob", elbows=FIX_EL, P_add=(0.0, -0.2, 0.0), yaw=9.0); kf(FIRE_FRAME)  # 0.37 LOB
# 0.50 KICK: torso tips back, head jerks back, muzzle kicks up, right foot lifts to stumble back
fire_pose(0.95, 60.0, recoil=0.75, step=("Right", 1.1, 0.8, 0.25), lean_add=10.0, bend_add=3.0,
          look=(-10.0, 7.5, -1.8), name="kick", elbows=KICK_EL); kf(14)                          # sharper: 3 frames after the shot
# 0.63 lands back: knee buckle, the muzzle falls back
fire_pose(0.8, 40.0, recoil=1.0, step=("Right", 1.35, 0.95, 0.0), drop_add=0.18, back_add=0.15,
          lean_add=2.0, name="stumble", elbows=KICK_EL); kf(19)
fire_pose(0.75, 28.0, recoil=0.7, feet={"Left": LF, "Right": (1.35, 0.95)}); kf(25)   # 0.83 regain
fire_pose(0.6, 10.0, recoil=0.4, feet={"Left": LF, "Right": (1.35, 0.95)},
          look=(-12.0, 1.0, -2.5)); kf(31)                                       # 1.03 lowering
fire_pose(0.6, 4.0, recoil=0.2, step=("Right", 1.05, 0.55, 0.2), look=(-10.0, 0.5, -2.5)); kf(36)  # step in
# 1.43 hoist: the cannon swings up across the chest toward the outer shoulder
body(yaw=14.0, lean=-6.0, drop=0.28, back=0.12, waist_yaw=14.0, waist_bend=-4.0, waist_roll=-2.0)
solve(tuple(L.ry(28.0) @ Vector((1.3, -0.1, -1.0))), 58.0, 12.0, roll=8.0, left="free", free=(0.35, 0.05, 0.12),
      elbows=READY_EL, name="hoist", look=(-12.0, 0.5, -3.0), tilt=4.0); kf(41)
# 1.53 up and OUT past the head, then down onto the shoulder
body(yaw=16.0, lean=-4.0, drop=0.22, back=0.1, waist_yaw=16.0, waist_bend=-3.0, waist_roll=-3.0)
solve(tuple(L.ry(32.0) @ Vector((1.5, 0.3, -1.1))), 56.0, 22.0, roll=12.0, left="free", free=(0.18, 0.03, 0.05), elbows=READY_EL, name="hoist2",
      look=(-12.0, 0.8, -3.0), tilt=6.0); kf(44)
ready(0.6, 0.0, "settle"); kf(50)                                                # 1.63 back on the shoulder
ready(0.0, 0.0, "ready_end"); kf(54)                                                          # 1.80
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in dbg.items():
    print("REPORTK %s %s" % (k, json.dumps(v, default=str)))

# per-frame probe: right-elbow jumps (max step and max 2nd difference), wrist range, motion ranges
for kind in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
    L.use_clip(kind)
    n = int(round(SPEC[kind] * 30))
    el, wr, hd, mz, gp = [], [], [], [], []
    for f in range(n + 1):
        L.goto(f / 30.0)
        el.append(L.joint("RightLowerArm").copy())
        wr.append(wrist_swing())
        hd.append(L.joint("Head").copy())
        mz.append(L.launcher_point(META["Muzzle"]["pos"]).copy())
        gp.append((L.hand_cf("Left").translation - L.launcher_point(G2)).length)
    st = [(el[i + 1] - el[i]).length for i in range(n)]
    ac = [(el[i + 1] - 2 * el[i] + el[i - 1]).length for i in range(1, n)]
    rng = lambda ps: round(max(max(p[i] for p in ps) - min(p[i] for p in ps) for i in range(3)), 2)
    print("REPORTP %s elbow_step_max %.3f at f%d  elbow_acc_max %.3f at f%d  wrist %.0f..%.0f  head_rng %s  muzzle_rng %s  gap %s" % (
        kind, max(st), st.index(max(st)), max(ac), ac.index(max(ac)) + 1, min(wr), max(wr), rng(hd), rng(mz),
        " ".join("%.2f" % g for g in gp[::3])))
    if kind != "Ready":
        print("REPORTS %s steps %s" % (kind, " ".join("%.2f" % v for v in st)))
L.finish(SPEC, OUT, extra_times=[0.1667, 0.2667, 0.4667,0.6333, 0.8333, 1.0333, 1.2, 1.4333, 1.5333])
