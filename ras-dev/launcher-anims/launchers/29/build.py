"""29 Singularity Cannon -- a black cannon with a dark-energy (pink / teal) rim: it holds a tiny
black hole, and the shot is a gravitational implosion + blast.

The player stands side-on on the pad (down-track = their LEFT, away from the camera).  The cannon
is carried across the character's FRONT (screen-right) so the pad camera sees it end-on, the dark
muzzle pointing into the screen.
  Ready    a HEAVY low hold at arm's length in front of the hips, muzzle sagging, the body looming over
           it; ominous stillness: slow deep breathing, a barely-there sway, the cannon's weight dipping
           every 1.2 s, eyes down the track.
Round 2 (director fixes): the cannon is held ~0.6-0.9 studs further out in front (az -1.8..-2.5) so
the breech clears the chest and the head hunches OVER/behind it; the hunch comes from the squat +
waist twist; both upper arms are solved with their part +X kept outward (arm_away), so the elbows hang
out/down instead of twisting into the chest.  probe29.py / tune29.py in this folder measure the
body-vs-launcher and limb-vs-torso box overlaps.
Round 3 (ball must be SEEN leaving in the pad camera): after the release the recoil is first a straight
shove back along the level barrel (0.27 s) so the ball shows rising over the rim; the barrel then swings
toward the character's BACK (ayaw -30 -> -66) before it flips up, and the peak / hang carry the cannon up
over the right shoulder (grip z ~0, torso bent far back) so the barrel sits screen-LEFT of the ball's
line.  occl29.py ray-casts the ball disk from the pad camera per Fire frame (100 % visible 0.33-0.77 s).
In-between keys 14/16/25 (FIX / FIX2) were tuned with tune29.py for left-hand reach, wrist bend, overlaps.
  ChargeLo the singularity PULLS: the body curls inward around the cannon (hunched, head tucked),
           hips sitting back away from the muzzle.  Once per loop the cannon LURCHES toward the
           track (the pull) and is hauled back in; a steady tremble of resisting.
  ChargeHi the same rhythm: extreme hunch, deeper crouch, bigger lurches, violent trembling.
  Fire     implosion anticipation (curl in even tighter) -> the release at FireAt, dead level down
           the track -> the character is BLOWN BACK: torso thrown back and away from the track, the
           cannon and both arms flung up high, the right foot staggers a step back, head snapped
           back -> a shaky hang -> the step back in, the cannon lowered to the hip.
Ball: hidden until it pops out of the muzzle (barrel), violet spark burst + violet charge sparks.
Every frame is solved with IK from smooth parameter curves (loops are closed-form periodic).
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

LID = 29
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_FRAME = 6
SPEC = {
    "Ready": 2.4, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.6,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Never", "start": "Muzzle", "grow": 1.0},
    "Fx": {"Style": "spark", "Color": [150, 90, 255], "Charge": "spark", "ChargeColor": [120, 60, 220]},
    "TwoHanded": True,
    "AllowFootLift": True,
    "Notes": "singularity cannon: heavy ominous hip hold, hunched and trembling against the pull while charging, implosion then a massive blow-back (arms flung up, stagger step) and recovery",
}
FEET = {"Left": (-1.0, -0.3), "Right": (0.85, 0.4)}
G2 = L.load_meta(LID)["Grip2"]["pos"]
GRIP = None
report = {}
_last = {}

# parameter channels
NAMES = ["yaw", "lean", "tilt", "drop", "back", "side", "wyaw", "wbend", "wroll",
         "ax", "ay", "az", "ayaw", "aelev", "aroll", "lx", "ly", "lz",
         "rfx", "rfz", "rlift", "lfx", "lfz", "shake", "rex", "rey", "rez", "lex", "ley", "lez",
         "lfree", "flx", "fly", "flz", "bshake"]
QUICK = bool(os.environ.get("Q29"))
REACH = math.sqrt(0.25 + (L.UPPER_ARM + L.LOWER_ARM) ** 2)
LO_R, HI_R = 0.72 * REACH + 0.22, 0.88 * REACH + 0.22   # hand-centre distance band of the free left arm


DIAG = {}


def diag(kind, info):
    """per-frame elbow bends + reach ratios (shoulder->wrist / full reach) for the tuning printout"""
    bl = math.degrees(L.get_rot("LeftLowerArm").angle)
    br = math.degrees(L.get_rot("RightLowerArm").angle)
    DIAG.setdefault(kind, []).append("%.0f/%.0f|%.2f/%.2f" % (br, min(bl, 360 - bl), info["rr"], info["lr"]))


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


def lift_foot(side, x, z, lift, yaw):
    """re-solves one leg with its ankle `lift` studs off the floor (a stepping foot)"""
    target = Vector((x, L.ANKLE_REST[side][1] + lift, z))
    toe = L.ry(yaw) @ Vector((0.0, 0.0, -1.0))
    hip = L.joint(side + "UpperLeg")
    Mi = L.frame_of("LowerTorso").inverted()
    qu, ql, err = L.solve_limb(Mi @ (target - hip), L.THIGH, L.SHIN, Mi @ toe, bend=-1.0)
    L.set_rot(side + "UpperLeg", qu)
    L.set_rot(side + "LowerLeg", ql)
    want = (L.ry(yaw) @ L.rx(12.0 * min(1.0, lift / 0.2))).to_matrix()     # toe drops a little
    L.set_rot(side + "Foot", (L.frame_of(side + "LowerLeg").inverted() @ want).to_quaternion())
    L.update()
    return err


def shake_at(t, freqs):
    """5 smooth pseudo-random tremble values in about -1..1 (periodic if freqs are loop harmonics)"""
    out = []
    for i in range(5):
        v = 0.0
        for j, fq in enumerate(freqs):
            v += math.sin(2.0 * math.pi * fq * t + 1.7 * i + 2.3 * j + 0.9 * i * j) / len(freqs) ** 0.5
        out.append(max(-1.0, min(1.0, v)))
    return out


def arm_away(side, n):
    """elbow_away (world) that makes the arm's part +X follow n (UpperTorso frame) for the current
    shoulder->wrist line: t x (n x t) = n (perpendicular part), and solve_arm uses t x away."""
    Mt = L.frame_of("UpperTorso")
    t = Mt.inverted() @ (L.joint(side + "Hand") - L.joint(side + "UpperArm"))
    e = Vector(n).normalized().cross(t.normalized())
    return tuple(Mt @ e)


def pose(p, s=(0.0, 0.0, 0.0, 0.0, 0.0), **kw):
    a = p["shake"]
    b = a * p.get("bshake", 1.0)                 # body share of the tremble (the rest goes on the cannon)
    L.reset_pose()
    root = L.ry(p["yaw"] + 2.0 * b * s[3]) @ L.rx(p["lean"] + 1.5 * b * s[4]) @ L.rz(p["tilt"] + 1.5 * b * s[2])
    feet = {"Left": (p["lfx"], p["lfz"]), "Right": (p["rfx"], p["rfz"])}
    L.stance(hip_drop=p["drop"] + 0.02 * b * s[1], hip_back=p["back"], hip_side=p["side"] + 0.02 * b * s[0],
             root=root, feet=feet)
    if p["rlift"] > 0.005:
        lift_foot("Right", p["rfx"], p["rfz"], p["rlift"], p["yaw"])
    L.waist(L.ry(p["wyaw"] + 2.0 * b * s[0]) @ L.rx(p["wbend"] + 1.8 * b * s[2]) @ L.rz(p["wroll"] + 2.0 * b * s[4]))
    at = (p["ax"] + 0.03 * a * s[0], p["ay"] + 0.04 * a * s[1], p["az"] + 0.025 * a * s[2])
    hk = dict(yaw=p["ayaw"] + 1.3 * a * s[3], elev=p["aelev"] + 1.4 * a * s[4], roll=p["aroll"], grip_twist=GRIP)
    hk.update(kw)
    # (rex, rey, rez) / (lex, ley, lez) = the upper arm's OUTWARD axis (part +X) in the UpperTorso frame.
    # The IK is solved twice: once to find the shoulder->wrist line, then with the elbow_away that keeps
    # the arm part's +X on that axis (never twisted into the chest; the elbow hangs out/down/back).
    L.hold(at, elbow_away=(0.3, -1.0, -0.2), **hk)
    info = L.hold(at, elbow_away=arm_away("Right", (p["rex"], p["rey"], p["rez"])), **hk)
    info["sh"] = [round(v, 2) for v in L.joint("RightUpperArm")]
    info["wr"] = [round(v, 2) for v in L.joint("RightHand")]
    lf = max(0.0, min(1.0, p.get("lfree", 0.0)))
    if lf < 0.002:
        L.left_hand_to(key="Grip2", elbow_away=(-0.4, -1.0, -0.2))
        info["left"] = L.left_hand_to(key="Grip2", elbow_away=arm_away("Left", (p["lex"], p["ley"], p["lez"])))
    else:
        # the left hand lets go of Grip2 and is flung up: its target slides from the grip to a free
        # point given in the UpperTorso frame relative to the left shoulder, bulging out to the left
        Mt = L.frame_of("UpperTorso")
        sh = L.joint("LeftUpperArm")
        free = sh + Mt @ Vector((p["flx"], p["fly"], p["flz"]))
        w = L.smooth(lf)
        # shoulder-relative swing: the direction turns (with an outward bulge), the distance stays in
        # 0.75..0.92 of full reach so the elbow never locks straight or folds flat on the way
        vg, vf = L.launcher_point(G2) - sh, free - sh
        lg, lfl = vg.length, vf.length
        dg, dfr = vg.normalized(), vf.normalized()
        dirv = dg.slerp(dfr, w) if dg.dot(dfr) > -0.95 else dg.lerp(dfr, w)
        dirv = (dirv + (Mt @ Vector((-0.45, 0.15, 0.0))) * math.sin(math.pi * w)).normalized()
        ln = lg + (lfl - lg) * w
        e = min(1.0, 3.0 * w)
        ln = max(ln, lg + (LO_R - lg) * e) if lg < LO_R else ln
        ln = min(ln, lg + (HI_R - lg) * e) if lg > HI_R else min(ln, max(lg, HI_R))
        tgt = sh + dirv * ln
        L.left_hand_to(point=tgt, elbow_away=(-0.4, -1.0, -0.2))
        info["left"] = L.left_hand_to(point=tgt, elbow_away=arm_away("Left", (p["lex"], p["ley"], p["lez"])))
        # never let the letting-go arm lock straight (the grip races away during the shove): keep the
        # shoulder->wrist line under 0.9 of full reach so the elbow stays bent (no straight/bent flip)
        for _ in range(3):
            lr = (L.joint("LeftHand") - sh).length / REACH
            if lr <= 0.9:
                break
            ln *= 0.9 / lr
            tgt = sh + dirv * ln
            L.left_hand_to(point=tgt, elbow_away=(-0.4, -1.0, -0.2))
            info["left"] = L.left_hand_to(point=tgt, elbow_away=arm_away("Left", (p["lex"], p["ley"], p["lez"])))
    info["gap"] = round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 3)
    info["rr"] = round((L.joint("RightHand") - L.joint("RightUpperArm")).length / REACH, 3)
    info["lr"] = round((L.joint("LeftHand") - L.joint("LeftUpperArm")).length / REACH, 3)
    info["lsh"] = [round(v, 2) for v in L.joint("LeftUpperArm")]
    info["g2"] = [round(v, 2) for v in L.launcher_point(G2)]
    L.head_look(target=(p["lx"] + 0.3 * a * s[0], p["ly"] + 0.3 * a * s[1], p["lz"]))
    return info


BASE = dict(yaw=10.0, lean=-4.0, tilt=-2.0, drop=0.3, back=0.14, side=0.04, wyaw=-3.0, wbend=-2.0, wroll=0.0,
            ax=0.8, ay=-1.12, az=-1.5, ayaw=13.0, aelev=-15.0, aroll=0.0, lx=-9.0, ly=-2.0, lz=-3.0,
            rfx=FEET["Right"][0], rfz=FEET["Right"][1], rlift=0.0, lfx=FEET["Left"][0], lfz=FEET["Left"][1],
            shake=0.0, rex=1.0, rey=0.5, rez=0.0, lex=1.0, ley=-1.1, lez=-0.2,
            lfree=0.0, flx=-0.55, fly=1.2, flz=0.3, bshake=1.0)
BASE.update(yaw=7.0, lean=-12.0, wyaw=-6.0, wbend=-1.0, ax=1.0, ay=-0.95, az=-1.85, ayaw=5.0, aelev=-8.0)


def P(**kw):
    d = dict(BASE)
    d.update(kw)
    return d


# ------------------------------------------------------------------ poses
def ready_params(t, T):
    ph = 2.0 * math.pi * t / T
    b = 0.5 - 0.5 * math.cos(ph)                 # one slow, deep breath per loop
    w = math.sin(ph + 0.6)                       # a barely-there sway
    h = 0.5 - 0.5 * math.cos(2.0 * ph)           # the cannon's weight re-settles twice per loop
    return P(yaw=7.0 + 1.5 * w, lean=-12.0 - 1.5 * b, tilt=-2.0 - 1.0 * w, drop=0.3 + 0.05 * b + 0.04 * h,
             side=0.04 + 0.03 * w, wbend=-2.5 - 3.0 * b, wroll=1.0 * w, wyaw=-16.0,
             ax=1.0 + 0.02 * w, ay=-0.95 - 0.05 * b - 0.1 * h, az=-1.6,
             ayaw=3.0 + 1.5 * w, aelev=-8.0 - 2.5 * b - 3.0 * h, ly=-2.2 + 0.3 * b)


def tug(ph):
    """the singularity's pull: a sharp lurch 0.12..0.28, hauled back in by 0.8 (0 at the seam)"""
    ph = ph % 1.0
    if ph < 0.12:
        return 0.0
    if ph < 0.28:
        return L.smooth((ph - 0.12) / 0.16)
    if ph < 0.8:
        return 1.0 - L.smooth((ph - 0.28) / 0.52)
    return 0.0


