"""03 Snowball Flipper -- a curved orange arm with a small cup at the end (lacrosse / jai-alai).

Concept (the character stands side-on, down-track = their LEFT, the camera sees their right side):
  Ready    the flipper carried upright over the right shoulder, cup up, the ball resting in it;
           easy breathing, the stick bobs gently.
  ChargeLo cocked back behind the right shoulder (cup back behind the head, screen-left),
           torso turned a little away from the track, a calm cradle rock.
  ChargeHi the same rock, deeper coil (more twist away, lower hips, stick lower), bigger rock
           plus a double-time tremble.
  Fire     hips lead -> the stick dips back (load) -> whips round in a 3/4 sidearm arc past the
           front -> at FireAt the stick points down-track and the ball slings out of the cup
           (~26 deg up) -> wrist snap -> follow-through down across the body -> settle to Ready.
Geometry: the cup (Seat = Muzzle) sits 4.47 studs from the grip along the stick CHORD S; the cup
opening (exit look) is the chord tilted 17.3 deg toward the concave side Q: L = .955 S + .297 Q.
The roll of the stick about its chord is searched per pose so the launcher turns as little as
possible in the hand (vs the Ready grip).
Fire (round 3): keyed every frame through the whip (the cup accelerates ~1.9 -> 3.0 studs/frame
and peaks AT the release, then keeps going down-track), in-betweens every 2 frames after the
snap, and the roll + elbow of EVERY key chosen together by a Viterbi pass (cost = grip turn,
wrist, stick clearance >= 0.2, joint + stick speed^2) so nothing flips.  The recovery comes back
the short way, low through down-track, the forearm rolling the grip back to Ready gradually.
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

LID = 3
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.0, "ChargeLo": 1.0, "ChargeHi": 1.0, "Fire": 1.6,
    "FireAt": 0.30,
    "Ball": {"show": "Always", "start": "Seat", "grow": 1.0},
    "Fx": {"Style": "snow", "Color": [1.0, 1.0, 1.0]},
    "TwoHanded": False,
    "Notes": "flipper (jai-alai cup): cradle-rock cocked behind the shoulder, sidearm whip, ball slings out of the cup",
}
FEET = {"Left": (-0.85, -0.25), "Right": (0.65, 0.35)}
CA, SA = 0.7919, 0.6107          # chord direction in the launcher's forward / top plane
A17 = math.radians(17.3)          # exit look vs chord
STICK = 4.47
REF = [None]                      # Launcher-bone rotation of the Ready grip
report = {}
PREVQ = {}


def unit(v):
    return Vector(v).normalized()


MAX_WRIST = 55.0


def _place(grip, S, Q, elbow):
    S = unit(S)
    Q = Vector(Q)
    Q = (Q - Q.dot(S) * S).normalized()
    F = CA * S - SA * Q
    T = SA * S + CA * Q
    return L.place_launcher(at=grip, forward=F, up=T, anchor="Pivot", elbow_away=elbow, max_wrist=MAX_WRIST)


def _bend():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


def _turn():
    g = L.get_rot("Launcher")
    ref = REF[0]
    return math.degrees((ref.inverted() @ g).angle if ref is not None else g.angle)


def _stick_clear():
    """nearest body block to the stick (excluding the right hand / forearm)"""
    piv = L.pivot_cf()
    worst, who = 9.0, None
    for i in range(3, 11):
        f = i / 10.0
        p = piv @ (Vector((0.0, -2.36 * f, -1.82 * f * f)) * L.LAUNCHER_SCALE)
        c, w = L.clearance(p, skip=("RightHand", "RightLowerArm"))
        if c < worst:
            worst, who = c, w
    return [round(worst, 2), who]


_LV = []


def apen(arm=True):
    """audit-style penetration on the realistic avatar boxes: (launcher depth in the UpperTorso /
    Head, right-arm depth in the torso / head)"""
    ob = L.launcher_object()
    if not _LV:
        vs = [v.co.copy() for v in ob.data.vertices]
        _LV.extend(vs[::max(1, len(vs) // 90)])
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    mw = ob.matrix_world
    wl = 0.0
    for co in _LV:
        pt = L.b2r(mw @ co)
        for bd in ("UpperTorso", "Head"):
            wl = max(wl, L._depth_inside(pt, *boxes[bd]))
    wa = 0.0
    if arm:
        for a in ("RightUpperArm", "RightLowerArm", "RightHand"):
            ab, ah = boxes[a]
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    for k in (-1, 0, 1):
                        pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                        for bd in ("UpperTorso", "Head", "LowerTorso"):
                            wa = max(wa, L._depth_inside(pt, *boxes[bd]))
    return wl, wa


LPOLE = Vector((0.0, 0.7, -0.7))     # left-arm pole in the UpperTorso frame: up + forward (elbow down/back)
LNX = []


def larm(target):
    """left arm IK with a pole fixed in the torso frame, so the hinge stays on the guard's safe
    side (targets are kept below / in front of the shoulder) and never mirrors mid-clip"""
    M = L.frame_of("UpperTorso")
    sh = L.joint("LeftUpperArm")
    t = (M.inverted() @ (Vector(target) - sh)).normalized()
    LNX.append(round(t.cross(LPOLE).normalized().x, 2))
    return L.arm_to("Left", target, M @ LPOLE)


def _elbows(elbow, scan=True):
    e = Vector(elbow)
    if not scan:
        return [tuple(e)]
    return [tuple(e), (e.x, e.y, e.z + 0.8), (e.x + 0.6, e.y * 0.5, e.z), (e.x - 0.4, e.y, e.z - 0.6)]


ARM = ("RightUpperArm", "RightLowerArm", "RightHand", "Launcher")


def _jump(ref=None):
    """degrees the right arm + launcher bones turn vs the previous Fire key (0 when none)"""
    ref = PREVQ if ref is None else ref
    tot = 0.0
    for b in ARM:
        p = ref.get(b)
        if p is None:
            return 0.0
        a = L.get_rot(b).rotation_difference(p).angle
        tot += math.degrees(min(a, 2.0 * math.pi - a))
    return tot


def stick(grip, S, Q, elbow=(0.6, -1.0, 0.3), search=90, step=15, pref=0.25, scan=True, roll=None, roll_c=None,
          win=20, cont=0.0, refs=None, tw=1.0):
    """grip = where the right hand holds the handle; S = chord direction grip -> cup;
    Q = the concave side hint.  Rolls Q about S (within +-search, or exactly `roll`, or within
    +-win of `roll_c`) and tries a few elbow directions for the least grip turn and a relaxed wrist."""
    S = unit(S)
    best = None
    if roll is not None:
        rolls = [roll]
    elif roll_c is not None:
        rolls = range(int(roll_c) - win, int(roll_c) + win + 1, 10)
    else:
        rolls = range(-search, search + 1, step)
    for el in _elbows(elbow, scan):
        for r in rolls:
            Qr = Quaternion(S, math.radians(r)) @ Vector(Q)
            inf = _place(grip, S, Qr, el)
            score = tw * _turn() + pref * abs(r - (roll_c or 0)) + 60.0 * inf["anchor_err"] + 1.5 * max(0.0, _bend() - 48.0)
            if cont:
                score += cont * sum(_jump(rf) for rf in (refs or [None])) + 150.0 * max(0.0, 0.15 - _stick_clear()[0])
            if best is None or score < best[0]:
                best = (score, Qr, r, el)
    info = _place(grip, S, best[1], best[3])
    info["elbow"] = best[3]
    info["roll"] = best[2]
    info["turn"] = round(_turn(), 1)
    info["bend"] = round(_bend(), 1)
    info["stick_clear"] = _stick_clear()
    info["cup"] = [round(v, 2) for v in (Vector(grip) + S * STICK)]
    return info


def stick_exit(grip, Lx, N, elbow=(0.6, -1.0, 0.3), search=90, step=15, pref=0.25, scan=True, cont=0.0, refs=None):
    """same, but the cup's EXIT look is fixed to Lx; N (perp to Lx) = the side the chord leans
    away from.  Rolls N about Lx."""
    Lx = unit(Lx)
    N0 = Vector(N)
    N0 = (N0 - N0.dot(Lx) * Lx).normalized()
    best = None
    for el in _elbows(elbow, scan):
        for r in range(-search, search + 1, step):
            n = Quaternion(Lx, math.radians(r)) @ N0
            S = math.cos(A17) * Lx - math.sin(A17) * n
            Q = math.sin(A17) * Lx + math.cos(A17) * n
            inf = _place(grip, S, Q, el)
            score = _turn() + pref * abs(r) + 60.0 * inf["anchor_err"] + 1.5 * max(0.0, _bend() - 48.0)
            if cont:
                score += cont * sum(_jump(rf) for rf in (refs or [None])) + 150.0 * max(0.0, 0.15 - _stick_clear()[0])
            if best is None or score < best[0]:
                best = (score, S, Q, r, el)
    info = _place(grip, best[1], best[2], best[4])
    info["elbow"] = best[4]
    info["roll"] = best[3]
    info["turn"] = round(_turn(), 1)
    info["bend"] = round(_bend(), 1)
    info["stick_clear"] = _stick_clear()
    info["cup"] = [round(v, 2) for v in (Vector(grip) + best[1] * STICK)]
    return info


def body(yaw=0.0, lean=-4.0, drop=0.15, back=0.0, side=0.0, waist_yaw=0.0, waist_bend=-4.0, waist_tilt=0.0,
         right_foot=None):
    """feet stay planted; the toes turn part of the way with the hips (the back foot pivots
    further on its ball in the throw via right_foot = its yaw)"""
    L.reset_pose()
    fy = {"Left": 0.35 * yaw, "Right": 0.55 * yaw if right_foot is None else right_foot}
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET, foot_yaw=fy)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_tilt))


def left_arm(local, elbow=None):
    """left wrist = left shoulder + offset in the UpperTorso frame"""
    sh = L.joint("LeftUpperArm")
    return larm(sh + L.frame_of("UpperTorso") @ Vector(local))


def left_world(offset, elbow=None):
    sh = L.joint("LeftUpperArm")
    return larm(sh + Vector(offset))


# ------------------------------------------------------------------ poses
def ready(b, sway=0.0, search=90):
    """b 0..1 = breath; sway -1..1 = small weight shift"""
    body(yaw=-4.0 + 2.0 * sway, lean=-3.0 - 1.5 * b, drop=0.12 + 0.04 * b, side=0.04 * sway,
         waist_yaw=-3.0, waist_bend=-3.0 - 2.0 * b)
    info = stick((1.38, -0.14 + 0.12 * b, -0.8 + 0.05 * sway), S=(0.18 + 0.17 * sway, 1.0, 0.42 + 0.2 * b),
                 Q=(-0.6, 0.0, -1.0), elbow=(0.6, -1.0, 0.4), search=search, scan=False)
    left_arm((-0.38 - 0.05 * b - 0.05 * sway, -1.45 + 0.05 * b, -0.18 + 0.12 * sway - 0.06 * b))
    L.head_look(target=(-9.0, 0.3 - 0.25 * b, -1.0 - 1.2 * sway))
    return info


def cocked(p, depth, roll=None, elbow=(0.5, -0.8, 0.5)):
    """p 0..1 = cradle phase (sine); depth 0 = ChargeLo, 1 = ChargeHi.  Keys every 2 frames so
    the triple-time full-charge tremble (sh) is really sampled."""
    s = math.sin(2.0 * math.pi * p)
    c = math.cos(2.0 * math.pi * p)
    sh = math.sin(6.0 * math.pi * p) * depth
    amp = 1.0 + 0.8 * depth
    body(yaw=-16.0 - 16.0 * depth + 3.0 * s * amp, lean=-5.0 - 5.0 * depth - 1.5 * c, drop=0.22 + 0.25 * depth,
         back=0.05 + 0.1 * depth, waist_yaw=-10.0 - 12.0 * depth + 2.0 * s * amp,
         waist_bend=-2.0 + 2.0 * depth, waist_tilt=-4.0 - 6.0 * depth)
    elev = 47.0 - 9.0 * depth + 6.0 * s * amp + 4.5 * sh
    S = L.direction(yaw=-125.0 - 10.0 * depth + 6.0 * c * amp + 2.0 * sh, elev=elev)   # back + up, cup behind the head
    grip = (1.3 + 0.16 * depth + 0.05 * s * amp + 0.02 * sh, 0.9 - 0.12 * depth + 0.05 * c + 0.05 * sh,
            0.0 + 0.1 * depth - 0.08 * s * amp)
    info = stick(grip, S=S, Q=(0.0, 1.0, 0.0), elbow=elbow, scan=False, roll=roll)
    # the lead arm reaches out to the front-left (toward the track side), rocking with the cradle
    left_arm((-1.12 - 0.06 * depth, -0.4 + 0.04 * depth + 0.04 * s + 0.03 * sh, -0.72 - 0.06 * depth - 0.04 * c))
    L.head_look(target=(-10.0, 0.5, -0.8))
    return info



KEYLOG = []


def fkey(frame):
    _fkey(frame)
    row = [frame]
    for b in ARM:
        rel = READYQ[b].inverted() @ L.get_rot(b)
        row.append(round(math.degrees(2.0 * math.acos(max(-1.0, min(1.0, rel.w))))))
    sw, tw_ = L.swing_twist(READYQ["RightUpperArm"].inverted() @ L.get_rot("RightUpperArm"))
    row.append([round(math.degrees(sw.angle)), round(math.degrees(tw_.angle))])
    KEYLOG.append(row)


def _fkey(frame):
    """L.key with every bone's quaternion kept in the same hemisphere as its previous key, so
    the F-curve interpolation takes the short way round (no flip through odd poses)"""
    for name in L.BONES:
        q = L.get_rot(name)
        p = PREVQ.get(name)
        if p is not None and q.dot(p) < 0.0:
            q = -q
            L.set_rot(name, q)
        PREVQ[name] = q.copy()
    L.key(frame)


# ------------------------------------------------------------------ clips
L.new_clip("Ready")
report["ready0"] = ready(0.0, 0.0, search=180)
REF[0] = L.get_rot("Launcher")
L.key(0)
report["ready1"] = ready(1.0, 1.0); L.key(24)
ready(0.2, 0.0); L.key(36)
ready(0.9, -1.0); L.key(48)
ready(0.0, 0.0); L.key(60)
L.make_cyclic("Ready")

# one roll of the stick about its chord and one elbow for BOTH charge depths (no turning in the
# hand as the live charge blends Lo <-> Hi); per phase, near the base roll
L.new_clip("ChargeLo")
CROLL = cocked(0.0, 0.0)["roll"]
CBEST = None
for el in _elbows((0.5, -0.8, 0.5)) + [(0.9, -0.4, 0.5), (0.3, -1.0, 1.0)]:
    rolls, worst = [], 0.0
    for i in range(0, 15):
        best = None
        for r in range(CROLL - 30, CROLL + 31, 15):
            t, pen = 0.0, 0.0
            for d in (0.0, 1.0):
                t = max(t, cocked(i / 15.0, d, roll=r, elbow=el)["turn"])
                wl, wa = apen()
                pen = max(pen, max(0.0, wl - 0.06) + max(0.0, wa - 0.12))
            sc = t + 0.3 * abs(r - CROLL) + 400.0 * pen
            if best is None or sc < best[0]:
                best = (sc, r, t + 400.0 * pen)
        rolls.append(best[1])
        worst = max(worst, best[2])
    if CBEST is None or worst < CBEST[0]:
        CBEST = (worst, rolls, el)
ROLLS, CEL = CBEST[1], CBEST[2]
report["charge_rolls"] = ROLLS
report["charge_elbow"] = CEL
report["charge_worst_turn"] = round(CBEST[0], 1)
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind)
    for i in range(15):
        info = cocked(i / 15.0, depth, roll=ROLLS[i], elbow=CEL)
        if i in (0, 4, 8):
            report["%s_%d" % (kind, i)] = info
        L.key(i * 2)
    cocked(0.0, depth, roll=ROLLS[0], elbow=CEL); L.key(30)
    L.make_cyclic(kind)

L.new_clip("Fire")
ready(0.0, 0.0)
READYQ = {b: L.get_rot(b).copy() for b in ARM}


def lerp(a, b, t):
    return a + (b - a) * t


BODY0 = dict(yaw=0.0, lean=-4.0, drop=0.15, back=0.0, waist_yaw=0.0, waist_bend=-4.0, waist_tilt=0.0)


def B(**kw):
    """a full body-parameter dict (the back foot pivot defaults to 0.55 x the hip yaw)"""
    d = dict(BODY0)
    d.update(kw)
    d.setdefault("right_foot", 0.55 * d["yaw"])
    return d


LOADB = B(yaw=-24.0, lean=-8.0, drop=0.45, back=0.15, waist_yaw=-28.0, waist_bend=0.0, waist_tilt=-10.0, right_foot=-13.0)
RELB = B(yaw=42.0, lean=-10.0, drop=0.3, back=0.05, waist_yaw=16.0, waist_bend=-6.0, waist_tilt=0.0, right_foot=40.0)
LIFTB = B(yaw=30.0, lean=-9.0, drop=0.28, back=0.03, waist_yaw=6.0, waist_bend=-7.0, right_foot=26.0)
RECB = B(yaw=12.0, lean=-5.0, drop=0.18, back=0.0, waist_yaw=2.0, waist_bend=-4.0, right_foot=6.6)


def mix(a, b, t):
    return {k: lerp(a[k], b[k], t) for k in a}


def bt(t):
    """the unwind from the load (t 0) to the release (t 1)"""
    return mix(LOADB, RELB, t)


def W(off, elbow):
    return ("w", off, elbow)          # left wrist = left shoulder + world offset


def A(off, elbow=(-0.4, -0.3, 1.0)):
    return ("a", off, elbow)          # left wrist = left shoulder + offset in the UpperTorso frame


def left_target(spec):
    sh = L.joint("LeftUpperArm")
    if spec[0] == "w":
        return sh + Vector(spec[1])
    return sh + L.frame_of("UpperTorso") @ Vector(spec[1])


GLOVE = A((-1.18, -0.36, -0.82))      # lead arm out front-left (the ChargeHi arm)
UP = (0.0, 1.0, 0.0)

# Fire keys: frame, body, left arm, head target, stick (grip, chord S, elbow) or exit (grip, exit
# look Lx, N) for the release.  The roll of the stick about its chord and the elbow of EVERY key
# are chosen together below (dynamic programming over all keys), so the arm never flips.
KEYS = [
    dict(f=3, B=bt(0.0), L=GLOVE, look=(-10.0, 0.5, -0.8), name="load",
         grip=(1.43, 0.7, 0.2), S=L.direction(-140.0, 20.0), el=(0.5, -0.6, 0.7)),
    # the whip: one accelerating sidearm arc round the camera side and over the front; the lead
    # arm swings down-track and pulls in to the hip as the hips open
    dict(f=4, B=bt(0.12), L=A((-1.16, -0.4, -0.8)), look=(-10.0, 0.6, -0.8),
         grip=(1.48, 0.72, 0.0), S=L.direction(-162.0, 28.0), el=(0.5, -0.6, 0.7)),
    dict(f=5, B=bt(0.27), L=A((-1.12, -0.46, -0.75)), look=(-10.0, 0.7, -1.0),
         grip=(1.42, 0.68, -0.35), S=L.direction(-190.0, 36.0), el=(0.6, -0.6, 0.6)),
    dict(f=6, B=bt(0.45), L=A((-1.04, -0.55, -0.66)), look=(-10.0, 0.9, -1.2), name="whip",
         grip=(1.15, 0.60, -0.80), S=L.direction(-222.0, 42.0), el=(0.7, -0.6, 0.5)),
    dict(f=7, B=bt(0.63), L=A((-0.94, -0.66, -0.56)), look=(-10.0, 1.2, -1.4),
         grip=(0.85, 0.45, -1.15), S=L.direction(-258.0, 44.0), el=(0.8, -0.6, 0.3)),
    dict(f=8, B=bt(0.82), L=A((-0.82, -0.78, -0.45)), look=(-10.0, 1.6, -1.4),
         grip=(0.45, 0.28, -1.35), S=L.direction(-297.0, 40.0), el=(0.8, -0.6, 0.2)),
    # 0.30 RELEASE (FireAt): the cup's exit points down the track, the ball slings out while the
    # cup is still travelling fast down-track
    dict(f=9, B=bt(1.0), L=A((-0.7, -0.9, -0.3)), look=(-10.0, 2.0, -1.2), name="release",
         grip=(0.05, 0.1, -1.45), Lx=L.direction(3.5, 26.0), N=L.direction(-82.0, 0.0), el=(0.8, -0.6, 0.2),
         cup_t=(-3.55, 2.3, -2.75)),
    # the arc keeps going down-track, the cup already dropping; wrist snap over and down, the
    # stick finishing low down-track on the FRONT side (visible from the pad camera)
    dict(f=10, B=B(yaw=47.0, lean=-12.0, drop=0.3, back=0.03, waist_yaw=18.0, waist_bend=-8.0, right_foot=46.0),
         L=A((-0.6, -1.05, -0.15)), look=(-10.0, 2.0, -1.1), name="through",
         grip=(-0.25, -0.02, -1.45), S=L.direction(10.0, 8.0), el=(0.7, -0.9, 0.0)),
    dict(f=11, B=B(yaw=51.0, lean=-14.0, drop=0.32, back=0.02, waist_yaw=19.0, waist_bend=-10.0, right_foot=52.0),
         L=A((-0.52, -1.15, 0.0)), look=(-10.0, 1.9, -1.0), name="snap",
         grip=(-0.4, -0.12, -1.48), S=L.direction(20.0, -8.0), el=(0.6, -1.0, -0.2)),
    dict(f=14, B=B(yaw=55.0, lean=-17.0, drop=0.36, back=0.02, waist_yaw=20.0, waist_bend=-12.0, right_foot=57.0),
         L=A((-0.46, -1.25, 0.12)), look=(-10.0, 1.6, -0.9), name="snap2",
         grip=(-0.5, -0.3, -1.52), S=L.direction(32.0, -18.0), el=(0.6, -1.0, -0.3)),
    # follow-through: the stick down and out in front, the right hand out in front of the belly
    dict(f=17, B=B(yaw=60.0, lean=-20.0, drop=0.42, back=0.05, waist_yaw=20.0, waist_bend=-14.0, right_foot=62.0),
         L=A((-0.45, -1.3, 0.18)), look=(-10.0, 1.3, -0.8), name="follow",
         grip=(-0.55, -0.45, -1.56), S=L.direction(42.0, -22.0), el=(0.5, -1.0, -0.6)),
    # settle (short): the weight sinks, the stick drifts on a few degrees
    dict(f=21, B=B(yaw=62.0, lean=-21.0, drop=0.48, back=0.05, waist_yaw=22.0, waist_bend=-15.0, right_foot=63.0),
         L=A((-0.45, -1.3, 0.2)), look=(-12.0, 0.9, -0.8), name="settle",
         grip=(-0.52, -0.5, -1.56), S=L.direction(48.0, -24.0), el=(0.5, -1.0, -0.6)),
    # the stick swings back round the front at hip height, then lifts up the right side
    dict(f=27, B=B(yaw=45.0, lean=-13.0, drop=0.36, back=0.03, waist_yaw=12.0, waist_bend=-10.0, right_foot=44.0),
         L=A((-0.42, -1.35, 0.1)), look=(-10.0, 0.8, -1.0), name="round",
         grip=(-0.15, -0.45, -1.56), S=L.direction(62.0, -14.0), el=(0.6, -1.0, -0.1)),
    dict(f=33, B=LIFTB, L=A((-0.4, -1.4, -0.05)), look=(-10.0, 0.7, -1.0), name="lift",
         grip=(0.4, -0.42, -1.45), S=L.direction(78.0, 5.0), el=(0.6, -1.0, 0.3)),
    dict(f=37, B=mix(LIFTB, RECB, 0.45), L=A((-0.4, -1.42, -0.11)), look=(-10.0, 0.57, -1.0),
         grip=(0.8, -0.33, -1.25), S=L.direction(95.0, 30.0), el=(0.6, -1.0, 0.35)),
    dict(f=42, B=RECB, L=A((-0.4, -1.45, -0.18)), look=(-10.0, 0.4, -1.0), name="recover",
         grip=(1.15, -0.25, -1.0), S=L.direction(110.0, 58.0), el=(0.6, -1.0, 0.4)),
    # the relaxed carry the clip ends on: the Ready stance and stick line
    dict(f=48, B=B(yaw=-4.0, lean=-3.0, drop=0.12, waist_yaw=-3.0, waist_bend=-3.0), L=A((-0.38, -1.45, -0.18)),
         look=(-9.0, 0.3, -1.0), name="carry", end=True,
         grip=(1.38, -0.14, -0.8), S=(0.18, 1.0, 0.42), el=(0.6, -1.0, 0.4)),
]


def tween(a, b, f):
    """an in-between key (post-release): everything interpolated, the stick direction slerped"""
    t = (f - a["f"]) / float(b["f"] - a["f"])
    return dict(f=f, B=mix(a["B"], b["B"], t), L=("mix", a["L"], b["L"], t),
                look=tuple(lerp(x, y, t) for x, y in zip(a["look"], b["look"])),
                grip=tuple(lerp(x, y, t) for x, y in zip(a["grip"], b["grip"])),
                S=tuple(unit(a["S"]).slerp(unit(b["S"]), t)),
                el=tuple(lerp(x, y, t) for x, y in zip(a["el"], b["el"])), end=False)


# in-betweens every 2 frames after the snap, so the IK (not the F-curves) shapes the recovery
full = []
for i, k in enumerate(KEYS):
    full.append(k)
    if k["f"] >= 11 and i + 1 < len(KEYS):
        nxt = KEYS[i + 1]
        f = k["f"] + 2
        while f <= nxt["f"] - 2:
            full.append(tween(k, nxt, f))
            f += 2
KEYS = full
WIND_GUARD = False  # hard 'never wind round' guard (off: it forces a wrist flip on this rig)
SPEED_W = 0.02     # cost of joint speed: w * jump^2 / frames
TURN_W = 2.0       # cost of the launcher turning in the hand (vs the Ready grip)
RW = 0.6
TURN_W_REC = 0.5   # ... in the recovery, where the grip unwinds back to the Ready grip


def elbow_opts(k):
    """elbow hint turned about the shoulder -> grip axis (deg).  The throw keeps its elbow near
    the authored one; the recovery may circle the elbow so the forearm can roll the grip back
    to the Ready grip without the wrist flipping."""
    if k["f"] >= 21:
        return [0, 25, -25, 50, -50, 75, -75, 100, -100, 125, -125, 150, -150]
    if k["f"] == 9:
        return [0, 30, -30, 60, -60, 90, -90]
    return [0, 30, -30]


def elbow_vec(k, ang):
    e = Vector(k["el"])
    if not ang:
        return tuple(e)
    axis = (Vector(k["grip"]) - L.joint("RightUpperArm")).normalized()
    return tuple(Quaternion(axis, math.radians(ang)) @ e)


def pose_left(spec, elbow=None):
    if spec[0] == "mix":
        _, a, b, t = spec
        p = left_target(a).lerp(left_target(b), t)
        return larm(p)
    return larm(left_target(spec))


def pose_key(k, ang, r):
    """puts the whole key pose: body, left arm, stick (roll r about the chord / exit), head"""
    body(**k["B"])
    pose_left(k["L"])
    el = elbow_vec(k, ang)
    if "Lx" in k:
        Lx = unit(k["Lx"])
        N0 = Vector(k["N"])
        N0 = (N0 - N0.dot(Lx) * Lx).normalized()
        n = Quaternion(Lx, math.radians(r)) @ N0
        S = math.cos(A17) * Lx - math.sin(A17) * n
        Q = math.sin(A17) * Lx + math.cos(A17) * n
    else:
        S = unit(k["S"])
        Q = Quaternion(S, math.radians(r)) @ Vector(UP)
    inf = _place(k["grip"], S, Q, el)
    L.head_look(target=k["look"])
    return inf, S


def unary(k, inf, S):
    clear = _stick_clear()[0]
    c = (TURN_W if k["f"] <= 21 else TURN_W_REC) * _turn() + 60.0 * inf["anchor_err"] + 1.5 * max(0.0, _bend() - 48.0) + 300.0 * max(0.0, 0.25 - clear)
    c += 15.0 * max(0.0, _turn() - 55.0)
    wl, wa = apen()
    c += 1500.0 * max(0.0, wl - 0.04) + 600.0 * max(0.0, wa - 0.1)
    cup = Vector(k["grip"]) + S * STICK
    if k["f"] <= 14 and cup.x < -0.7 and cup.z > -0.8:        # keep the throw on the camera's side
        c += 40.0 * (cup.z + 0.8)
    # never wind round: the launcher may not turn past 120 deg in the hand and the upper arm may
    # not twist past 150 deg (a winding path has to cross those)
    _, twq = L.swing_twist(READYQ["RightUpperArm"].inverted() @ L.get_rot("RightUpperArm"))
    tw_deg = math.degrees(twq.angle)
    if WIND_GUARD and (_turn() > 120.0 or min(tw_deg, 360.0 - tw_deg) > 150.0):
        c += 1000.0
    if k.get("end"):
        c += 3.0 * _jump(READYQ)
    if "cup_t" in k:
        c += 120.0 * (cup - Vector(k["cup_t"])).length
    return c, clear, cup


def jump_q(a, b):
    tot = 0.0
    for bn in ARM + ("PIV",):
        x = a[bn].rotation_difference(b[bn]).angle
        tot += math.degrees(min(x, 2.0 * math.pi - x))
    return tot


# the start (the ChargeHi pose) is fixed
cocked(0.0, 1.0, roll=ROLLS[0], elbow=CEL)
START = {b: L.get_rot(b).copy() for b in ARM}
START["PIV"] = L.pivot_cf().to_quaternion()
cands = []
for k in KEYS:
    row = []
    for ang in elbow_opts(k):
        for r in range(-180, 180, 20 if k["f"] >= 21 else 15):
            inf, S = pose_key(k, ang, r)
            u, clear, cup = unary(k, inf, S)
            u += 0.4 * abs(ang)
            if k["f"] >= 21:                      # unwind toward the Ready arm, never wind round
                u += RW * (k["f"] - 20) / 28.0 * _jump(READYQ)
            qd = {b: L.get_rot(b).copy() for b in ARM}
            qd["PIV"] = L.pivot_cf().to_quaternion()
            row.append(dict(el=ang, r=r, u=u, q=qd))
    cands.append(row)
# Viterbi over the keys.  Each candidate's quaternions are hemisphere-aligned to the predecessor
# (as the F-curves will be), and the states are split by the sign of every arm bone vs the Ready
# pose, so a path that winds a bone a full turn round (and ends on -Ready) can be told apart
# and refused at the end.
BN = ARM + ("PIV",)
BEAM = 40
END_WIND = 0.0     # the rig cannot unwind the grip without a flip: allow the smooth full forearm roll


def step(pq, cq):
    al, tot = {}, 0.0
    for bn in BN:
        q = cq[bn]
        d = pq[bn].dot(q)
        if d < 0.0:
            q, d = -q, -d
        al[bn] = q
        tot += 2.0 * math.degrees(math.acos(min(1.0, d)))
    return al, tot


prev_f, prev = 0, [dict(cost=0.0, q=START, ci=None)]
back = []
for ki, k in enumerate(KEYS):
    gap = k["f"] - prev_f
    states = {}
    for ci, c in enumerate(cands[ki]):
        for pi, p in enumerate(prev):
            al, j = step(p["q"], c["q"])
            v = p["cost"] + SPEED_W * j * j / gap + c["u"]
            par = tuple(al[b].dot(READYQ[b]) > 0.0 for b in ARM)
            key = (ci, par)
            if key not in states or v < states[key]["cost"]:
                states[key] = dict(cost=v, q=al, ci=ci, par=par, prev=pi)
    groups = {}
    for st in sorted(states.values(), key=lambda st: st["cost"]):
        g = groups.setdefault(st["par"], [])
        if len(g) < BEAM:
            g.append(st)
    cur = [st for g in groups.values() for st in g]
    back.append(cur)
    prev, prev_f = cur, k["f"]
# the end must be the Ready pose itself, not Ready wound a full turn (-q)
ends = [(st["cost"] + (0.0 if all(st["par"]) else END_WIND), i) for i, st in enumerate(prev)]
bi = min(ends)[1]
report["dp_cost"] = round(min(ends)[0], 1)
print("REPORT_DP " + json.dumps(sorted(set(str(st["par"]) for st in prev))))
choice = [None] * len(KEYS)
for ki in range(len(KEYS) - 1, -1, -1):
    st = back[ki][bi]
    choice[ki] = st["ci"]
    bi = st["prev"]
cocked(0.0, 1.0, roll=ROLLS[0], elbow=CEL); fkey(0)                     # 0.00 the charge pose
for ki, k in enumerate(KEYS):
    c = cands[ki][choice[ki]]
    inf, S = pose_key(k, c["el"], c["r"])
    if "name" in k:
        report[k["name"]] = dict(roll=c["r"], elbow=[c["el"]], turn=round(_turn(), 1),
                                 bend=round(_bend(), 1), stick_clear=_stick_clear(),
                                 arm_overreach=inf.get("arm_overreach"),
                                 cup=[round(v, 2) for v in (Vector(k["grip"]) + S * STICK)])
    fkey(k["f"])
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
L.set_interpolation("Fire", 'BEZIER', 'AUTO', frames=list(range(3, 12)))

# ---------------------------------------------------------------- probe: cup path, hand turn, stick clearance
L.use_clip("Fire")
SEAT = L.load_meta(LID)["Seat"]["pos"]
rows, prev, prevh, prevl = [], None, None, None
for f in range(0, 49):
    L.goto(f / 30.0)
    cup = L.launcher_point(SEAT)
    h = L.world_cf("RightHand").to_quaternion()
    lq = L.pivot_cf().to_quaternion()
    step = (cup - prev).length if prev is not None else 0.0
    hs = math.degrees(h.rotation_difference(prevh).angle) if prevh is not None else 0.0
    ls = math.degrees(lq.rotation_difference(prevl).angle) if prevl is not None else 0.0
    rows.append([f, [round(v, 2) for v in cup], round(step, 2), round(min(hs, 360 - hs)), round(min(ls, 360 - ls)), _stick_clear()[0],
                 _stick_clear()[1], round(L.launcher_lowest_y(), 2), [round(x, 2) for x in apen()]])
    prev, prevh, prevl = cup, h, lq
for r in rows:
    print("REPORT_F " + json.dumps(r))
print("REPORT_T " + json.dumps({k: [v.get("roll"), v.get("turn"), v.get("bend"), v.get("stick_clear", [0])[0], [round(x, 1) for x in v.get("elbow", ())]] for k, v in report.items() if isinstance(v, dict)}))
print("REPORT_K " + json.dumps(KEYLOG))
print("REPORT_LNX min %.2f" % min(LNX))
print("REPORT_POSES " + json.dumps({k: {kk: v[kk] for kk in ("roll", "turn", "bend", "stick_clear", "cup", "elbow")
                                         if kk in v} | {e: v[e] for e in v if "overreach" in e}
                                     for k, v in report.items() if isinstance(v, dict)}))
L.finish(SPEC, OUT, extra_times=[0.1, 0.2, 0.27, 0.33, 0.37, 0.47, 0.6, 0.77, 0.93, 1.07, 1.2, 1.4])
