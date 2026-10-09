"""24 Dragon Launcher -- green dragon head with horns: it breathes, rears back, and LUNGES to spit the ball.

The player stands side-on on the pad (down-track = their LEFT, away from the pad camera); the
dragon head is carried on the character's FRONT side (screen-right) so the camera sees it.
  Ready    held at the right hip, left hand on the dragon's neck (Grip2); the head 'breathes':
           a slow rise and fall plus a small nod, like a living head; body breathing + weight shift.
  ChargeLo the dragon REARS BACK: pulled back and up toward the right shoulder, the head tilting up
           and down menacingly (one slow sweep per loop), torso leaning back, left hand on the neck.
  ChargeHi the same rear-back, deeper (higher, further back, deeper crouch), trembling with rage
           (a fast shake riding on the same slow sweep).
  Fire     a last snap back (anticipation) -> the dragon LUNGES forward down the track (arms and
           torso thrust out), the ball bursts from its open mouth at FireAt -> the head recoils up
           and shakes (decaying) -> settles back to the hip carry.
Ball: hidden until it comes out of the mouth (Muzzle).  Fire burst, fire flicker at the mouth while charging.
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

LID = 24
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.0, "ChargeHi": 1.0, "Fire": 1.5,
    "FireAt": 0.20,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "fire", "Color": [255, 140, 40], "Charge": "fire", "ChargeColor": [255, 100, 30]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "dragon head: breathes at the hip, rears back tilting menacingly (shaking with rage at full charge), then lunges and spits the ball from its mouth",
}
FEET = {"Left": (-1.0, -0.45), "Right": (0.75, 0.25)}
TRACK_LOOK = (-12.0, 0.5, -1.8)
R_ELBOW = (-0.3, 1.0, -0.6)
L_ELBOW = (0.3, 1.0, -0.5)
report = {}

GRIP = {"q": None}      # the handle sits rigidly in the fist: one grip rotation, a little give


def dragon(at, yaw, elev, roll=0.0, elbow=R_ELBOW, give=25.0):
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
    info["grip_vs_ready"] = round(min(d, give), 1)
    return info


PREV = {}


def key(frame):
    """L.key with every bone's quaternion kept in one hemisphere (no long-way spins)"""
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


def left(offset=(0.0, 0.0, 0.0)):
    return L.left_hand_to(key="Grip2", elbow_away=L_ELBOW, offset=offset)


def lerp(a, b, u):
    return a + (b - a) * u


BODY_KEYS = ("yaw", "lean", "drop", "back", "waist_yaw", "waist_bend", "side", "roll", "waist_roll")


def P(yaw=15.0, lean=-9.0, drop=0.25, back=0.1, waist_yaw=4.0, waist_bend=-8.0, side=0.0, roll=0.0, waist_roll=0.0,
      at=(0.4, -0.9, -1.3), cyaw=15.0, celev=0.0, croll=0.0, elbow=R_ELBOW, look=TRACK_LOOK, give=10.0):
    """one pose as plain numbers (so poses can be interpolated and re-solved with IK)"""
    return dict(yaw=yaw, lean=lean, drop=drop, back=back, waist_yaw=waist_yaw, waist_bend=waist_bend, side=side,
                roll=roll, waist_roll=waist_roll, at=Vector(at), cyaw=cyaw, celev=celev, croll=croll,
                elbow=Vector(elbow), look=Vector(look), give=give)


def apply(p):
    body(**{k: p[k] for k in BODY_KEYS})
    info = dragon(tuple(p["at"]), yaw=p["cyaw"], elev=p["celev"], roll=p["croll"],
                  elbow=tuple(Vector(p["elbow"]).normalized()), give=p["give"])
    info["left"] = left()
    L.head_look(target=tuple(p["look"]))
    return info


# ------------------------------------------------------------------ poses
N_READY = 24    # keys over the Ready loop (every 3 frames, 72 frames = 2.4 s)


