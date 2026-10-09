"""02 Snow Scoop -- blue dish scoop on a short claw handle, ONE-handed.

  Ready    held at the right hip, dish up and out in front, small bob + breathing; left arm easy.
  ChargeLo dip-and-scoop: the dish dips to the snow in front, pushes out along it (collecting
           snow), tilts up and lifts back to waist height.
  ChargeHi the same rhythm (same key frames) with a deep torso fold + knee bend, a longer push
           out along the snow, a heave of the loaded dish up to chest height and a small fast
           tremble while it is lifted.
           The free left hand braces on the left thigh during the dip/push (elbow down + out).
  Fire     underarm bowling toss (a pendulum): the loaded dish drops past the right leg and swings
           BACK toward the camera (0.17 s) as the body winds up to the right, sweeps low round the
           front (0.30 s), and ACCELERATES forward-and-up past the hip: the release (0.43 s) is the
           fastest part of the swing (mscale tangents; dish ~1.5 studs/frame, no 2-frame step over
           ~3 studs in the swing) -> wrist flick -> follow-through high to the front -> settle.
           The free left arm counter-balances.
  Grip + elbows are searched over the keys AND sampled in-betweens; baked in-betweens re-turn
  the elbow about the shoulder-wrist line (smoothly) where it saves wrist bend.
meta/02.json: Muzzle/Seat look changed to 20 deg above the scoop's forward axis (the ball rolls
off the front lip of the dish in an underarm toss; the original look was 59 deg up = straight
out of the top of the dish).
2026-09-23 elbow-guard pass: every arm pole goes through safe_pole (the hinge is turned continuously
so the library guard never mirrors it), both wrists are soft-limited to 1.48 studs from the shoulder
(the launcher / free hand slides in: no straight<->bent elbow flips), the charge keys give the right
elbow as a HINGE axis in the UpperTorso frame (HL; a world pole lined up with the arm in the deep
fold), pole directions are interpolated at unit length, no in-between elbow re-turn.  Backswing
raised into the game crop, ChargeHi folds more at the knees, the follow-through sweeps the dish
to the front so the ball is seen leaving it.
Method: every clip is a list of key POSES (body + pivot target + angles + elbow + free arm +
look).  In-betweens are IK-solved from Hermite-interpolated pose parameters (keyed every 1-2
frames), so the scoop follows a controlled path instead of joint slerps.  The scoop keeps ONE
fixed turn in the hand (GRIP, searched so the wrist bends as little as possible over all keys).
"""
import importlib
import math
import os
import random
import sys

from mathutils import Quaternion, Vector

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)

LID = 2
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_F = 13
SPEC = {
    "Ready": 2.0, "ChargeLo": 1.0, "ChargeHi": 1.0, "Fire": 1.5,
    "FireAt": round(FIRE_F / 30.0, 4),
    "Ball": {"show": "Charge", "start": "Seat", "grow": 0.4},
    "Fx": {"Style": "snow", "Color": [235, 245, 255], "Charge": "snow", "ChargeColor": [235, 245, 255]},
    "TwoHanded": False,
    "Notes": "snow scoop: dip-and-scoop the snow while charging, underarm bowling toss on release",
}
FEET = {"Left": (-0.75, -0.35), "Right": (0.65, 0.35)}
EL_HIP = (-0.5, 0.3, -1.0)       # elbow_away: the elbow bows AWAY from this (-> out, down, back)
EL_DIP = (-1.0, 0.45, -0.2)      # elbow out + down (bows back, not up above the shoulder)
EL_L = (0.6, 0.2, -0.6)          # free left arm: elbow out / back
LEL_BRACE = (0.4, 1.0, 0.2)      # left elbow DOWN and out while the hand braces on the thigh
TIP_R = 3.66                     # pivot -> dish lip (template 2.44 x 1.5)
GRIP = L.IDENT.copy()
BACK_AT = (1.6, -0.15, 0.3)       # Fire pendulum: pivot at the top of the backswing
SWEEP_AT = (1.3, -1.05, -0.65)     # pivot at the bottom (close to the body)
REL_AT = (-1.6, 0.35, -2.4)       # SEAT at release
SEAT = (0.0, -1.92, -0.3645666666666667)
DIAG = {}
RNG = {"Fire": 0.0, "Ready": 0.0, "ChargeLo": 0.0, "ChargeHi": 0.0}   # in-between elbow re-turn range per clip
NUM = ("yaw", "lean", "drop", "back", "wyaw", "wbend", "lyaw", "lelev")
VEC = ("at", "elbow", "lw", "lel", "look")


