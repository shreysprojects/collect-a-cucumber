"""22 Royal Cannon -- purple + gold cannon with a crown of spikes: a ROYAL salute of a shot.

The player stands side-on on the pad (down-track = their LEFT, away from the pad camera); the
cannon is carried on the character's FRONT side (screen-right) so the camera sees it.
  Ready    upright regal posture: chest out, chin up, the cannon carried ONE-HANDED at the RIGHT HIP
           (forearm beside the hip), barrel raised ~30 deg to the FRONT in front of the right shoulder
           (full profile to the pad camera, face clear), left fist on the left hip (akimbo);
           a slow dignified weight shift + breathing with a chin lift.
  ChargeLo FORMAL AIM: the cannon comes up off the hip and is levelled down the track at chest
           height, front (left) knee bent, left hand under the barrel, head high and level.
  ChargeHi the same aim (same grip in the fist), deeper knee bend + forward lean, braced, with a
           visible strain tremor; the head stays level.
  Fire     a readable squeeze-down (hips sink, muzzle dips) -> the shot at FireAt out of the
           muzzle -> a HEAVY kick: the cannon shoves back along the barrel toward the camera,
           weight thrown onto the rear (right) foot -> the left hand lets go and rises high above
           the head (a royal raise, arm near straight), then sweeps out and down on the FRONT side to
           an extended, palm-up "behold" just above shoulder height (chest turned to the front),
           holds with a wrist roll, and comes back down to the hip -> back to the hip carry.
           Meanwhile the cannon settles UPRIGHT (crown roll <= ~15 deg, the carry roll) into a
           weighted lowered carry at the right hip, barrel near end-on and the muzzle dipping ~27
           deg, so its crown sits below the behold hand from the pad camera.
Ball: hidden until it pops out of the Muzzle; golden smoke burst.
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
from mathutils import Vector

LID = 22
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 3.0, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.5,
    "FireAt": 0.20,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "smoke", "Color": [255, 225, 150]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "royal cannon: one-handed parade carry at the right hip (left fist on the hip), formal knee-bent aim, heavy kick onto the rear foot, then a royal raise + palm-up flourish of the left hand",
}
FEET = {"Left": (-1.05, -0.5), "Right": (0.7, 0.3)}
TRACK_LOOK = (-12.0, 1.4, -1.8)
# elbow poles: all UP-ish, so the library's elbow guard never has to mirror one (a pole that flips
# between two keys rolls the upper arm 180 deg = a one-frame snap)
R_ELBOW = (-0.3, 1.0, -0.6)
R_ELBOW_HI = (-0.6, 1.0, -0.3)   # the right elbow at full charge
L_ELBOW = (0.3, 1.0, -0.5)
META = L.load_meta(LID)
report = {}


def cannon(at, yaw, elev, roll=0.0, elbow=R_ELBOW, grip=None, give=25.0):
    """hold the cannon by its grip; grip = a Launcher-bone quaternion the cannon sits at in the
    fist (None = free).  give = how far (deg) it may turn away from `grip` if the wrist needs it."""
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow)
    if grip is None:
        return info
    g0, gn = grip, L.get_rot("Launcher").copy()
    if g0.dot(gn) < 0.0:
        gn = -gn
    d = math.degrees(g0.rotation_difference(gn).angle)
    gq = g0.slerp(gn, min(1.0, give / d)) if d > 1e-3 else g0.copy()
    info = L.hold(at, yaw=yaw, elev=elev, roll=roll, anchor="Pivot", elbow_away=elbow, grip_twist=gq)
    info["grip_vs_ref"] = round(min(d, give), 1)
    return info


def wrist_swing():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return round(math.degrees(sw.angle), 1)


PREV = {}
GUARD = {}          # side -> hinge n.x of the last arm solve (< -0.15 = the library's elbow guard mirrored it)
GUARD_LOG = []      # (clip frame, {side: n.x}) per key, printed in PROBE runs
_solve_arm = L.solve_arm


def _solve_arm_logged(side, d_local, fwd_local, guard=None):
    t = Vector(d_local)
    if t.length > 1e-6:
        n = t.normalized().cross(Vector(fwd_local))
        if n.length > 1e-4:
            GUARD[side] = tuple(round(c, 2) for c in n.normalized())
    return _solve_arm(side, d_local, fwd_local, guard)


L.solve_arm = _solve_arm_logged


def key(frame):
    """L.key with every bone's quaternion kept in one hemisphere (no long-way spins)"""
    GUARD_LOG.append((frame, dict(GUARD)))
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