def ready_p(i):
    th = 2.0 * math.pi * i / N_READY
    b = 0.5 - 0.5 * math.cos(th)                 # breathing 0..1
    s = math.sin(th)                             # weight shift
    nod = math.sin(2.0 * th)                     # the dragon's head nods twice per loop
    return P(yaw=RYAW + 2.0 * s, lean=-9.0 + 1.5 * b, drop=0.22 - 0.04 * b, back=0.08, side=0.05 * s,
             waist_yaw=4.0 + 1.0 * b, waist_bend=-8.0 + 2.5 * b, roll=1.5 * s,
             at=(RA[0], RA[1] + 0.1 * b, RA[2]), cyaw=RCYAW + 3.0 * s, celev=-6.0 + 4.0 * b + 8.0 * nod,
             croll=RROLL + 3.0 * nod, look=(-8.0, -0.5 + 0.5 * b, -3.0))


RA = (0.7, -1.0, -1.4)       # the carry: out in front of the right hip, the skull below the chin
RROLL = 24.0                 # the dragon's crown rolled away from the face
RYAW = 0.0
RCYAW = 15.0


N_CH = 15       # keys per charge loop (every 2 frames, 30 frames = 1.0 s)
GIVE_CH = 15.0


def rear_p(i, depth):
    """i = key index over the loop; depth 0 = ChargeLo, 1 = ChargeHi"""
    th = 2.0 * math.pi * i / N_CH
    tilt = math.sin(th)                          # the slow menacing up/down sweep (one per loop)
    sway = math.cos(th)
    # rage shake at full charge: fast (5 per loop) plus a flutter (3 per loop, offset)
    sh1 = math.sin(5.0 * th) * depth
    sh2 = math.sin(3.0 * th + 1.3) * depth
    A = 11.0 + 7.0 * depth                        # tilt amplitude (deg)
    return P(yaw=6.0 - 4.0 * depth + 1.5 * sway + 1.2 * sh2,
             lean=-2.0 + 5.0 * depth + 1.5 * tilt + 1.0 * sh1,       # leaning BACK as it rears
             drop=0.32 + 0.3 * depth - 0.03 * tilt,
             back=0.2 + 0.08 * depth,
             side=0.08 + 0.04 * depth,
             waist_yaw=CWY - 2.0 * depth + 1.0 * sway,
             waist_bend=2.0 + 4.0 * depth + 2.0 * tilt,
             roll=-1.0 * sway + 1.2 * sh1,
             waist_roll=-2.0 * sway,
             at=(CA[0] + HX * depth + 0.04 * sway + 0.03 * sh2,
                 CA[1] + HY * depth + 0.07 * tilt + 0.03 * sh1,
                 CA[2] + HZ * depth + 0.03 * sway),
             cyaw=40.0 + 4.0 * depth + 3.0 * sway + 3.0 * sh2,
             celev=18.0 + 10.0 * depth + A * tilt + 7.0 * sh1,
             croll=CROLL + 4.0 * sway + 3.0 * sh1, give=GIVE_CH,
             look=(-8.0, 1.5 + 1.0 * tilt, -3.5))


CA = (0.8, -0.62, -0.95)
HX, HY, HZ = 0.0, 0.05, 0.1
CWY = -9.0
CROLL = 15.0


