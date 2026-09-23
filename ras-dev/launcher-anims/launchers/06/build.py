"""06 Steel Slingshot -- build script (polish round 2: ChargeHi crouches 0.44 deeper, leans back into the
draw, squares the shoulders (+9 deg twist) and lifts the drawing elbow out to screen-left; the aim line sits
further toward the character's front (fork targets z -1.6 / -1.65) and the head tilts away from the anchor
(HEAD roll 16 / 20 deg, chin up) so the pouch + ball read beside the head in the pad camera; ball kept off
the pouch line by 0.2 toward the front; the Fire squeeze dips the fork with the body and the drawing hand
springs up/out in front of the face instead of back through it).

Concept: the steel Y-frame slingshot held SIDEWAYS, 'gangster' style: the fork rolled ~80 deg so the
handle and the fist point to the character's FRONT (screen-right in the pad camera) and the fork sits
at chin height out in front, the fork arm LOCKED straight like a real slingshot shooter.  Wide
athletic stance, fast snappy draws.
  Ready    casual low hold: the slingshot hanging from the relaxed right hand at the thigh, the left
           hand bounces the ball in front of the belly (a big flip + a small one), breathing.
  ChargeLo body side-on to the track, the fork punched out on a straight arm, half draw (the ball
           0.55 studs behind the fork), upright; breathing sway + a faint tremor.
  ChargeHi same aim and rhythm, full draw (0.75 + 0.2 nudge, kept near the pouch), crouched much deeper,
           the shoulders squared into the draw, elbow up; 6 Hz tension tremor.
  Fire     last tug + dip -> release (FireAt) -> crisp snap: the fork kicks up (recoil flick), the
           left hand springs back open past the cheek, the torso rocks back -> a held beat -> a
           smooth settle (every in-between frame solved by IK) back to the low hold.
Ball: in the left hand (always visible), leaves from the hand through the fork at FireAt; the
runtime draws the bands from the fork tips (meta Bands) to it.

Geometry found with search.py (random search against the audit boxes, ball clearance and reach);
the ball (0.67 radius) must clear the head, so the fork arm is fully extended: its IK target is kept
beyond full reach on purpose (LOCK), so the elbow stays straight and can never flip.
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

LID = 6
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)
META = L.load_meta(LID)

BALL_OFF = [0.0, -0.9, 0.0]
SPEC = {
    "Ready": 2.0, "ChargeLo": 1.0, "ChargeHi": 1.0, "Fire": 1.3,
    "FireAt": 0.133,
    "Ball": {"show": "Always", "start": "Seat", "grow": 1.0, "hand": "Left", "offset": BALL_OFF},
    "Fx": {"Style": "snow", "Color": [0.85, 0.92, 1.0]},
    "TwoHanded": False,
    "AllowFootLift": False,
    "Notes": "steel slingshot held sideways gangster-style: locked fork arm, fork at chin height, snappy draw, crisp snap + recoil flick",
}
FEET = {"Left": (0.85, 0.6), "Right": (-0.75, -0.6)}
FOOT_YAW = {"Left": 110, "Right": 70}
report = {}

# charge geometry: half draw (Lo) and full draw (Hi)
P_LO = {"hy": 89.7, "wy": 20.9, "lean": 0.5, "drop": 0.46, "back": -0.77, "wbend": 4.8, "wroll": 5.4,
        "F": (-1.8, 1.58, -1.6), "roll": -80.0, "elev": 5.5, "yaw": 4.5, "d": 0.55, "hroll": 16.0,
        "lp": (-0.15, 1.0, -0.18), "lg": (0.3, 0.01, 0.53), "hup": 1.0}
P_HI = {"hy": 93.2, "wy": 30.0, "lean": 7.0, "drop": 0.9, "back": -0.77, "wbend": 8.5, "wroll": 5.4,
        "F": (-1.75, 1.36, -1.65), "roll": -80.0, "elev": 5.5, "yaw": 4.5, "d": 0.75, "hroll": 20.0,
        "lp": (-0.3, 1.0, -0.3), "lg": (0.3, 0.01, 0.53), "hup": 3.0}
RPOLE = (-0.08, 1.0, -0.64)       # fork arm pole (UP-ish; the arm is straight anyway)
LPOLE = P_LO["lp"]                # drawing arm pole (UP-ish = the elbow hangs down/out); Hi flares it
LGUESS = (0.3, 0.01, 0.53)        # drawing wrist start offset from the ball
BALL_SHIFT = (-0.08, -0.12, -0.2)      # full-draw ball nudge (keeps the drawing hand off the cheek)
CW_OFF = (-0.3, -0.5, -1.85)      # settle: right-wrist path bulge (in front of the body)
TQ_EASE = 2.0                     # settle: the launcher turns ahead of the arm (ease-out 1 - (1 - s) ** TQ_EASE)
LOCK = 0.12                      # fork IK target pushed this far past the arm's reach (straight arm)
SNAP_H = (-0.1, 0.8, -0.6)         # Fire: the drawing hand's spring-back at the snap extreme (from the release)
FOL_H = (-0.1, 0.4, -0.55)       # Fire: the drawing hand at the follow-through
SNAP_LP = (0.1, 1.0, -0.4)        # Fire: drawing-arm pole after the release
TUG = (0.14, 0.1)                 # Fire: extra draw at the last tug (0.07 s) and at the release
BOB = 0.15                        # charge loops: head bob (head-look target lift per breath)
# probe overrides


def dbg(tag, v):
    report[tag] = v
    print("REPORT_dbg", tag, v)


def lerp(a, b, t):
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def body(hy, wy, lean=-5.0, drop=0.35, back=0.0, wbend=-6.0, wroll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, root=L.ry(hy) @ L.rx(lean), feet=FEET, foot_yaw=FOOT_YAW)
    L.waist(L.ry(wy) @ L.rx(wbend) @ L.rz(wroll))


def ball_now():
    return (L.hand_cf("Left") @ L.cf(Vector(BALL_OFF))).translation


def hand_centre(side="Left"):
    return L.joint(side + "Hand") + L.frame_of(side + "Hand") @ Vector(L.HAND_CENTER)


def left_ball_to(B, elbow_away=LPOLE, guess=LGUESS):
    """left hand so the held ball lands on B"""
    B = Vector(B)
    H = B + Vector(guess)
    err = None
    for _ in range(12):
        err = L.left_hand_to(point=H, elbow_away=elbow_away)
        H = H + (B - ball_now())
    return {"left": err, "ball_err": round((ball_now() - B).length, 3)}


def pole_nx(side, wrist, pole):
    """hinge axis x in the UpperTorso frame (< -0.15 = the elbow guard mirrors the pole)"""
    Mi = L.frame_of("UpperTorso").inverted()
    t = (Mi @ (Vector(wrist) - L.joint(side + "UpperArm"))).normalized()
    n = t.cross(Mi @ Vector(pole))
    return round(n.normalized().x, 2) if n.length > 1e-6 else 0.0


def muzzle():
    """actual Muzzle point + look (world) of the launcher as posed"""
    m = L.pivot_cf() @ L._meta_frame(META, "Muzzle")
    return m.translation.copy(), (m.to_3x3() @ Vector((0.0, 0.0, -1.0))).normalized()


def locked(F):
    """push the fork target LOCK studs past the fork arm's reach (along shoulder -> fork)"""
    sh = L.joint("RightUpperArm")
    return Vector(F) + (Vector(F) - sh).normalized() * LOCK


