"""14 Snowball Gatling -- a heavy blue six-barrel gatling, held at the hip with both hands.

The player stands side-on on the pad (down-track = their LEFT, away from the camera).  The gun is
carried across the character's FRONT (screen-right) so the pad camera sees it end-on, barrels
pointing into the screen.
  Ready    heavy gun held low at the right hip: the weight slowly drags the barrels and the hips
           down (sag), then a quick hitch heaves it back up (waist straightens, gun lifts, small
           root turn) -- a weight cycle, not a still pose.
  ChargeLo SPIN-UP: same feet as Ready (no slide in the crossfade), gun raised onto the track,
           canted 10 deg, chest hunched a little; the buzz runs through the WHOLE body
           (root yaw / lean / roll + hip translation + waist), the chest, both arms and the gun
           shaking together as one heavy unit.  The hand targets are carried rigidly with the
           chest (so the elbows keep their shape) plus only a tiny residual gun buzz.
  ChargeHi the same SHAKE table and phase: the root / hip terms at 3.5x (violent: hips ~0.14,
           muzzle ~0.45 studs), waist / aim at 2x, a deeper crouch, plus a 1-frame hand + aim
           jitter on the odd frames between the 2-frame keys (zero at Lo, so the blend keeps phase).
  Fire     BRRRT: brace (keyed at frame 4, the gun canted 30 deg about its barrels so the hopper
           leans out to screen-right and the pad camera sees the muzzle), then six rapid recoil
           kicks every 0.1 s (the first at FireAt, each a 1-frame snap): each kick drives the hips
           and the right shoulder back along the barrel (+X) with a roll that climbs the muzzle,
           then a spin-down that starts near the ChargeHi buzz and fades as its spacing slows
           (2 -> 3 -> 4 frames), an exhale / shoulder drop, and an 11-frame lowering to the hip.
Ball: hidden until it pops out of the muzzle (barrel launcher), smoke burst, snow at the muzzle
while charging (the barrels spinning up).  meta/14.json Muzzle sits one ball radius ahead of the
barrel face (slightly above the axis): the 0.67-stud ball is bigger than the barrels, so that is
where it leaves them -- and where the pad camera can see it at FireAt.
"""
import importlib
import math
import os
import sys

from mathutils import Vector

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)

LID = 14
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_FRAME = 5
SPEC = {
    "Ready": 2.4, "ChargeLo": 0.8, "ChargeHi": 0.8, "Fire": 1.6,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Never", "start": "Muzzle", "grow": 1.0},
    "Fx": {"Style": "smoke", "Color": [235, 240, 255], "Charge": "snow", "ChargeColor": [225, 238, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "gatling: heavy sagging hip carry, whole-body spin-up buzz while charging, BRRRT burst of recoil kicks with the muzzle climbing, slowing spin-down",
}
FEET_READY = {"Left": (-1.05, -0.3), "Right": (0.9, 0.4)}
FEET_WIDE = FEET_READY
LOOK_TRACK = (-14.0, 0.5, -1.8)
R_ELBOW = Vector((-0.2, 1.0, 0.0))
L_ELBOW = Vector((0.3, 1.0, 0.1))
report = {}
GRIP = None          # constant launcher turn in the hand (taken from the neutral charge pose)
_last = {}


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

# deterministic "random" shake table (unit-ish values), 12 steps per charge loop
SHAKE = []
for i in range(12):
    SHAKE.append((math.sin(i * 2.7 + 0.3), math.sin(i * 4.1 + 1.9), math.sin(i * 5.3 + 0.7),
                  math.sin(i * 3.3 + 2.4), math.sin(i * 6.1 + 1.1)))

# 1-frame jitter samples for ChargeHi's odd frames (hand x, y, z, aim yaw, aim elev)
ODD = []
for i in range(12):
    sg = -1.0 if i % 2 else 1.0
    ODD.append((sg * math.sin(i * 7.3 + 0.4), -sg * math.sin(i * 3.9 + 2.2), sg * math.sin(i * 5.7 + 1.3),
                -sg * (0.6 + 0.4 * abs(math.sin(i * 2.3))), sg * math.sin(i * 4.7 + 0.9)))

ZERO_SH = {}
CHARGE_CANT = 10.0   # the gun is canted a little while spinning up (hopper out, clear of the head)


def _body(yaw, lean, roll, drop, back, side, waist_yaw, waist_bend, feet):
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=feet)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend))


