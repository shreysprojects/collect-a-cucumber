"""12 Snow Revolver -- one-handed gunslinger.

Concept: a big purple snow revolver held in the RIGHT hand only.
  Ready    cowboy stance, the gun hangs low at the right hip pointing forward/down, lazy sway,
           weight shift + knee give, the gun bobbing in the hand.
  ChargeLo hip-fire aim: the grip at the belly, barrel at chest height aimed down the track
           one-handed, elbow hanging at the side (UP-ish pole), gun canted a little away from the
           face, head cocked away; the LEFT hand FANS the hammer: a big arc up and back over the
           brow, a chop down-forward onto the top bar, a brush off the front, and back up.  Calm.
  ChargeHi same key timing, backswing 1.5x, crouched deeper, the gun jolts up on every slap and
           the body bounces.
  Fire     a last slap -> snap shot (elev ~5, 0.133 s) -> KICK: the muzzle snaps up ~50 deg and the
           body rocks back (0.23 s), hangs a beat (0.30 s) -> the arm swings out to the front-right
           and the gun SPINS 360 about the trigger finger (Launcher bone) -> catch -> hip hold.
Audit fixes (2026-09-23, after the elbow guard): consistent UP-ish right-arm poles through aim /
kick / spin (the old down-ish kick pole tucked the elbow into the chest = 0.46 sunk + a shoulder
snap), less hip/chest counter-twist, the left palm unrolls gradually after the last slap (no hand
snap), the left arm's wrist AND pole blend back to the side, the head turn blends angles.
Ball: hidden, pops out of the muzzle at FireAt.
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
from mathutils import Vector

LID = 12
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.2,
    "FireAt": 0.133,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "smoke", "Color": [225, 215, 255]},
    "TwoHanded": False,
    "Notes": "gunslinger revolver: hip carry, one-handed aim while the left hand fans the hammer, snap shot + kick + trigger-finger spin",
}
FEET = {"Left": (-0.95, -0.25), "Right": (0.75, 0.35)}
HAMMER = (0.0, -0.05, -1.45)      # top-rear of the revolver (pivot frame, template scale)
DOWN = (-12.0, 0.6, -1.6)         # where the eyes go when aiming
report = {}
READY_Q = [None]
READY_YAW = 64.0

# the aim (charge) hold
AIM = Vector((0.45, -0.95, -1.2))
AIM_YAW, AIM_ROLL = 17.0, 8.0
AIM_POLE = [(-0.3, 1.0, 0.1)]       # UP-ish pole: the elbow hangs down at the side
TOPBAR = (0.0, -0.4, -1.5)        # the gun's top bar just ahead of the hammer (the slap spot)
LEFT_REACH = 1.58
BODY = dict(yaw=24.0, lean=-4.0, wy=-28.0, wb=1.0, wr=-18.0)
FAN_A = (0.9, 0.35)                # backswing height: Lo, extra at Hi


def body(yaw=10.0, lean=-4.0, drop=0.15, back=0.05, side=0.0, waist_yaw=0.0, waist_bend=-4.0, waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def H(*a, **kw):
    info = L.hold(*a, **kw)
    if READY_Q[0] is not None:
        q = L.get_rot("Launcher")
        if q.dot(READY_Q[0]) < 0:
            q = -q
        info["rel_turn"] = round(math.degrees(READY_Q[0].rotation_difference(q).angle), 1)
    info["sh_el_wr"] = [[round(c, 2) for c in L.joint(b)] for b in ("RightUpperArm", "RightLowerArm", "RightHand")]
    return info


def free_left(swing=0.0, out=0.0, lift=0.0):
    """relaxed left arm hanging beside the body (torso-relative)"""
    T = L.frame_of("UpperTorso")
    sh = L.joint("LeftUpperArm")
    wrist = sh + T @ Vector((-0.22 - out, -1.5 + lift, 0.12 + swing))
    L.arm_to("Left", wrist, elbow_away=T @ Vector((-0.2, 0.0, 1.0)))


# fan stroke, offsets from the slap spot in Roblox space (Y/Z = the pad camera's screen plane,
# +X = toward the camera; depth is given up first when out of reach).  The whole stroke stays
# ABOVE / in front of the gun: the torso's gunslinger roll puts the head over the gun, so any
# stroke that drops back toward the chest drags the left arm under the chin.
def fan_offset(p, a):
    """offset from the slap spot on top of the gun.  a = backswing height"""
    high = Vector((0.2, 0.8 * a, 0.35 + 0.2 * a))         # backswing: up and back, over the brow
    peak = Vector((0.2, 0.8 * a + 0.1, 0.4 + 0.2 * a))    # wind-up at the top (a big arc on screen)
    hit = Vector((0.1, 0.2, -0.05))                       # palm slaps the hammer / top rib
    off = Vector((0.1, 0.18, -0.35))                      # the palm brushes forward off the hammer
    past = Vector((0.2, 0.38, -0.5))                      # rebounds up off the front of the gun
    if p <= 0.3:
        return high.lerp(peak, L.smooth(p / 0.3))
    if p <= 0.45:
        return peak.lerp(hit, (p - 0.3) / 0.15)
    if p <= 0.55:
        return hit.lerp(off, (p - 0.45) / 0.1)
    if p <= 0.7:
        return off.lerp(past, (p - 0.55) / 0.15)
    u = (p - 0.7) / 0.3
    return past.lerp(high, L.smooth(u))

def reachable(t, max_d=LEFT_REACH):
    """keeps a left-hand target in reach by giving up DEPTH (x, along the pad camera's view
    axis) first, so its place on screen stays put"""
    ls = L.joint("LeftUpperArm")
    t = Vector(t)
    if (t - ls).length <= max_d:
        return t
    yz2 = (t.y - ls.y) ** 2 + (t.z - ls.z) ** 2
    if yz2 < max_d * max_d:
        t.x = ls.x + math.sqrt(max_d * max_d - yz2) * (1.0 if t.x >= ls.x else -1.0)
    else:
        # out of reach even on screen: pull it in toward the shoulder in the screen plane too
        k = max_d / math.sqrt(yz2)
        t = Vector((ls.x, ls.y + (t.y - ls.y) * k, ls.z + (t.z - ls.z) * k))
    return t


def fan_left(p, a):
    spot = L.launcher_point(TOPBAR)
    t = reachable(spot + fan_offset(p, a))
    err = L.left_hand_to(point=t, elbow_away=(-1.0, -0.3, -0.3), palm_toward=(0.0, -1.0, 0.1))
    return [err[0], [round(v, 2) for v in t], [round(v, 2) for v in spot], [round(v, 2) for v in L.joint("LeftUpperArm")]]


# ------------------------------------------------------------------ poses
def ready(b, s, c):
    """b 0..1 breathing, s -1..1 sway, c -1..1 gun bob (out of phase)"""
    body(yaw=12.0 + 6.0 * s, lean=-3.0 - 1.5 * b, drop=0.2 + 0.04 * b + 0.05 * abs(s), side=0.18 * s,
         waist_yaw=-6.0 - 3.0 * s, waist_bend=-3.0 - 2.0 * b, waist_roll=3.0 * s)
    info = H((1.3, -1.05 + 0.03 * b + 0.04 * c, -0.6), yaw=READY_YAW + 5.0 * c, elev=-32.0 - 2.0 * b + 5.0 * s,
             elbow_away=(0.6, -0.3, 1.0))
    free_left(swing=0.1 * s, out=0.03 * b)
    L.head_look(target=(-8.0, 0.5, -3.0 + 1.5 * s))
    return info


def aim_body(depth, fan_p=None, bounce=0.0, shake=0.0):
    # the fan rocks the chest: backswing twists the left shoulder up/forward, the slap drops it
    wy, wr = 0.0, 0.0
    if fan_p is not None:
        rise = math.cos(math.pi * min(1.0, abs(fan_p - 0.15) / 0.45)) if abs(fan_p - 0.15) < 0.45 else -1.0
        rise = 0.5 + 0.5 * rise
        wy, wr = -5.0 * rise, -5.0 * rise
    B = BODY
    body(yaw=B["yaw"] + 3.0 * depth, lean=B["lean"] - 8.0 * depth, drop=0.38 + 0.4 * depth + bounce,
         back=0.1 + 0.08 * depth, side=0.04, waist_yaw=B["wy"] + wy + 1.5 * shake,
         waist_bend=B["wb"] - 2.0 * depth, waist_roll=B["wr"] + wr)


def aim_gun(depth, kick=0.0, shake=0.0, yaw=None, elev=None):
    """the gun raised and aimed down the track, arm out in front.  kick 0..1 = hammer jolt"""
    at = AIM + Vector((0.03 * kick, -0.2 * depth + 0.08 * kick, -0.05 * depth))
    return H(tuple(at), yaw=(AIM_YAW + 2.0 * depth + 3.5 * shake) if yaw is None else yaw,
             elev=(4.0 + 14.0 * kick + 3.0 * shake) if elev is None else elev, roll=AIM_ROLL,
             elbow_away=AIM_POLE[0])


def aim_head(tilt=14.0):
    """sight down the track, head cocked away from the gun (top toward the pad camera's left)"""
    L.head_look(target=DOWN)
    L.set_rot("Head", L.get_rot("Head") @ L.rz(tilt))
    L.update()


def screen_gap():
    """pad-camera screen gap (studs, Z/Y plane) between the head block and the gun; < 0 = overlap"""
    E = Vector(L.CAMERA_GAME[0])
    f = (Vector(L.CAMERA_GAME[1]) - E).normalized()
    r = f.cross(Vector((0.0, 1.0, 0.0))).normalized()
    u = r.cross(f)

    def proj(p):
        d = p - E
        k = 13.3 / d.dot(f)
        return d.dot(r) * k, d.dot(u) * k
    z0 = y0 = 99.0
    z1 = y1 = -99.0
    for name, box, half in L.body_boxes():
        if name == "Head":
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        a, b = proj(box @ Vector((sx * half.x, sy * half.y, sz * half.z)))
                        z0, z1, y0, y1 = min(z0, a), max(z1, a), min(y0, b), max(y1, b)
    ob = L.launcher_object()
    L.update()
    mw = ob.matrix_world
    best = 9.0
    for v in ob.data.vertices:
        a, b = proj(L.b2r(mw @ v.co))
        best = min(best, max(z0 - a, a - z1, y0 - b, b - y1))
    return round(best, 2)


def charge(p, depth, kick=0.0, shake=0.0, bounce=0.0):
    aim_body(depth, p, bounce, shake)
    info = aim_gun(depth, kick, shake)
    info["left"] = fan_left(p, FAN_A[0] + FAN_A[1] * depth)
    want = L.launcher_point(TOPBAR) + fan_offset(p, FAN_A[0] + FAN_A[1] * depth)
    got = L.hand_cf("Left").translation
    info["hand_gap_yz_x"] = [round(math.hypot(got.y - want.y, got.z - want.z), 2), round(got.x - want.x, 2)]
    aim_head()
    info["gap"] = screen_gap()
    return info


def static_depth():
    """worst arm depth in the torso/head for the CURRENT pose (the audit's boxes)"""
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    wa, wat = 0.0, ""
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for bd in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[bd])
                        if d > wa:
                            wa, wat = d, arm[:-3] + ">" + bd[:2]
    return round(wa, 2), wat


