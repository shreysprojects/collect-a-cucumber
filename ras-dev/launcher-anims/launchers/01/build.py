"""01 Wooden Shovel -- snow shovel: scrape the floor while charging, dig + scoop + heave on release.

The player stands side-on on the pad (down-track = their LEFT, away from the camera; the camera
sees their right side / back).  Everything happens on the character's FRONT side (screen-right)
so the pad camera sees it, and the ball then flies INTO the screen off the blade.
  Ready    shovelling stance: torso turned a little right (left shoulder toward the blade), right
           hand on the D-handle in front of the right hip, left hand on the shaft, blade resting
           ON the snow ahead of the feet, easy breathing + a small weight shift.
  ChargeLo SHOVELLING THE FLOOR: the blade edge scrapes forward along the snow and back (edge
           touching the floor on the push, a small lift on the return), steady rhythm; the
           snowball packs onto the blade.
  ChargeHi the same rhythm, deeper crouch (knees + hips, NOT a folded spine), longer harder
           pushes, a visible strain tremble.
  Fire     jab the blade into the snow -> lever the D-handle down toward the right knee (scoop,
           the loaded blade tips up and lifts, held for a beat) -> heave: the body rises and
           turns hard LEFT toward the track and both arms swing the loaded blade up to shoulder
           height, torso upright, weight onto the left (down-track) foot -> the ball leaves the
           BLADE at FireAt going down the track (blade out in front of the body, face pitched up
           toward the pad camera, clear of the head: cam_probe) -> follow-through with the raised
           blade kept on the FRONT side, off the head silhouette -> settle.
The left hand stays on the shaft (Grip2) in every clip.  The D-handle keeps ONE fixed grip in the
right fist (GRIP).

Arms vs body: the rig's upper-arm block hangs 0.5 stud OUTSIDE the shoulder-elbow line, on the
bone's local X, and launcherlib's arm IK twists that axis with elbow_away -- a bad elbow_away
buries the arm block in the chest.  Every arm here is solved with
elbow_away = rotate(torsoX x armDir, phi) and the key search picks the twist phi, the hand spot and
(on non-aim keys) a shaft yaw within +-yaw_free that brings the left hand's grip within reach,
scored by a limb-vs-torso/head box test (limb_samples: each arm block's centre line >= 0.3 stud
outside the torso / head boxes).  Grip2 (meta) sits 1.43 studs down the shaft (was 0.93: that put
both hands in front of the belly, which is what buried the arms).  Spine fold (lean + waist bend)
stays <= ~38 deg; depth comes from the knees.  The body stands turned ~48 deg right (toward the
pad camera) so the shaft can cross it from the right hip to the left hand AND the blade still lies
on the character's front side; the Fire heave swings the torso ~75 deg left to face the track.

Run:  blender.exe -b ..\\..\\LauncherAnims.blend --python build.py
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

LID = 1
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)
KEYS_ONLY = bool(os.environ.get("L01_KEYS"))

FIRE_FRAME = 13
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.0, "ChargeHi": 1.0, "Fire": 1.5,
    "FireAt": round(FIRE_FRAME / 30.0, 4),
    "Ball": {"show": "Charge", "start": "Seat", "grow": 0.35},
    "Fx": {"Style": "snow"},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "shovel: scrape the snow while charging, jab + scoop + heave the ball off the blade down the track",
}
FEET = {"Left": (-0.75, -0.45), "Right": (0.65, 0.35)}
META = L.load_meta(LID)
G2 = META["Grip2"]["pos"]
SEAT = META["Seat"]["pos"]
SHAFT = [(0.0, -0.3 * i, 0.09 * i) for i in range(1, 8)] + [META["Seat"]["pos"]]
ARM_PARTS = ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand")
GRIP = Quaternion((0.42631810903549194, 0.8503636717796326, -0.11256927251815796, -0.28716346621513367))
PHIS = (-100.0, -75.0, -50.0, -25.0, 0.0, 25.0)
L_PHIS = (-40.0, -20.0, 0.0, 20.0, 40.0)
RIGHT_LIMBS = ("RightUpperArm", "RightLowerArm", "RightHand")
LEFT_LIMBS = ("LeftUpperArm", "LeftLowerArm", "LeftHand")
CORE = ("UpperTorso", "LowerTorso", "Head")
PREV = {"el": None, "lel": None}
CUR = {"dr_min": 0.8, "dr_max": 1.5, "sw_max": 68.0}
dbg = {}


def body(yaw=0.0, lean=-20.0, drop=0.3, back=0.15, side=0.0, waist_yaw=0.0, waist_bend=-15.0, waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def gap():
    return (L.hand_cf("Left").translation - L.launcher_point(G2)).length


def arm_d(side):
    """shoulder -> wrist distance and elbow bend (deg) of one arm"""
    d = (L.joint(side + "Hand") - L.joint(side + "UpperArm")).length
    b = math.degrees(L.get_rot(side + "LowerArm").angle)
    return d, min(b, 360.0 - b)


def wrist_swing():
    sw, tw = L.swing_twist(L.get_rot("RightHand"))
    ta = math.degrees(tw.angle)
    return math.degrees(sw.angle), (360.0 - ta if ta > 180.0 else ta)


def elbow_local(side="Right"):
    Mt = L.frame_of("UpperTorso")
    return Mt.inverted() @ (L.joint(side + "LowerArm") - L.joint("UpperTorso"))


def hint(side, target, phi):
    """elbow_away that keeps the arm block on the outside (phi = extra twist about the arm)"""
    t = Vector(target) - L.joint(side + "UpperArm")
    if t.length < 1e-4:
        return Vector((0.0, -1.0, 0.0))
    t.normalize()
    x = L.frame_of("UpperTorso") @ Vector((1.0, 0.0, 0.0))
    e = x.cross(t)
    if e.length < 1e-3:
        e = Vector((0.0, 0.0, -1.0)).cross(t)
    e.normalize()
    return safe_pole(side, t, Quaternion(t, math.radians(phi)) @ e)


POLE_LIM = 0.05
LREACH_PROXY = 1.58      # |Grip2 - left shoulder| above this = the left arm locks out (wrist D ~1.5)
L_DMAX = 1.49            # left shoulder -> wrist: keep >= 0.15 inside the 1.66 full reach


def safe_pole(side, t, pole, lim=POLE_LIM):
    """turn the pole about the arm line just far enough that the library's elbow guard (which
    MIRRORS a pole whose hinge points into the body, n.x < -0.15 in the torso frame) never fires:
    a mirrored pole jumps the elbow to the other side from one frame to the next (an elbow flip)."""
    Mi = L.frame_of("UpperTorso").inverted()
    tl = Mi @ t

    def nx(p):
        n = tl.cross(Mi @ p)
        return n.x / max(n.length, 1e-6)

    if nx(pole) >= lim:
        return pole
    for k in range(4, 184, 4):
        for s in (1.0, -1.0):
            p = Quaternion(t, math.radians(s * k)) @ pole
            if nx(p) >= lim:
                return p
    return pole


def _box(bone, shrink=True):
    centre, size = L.PART_BLOCKS[bone]
    k = L.BLOCK_SHRINK.get(bone, 1.0) if shrink else 1.0
    half = Vector((size[0] * k, size[1], size[2] * k)) * 0.5
    return L.world_cf(bone) @ L.cf(Vector(centre) - Vector(L.REST[bone])), half


def limb_samples(limbs):
    """(limb, clearance) of 3 samples along each arm block's long axis vs the torso / head boxes.
    The block's CENTRE LINE must stay 0.3 outside the body (= most of the 0.8-thick block shows);
    only the upper arm's shoulder end may tuck in (0.1), as R15 shoulders always do."""
    core = [(_box(b, False), b) for b in CORE]
    out = []
    for limb in limbs:
        box, half = _box(limb)
        for s in (-0.7, 0.0, 0.7):
            need = 0.1 if (s > 0 and "UpperArm" in limb) else 0.3
            p = box @ Vector((0.0, s * half.y, 0.0))
            for (cb, ch), cn in core:
                out.append(("%s%+.1f>%s" % (limb, s, cn), L.point_box_distance(p, cb, ch) - need))
    return out