REACH = math.sqrt(L.ARM_SIDE_OFFSET ** 2 + (L.UPPER_ARM + L.LOWER_ARM) ** 2)


def aim(F, yaw, elev, roll, grip=None, **kw):
    """fork (Muzzle) toward F on a LOCKED straight arm: the target is pushed out until the arm is straight"""
    T = locked(F)
    for _ in range(4):
        info = L.hold(T, yaw=yaw, elev=elev, roll=roll, anchor="Muzzle", elbow_away=RPOLE,
                      grip_twist=QG if grip is None else grip, **kw)
        D = (L.joint("RightHand") - L.joint("RightUpperArm")).length
        if D > REACH - 0.004:
            break
        T = T + (Vector(F) - L.joint("RightUpperArm")).normalized() * (REACH - D + 0.08)
    return info


def charge_params(c):
    return {k: lerp(P_LO[k], P_HI[k], c) for k in P_LO}


def _grip():
    p = charge_params(0.5)
    body(p["hy"], p["wy"], p["lean"], p["drop"], p["back"], p["wbend"], p["wroll"])
    dbg("grip", L.hold(locked(p["F"]), yaw=p["yaw"], elev=p["elev"], roll=p["roll"], anchor="Muzzle",
                       elbow_away=RPOLE, max_wrist=15.0))
    return L.get_rot("Launcher")