# ------------------------------------------------------------------ Fire: key poses, IK re-solved every frame
THR_ELBOW = (-0.6, 1.0, -0.2)
REC_ELBOW = (-0.2, 1.0, -0.45)
FZ = -1.45
WF = int(os.environ.get("WF24", "2"))   # the snap-back key frame (4 frames of lunge after it)
LUNGE_ELBOW = (-0.1, 1.0, -1.0)   # elbow pushed forward-up through the lunge: keeps the wrist from rolling over
CR = 12.0        # the recoil keeps the dragon's crown rolled away from the face
FIRE = [
    (0, rear_p(0, 1.0)),                                                    # 0.00 the ChargeHi pose
    # 0.10 SNAP BACK: the dragon draws its head back (to the right, away from the track) and up (anticipation)
    (WF, P(yaw=-10.0, lean=6.0, drop=0.6, back=0.3, waist_yaw=-8.0, waist_bend=6.0, side=0.14, roll=2.0,
          at=(0.75, -0.3, -0.75), cyaw=50.0, celev=36.0, elbow=R_ELBOW, give=20.0, look=(-8.0, 2.0, -3.0))),
    # 0.20 LUNGE (FireAt): arms and torso thrust the head out down the track, the ball leaves the mouth
    (6, P(yaw=30.0, lean=-16.0, drop=0.4, back=0.0, waist_yaw=16.0, waist_bend=-6.0, side=-0.3,
          at=(0.2, -0.65, -1.7), cyaw=6.0, celev=15.0, croll=20.0, elbow=LUNGE_ELBOW, give=20.0)),
    # 0.27 hold the lunge a beat (the ball clears the mouth)
    (8, P(yaw=29.0, lean=-15.0, drop=0.4, back=0.0, waist_yaw=15.0, waist_bend=-6.0, side=-0.28,
          at=(0.23, -0.64, -1.7), cyaw=7.0, celev=14.0, croll=20.0, elbow=LUNGE_ELBOW, give=20.0)),
    # 0.37 RECOIL: the head kicks back and to the right (+X, +Z) ...
    (11, P(yaw=10.0, lean=-8.0, drop=0.42, back=0.12, waist_yaw=0.0, waist_bend=-3.0, roll=-3.0,
           at=(0.55, -0.5, FZ), cyaw=18.0, celev=12.0, croll=CR + 6.0, elbow=REC_ELBOW, give=20.0, look=(-10.0, 2.0, -1.8))),
    # 0.43 ... then tosses up
    (13, P(yaw=10.0, lean=-7.0, drop=0.42, back=0.12, waist_yaw=0.0, waist_bend=-2.0, roll=-4.0,
           at=(0.55, -0.4, FZ), cyaw=16.0, celev=26.0, croll=CR + 2.0, elbow=REC_ELBOW, give=20.0, look=(-10.0, 2.5, -1.8))),
    # then it shakes itself out (decaying)
    (16, P(yaw=12.0, lean=-11.0, drop=0.4, back=0.1, waist_yaw=0.0, waist_bend=-5.0, roll=4.0,
           at=(0.47, -0.55, FZ), cyaw=10.0, celev=8.0, croll=CR + 16.0, elbow=REC_ELBOW, give=20.0)),
    (19, P(yaw=12.0, lean=-9.0, drop=0.36, back=0.1, waist_yaw=0.0, waist_bend=-4.0, roll=-3.0,
           at=(0.51, -0.55, FZ), cyaw=20.0, celev=16.0, croll=CR + 4.0, elbow=REC_ELBOW, give=20.0)),
    (22, P(yaw=10.0, lean=-10.0, drop=0.32, back=0.1, waist_yaw=1.0, waist_bend=-6.0, roll=2.0,
           at=(0.55, -0.65, FZ + 0.05), cyaw=16.0, celev=6.0, croll=CR + 12.0, elbow=REC_ELBOW, give=20.0)),
    (26, P(yaw=6.0, lean=-10.0, drop=0.28, back=0.1, waist_yaw=2.0, waist_bend=-7.0, roll=-1.0,
           at=(0.62, -0.8, FZ + 0.15), cyaw=20.0, celev=2.0, croll=CR + 8.0, elbow=REC_ELBOW, give=20.0)),
    # 1.17 settle back toward the hip carry
    (35, P(yaw=2.0, lean=-9.5, drop=0.24, back=0.08, waist_yaw=4.0, waist_bend=-8.0,
           at=(0.7, -0.98, -1.45), cyaw=17.0, celev=-5.0, croll=20.0, look=(-8.0, -0.5, -3.0))),
    (45, ready_p(0)),                                                       # 1.50 the Ready carry
]