def limb_clear(limbs):
    return min(((d, w) for w, d in limb_samples(limbs)), key=lambda x: x[0])


def limb_pen(limbs):
    return sum(400.0 * max(0.0, 0.0 - d) for _, d in limb_samples(limbs))


def _place(P, fwd, up, phi, floor):
    P = Vector(P)
    info = L.place_launcher(at=P, forward=fwd, up=up, anchor="Pivot", elbow_away=hint("Right", P, phi),
                            grip_twist=GRIP)
    if floor is not None:
        dy = (L.FLOOR_Y + floor) - L.launcher_lowest_y()
        P = P + Vector((0.0, dy, 0.0))
        info = L.place_launcher(at=P, forward=fwd, up=up, anchor="Pivot", elbow_away=hint("Right", P, phi),
                                grip_twist=GRIP)
    return info, P


def right_cost(floor, prev_w=60.0):
    sw, tw = wrist_swing()
    c = 1.5 * max(0.0, sw - 30.0) + 6.0 * max(0.0, sw - CUR["sw_max"]) + 2.0 * max(0.0, tw - 80.0)
    if PREV["el"] is not None:
        c += prev_w * (elbow_local() - PREV["el"]).length
    el = L.joint("RightLowerArm")
    ce, _ = L.clearance(el, skip=ARM_PARTS)
    c += 400.0 * max(0.0, 0.15 - ce)
    c += 150.0 * max(0.0, el.y - L.joint("RightUpperArm").y + 0.1)       # no chicken wing
    c += 600.0 * max(0.0, CUR["dr_min"] - arm_d("Right")[0])                     # no fist folded onto the shoulder
    c += 600.0 * max(0.0, arm_d("Right")[0] - CUR["dr_max"])                     # nor a locked-out arm
    for p in SHAFT:
        cs, _ = L.clearance(L.launcher_point(p), skip=ARM_PARTS)
        c += 120.0 * max(0.0, 0.12 - cs)
    c += limb_pen(RIGHT_LIMBS)
    # cheap proxy for the left hand's reach to the shaft grip
    c += 1500.0 * max(0.0, (L.launcher_point(G2) - L.joint("LeftUpperArm")).length - LREACH_PROXY)
    if floor is not None:
        c += 400.0 * abs(L.launcher_lowest_y() - (L.FLOOR_Y + floor))
    return c