def charge_params(d, ph):
    g = tug(ph)
    k = 1.5 + 1.1 * d                            # lurch size
    gk = g * k
    return P(yaw=9.5 + 11.5 * d - 2.0 * gk, lean=-12.0 + 1.0 * d - 1.6 * gk, tilt=-5.0 - 5.0 * d + 3.0 * gk,
             drop=0.6 + 0.4 * d + 0.03 * g, back=0.12 + 0.08 * d, side=0.12 + 0.1 * d - 0.2 * gk,
             wyaw=-8.5 - 2.0 * d, wbend=-8.0 - 5.4 * d - 2.2 * gk, wroll=-3.0 * d,
             ax=1.0 - 0.05 * d - 0.03 * gk, ay=-1.25 - 0.2 * d - 0.05 * gk, az=-1.85 - 0.2 * d - 0.04 * gk,
             ayaw=4.0 - 12.0 * d - 0.5 * gk, aelev=2.0 - 3.5 * gk, lx=-14.0, ly=-1.8 - 0.9 * d + 1.2 * gk, lz=-1.6,
             shake=0.7 + 0.7 * d, bshake=0.5)


# ------------------------------------------------------------------ fire (keys -> Hermite, IK every frame)
def hermite(keys, f, name):
    fs = [k[0] for k in keys]
    n = len(keys)
    i = 0
    while i < n - 2 and f > fs[i + 1]:
        i += 1
    f0, f1 = fs[i], fs[i + 1]
    v0, v1 = keys[i][1][name], keys[i + 1][1][name]

    def tan(j):
        if j == 0 or j == n - 1:
            return 0.0
        return (keys[j + 1][1][name] - keys[j - 1][1][name]) / (fs[j + 1] - fs[j - 1]) * keys[j][2]

    m0, m1 = tan(i), tan(i + 1)
    h = f1 - f0
    s = (f - f0) / h
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * v0 + (s3 - 2 * s2 + s) * h * m0 + (-2 * s3 + 3 * s2) * v1 + (s3 - s2) * h * m1