def P(yaw, lean, drop, back, wyaw, wbend, at, lyaw, lelev, lw, look, elbow=EL_HIP, anchor="Pivot", lel=None):
    return {"yaw": yaw, "lean": lean, "drop": drop, "back": back, "wyaw": wyaw, "wbend": wbend,
            "at": Vector(at), "lyaw": lyaw, "lelev": lelev, "anchor": anchor,
            "elbow": Vector(elbow), "lw": Vector(lw), "look": Vector(look),
            "lel": Vector(lel if lel is not None else EL_L)}


def floor_elev(h, lift=0.25):
    """launcher elevation that puts the dish lip on the snow with the pivot at height h"""
    s = (h - (L.FLOOR_Y + 0.05 + lift)) / TIP_R
    return -math.degrees(math.asin(max(-1.0, min(1.0, s))))


DBG = {}
HINGE_MIN = 0.05                 # hinge axis x (UpperTorso frame) kept >= this: never near the guard's mirror


def safe_pole(side, wrist, pole, margin=None):
    """the same elbow pole, turned (continuously, the least amount) about the shoulder-wrist line
    so the IK hinge axis stays on the outer side: the library's elbow guard (which MIRRORS a pole
    whose hinge points into the chest) then never fires, so poses never jump between frames"""
    m = HINGE_MIN if margin is None else margin
    sh = L.joint(side + "UpperArm")
    M = L.frame_of("UpperTorso")
    Mi = M.inverted()
    d = Mi @ (Vector(wrist) - sh)
    if d.length < 1e-6:
        return tuple(pole)
    t = d.normalized()
    n = t.cross(Mi @ Vector(pole))
    if n.length < 1e-4:
        return tuple(pole)
    n.normalize()
    DBG["n"] = (round(n.x, 2), round(n.y, 2), round(n.z, 2), [round(v, 2) for v in t])
    if n.x >= m:
        return tuple(pole)
    X = Vector((1.0, 0.0, 0.0))
    xp = X - X.dot(t) * t                       # the +X direction inside the hinge plane
    if xp.length < 0.2:
        return tuple(pole)
    xp.normalize()
    yp = t.cross(xp)
    # n = cos(a) xp + sin(a) yp; n.x = cos(a) * |xp_raw| ... keep the side of yp, clamp the angle
    sa = n.dot(yp)
    ca = n.dot(xp)
    kx = (X - X.dot(t) * t).length              # n.x = ca * kx
    need = min(0.999, m / kx)
    if ca < need:
        ca = need
        sa = math.copysign(math.sqrt(max(0.0, 1.0 - ca * ca)), sa if abs(sa) > 1e-6 else 1.0)
    n2 = (xp * ca + yp * sa).normalized()
    f = n2.cross(t)                             # t x (n2 x t) = n2
    return tuple(M @ f)


R_SOFT, R_MAX = 1.3, 1.48       # shoulder -> wrist: free up to R_SOFT, smoothly saturating at R_MAX
HAND_OFF = (0.0, 0.0, 0.0)


def soft_shift(d):
    """shift (toward the shoulder) that brings a shoulder->wrist vector d inside reach, smoothly"""
    D = d.length
    if D <= R_SOFT:
        return None
    w = R_MAX - R_SOFT
    Dn = R_SOFT + w * math.tanh((D - R_SOFT) / w)
    return d.normalized() * (D - Dn)