def left_place(phi):
    L.left_hand_to(key="Grip2", elbow_away=hint("Left", L.launcher_point(G2), phi))


def left_solve(phis, prev_w=60.0):
    best = None
    for phi in phis:
        left_place(phi)
        c = 150.0 * gap() + limb_pen(LEFT_LIMBS) + 0.2 * abs(phi) + 1500.0 * max(0.0, arm_d("Left")[0] - L_DMAX)
        if PREV["lel"] is not None:
            c += prev_w * (elbow_local("Left") - PREV["lel"]).length
        if best is None or c < best[0]:
            best = (c, phi)
    left_place(best[1])
    return best


PIVOT_A_INV = L.cf((0.0, 0.0, 0.0), L.look_frame((0.0, -1.0, 0.0), (0.0, 0.0, -1.0))).inverted()


def grip2_world(P, yaw, elev):
    """where Grip2 lands for a D-handle at P and the shaft along (yaw, elev) -- no IK needed"""
    fwd = L.direction(yaw, elev)
    M = L.cf(P, L.look_frame(fwd, L.up_for(fwd, 0.0))) @ PIVOT_A_INV
    return M @ (Vector(G2) * L.LAUNCHER_SCALE)


def best_yaw(P, yaw0, elev, free):
    """shaft yaw within +-free of yaw0 that brings Grip2 within easy reach of the left shoulder"""
    if not free:
        return yaw0
    sh = L.joint("LeftUpperArm")
    best = None
    for dy in range(-int(free), int(free) + 1, 4):
        d = (grip2_world(P, yaw0 + dy, elev) - sh).length
        c = max(d, LREACH_PROXY - 0.08) + 0.01 * abs(dy)         # turn only as far as the reach needs
        if best is None or c < best[0]:
            best = (c, yaw0 + dy)
    return best[1]