def fire_params(f, keys):
    return {n: hermite(keys, f, n) for n in NAMES}


T = SPEC["Ready"]
# Fire
C0 = charge_params(1.0, 0.0)
C0["shake"] = 1.6


def FK(**kw):
    d = dict(C0)
    d.update(kw)
    return d


fire_keys = [
    (0, C0, 1.0),
    # 0.10 IMPLOSION: curl in even tighter around the cannon, pulled in, max tremble
    (3, FK(lean=-12.7, drop=1.13, wbend=-16.1, wyaw=-13.4, tilt=-11.0, ax=0.885, ay=-1.72, az=-2.2, aelev=1.0,
           side=0.24, shake=1.8, ly=-4.3, lz=-1.6), 1.0),
    # 0.20 RELEASE (FireAt): dead level down the track, the body starting to snap open
    (FIRE_FRAME, FK(yaw=16.6, lean=-9.1, drop=1.0, wbend=-12.6, wyaw=-7.6, tilt=-12.0, ax=1.07, ay=-1.385, az=-2.0, ayaw=5.0,
                    aelev=9.0, side=0.26, shake=0.0, lx=-14.0, ly=-1.5), 0.6),
    # 0.27 SHOVE: the recoil drives the cannon straight back along the barrel (toward the camera) and
    # down into the hips; the barrel stays level so the ball is seen leaving over the rim
    (8, FK(yaw=13.0, lean=-8.0, drop=0.85, back=0.18, tilt=-12.5, side=0.40, wyaw=-9.0, wbend=-6.0, wroll=-2.0,
           ax=1.42, ay=-1.6, az=-1.85, ayaw=5.0, aelev=3.0, shake=0.0, lx=-12.0, ly=-0.5, lz=-2.3,
           rfx=1.0, rfz=0.45, rlift=0.15), 1.0),
    # 0.33 BLOWN BACK: the torso starts to go, the barrel swings LEFT (toward the back) before it flips up
    (10, FK(yaw=13.3, lean=5.7, drop=0.6, back=0.18, tilt=-19.5, side=0.5, wyaw=-15.4, wbend=1.7, wroll=-8.0,
            ax=1.55, ay=-1.3, az=-1.45, ayaw=-30.0, aelev=12.0, shake=0.0, lx=-8.0, ly=2.7, lz=-2.3,
            rex=0.58, rey=0.53, rez=0.16, lex=1.0, ley=-1.1, lez=-0.47,
            rfx=1.2, rfz=0.52, rlift=0.3), 1.0),
    # 0.43 PEAK: arms + cannon flung up high over the right shoulder, head snapped back, the step lands
    (13, FK(yaw=10.0, lean=20.0, drop=0.05, back=0.18, tilt=-11.7, side=0.45, wyaw=-27.2, wbend=24.0, wroll=-16.2,
            ax=1.52, ay=0.8, az=0.15, ayaw=-66.0, aelev=50.0, shake=0.0, lx=-5.0, ly=10.0, lz=-2.0,
            rex=0.87, rey=0.22, lex=0.85, ley=-0.35, lez=-1.14,
            aroll=-27.4, rez=0.65, rfx=1.45, rfz=0.6, rlift=0.0), 0.5),
    # 0.63 shaky hang, still reeling, torso bent far back
    (19, FK(yaw=5.0, lean=14.7, drop=0.1, back=0.0, tilt=-19.2, side=0.35, wyaw=-23.0, wbend=35.5, wroll=-14.1,
            ax=1.36, ay=0.85, az=0.05, ayaw=-62.0, aelev=42.0, shake=0.5, lx=-8.0, ly=9.6, lz=-2.5,
            rex=0.58, rey=0.17, lex=0.66, ley=-1.24, lez=-0.25,
            aroll=-38.9, rez=-0.8, rfx=1.45, rfz=0.6), 1.0),
    # 0.77 the cannon swings down OUTSIDE the right shoulder (clear of the chest), still reeling
    (23, FK(yaw=-0.75, lean=-1.3, drop=0.4, back=0.18, tilt=-9.6, side=0.38, wyaw=-19.5, wbend=3.8, wroll=-4.1,
            ax=1.69, ay=0.25, az=-0.84, ayaw=-22.8, aelev=18.0, shake=0.6, lx=-9.0, ly=3.5, lz=-2.8,
            rex=2.74, rey=1.5, rez=0.0, lex=0.87, ley=-1.1, lez=-0.72,
            aroll=-19.5, rfx=1.45, rfz=0.6), 1.0),
    # 0.93 recovering: torso still back while the cannon comes down in front, then weight forward
    (28, FK(yaw=9.4, lean=-8.8, drop=0.42, back=0.18, tilt=-8.0, side=0.3, wyaw=-14.7, wbend=0.2, wroll=0.0,
            ax=1.0, ay=-0.81, az=-1.5, ayaw=5.0, aelev=-2.0, shake=0.35, lx=-10.0, ly=0.0, lz=-3.0,
            rfx=1.45, rfz=0.6), 1.0),
    # 1.17 step back in (right foot lifts and returns)
    (35, FK(yaw=9.2, lean=-10.4, drop=0.36, back=0.16, tilt=-4.0, side=0.12, wyaw=-9.4, wbend=-3.4, wroll=0.0,
            ax=0.95, ay=-0.96, az=-1.62, ayaw=2.0, aelev=-9.0, shake=0.0, lx=-9.0, ly=-2.0, lz=-3.0,
            rfx=1.15, rfz=0.5, rlift=0.22), 1.0),
    (41, dict(ready_params(0.0, T)), 1.0),
    (48, dict(ready_params(0.0, T)), 1.0),
]
# in-between keys (sampled from the curve, then tuned: left-hand reach, cannon clear of the head/arms)
# the LEFT hand lets go after the shove, is flung up above the head at the peak and re-grabs Grip2 by 0.93 s
FREE_POLE = dict(lex=1.0, ley=0.0, lez=0.1)
LFREE = {6: dict(lfree=0.0),
         8: dict(lfree=0.35),
         10: dict(lfree=0.6, **FREE_POLE),
         13: dict(lfree=1.0, flx=-0.55, fly=1.2, flz=0.3, **FREE_POLE),
         19: dict(lfree=1.0, flx=-0.75, fly=0.95, flz=0.2, **FREE_POLE),
         23: dict(lfree=0.6, flx=-0.85, fly=0.3, flz=-0.3, lex=1.0, ley=-0.3, lez=0.0),
         28: dict(lfree=0.0)}