QG = _grip()


def draw(c, br=0.0, br2=0.0, trem=0.0, trem2=0.0, extra=0.0, dip=0.0):
    """c 0 = half draw (ChargeLo) .. 1 = full draw (ChargeHi); br/br2 -1..1 breathing (sin/cos);
    trem/trem2 -1..1 tremor (sin/cos, scaled here by the charge); extra = more pull; dip = anticipation"""
    p = charge_params(c)
    a = 0.25 + 0.75 * c
    body(p["hy"] + 2.5 * br, p["wy"] + 1.0 * br2 + 3.5 * dip, lean=p["lean"] - 1.2 * br2 - 3.0 * dip,
         drop=p["drop"] + 0.05 * br2 + 0.24 * dip, back=p["back"], wbend=p["wbend"] - 1.0 * br2 - 3.0 * dip,
         wroll=p["wroll"] + 2.0 * br2 + 0.8 * a * trem)
    F = Vector(p["F"]) + Vector((0.0, 0.04 * br2 + 0.03 * a * trem - 0.24 * dip, 0.02 * a * trem2))
    yaw = p["yaw"] + 1.0 * a * trem2
    elev = p["elev"] + 1.0 * br + 1.5 * a * trem - 3.0 * dip
    roll = p["roll"] + 1.5 * a * trem2
    info = aim(F, yaw, elev, roll)
    M, look = muzzle()
    d = p["d"] + 0.06 * br + extra
    B = M - look * d + Vector((0.0, 0.04 * a * trem2, -0.03 * a * trem)) + Vector(BALL_SHIFT) * c
    info.update(left_ball_to(B, elbow_away=p["lp"], guess=p["lg"]))
    info["nxL"] = pole_nx("Left", L.joint("LeftHand"), p["lp"])
    info["reachR"] = round((L.joint("RightHand") - L.joint("RightUpperArm")).length, 3)
    L.head_look(target=M + look * 10.0 + Vector((0.0, p["hup"] + BOB * br2, 0.0)))
    tilt(p["hroll"])
    return info


HEAD_TILT = [0.0]                 # the tilt capture() records (set before capturing)


def tilt(deg):
    """rolls the head away from the anchor (toward the character's left / screen-left)"""
    HEAD_TILT[0] = deg
    L.set_rot("Head", L.get_rot("Head") @ L.rz(deg))
    L.update()


# ------------------------------------------------------------------ ready (low hold at the thigh)
READY_HAND = (-20.0, -100.0)        # right wrist: bend (hand x) / twist (about the forearm) degrees
READY_WRIST = (0.95, -0.55, -0.45)
READY_RPOLE = (0.0, 1.0, 0.3)
READY_LPOLE = (0.3, 1.0, 0.1)