def grip_hold(P, yaw, elev, floor=None, radius=0.6, name=None, look=None, phis=PHIS, yaw_free=0.0):
    """launcher forward along (yaw, elev); the D-handle searched around P (fixed GRIP).
    floor = the blade's lowest point lands that far above the snow (None = free).
    yaw_free = the shaft may turn that many degrees to put the left hand's grip within reach."""

    def grid(centre, rad, st, plist, rad_y):
        out = []
        n = int(round(rad / st))
        ny = 0 if floor is not None else int(round(rad_y / st))
        for i in range(-n, n + 1):
            for j in range(-ny, ny + 1):
                for k in range(-n, n + 1):
                    if math.hypot(i, k) * st > rad + 1e-6:
                        continue
                    P0 = Vector(centre) + Vector((i * st, j * st, k * st))
                    fw0 = L.direction(yaw, elev)
                    _, Pf = _place(P0, fw0, L.up_for(fw0, 0.0), 0.0, floor)
                    yw = best_yaw(Pf, yaw, elev, yaw_free)
                    fw = L.direction(yw, elev)
                    upv = L.up_for(fw, 0.0)
                    for phi in plist:
                        info, Pq = _place(P0, fw, upv, phi, floor)
                        tot = Pq - Vector(P)
                        if floor is not None:
                            tot.y = 0.0
                        c = right_cost(floor) + 20.0 * tot.length + 300.0 * info["arm_overreach"] \
                            + 0.5 * abs(yw - yaw)
                        out.append((c, Pq, phi, yw))
        return out

    cand = grid(P, radius, 0.2, phis[::2], min(radius, 0.4))
    cand.sort(key=lambda x: x[0])
    seeds = []
    for c, Pq, phi, yw in cand:
        if all((Pq - s).length > 0.25 for s in seeds):
            seeds.append(Pq)
        if len(seeds) >= 3:
            break
    for s in seeds:
        cand += grid(s, 0.1, 0.1, phis, 0.1)
    cand.sort(key=lambda x: x[0])
    best = None
    for c, Pq, phi, yw in cand[:10]:                        # left arm only for the best few
        fw = L.direction(yw, elev)
        _place(Pq, fw, L.up_for(fw, 0.0), phi, None)
        cl, lphi = left_solve(L_PHIS)
        if best is None or c + cl < best[0]:
            best = (c + cl, Pq, phi, lphi, yw)
    c, Pq, phi, lphi, yaw = best
    fwd = L.direction(yaw, elev)
    up = L.up_for(fwd, 0.0)
    info, _ = _place(Pq, fwd, up, phi, None)
    left_place(lphi)
    PREV["el"] = elbow_local()
    PREV["lel"] = elbow_local("Left")
    if look is not None:
        L.head_look(target=look)
    if name:
        sw, tw = wrist_swing()
        per = {}
        for w, d in limb_samples(RIGHT_LIMBS + LEFT_LIMBS):
            if d < 0.0:
                per[w] = round(d, 2)
        dbg[name] = {"cost": round(c, 1), "P": [round(v, 2) for v in Pq], "yaw": yaw, "phi": phi, "lphi": lphi,
                     "swing": round(sw, 1), "twist": round(tw, 1), "gap": round(gap(), 3),
                     "low": round(L.launcher_lowest_y(), 3), "reach": info["arm_overreach"], "per": per,
                     "seat": [round(v, 2) for v in L.launcher_point(SEAT)],
                     "elR": [round(v, 2) for v in elbow_local()], "elL": [round(v, 2) for v in elbow_local("Left")],
                     "dL": [round(v, 2) for v in arm_d("Left")], "dR": [round(v, 2) for v in arm_d("Right")],
                     "cam": cam_probe()}
    return Pq, phi, lphi, yaw


def _screen(p):
    eye, tgt = Vector(L.CAMERA_GAME[0]), Vector(L.CAMERA_GAME[1])
    f = (tgt - eye).normalized()
    r = f.cross(Vector((0.0, 1.0, 0.0))).normalized()
    u = r.cross(f)
    d = Vector(p) - eye
    z = d.dot(f)
    return Vector((d.dot(r) / z, d.dot(u) / z)), z


def cam_probe():
    """pad-camera readability of the ball on the blade: head gap (in ball radii, screen space, + = clear),
    blade face toward the camera (|cos|), ball screen x minus head screen x (+ = ball right of head)"""
    seat = L.launcher_point(SEAT)
    sb, zb = _screen(seat)
    rb = L.BALL_RADIUS / zb
    hbox, hhalf = _box("Head", False)
    best = 9.0
    n = 4
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            for k in range(-n, n + 1):
                if max(abs(i), abs(j), abs(k)) != n:
                    continue
                q = hbox @ Vector((hhalf.x * i / n, hhalf.y * j / n, hhalf.z * k / n))
                sq, _ = _screen(q)
                best = min(best, (sq - sb).length)
    hc, _ = _screen(hbox @ Vector((0.0, 0.0, 0.0)))
    nrm = L.launcher_dir((0.0, 0.0, -1.0))
    face = abs(nrm.dot((Vector(L.CAMERA_GAME[0]) - seat).normalized()))
    return {"head_gap_r": round((best - rb) / rb, 2), "face": round(face, 2), "dx_r": round((sb.x - hc.x) / rb, 2)}