def apply(p):
    L.reset_pose()
    L.stance(hip_drop=p["drop"], hip_back=p["back"], root=L.ry(p["yaw"]) @ L.rx(p["lean"]), feet=FEET)
    L.waist(L.ry(p["wyaw"]) @ L.rx(p["wbend"]))
    at = Vector(p["at"])
    info = L.hold(tuple(at), yaw=p["lyaw"], elev=p["lelev"], anchor=p["anchor"],
                  elbow_away=tuple(p["elbow"]), grip_twist=GRIP)
    # soft reach limit: the whole launcher slides toward the shoulder so the wrist stays inside
    # full reach (a target near full reach flips the elbow straight <-> bent between frames)
    sh = L.joint("RightUpperArm")
    wr = L.joint("RightHand")
    dv = wr - sh
    s = soft_shift(dv.normalized() * (dv.length + info["arm_overreach"]))
    if s is not None:
        at = at - s
    wr2 = wr - (s if s is not None else Vector())
    pole = tuple(p["elbow"])
    if p.get("hl") is not None:
        # elbow given as the IK HINGE axis in the UpperTorso frame (well-defined for any arm
        # direction, unlike a world pole that can line up with the arm)
        M = L.frame_of("UpperTorso")
        t = (M.inverted() @ (wr2 - sh)).normalized()
        hl = Vector(p["hl"])
        nd = (hl - hl.dot(t) * t).normalized()
        pole = tuple(M @ nd.cross(t))
    pole = safe_pole("Right", wr2, pole)
    if True:
        info = L.hold(tuple(at), yaw=p["lyaw"], elev=p["lelev"], anchor=p["anchor"],
                      elbow_away=pole, grip_twist=GRIP)
    info["pole"] = [round(v, 2) for v in pole]
    info["pole_v"] = Vector(pole)
    info["n"] = DBG.get("n")
    info["reach"] = round((L.joint("RightHand") - L.joint("RightUpperArm")).length, 3)
    lw = Vector(p["lw"])
    ls = soft_shift(lw - Vector(HAND_OFF) - L.joint("LeftUpperArm"))
    if ls is not None:
        lw = lw - ls
    lo = L.arm_to("Left", tuple(lw), safe_pole("Left", lw, p["lel"]))
    info["lreach"] = round((L.joint("LeftHand") - L.joint("LeftUpperArm")).length, 3)
    info["left_over"] = round(lo[0], 3)
    L.head_look(target=tuple(p["look"]))
    sw, tw = L.swing_twist(L.get_rot("RightHand"))
    info["swing"] = round(math.degrees(sw.angle), 1)
    info["elbow_at"] = [round(v, 2) for v in L.joint("RightLowerArm")]
    info["relb"] = L.joint("RightLowerArm").y - L.joint("RightUpperArm").y
    info["low"] = p.get("low_elbow", False)
    return info


def to_pivot(p):
    """same pose with the anchor converted to the Pivot (for interpolation)"""
    if p["anchor"] == "Pivot":
        return p
    apply(p)
    q = dict(p)
    q["at"] = L.pivot_cf().translation.copy()
    f = L.launcher_dir((0.0, -1.0, 0.0))
    q["lyaw"] = math.degrees(math.atan2(-f.z, -f.x))
    q["lelev"] = math.degrees(math.asin(max(-1.0, min(1.0, f.y))))
    q["anchor"] = "Pivot"
    return q


def hermite(keys, t, cyclic_len=None):
    """keys = [(frame, pose)]: Hermite through every parameter, finite-difference tangents
    (periodic for loops, eased to zero at the ends of a one-shot clip)"""
    n = len(keys)
    i = 0
    while i < n - 2 and t > keys[i + 1][0]:
        i += 1
    (t0, a), (t1, b) = keys[i], keys[i + 1]
    h = float(t1 - t0)
    u = (t - t0) / h if h > 0 else 0.0
    if i > 0:
        tp, pp = keys[i - 1]
    elif cyclic_len:
        tp, pp = keys[-2][0] - cyclic_len, keys[-2][1]
    else:
        tp, pp = None, None
    if i + 2 < n:
        tn, pn = keys[i + 2]
    elif cyclic_len:
        tn, pn = keys[1][0] + cyclic_len, keys[1][1]
    else:
        tn, pn = None, None
    h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
    out = dict(a)
    sa, sb = a.get("mscale", 1.0), b.get("mscale", 1.0)   # per-key tangent scale (speed through the key)
    for k in NUM + VEC:
        ma = (b[k] - pp[k]) / (t1 - tp) * h * sa if pp is not None else a[k] * 0.0
        mb = (pn[k] - a[k]) / (tn - t0) * h * sb if pn is not None else a[k] * 0.0
        out[k] = a[k] * h00 + ma * h10 + b[k] * h01 + mb * h11
    if a.get("hl") is not None and b.get("hl") is not None:
        out["hl"] = a["hl"].lerp(b["hl"], h01).normalized()
    else:
        out["hl"] = None
    for k in ("elbow", "lel"):          # pole directions: keep unit length (no collapse between keys)
        if out[k].length > 1e-6:
            out[k] = out[k].normalized()
    return out


