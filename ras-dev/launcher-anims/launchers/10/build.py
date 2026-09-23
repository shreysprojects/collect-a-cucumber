"""10 Pump Blaster -- teal blaster, flared barrel, orange ribbed PUMP grip under the barrel.

The player stands side-on (down-track = their LEFT, away from the pad camera).  The gun is always
carried on the character's FRONT side (screen-right), low and forward of the belly, head up, so the
tall body of the gun never runs into the head / chest and the camera sees the pump.
  Ready    SIDE-ON hip carry (torso turned ~40 deg toward the camera, gun straight out of the belly
           so the barrel crosses the pad camera frame): right hand on the pistol grip, left palm under the orange pump,
           breathing + a weight shift with a small waist sway.
  ChargeLo PUMP ACTION: the left hand racks the pump back along the ribs and shoves it forward
           again (two slow strokes per loop); the gun dips on each rack, clacks up on the push, the
           shoulders and knees give a little with every stroke.
  ChargeHi the same two strokes, harder: deeper crouch, longer strokes (0.45 vs 0.36 back),
           2x the pull-back and muzzle rock (+-12 deg), the gun jolts,
           the whole body bobs (in the knees, head up).
  Fire     snap the gun up to shoulder level aimed down the track -> hold the aim a frame -> the
           ball blasts out of the flared muzzle at FireAt -> one-frame recoil kick through the body
           (muzzle up, shoulders / head back, left hand stays on the pump) -> a quick final pump
           seen in silhouette (muzzle dips + rolls toward the camera, clack back up) -> lower to
           the hip carry.
Ball: hidden (inside the barrel) until it pops out of the Muzzle.
Round 4 (elbow guard + motion audit): every elbow pole is UP-ish; the hip carry (READY_GRIP_B) and
the shoulder aim (AIM_GRIP) come from grid searches that keep both forearms out of the chest and
the pump inside ~0.85 of the left arm's reach over the whole stroke; hip <-> shoulder moves go
through between() (body, grip, angles and poles blended) so nothing pops; the one-frame recoil is
a 0.3-stud shove back + muzzle up with the left hand riding the pump (no left-arm snap).

Run:  blender.exe -b ..\\..\\LauncherAnims.blend --python build.py
"""
import importlib
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)

LID = 10
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_F = 5                      # frame of the shot
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.4,
    "FireAt": round(FIRE_F / 30.0, 4),
    "Ball": {"show": "Never", "start": "Muzzle", "grow": 1.0},
    "Fx": {"Style": "smoke", "Color": [225, 240, 245], "Charge": None},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "pump blaster: rack the pump while charging, snap to the shoulder, blast + recoil + final pump",
}
FEET = {"Left": (-0.85, -0.35), "Right": (0.65, 0.45)}
G2 = tuple(L.load_meta(LID)["Grip2"]["pos"])   # middle of the orange pump ribs
HAND_DOWN = 0.1                 # palm just under the pump (meta Grip2 moved to the pump underside)
report = {}


def body(yaw=20.0, lean=-2.0, drop=0.15, back=0.1, waist_yaw=-4.0, waist_bend=-2.0, side=0.0,
         waist_roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


MISS = [0.0]
LAST = [None]
CLIP = [""]
PREV = {}


def pump_hand(slide=0.0, elbow=None):
    """left hand on the pump; slide + = pushed toward the muzzle, - = racked back (studs)"""
    p = L.launcher_point((G2[0], G2[1] - slide / L.LAUNCHER_SCALE, G2[2] + HAND_DOWN))
    L.left_hand_to(point=p, elbow_away=elbow or L_ELBOW)
    miss = round((L.hand_cf("Left").translation - p).length, 3)
    MISS[0] = max(MISS[0], miss)
    LAST[0] = None
    if miss > 0.06:
        LAST[0] = (slide, miss, [round(v, 2) for v in L.joint("LeftLowerArm")])
    return miss


def arm_depth():
    """audit-style check of the current pose: deepest arm point inside torso / head"""
    from mathutils import Vector
    boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    worst, at = 0.0, ""
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for bd in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[bd])
                        if d > worst:
                            worst, at = d, "%s/%s" % (arm, bd)
    ob = L.launcher_object()
    mw = ob.matrix_world
    lw = 0.0
    for co in [v.co for v in ob.data.vertices][::6]:
        pt = L.b2r(mw @ co)
        for bd in ("UpperTorso", "Head"):
            lw = max(lw, L._depth_inside(pt, *boxes[bd]))
    return round(worst, 2), at, round(lw, 2)


def reach(side):
    return round((L.joint(side + "Hand") - L.joint(side + "UpperArm")).length / 1.66, 2)