# ------------------------------------------------------------------ key poses -> dense IK frames
BODY_DEF = dict(yaw=0.0, lean=-20.0, drop=0.3, back=0.15, side=0.0, waist_yaw=0.0, waist_bend=-15.0, waist_roll=0.0)


def K(f, b, P, yaw, elev, floor=None, look=(-2.0, -2.4, -3.5), name=None, radius=0.6, yaw_free=0.0, dr_min=0.8, dr_max=1.5, sw_max=68.0):
    bb = dict(BODY_DEF)
    bb.update(b)
    return {"f": f, "b": bb, "P": Vector(P), "yaw": yaw, "elev": elev, "floor": floor,
            "look": Vector(look), "name": name, "radius": radius, "yaw_free": yaw_free, "dr_min": dr_min, "dr_max": dr_max,
            "sw_max": sw_max}


def solve_keys(keys):
    PREV["el"] = None
    PREV["lel"] = None
    for k in keys:
        if k.get("same_as") is not None:
            src = keys[k["same_as"]]
            k["Ps"], k["phi"], k["lphi"], k["yaw"] = src["Ps"], src["phi"], src["lphi"], src["yaw"]
            continue
        body(**k["b"])
        CUR["dr_min"], CUR["dr_max"], CUR["sw_max"] = k["dr_min"], k["dr_max"], k["sw_max"]
        k["Ps"], k["phi"], k["lphi"], k["yaw"] = grip_hold(k["P"], k["yaw"], k["elev"], floor=k["floor"],
                                                           radius=k["radius"], name=k["name"], look=k["look"],
                                                           yaw_free=k["yaw_free"])


def _hermite(keys, f, get, cyclic, period):
    """value at frame f through the keys (finite-difference tangents like Blender's auto handles)"""
    n = len(keys)
    fs = [k["f"] for k in keys]
    i = 0
    while i < n - 2 and f > fs[i + 1]:
        i += 1
    f0, f1 = fs[i], fs[i + 1]
    v0, v1 = get(keys[i]), get(keys[i + 1])

    def tangent(j):
        if j == 0 or j == n - 1:
            if not cyclic:
                return get(keys[j]) * 0.0
            return (get(keys[1]) - get(keys[n - 2])) / (fs[1] + period - fs[n - 2])
        return (get(keys[j + 1]) - get(keys[j - 1])) / (fs[j + 1] - fs[j - 1])

    m0, m1 = tangent(i), tangent(i + 1)
    h = f1 - f0
    s = (f - f0) / h
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * v0 + (s3 - 2 * s2 + s) * h * m0 + (-2 * s3 + 3 * s2) * v1 + (s3 - s2) * h * m1


SHAKE_PERIOD = 7.5          # frames (4 Hz; a 30-frame loop = 4 whole cycles)
DPHI = (-20.0, -10.0, 0.0, 10.0, 20.0)