for _f, _p, _t in fire_keys:
    if _f in LFREE:
        _p.update(LFREE[_f])
FIX = {16: dict(aroll=-44.0, rex=0.1, rey=0.04, rez=-0.38, wyaw=-26.0, wroll=-20.4,
                wbend=27.6, lean=19.5, tilt=-17.2),
       25: dict(rex=1.62, rey=1.21, rez=0.35, lex=2.07, ley=-1.27, lez=-0.13, wyaw=-19.2, wroll=-1.6, wbend=12.5,
                lean=-13.5, tilt=-9.0, ax=1.3, ay=0.04, az=-1.49, ayaw=-9.8, ly=0.63, lz=-2.89)}
FIX2 = {14: dict(aroll=-31.4, rex=0.75, rey=-0.03, rez=0.3, wyaw=-31.3, wroll=-18.6,
                 wbend=23.8, lean=21.0, tilt=-15.2)}                         # second pass: sampled from the curve incl. 16 / 25


def add_keys(keys, fix):
    new = []
    for f, d in sorted(fix.items()):
        p = fire_params(f, keys)
        p.update(d)
        new.append((f, p, 1.0))
    return sorted(keys + new, key=lambda k: k[0])


fire_keys = add_keys(add_keys(fire_keys, FIX), FIX2)
# ------------------------------------------------------------------ clips
report["grip_probe"] = pose(charge_params(0.5, 0.0), max_wrist=25.0)
GRIP = L.get_rot("Launcher").copy()