def bake(kind, keys, length_f, step=1, cyclic=False):
    keys = [(f, to_pivot(p)) for f, p in keys]
    L.new_clip(kind)
    frames = list(range(0, length_f + 1, step))
    if frames[-1] != length_f:
        frames.append(length_f)
    prev = 0.0
    for f in sorted(set(frames + [k[0] for k in keys])):
        p = tremble(kind, f, hermite(keys, float(f), length_f if cyclic else None))
        is_key = any(k[0] == f for k in keys)
        if not is_key:
            # in-betweens: turn the interpolated elbow about the shoulder-wrist line when that
            # saves a lot of wrist bend (smooth: penalised vs 0 and vs the previous frame's turn)
            base = p["elbow"].copy()
            apply(p)
            axis = (L.joint("RightHand") - L.joint("RightUpperArm")).normalized()
            best, ba = 1e9, 0.0
            a = -RNG.get(kind, 60.0)
            while a <= RNG.get(kind, 60.0) + 1e-6:
                p["elbow"] = Quaternion(axis, math.radians(a)) @ base
                c = wrist_cost(apply(p)) + 0.25 * abs(a) + 1.2 * abs(a - prev)
                if c < best:
                    best, ba = c, a
                a += 5.0
            p["elbow"] = Quaternion(axis, math.radians(ba)) @ base
            prev = ba
        else:
            prev = 0.0
        inf = apply(p)
        if inf["swing"] > 70.0:
            print("REPORT bend %s f%d swing %.0f" % (kind, f, inf["swing"]))
        L.key(f)
        if kind == "ChargeHi":
            print("REPORT hipole f%d pole %s elbow %s reach %.2f n %s" % (f, inf["pole"], [round(v, 2) for v in p["elbow"]], inf["reach"], inf.get("n")))
        if kind.startswith("Charge"):
            M = L.frame_of("UpperTorso").inverted()
            base_t = L.joint("UpperTorso")
            el = M @ (L.joint("LeftLowerArm") - base_t)
            nk = M @ (L.joint("Head") - base_t)
            if f % 3 == 0:
                print("REPORT larm %s f%d Lelbow_local-neck %.2f  Lelbow_world-neck %.2f  Relbow-Rshoulder %.2f  lov %.2f  swing %.0f" % (
                    kind, f, el.y - nk.y, L.joint("LeftLowerArm").y - L.joint("Head").y,
                    L.joint("RightLowerArm").y - L.joint("RightUpperArm").y, inf["left_over"], inf["swing"]))
        if kind == "Fire" and f <= 24:
            seat = L.launcher_point(SEAT)
            if f > 0:
                print("REPORT seat f%d %s step %.2f pole %s elbow %s" % (f, [round(v, 2) for v in seat], (seat - DIAG["prev"]).length, inf["pole"], [round(v, 2) for v in p["elbow"]]))
            DIAG["prev"] = seat.copy()
    if cyclic:
        L.make_cyclic(kind)


# ------------------------------------------------------------------ key poses
def ready(b, s, c=0.0):
    """b 0..1 breathing, s -1..1 dish bob, c -1..1 (later phase) left-arm swing + head drift"""
    return P(10.0 + 1.5 * c, -6.0 - 3.0 * b, 0.12 + 0.06 * b, 0.1, 0.0, -6.0 - 3.0 * b,
             (1.05, -0.8 + 0.12 * s, -0.55 - 0.04 * s), 82.0, 12.0 + 6.0 * s,
             (-1.3 + 0.05 * c, -0.62 + 0.04 * b, -0.15 - 0.16 * c),
             (-6.0 + 0.6 * c, 0.3 + 0.25 * s, -3.0 - 0.5 * c))