def pose_at(keys, f, cyclic=False, shake=0.0):
    period = keys[-1]["f"] - keys[0]["f"]
    exact = [k for k in keys if k["f"] == f]
    if exact:
        k = exact[0]
        b, Ps, yaw, elev, floor, look, phi, lphi = (k["b"], k["Ps"], k["yaw"], k["elev"], k["floor"], k["look"],
                                                     k["phi"], k["lphi"])
    else:
        hv = lambda get: _hermite(keys, f, get, cyclic, period)
        b = {name: hv(lambda k, nm=name: k["b"][nm]) for name in BODY_DEF}
        Ps = hv(lambda k: k["Ps"])
        yaw, elev = hv(lambda k: k["yaw"]), hv(lambda k: k["elev"])
        look = hv(lambda k: k["look"])
        phi, lphi = hv(lambda k: k["phi"]), hv(lambda k: k["lphi"])
        i = max(j for j in range(len(keys)) if keys[j]["f"] <= f)
        fa, fb = keys[i]["floor"], keys[i + 1]["floor"]
        floor = None
        if fa is not None and fb is not None:
            s = (f - keys[i]["f"]) / (keys[i + 1]["f"] - keys[i]["f"])
            s = s * s * (3.0 - 2.0 * s)
            floor = fa + (fb - fa) * s
    Ps = Vector(Ps)
    if shake:                                          # full-charge strain: a quick visible tremble
        b = dict(b)
        ph = 2.0 * math.pi * f / SHAKE_PERIOD
        b["waist_roll"] += shake * 3.2 * math.sin(ph)
        b["waist_bend"] += shake * 2.0 * math.sin(2.0 * ph + 1.0)
        b["drop"] += shake * 0.05 * math.sin(ph + 2.0)
        Ps = Ps + shake * Vector((0.05 * math.sin(2.0 * ph + 0.5), 0.0, 0.05 * math.sin(ph + 1.3)))
        elev = elev + shake * 1.5 * math.sin(2.0 * ph + 2.1)
    body(**b)
    fwd = L.direction(yaw, elev)
    up = L.up_for(fwd, 0.0)
    if exact or PREV["el"] is None:
        info, P = _place(Ps, fwd, up, phi, floor)
        best_phi = phi
    else:
        best = None
        for d in DPHI:
            info, P = _place(Ps, fwd, up, phi + d, floor)
            sw, _ = wrist_swing()
            el = L.joint("RightLowerArm")
            c = 1.5 * max(0.0, sw - 35.0) + 6.0 * max(0.0, sw - 68.0) + 150.0 * (elbow_local() - PREV["el"]).length + 0.3 * abs(d)
            c += limb_pen(RIGHT_LIMBS) + 150.0 * max(0.0, el.y - L.joint("RightUpperArm").y + 0.1)
            if best is None or c < best[0]:
                best = (c, phi + d)
        best_phi = best[1]
        info, P = _place(Ps, fwd, up, best_phi, floor)
    if floor is None:
        low = L.launcher_lowest_y()
        if low < L.FLOOR_Y - 0.02:                      # never through the snow in free swings
            info, P = _place(P + Vector((0.0, L.FLOOR_Y - 0.02 - low, 0.0)), fwd, up, best_phi, None)
    if exact or PREV["lel"] is None:
        left_place(lphi)
    else:
        left_solve([lphi + d for d in DPHI], prev_w=150.0)
    L.head_look(target=look)
    PREV["el"] = elbow_local()
    PREV["lel"] = elbow_local("Left")
    return info


def build_clip(kind, keys, cyclic, shake=0.0):
    solve_keys(keys)
    if KEYS_ONLY:
        return
    L.new_clip(kind)
    PREV["el"] = None
    PREV["lel"] = None
    worst = {"gap": 0.0, "low": 9.0, "swing": 0.0, "limb": 9.0, "limb_at": None, "limb_f": None}
    for f in range(keys[0]["f"], keys[-1]["f"] + 1):
        pose_at(keys, f, cyclic, shake)
        worst["gap"] = max(worst["gap"], round(gap(), 3))
        worst["low"] = min(worst["low"], round(L.launcher_lowest_y(), 3))
        sw_now = round(wrist_swing()[0], 1)
        if sw_now > worst["swing"]:
            worst["swing"], worst["swing_f"] = sw_now, f
        for sd in ("Left", "Right"):
            dd, bb = arm_d(sd)
            if dd > worst.get("d" + sd, (0.0,))[0]:
                worst["d" + sd] = (round(dd, 3), round(bb, 1), f)
            worst["minbend" + sd] = min(worst.get("minbend" + sd, 999.0), round(bb, 1))
            worst.setdefault("bend" + sd, []).append(int(round(bb)))
            worst.setdefault("dist" + sd, []).append(round(dd, 2))
        lc, lw = limb_clear(RIGHT_LIMBS + LEFT_LIMBS)
        if lc < worst["limb"]:
            worst["limb"], worst["limb_at"], worst["limb_f"] = round(lc, 3), lw, f
        L.key(f)
    if cyclic:
        L.make_cyclic(kind)
    dbg[kind + "_frames"] = worst


# ------------------------------------------------------------------ poses
SHAFT_YAW = 62.0


def ready_key(f, b, s, name=None):
    """b 0..1 = breathing, s -1..1 = small weight shift"""
    return K(f, dict(yaw=-32.0 + 3.0 * s, lean=-18.0 - 3.5 * b, drop=0.32 + 0.07 * b, back=0.1, side=0.06 * s,
                     waist_yaw=-16.0 + 1.5 * s, waist_bend=-12.0 - 5.0 * b),
             (1.1 + 0.03 * s, -0.9, -0.7), SHAFT_YAW, -18.0 - 2.0 * b, floor=0.0,
             look=(-0.9, -2.6, -3.8 + 0.2 * b), name=name, yaw_free=32.0)


