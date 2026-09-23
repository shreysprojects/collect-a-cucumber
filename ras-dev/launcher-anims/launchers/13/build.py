"""13 Pressure Cannon -- teal cannon with a pressure tank slung under the barrel.

The player stands side-on on the pad (down-track = their LEFT, away from the camera); the cannon
is carried well forward on the character's FRONT side (screen-right), muzzle turned toward the
front, so the pad camera sees the barrel side, the tank and the pumping left hand, and the head
stays behind / above the funnel.
  Ready    heavy low carry: right hand on the pistol grip, left hand on the tank; the body leans
           BACK against the load (positive lean), soft knees, big slow breathing + weight onto the
           right hip, and one knee-dip re-hoist of the cannon per loop.
  ChargeLo pressure builds: braced wide, the body shudders, the left hand pumps twice per cycle:
           a short stroke off the tank OUT toward the camera (+X, only a small lift so it never comes
           up to the face) where the pad camera sees it over the breech, then slaps back onto the tank.
  ChargeHi same rhythm, much stronger: deep knee bend (depth from the knees, not the spine), fast
           hard vibration of the whole body + cannon, higher pumps, harder slaps.
  Fire     swing the muzzle onto the track out in front of the face + sink into the brace -> still
           sighting aim -> BOOM at FireAt, the ball comes out of the muzzle -> 2-frame kick straight
           back along the barrel, hips shoved back -> the muzzle climbs -> heavy recover -> settle
           into the hip carry.
Ball: hidden until it pops out of the Muzzle.  Steam burst, steam hissing while charging.
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

LID = 13
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.5,
    "FireAt": 0.20,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "steam", "Color": [235, 245, 245], "Charge": "steam", "ChargeColor": [200, 240, 240]},
    "TwoHanded": True,
    "Notes": "pressure cannon: heavy hip carry, braced shudder + tank pumps while charging, still aim then a big up-and-back recoil snap",
}
FEET = {"Left": (-1.05, -0.45), "Right": (0.75, 0.25)}
TRACK_LOOK = (-12.0, 0.5, -1.6)
R_ELBOW = (0.3, -1.0, 0.6)
L_ELBOW = (0.3, 1.0, 0.1)      # up-ish pole = the elbow hangs down + out (to the left, under the barrel)
report = {}
AUTO_ELBOW = 1.0
from mathutils import Vector
# elbow poles to try (the library's elbow guard mirrors any pole that would roll the upper arm into the chest)
ELBOW_CANDIDATES = [Vector((x, y, z)).normalized()
                    for x in (-1.0, -0.5, 0.0, 0.5, 1.0) for y in (-1.0, -0.5, 0.0, 0.5, 1.0) for z in (-1.0, -0.5, 0.0, 0.5, 1.0)
                    if (x, y, z) != (0.0, 0.0, 0.0)]

# ------------------------------------------------------------------ helpers
def arm_depth(arms=L.AUDIT_ARMS, where=False):
    """the motion audit's arm-in-body measure for the CURRENT pose (studs): the deepest of the
    27 sample points of each arm block inside the torso / head blocks (realistic proportions)"""
    L.update()
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    worst, at = 0.0, ""
    for arm in arms:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for bd in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[bd])
                        if d > worst:
                            worst, at = d, "%s in %s" % (arm, bd)
    return (round(worst, 3), at) if where else worst


R_ARMS = ("RightUpperArm", "RightLowerArm", "RightHand")
L_ARMS = ("LeftUpperArm", "LeftLowerArm", "LeftHand")
MIN_BEND = 28.0         # Fire: the right elbow never straighter than this (the recoil must not pop a locked arm)
ARM_CLEAR = 0.12        # arm depth allowed before the elbow chooser starts paying for it
GRIP = {"q": None}      # the cannon sits rigidly in the hand: one grip rotation for every pose
LAST_ELBOW = {"e": None}  # elbow choices stick between keys (no swinging elbow between poses)


def cannon(at, yaw, elev, roll=0.0, elbow=R_ELBOW, give=25.0, auto_elbow=AUTO_ELBOW, min_bend=0.0):
    """_cannon, but a grip point out of reach is pulled toward the shoulder until the arm reaches
    it (so the carry sits as far forward as the arm allows, never a stretched / detached hand)"""
    at = Vector(at)
    info = None
    for _ in range(10):
        info = _cannon(tuple(at), yaw, elev, roll, elbow, give, auto_elbow)
        over = info.get("arm_overreach", 0.0)
        bend = math.degrees(L.get_rot("RightLowerArm").angle)
        bend = min(bend, 360.0 - bend)
        if over <= 0.01 and bend >= min_bend:
            break
        # keep the grip ~0.15 inside full reach: a locked-straight elbow pops (snaps / flips)
        sh = L.joint("RightUpperArm")
        at = at + (sh - at).normalized() * (over + 0.05)
    info["r_bend"] = round(bend, 1)
    info["at"] = tuple(round(c, 2) for c in at)
    return info


def _cannon(at, yaw, elev, roll=0.0, elbow=R_ELBOW, give=25.0, auto_elbow=AUTO_ELBOW):
    """right hand on the grip.  The cannon keeps the Ready grip, except it may shift up to
    `give` degrees toward the natural (wrist-clamped) grip, e.g. when the recoil wrenches it."""
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow)
    if GRIP["q"] is None:
        GRIP["q"] = L.get_rot("Launcher").copy()
        return info
    g0, gn = GRIP["q"], L.get_rot("Launcher").copy()
    if g0.dot(gn) < 0.0:
        gn = -gn
    d = math.degrees(g0.rotation_difference(gn).angle)
    gq = g0.slerp(gn, min(1.0, give / d)) if d > 1e-3 else g0
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow, grip_twist=gq)
    if auto_elbow > 0.0:
        # with the grip fixed the hand's frame is set by the cannon: pick the elbow direction
        # (swivel) that keeps the wrist straightest, preferring ones near the requested elbow
        e0 = Vector(elbow).normalized()
        best = None
        for e in ELBOW_CANDIDATES:
            L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=tuple(e), grip_twist=gq)
            sw, _ = L.swing_twist(L.get_rot("RightHand"))
            score = math.degrees(sw.angle) + 25.0 * auto_elbow * (1.0 - e.dot(e0))
            score += 400.0 * max(0.0, arm_depth(R_ARMS) - ARM_CLEAR)
            if LAST_ELBOW["e"] is not None:
                score += 40.0 * (1.0 - e.dot(LAST_ELBOW["e"]))
            if best is None or score < best[0]:
                best = (score, e)
        info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=tuple(best[1]), grip_twist=gq)
        info["elbow"] = tuple(round(c, 2) for c in best[1])
        LAST_ELBOW["e"] = best[1]
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    info["wrist_swing"] = round(math.degrees(sw.angle), 1)
    info["grip_vs_ready"] = round(min(d, give), 1)
    return info


PREV = {}


def key(frame):
    """L.key with every bone's quaternion kept in one hemisphere (no long-way spins)"""
    if os.environ.get("PROBE_ONLY"):
        ov = launcher_overlaps(margin=0.05, where=True)
        ov = {k: v for k, v in ov.items() if k in ("Head", "UpperTorso", "LeftUpperArm", "RightUpperArm",
                                                    "RightUpperLeg", "LeftUpperLeg", "LowerTorso")}
        if ov:
            print("REPORT_KEY", frame, ov)
    if os.environ.get("ARM_DEBUG"):
        print("REPORT_ARM", L.rig().animation_data.action.name if L.rig().animation_data and L.rig().animation_data.action else "?", frame,
              arm_depth(R_ARMS, where=True), arm_depth(L_ARMS, where=True),
              "Lbend %.0f Ldist %.2f" % (math.degrees(L.get_rot("LeftLowerArm").angle), (L.joint("LeftHand") - L.joint("LeftUpperArm")).length),
              "Lup", tuple(round(c, 2) for c in L.get_rot("LeftUpperArm")))
    r = L.rig()
    for name in L.BONES:
        pb = r.pose.bones[name]
        q = pb.rotation_quaternion.copy()
        ref = PREV.get(name)
        if ref is not None and q.dot(ref) < 0.0:
            pb.rotation_quaternion = -q
        PREV[name] = pb.rotation_quaternion.copy()
    L.update()
    L.key(frame)