def lifted(d):
    return P(10.0, -8.0 + 3.0 * d, 0.18 + 0.1 * d, 0.1, 0.0, -8.0 + 2.0 * d,
             (1.05, -0.74 + 0.44 * d, -0.62 - 0.12 * d), 82.0, 14.0 + 24.0 * d,
             (-1.35, -0.55 + 0.1 * d, -0.2), (0.6, -1.0 + 0.6 * d, -4.0))


def dip(d):
    """dish lands on the snow in front"""
    h = -1.1 - 0.42 * d
    p = P(12.0, -20.0 - 14.0 * d, 0.3 + 0.5 * d, 0.15 + 0.22 * d, 0.0, -12.0 - 12.0 * d,
          (1.1, h, -0.7 - 0.35 * d), 86.0, floor_elev(h, 0.25 + 0.08 * d),
          (-0.85, -1.35 - 0.35 * d, -0.85 - 0.3 * d), (0.9, -3.0, -3.8), elbow=EL_DIP, lel=LEL_BRACE)
    p["span"] = 60.0
    return p


def push(d):
    """dish pushes out along the snow, collecting it; the free hand braces on the left thigh"""
    h = -1.22 - 0.45 * d
    p = P(13.0, -24.0 - 14.0 * d, 0.34 + 0.52 * d, 0.18 + 0.22 * d, 0.0, -14.0 - 10.0 * d,
          (1.1, h, -1.05 - 1.15 * d), 86.0, floor_elev(h, 0.25 + 0.08 * d),
          (-0.85, -1.45 - 0.35 * d, -0.95 - 0.3 * d), (0.9, -3.0, -4.4 - 0.4 * d), elbow=EL_DIP, lel=LEL_BRACE)
    p["span"] = 60.0
    return p


def scoop_up(d):
    """wrist tilts the loaded dish up and the arm lifts it off the snow"""
    return P(11.0, -14.0 - 4.0 * d, 0.26 + 0.2 * d, 0.13 + 0.05 * d, 0.0, -10.0 - 2.0 * d,
             (1.05, -0.95 + 0.15 * d, -0.85 - 0.1 * d), 84.0, 6.0 + 10.0 * d,
             (-1.1, -0.95 - 0.2 * d, -0.6 - 0.15 * d), (0.9, -1.8, -3.6), lel=(0.5, 1.0, 0.0))


def f_drop():
    """0.13 the loaded dish drops out of the charge pose, swinging down past the right leg"""
    p = P(-6.0, -13.0, 0.38, 0.2, -4.0, -9.0, (1.3, -0.7, -0.5), 122.0, -8.0,
          (-1.35, -0.2, -0.7), (0.5, -2.5, -3.5), elbow=(-1.0, 0.1, -0.4))
    p["span"] = 100.0
    return p


def f_back():
    """0.23 wind-up: body turns right, the loaded dish swings BACK low beside the right leg
    (toward the camera) -- the top of the pendulum"""
    p = P(-22.0, -12.0, 0.42, 0.2, -9.0, -8.0, BACK_AT, 152.0, 12.0,
          (-1.3, -0.1, -0.85), (1.5, -2.2, -3.5), elbow=(-1.0, 0.2, -0.4))
    p["span"] = 100.0
    return p


def f_sweep():
    """0.33 bottom of the pendulum: the dish skims low round the front, body unwinding"""
    p = P(0.0, -14.0, 0.45, 0.2, -4.0, -9.0, SWEEP_AT, 115.0, -12.0,
          (-1.4, -0.3, 0.1), (-4.0, -1.5, -3.0), elbow=(-1.0, 0.3, 0.1))
    p["mscale"] = 0.85
    return p


def f_release_():
    """0.43 RELEASE (FireAt): body turned toward the track, the arm swinging forward-and-up past
    the hip, dish tipped up the track"""
    return P(25.0, -12.0, 0.24, 0.1, 0.0, -7.0, REL_AT, 7.0, 28.0,
             (-1.3, 0.1, 0.8), (-10.0, 0.5, -2.0), elbow=(-1.0, 0.5, -0.1), anchor="Seat")