if os.environ.get("PROBE12B"):
    import itertools
    global_rows = []
    ready(0.0, 0.0, 0.0)
    READY_Q[0] = L.get_rot("Launcher")
    POLES = {"old": (1.0, -0.9, 0.2), "up": (-0.3, 1.0, 0.1), "upfwd": (0.3, 1.0, -0.3), "out": (-1.0, 0.6, 0.2)}
    for yaw, wy, wr, ax, ay, az, pole, roll in itertools.product(
            (24, 30), (-32, -40), (-18,), (0.45, 0.6), (-0.95,), (-1.05, -1.25), ("up",), (4, 10, 15)):
        AIM_ROLL = roll
        hg = 0.0
        BODY.update(yaw=yaw, lean=-4.0, wy=wy, wb=1.0, wr=wr)
        AIM[:] = (ax, ay, az)
        AIM_POLE[0] = POLES[pole]
        wd, over, lover, wb, rt = 0.0, 0.0, 0.0, 0.0, 0.0
        where = ""
        for depth in (0.0, 1.0):
            for p in (0.0, 0.15, 0.3, 0.45, 0.7):
                aim_body(depth, p)
                inf = aim_gun(depth)
                le = fan_left(p, FAN_A[0] + FAN_A[1] * depth)
                d, w = static_depth()
                if d > wd:
                    wd, where = d, w
                over = max(over, inf["arm_overreach"])
                lover = max(lover, le[0])
                wb = max(wb, inf["wrist_bend_deg"])
                rt = max(rt, inf.get("rel_turn", 0.0))
                if p == 0.45:
                    want = L.launcher_point(TOPBAR) + fan_offset(p, FAN_A[0] + FAN_A[1] * depth)
                    hg = max(hg, (L.hand_cf("Left").translation - want).length)
                if p == 0.3 and depth == 0.0:
                    gp = screen_gap()
        score = -wd * 4 - over * 4 - hg * 3 - wb / 100.0 - rt / 100.0 + min(gp, 0.0) * 3
        global_rows.append((score, "roll%d hitgap %.2f yaw%d wy%d wr%d aim(%.2f,%.2f,%.2f) %s | depth %.2f %s over %.2f lover %.2f wbend %.0f turn %.0f gap %.2f" % (
            roll, hg, yaw, wy, wr, ax, ay, az, pole, wd, where, over, lover, wb, rt, gp)))
    global_rows.sort(key=lambda r: -r[0])
    for r in global_rows[:30]:
        print("REPORT_PROBE %.2f %s" % r)
    raise SystemExit