def pose(yaw, lean, drop, back, waist_yaw, waist_bend, at, aim_yaw, aim_elev, feet, look=LOOK_TRACK,
         roll=0.0, sh=None, jit=(0.0, 0.0, 0.0), **kw):
    """sh = body shake carried RIGIDLY by the chest, arms and gun together:
         dict(yaw, lean, roll, drop, back, side, wyaw, wbend) deltas.
       The hold target / aim / elbow poles are moved by the same chest transform, so the arms keep
       their shape; jit = a tiny residual hand-target buzz (studs) on top."""
    sh = sh or ZERO_SH
    L.reset_pose()
    _body(yaw, lean, 0.0, drop, back, 0.0, waist_yaw, waist_bend, feet)
    M0 = L.world_cf("UpperTorso")
    _body(yaw + sh.get("yaw", 0.0), lean + sh.get("lean", 0.0), sh.get("roll", 0.0),
          drop + sh.get("drop", 0.0), back + sh.get("back", 0.0), sh.get("side", 0.0),
          waist_yaw + sh.get("wyaw", 0.0), waist_bend + sh.get("wbend", 0.0), feet)
    M1 = L.world_cf("UpperTorso")
    D = M1 @ M0.inverted()
    R = D.to_3x3()
    fwd = L.direction(aim_yaw, aim_elev)
    up = L.up_for(fwd, roll)
    at2 = D @ Vector(at) + Vector(jit)
    info = L.place_launcher(at=at2, forward=(R @ fwd).normalized(), up=(R @ up).normalized(), anchor="Pivot",
                            elbow_away=R @ R_ELBOW, grip_twist=GRIP, **kw)
    info["left"] = L.left_hand_to(key="Grip2", elbow_away=R @ L_ELBOW)
    L.head_look(target=look)
    info["relb"] = round(math.degrees(L.get_rot("RightLowerArm").angle), 1)
    info["lelb"] = round(math.degrees(L.get_rot("LeftLowerArm").angle), 1)
    info["rreach"] = round((L.joint("RightHand") - L.joint("RightUpperArm")).length, 2)
    info["lreach"] = round((L.joint("LeftHand") - L.joint("LeftUpperArm")).length, 2)
    return info


# ------------------------------------------------------------------ poses
def ready(sag=0.0, hitch=0.0, lift=0.0):
    """sag 0..1 = the weight dragging the gun + hips down, hitch 0..1 = the quick heave back up
    (waist straightens, shrug lifts the gun, root turns), lift 0..1 = part way up toward the charge hold"""
    return pose(yaw=4.0 - 2.0 * sag + 2.0 * hitch + 4.0 * lift,
                lean=2.5 - 0.5 * sag + 1.5 * hitch - 2.5 * lift,
                drop=0.28 + 0.1 * sag - 0.03 * hitch + 0.07 * lift, back=-0.08 + 0.1 * lift,
                waist_yaw=-7.0 - 2.0 * sag + 1.0 * hitch + 4.0 * lift,
                waist_bend=1.0 - 0.3 * sag + 3.5 * hitch - 2.0 * lift,
                at=(0.52 + 0.07 * sag + 0.03 * lift, -0.92 - 0.06 * sag + 0.09 * hitch - 0.1 * lift, -1.25 - 0.04 * sag - 0.15 * lift),
                aim_yaw=4.0 + 1.0 * sag + 5.0 * lift, aim_elev=-12.0 - 8.0 * sag + 3.0 * hitch + 11.0 * lift,
                feet=FEET_READY, look=(-9.0, -2.0 - 0.8 * sag, -3.0))