def K(f):
    """key all bones, keeping every quaternion in the same hemisphere as the previous key"""
    if LAST[0]:
        print("REPORT_MISS", CLIP[0], f, LAST[0])
    import math as _m
    bl = round(_m.degrees(L.get_rot("LeftLowerArm").angle), 0)
    br = round(_m.degrees(L.get_rot("RightLowerArm").angle), 0)
    print("REPORT_K", CLIP[0], f, "depth", arm_depth(), "reachL", reach("Left"), "reachR", reach("Right"),
          "bendL", bl, "bendR", br)
    for name in L.BONES:
        q = L.get_rot(name)
        p = PREV.get(name)
        if p is not None and q.dot(p) < 0.0:
            q.negate()
            L.set_rot(name, q)
        PREV[name] = q.copy()
    L.update()
    L.key(f)


def clip(kind):
    CLIP[0] = kind
    PREV.clear()
    L.new_clip(kind)


def finish_pose(look, slide=0.0, elbow=None):
    pump_hand(slide, elbow)
    L.head_look(target=look)


TRACK_LOOK = (-8.0, 0.5, -4.0)


# ------------------------------------------------------------------ poses
# SIDE-ON hip carry (round 3, grid search in scratch grid10c.py): the upper body turns ~35 deg
# toward the camera and the gun points straight out of the belly toward the character's front
# (world yaw ~58), so from the pad camera the barrel crosses the frame left -> right and the
# orange pump + the left forearm sit in plain view under it.  The grip is given in the upper
# body's own frame (x right, z back) and rotated by the torso yaw.
import math
BODY_YAW, WAIST_YAW = -12.0, -30.0
# round 4 (elbow guard + motion audit): grid search (scratch grid10.py) for a carry with no arm in
# the chest and the pump well inside the left arm's reach over the whole stroke
READY_GRIP_B = (0.85, -0.15, -1.15)    # grip in the torso-yaw frame
READY_YAW, READY_ELEV, ROLL = 48.0, 3.0, 0.0
R_ELBOW = (-0.3, 1.0, 0.1)             # UP-ish poles: elbows hang down and out
L_ELBOW = (0.3, 1.0, 0.1)
LO_STROKE = (-0.36, 0.1)               # pump stroke in studs (racked back, shoved forward)
HI_STROKE = (-0.45, 0.2)


def grip_world(b, tyaw):
    a = math.radians(tyaw)
    return (b[0] * math.cos(a) + b[2] * math.sin(a), b[1], -b[0] * math.sin(a) + b[2] * math.cos(a))


def gun_back(yaw):
    """unit (x, z) along the gun axis toward its butt (for the pump pull-back)"""
    y = math.radians(yaw)
    return math.cos(y), math.sin(y)


def slide_studs(s, depth):
    back = LO_STROKE[0] + (HI_STROKE[0] - LO_STROKE[0]) * depth
    fwd = LO_STROKE[1] + (HI_STROKE[1] - LO_STROKE[1]) * depth
    return fwd * s if s > 0 else -back * s


def ready(b=0.0, shift=0.0):
    """b 0..1 = breath in, shift -1..1 = weight toward the back / front foot (+ waist sway)"""
    by, wy = BODY_YAW + 2.0 * shift, WAIST_YAW - 2.5 * shift
    body(yaw=by, lean=-2.0 - 1.5 * b, drop=0.14 + 0.04 * b - 0.03 * shift,
         back=0.1, side=0.08 * shift, waist_yaw=wy, waist_bend=-2.0 - 2.5 * b, waist_roll=1.5 * shift)
    g = grip_world(READY_GRIP_B, by + wy)
    info = L.hold((g[0], g[1] + 0.08 * b, g[2]), yaw=READY_YAW + 2.0 * shift,
                  elev=READY_ELEV + 3.0 * b, roll=ROLL, elbow_away=R_ELBOW)
    finish_pose((TRACK_LOOK[0], TRACK_LOOK[1] + 0.4 * b, TRACK_LOOK[2]), 0.0)
    return info


def charge(slide, depth, rock=0.0, bob=0.0, jolt=(0.0, 0.0, 0.0), sdip=0.0):
    """slide -1 = pump racked back, +1 = shoved forward; depth 0 = ChargeLo, 1 = ChargeHi;
    rock = gun pitch (deg, + = muzzle up); bob = extra knee dip (studs); jolt = gun shake offset;
    sdip = shoulder dip (deg of extra waist bend)"""
    by, wy = BODY_YAW - 3.0 * depth, WAIST_YAW
    body(yaw=by, lean=-2.0 - 1.5 * depth,
         drop=0.2 + 0.24 * depth + bob, back=0.12 + 0.1 * depth,
         waist_yaw=wy, waist_bend=-2.0 - 2.0 * depth - sdip)
    gyaw = READY_YAW - 2.0 * depth
    # the racked-back pump pulls the gun back along its axis (twice as hard at full charge)
    pull = -(0.1 + 0.1 * depth) * min(0.0, slide)
    bx, bz = gun_back(gyaw)
    g = grip_world(READY_GRIP_B, by + wy)
    grip = (g[0] + bx * pull + jolt[0],
            g[1] - 0.05 - 0.12 * depth - bob * 0.8 + jolt[1],
            g[2] + bz * pull + jolt[2])
    info = L.hold(grip, yaw=gyaw, elev=READY_ELEV + rock, roll=ROLL, elbow_away=R_ELBOW)
    finish_pose((-4.0, -0.2, -4.5), slide_studs(slide, depth))
    return info