if os.environ.get("PROBE12"):
    import itertools
    rows = []
    for yaw, lean, wy, wb, wr, ax, ay, az, roll in itertools.product(
            (30, 38), (-4, 0), (-28, -36), (-2, 5), (-18,), (0.5,), (-1.1, -1.25), (-1.3, -1.45), (10, 16)):
        BODY.update(yaw=yaw, lean=lean, wy=wy, wb=wb, wr=wr)
        AIM[:] = (ax, ay, az)
        AIM_ROLL = roll
        worst_r, worst_l, gaps, hand = 0.0, 0.0, [], None
        for p in (0.0, 0.3, 0.45, 0.7):
            inf = charge(p, 0.0)
            worst_r = max(worst_r, inf["arm_overreach"])
            worst_l = max(worst_l, inf["left"][0])
            gaps.append(inf["gap"])
            if p == 0.3:
                hand = L.hand_cf("Left").translation.copy()
                hb = [b for b in L.body_boxes() if b[0] == "Head"][0]
                hz0 = min((hb[1] @ Vector((sx * hb[2].x, 0, sz * hb[2].z))).z for sx in (-1, 1) for sz in (-1, 1))
                handgap = hz0 - hand.z - 0.25
                spot = L.launcher_point(TOPBAR)
        score = min(gaps) + 0.5 * handgap - 2.0 * worst_r - 2.0 * worst_l
        rows.append((score, "body %s aim(%.2f,%.2f,%.2f) roll%d | over=%.2f left=%.2f gap=%.2f handgap=%.2f hand=(%.2f,%.2f,%.2f) spot=(%.2f,%.2f,%.2f)" % (
            dict(BODY), ax, ay, az, roll, worst_r, worst_l, min(gaps), handgap, hand.x, hand.y, hand.z, spot.x, spot.y, spot.z)))
    rows.sort(key=lambda r: -r[0])
    for r in rows[:25]:
        print("REPORT_PROBE %.2f %s" % (r[0], r[1]))
    raise SystemExit