def ready(b=0.0, flip=0.0, sway=0.0):
    """b 0..1 breathing; flip how high the left hand tosses the ball (neg = the catch dip)"""
    body(70.0 + 2.0 * sway, -18.0 + 2.0 * b, lean=-3.0 - 1.5 * b, drop=0.22 + 0.03 * b, wbend=-3.0 - 2.0 * b)
    W = Vector(READY_WRIST) + Vector((0.02 * sway, 0.03 * b, 0.0))
    L.arm_to("Right", W, READY_RPOLE)
    L.set_rot("RightHand", L.rx(READY_HAND[0] + 3.0 * b) @ L.ry(READY_HAND[1]))
    L.set_rot("Launcher", QG)
    L.update()
    B = Vector((-0.55, -0.15 + 0.03 * b + 0.75 * flip, -1.6 + 0.1 * flip))
    info = left_ball_to(B, elbow_away=READY_LPOLE, guess=(0.45, 0.0, 0.45))
    info["nxL"] = pole_nx("Left", L.joint("LeftHand"), READY_LPOLE)
    L.head_look(target=(-6.0, -1.0 + 1.5 * max(flip, 0.0), -5.0))
    return info


# ------------------------------------------------------------------ captured poses + solved blends
def hinge_of(side, wrist, pole):
    """the elbow hinge axis (UpperTorso frame, after the library's elbow guard) for this wrist + pole"""
    Mi = L.frame_of("UpperTorso").inverted()
    t = (Mi @ (Vector(wrist) - L.joint(side + "UpperArm"))).normalized()
    n = t.cross(Mi @ Vector(pole)).normalized()
    sx = -1.0 if side == "Left" else 1.0
    if sx * n.x < -0.15:
        n = -n
    return n


def pole_for_hinge(side, wrist, n):
    """a world pole that makes the IK use hinge n (UpperTorso frame) -> continuous elbows in a blend"""
    Mt = L.frame_of("UpperTorso")
    t = (Mt.inverted() @ (Vector(wrist) - L.joint(side + "UpperArm"))).normalized()
    return tuple(Mt @ n.cross(t).normalized())


def capture(body_args, rpole, lpole, head):
    """a solved pose as IK inputs: right WRIST point + the hand's local turn (so a blend keeps the wrist
    between the two end bends), left hand centre, poles, head target, the right elbow hinge"""
    W = L.joint("RightHand").copy()
    return {"body": tuple(body_args), "W": W, "qh": L.get_rot("RightHand").copy(),
            "rpole": tuple(rpole), "H": hand_centre("Left"), "lpole": tuple(lpole), "head": Vector(head),
            "rhinge": hinge_of("Right", W, rpole), "hr": HEAD_TILT[0]}


def apply(P):
    body(*P["body"])
    rpole = P["rpole"]
    if P.get("rhinge") is not None:
        rpole = pole_for_hinge("Right", P["W"], P["rhinge"])
    over, _ = L.arm_to("Right", P["W"], rpole)
    L.set_rot("RightHand", P["qh"])
    L.set_rot("Launcher", QG)
    L.update()
    info = {"right": over, "nxR": pole_nx("Right", L.joint("RightHand"), rpole)}
    info["left"] = L.left_hand_to(point=P["H"], elbow_away=P["lpole"])
    info["nxL"] = pole_nx("Left", L.joint("LeftHand"), P["lpole"])
    L.head_look(target=P["head"])
    tilt(P.get("hr", 0.0))
    return info


def bez(a, c, b, t):
    return a * ((1 - t) ** 2) + c * (2 * t * (1 - t)) + b * (t * t)


def mix(A, B, t, cW=None, cH=None, tq=None):
    """blend of two captured poses; cW / cH = quadratic-Bezier control points for the right wrist and the
    left hand (paths kept in front of the body)"""
    W = bez(A["W"], cW, B["W"], t) if cW is not None else A["W"].lerp(B["W"], t)
    H = bez(A["H"], cH, B["H"], t) if cH is not None else A["H"].lerp(B["H"], t)
    qa, qb = A["qh"], B["qh"]
    if qa.dot(qb) < 0.0:
        qb = -qb
    return {"body": lerp(A["body"], B["body"], t), "W": W, "qh": qa.slerp(qb, t if tq is None else tq),
            "rpole": lerp(A["rpole"], B["rpole"], t), "H": H,
            "rhinge": A["rhinge"].slerp(B["rhinge"], t) if "rhinge" in A and "rhinge" in B else None,
            "lpole": lerp(A["lpole"], B["lpole"], t), "head": A["head"].lerp(B["head"], t),
            "hr": lerp(A.get("hr", 0.0), B.get("hr", 0.0), t)}