def charge(depth, s=(0, 0, 0, 0, 0), phase=0.0, odd=None, cant=None, **kw):
    """depth 0..1 = Lo..Hi, s = shake sample, phase 0..1 through the loop (slow bob).
    The whole body buzzes (rigid chest+arms+gun); the hands only add a small residual.
    Hi = 3.5x the Lo body shake (violent), same table, same phase.  odd = an extra 1-frame
    jitter sample (Hi only: hand + aim), scaled by depth so it vanishes at Lo."""
    a = 1.0 + 1.0 * depth            # waist / aim terms
    b = 1.0 + 2.5 * depth            # root yaw / roll / lean + hip translation (the violent part)
    bob = math.sin(2.0 * math.pi * phase)
    sh = {"yaw": 1.2 * b * s[3], "lean": 1.0 * b * s[4], "roll": 0.8 * b * s[0],
          "drop": 0.025 * b * s[1] + 0.02 * bob, "back": 0.02 * b * s[2], "side": 0.025 * b * s[0],
          "wyaw": 1.0 * a * s[2], "wbend": 0.8 * a * s[1] + 0.6 * bob}
    j = 0.012 * b
    jit = [j * s[0], j * s[1], j * s[2]]
    ay, ae = 0.7 * b * s[3], 0.7 * b * s[4]
    if odd is not None:
        jit = [jit[0] + 0.05 * depth * odd[0], jit[1] + 0.05 * depth * odd[1], jit[2] + 0.05 * depth * odd[2]]
        ay += 1.5 * depth * odd[3]
        ae += 1.5 * depth * odd[4]
    return pose(yaw=8.0, lean=-3.0 - 2.0 * depth,
                drop=0.35 + 0.32 * depth, back=0.08 + 0.06 * depth,
                waist_yaw=-3.0, waist_bend=-3.0 - 1.0 * depth,
                at=(0.55, -0.9 - 0.27 * depth, -1.4 - 0.06 * depth),
                aim_yaw=10.0 + ay, aim_elev=4.0 + ae,
                feet=FEET_WIDE, sh=sh, jit=tuple(jit), roll=CHARGE_CANT if cant is None else cant, **kw)


CANT = 30.0          # fire cant about the barrel axis: hopper leans out to the front (-Z, screen-right)
AIM_YAW = 6.0        # fire aim (pose frame); smaller = barrel less parallel to the pad-camera ray


def fire_pose(kick, climb, shake=(0, 0, 0, 0, 0), amp=0.0, cant=CANT, exhale=0.0):
    """kick 0..1 recoil impulse, climb deg of muzzle rise, shake/amp spin-down vibration,
    cant = gun roll about its barrel (+ = hopper out toward the front so the pad camera sees the
    muzzle past it), exhale 0..1 = shoulders drop / chest sinks at the settle.
    The kick is carried by the body (hips + right shoulder driven back along the barrel, +X, a
    roll that climbs the muzzle); the arms only add a small push of the gun."""
    s = shake
    sh = {"yaw": 2.0 * kick + 1.2 * amp * s[3], "lean": 3.0 * kick + 1.0 * amp * s[4], "roll": -3.0 * kick + 0.8 * amp * s[0],
          "drop": -0.03 * kick + 0.025 * amp * s[1] + 0.05 * exhale, "back": 0.05 * kick + 0.02 * amp * s[2],
          "side": 0.07 * kick + 0.03 * amp * s[0],
          "wyaw": 1.5 * kick + 0.6 * amp * s[2], "wbend": 2.5 * kick + 0.5 * amp * s[1] - 4.0 * exhale}
    j = 0.012 * amp
    return pose(yaw=10.0, lean=-6.0, drop=0.62, back=0.14,
                waist_yaw=-2.0, waist_bend=-4.0,
                at=(0.55 + 0.05 * kick, -1.18 + 0.03 * kick - 0.04 * exhale, -1.48 + 0.08 * kick),
                aim_yaw=AIM_YAW + 1.0 * kick * s[3] + 0.7 * amp * s[3],
                aim_elev=6.0 + climb + 4.0 * kick + 0.7 * amp * s[4] - 3.0 * exhale,
                feet=FEET_WIDE, sh=sh, jit=(j * s[0], j * s[1], j * s[2]), roll=cant)