def f_release():
    p = f_release_()
    p["mscale"] = 1.5           # the release is the fastest point of the swing
    p["span"] = 35.0            # keep the elbow LOW (a hanging underarm arm) so it does not hide the dish
    return p


def f_flick():
    """0.53 wrist flick: the emptied dish keeps rising after the ball"""
    p = P(38.0, 0.0, 0.2, 0.05, 7.0, 2.0, (0.6, 0.3, -2.0), 30.0, 42.0,
          (-1.25, 0.0, 0.85), (-10.0, 1.2, -1.8), elbow=(-0.8, 0.6, 0.1))
    p["span"] = 100.0
    return p


def f_follow():
    """0.70 follow-through: the scoop keeps rising, kept to the character's front"""
    return P(43.0, 2.0, 0.15, 0.0, 8.0, 4.0, (0.55, 0.45, -2.05), 52.0, 45.0,
             (-1.2, -0.1, 0.9), (-10.0, 2.0, -1.5), elbow=(-0.7, 0.7, 0.2))


def f_lower():
    """0.97 lowering back toward the hip"""
    return P(24.0, -4.0, 0.12, 0.1, 4.0, -4.0, (1.0, -0.75, -0.8), 65.0, 8.0,
             (-1.32, -0.55, -0.05), (-8.0, 0.0, -2.0))


HL = [(0.85, 0.52, 0.0), (0.65, 0.6, 0.4), (0.37, 0.57, 0.74), (0.84, 0.51, 0.21), (0.85, 0.52, 0.0)]


def charge_keys(d):
    top = lifted(d)
    keys = [(0, top), (9, dip(d)), (15, push(d)), (22, scoop_up(d)), (30, top)]
    for (_, p), hl in zip(keys, HL):
        p["hl"] = Vector(hl).normalized()
    for _, p in keys:
        p["low_elbow"] = True
    return keys


CH = {0: charge_keys(0.0), 1: charge_keys(1.0)}
READY_KEYS = []
for f in range(0, 60, 10):
    ph = f / 60.0 * 2.0 * math.pi
    READY_KEYS.append((f, ready(0.5 - 0.5 * math.cos(ph), math.sin(ph), math.sin(ph - 1.6))))
READY_KEYS.append((60, READY_KEYS[0][1]))
FIRE_LEN = 45
FIRE_KEYS = [(0, CH[1][0][1]), (3, f_drop()), (5, f_back()), (9, f_sweep()), (FIRE_F, f_release()), (16, f_flick()),
             (22, f_follow()), (33, f_lower()), (FIRE_LEN, READY_KEYS[0][1])]


def tremble(kind, f, p):
    """ChargeHi only: a small fast shake (3-frame period, closes on the 30-frame loop) while the
    loaded dish is heaved up (scoop_up -> lifted, frames ~18..30 and 0..6)"""
    if kind != "ChargeHi":
        return p
    g = ((f - 26.0 + 15.0) % 30.0) - 15.0
    env = math.cos(math.pi * g / 20.0) ** 2 if abs(g) < 10.0 else 0.0
    if env <= 0.0:
        return p
    q = dict(p)
    w = 2.0 * math.pi * f / 3.0
    q["wyaw"] = p["wyaw"] + 1.5 * env * math.sin(w)
    q["at"] = p["at"] + Vector((0.0, 0.03 * env * math.sin(w + 1.3), 0.02 * env * math.cos(w)))
    return q
ALL = [p for _, p in READY_KEYS[:6]] + [p for _, p in CH[0][:4]] + [p for _, p in CH[1][:4]] + \
      [p for _, p in FIRE_KEYS[1:8]]


# ------------------------------------------------------------------ grip + elbow search
def twist_pen(tw):
    t = math.degrees(tw.angle)
    if t > 180.0:
        t = 360.0 - t
    return max(0.0, t - 95.0) * 2.0


def wrist_cost(info):
    sw, tw = L.swing_twist(L.get_rot("RightHand"))
    low = 150.0 * max(0.0, info["relb"] + 0.05) if info.get("low") else 0.0   # charge: elbow stays below the shoulder
    return math.degrees(sw.angle) + twist_pen(tw) + 100.0 * info["arm_overreach"] + low