def clamp_left(H, margin=0.22):
    """keeps a left-hand target inside the arm's reach"""
    sh = L.joint("LeftUpperArm")
    d = Vector(H) - sh
    m = REACH + 0.25 - margin
    return sh + d.normalized() * min(d.length, m)


_prev = {}


def K(frame):
    """L.key with quaternion sign continuity (no 360-degree flips between keys)"""
    for pb in L.rig().pose.bones:
        q = pb.rotation_quaternion
        p = _prev.get(pb.name)
        if p is not None and q.dot(p) < 0.0:
            pb.rotation_quaternion = -q
        _prev[pb.name] = pb.rotation_quaternion.copy()
    L.key(frame)


def clip(kind):
    _prev.clear()
    L.new_clip(kind)


# ------------------------------------------------------------------ clips
if __name__ != "probe":
    clip("Ready")
    dbg("ready0", ready(0.0)); K(0)
    ready(0.5, 0.0, 0.5); K(12)
    dbg("ready_dip", ready(0.6, -0.15, 0.6)); K(19)
    dbg("ready_flip", ready(0.7, 1.0, 0.7)); K(24)
    ready(0.8, -0.14, 0.4); K(30)
    ready(0.6, 0.0, 0.0); K(38)
    ready(0.4, -0.08, -0.4); K(45)
    ready(0.3, 0.45, -0.5); K(49)
    ready(0.2, -0.06, -0.4); K(53)
    ready(0.1, 0.0, -0.2); K(58)
    ready(0.0); K(60)
    L.make_cyclic("Ready")

    for kind, c in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
        clip(kind)
        for i in range(31):
            t = i / 30.0
            br, br2 = math.sin(2.0 * math.pi * t), math.cos(2.0 * math.pi * t)
            trem, trem2 = math.sin(2.0 * math.pi * 6.0 * t), math.cos(2.0 * math.pi * 6.0 * t)
            r = draw(c, br, br2, trem, trem2)
            if i in (0, 8, 15, 23):
                dbg("%s_%d" % (kind, i), r)
            K(i)
        L.make_cyclic(kind)

    clip("Fire")
    draw(1.0, 0.0, 1.0, 0.0, 1.0); K(0)                                        # 0.00 = the ChargeHi start pose
    dbg("tug", draw(1.0, 0.0, 1.0, 0.0, 0.0, extra=TUG[0], dip=1.0)); K(2)      # 0.07 last tug + dip
    dbg("release", draw(1.0, 0.0, 1.0, 0.0, 0.0, extra=TUG[1], dip=0.8)); K(4)   # 0.133 RELEASE (FireAt)
    M_rel, look_rel = muzzle()
    H_rel = hand_centre("Left")
    # 0.20 snap: the fork kicks up (recoil flick), the left hand springs back and OUT (away from the
    # face) opening, the torso rocks back; 0.27 the hand reaches its extreme; 0.37 follow-through
    SNAP_BODY = (P_HI["hy"] + 6.0, P_HI["wy"] - 4.0, P_HI["lean"] + 5.0, P_HI["drop"] - 0.04, P_HI["back"],
                 P_HI["wbend"] + 6.0, P_HI["wroll"] - 3.0)
    SNAP_HEAD = M_rel + look_rel * 12.0 + Vector((0.0, 1.0, 0.0))

    def snap_pose(k, tag=None):
        """k 0 = release .. 1 = the extreme of the snap"""
        bd = lerp((P_HI["hy"], P_HI["wy"], P_HI["lean"] - 4.0, P_HI["drop"] + 0.1, P_HI["back"], P_HI["wbend"] - 2.4,
                   P_HI["wroll"] + 2.0), SNAP_BODY, k)
        body(*bd)
        r = aim(Vector(P_HI["F"]) + Vector((0.05 * k, 0.14 * k, 0.0)), P_HI["yaw"] + 2.0 * k,
                P_HI["elev"] + 18.0 * k, P_HI["roll"] + 8.0 * k)
        H = clamp_left(H_rel + Vector(SNAP_H) * k)
        r["left"] = L.left_hand_to(point=H, elbow_away=lerp(P_HI["lp"], SNAP_LP, k))
        L.head_look(target=M_rel.lerp(SNAP_HEAD, k) + look_rel * 10.0 * (1 - k))
        tilt(P_HI["hroll"] * (1.0 - 0.5 * k))
        if tag:
            dbg(tag, r)
        return bd

    snap_pose(0.62, "snap"); K(6)
    SB = snap_pose(1.0, "snap_x"); K(8)
    P_SNAP = capture(SB, RPOLE, SNAP_LP, SNAP_HEAD)
    # 0.37 follow-through: fork settling back toward level, left hand open out by the shoulder
    FOL_BODY = (P_HI["hy"] + 4.0, P_HI["wy"] - 2.0, P_HI["lean"] + 2.5, P_HI["drop"] - 0.02, P_HI["back"],
                P_HI["wbend"] + 3.0, P_HI["wroll"] - 1.5)
    body(*FOL_BODY)
    dbg("follow", aim(Vector(P_HI["F"]) + Vector((0.08, 0.05, 0.0)), P_HI["yaw"] + 1.0, P_HI["elev"] + 7.0,
                      P_HI["roll"] + 4.0))
    FOL_HP = clamp_left(H_rel + Vector(FOL_H))
    dbg("follow_left", L.left_hand_to(point=FOL_HP, elbow_away=SNAP_LP))
    FOL_HEAD = M_rel + look_rel * 14.0 + Vector((0.0, 0.5, 0.0))
    L.head_look(target=FOL_HEAD)
    tilt(P_HI["hroll"] * 0.35); K(11)
    P_FOL = capture(FOL_BODY, RPOLE, SNAP_LP, FOL_HEAD)
    # 0.37 -> 0.47 a held beat (tiny drift), then a smooth solved settle into the low hold
    ready(0.3)
    HEAD_TILT[0] = 0.0
    P_RDY = capture((70.0, -18.0 + 0.6, -3.45, 0.229, 0.0, -3.6, 0.0), READY_RPOLE, READY_LPOLE, (-6.0, -1.0, -5.0))
    beat = dict(P_FOL)
    beat["H"] = P_FOL["H"] + (P_FOL["H"] - P_SNAP["H"]) * 0.15
    beat["W"] = P_FOL["W"] + Vector((0.03, -0.04, 0.0))
    beat["body"] = lerp(P_SNAP["body"], P_FOL["body"], 1.15)
    dbg("beat", apply(beat)); K(14)
    cW = (beat["W"] + P_RDY["W"]) * 0.5 + Vector(CW_OFF)
    cH = (beat["H"] + P_RDY["H"]) * 0.5 + Vector((-0.3, 0.0, -0.5))
    s0, s1 = 14, 32
    settle_log = []
    for f in range(s0 + 1, s1):
        s = L.smooth((f - s0) / float(s1 - s0))
        # the launcher swings down ahead of the arm (its fork clears the head)
        r = apply(mix(beat, P_RDY, s, cW, cH, tq=1.0 - (1.0 - s) ** TQ_EASE))
        settle_log.append((f, r["nxL"], r["nxR"], r["right"], r["left"][0]))
        K(f)
    dbg("settle_log", settle_log)
    ready(0.3); K(s1)
    ready(0.15); K(35)
    ready(0.0); K(39)
    L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

    print("REPORT_dbg all", report)
    L.finish(SPEC, OUT, extra_times=[0.067, 0.2, 0.267, 0.367, 0.6, 0.8])