# Ready
T = SPEC["Ready"]
N = int(round(T * 30))
clip("Ready")
for f in range(0, N, 2):
    info = pose(ready_params(f / 30.0, T))
    if f in (0, 36):
        report["ready%d" % f] = info
    diag("Ready", info)
    kf(f)
pose(ready_params(0.0, T)); kf(N)
L.make_cyclic("Ready")

# ChargeLo / ChargeHi: same rhythm, Hi deeper, bigger lurch, faster tremble
TC = SPEC["ChargeLo"]
NC = int(round(TC * 30))
for kind, depth, freqs in (("ChargeLo", 0.0, (4.0, 6.0)), ("ChargeHi", 1.0, (6.0, 9.0))):
    clip(kind)
    for f in range(NC):
        t = f / 30.0
        info = pose(charge_params(depth, t / TC), shake_at(t / TC, freqs))
        if f in (0, 7):
            report["%s_%d" % (kind, f)] = info
        diag(kind, info)
        kf(f)
    pose(charge_params(depth, 0.0), shake_at(0.0, freqs)); kf(NC)
    L.make_cyclic(kind)

FN = int(round(SPEC["Fire"] * 30))
clip("Fire")
for f in range(FN + 1):
    p = fire_params(f, fire_keys)
    p["rlift"] = max(0.0, p["rlift"])
    p["shake"] = max(0.0, p["shake"])
    info = pose(p, shake_at(f / 30.0, (5.0, 7.0)))
    for kf_, nm in ((3, "implode"), (FIRE_FRAME, "release"), (8, "shove"), (10, "blown"), (13, "peak"), (15, "p15"), (19, "hang"), (23, "down"), (28, "recover"), (35, "stepin")):
        if f == kf_:
            report[nm] = info
    diag("Fire", info)
    kf(f)

for _kind, _n in (("Fire", FN), ("Ready", N), ("ChargeHi", NC), ("ChargeLo", NC)):
    L.use_clip(_kind)
    _g = []
    for _f in range(_n + 1):
        L.goto(_f / 30.0)
        _g.append("%d:%.2f" % (_f, (L.hand_cf("Left").translation - L.launcher_point(G2)).length))
    print("REPORTG", _kind, " ".join(x for x in _g if float(x.split(":")[1]) > 0.08))
    _w = []
    for _f in range(0, _n + 1, 2):
        L.goto(_f / 30.0)
        _w.append("%d:%.0f" % (_f, math.degrees(L.swing_twist(L.get_rot("RightHand"))[0].angle)))
    print("REPORTW", _kind, " ".join(x for x in _w if float(x.split(":")[1]) > 60))
for k, v in report.items():
    print("REPORTP", k, json.dumps(v))
for _k, _v in DIAG.items():
    print("REPORTD", _k, " ".join("%d:%s" % (i, s) for i, s in enumerate(_v)))
if not QUICK:
    L.finish(SPEC, OUT, extra_times=[0.1, 0.2667, 0.3, 0.3333, 0.4333, 0.6333, 0.9333, 1.1667])