def body(yaw=40.0, lean=-8.0, drop=0.25, back=0.1, waist_yaw=5.0, waist_bend=-8.0, side=0.0, roll=0.0, waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def body_args(yaw, lean, drop, back, waist_yaw, waist_bend, side=0.0, roll=0.0, waist_roll=0.0):
    return dict(yaw=yaw, lean=lean, drop=drop, back=back, waist_yaw=waist_yaw, waist_bend=waist_bend,
                side=side, roll=roll, waist_roll=waist_roll)


LAST_LEFT = {"e": None}


def left(offset=(0.0, 0.0, 0.0), max_reach=None):
    """left hand on the tank; the elbow pole is chosen (near L_ELBOW, sticky between keys) so the
    left arm stays out of the chest"""
    if max_reach is not None:
        # keep the (pumping) hand well inside the arm's reach: no straight-locked elbow / flips
        g = L.launcher_point(L.load_meta(LID)["Grip2"]["pos"])
        p = g + Vector(offset)
        sh = L.joint("LeftUpperArm")
        if (p - sh).length > max_reach:
            p = sh + (p - sh).normalized() * max_reach
            offset = tuple(p - g)
    e0 = Vector(L_ELBOW).normalized()
    best = None
    ob = L.launcher_object()
    L.update()
    mw = ob.matrix_world
    vs = [L.b2r(mw @ v.co) for v in ob.data.vertices]
    vs = vs[::max(1, len(vs) // 400)]
    for e in ELBOW_CANDIDATES:
        res = L.left_hand_to(key="Grip2", elbow_away=tuple(e), offset=offset)
        fb, fh = [(b, h) for n, b, h in L.body_boxes() if n == "LeftLowerArm"][0]
        fore = max([L._depth_inside(p, fb, fh) for p in vs] + [0.0])     # forearm through the cannon
        score = 400.0 * max(0.0, arm_depth(L_ARMS) - ARM_CLEAR) + 20.0 * (1.0 - e.dot(e0))
        score += 150.0 * max(0.0, fore - 0.08)
        if LAST_LEFT["e"] is not None:
            score += 40.0 * (1.0 - e.dot(LAST_LEFT["e"]))
        if best is None or score < best[0]:
            best = (score, e)
    LAST_LEFT["e"] = best[1]
    return L.left_hand_to(key="Grip2", elbow_away=tuple(best[1]), offset=offset)


def _seg_hits_box(a, b, box, half):
    """does the segment a->b (Roblox space) pass through the box?"""
    inv = box.inverted()
    p, q = inv @ a, inv @ b
    d = q - p
    t0, t1 = 0.0, 1.0
    for i in range(3):
        if abs(d[i]) < 1e-9:
            if abs(p[i]) > half[i]:
                return False
            continue
        ta, tb = (-half[i] - p[i]) / d[i], (half[i] - p[i]) / d[i]
        if ta > tb:
            ta, tb = tb, ta
        t0, t1 = max(t0, ta), min(t1, tb)
        if t0 > t1:
            return False
    return True


def hand_visible(pt, eye=L.CAMERA_GAME[0]):
    """fraction (0..1) of a small cross of sample points around `pt` (Roblox space) that the pad
    camera sees unblocked by the launcher mesh or the head"""
    ob = L.launcher_object()
    L.update()
    mwi = ob.matrix_world.inverted()
    head = [(b, h) for n, b, h in L.body_boxes() if n == "Head"][0]
    eye = Vector(eye)
    seen, n = 0, 0
    for d in ((0, 0, 0), (0, 0.15, 0), (0, -0.15, 0), (0, 0, 0.15), (0, 0, -0.15)):
        p = Vector(pt) + Vector(d)
        o, t = mwi @ L.r2b(eye), mwi @ L.r2b(p)
        dirn = t - o
        hit = ob.ray_cast(o, dirn.normalized(), distance=dirn.length - 0.05)[0]
        blocked = hit or _seg_hits_box(eye, p, head[0], head[1])
        seen += 0 if blocked else 1
        n += 1
    return seen / n


# ------------------------------------------------------------------ poses
CARRY_Z = -1.55         # the carry sits well forward: the camera sees the barrel side + tank, the head clears the funnel
CARRY_X = 0.45          # right of centre, but close enough for the left hand to stay on the tank
CARRY_YAW = 26.0     # muzzle turned toward the character's front while holding
CARRY_ROLL = 45.0    # the cannon is canted outward (top toward the camera): valve knob + funnel lean away from the body


READY_Y = -1.05        # the carry sits low, toward the right hip / thigh


def ready_params(b, hoist=0.0, shift=0.0):
    """b 0..1 = breathing (in = chest up, cannon rises; out = the weight sags); hoist 0..1 = the
    small re-hoist (a knee dip + the cannon bumped up); shift = weight onto the right hip.
    A heavy load held in front: the body leans BACK (positive lean) to counterbalance it."""
    return {"body": body_args(-10.0, 4.0 + 2.5 * b + 2.0 * hoist, 0.42 - 0.1 * b + 0.06 * hoist, 0.02,
                              -14.0 + 1.5 * b, 2.0 + 2.0 * b + 1.0 * hoist, side=0.07 * shift, roll=-2.0 * shift),
            "at": (CARRY_X + 0.1, READY_Y + 0.22 * b + 0.1 * hoist, -1.2),
            "yaw": CARRY_YAW - 1.0 * b, "elev": -9.0 + 3.0 * b + 2.0 * hoist, "roll": CARRY_ROLL,
            "look": (-8.0, -0.5 + 0.5 * b, -3.0)}


def ready(b, hoist=0.0, shift=0.0):
    P = ready_params(b, hoist, shift)
    body(**P["body"])
    info = cannon(P["at"], yaw=P["yaw"], elev=P["elev"], roll=P["roll"], elbow=R_ELBOW)
    info["left"] = left()
    L.head_look(target=P["look"])
    measure(info)
    return info


MUZ = L.load_meta(LID)["Muzzle"]["pos"]


def measure(info):
    """where the head / shoulder / muzzle / left hand are (studs, HRP space) for tuning"""
    L.update()
    r = lambda v: tuple(round(c, 2) for c in v)
    info["m_head"] = r(L.joint("Head"))
    info["m_rsh"] = r(L.joint("RightUpperArm"))
    info["m_muz"] = r(L.launcher_point(MUZ))
    info["m_lhand"] = r(L.joint("LeftHand"))
    info["m_lsh"] = r(L.joint("LeftUpperArm"))
    info["m_lelb"] = r(L.joint("LeftLowerArm"))
    info["m_lpole"] = r(LAST_LEFT["e"]) if LAST_LEFT["e"] is not None else None


# deterministic shudder pattern (one value set per key), same for Lo and Hi
SHAKE = [(0.0, 0.0, 0.0), (0.7, -0.5, 0.3), (-0.6, 0.8, -0.4), (0.9, 0.2, -0.8), (-0.8, -0.6, 0.5),
         (0.4, 0.9, 0.7), (0.0, 0.0, 0.0), (-0.7, 0.5, -0.3), (0.6, -0.8, 0.6), (-0.9, -0.2, 0.8),
         (0.8, 0.6, -0.5), (-0.4, -0.9, -0.7)]
STEP = 2   # frames between shake keys (24-frame loop = 12 keys)


def charge(i, depth):
    """i = key index 0..11 over the loop; depth 0 = ChargeLo, 1 = ChargeHi.
    Hi gets its depth from the knees (hip drop), not from curling the spine over the funnel."""
    sx, sy, sz = SHAKE[i % len(SHAKE)]
    amp = 0.55 + 2.3 * depth           # shudder intensity (Hi much harder than Lo)
    # two pumps per loop: the left hand lifts off the tank, out toward the camera and up above the
    # barrel (keys 1-2 / 7-8) and slaps down HARD (3 / 9): the cannon dips and the body jolts
    ph = i % 6
    # the lift is capped (0.42 Lo / 0.61 Hi): the hand never comes up to the face; the rest of the
    # pump goes forward along the barrel and out toward the camera, so the raised hand shows
    # against the teal barrel / the floor and then comes down onto the tank
    lift = {0: 0.0, 1: 0.18, 2: 0.25, 3: 0.0, 4: 0.0, 5: 0.0}[ph] * (1.0 + 0.4 * depth)
    out = {0: 0.0, 1: 0.7, 2: 1.0, 3: 0.15, 4: 0.0, 5: 0.0}[ph] * (1.0 + 0.2 * depth)
    slap = 1.0 if ph == 3 else 0.0
    body(yaw=-10.0 + 3.0 * depth + 1.2 * amp * sx,
         lean=-7.0 - 1.5 * depth + 0.6 * amp * sy - 2.0 * slap,
         drop=0.45 + 0.5 * depth + 0.022 * amp * sz + 0.05 * slap,
         back=0.12 + 0.08 * depth,
         waist_yaw=-13.0 + 1.0 * amp * sz,
         waist_bend=-6.0 + 1.0 * depth + 1.2 * amp * sx - 1.5 * slap,
         roll=1.2 * amp * sy)
    at = (CARRY_X + 0.052 * amp * sx, -1.1 - 0.3 * depth + 0.052 * amp * sy - 0.18 * slap,
          CARRY_Z - 0.05 * depth + 0.045 * amp * sz)
    info = cannon(at, yaw=CARRY_YAW - 1.0 - 5.0 * depth + 1.5 * amp * sz,
                  elev=-3.0 + 3.0 * depth + 2.1 * amp * sx - 4.0 * slap,
                  roll=CARRY_ROLL - 6.0 * depth + 1.0 * amp * sy, elbow=R_ELBOW)
    fwd = L.launcher_dir((0.0, -1.0, 0.0))          # along the barrel, toward the muzzle
    fwd = (fwd + Vector((0.0, 0.0, -1.0))).normalized()   # ... and toward the front (screen-right)
    # lift a little, then forward along the barrel + out toward the camera (+X)
    info["left"] = left(offset=((0.9 + 0.05 * depth) * out, lift, (0.2 + 0.02 * depth) * out), max_reach=1.5)
    if os.environ.get("VIS_PROBE") and i in (2, 8):
        g = L.launcher_point(L.load_meta(LID)["Grip2"]["pos"])
        rows = []
        for xo in (0.5, 0.7, 0.9):
            for zo in (0.4, 0.2, 0.0):
                for lo in (0.2, 0.35, 0.5, 0.65):
                    p = g + Vector((xo, lo, zo))
                    rows.append("%.1f/%.1f/%.1f:%.1f" % (xo, lo, zo, hand_visible(p)))
        print("REPORT_VIS", depth, i, "cur", round(hand_visible(g + Vector((0.7 * out, lift, -0.4 * out))), 2), " ".join(rows))
    L.head_look(target=(TRACK_LOOK[0], TRACK_LOOK[1] + 1.2 * depth + 0.3 * amp * sy, TRACK_LOOK[2]))
    measure(info)
    return info


# ------------------------------------------------------------------ overlap probe
def launcher_overlaps(margin=0.0, where=False):
    """deepest launcher-vertex penetration per body block for the current pose (studs; margin
    grows the block, so > 0 means closer than `margin`).  where=True also gives the worst vertex
    in the launcher's pivot frame (template scale) and in the block's frame."""
    ob = L.launcher_object()
    L.update()
    mw = ob.matrix_world
    pts = [L.b2r(mw @ v.co) for v in ob.data.vertices]
    pinv = L.pivot_cf().inverted()
    out = {}
    for name, box, half in L.body_boxes():
        inv = box.inverted()
        h = half + Vector((margin, margin, margin))
        worst, wp, wq = 0.0, None, None
        for p in pts:
            q = inv @ p
            d = min(h.x - abs(q.x), h.y - abs(q.y), h.z - abs(q.z))
            if d > worst:
                worst, wp, wq = d, p, q
        if worst > 0.0:
            if where:
                lp = (pinv @ wp) / L.LAUNCHER_SCALE
                out[name] = (round(worst, 2), "L", tuple(round(c, 2) for c in lp), "B", tuple(round(c, 2) for c in wq))
            else:
                out[name] = round(worst, 2)
    return out


def probe(kinds_lengths, step=1):
    for kind, length in kinds_lengths:
        L.use_clip(kind)
        worst = {}
        n = int(round(length * L.FPS))
        for f in range(0, n + 1, step):
            L.goto(f / L.FPS)
            for bone, d in launcher_overlaps().items():
                if d > worst.get(bone, (0.0, 0))[0]:
                    worst[bone] = (d, round(f / L.FPS, 2))
            hd = launcher_overlaps(margin=0.05).get("Head")
            if hd and hd > worst.get("Head+0.05", (0.0, 0))[0]:
                worst["Head+0.05"] = (hd, round(f / L.FPS, 2))
        print("REPORT_OVERLAP", kind, {k: v for k, v in sorted(worst.items())})


# ------------------------------------------------------------------ clips
ready(0.0)                                                    # sets GRIP (the Ready grip)
L.new_clip("Ready"); PREV.clear()
report["ready0"] = ready(0.0); READY0 = L.snapshot(); READY_ELBOW = LAST_ELBOW["e"]; key(0)
report["ready1"] = ready(1.0, shift=0.6); key(24)                   # 0.8 breathe in, weight onto the right hip
report["ready_sag"] = ready(0.1, shift=1.0); key(44)                # 1.47 breathe out, the load sags
report["ready_dip"] = ready(0.0, hoist=-0.6, shift=0.8); key(50)    # 1.67 knee dip under it ...
report["ready_hoist"] = ready(0.45, hoist=1.0, shift=0.3); key(56)  # 1.87 ... and hoist it back up
ready(0.2, shift=0.1); key(64)
L.restore(READY0); key(72)
L.make_cyclic("Ready")
READY_PREV = dict(PREV)

if os.environ.get("GRIP_PROBE"):
    # where on the tank can the left hand sit without the forearm sinking into the cannon?
    ready(0.0)
    ob = L.launcher_object()
    mw = ob.matrix_world
    vs = [L.b2r(mw @ v.co) for v in ob.data.vertices]
    for ty in (-0.7, -0.95, -1.2):
        for th in range(0, 360, 30):
            for rad in (0.45, 0.55):
                pos = (rad * math.sin(math.radians(th)), ty, rad * -math.cos(math.radians(th)))
                LAST_LEFT["e"] = None
                res = L.left_hand_to(point=L.launcher_point(pos), elbow_away=L_ELBOW)
                boxes = {n: (b, h) for n, b, h in L.body_boxes()}
                ov = {}
                for arm in ("LeftLowerArm", "LeftHand"):
                    b, h = boxes[arm]
                    ov[arm] = round(max([L._depth_inside(p, b, h) for p in vs] + [0.0]), 2)
                print("REPORT_GRIP", pos and tuple(round(c, 2) for c in pos), th, res, ov,
                      arm_depth(L_ARMS, where=True), tuple(round(c, 2) for c in L.launcher_point(pos)))
    raise SystemExit

FIRST = {}
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind); PREV.clear(); PREV.update(READY_PREV)
    for i in range(12):
        r = charge(i, depth)
        if i == 0:
            FIRST[kind] = L.snapshot()
        if i in (0, 2, 3):
            report["%s_%d" % (kind, i)] = r
        key(i * STEP)
    L.restore(FIRST[kind]); key(24)
    L.make_cyclic(kind)


# ------------------------------------------------------------------ Fire
# every Fire key is an IK-solved pose; in-between keys are solved from blended parameters so
# the left hand stays on the tank while the cannon swings between very different aims
def fpose(P):
    body(**P["body"])
    info = cannon(P["at"], yaw=P["yaw"], elev=P["elev"], roll=P["roll"], elbow=P.get("elbow", R_ELBOW), give=P.get("give", 25.0), min_bend=MIN_BEND)
    info["left"] = left()
    L.head_look(target=P["look"])
    return info


def mix(a, b, t):
    if isinstance(a, dict):
        dflt = {"give": 25.0}
        return {k: mix(a.get(k, dflt.get(k)), b.get(k, dflt.get(k)), t) for k in set(a) | set(b)}
    if isinstance(a, (tuple, list)):
        return tuple(mix(x, y, t) for x, y in zip(a, b))
    return a + (b - a) * t


AIM_Z = -2.0
# 0.10 swing the muzzle onto the track out in front of the face, sink into the brace (anticipation)
BRACE = {"body": body_args(7.0, -14.0, 1.1, 0.14, -3.0, -9.0), "at": (0.32, -1.05, AIM_Z),
         "yaw": 7.0, "elev": 7.0, "roll": 12.0, "look": TRACK_LOOK}
# 0.13 - 0.20 still sighting aim ... BOOM at FireAt (frame 6)
AIM = {"body": body_args(8.0, -11.0, 0.9, 0.14, -3.0, -6.0), "at": (0.3, -0.85, AIM_Z),
       "yaw": 6.0, "elev": 22.0, "roll": 12.0, "look": TRACK_LOOK}
# 0.27 kick (2-frame snap): the cannon slams straight back along the barrel (+X), barely flips;
# the hips are shoved back, the torso rocks back, the head snaps back
KICK = {"body": body_args(5.0, 0.0, 1.03, 0.48, -7.0, -2.0, side=0.35, roll=-4.0, waist_roll=-3.0),
        "at": (0.72, -0.82, AIM_Z), "yaw": 6.0, "elev": 27.0, "roll": 10.0, "give": 28.0, "look": (-8.0, 2.5, -1.5)}
# 0.37 recoil peak: the muzzle climbs, the whole body rocks back over the rear foot
PEAK = {"body": body_args(5.0, 7.0, 0.92, 0.6, -7.0, 2.0, side=0.3, roll=-7.0, waist_roll=-5.0),
        "at": (0.8, -0.58, AIM_Z), "yaw": 6.0, "elev": 36.0, "roll": 10.0, "give": 30.0, "look": (-8.0, 5.5, -1.5)}
# 0.53 still riding the kick, low, cannon starts to drop
RIDE = {"body": body_args(5.0, -3.0, 0.7, 0.32, -5.0, -2.0, side=0.2, roll=-5.0, waist_roll=-3.0),
        "at": (0.62, -0.72, AIM_Z), "yaw": 8.0, "elev": 20.0, "roll": 14.0, "give": 28.0, "look": (-10.0, 1.5, -1.5)}
# 0.77 recover forward, weight comes back over the feet (slight overshoot down)
RECOVER = {"body": body_args(-8.0, -6.0, 0.4, 0.1, -12.0, -3.0, side=0.05), "at": (0.5, -1.1, -1.7),
           "yaw": CARRY_YAW - 4.0, "elev": -8.0, "roll": CARRY_ROLL, "look": (-10.0, 0.0, -2.0)}
# 1.03 settle (= the Ready carry, a touch lower)
SETTLE = ready_params(0.0, hoist=-0.5)                                   # a touch lower than the carry
READY_P = ready_params(0.0)

L.new_clip("Fire"); PREV.clear(); PREV.update(READY_PREV)
L.restore(FIRST["ChargeHi"]); key(0)                                  # 0.00 the ChargeHi pose
report["brace"] = fpose(BRACE); key(4)
report["aim"] = fpose(AIM); key(5)
report["fire"] = fpose(AIM); key(6)
report["kick_in"] = fpose(mix(AIM, KICK, 0.5)); key(7)                # fast-out snap (split over 2 frames)
report["kick"] = fpose(KICK); key(8)
report["peak"] = fpose(PEAK); key(11)
report["ride"] = fpose(RIDE); key(16)
fpose(mix(RIDE, RECOVER, 0.5)); key(19)
report["recover"] = fpose(RECOVER); key(23)
LAST_ELBOW["e"] = READY_ELBOW                                          # settle into the Ready arm
fpose(mix(RECOVER, SETTLE, 0.5)); key(27)
fpose(SETTLE); key(31)
fpose(mix(SETTLE, READY_P, 0.5)); key(38)
L.restore(READY0); key(45)                                             # 1.50 back to the Ready carry
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
L.set_interpolation("Fire", 'LINEAR', 'AUTO_CLAMPED', frames=[6, 7])   # 6 -> 8 = the snap


for k, v in report.items():
    print("REPORT_POSE", k, v)
probe([("Ready", SPEC["Ready"]), ("ChargeLo", SPEC["ChargeLo"]), ("ChargeHi", SPEC["ChargeHi"]),
       ("Fire", SPEC["Fire"])])
if not os.environ.get("PROBE_ONLY"):
    L.finish(SPEC, OUT, extra_times=[0.1, 0.23, 0.27, 0.37, 0.53])
if os.environ.get("DBG_SHEET"):
    # tuning aid: the charge loops at every key (2 frames apart) + Ready at 0.2 s steps, both views
    for view in ("game", "track"):
        L.render_sheet(SPEC, os.path.join(OUT, "dbg_charge_%s.png" % view), view=view,
                       kinds=["ChargeLo", "ChargeHi"], per_clip=13)
        L.render_sheet(SPEC, os.path.join(OUT, "dbg_ready_%s.png" % view), view=view,
                       kinds=["Ready"], per_clip=13)