AIM_ELBOW = (0.3, 1.0, 0.1)      # left elbow for the shoulder aim: hangs under the pump
AIM_RELB = (-0.3, 1.0, 0.1)      # right elbow for the shoulder aim: hangs down and out
AIM_GRIP = (1.0, 0.4, -1.2)     # grid10b.py: no forearm in the chest, pump in reach
AIM_ELEV = 8.0


def aim(dx=0.0, dy=0.0, elev=AIM_ELEV, yaw=8.0, lean=-1.0, byaw=6.0, wbend=-2.0, slide=0.05, look=None,
        roll=-10.0, wyaw=-12.0, drop=0.12, lelbow=None, hback=0.0):
    """shoulder-level aim down the track (dx + = gun pushed back toward the camera)"""
    body(yaw=byaw, lean=lean, drop=drop, back=0.05 + hback, waist_yaw=wyaw, waist_bend=wbend)
    info = L.hold((AIM_GRIP[0] + dx, AIM_GRIP[1] + dy, AIM_GRIP[2]), yaw=yaw, elev=elev, roll=roll,
                  elbow_away=AIM_RELB)
    finish_pose(look or (-12.0, 1.6 + 0.1 * elev, -2.5), slide, lelbow or AIM_ELBOW)
    return info


def lerp(a, b, t):
    return a + (b - a) * t


def lerpv(a, b, t):
    return tuple(lerp(x, y, t) for x, y in zip(a, b))


def between(t, lead=0.0, drop=0.0):
    """hip carry (t=0) -> shoulder aim (t=1): body, grip, gun angles and elbow poles all blended,
    so the arms travel smoothly (no IK pop); lead = extra muzzle-up degrees"""
    by, wy = lerp(BODY_YAW, 6.0, t), lerp(WAIST_YAW, -12.0, t)
    body(yaw=by, lean=lerp(-2.0, -1.0, t), drop=lerp(0.14, 0.12, t) + drop, back=lerp(0.1, 0.05, t),
         waist_yaw=wy, waist_bend=-2.0)
    g0 = grip_world(READY_GRIP_B, BODY_YAW + WAIST_YAW)
    info = L.hold(lerpv(g0, AIM_GRIP, t), yaw=lerp(READY_YAW, 8.0, t), elev=lerp(READY_ELEV, AIM_ELEV, t) + lead,
                  roll=lerp(ROLL, -10.0, t), elbow_away=lerpv(R_ELBOW, AIM_RELB, t))
    finish_pose(lerpv(TRACK_LOOK, (-12.0, 1.6 + 0.1 * AIM_ELEV, -2.5), t), 0.05, lerpv(L_ELBOW, AIM_ELBOW, t))
    return info


# ------------------------------------------------------------------ clips
clip("Ready")
report["ready0"] = ready(0.0, 0.0); K(0)
report["ready1"] = ready(1.0, 0.5); K(20)
ready(0.2, 1.0); K(36)
ready(0.9, -0.3); K(54)
ready(0.0, 0.0); K(72)
L.make_cyclic("Ready")

# two pump strokes per loop, the same phase timing in Lo and Hi
#   stroke: forward (clack) -> rack back -> shove forward
for kind, d in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    clip(kind)
    for base in (0, 18):
        report["%s_fwd%d" % (kind, base)] = charge(1.0, d, rock=4.0 + 4.0 * d, bob=0.0); K(base)
        if d > 0.5:
            # hard rack: reaches the back fast, the gun jolts down, body dips
            charge(-1.0, d, rock=-12.0, bob=0.16, jolt=(0.03, -0.05, 0.0), sdip=1.5); K(base + 5)
            report["%s_back%d" % (kind, base)] = charge(-1.0, d, rock=-9.0, bob=0.12, jolt=(-0.02, 0.02, 0.02), sdip=0.5); K(base + 9)
            # shove forward: the clack kicks the muzzle up, the body pops up
            charge(1.0, d, rock=12.0, bob=-0.03, jolt=(-0.03, 0.06, -0.02), sdip=-2.5); K(base + 13)
        else:
            charge(-0.4, d, rock=-3.0, bob=0.04, sdip=1.5); K(base + 5)
            report["%s_back%d" % (kind, base)] = charge(-1.0, d, rock=-5.0, bob=0.05, sdip=2.5); K(base + 9)
            charge(0.7, d, rock=3.0, bob=0.02, sdip=0.5); K(base + 13)
    charge(1.0, d, rock=4.0 + 4.0 * d, bob=0.0); K(36)
    L.make_cyclic(kind)