def fire_at_frame(f):
    """Catmull-Rom through the key poses (zero tangents at both ends)"""
    fs = [k[0] for k in FIRE]
    i = max(j for j in range(len(FIRE) - 1) if fs[j] <= f)
    f0, f1 = fs[i], fs[i + 1]
    a, b = FIRE[i][1], FIRE[i + 1][1]
    h = f1 - f0
    s = (f - f0) / h

    def tan(j):
        if j == 0 or j == len(FIRE) - 1:
            return {k: FIRE[j][1][k] * 0.0 for k in FIRE[j][1]}
        pa, pb = FIRE[j - 1][1], FIRE[j + 1][1]
        return {k: (pb[k] - pa[k]) / (fs[j + 1] - fs[j - 1]) for k in pa}

    m0, m1 = tan(i), tan(i + 1)
    s2, s3 = s * s, s * s * s
    h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
    return {k: h00 * a[k] + h10 * h * m0[k] + h01 * b[k] + h11 * h * m1[k] for k in a}



# ------------------------------------------------------------------ one fixed grip for the handle
# The free IK solve of the first pose is a poor grip for the lunge / recoil; search the grip
# rotation (from the free solves of the key poses and their mixes) that keeps the right wrist
# least bent over ALL key poses, then every pose starts from it with a little give.
def wrist_swing():
    sw, _ = L.swing_twist(L.get_rot("RightHand"))
    return math.degrees(sw.angle)


def _old_test():
    """the round-1 key poses: their best grip gave the least bent wrists; the grip search runs on them"""
    global HX, HY, HZ
    keep = (HX, HY, HZ)
    HX, HY, HZ = 0.2, 0.14, 0.1
    out = [ready_p(0), ready_p(12)] + [rear_p(i, d) for d in (0.0, 1.0) for i in (0, 4, 8, 11)]
    HX, HY, HZ = keep
    fz, cr, re = -1.95, 12.0, REC_ELBOW
    out += [
        P(yaw=-10.0, lean=6.0, drop=0.6, back=0.3, waist_yaw=-8.0, waist_bend=6.0, side=0.14, roll=2.0,
          at=(1.05, -0.45, -1.05), cyaw=50.0, celev=36.0, give=20.0),
        P(yaw=24.0, lean=-14.0, drop=0.4, back=0.0, waist_yaw=14.0, waist_bend=-6.0, side=-0.1,
          at=(0.3, -0.5, -1.95), cyaw=10.0, celev=24.0, croll=20.0, elbow=(-0.5, 1.0, 0.0), give=20.0),
        P(yaw=24.0, lean=-13.0, drop=0.4, back=0.0, waist_yaw=13.0, waist_bend=-6.0, side=-0.1,
          at=(0.33, -0.51, -1.95), cyaw=11.0, celev=23.0, croll=20.0, elbow=(-0.5, 1.0, 0.0), give=20.0),
        P(yaw=10.0, lean=-8.0, drop=0.42, back=0.12, waist_yaw=0.0, waist_bend=-3.0, roll=-3.0,
          at=(0.55, -0.5, fz), cyaw=18.0, celev=12.0, croll=cr + 6.0, elbow=re, give=20.0),
        P(yaw=10.0, lean=-7.0, drop=0.42, back=0.12, waist_yaw=0.0, waist_bend=-2.0, roll=-4.0,
          at=(0.55, -0.4, fz), cyaw=16.0, celev=26.0, croll=cr + 2.0, elbow=re, give=20.0),
        P(yaw=12.0, lean=-11.0, drop=0.4, back=0.1, waist_yaw=0.0, waist_bend=-5.0, roll=4.0,
          at=(0.47, -0.55, fz), cyaw=10.0, celev=8.0, croll=cr + 16.0, elbow=re, give=20.0),
        P(yaw=12.0, lean=-9.0, drop=0.36, back=0.1, waist_yaw=0.0, waist_bend=-4.0, roll=-3.0,
          at=(0.51, -0.55, fz), cyaw=20.0, celev=16.0, croll=cr + 4.0, elbow=re, give=20.0),
        P(yaw=10.0, lean=-10.0, drop=0.32, back=0.1, waist_yaw=1.0, waist_bend=-6.0, roll=2.0,
          at=(0.55, -0.65, fz + 0.05), cyaw=16.0, celev=6.0, croll=cr + 12.0, elbow=re, give=20.0),
        P(yaw=6.0, lean=-10.0, drop=0.28, back=0.1, waist_yaw=2.0, waist_bend=-7.0, roll=-1.0,
          at=(0.62, -0.8, fz + 0.15), cyaw=20.0, celev=2.0, croll=cr + 8.0, elbow=re, give=20.0),
        P(yaw=2.0, lean=-9.5, drop=0.24, back=0.08, waist_yaw=4.0, waist_bend=-8.0,
          at=(0.7, -0.98, -1.45), cyaw=17.0, celev=-5.0, croll=20.0),
    ]
    return out