# ------------------------------------------------------------------ clips
report["grip_probe"] = charge(0.5, max_wrist=25.0, cant=0.0)   # grip turn from the uncanted hold
GRIP = L.get_rot("Launcher").copy()
clip("Ready")
report["ready0"] = ready(0.0, 0.0); kf(0)
ready(0.3, 0.0); kf(18)
ready(0.65, 0.0); kf(36)
report["ready_sag"] = ready(1.0, 0.0); kf(52)
report["ready_hitch"] = ready(0.2, 1.0); kf(58)
ready(0.0, 0.3); kf(64)
ready(0.0, 0.0); kf(72)
L.make_cyclic("Ready")

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    clip(kind)
    for i in range(12):
        info = charge(depth, SHAKE[i], i / 12.0)
        report["%s_%d" % (kind, i)] = (info["relb"], info["lelb"], info["arm_overreach"], info["left"])
        kf(2 * i)
        if depth > 0.0:
            # Hi only: a 1-frame jitter between the 2-frame keys (zero at Lo -> same phase)
            s0, s1 = SHAKE[i], SHAKE[(i + 1) % 12]
            smid = tuple(0.5 * (p + q) for p, q in zip(s0, s1))
            info = charge(depth, smid, (i + 0.5) / 12.0, odd=ODD[i])
            report["%s_odd%d" % (kind, i)] = (info["relb"], info["lelb"], info["arm_overreach"])
            kf(2 * i + 1)
    charge(depth, SHAKE[0], 0.0); kf(24)
    L.make_cyclic(kind)

clip("Fire")
charge(1.0, (0, 0, 0, 0, 0), 0.0); kf(0)                      # 0.00 ChargeHi pose
fire_pose(0.0, 0.0, cant=CANT * 0.4); kf(2)                  # the cant starts (keeps the left hand on)
report["brace"] = fire_pose(0.0, 0.0); kf(4)                  # 0.13 brace + cant, aim on the track
KICKS = [5, 8, 11, 14, 17, 20]
for n, f in enumerate(KICKS):
    climb = 2.2 * n
    info = fire_pose(1.0, climb, SHAKE[n], 0.0)
    report["kick%d" % n] = (info["relb"], info["lelb"], info["arm_overreach"], info["left"])
    kf(f)
    info = fire_pose(0.25, climb + 1.0, SHAKE[n + 3], 0.3); kf(f + 2)
# spin-down: the barrels wind down, the shake starts near the ChargeHi buzz, its spacing slows
# 2 -> 3 -> 4 frames and it fades; the cant eases out
for n, f in enumerate((24, 26, 29, 33)):
    fire_pose(0.1, 12.0 - 2.5 * n, SHAKE[(n + 6) % 12], (4.0, 3.0, 2.0, 1.0)[n],
              cant=CANT * (1.0 - 0.2 * n)); kf(f)
report["settle"] = fire_pose(0.0, 2.0, cant=CANT * 0.3, exhale=1.0); kf(37)   # 1.23 exhale, shoulders drop
# lower the heavy gun back to the hip, spread over 11 frames
report["lower"] = ready(0.3, 0.0, 0.55)
kf(41)
ready(0.1, 0.0, 0.15); kf(45)
ready(0.0, 0.0); kf(48)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in report.items():
    print("REPORTP", k, v)


def measure(kind, n):
    """per-frame hips / muzzle offsets from their clip mean, LowerTorso turn per frame, elbows"""
    L.use_clip(kind)
    hips, mz, rot, el = [], [], [], []
    for f in range(n + 1):
        L.goto(f / 30.0)
        hips.append(L.joint("LowerTorso").copy())
        mz.append(L.launcher_point(L.load_meta(LID)["Muzzle"]["pos"]).copy())
        rot.append(L.get_rot("LowerTorso").copy())
        gap = (L.hand_cf("Left").translation - L.launcher_point(L.load_meta(LID)["Grip2"]["pos"])).length
        el.append((round(math.degrees(L.get_rot("RightLowerArm").angle)), round(math.degrees(L.get_rot("LeftLowerArm").angle)),
                   round(gap, 2)))
    mh = sum(hips, Vector()) / len(hips); mm = sum(mz, Vector()) / len(mz)
    dr = [round(math.degrees(rot[i].rotation_difference(rot[i + 1]).angle), 1) for i in range(n)]
    print("MEAS", kind, "hips max", round(max((h - mh).length for h in hips), 3),
          "muzzle max", round(max((m - mm).length for m in mz), 3), "LT deg/frame", dr)
    print("MEAS", kind, "elbows", el)


measure("ChargeLo", 24)
measure("ChargeHi", 24)
measure("Fire", 48)
L.finish(SPEC, OUT, extra_times=[0.1, 0.2667, 0.4667, 0.6667, 0.8667, 1.1, 1.3667])