clip("Fire")
charge(1.0, 1.0, rock=6.0); K(0)                          # 0.00 the ChargeHi pose
# 0.03 / 0.07 the gun swings up from the hip toward the shoulder, muzzle leading (blended poses)
report["rise"] = between(0.35, lead=5.0, drop=0.05); K(1)
report["raise"] = between(0.75, lead=4.0, drop=0.02); K(2)
report["arrive"] = aim(dx=0.05, dy=-0.06, elev=AIM_ELEV - 3.0, byaw=4.0); K(3)
# 0.13 on target, 0.17 FireAt: aimed flat down the track, HELD still for the shot
report["settle"] = aim(dy=0.04); K(4)
report["shot"] = aim(dy=0.04); K(FIRE_F)
# 0.20 RECOIL peak in ONE frame (linear f5->f6): the kick goes through the body -- shoulders and
# head thrown back, muzzle up, the gun shoved back; the left hand stays on the pump
report["recoil"] = aim(dx=0.3, dy=0.08, elev=AIM_ELEV + 7.0, yaw=8.0, lean=2.0, wbend=0.0, slide=0.15,
                       look=(-12.0, 4.0, -2.5)); K(6)
# 0.30 recover onto the target
report["recover"] = aim(dx=0.04, dy=0.03, elev=AIM_ELEV - 1.0, lean=1.0, wbend=0.0, slide=0.05); K(9)
# 0.37 FINAL PUMP: rack back -- muzzle dips, the gun rolls, left elbow drops back, knees give
report["rack"] = aim(dx=0.14, dy=-0.1, elev=-3.0, roll=-3.0, lean=-4.0, wbend=-4.0, slide=-0.4,
                     look=(-12.0, 1.0, -2.5), lelbow=(0.3, 1.0, -0.4), drop=0.18); K(11)
# 0.47 ... and shove forward (clack): muzzle snaps back up, small upward pop
report["clack"] = aim(dx=0.06, dy=0.06, elev=AIM_ELEV + 2.0, lean=0.0, slide=0.15, drop=0.07); K(14)
# 0.63 hold on target a beat
aim(dx=0.1, dy=-0.02, elev=AIM_ELEV - 3.0, lean=-2.0, slide=0.05); K(19)
# 0.77 / 0.93 lowering to the hip (through blended poses: the gun clears the head)
between(0.8, lead=-1.0); K(23)
report["lower"] = between(0.4, lead=-2.0); K(29)
ready(0.0, 0.0); K(42)                                    # 1.40 hip carry again
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
L.set_interpolation("Fire", 'LINEAR', 'AUTO_CLAMPED', frames=[FIRE_F])

for k, v in report.items():
    print("REPORT_POSE", k, v)
print("REPORT_POSE left_miss_max", MISS[0])


def body_hits():
    """launcher vertices inside the head / torso blocks: (count, deepest)"""
    ob = L.launcher_object()
    mw = ob.matrix_world
    verts = [L.b2r(mw @ v.co) for v in ob.data.vertices]
    out = {}
    for name, box, half in L.body_boxes():
        if name not in ("Head", "UpperTorso", "LowerTorso"):
            continue
        inv = box.inverted()
        n, best = 0, 0.0
        for p in verts:
            q = inv @ p
            dx, dy, dz = half.x - abs(q.x), half.y - abs(q.y), half.z - abs(q.z)
            if dx > 0 and dy > 0 and dz > 0:
                n += 1
                best = max(best, min(dx, dy, dz))
        if n:
            out[name] = (n, round(best, 2))
    return out


for kind, n in (("Ready", 72), ("ChargeLo", 36), ("ChargeHi", 36), ("Fire", 42)):
    L.use_clip(kind)
    gaps, hits = [], {}
    for i in range(0, n + 1, 1):
        L.goto(i / 30.0)
        if i % 2 == 0:
            gaps.append(round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 2))
    print("REPORT_GAPS", kind, gaps)
    worst = {}
    for i, h in hits.items():
        for part, (cnt, dep) in h.items():
            w = worst.setdefault(part, [0, 0.0, []])
            w[0] = max(w[0], cnt); w[1] = max(w[1], dep); w[2].append(i)
    print("REPORT_HITS", kind, {k: (v[0], v[1], v[2][:12]) for k, v in worst.items()})
L.finish(SPEC, OUT, extra_times=[0.067, 0.1, 0.133, 0.2, 0.3, 0.367, 0.467])