def scrape_key(f, t, depth, lift=0.0, name=None):
    """t 0 = pulled back, 1 = pushed out along the snow; depth 0..1 = charge;
    lift = the blade rides up a touch on the return stroke (push and return read differently)"""
    k = 1.5 + 0.45 * depth                                  # push length (studs)
    fwd = L.direction(56.0, 0.0)                              # along the (reach-turned) shaft
    P = (1.5 + fwd.x * k * t, -0.9 - 0.3 * depth, -0.55 + fwd.z * k * t - 0.1 * depth)
    # the body follows the push only a little (hips / turn) so the blade's travel reads on screen;
    # the shaft keeps ~one yaw through the stroke (a turning shaft slides the blade INTO the screen)
    return K(f, dict(yaw=-34.0 + (3.0 + 3.0 * depth) * t, lean=-19.0 - 1.0 * depth - (5.0 + 3.0 * depth) * t,
                     drop=0.4 + 0.45 * depth + 0.06 * t, back=0.14 + 0.18 * depth - (0.14 + 0.2 * depth) * t,
                     waist_yaw=-16.0 + (3.0 + 2.0 * depth) * t, waist_bend=-12.0 - 3.0 * t),
             P, 38.0, -16.0 + 6.0 * depth + 3.0 * lift, floor=0.02 * lift,
             look=(-1.0 - 0.5 * t, -1.7, -4.0 - 0.9 * t), name=name, yaw_free=8.0, radius=0.2)


ready_keys = [ready_key(0, 0.0, 0.0, "ready0"), ready_key(18, 1.0, 0.5, "ready1"), ready_key(36, 0.2, 1.0),
              ready_key(54, 0.9, -0.3), ready_key(72, 0.0, 0.0)]
ready_keys[-1]["same_as"] = 0
FIRE_ONLY = KEYS_ONLY and bool(os.environ.get("L01_FIRE"))
if not FIRE_ONLY:
    build_clip("Ready", ready_keys, True)

for kind, depth in (() if FIRE_ONLY else (("ChargeLo", 0.0), ("ChargeHi", 1.0))):
    ks = [scrape_key(0, 0.0, depth, 0.0, kind + "_back"), scrape_key(6, 0.35, depth),
          scrape_key(14, 1.0, depth, 0.0, kind + "_out"), scrape_key(22, 0.55, depth, 1.0, kind + "_ret"),
          scrape_key(30, 0.0, depth)]
    ks[-1]["same_as"] = 0
    build_clip(kind, ks, True, shake=depth)