PREV = [None]


def keyc(frame):
    """key with quaternion hemisphere continuity (the gun spin passes 180 deg)"""
    r = L.rig()
    if PREV[0] is not None:
        for pb in r.pose.bones:
            q = pb.rotation_quaternion
            if q.dot(PREV[0][pb.name]) < 0.0:
                pb.rotation_quaternion = -q
    PREV[0] = {pb.name: pb.rotation_quaternion.copy() for pb in r.pose.bones}
    L.key(frame)


def clip(kind):
    PREV[0] = None
    L.new_clip(kind)


# ------------------------------------------------------------------ clips
ready(0.0, 0.0, 0.0)
READY_Q[0] = L.get_rot("Launcher")
clip("Ready")
n = 72
for i in range(0, 9):
    t = i / 8.0
    b = 0.5 - 0.5 * math.cos(2 * math.pi * t * 2)   # two breaths per loop
    s = math.sin(2 * math.pi * t)                    # one slow sway
    c = math.sin(2 * math.pi * t * 2 + 1.2) if i < 8 else math.sin(1.2)
    report["ready%d" % i] = ready(b, s, c)
    keyc(int(round(t * n)))
L.make_cyclic("Ready")

# two fans per 0.8 s loop; Lo and Hi share the exact phase timing.  Keys every 2 frames so the
# Hi gun can tremble (alternating +/- elev/yaw) on the same keys the Lo uses calmly.
FAN_P = {0: 0.0, 2: 0.15, 4: 0.3, 6: 0.45, 8: 0.7, 10: 0.85, 12: 1.0}
FAN_KEYS = [(fr, FAN_P[fr % 12] if fr % 12 or fr == 0 else 1.0) for fr in range(0, 25, 2)]
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    clip(kind)
    for fr, p in FAN_KEYS:
        pp = p % 1.0
        slap = abs(pp - 0.45) < 1e-3
        kick = (1.0 if slap else 0.0) * (0.35 + 0.65 * depth)
        shake = depth * (1.0 if (fr // 2) % 2 else -1.0) if fr not in (0, 12, 24) else 0.0
        bounce = 0.08 * depth if slap else 0.0
        report["%s_%d" % (kind, fr)] = charge(pp, depth, kick, shake, bounce)
        keyc(fr)
    L.make_cyclic(kind)
# the Hi chop snaps down (linear downstroke), the Lo stays soft
L.set_interpolation("ChargeHi", 'LINEAR', 'AUTO_CLAMPED', frames=[4, 6, 16, 18])

# ------------------------------------------------------------------ Fire
clip("Fire")
charge(0.3, 1.0); keyc(0)                                   # 0.00 = ChargeHi wind-up
# 0.07 last slap on the hammer, body sets
report["slap"] = charge(0.45, 1.0, kick=0.2, bounce=0.05); keyc(2)
FA = FAN_A[0] + FAN_A[1]
W_SLAP = L.joint("LeftHand").copy()
HR_SLAP = L.frame_of("LeftHand").to_quaternion()
LEFT_OFF = Vector((-0.2, -0.55, -1.55))                  # left hand flung down/out in front, off the gun


def left_off(u):
    """left hand sweeping off the gun after the last slap (u 0..1), away from the head"""
    w = W_SLAP.lerp(LEFT_OFF, u)
    w.z -= 0.3 * math.sin(math.pi * u)                     # arcs out to the front, away from the head
    L.arm_to("Left", w, elbow_away=(-1.0, -0.6, 0.0))
    # the palm unrolls gradually from the slap orientation to a straight wrist (no hand snap)
    nat = L.frame_of("LeftLowerArm").to_quaternion()
    a = HR_SLAP.copy()
    if a.dot(nat) < 0:
        a = -a
    return L.arm_to("Left", w, elbow_away=(-1.0, -0.6, 0.0), hand_rot=a.slerp(nat, L.smooth(u)))


# 0.13 SHOT (FireAt): gun dead level down the track, left hand already sweeping off
aim_body(1.0, 0.6)
report["shot"] = aim_gun(1.0, yaw=0.0, elev=5.0)
report["shot_left"] = left_off(0.6)
aim_head(); keyc(4)

# KICK (0.23) + hang (0.30): wrist snaps up, the body rocks back; then the gun SPINS about the
# trigger finger in the pad camera's screen plane, continuing the kick's upward turn
# (front -> up -> back -> down -> front) while the arm carries it out to the front-right.
KICK_AT = Vector((AIM.x + 0.15, AIM.y + 0.35, AIM.z + 0.3))   # kept 0.2+ inside reach (no elbow flip)
SPIN_AT = Vector((2.0, 1.25, -1.5))
KICK_ELEV = 38.0
SPIN_FRAMES = [9, 11, 13, 14, 15, 16, 17, 19, 21]           # [0] = the hang; 45 deg per step, eased ends
FINGER = Vector((0.0, -0.35, -0.75))  # trigger guard (pivot frame, template scale): the twirl axis


def pin_to(c, target, loc, w=1.0):
    """moves the Launcher bone so launcher point c lands on target (w = how much, 0..1)"""
    p0 = L.launcher_point(c)
    J = []
    for i in range(3):
        d = loc.copy()
        d[i] += 0.1
        L.set_loc("Launcher", tuple(d))
        L.update()
        J.append((L.launcher_point(c) - p0) / 0.1)
    from mathutils import Matrix
    M = Matrix((J[0], J[1], J[2])).transposed()
    step = M.inverted() @ (Vector(target) - p0)
    L.set_loc("Launcher", tuple(loc + step * w))
    L.update()


EA_KICK = Vector(AIM_POLE[0])         # same UP-ish pole as the aim: the elbow stays down at the side
EA_SPIN = Vector((-0.6, 0.8, 0.3))    # elbow out right + down, arm extended to the front-right


def spin_pose(k, ang=None, rock=0.0):
    """k = spin key index (0 = the kick); ang overrides SPIN_ANG[k]; rock 0..1 = recoil lean-back"""
    u = L.smooth(min(1.0, k / 2.5))                          # arm travel kick -> spin spot
    body(yaw=18.0 - 8.0 * u + 4.0 * rock, lean=-2.0 - 2.0 * u + 7.0 * rock, drop=0.52 - 0.27 * u - 0.06 * rock,
         back=0.2 - 0.12 * u + 0.06 * rock, side=0.04,
         waist_yaw=-12.0 + 2.0 * u - 4.0 * rock, waist_bend=3.0 - 5.0 * u + 6.0 * rock, waist_roll=-4.0 + 2.0 * u)
    bob = 0.06 * math.sin(math.pi * k / 4.0) * u
    at = KICK_AT.lerp(SPIN_AT, u) + Vector((0.0, bob, 0.0))
    yaw = 4.0 + 86.0 * L.smooth(min(1.0, k / 2.0))
    ea = EA_KICK.lerp(EA_SPIN, u)          # NB the elbow bows AWAY from elbow_away
    info = H(tuple(at), yaw=yaw, elev=0.0, roll=AIM_ROLL * (1.0 - u), elbow_away=tuple(ea))
    base = L.get_rot("Launcher")
    # launcher bone local X = the gun's side axis: turn in the gun's own plane, beside the finger
    loc = Vector((0.38 * u, 0.0, 0.0))
    L.set_loc("Launcher", tuple(loc))
    L.update()
    pin = L.launcher_point(FINGER)                           # the trigger guard stays on the finger
    L.set_rot("Launcher", base @ L.rx(SPIN_ANG[k] if ang is None else ang))
    L.update()
    pin_to(FINGER, pin, loc, u)
    if k == 0:
        left_off(1.0)
    else:
        # the flung left hand settles to the side: wrist AND pole blend (no pole switch = no snap)
        w = L.smooth(min(1.0, k / 3.0))
        T = L.frame_of("UpperTorso")
        sh = L.joint("LeftUpperArm")
        free_w = sh + T @ Vector((-0.34, -1.5, 0.02))
        L.arm_to("Left", LEFT_OFF.lerp(free_w, w), elbow_away=Vector((-1.0, -0.6, 0.0)).lerp(T @ Vector((-0.2, 0.0, 1.0)), w))
    # the eyes follow the shot down the track, then turn to watch the twirl (angles blended, not
    # the target point: a target sweeping past the head whips the neck around)
    hw = L.smooth(min(1.0, k / 4.0))
    y0, p0 = L.head_look(target=(-10.0, 1.5, -1.8))
    y1, p1 = L.head_look(target=(1.2, 1.8, -3.0))
    L.head_look(yaw=y0 + (y1 - y0) * hw, pitch=p0 + (p1 - p0) * hw)
    return info


# 0.23 KICK peak (its own beat): the wrist snaps the muzzle up ~50 deg, the body rocks back
report["kick"] = spin_pose(0, ang=52.0, rock=1.0); keyc(7)
# 0.30 the kick hangs a moment (muzzle settles a touch) ...
report["hang"] = spin_pose(0, ang=44.0, rock=0.6); keyc(9)
# ... then the gun SPINS: one full turn from the hang to 370, 45 deg steps, the last two easing out
SPIN_ANG = [44.0, 83.0, 128.0, 173.0, 218.0, 263.0, 308.0, 345.0, 370.0]
for k, fr in enumerate(SPIN_FRAMES):
    if k == 0:
        continue
    info = spin_pose(k)
    report["spin%d" % k] = info
    keyc(fr)
SPIN_END = SPIN_FRAMES[-1]

# 0.73 caught: the arm lowers with the gun level out front (plain grip again, no spin offset)
body(yaw=11.0, lean=-4.0, drop=0.24, back=0.06, waist_yaw=-8.0, waist_bend=-2.5, waist_roll=-1.0)
report["catch"] = H((1.75, 0.2, -1.25), yaw=90.0, elev=-2.0, elbow_away=tuple(EA_SPIN))
free_left(swing=-0.05, out=0.08)
L.head_look(target=(-2.0, 0.8, -3.0)); keyc(25)
# 0.90 the gun drops into the hip hold
body(yaw=12.0, lean=-3.0, drop=0.22, back=0.05, waist_yaw=-6.0, waist_bend=-3.0)
report["holster"] = H((1.35, -0.8, -0.75), yaw=92.0, elev=-22.0, elbow_away=(0.6, -0.3, 1.0))
free_left(swing=0.0, out=0.05)
L.head_look(target=(-8.0, 0.5, -3.0)); keyc(30)
ready(0.0, 0.0, 0.0); keyc(36)                             # 1.20 = Ready
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
L.set_interpolation("Fire", 'LINEAR', 'AUTO_CLAMPED', frames=SPIN_FRAMES[2:-1])

for k, v in report.items():
    print("REPORT_POSE %s %s" % (k, json.dumps(v, default=str)))


def detail(kind, length):
    """per-frame worst arm / launcher depth inside the torso/head (the audit's boxes)"""
    L.use_clip(kind)
    lob = L.launcher_object()
    verts = [v.co.copy() for v in lob.data.vertices]
    verts = verts[::max(1, len(verts) // 120)]
    rows = []
    for fi in range(0, int(round(length * L.FPS)) + 1):
        L.goto(fi / L.FPS)
        boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
        wa, wat = 0.0, ""
        for arm in L.AUDIT_ARMS:
            ab, ah = boxes[arm]
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    for k in (-1, 0, 1):
                        pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                        for bd in ("UpperTorso", "Head", "LowerTorso"):
                            d = L._depth_inside(pt, *boxes[bd])
                            if d > wa:
                                wa, wat = d, arm + ">" + bd
        wl, wlt = 0.0, ""
        mw = lob.matrix_world
        for co in verts:
            pt = L.b2r(mw @ co)
            for bd in ("UpperTorso", "Head"):
                d = L._depth_inside(pt, *boxes[bd])
                if d > wl:
                    wl, wlt = d, bd
        if wa > 0.1 or wl > 0.08:
            rows.append("%d:%.2f %s|L%.2f %s" % (fi, wa, wat, wl, wlt))
    print("REPORT_DETAIL %s %s" % (kind, "  ".join(rows)))


if os.environ.get("FAST12"):
    for kind in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
        detail(kind, SPEC[kind])
    rep = L.check(SPEC)
    for k in ("problems", "warnings", "fire_yaw_off_track_deg", "fire_elevation_deg", "ball_body_clearance",
              "flight_clearance", "fire_muzzle_pos"):
        print("REPORT_FAST %s %s" % (k, rep.get(k)))
    for kind in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
        print("REPORT_FAST %s %s" % (kind, rep.get(kind + "_audit")))
    raise SystemExit
L.finish(SPEC, OUT, extra_times=[0.067, 0.233, 0.3, 0.37, 0.43, 0.5, 0.57, 0.63, 0.83, 1.0])