def body(yaw=15.0, lean=-9.0, drop=0.25, back=0.1, waist_yaw=4.0, waist_bend=-8.0, side=0.0, roll=0.0, waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def head_level(target, level=1.0, max_yaw=80.0, max_pitch=45.0):
    """head looks at target with its crown kept upright in the WORLD (counter-rolls the torso's
    lean/roll) -- level 1 = fully level, 0 = plain head_look"""
    UT = L.frame_of("UpperTorso")
    eye = L.joint("Head") + UT @ Vector((0.0, 0.6, 0.0))
    dl = UT.inverted() @ (Vector(target) - eye)
    yaw = max(-max_yaw, min(max_yaw, math.degrees(math.atan2(-dl.x, -dl.z))))
    pitch = max(-max_pitch, min(max_pitch, math.degrees(math.atan2(dl.y, math.hypot(dl.x, dl.z)))))
    fwd = L.ry(yaw) @ L.rx(pitch) @ Vector((0.0, 0.0, -1.0))
    up_local = (UT.inverted() @ Vector((0.0, 1.0, 0.0))).lerp(Vector((0.0, 1.0, 0.0)), 1.0 - level)
    R = L.look_frame(fwd, up_local)
    L.set_rot("Head", R.to_quaternion())
    L.update()


LEFT_MAX = float(os.environ.get("LEFT_MAX", "1.86"))
LEFT_MAX_LO = float(os.environ.get("LEFT_MAX_LO", "1.91"))   # ChargeLo only: the hand stays on Grip2 (no flip there; Hi/Fire keep 1.86)
  # shoulder -> Grip2 beyond this = the arm at full stretch (elbow pops): slide the hand in


def left(offset=(0.0, 0.0, 0.0), lmax=None):
    g = L.launcher_point(META["Grip2"]["pos"])
    sh = L.joint("LeftUpperArm")
    v = sh - g
    off = Vector(offset)
    lm = LEFT_MAX if lmax is None else lmax
    if v.length > lm:
        off = off + v.normalized() * (v.length - lm)
    return L.left_hand_to(key="Grip2", elbow_away=L_ELBOW, offset=tuple(off))


def gap():
    return round((L.hand_cf("Left").translation - L.launcher_point(META["Grip2"]["pos"])).length, 3)


def head_clear():
    """left hand centre -> head centre (studs; the head box is ~0.6 half-size)"""
    UT = L.frame_of("UpperTorso")
    hc = L.joint("Head") + UT @ Vector((0.0, 0.6, 0.0))
    return round((L.hand_cf("Left").translation - hc).length, 2)


def pt(v):
    return [round(x, 2) for x in v]


# ------------------------------------------------------------------ poses
# elbow pole up-ish + a little forward: the elbow hangs at the side of the hip and the wrist stays
# ~45 deg (the old sideways pole (-0.66, 0.11, -0.2) cranked the wrist to 86 deg)
CARRY = dict(at=(1.95, -0.21, -1.18), yaw=72.0, elev=30.0, roll=13.0, elbow=(-0.3, 1.0, 0.5))


def akimbo(s=0.0, b=0.0):
    """left fist on the left hip, elbow out and a little back (the regal stance)"""
    # (arm_to mirrors elbow_away for the left arm: (1, 0, -0.4) = elbow out to the left and a bit back)
    return L.arm_to("Left", (-1.5 - 0.02 * s, -0.45 + 0.03 * b, 0.0), (1.0, 0.0, -0.4), None)


def ready(ph):
    """ph 0..1 around the loop: one slow weight shift + two breaths (chin lifts on the breath).
    The cannon rides at the RIGHT HIP in the right fist (forearm beside the hip, elbow at the side),
    barrel rising in front of the right shoulder; the left fist sits on the left hip."""
    s = math.sin(2.0 * math.pi * ph)                 # sway
    b = 0.5 - 0.5 * math.cos(4.0 * math.pi * ph)     # breathing
    body(yaw=-3.0 + 2.5 * s, lean=1.5 + 1.5 * b, drop=0.1 - 0.03 * b, back=0.03, side=0.18 * s,
         waist_yaw=-3.0 + 2.0 * s, waist_bend=3.0 + 2.5 * b, roll=2.5 * s, waist_roll=-1.5 * s)
    a = CARRY["at"]
    info = cannon((a[0] + 0.03 * s, a[1] + 0.05 * b, a[2] - 0.12 * s), yaw=CARRY["yaw"] - 2.5 * s,
                  elev=CARRY["elev"] + 2.0 * b, roll=CARRY["roll"], elbow=CARRY["elbow"],
                  grip=GRIP.get("ready", GRIP.get("aim")), give=(6.0 if "ready" in GRIP else READY_GIVE))
    info["left"] = akimbo(s, b)
    info["wrist"] = wrist_swing()
    head_level((-9.0, 3.6 + 2.4 * b, -4.0 + 1.0 * s))
    return info


N_CH = 36       # keys per charge loop (every frame, 1.2 s)
AIM_X = 0.55    # the grip sits right of the centre line so the right arm stays clear of the chest
GRIP = {}       # "ready" / per-phase charge grips (the ChargeHi fist = the ChargeLo fist)
READY_GIVE = float(os.environ.get("READY_GIVE", "15"))   # how far the hip-carry fist may turn off the aim fist (wrist relief)


def aim(i, depth):
    """i = key index over the loop; depth 0 = ChargeLo, 1 = ChargeHi"""
    th = 2.0 * math.pi * i / N_CH
    br = 0.5 - 0.5 * math.cos(th)                    # one steadying breath per loop
    sw = math.sin(th)
    # strain tremor at full charge: 6 per loop + an 8-per-loop flutter (fast, visible)
    tr = depth * (math.sin(6.0 * th) + 0.45 * math.sin(8.0 * th + 1.0)) / 1.3
    body(yaw=20.0 + 3.0 * depth + 1.0 * sw,
         lean=-6.0 - 13.0 * depth - 3.0 * br,
         drop=0.34 + 0.42 * depth + 0.04 * br + 0.02 * tr,
         back=0.06 + 0.12 * depth,
         side=-0.16 - 0.14 * depth + 0.03 * sw,      # weight onto the front (left) knee
         waist_yaw=-8.0 + 2.0 * depth,
         waist_bend=4.0 - 3.0 * depth + 1.5 * br,    # chest stays proud
         roll=1.0 * sw + 1.0 * tr)
    at = (AIM_X - 0.04 * depth, -0.85 - 0.1 * depth + 0.15 * br + 0.12 * tr, -1.55 - 0.12 * depth)
    g = GRIP.get(i) if depth > 0.0 else GRIP.get("aim")
    info = cannon(at, yaw=6.0 + 1.2 * sw + 1.0 * tr, elev=5.0 + 3.0 * br - 1.0 * depth + 2.5 * tr,
                  roll=3.5 * tr, grip=g, give=(15.0 if depth > 0.0 else 40.0),
                  elbow=tuple(a + (b - a) * depth for a, b in zip(R_ELBOW, R_ELBOW_HI)))
    if depth == 0.0:
        GRIP[i] = L.get_rot("Launcher").copy()
    info["left"] = left(lmax=(LEFT_MAX_LO if depth == 0.0 else None))
    info["wrist"] = wrist_swing()
    head_level((TRACK_LOOK[0], TRACK_LOOK[1] + 0.6 * br, TRACK_LOOK[2]))
    return info


if os.environ.get("TUNE"):                        # offline pose tuning (writes nothing)
    exec(open(os.environ["TUNE"]).read())
    raise SystemExit

# ------------------------------------------------------------------ clips
aim(0, 0.0)
GRIP["aim"] = L.get_rot("Launcher").copy()       # the fist on the cannon during the aim
ready(0.25)
GRIP["ready"] = L.get_rot("Launcher").copy()     # the fist on the cannon at the hip

L.new_clip("Ready"); PREV.clear()
NR = 12
for i in range(NR):
    r = ready(i / NR)
    if i in (0, 3, 6, 9):
        report["ready_%d" % i] = r
    key(i * 90 // NR)
ready(0.0); key(90)
L.make_cyclic("Ready")
READY_PREV = dict(PREV)

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind); PREV.clear(); PREV.update(READY_PREV)
    for i in range(N_CH):
        r = aim(i, depth)
        if i in (0, 9, 18, 27):
            report["%s_%d" % (kind, i)] = r
        key(i)
    aim(0, depth); key(N_CH)
    L.make_cyclic(kind)

g0 = GRIP[0]
report["lo_vs_ready_grip"] = round(math.degrees(GRIP["ready"].rotation_difference(g0 if GRIP["ready"].dot(g0) >= 0 else -g0).angle), 1)


def flourish_hand(p, palm, elbow=(-0.8, -0.4, 0.4)):
    e = L.left_hand_to(point=p, elbow_away=elbow, palm_toward=palm)
    return {"left": e, "hand": pt(L.hand_cf("Left").translation), "head_clear": head_clear(), "gap": gap()}


def larm(p, palm, hinge):
    """left hand to p with the elbow's hinge axis = `hinge` (UpperTorso-local, x > 0 = never
    mirrored by the elbow guard): the pole is hinge x (shoulder->p), so consecutive keys with
    similar hinges swing the arm smoothly instead of rolling the upper arm around"""
    UT = L.frame_of("UpperTorso")
    t = UT.inverted() @ (Vector(p) - L.joint("LeftUpperArm"))
    t.normalize()
    pole = UT @ Vector(hinge).normalized().cross(t)
    return flourish_hand(p, palm, elbow=tuple(pole))


FIRE_GRIP = GRIP[0]
REL_GRIP = FIRE_GRIP.slerp(GRIP["ready"] if GRIP["ready"].dot(FIRE_GRIP) >= 0 else -GRIP["ready"], 0.5)
KICK_GIVE = float(os.environ.get("KICK_GIVE", "10"))
REL_GIVE = float(os.environ.get("REL_GIVE", "12"))
LOW_GIVE = float(os.environ.get("LOW_GIVE", "18"))
KICK_ONSET = 0.65
LOW_ELBOW = tuple(float(v) for v in os.environ.get("LOW_ELBOW", "-0.6,1.0,0.2").split(","))
LOW_YAW = (14.0, 15.0, 17.0, 19.0)     # the lowered carry after the kick: ~end-on, so it never hides the flourish
LOW_ELEV = tuple(float(v) for v in os.environ.get("LOW_ELEV", "2,-18,-27,-25").split(","))     # the heavy barrel settles, muzzle dipping below the behold hand
RAISE_OFF = (0.1, 1.42, -0.5)      # left shoulder -> hand at the royal raise (truly overhead, arm near straight)
SWEEP_OFF = (0.15, 1.3, -0.75)      # halfway round the arc: up and out in front
BEHOLD_OFF = (0.3, 1.08, -1.02)        # the extended palm-up behold: out on the FRONT side, a little above the shoulder (clear of the cannon's crown)


def settle_carry(dx=0.0, dy=0.0, dz=0.0, yaw=0.0, elev=0.0, give=20.0):
    """the hip carry of Ready, offset (the settle keys reuse it; the barrel is lowered)"""
    a = CARRY["at"]
    return cannon((a[0] + dx, a[1] + dy, a[2] + dz), yaw=CARRY["yaw"] + yaw, elev=CARRY["elev"] + elev,
                  roll=CARRY["roll"], elbow=CARRY["elbow"], grip=GRIP["ready"], give=give)


L.new_clip("Fire"); PREV.clear(); PREV.update(READY_PREV)
aim(0, 1.0); key(0)                                              # 0.00 the ChargeHi pose


def look():
    """the Muzzle look as (yaw, elev) in the game's convention"""
    m = Vector(META["Muzzle"]["pos"]); lk = Vector(META["Muzzle"]["look"])
    d = (L.launcher_point(m) - L.launcher_point(m - lk)).normalized()
    return [round(math.degrees(math.atan2(-d.z, -d.x)), 1), round(math.degrees(math.asin(max(-1.0, min(1.0, d.y)))), 1)]


def reach(p, maxd=1.5):
    """clamp a left-hand target to maxd from the left shoulder in the CURRENT body pose"""
    sh = L.joint("LeftUpperArm")
    v = Vector(p) - sh
    if v.length > maxd:
        v = v.normalized() * maxd
    return tuple(sh + v)

# 0.13 SQUEEZE: hips sink deep into the brace, the muzzle dips ~10 deg (anticipation)
body(yaw=23.0, lean=-20.5, drop=1.0, back=0.2, side=-0.34, waist_yaw=-6.0, waist_bend=-2.0)
report["squeeze"] = cannon((AIM_X - 0.05, -1.14, -1.69), yaw=5.0, elev=-5.5, elbow=(-0.8, 0.6, -0.2), grip=FIRE_GRIP, give=16.0)
report["squeeze"]["left"] = left()
report["squeeze"]["look"] = look()
head_level(TRACK_LOOK); key(4)
# 0.20 FIRE: snaps back to level, dead down the track
body(yaw=23.0, lean=-19.0, drop=0.76, back=0.18, side=-0.3, waist_yaw=-6.0, waist_bend=-1.0)
report["fire"] = cannon((AIM_X - 0.05, -0.95, -1.67), yaw=4.0, elev=6.0, elbow=(-0.7, 0.8, -0.25), grip=FIRE_GRIP, give=14.0)
report["fire"]["left"] = left()
head_level(TRACK_LOOK); key(6)
S_FIRE = L.snapshot()
# 0.33 HEAVY KICK: the cannon shoves back along the barrel toward the camera (+X), climbs ~22 deg
# and swings a little to the front; hips + torso thrown onto the rear (right) foot
body(yaw=14.0, lean=-4.0, drop=0.55, back=0.14, side=0.24, waist_yaw=-12.0, waist_bend=6.0, roll=-7.0, waist_roll=-4.0)
report["kick"] = cannon((1.3, -0.62, -1.35), yaw=18.0, elev=22.0, elbow=(-0.9, 0.8, -0.3), grip=FIRE_GRIP, give=KICK_GIVE)
report["kick"]["left"] = left()
report["kick"]["gap"] = gap()
report["kick"]["look"] = look()
head_level((-10.0, 3.5, -2.0)); key(10)
# 0.23 the kick onset: 65 % of the recoil lands one frame after the shot (peak speed ON the shot)
S_KICK = L.snapshot()
L.restore(L.blend_snapshots(S_FIRE, S_KICK, KICK_ONSET)); L.key(7)
L.restore(S_KICK)


def lowered(at, yaw, elev, roll=None, give=LOW_GIVE):
    """the weighted LOWERED carry after the kick: right arm hanging at the hip, barrel ~level,
    the same fist as the hip carry"""
    return cannon(at, yaw=yaw, elev=elev, roll=CARRY["roll"] if roll is None else roll, elbow=LOW_ELBOW, grip=GRIP["ready"], give=give)


# 0.40 the left hand lets go and starts up in front of the chest; the barrel sinks off the kick
body(yaw=9.0, lean=-1.0, drop=0.42, back=0.1, side=0.18, waist_yaw=-15.0, waist_bend=5.0, roll=-5.0, waist_roll=-3.0)
report["release"] = cannon((1.48, -0.6, -1.15), yaw=20.0, elev=16.0, roll=CARRY["roll"], elbow=(-1.0, 0.6, -0.35), grip=REL_GRIP, give=REL_GIVE)
report["release"].update(larm(reach((-0.65, 1.05, -1.55)), None, (0.8, 0.35, 0.5)))
report["release"]["look"] = look()
head_level((-10.0, 3.8, -2.4)); key(12)
# 0.50 ROYAL RAISE: the arm near-straight overhead, a little to the front, palm forward;
# the cannon in the lowered carry at the hip (barrel ~level, heavy); chin up
body(yaw=4.0, lean=3.5, drop=0.16, back=0.05, side=0.12, waist_yaw=-18.0, waist_bend=6.0, roll=-3.0, waist_roll=-2.0)
report["raise"] = lowered((1.48, -0.7, -0.85), yaw=LOW_YAW[0], elev=LOW_ELEV[0])
report["raise"].update(larm(reach(tuple(L.joint("LeftUpperArm") + Vector(RAISE_OFF)), 1.52), (0.2, 0.1, -1.0), (0.22, 0.69, 0.69)))
report["raise"]["look"] = look()
head_level((-9.0, 5.0, -3.5)); key(15)
# 0.57 SWEEP: the chest turns to the front, the arm swings forward and down in front of the face-line,
# the palm turning up
body(yaw=-7.0, lean=-2.0, drop=0.15, back=0.04, side=0.08, waist_yaw=-33.0, waist_bend=-2.0, roll=-1.5)
report["sweep"] = lowered((1.62, -0.72, -0.77), yaw=LOW_YAW[1], elev=LOW_ELEV[1])
report["sweep"].update(larm(reach(tuple(L.joint("LeftUpperArm") + Vector(SWEEP_OFF)), 1.5), (0.0, 0.5, -0.85), (0.5, 0.6, 0.2)))
report["sweep"]["look"] = look()
head_level((-6.0, 3.8, -5.0)); key(17)
# 0.63 BEHOLD: chest turned to the front, a slight courtly bow, the arm almost straight out and up in
# FRONT, open palm UP -- screen-right of the head and above the lowered cannon from the pad camera
body(yaw=-16.0, lean=-6.0, drop=0.17, back=0.03, side=0.05, waist_yaw=-40.0, waist_bend=-5.0)
report["behold"] = lowered((1.76, -0.64, -0.58), yaw=LOW_YAW[2], elev=LOW_ELEV[2])
BEHOLD = tuple(L.joint("LeftUpperArm") + Vector(BEHOLD_OFF))
report["behold"].update(larm(reach(BEHOLD, 1.5), (0.0, 1.0, -0.2), (0.85, 0.35, -0.3)))
report["behold"]["look"] = look()
head_level((-4.0, 3.2, -6.0)); key(19)
# 0.87 hold, the wrist rolls (the palm turns out to the crowd); the barrel eases round to the front
body(yaw=-17.0, lean=-5.5, drop=0.16, back=0.03, side=0.03, waist_yaw=-41.0, waist_bend=-4.5)
report["hold"] = lowered((1.76, -0.62, -0.58), yaw=LOW_YAW[3], elev=LOW_ELEV[3])
report["hold"].update(larm(reach((BEHOLD[0] + 0.1, BEHOLD[1] - 0.05, BEHOLD[2] - 0.05), 1.5), (0.5, 1.0, 0.1), (0.85, 0.35, -0.3)))
report["hold"]["look"] = look()
head_level((-4.0, 3.2, -6.0)); key(26)
# 1.07 the hand comes down and back toward the hip, the barrel starts back up: the halfway pose
# of every joint (slerp), so the arm takes the shortest turn from the presentation to the hip
S_HOLD = L.snapshot()
ready(0.0)
L.restore(L.blend_snapshots(S_HOLD, L.snapshot(), 0.5))
report["lower"] = {"hand": pt(L.hand_cf("Left").translation), "head_clear": head_clear(), "look": look()}
key(32)
# 1.33 the left fist is back on the hip, the barrel back up at parade angle (0.46 s from the hold)
ready(0.0)
report["return"] = {"left_hand": pt(L.hand_cf("Left").translation)}
key(40)
ready(0.0); key(45)                                              # 1.50 the Ready carry
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
L.set_interpolation("Fire", 'LINEAR', 'AUTO_CLAMPED', frames=[6])   # 0.20 -> 0.23 straight into the kick

L.use_clip("Fire")
_diag = []
for _i in range(0, 46, 2):
    L.goto(_i / 30.0)
    _diag.append("%d:%.2f/%.2f/%.2f/w%.0f" % (_i, gap(), head_clear(), L.launcher_lowest_y(), wrist_swing()))
print("REPORT_GAP", " ".join(_diag))
for k, v in report.items():
    print("REPORT_POSE", k, v)
if os.environ.get("PROBE"):
    print("REPORT_GUARD", " ".join("%d:%s" % (f, ";".join("%s%s" % (s[0], v) for s, v in sorted(g.items()))) for f, g in GUARD_LOG[-12:]))
    for _k in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
        print("REPORT_AUDIT", _k, L.motion_audit(_k, SPEC[_k]))
    # per-frame arm turn (deg) in Fire
    _fr = L.sample_clip("Fire", SPEC["Fire"])
    from mathutils import Quaternion as _Q
    _rows = []
    for _j, _n in enumerate(L.EXPORT_BONES):
        if _n in ("RightUpperArm", "LeftUpperArm", "LeftHand", "RightHand", "Launcher"):
            _d = []
            for _f in range(1, len(_fr)):
                _a = math.degrees(_Q(_fr[_f - 1][_j][:4]).rotation_difference(_Q(_fr[_f][_j][:4])).angle)
                _d.append("%.0f" % min(_a, 360 - _a))
            _rows.append(_n + ":" + ",".join(_d))
    print("REPORT_TURN", " | ".join(_rows))
    ready(0.0)
    print("REPORT_REF shoulderL", pt(L.joint("LeftUpperArm")), "shoulderR", pt(L.joint("RightUpperArm")), "neck", pt(L.joint("Head")))
    raise SystemExit
if os.environ.get("QUICK"):                       # Fire only, big pad-camera frames, no export
    print("REPORT_AUDIT Fire", L.motion_audit("Fire", SPEC["Fire"]))
    L.use_clip("Fire")
    _cr = []
    for _i in range(0, 46, 2):
        L.goto(_i / 30.0)
        _m = Vector(META["Muzzle"]["pos"])
        _u = (L.launcher_point(_m + Vector(META["Muzzle"]["up"])) - L.launcher_point(_m)).normalized()
        _f = (L.launcher_point(_m) - L.launcher_point(_m - Vector(META["Muzzle"]["look"]))).normalized()
        _side = _f.cross(Vector((0.0, 1.0, 0.0))).normalized()
        _roll = math.degrees(math.asin(max(-1.0, min(1.0, _u.dot(_side)))))
        _cr.append("%d:tilt%.0f/roll%.0f/L%s" % (_i, math.degrees(_u.angle(Vector((0.0, 1.0, 0.0)))), _roll, pt(L.hand_cf("Left").translation)))
    print("REPORT_CROWN", " ".join(_cr))
    for _v in os.environ.get("QUICK_VIEWS", "game").split(","):
        L.render_sheet(SPEC, os.path.join(os.environ["QUICK"], "q22_%s.png" % _v), view=_v, kinds=["Fire"], per_clip=2,
                       size=(480, 400), extra_times=[0.33, 0.4, 0.5, 0.57, 0.63, 0.73, 0.87, 1.07])
    raise SystemExit
L.finish(SPEC, OUT, extra_times=[0.13, 0.33, 0.4, 0.5, 0.57, 0.63, 0.87, 1.07, 1.33])
