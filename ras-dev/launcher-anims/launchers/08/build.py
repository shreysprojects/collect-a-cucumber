"""08 Snow Crossbow.

Concept: a blue crossbow with a bolt rail and a pistol grip.
  Ready    carried low at the right hip: the grip at the hip, the nose angled down and forward,
           the top rolled out so the stock rides along the right flank (well under the chin),
           left hand under the fore-end; easy breathing and a small weight shift.
  ChargeLo shoulder it: the butt in the right shoulder pocket, the chest turned toward the track,
           the head down on the stock looking along the rail; the snowball loaded on the rail;
           slow breathing sway of the aim.
  ChargeHi the same aim from a deeper, tighter stance (the crossbow comes down with the body so
           the cheek weld holds), elbows tucked, breath held: a fine tremor.
  Fire     head dips onto the stock + squeeze -> the string snaps: the ball shoots off the rail
           (flat), the stock drives INTO the shoulder and the muzzle climbs about that contact,
           the shoulder and chest rock back, settle, then lower to the hip.
Ball: on the rail (Seat) while charging, leaves from the Seat.
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

LID = 8
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.3,
    "FireAt": 0.13,
    "Ball": {"show": "Charge", "start": "Seat", "grow": 1.0},
    "Fx": {"Style": "snow", "Color": [0.85, 0.93, 1.0], "Charge": "snow", "ChargeColor": [0.72, 0.86, 1.0]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "crossbow: low angled hip carry, shouldered with the head on the stock aiming down the rail, deeper still crouch with a fine tremor, string snap + kick about the shoulder",
}
FEET = {"Left": (-0.9, -0.25), "Right": (0.6, 0.4)}
GT = Quaternion((-0.5667, -0.784, 0.25, 0.0419)).normalized()   # fixed pistol-grip turn in the hand

# launcher points in the PIVOT frame (studs, 1.5x scale): forward -Y, top -Z
BUTT = Vector((0.0, 1.55, -0.75))       # centre of the butt plate's back face
RAIL = Vector((0.0, 0.0, -1.73))        # a point on the rail top (the rail runs along -Y)
RAIL_BACK = Vector((0.0, 0.4, -1.73))   # rear end of the rail top (nearest the body)

# ---- shouldered aim (tuned by the S08=aim search)
POCKET = Vector((0.28, -0.12, -0.36))   # butt contact (out on the deltoid, 0.15+ inside both arms' reach: S08=aim2): offset from the right shoulder joint, UpperTorso frame
AIM_ELBOW = (0.0, 1.0, 0.3)
AIM_LEFT = (0.3, 1.0, 0.1)
ROLL = -22.0
HEAD_ROLL = -2.0
DIP_LO, DIP_HI, PK_DROP, TREM_E = 0.0, 4.0, 0.03, 1.8  # head pitch (+ = up) at Lo / Hi, pocket drop at Hi
AIMB = dict(yaw=48.0, lean=-12.0, drop=0.3, back=-0.15, waist_yaw=-12.0, waist_bend=-8.0, waist_tilt=-12.0)
DEEP = dict(yaw=2.0, lean=-2.0, drop=0.45, back=-0.05, waist_yaw=0.0, waist_bend=-6.0, waist_tilt=0.0)

# ---- low hip carry (tuned by the S08=ready search)
READY_BODY = dict(yaw=-12.0, lean=-6.0, drop=0.15, back=0.05, waist_yaw=0.0, waist_bend=-5.0)
READY_AT = (0.6, -1.15, -0.55)
READY_YAW, READY_ELEV, READY_ROLL = 30.0, -22.0, 20.0
READY_ELBOW = (-0.3, 1.0, 0.0)
READY_LEFT = (0.3, 1.0, 0.1)

report = {}
_prev = {}
_VERTS = []


def new_clip(kind):
    _prev.clear()
    L.new_clip(kind)


def K(f):
    """key with every quaternion kept in the previous key's hemisphere (no long-way-round flips)"""
    for pb in L.rig().pose.bones:
        q = pb.rotation_quaternion.copy()
        p = _prev.get(pb.name)
        if p is not None and q.dot(p) < 0.0:
            q = -q
            pb.rotation_quaternion = q
        _prev[pb.name] = q
    L.key(f)
    if os.environ.get("V08") == "1":
        print("REPORT key %s f%d %s" % (L.rig().animation_data.action.name[-8:], f, fmt(pose_stats({"arm_overreach": 0.0}))))