TEST = _old_test()
free = []
for p in TEST:
    GRIP["q"] = None
    apply(p)
    free.append(L.get_rot("Launcher").copy())
cands = list(free)
for i in range(len(free)):
    for j in range(i + 1, len(free)):
        qa, qb = free[i], free[j]
        if qa.dot(qb) < 0.0:
            qb = -qb
        cands.append(qa.slerp(qb, 0.5))
best = None
for q in cands:
    worst, tot = 0.0, 0.0
    for p in TEST:
        body(**{k: p[k] for k in BODY_KEYS})
        L.hold(tuple(p["at"]), yaw=p["cyaw"], elev=p["celev"], roll=p["croll"], anchor="Pivot",
               elbow_away=tuple(Vector(p["elbow"]).normalized()), grip_twist=q)
        s = wrist_swing()
        worst, tot = max(worst, s), tot + s
    c = worst + 0.3 * tot / len(TEST)
    if best is None or c < best[0]:
        best = (c, q, worst)
GRIP["q"] = best[1]
print("REPORT_GRIP worst swing %.1f cost %.1f" % (best[2], best[0]))

if os.environ.get("PROBE24B"):
    _meta = L.load_meta(LID)["Muzzle"]
    _mp, _ml = Vector(_meta["pos"]), Vector(_meta["look"])
    base_l = dict(FIRE[2][1]); base_8 = dict(FIRE[3][1])
    VARS = [
        {},
        dict(elbow=Vector((-0.3, 1.0, -0.6))),
        dict(elbow=Vector((-0.2, 1.0, -0.8))),
        dict(elbow=Vector((-0.1, 1.0, -1.0))),
        dict(elbow=Vector((-0.2, 1.0, -0.8)), croll=14.0),
        dict(elbow=Vector((-0.2, 1.0, -0.6))),
        dict(elbow=Vector((-0.1, 1.0, -1.0)), at=Vector((0.28, -0.65, -1.55))),
        dict(elbow=Vector((-0.1, 1.0, -1.0)), at=Vector((0.2, -0.65, -1.7))),
        dict(elbow=Vector((-0.1, 1.0, -1.0)), at=Vector((0.28, -0.65, -1.62))),
        dict(elbow=Vector((-0.3, 1.0, -0.8))),
        dict(elbow=Vector((-0.1, 1.0, -1.0)), yaw=26.0, waist_yaw=14.0),
    ]
    STEPS = os.environ.get("PROBE24B") == "2"
    for vi, var in enumerate(VARS):
        p = dict(base_l); p.update(var)
        FIRE[2] = (6, p)
        q8 = dict(base_8); q8.update(var); FIRE[3] = (8, q8)
        prev = None; worst = (0, 0); sw = 0; steps = []
        for f in range(0, 20):
            apply(fire_at_frame(f))
            q = L.get_rot("RightHand").copy()
            sw = max(sw, wrist_swing())
            if prev is not None:
                if q.dot(prev) < 0: q = -q
                d = math.degrees(prev.rotation_difference(q).angle)
                steps.append("%.0f/%.2f" % (d, (L.joint("RightHand") - L.joint("RightUpperArm")).length))
                if d > worst[0]: worst = (d, f)
            prev = q
        print("REPORT_S%d %s" % (vi, " ".join(steps)))
        deps = []
        for f in (4, 5, 6, 7, 8, 9):
            apply(fire_at_frame(f))
            boxes = {n: (b, (Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
            w = 0.0
            for arm in L.AUDIT_ARMS:
                ab, ah = boxes[arm]
                for i in (-1, 0, 1):
                    for j in (-1, 0, 1):
                        for k in (-1, 0, 1):
                            pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                            for bd in ("UpperTorso", "Head", "LowerTorso"):
                                w = max(w, L._depth_inside(pt, *boxes[bd]))
            deps.append("f%d:%.2f" % (f, w))
        print("REPORT_D%d %s" % (vi, " ".join(deps)))
        apply(fire_at_frame(6))
        a = L.launcher_point(tuple(_mp)); b = L.launcher_point(tuple(_mp + _ml)); d = (b - a).normalized()
        yaw = math.degrees(math.atan2(-d.z, -d.x)); el = math.degrees(math.asin(max(-1, min(1, d.y))))
        print("REPORT_V%d %s maxstep %.0f@f%d maxswing %.0f fire yaw %.1f elev %.1f muzzle (%.2f,%.2f,%.2f)" % (
            vi, var, worst[0], worst[1], sw, yaw, el, a.x, a.y, a.z))
        FIRE[2] = (6, base_l); FIRE[3] = (8, base_8)
    sys.exit(0)

if os.environ.get("PROBE24"):
    _meta = L.load_meta(LID)["Muzzle"]
    _mp, _ml = Vector(_meta["pos"]), Vector(_meta["look"])

    def _probe(tag, p):
        info = apply(p)
        eb = math.degrees(L.get_rot("RightLowerArm").angle)
        lb = math.degrees(L.get_rot("LeftLowerArm").angle)
        a = L.launcher_point(tuple(_mp)); b = L.launcher_point(tuple(_mp + _ml))
        d = (b - a).normalized()
        yaw = math.degrees(math.atan2(-d.z, -d.x)); el = math.degrees(math.asin(max(-1, min(1, d.y))))
        h = L.joint("Head")
        lf = L.joint("LeftHand")
        print("REPORT_PROBE %s Rbend %.0f Lbend %.0f left %s over %.2f yaw %.1f elev %.1f muzzle (%.2f,%.2f,%.2f) mz-head %.2f lhand-head %.2f" % (
            tag, eb, lb, info["left"], info["arm_overreach"], yaw, el, a.x, a.y, a.z, (a - h).length, (lf - h).length))

    for (hx, hy, hz) in ((0.2, 0.14, 0.1), (0.05, 0.14, 0.1), (0.0, 0.1, 0.0), (-0.05, 0.05, -0.05), (0.0, 0.0, 0.1), (-0.1, 0.1, -0.1)):
        HX, HY, HZ = hx, hy, hz
        rows = []
        for i in range(N_CH):
            info = apply(rear_p(i, 1.0))
            rows.append((info["left"][0], math.degrees(L.get_rot("LeftLowerArm").angle), math.degrees(L.get_rot("RightLowerArm").angle)))
        print("REPORT_HI %s maxleft %.2f minLbend %.0f Rbend %.0f..%.0f" % ((hx, hy, hz), max(r[0] for r in rows), min(r[1] for r in rows),
                                                                        min(r[2] for r in rows), max(r[2] for r in rows)))
    HX, HY, HZ = 0.0, 0.05, 0.1
    for i in (0, 4):
        _probe("rear1_%d" % i, rear_p(i, 1.0))
    base_w = FIRE[1][1]
    for at in ((0.8, -0.38, -0.85), (0.75, -0.3, -0.75), (0.7, -0.35, -0.7), (0.8, -0.25, -0.7), (0.65, -0.2, -0.75), (0.9, -0.3, -0.6)):
        p = dict(base_w); p["at"] = Vector(at)
        _probe("windup%s" % (at,), p)
    base_l = FIRE[2][1]
    for (yw, lean, side, wy, at, cy, ce) in (
            (30, -16, -0.3, 16, (0.25, -0.65, -1.7), 6, 15),
            (30, -16, -0.3, 16, (0.3, -0.7, -1.55), 6, 15),
            (30, -16, -0.3, 16, (0.2, -0.65, -1.55), 6, 15),
            (34, -17, -0.35, 16, (0.2, -0.7, -1.55), 4, 14),
            (30, -16, -0.3, 16, (0.35, -0.6, -1.6), 6, 15)):
        p = dict(base_l); p.update(yaw=yw, lean=lean, side=side, waist_yaw=wy, at=Vector(at), cyaw=cy, celev=ce)
        _probe("lunge%s" % ((yw, lean, side, wy, at, cy, ce),), p)
    sys.exit(0)

# ------------------------------------------------------------------ clips
L.new_clip("Ready"); PREV.clear()
for i in range(N_READY):
    r = apply(ready_p(i))
    if i in (0, 6, 12, 18):
        report["ready_%d" % i] = r
    key(i * 3)
apply(ready_p(0)); key(N_READY * 3)
L.make_cyclic("Ready")
READY_PREV = dict(PREV)

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind); PREV.clear(); PREV.update(READY_PREV)
    for i in range(N_CH):
        r = apply(rear_p(i, depth))
        if i in (0, 4, 8, 11):
            report["%s_%d" % (kind, i)] = r
        key(i * 2)
    apply(rear_p(0, depth)); key(N_CH * 2)
    L.make_cyclic(kind)



L.new_clip("Fire"); PREV.clear(); PREV.update(READY_PREV)
names = {WF: "windup", 6: "lunge", 11: "kick", 13: "toss", 16: "shake1", 22: "shake3", 35: "settle"}
for f in list(range(0, 24)) + list(range(24, 46, 2)):
    r = apply(fire_at_frame(f))
    if f in names:
        report[names[f]] = r
    key(f)

L.use_clip("Fire")
_g2 = L.load_meta(LID)["Grip2"]["pos"]
_diag = []
for _i in range(0, 46, 1):
    L.goto(_i / 30.0)
    _diag.append("%d:%.2f/%.2f/e%.0f/%.0f" % (_i, (L.hand_cf("Left").translation - L.launcher_point(_g2)).length, L.launcher_lowest_y(),
                                          math.degrees(L.get_rot("RightLowerArm").angle), math.degrees(L.get_rot("LeftLowerArm").angle)))
print("REPORT_GAP", " ".join(_diag))
for k, v in report.items():
    print("REPORT_POSE", k, v)


def pen_report():
    """how deep the launcher mesh sinks into each body block (the right hand holds it: skipped)"""
    ob = L.launcher_object()
    L.update()
    mw = ob.matrix_world
    verts = [L.b2r(mw @ v.co) for v in ob.data.vertices]
    out = {}
    for name, box, half in L.body_boxes():
        if name == "RightHand":
            continue
        inv = box.inverted()
        worst = 0.0
        for p in verts:
            q = inv @ p
            dx, dy, dz = half.x - abs(q.x), half.y - abs(q.y), half.z - abs(q.z)
            if dx > 0 and dy > 0 and dz > 0:
                worst = max(worst, min(dx, dy, dz))
        if worst > 0.03:
            out[name] = round(worst, 2)
    return out


_mz = L.load_meta(LID)["Muzzle"]["pos"]
for _kind in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
    L.use_clip(_kind)
    _n = int(round(SPEC[_kind] * 30))
    _rows = []
    for _f in range(0, _n + 1, 1 if _kind == "Fire" else 3):
        L.goto(_f / 30.0)
        _r = pen_report()
        if _r:
            _rows.append("f%d%s" % (_f, _r))
    print("REPORT_PEN", _kind, " ".join(_rows) if _rows else "clean")
L.use_clip("Fire")
for _f in (6, 8, 9, 11, 13):
    L.goto(_f / 30.0)
    _m = L.launcher_point(_mz)
    _h = L.joint("Head")
    print("REPORT_MZ f%d muzzle (%.2f,%.2f,%.2f) head (%.2f,%.2f,%.2f)" % (_f, _m.x, _m.y, _m.z, _h.x, _h.y, _h.z))
L.finish(SPEC, OUT, extra_times=[0.1, 0.15, 0.27, 0.3, 0.37, 0.43, 0.5, 0.6])