fire_keys = [
    scrape_key(0, 0.5, 1.0, 0.0, "fire0"),                                       # 0.00 the charge pose
    # 0.13 JAB: drive the blade edge into the snow, knees deep, elbows tucked by the ribs
    K(4, dict(yaw=-30.0, lean=-24.0, drop=0.95, back=-0.45, waist_yaw=-12.0, waist_bend=-10.0),
      (0.85, -0.9, -2.6), 50.0, -12.0, floor=-0.08, look=(-1.6, -2.4, -5.0), name="jab", yaw_free=8.0, radius=0.3,
      dr_max=1.42),
    # 0.23 SCOOP: lever the D-handle down toward the right knee, the loaded blade tips up and lifts
    K(7, dict(yaw=-28.0, lean=-22.0, drop=1.0, back=0.3, waist_yaw=-8.0, waist_bend=-8.0),
      (1.5, -2.1, -0.6), 70.0, 10.0, floor=0.5, look=(-1.5, -1.6, -4.0), name="scoop", yaw_free=24.0, dr_max=1.28),
    # (the old 0.27 "sink" hold key was dropped: scoop -> heave in 4 frames keeps the right elbow from popping)
    # 0.40 heave under way: rising and turning, the loaded blade swung out in front of the body
    K(11, dict(yaw=-8.0, lean=-12.0, drop=0.7, back=0.12, side=-0.12, waist_yaw=-4.0, waist_bend=-2.0),
      (1.0, -0.4, -2.2), 24.0, 8.0, look=(-6.0, -0.5, -3.2), name="heave", radius=0.3, yaw_free=10.0, dr_min=1.1),
    # 0.43 HEAVE (FireAt): body rises upright and turns toward the track, the loaded blade swings up
    # out in FRONT of the body (screen-right of the head in the pad camera), the blade face pitched
    # up toward the camera under the ball -- checked by ball_visible_fraction
    K(FIRE_FRAME, dict(yaw=-2.0, lean=-8.0, drop=0.4, back=-0.15, side=-0.16, waist_yaw=0.0, waist_bend=0.0),
      (0.8, 0.0, -2.2), 12.0, 16.0, look=(-9.0, 0.8, -2.6), name="fling", radius=0.25, dr_min=0.95),
    # 0.63 follow-through: the blade keeps rising toward the track on the FRONT side, off the head
    K(19, dict(yaw=2.0, lean=-5.0, drop=0.12, back=-0.1, side=-0.14, waist_yaw=2.0, waist_bend=2.0),
      (0.75, -0.1, -1.8), 22.0, 18.0, look=(-10.0, 2.0, -1.5), name="follow", dr_min=1.0),
    # 0.93 hold high, watching the ball
    K(27, dict(yaw=14.0, lean=-8.0, drop=0.2, back=0.08, waist_yaw=4.0, waist_bend=-5.0),
      (0.9, -0.3, -1.6), 25.0, 2.0, look=(-12.0, 1.0, -1.5), name="recover", yaw_free=16.0),
    # 1.23 lowering the shovel back toward the snow
    K(37, dict(yaw=-16.0, lean=-14.0, drop=0.25, back=0.12, waist_yaw=-10.0, waist_bend=-10.0),
      (1.5, -0.3, -0.6), 60.0, -8.0, look=(-3.0, -1.8, -3.4), name="lower", yaw_free=24.0, sw_max=56.0),
    ready_key(45, 0.0, 0.0),                                          # 1.50 back to Ready
]
build_clip("Fire", fire_keys, False)

if KEYS_ONLY:
    for k, v in dbg.items():
        print("REPORTK %s %s" % (k, json.dumps(v)))
    raise SystemExit(0)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')


def ball_visible_fraction(t):
    """share of the ball's silhouette the PAD camera sees (not hidden by a body block) at Fire t"""
    L.use_clip("Fire")
    L.goto(t)
    return ball_visible_now()


def ball_visible_now():
    eye = Vector(L.CAMERA_GAME[0])
    c = L.seat_point(SPEC)
    d = (c - eye).normalized()
    s1 = d.cross(Vector((0.0, 1.0, 0.0))).normalized()
    s2 = s1.cross(d).normalized()
    pts = [c] + [c + (s1 * math.cos(a) + s2 * math.sin(a)) * 0.55 for a in [i * math.pi / 4 for i in range(8)]]
    boxes = L.body_boxes()
    seen = 0
    for p in pts:
        hidden = False
        for name, box, half in boxes:
            inv = box.inverted()
            o, q = inv @ eye, inv @ p
            dv = q - o
            t0, t1 = 0.0, 1.0
            for ax in range(3):
                if abs(dv[ax]) < 1e-9:
                    if abs(o[ax]) > half[ax]:
                        t0, t1 = 1.0, 0.0
                        break
                    continue
                ta, tb = (-half[ax] - o[ax]) / dv[ax], (half[ax] - o[ax]) / dv[ax]
                t0, t1 = max(t0, min(ta, tb)), min(t1, max(ta, tb))
            if t0 < t1:
                hidden = True
                break
        seen += 0 if hidden else 1
    return round(seen / len(pts), 2)


def spine_fold(kind, frames):
    """tilt of the upper torso from upright (deg) at the given frames"""
    L.use_clip(kind)
    out = {}
    for f in frames:
        L.goto(f / 30.0)
        yv = L.frame_of("UpperTorso") @ Vector((0.0, 1.0, 0.0))
        out[f] = round(math.degrees(math.acos(max(-1.0, min(1.0, yv.y)))), 1)
    return out


dbg["ball_visible_at_fire"] = ball_visible_fraction(SPEC["FireAt"])
dbg["spine_ChargeHi"] = spine_fold("ChargeHi", [0, 7, 14, 22])
dbg["spine_Fire"] = spine_fold("Fire", [0, 4, 7, 9, 14])
for k, v in dbg.items():
    print("REPORTK %s %s" % (k, json.dumps(v)))
L.finish(SPEC, OUT, extra_times=[0.13, 0.23, 0.3, 0.37, 0.5, 0.9])