def body(yaw, lean, drop, back=0.1, side=0.0, waist_yaw=0.0, waist_bend=0.0, waist_tilt=0.0):
    L.reset_pose()
    legs = L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_tilt))
    return legs


def mix(a, b, t):
    """body kwargs a + t * b (b = deltas)"""
    out = dict(a)
    for k, v in b.items():
        out[k] = out.get(k, 0.0) + t * v
    return out


# ------------------------------------------------------------------ measuring
def audit_parts():
    """current pose: worst depth of the right arm / left arm in the body, launcher in the torso / head"""
    L.update()
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    inv = {n: (boxes[n][0].inverted(), boxes[n][1]) for n in ("UpperTorso", "Head", "LowerTorso")}

    def dep(p, n):
        bi, h = inv[n]
        q = bi @ p
        dx, dy, dz = h.x - abs(q.x), h.y - abs(q.y), h.z - abs(q.z)
        return min(dx, dy, dz) if (dx > 0 and dy > 0 and dz > 0) else 0.0
    out = {"R": 0.0, "L": 0.0, "LT": 0.0, "LH": 0.0}
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        key = "R" if arm.startswith("Right") else "L"
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for bd in ("UpperTorso", "Head", "LowerTorso"):
                        out[key] = max(out[key], dep(pt, bd))
    lob = L.launcher_object()
    if not _VERTS:
        vs = [v.co.copy() for v in lob.data.vertices]
        _VERTS.extend(vs[::max(1, len(vs) // 400)])
    mw = lob.matrix_world
    top = -9.0
    for co in _VERTS:
        pt = L.b2r(mw @ co)
        top = max(top, pt.y)
        out["LT"] = max(out["LT"], dep(pt, "UpperTorso"))
        out["LH"] = max(out["LH"], dep(pt, "Head"))
    out["top"] = top
    return out


def head_centre():
    return L.joint("Head") + L.frame_of("Head") @ Vector((0.0, 0.6, 0.0))


def eye_point():
    return L.joint("Head") + L.frame_of("Head") @ Vector((0.0, 0.7, -0.45))


def rail_dist(p):
    pv = L.pivot_cf()
    a = pv @ RAIL
    d = (pv.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized()
    v = p - a
    return (v - d * v.dot(d)).length


def pose_stats(info):
    a = audit_parts()
    G2 = L.load_meta(LID)["Grip2"]["pos"]
    sp = L.launcher_point(L.load_meta(LID)["Seat"]["pos"])
    pv = L.pivot_cf()
    fwd = (pv.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized()
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    a["gap"] = (L.hand_cf("Left").translation - L.launcher_point(G2)).length
    a["ov"] = max(info.get("arm_overreach", 0.0), (info.get("left") or (0.0,))[0])
    a["w"] = math.degrees(sw.angle)
    a["bh"] = (sp - head_centre()).length
    a["bs"] = (pv @ BUTT - L.joint("RightUpperArm")).length
    a["ey"] = rail_dist(eye_point())
    a["hr"] = rail_dist(head_centre())
    a["rz"] = (pv @ RAIL).z
    a["rb"] = (pv @ RAIL_BACK).y
    a["chin"] = head_centre().y - 0.6
    a["nose"] = math.degrees(math.asin(max(-1.0, min(1.0, fwd.y))))
    for s in ("Right", "Left"):
        a["m" + s[0]] = REACH - (L.joint(s + "Hand") - L.joint(s + "UpperArm")).length
        a["b" + s[0]] = math.degrees(L.get_rot(s + "LowerArm").angle)
    return a


REACH = math.sqrt(L.ARM_SIDE_OFFSET ** 2 + (L.UPPER_ARM + L.LOWER_ARM) ** 2)


def fmt(a):
    return ("mR%.2f mL%.2f bR%.0f bL%.0f R%.2f L%.2f LT%.2f LH%.2f gap%.2f ov%.2f w%.0f bh%.2f bs%.2f ey%.2f hr%.2f rz%.2f rb%.2f chin%.2f nose%.0f top%.2f" %
            (a["mR"], a["mL"], a["bR"], a["bL"], a["R"], a["L"], a["LT"], a["LH"], a["gap"], a["ov"], a["w"], a["bh"], a["bs"], a["ey"], a["hr"], a["rz"],
             a["rb"], a["chin"], a["nose"], a["top"]))


# ------------------------------------------------------------------ poses
def aim_head(roll=None, dip=0.0, turn=0.0):
    """look along the rail (sight line just above it), head tilted over onto the stock"""
    pv = L.pivot_cf()
    fwd = (pv.to_3x3() @ Vector((0.0, -1.0, 0.0))).normalized()
    tgt = pv @ RAIL + fwd * 14.0 + Vector((0.0, 0.3, 0.0))
    L.head_look(target=tuple(tgt))
    L.set_rot("Head", L.get_rot("Head") @ L.ry(turn) @ L.rz(HEAD_ROLL if roll is None else roll) @ L.rx(dip))
    L.update()


def shoulder(kw, elev=2.0, yaw=0.0, roll=None, pocket=None, push=0.0, lift=0.0, relbow=None, lelbow=None,
             head_roll=None, dip=0.0, turn=0.0):
    """shouldered crossbow: the butt plate at the pocket of the right shoulder (UpperTorso frame),
    the rail along direction(yaw, elev); push > 0 drives the butt INTO the shoulder"""
    legs = body(**kw)
    want = L.joint("RightUpperArm") + L.frame_of("UpperTorso") @ (pocket if pocket is not None else POCKET)
    want = want - L.direction(yaw, elev) * push + Vector((0.0, lift, 0.0))
    p = want.copy()
    info = {}
    for _ in range(3):
        info = L.hold(tuple(p), yaw=yaw, elev=elev, roll=ROLL if roll is None else roll, anchor="Pivot",
                      elbow_away=relbow or AIM_ELBOW, grip_twist=GT)
        p = p + (want - L.pivot_cf() @ BUTT)
    info["butt_err"] = round((want - L.pivot_cf() @ BUTT).length, 3)
    info["left"] = L.left_hand_to(key="Grip2", elbow_away=lelbow or AIM_LEFT)
    info["legs"] = legs
    aim_head(head_roll, dip, turn)
    return info


def carry(b=0.0, s=0.0, at=None, yaw=None, elev=None, roll=None, bkw=None, relbow=None, lelbow=None):
    """low hip carry: b breathing 0..1, s weight shift -1..1"""
    kw = dict(bkw or READY_BODY)
    kw["yaw"] += 3.0 * s
    kw["lean"] -= 2.0 * b
    kw["drop"] += 0.05 * b
    kw["side"] = kw.get("side", 0.0) + 0.06 * s
    kw["waist_bend"] -= 1.5 * b
    legs = body(**kw)
    a = at or READY_AT
    info = L.hold((a[0] + 0.02 * s, a[1] - 0.04 * b, a[2]), yaw=(READY_YAW if yaw is None else yaw) + 2.0 * s,
                  elev=(READY_ELEV if elev is None else elev) - 1.5 * b, roll=READY_ROLL if roll is None else roll,
                  elbow_away=relbow or READY_ELBOW, grip_twist=GT)
    info["left"] = L.left_hand_to(key="Grip2", elbow_away=lelbow or READY_LEFT)
    info["legs"] = legs
    L.head_look(target=(-6.0, -1.0 + 0.3 * b, -3.0))
    return info


# ------------------------------------------------------------------ searches (S08=aim / ready)
if os.environ.get("S08") == "ready":
    import itertools
    L.new_clip("Search")
    LEFTS = ((0.3, 1.0, 0.1), (0.5, 1.0, 0.4))
    RIGHTS = ((-0.3, 1.0, 0.0), (0.3, 1.0, 0.3))
    res = []
    for by, px, py, pz, el, yw, rl in itertools.product((-12.0, -4.0, 4.0), (0.5, 0.6), (-1.05, -1.15), (-0.45, -0.55),
                                                        (-22.0, -28.0), (30.0, 38.0, 45.0), (10.0, 20.0, 30.0)):
        bk = dict(READY_BODY, yaw=by)
        best = None
        for ri, re_ in enumerate(RIGHTS):
            for li, le in enumerate(LEFTS):
                worst, wa = -1.0, None
                for b, s_ in ((0.0, 0.0), (1.0, 1.0), (0.5, -1.0)):
                    info = carry(b, s_, at=(px, py, pz), yaw=yw, elev=el, roll=rl, bkw=bk, relbow=re_, lelbow=le)
                    a = pose_stats(info)
                    sc = max((0.2 - a["mR"]) / 0.05, (0.2 - a["mL"]) / 0.05, a["R"] / 0.15, a["L"] / 0.15,
                             a["LT"] / 0.05, a["LH"] / 0.05, a["gap"] / 0.12,
                             (a["w"] - 55.0) / 10.0 if a["w"] > 55 else 0.0,
                             (a["rb"] - 0.5) / 0.15 if a["rb"] > 0.5 else 0.0, (a["top"] - 0.8) / 0.2 if a["top"] > 0.8 else 0.0)
                    if sc > worst:
                        worst, wa = sc, a
                if best is None or worst < best[0]:
                    best = (worst, ri, li, wa)
        sc, ri, li, a = best
        res.append((sc, "by%g p(%g,%g,%g) el%g yw%g rl%g ri%d li%d | %s" % (by, px, py, pz, el, yw, rl, ri, li, fmt(a))))
    res.sort(key=lambda r: r[0])
    for sc, line in res[:25]:
        print("REPORT S %.2f %s" % (sc, line))
    raise SystemExit

if os.environ.get("S08") == "aim":
    import itertools
    L.new_clip("Search")
    RIGHTS = ((-0.6, 0.6, 0.4), (0.0, 1.0, 0.3))
    LEFTS = ((0.3, 1.0, 0.1), (0.5, 1.0, 0.4))
    res = []
    for ry_, wy, ln, wt, pz, py, px, rl, hr in itertools.product((45.0, 50.0, 55.0), (-8.0, -12.0), (-10.0, -13.0), (-8.0, -3.0),
                                                              (-0.35, -0.42), (-0.1, -0.2), (0.0, 0.08), (-15.0, -6.0, 0.0), (-10.0, -16.0)):
        kw = dict(AIMB, yaw=ry_, waist_yaw=wy, lean=ln, waist_tilt=wt)
        HEAD_ROLL = hr
        best = None
        for ri, re_ in enumerate(RIGHTS):
            for li, le in enumerate(LEFTS):
                info = shoulder(kw, pocket=Vector((px, py, pz)), roll=rl, relbow=re_, lelbow=le)
                a = pose_stats(info)
                sc = max(a["R"] / 0.15, a["L"] / 0.15, a["LT"] / 0.15, a["LH"] / 0.12, a["gap"] / 0.12,
                         a["ov"] / 0.02 if a["ov"] > 0.005 else 0.0, info["butt_err"] / 0.05,
                         (a["w"] - 55.0) / 10.0 if a["w"] > 55 else 0.0, a["bs"] / 0.4,
                         a["ey"] / 0.55,(abs(a["rz"] + 1.45) - 0.2) / 0.1 if abs(a["rz"] + 1.45) > 0.2 else 0.0,
                         (1.6 - a["bh"]) / 0.2 if a["bh"] < 1.6 else 0.0)
                if best is None or sc < best[0]:
                    best = (sc, ri, li, a)
        sc, ri, li, a = best
        res.append((sc, "ry%g wy%g ln%g wt%g pk(%g,%g,%g) rl%g hr%g ri%d li%d | %s" % (ry_, wy, ln, wt, px, py, pz, rl, hr, ri, li, fmt(a))))
    res.sort(key=lambda r: r[0])
    for sc, line in res[:30]:
        print("REPORT S %.2f %s" % (sc, line))
    raise SystemExit


# ------------------------------------------------------------------ Ready (low hip carry)
new_clip("Ready")
N = int(round(SPEC["Ready"] * 30))
for f in range(0, N, 9):
    ph = f / N
    b = 0.5 - 0.5 * math.cos(2.0 * math.pi * 2.0 * ph)
    s = math.sin(2.0 * math.pi * ph)
    report["ready_%d" % f] = carry(b, s)
    K(f)
carry(0.0, 0.0); K(N)
L.make_cyclic("Ready")

# ------------------------------------------------------------------ charge loops (same keys, same phase)
NC = int(round(SPEC["ChargeLo"] * 30))
TUCK_R = (0.35, 1.0, 0.1)       # ChargeHi: the right elbow pulled in under the crossbow
TUCK_L = (0.55, 1.0, 0.25)      # ChargeHi: the left elbow tucked under the fore-end


def tremor(f):
    """fine shake, periodic over NC frames (integer cycles, 4-5 per loop); values ~ -1..1"""
    u = f / NC
    e = 0.65 * math.sin(2.0 * math.pi * 5.0 * u + 0.4) + 0.35 * math.sin(2.0 * math.pi * 4.0 * u + 2.1)
    w = 0.6 * math.cos(2.0 * math.pi * 4.0 * u + 1.3) + 0.4 * math.sin(2.0 * math.pi * 5.0 * u + 0.2)
    return e, w


def lerp3(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def charge_pose(depth, f):
    """depth 0 = ChargeLo, 1 = ChargeHi at loop frame f"""
    ph = f / NC
    amp = 1.0 - 0.7 * depth                      # breath held at full charge: the big sway calms down
    b = amp * (0.5 - 0.5 * math.cos(2.0 * math.pi * ph))
    s = amp * math.sin(2.0 * math.pi * ph)
    te, tw = tremor(f)
    kw = mix(AIMB, DEEP, depth)
    kw = mix(kw, dict(drop=-0.045, waist_bend=2.5), b)          # inhale: the chest lifts
    kw = mix(kw, dict(yaw=1.2, waist_yaw=0.5), s)
    info = shoulder(kw, elev=2.0 - 0.75 * amp + 1.5 * b + TREM_E * depth * te, yaw=-1.5 * s + 1.4 * depth * tw, pocket=pocket_at(depth),
                    relbow=lerp3(AIM_ELBOW, TUCK_R, depth), lelbow=lerp3(AIM_LEFT, TUCK_L, depth),
                    dip=DIP_LO + (DIP_HI - DIP_LO) * depth, turn=0.6 * depth * tw)
    return info


def pocket_at(depth):
    """ChargeHi seats the butt a touch lower so the head stays ON the stock, not in it"""
    return Vector((POCKET.x, POCKET.y - PK_DROP * depth, POCKET.z))


if os.environ.get("S08") == "aim2":
    # reach search: both arms >= 0.15 inside full reach on the Lo exhale / inhale / sway and the Hi pose
    import itertools
    L.new_clip("Search")
    RIGHTS = ((0.0, 1.0, 0.3), (0.35, 1.0, 0.4))
    res = []
    P0 = Vector(POCKET)
    A0 = dict(AIMB)
    for px, pz, py, rl, wy, ry_, hr, wt in itertools.product((0.24, 0.28, 0.32), (-0.36, -0.39, -0.42), (-0.12, -0.16),
                                                         (-22.0, -26.0), (-12.0,), (45.0, 48.0), (-2.0,), (-12.0, -15.0)):
        POCKET = Vector((px, py, pz))
        ROLL = rl
        HEAD_ROLL = hr
        AIMB = dict(A0, waist_yaw=wy, yaw=ry_, waist_tilt=wt)
        best = None
        for ri, re_ in enumerate(RIGHTS):
            AIM_ELBOW = re_
            worst, worst_a = -1.0, None
            for depth, f in ((0.0, 0), (0.0, NC // 2), (0.0, NC // 4), (1.0, 0)):
                info = charge_pose(depth, f)
                a = pose_stats(info)
                sc = max((0.2 - a["mR"]) / 0.05, (0.2 - a["mL"]) / 0.05, a["R"] / 0.15, a["L"] / 0.15,
                         a["LT"] / 0.1, a["LH"] / 0.1, a["gap"] / 0.12, info["butt_err"] / 0.05,
                         (a["w"] - 55.0) / 10.0 if a["w"] > 55 else 0.0, a["ey"] / 0.55,
                         (abs(a["rz"] + 1.45) - 0.3) / 0.1 if abs(a["rz"] + 1.45) > 0.3 else 0.0,
                         (1.6 - a["bh"]) / 0.2 if a["bh"] < 1.6 else 0.0)
                if sc > worst:
                    worst, worst_a = sc, a
            if best is None or worst < best[0]:
                best = (worst, ri, worst_a)
        sc, ri, a = best
        res.append((sc + 0.01 * abs(hr), "pk(%g,%g,%g) rl%g wy%g ry%g hr%g wt%g ri%d | %s" % (px, py, pz, rl, wy, ry_, hr, wt, ri, fmt(a))))
    res.sort(key=lambda r: r[0])
    for sc, line in res[:30]:
        print("REPORT S %.2f %s" % (sc, line))
    raise SystemExit

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    new_clip(kind)
    for f in range(NC):
        report["%s_%d" % (kind, f)] = charge_pose(depth, f)
        K(f)
    charge_pose(depth, 0); K(NC)
    L.make_cyclic(kind)

# ------------------------------------------------------------------ Fire
new_clip("Fire")
HI = mix(AIMB, DEEP, 1.0)
PK1 = pocket_at(1.0)
report["f0"] = charge_pose(1.0, 0); K(0)                                   # 0.00 the charge pose
# 0.07 squeeze: exhale and settle -- the hips sink, the head presses onto the stock, the muzzle dips a degree
sq = mix(HI, dict(drop=0.045, lean=-1.5), 1.0)
SQ_R = (0.5, 1.0, 0.05)
report["f2"] = shoulder(sq, elev=1.0, pocket=PK1, relbow=SQ_R, lelbow=TUCK_L, dip=0.5); K(2)
# 0.13 FIRE: the breath held at the bottom, the muzzle back on the line
sq2 = mix(HI, dict(drop=0.035, lean=-1.2), 1.0)
report["f4"] = shoulder(sq2, elev=2.0, pocket=PK1, relbow=SQ_R, lelbow=TUCK_L, dip=1.5); K(4)
report["pivot_at_fire"] = [round(v, 2) for v in L.pivot_cf().translation]
report["butt_at_fire"] = [round(v, 2) for v in L.pivot_cf() @ BUTT]
report["shoulder_at_fire"] = [round(v, 2) for v in L.joint("RightUpperArm")]
# 0.20 the string snaps: the stock slams INTO the shoulder, the right shoulder and chest start back
jolt = mix(HI, dict(side=0.05, lean=3.0, waist_yaw=-1.5, waist_bend=2.0, waist_tilt=1.5), 1.0)
report["jolt"] = shoulder(jolt, elev=7.0, push=0.08, pocket=POCKET + Vector((0.0, -0.06, 0.0)), relbow=SQ_R, lelbow=TUCK_L, dip=18.0, head_roll=6.0); K(6)
# 0.27 KICK: the muzzle climbs about the shoulder contact, the shoulder rocks back ~0.25, the head comes off the stock
kick = mix(HI, dict(side=0.1, lean=7.0, waist_yaw=-3.0, waist_bend=4.0, drop=-0.03, waist_tilt=3.0), 1.0)
report["kick"] = shoulder(kick, elev=14.0, push=0.1, pocket=POCKET + Vector((0.03, -0.14, 0.0)),
                          relbow=TUCK_R, lelbow=TUCK_L, dip=36.0, head_roll=16.0); K(8)
report["shoulder_at_kick"] = [round(v, 2) for v in L.joint("RightUpperArm")]
report["butt_at_kick"] = [round(v, 2) for v in L.pivot_cf() @ BUTT]
# 0.40 recover: muzzle back down, a little overshoot, the cheek back on the stock
rec = mix(HI, dict(back=0.05, lean=2.0, waist_bend=1.5, waist_tilt=1.0), 1.0)
report["recover"] = shoulder(rec, elev=0.5, pocket=PK1, relbow=TUCK_R, lelbow=TUCK_L, dip=6.0, head_roll=-2.0); K(12)
# 0.53 settle: still shouldered, the stance rising a little, following the ball down the track
setb = mix(AIMB, DEEP, 0.6)
report["settle"] = shoulder(setb, elev=4.0, pocket=pocket_at(0.6), relbow=lerp3(AIM_ELBOW, TUCK_R, 0.6), lelbow=AIM_LEFT,
                            dip=6.0, head_roll=-3.0); K(16)
S_SETTLE = L.snapshot()
# 0.83 dismount: the crossbow down off the shoulder to a low port in front of the body
report["dismount"] = carry(0.0, 0.0, at=(0.55, -1.05, -0.95), yaw=28.0, elev=-18.0, roll=10.0,
                           bkw=dict(READY_BODY, yaw=-6.0, lean=-8.0, drop=0.2), relbow=(-0.3, 1.0, 0.2), lelbow=(0.3, 1.0, 0.1))
L.head_look(target=(-9.0, -0.5, -2.0))
S_DIS = L.snapshot()
# 0.67 the head lifts off the stock, the butt slides off the shoulder, the nose starts down
lb = mix(mix(AIMB, DEEP, 0.24), dict(yaw=0.0, lean=1.8), 1.0)
report["lift"] = shoulder(lb, elev=-3.0, yaw=2.4, pocket=POCKET + Vector((0.12, -0.06, 0.06)), relbow=AIM_ELBOW, lelbow=AIM_LEFT,
                          dip=15.0, head_roll=8.0)
S_LIFT = L.snapshot()
if os.environ.get("S08") == "fire":
    import itertools

    def SC(a, top):
        return max((0.2 - a["mR"]) / 0.05, (0.2 - a["mL"]) / 0.05, a["R"] / 0.15, a["L"] / 0.15, a["LT"] / 0.1,
                   a["LH"] / 0.1, a["gap"] / 0.12, (a["top"] - top) / 0.2 if a["top"] > top else 0.0)
    res = []
    for dx, dy, dz, by, le in itertools.product((-0.05, 0.05, 0.12), (0.0, -0.06, -0.12), (0.06, 0.12, 0.18), (0.0, 4.0, 8.0), (-3.0, -8.0)):
        lb_ = mix(mix(AIMB, DEEP, 0.24), dict(yaw=by, lean=1.8), 1.0)
        info = shoulder(lb_, elev=le, yaw=2.4, pocket=POCKET + Vector((dx, dy, dz)), relbow=AIM_ELBOW, lelbow=AIM_LEFT, dip=15.0, head_roll=8.0)
        a = pose_stats(info)
        res.append((SC(a, 9.0), "LIFT d(%g,%g,%g) by%g le%g | %s" % (dx, dy, dz, by, le, fmt(a))))
    res.sort(key=lambda r: r[0])
    for sc, line in res[:10]:
        print("REPORT S %.2f %s" % (sc, line))
    res = []
    for px, py, pz, yw, el, rl, by, ri in itertools.product((0.45, 0.55), (-0.9, -1.05), (-0.8, -0.95, -1.1), (22.0, 28.0), (-18.0, -24.0),
                                                           (10.0, 20.0), (-6.0, 0.0, 6.0, 12.0), (0, 1)):
        info = carry(0.0, 0.0, at=(px, py, pz), yaw=yw, elev=el, roll=rl, bkw=dict(READY_BODY, yaw=by, lean=-8.0, drop=0.2),
                     relbow=((-0.3, 1.0, 0.2), (0.3, 1.0, 0.3))[ri], lelbow=(0.3, 1.0, 0.1))
        a = pose_stats(info)
        res.append((SC(a, 0.72), "DIS p(%g,%g,%g) yw%g el%g rl%g by%g ri%d | %s" % (px, py, pz, yw, el, rl, by, ri, fmt(a))))
    res.sort(key=lambda r: r[0])
    for sc, line in res[:10]:
        print("REPORT S %.2f %s" % (sc, line))
    raise SystemExit
carry(0.0, 0.0)
S_READY = L.snapshot()


def between(a, b, t, f, look, lelbow=(0.3, 1.0, 0.1)):
    L.restore(L.blend_snapshots(a, b, t))
    report["mid%d" % f] = L.left_hand_to(key="Grip2", elbow_away=lelbow)
    L.head_look(target=look)
    K(f)


between(S_SETTLE, S_LIFT, 0.5, 18, (-12.0, 2.0, -1.2))
L.restore(S_LIFT); K(20)
between(S_LIFT, S_DIS, 0.5, 23, (-10.0, 0.5, -1.8))
L.restore(S_DIS); K(26)
between(S_DIS, S_READY, 0.5, 32, (-7.0, -1.0, -2.5), READY_LEFT)
L.restore(S_READY); K(39)                                                 # 1.30 back to the hip carry
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
L.set_interpolation("Fire", 'LINEAR', 'AUTO_CLAMPED', frames=[4, 6])     # snap: no ease into the jolt

for k, v in report.items():
    if not k[-1].isdigit() or k.endswith("_0") or k in ("f0", "f2", "f4"):
        print("REPORT pose %s %s" % (k, v))
if os.environ.get("F08") == "1":
    L.use_clip("Fire")
    for f in range(0, 40):
        L.goto(f / 30.0)
        print("REPORT fire f%d %s" % (f, fmt(pose_stats({}))))
    raise SystemExit
L.finish(SPEC, OUT, extra_times=[0.07, 0.2, 0.27, 0.4, 0.53, 0.73, 0.87])