def actual(Q):
    global GRIP
    GRIP = Q
    return max(wrist_cost(apply(p)) for p in ALL)


def global_grip(rnd):
    """the fixed grip turn Q that keeps the worst wrist bend over all key poses smallest:
    prediction-based global search, the best 12 re-solved for real"""
    global GRIP
    G = L.G_GRIP().to_3x3().to_quaternion()
    GRIP = L.IDENT.copy()
    need = []
    for p in ALL:
        apply(p)
        need.append(L.get_rot("RightHand").copy())

    def predicted(Q):
        worst = 0.0
        for R in need:
            sw, tw = L.swing_twist(R @ G @ Q.inverted() @ G.inverted())
            worst = max(worst, math.degrees(sw.angle) + twist_pen(tw))
        return worst

    cands = []
    for _ in range(5000):
        u1, u2, u3 = rnd.random(), rnd.random(), rnd.random()
        q = Quaternion((math.sqrt(1 - u1) * math.sin(2 * math.pi * u2), math.sqrt(1 - u1) * math.cos(2 * math.pi * u2),
                        math.sqrt(u1) * math.sin(2 * math.pi * u3), math.sqrt(u1) * math.cos(2 * math.pi * u3)))
        cands.append((predicted(q), q))
    cands.sort(key=lambda c: c[0])
    best, bq = 1e9, None
    for _, q in cands[:12]:
        c = actual(q)
        if c < best:
            best, bq = c, q
    GRIP = bq
    return best


def local_grip(rnd, iters, step=12.0):
    global GRIP
    bq = GRIP.copy()
    best = actual(bq)
    for _ in range(iters):
        ax = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1))).normalized()
        q = (Quaternion(ax, math.radians(rnd.uniform(0, step))) @ bq).normalized()
        c = actual(q)
        if c < best:
            best, bq = c, q
        else:
            step = max(1.0, step * 0.97)
    GRIP = bq
    return best


def opt_elbows(span_all=70.0):
    """(Fire drop/back keys: span 100)"""
    """turn each key pose's elbow about the shoulder-wrist line (within +-span deg of the
    authored direction) to the least wrist bend"""
    for p in ALL:
        if p.get("hl") is not None:
            continue
        if "elbow0" not in p:
            p["elbow0"] = p["elbow"].copy()
        base = p["elbow0"]
        span = p.get("span", span_all)
        p["elbow"] = base.copy()
        apply(p)
        axis = (L.joint("RightHand") - L.joint("RightUpperArm")).normalized()
        best, be = 1e9, base
        a = -span
        while a <= span + 1e-6:
            e = Quaternion(axis, math.radians(a)) @ base
            p["elbow"] = e
            c = wrist_cost(apply(p)) + 0.3 * abs(a)
            if c < best:
                best, be = c, e
            a += 10.0
        p["elbow"] = be


L.new_clip("Probe")


def in_betweens():
    """interpolated poses between the keys where the wrist is most at risk: the grip + elbow
    search also scores these so the baked in-betweens do not bend the wrist past the keys"""
    out = []
    for keys, frames, cyc in ((FIRE_KEYS, (1, 2, 4, 6, 7, 8, 10, 11, 12, 14, 15), None),
                              (CH[0], (4, 6, 12, 18, 26), 30), (CH[1], (4, 6, 12, 18, 26), 30)):
        pk = [(f, to_pivot(p)) for f, p in keys]
        out += [hermite(pk, float(t), cyc) for t in frames]
    return out


ALL += in_betweens()
RND = random.Random(2)
print("REPORT grip global %.1f" % global_grip(RND))
print("REPORT grip local %.1f" % local_grip(RND, 70))
opt_elbows()
print("REPORT after elbows %.1f" % actual(GRIP))
print("REPORT grip local2 %.1f" % local_grip(RND, 50, 6.0))
opt_elbows()
print("REPORT final worst %.1f  grip angle %.1f" % (actual(GRIP), math.degrees(GRIP.angle)))
_cs = sorted(((wrist_cost(apply(p)), i) for i, p in enumerate(ALL)), reverse=True)[:6]
print("REPORT worst ALL idx (n=%d): %s" % (len(ALL), [(round(c), i) for c, i in _cs]))
report = {}
for name, p in (("ready", ready(0, 0)), ("dipHi", CH[1][1][1]), ("pushHi", CH[1][2][1]), ("pushLo", CH[0][2][1]),
                ("scoopHi", CH[1][3][1]), ("drop", FIRE_KEYS[1][1]), ("back", FIRE_KEYS[2][1]), ("sweep", FIRE_KEYS[3][1]),
                ("release", FIRE_KEYS[4][1]), ("flick", FIRE_KEYS[5][1]), ("follow", FIRE_KEYS[6][1]), ("lower", FIRE_KEYS[7][1])):
    report[name] = apply(p)
    report[name]["pivot"] = [round(v, 2) for v in L.pivot_cf().translation]

# ------------------------------------------------------------------ clips
_p0 = dict(CH[1][0][1])            # Fire starts on the ChargeHi top pose, with its elbow as a plain pole
_p0["elbow"] = apply(_p0)["pole_v"]
_p0["hl"] = None
FIRE_KEYS[0] = (0, _p0)
bake("Ready", READY_KEYS, 60, step=5, cyclic=True)
bake("ChargeLo", CH[0], 30, step=2, cyclic=True)
bake("ChargeHi", CH[1], 30, step=1, cyclic=True)
bake("Fire", FIRE_KEYS, FIRE_LEN, step=1)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

PREVQ = []


def diag(kind, length, arm_lim=0.15, l_lim=0.1):
    """per-frame version of the library's motion audit: which frames sink an arm / the launcher,
    and the elbow bend per frame (flip hunting)"""
    n = int(round(length * 30))
    L.use_clip(kind)
    lob = L.launcher_object()
    verts = [v.co.copy() for v in lob.data.vertices]
    verts = verts[::max(1, len(verts) // 120)]
    bends = []
    for fi in range(n + 1):
        L.goto(fi / 30.0)
        boxes = {nm: (b, (Vector(L.AUDIT_SIZE[nm]) * 0.5 if nm in L.AUDIT_SIZE else h)) for nm, b, h in L.body_boxes()}
        wa, wat = 0.0, ""
        for arm in L.AUDIT_ARMS:
            ab, ah = boxes[arm]
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    for k in (-1, 0, 1):
                        pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                        for body in ("UpperTorso", "Head", "LowerTorso"):
                            d = L._depth_inside(pt, *boxes[body])
                            if d > wa:
                                wa, wat = d, "%s>%s" % (arm, body)
        wl = 0.0
        mw = lob.matrix_world
        for co in verts:
            pt = L.b2r(mw @ co)
            for body in ("UpperTorso", "Head"):
                wl = max(wl, L._depth_inside(pt, *boxes[body]))
        rb = math.degrees(L.get_rot("RightLowerArm").angle)
        lb = math.degrees(L.get_rot("LeftLowerArm").angle)
        bends.append((round(min(rb, 360 - rb)), round(min(lb, 360 - lb))))
        qs = [L.get_rot(b).copy() for b in ("RightUpperArm", "RightHand", "LeftUpperArm")]
        if fi > 0 and kind in ("Fire", "ChargeHi"):
            dd = []
            for qa, qb in zip(PREVQ, qs):
                a = math.degrees(qa.rotation_difference(qb).angle)
                dd.append(round(min(a, 360 - a)))
            print("REPORT dq %s f%d RUA/RH/LUA %s" % (kind, fi, dd))
        PREVQ[:] = qs
        if wa > arm_lim or wl > l_lim:
            print("REPORT diag %s f%d arm %.2f %s launcher %.2f" % (kind, fi, wa, wat, wl))
    print("REPORT bends %s %s" % (kind, bends))


for k, v in report.items():
    print("REPORT", k, v)
if os.environ.get("LAUNCHER_DIAG"):        # per-frame audit / joint-delta dump while tuning
    for _k in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
        diag(_k, SPEC[_k])
L.finish(SPEC, OUT, extra_times=[0.2, 0.3, 0.53, 0.7])
