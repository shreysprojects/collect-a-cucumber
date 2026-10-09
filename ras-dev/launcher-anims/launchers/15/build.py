"""15 Avalanche Mortar -- tripod mortar: cradle it, crouch and range the tube, THUMP + lob.

The grip pivot is at the tripod base (right hand under the base); the tube axis is the meta
Muzzle look, 31 deg forward of the launcher's top.  Everything happens on the character's FRONT
side (screen-right in the pad camera) so the tube and the lob read from the game camera.
  Ready    mortar cradled against the chest, tube up, right hand under the tripod, left hand
           on the tube's handle; slow breathing + a small weight shift.
  ChargeLo crouched, the mortar at the hip, the tube laid over toward the track at ~44 deg;
           RANGING: the tube nods up/down a few degrees in rhythm with a small knee bounce.
  ChargeHi same rhythm, deeper braced crouch, bigger nods + a strained tremble.
  Fire     a short squeeze -> THUMP at FireAt: the ball lobs out of the tube (elev ~44) while
           the mortar SLAMS down + up-track into the hands, the knees buckle, the head nods -> rebound -> the
           mortar is lifted back to the chest.
The right fist keeps ONE fixed grip on the tripod base (GRIP); each key pose searches the base
position / elbow that keeps the wrist natural and the tube off the body.
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

LID = 15
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.5,
    "FireAt": 0.20,
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "smoke"},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "tripod mortar: cradled at the chest, crouch and range the tube at the hip, THUMP - kick down, knees buckle, ball lobs out of the tube",
}
FEET = {"Left": (-0.8, -0.35), "Right": (0.7, 0.3)}
ROLL = -25.0        # tube rolled so the body-side tripod foot tips down, clear of the belly
TILT = 59.0          # launcher forward axis = look elevation - TILT (tube 31 deg off the top)
L_ELBOW = (0.3, 1.0, 0.1)    # up-ish pole: the left elbow hangs down and out (clear of the chest)
CH_YAW = 20.0       # body turn toward the track while charging
META = L.load_meta(LID)
G2 = META["Grip2"]["pos"]
MZ = (0.0, -0.79, -1.83)   # the tube mouth (the Muzzle sits 0.45 beyond it, where the ball pops out)
TUBE = [tuple(MZ[k] * f for k in range(3)) for f in (0.35, 0.55, 0.75, 0.95)]
# the parts that poked the torso in earlier runs: the body-side tripod foot, the tube's lower back
HULL = [(-1.0, 0.15, 0.0), (-1.0, -0.15, 0.0), (-0.9, 0.0, -0.1), (-0.3, 0.48, -0.2), (-0.3, 0.45, -0.5),
        (-0.3, 0.35, -0.9), (-0.6, 0.3, -0.6)]
TUBE_R = 0.55        # rough tube radius (studs, scaled) for the body-clearance cost
ARM_PARTS = ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand")
ELBOWS = [Vector(v).normalized() for v in (
    (1.0, -1.0, 0.3), (1.0, -1.0, -0.3), (1.0, -0.2, 0.6), (0.4, -1.0, 0.6), (1.0, -0.3, -0.6),
    (0.2, -1.0, -0.2), (1.0, 0.3, 0.2), (0.5, -0.6, 1.0))]
dbg = {}


def body(yaw=0.0, lean=-10.0, drop=0.2, back=0.1, side=0.0, waist_yaw=0.0, waist_bend=-8.0, waist_roll=0.0, roll=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean) @ L.rz(roll), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend) @ L.rz(waist_roll))


def wrist_swing():
    sw, tw = L.swing_twist(L.get_rot("RightHand"))
    ta = math.degrees(tw.angle)
    return math.degrees(sw.angle), (360.0 - ta if ta > 180.0 else ta)


def gap():
    return (L.hand_cf("Left").translation - L.launcher_point(G2)).length


def tube_axes(yaw, elev, roll):
    """launcher forward / top (world) that put the TUBE (Muzzle look) along direction(yaw, elev),
    rolled `roll` deg about the tube itself"""
    look = L.direction(yaw, elev)
    Rm = L.look_frame(look, L.up_for(look, roll))
    Am = L.look_frame(META["Muzzle"]["look"], META["Muzzle"]["up"])
    Rp = Rm @ Am.transposed()
    return Rp @ Vector((0.0, -1.0, 0.0)), Rp @ Vector((0.0, 0.0, -1.0))


# the one grip: how the fist holds the tripod base, taken from a natural mid-charge pose
body(yaw=12.0, lean=-12.0, drop=0.55, back=0.25, waist_yaw=4.0, waist_bend=-6.0)
_f, _u = tube_axes(0.0, 44.0, ROLL)
L.place_launcher((0.45, -1.2, -1.75), _f, _u, anchor="Pivot", elbow_away=(1.0, -1.0, 0.4))
GRIP = L.get_rot("Launcher")


def _surface_samples(spacing=0.08):
    """dense points on the launcher's SURFACE (every triangle sampled on a barycentric grid, thinned
    to one per `spacing`-stud cell), in launcher-local template units.  Unlike the vertices alone
    these catch a head block pushing through a big flat face (the flared tube wall)."""
    import bpy
    L.update()
    ob = L.launcher_object()
    dg = bpy.context.evaluated_depsgraph_get()
    obe = ob.evaluated_get(dg)
    mw = obe.matrix_world
    me = obe.to_mesh()
    me.calc_loop_triangles()
    inv = L.pivot_cf().inverted()
    S = L.LAUNCHER_SCALE
    cells = {}
    n = 6
    for tri in me.loop_triangles:
        a, b, c = (me.vertices[i].co for i in tri.vertices)
        for i in range(n + 1):
            for j in range(n + 1 - i):
                w = (a * (n - i - j) + b * i + c * j) / n
                p = L.b2r(mw @ w)
                key_ = (round(p.x / spacing), round(p.y / spacing), round(p.z / spacing))
                if key_ not in cells:
                    cells[key_] = (inv @ p) / S
    obe.to_mesh_clear()
    return list(cells.values())


SURF = _surface_samples()
print("REPORTS surface samples %d" % len(SURF))


def _signed(p, inv, half):
    q = inv @ p
    o = Vector((max(abs(q.x) - half.x, 0.0), max(abs(q.y) - half.y, 0.0), max(abs(q.z) - half.z, 0.0)))
    if o.length > 0.0:
        return o.length
    return -min(half.x - abs(q.x), half.y - abs(q.y), half.z - abs(q.z))


def _thin(pts, spacing):
    cells = {}
    for q in pts:
        cells.setdefault(tuple(round(v * L.LAUNCHER_SCALE / spacing) for v in q), q)
    return list(cells.values())


SURF_C = _thin(SURF, 0.16)     # coarser copy for the pose-search cost
LEGS = ("LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg")


def surf_clear(parts=("Head",), samples=None):
    """{part: smallest signed distance of the launcher surface to that body block} (< 0 = inside)"""
    pc = L.pivot_cf()
    S = L.LAUNCHER_SCALE
    pts = [pc @ (q * S) for q in (SURF if samples is None else samples)]
    out = {}
    for name, box, half in L.body_boxes():
        if name not in parts:
            continue
        inv = box.inverted()
        out[name] = min(_signed(p, inv, half) for p in pts)
    return out


def _place(P, fwd, up, e):
    return L.place_launcher(at=P, forward=fwd, up=up, anchor="Pivot", elbow_away=e, grip_twist=GRIP)


def _box(bone):
    centre, size = L.PART_BLOCKS[bone]
    k = L.BLOCK_SHRINK.get(bone, 1.0)
    half = Vector((size[0] * k, size[1], size[2] * k)) * 0.5
    return L.world_cf(bone) @ L.cf(Vector(centre) - Vector(L.REST[bone])), half


def head_clear():
    """smallest clearance of the LEFT arm blocks from the Head block (5 samples along each block's
    long axis minus its half-width; < 0 = the arm is inside the head)"""
    hb, hh = _box("Head")
    worst = 9.0
    for limb in ("LeftUpperArm", "LeftLowerArm", "LeftHand"):
        box, half = _box(limb)
        r = min(half.x, half.z)
        for s in (-0.9, -0.45, 0.0, 0.45, 0.9):
            p = box @ Vector((0.0, s * half.y, 0.0))
            worst = min(worst, L.point_box_distance(p, hb, hh) - r)
    return worst


def left_hand():
    L.left_hand_to(point=L.launcher_point(G2), elbow_away=L_ELBOW)


def cost_now(offset):
    sw, tw = wrist_swing()
    c = sw + 25.0 * max(0.0, tw - 70.0) / 10.0 + 40.0 * offset
    el = L.joint("RightLowerArm")
    ce, _ = L.clearance(el, skip=ARM_PARTS)
    c += 150.0 * max(0.0, 0.15 - ce)
    for p in TUBE:
        cs, _ = L.clearance(L.launcher_point(p), skip=ARM_PARTS)
        c += 150.0 * max(0.0, TUBE_R + 0.1 - cs)
    for p in HULL:
        cs, _ = L.clearance(L.launcher_point(p), skip=ARM_PARTS)
        c += 300.0 * max(0.0, 0.12 - cs)
    left_hand()
    c += 150.0 * gap()
    c += 400.0 * max(0.0, 0.12 - head_clear())
    sc = surf_clear(("Head",) + LEGS, SURF_C)
    c += 600.0 * max(0.0, 0.1 - sc.pop("Head"))
    c += 400.0 * max(0.0, 0.1 - min(sc.values()))
    return c



REACH = math.sqrt(L.ARM_SIDE_OFFSET ** 2 + (L.UPPER_ARM + L.LOWER_ARM) ** 2)
MARGIN = 0.16       # keep the right wrist this far INSIDE full reach (no straight-arm elbow pops)


def reach_margin(info):
    """studs the right wrist target sits inside full reach (< 0 = overreach)"""
    d = (L.joint("RightHand") - L.joint("RightUpperArm")).length
    return REACH - d - info["arm_overreach"]


def pull_in(P, fwd, up, e):
    """moves the tripod base toward the right shoulder until the wrist is MARGIN inside reach
    (the fist's grip on the base is rigid, so the base moves 1:1 with the wrist)"""
    P = Vector(P)
    for _ in range(3):
        info = _place(P, fwd, up, e)
        m = reach_margin(info)
        if m >= MARGIN - 0.005:
            break
        d = (L.joint("RightUpperArm") - L.joint("RightHand")).normalized()
        P = P + d * (MARGIN - m)
    return P


def mortar(P, yaw, elev, roll=ROLL, name=None, look=None, radius=0.3, step=0.15, fix=None, elbows=None):
    """tripod base near P, tube (Muzzle look) along direction(yaw, elev).  The base offset + right
    elbow are searched, or reused from fix=(offset, elbow) so a loop's keys hold one arm solution.
    Returns (offset, elbow)."""
    fwd, up = tube_axes(yaw, elev, roll)
    P0 = Vector(P)
    if fix is None:
        elbows = elbows or ELBOWS
        P = pull_in(P0, fwd, up, elbows[0])
        n = int(round(radius / step))
        best = None
        for i in range(-n, n + 1):
            for j in range(-n, n + 1):
                for k in range(-n, n + 1):
                    off = Vector((i * step, j * step, k * step))
                    if off.length > radius + 1e-6:
                        continue
                    for e in elbows:
                        info = _place(Vector(P) + off, fwd, up, e)
                        c = cost_now(off.length) + 300.0 * max(0.0, MARGIN - 0.03 - reach_margin(info))
                        if best is None or c < best[0]:
                            best = (c, off, e)
        c, off, e = best
        Pq = pull_in(Vector(P) + off, fwd, up, e)
    else:
        off, e = fix
        c = -1.0
        Pq = pull_in(P0 + off, fwd, up, e)
    info = _place(Pq, fwd, up, e)
    left_hand()
    if look is not None:
        L.head_look(target=look)
    if name:
        sw, tw = wrist_swing()
        mz = L.pivot_cf() @ L._meta_frame(META, "Muzzle")
        base = L.launcher_point((0.0, 0.0, 0.0))
        dbg[name] = {"cost": round(c, 1), "P": [round(v, 2) for v in Pq], "elbow": [round(v, 2) for v in e],
                     "swing": round(sw, 1), "twist": round(tw, 1), "gap": round(gap(), 3),
                     "headclr": round(head_clear(), 2), "headsurf": round(surf_clear()["Head"], 2),
                     "lhand": [round(v, 2) for v in L.hand_cf("Left").translation],
                     "head": [round(v, 2) for v in L.joint("Head")],
                     "base": [round(v, 2) for v in base],
                     "reach": info["arm_overreach"], "margin": round(reach_margin(info), 2), "muzzle": [round(v, 2) for v in mz.translation],
                     "low": round(L.launcher_lowest_y(), 2)}
    return Pq - P0, e


_LASTQ = {}
_FIRSTQ = {}


def key(frame, close=False):
    """L.key with quaternion sign continuity (q and -q are the same turn, but the F-curves
    interpolate the components, so a sign flip between two keys swings the bone the long way)"""
    r = L.rig()
    for pb in r.pose.bones:
        q = pb.rotation_quaternion
        prev = _FIRSTQ.get(pb.name) if close else _LASTQ.get(pb.name)
        if prev is not None and prev.dot(q) < 0.0:
            pb.rotation_quaternion = -q
        _LASTQ[pb.name] = pb.rotation_quaternion.copy()
        _FIRSTQ.setdefault(pb.name, pb.rotation_quaternion.copy())
    L.key(frame)


def new_clip(kind):
    _LASTQ.clear()
    _FIRSTQ.clear()
    return L.new_clip(kind)


# ------------------------------------------------------------------ poses
def ready(b, s=0.0, name=None, fix=None):
    """b 0..1 breathing, s -1..1 weight shift.  The mortar is carried low and forward so the left
    hand on the tube sits at chest height, well clear of the face."""
    body(yaw=16.0 + 5.0 * s, lean=-3.0 - 3.0 * b, drop=0.08 + 0.06 * b, back=0.05, side=0.1 * s,
         waist_yaw=2.0 - 2.0 * s, waist_bend=-2.0 + 4.0 * b, waist_roll=2.0 * s)
    return mortar((0.35 + 0.04 * s, -0.95 + 0.1 * b, -1.6), 60.0 + 3.0 * s, 64.0 + 4.0 * b, roll=15.0, name=name,
                  look=(-5.0, 0.5, -1.8), fix=fix)


def ranging(t, depth, name=None, shake=0.0, fix=None, elbows=None):
    """RANGING the tube: t 0..1 phase (0 = low + traversed back, 1 = high + traversed out),
    depth 0 (Lo) .. 1 (Hi), shake = strained tremble offset (Hi only, alternating +-1)"""
    body(yaw=CH_YAW + 4.0 * shake, lean=-8.0 - 2.0 * depth - 3.0 * t,
         drop=0.42 + 0.5 * depth - (0.22 + 0.12 * depth) * t + 0.05 * shake,
         back=0.25 + 0.12 * depth, waist_yaw=8.0 + (3.0 + 2.0 * depth) * t, waist_bend=-3.0 - 1.0 * depth + 4.0 * shake,
         waist_roll=3.0 * shake)
    u = (t - 0.5) * 2.0
    el = 44.0 + (7.0 + 4.0 * depth) * u + 2.5 * shake
    yaw = 5.0 + (6.0 + 2.0 * depth) * u + 1.5 * shake
    return mortar((0.45 + 0.08 * shake, -1.13 - 0.28 * depth + 0.12 * t, -1.85 - 0.08 * depth), yaw, el, name=name,
                  look=(-8.0, 2.0 + 0.8 * t, -1.5), fix=fix, elbows=elbows)


# ------------------------------------------------------------------ clips
new_clip("Ready")
fx = ready(0.0, 0.0, "ready0"); key(0)
ready(1.0, 0.5, "ready1", fix=fx); key(18)
ready(0.2, 1.0, fix=fx); key(36)
ready(0.9, -0.3, fix=fx); key(54)
ready(0.0, 0.0, fix=fx); key(72, close=True)
L.make_cyclic("Ready")
READY_FIX = fx

# ONE right-arm solution for both charge clips (the runtime blends Lo/Hi by the live charge):
# the elbow is searched on the Hi pose, Lo searches only its base offset with that elbow
HI_SEARCH = ranging(0.5, 1.0)
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    sh = 1.0 if depth > 0.5 else 0.0
    new_clip(kind)
    fx = HI_SEARCH if depth > 0.5 else ranging(0.5, depth, elbows=[HI_SEARCH[1]])
    # two nods per loop (0.6 s each); ChargeHi adds a strained tremble between the main keys
    ranging(0.0, depth, kind + "_low", fix=fx); key(0)
    if sh:
        ranging(0.5, depth, kind + "_shake", shake=1.0, fix=fx); key(4)
    ranging(1.0, depth, kind + "_high", fix=fx); key(9)
    if sh:
        ranging(0.7, depth, shake=-1.0, fix=fx); key(13)
    ranging(0.4, depth, fix=fx); key(18)
    if sh:
        ranging(0.65, depth, shake=1.0, fix=fx); key(22)
    ranging(0.9, depth, fix=fx); key(27)
    if sh:
        ranging(0.45, depth, shake=-1.0, fix=fx); key(31)
    ranging(0.0, depth, fix=fx); key(36, close=True)
    L.make_cyclic(kind)
HI_FIX = fx

new_clip("Fire")
ranging(0.5, 1.0, fix=HI_FIX); key(0)
# 0.20 THUMP (FireAt): the ball leaves the tube (solved first: its base + elbow are pinned
# through the squeeze / kick / absorb keys so the fist never slides on the tripod)
body(yaw=20.0, lean=-9.0, drop=0.8, back=0.36, waist_yaw=9.0, waist_bend=-3.0)
FIRE_P = Vector((0.45, -1.42, -2.05))
fx = mortar(FIRE_P, 3.0, 44.0, name="fire", look=(-8.0, 3.0, -1.2)); key(6)
FIRE_BASE = FIRE_P + fx[0]
PIN = (Vector((0.0, 0.0, 0.0)), fx[1])      # exact base, the fire elbow
# 0.10 squeeze / brace: shoulders drop, the tube pulls down into the hands, 4 deg lower -> snap
body(yaw=20.0, lean=-12.0, drop=1.0, back=0.4, waist_yaw=9.0, waist_bend=-6.0)
mortar(FIRE_BASE + Vector((0.03, -0.16, 0.03)), 3.0, 40.0, name="squeeze", look=(-8.0, 2.5, -1.2), fix=PIN); key(3)
# 0.30 KICK: the mortar slams ~0.6 studs down the tube axis into the hands, the knees buckle,
# the torso rolls away from the track and the head nods down with the impact
TUBE_BACK = -L.direction(3.0, 44.0)
KICK = TUBE_BACK * 0.6 + Vector((-0.03, 0.0, -0.25))
body(yaw=20.0, lean=-9.0, drop=1.22, back=0.4, side=0.18, waist_yaw=9.0, waist_bend=-3.0, roll=-6.0)
mortar(FIRE_BASE + KICK, 3.0, 49.0, name="kick", look=(-7.0, -2.0, -1.2), fix=PIN); key(9)
# 0.40 absorb: bottom of the buckle, the head comes back up to the lob
body(yaw=20.0, lean=-10.5, drop=1.22, back=0.4, side=0.14, waist_yaw=9.0, waist_bend=-2.0, roll=-4.0)
mortar(FIRE_BASE + KICK * 0.88, 3.0, 46.0, name="absorb", look=(-9.0, 1.5, -1.2), fix=PIN); key(12)
# 0.55 rebound up (clear overshoot out of the buckle), watching the lob
body(yaw=20.0, lean=-7.0, drop=0.4, back=0.22, waist_yaw=7.0, waist_bend=-3.0)
fr = mortar((0.5, -1.2, -1.85), 3.0, 46.0, name="recover", look=(-12.0, 4.0, -1.2)); key(16)
# 0.87 still watching, starting to lift it back to the chest
body(yaw=18.0, lean=-6.0, drop=0.3, back=0.15, waist_yaw=4.0, waist_bend=-3.0)
mortar((0.4, -1.2, -1.75), 30.0, 56.0, roll=-10.0, name="lift", look=(-12.0, 2.0, -1.5)); key(26)
# 1.20 halfway to the carry
body(yaw=17.0, lean=-4.5, drop=0.19, back=0.1, waist_yaw=3.0, waist_bend=-2.5)
mortar((0.37, -1.23, -1.78), 45.0, 60.0, roll=-5.0, name="lift2", look=(-8.0, 1.0, -2.2)); key(36)
ready(0.0, 0.0, fix=READY_FIX); key(45)


def pin_left(kind, skip=(), step=2):
    """between the key poses the two arm IK solutions interpolate apart; re-solve the LEFT arm on
    the in-between frames so the steadying hand stays on the tube (keys only the left arm)"""
    act = L.use_clip(kind)
    keyed = set()
    for fc in L.fcurves(act):
        keyed |= {int(round(kp.co.x)) for kp in fc.keyframe_points}
    last = max(keyed)
    r = L.rig()
    arm = ("LeftUpperArm", "LeftLowerArm", "LeftHand")
    for f in range(1, last, step):
        if f in keyed or f in skip:
            continue
        L.goto(f / 30.0)
        before = {b: r.pose.bones[b].rotation_quaternion.copy() for b in arm}
        # the rest of the pose stays as interpolated (the animation is re-applied on goto)
        left_hand()
        for b in arm:
            pb = r.pose.bones[b]
            if pb.rotation_quaternion.dot(before[b]) < 0.0:
                pb.rotation_quaternion = -pb.rotation_quaternion
            pb.keyframe_insert("rotation_quaternion", frame=f)


for _k in ("ChargeLo", "ChargeHi"):
    pin_left(_k, step=1)
    L.make_cyclic(_k)
pin_left("Fire", skip=(7, 8), step=1)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')
# the THUMP snaps: straight line from the shot into the kick
L.set_interpolation("Fire", 'LINEAR', 'VECTOR', frames=[6])

def body_hits():
    """launcher vertices inside a non-arm body block (0 = clean)"""
    ob = L.launcher_object()
    L.update()
    mw = ob.matrix_world
    boxes = [b for b in L.body_boxes() if b[0] not in ARM_PARTS]
    hits = {}
    for v in list(ob.data.vertices)[::3]:
        p = L.b2r(mw @ v.co)
        for name, box, half in boxes:
            if L.point_box_distance(p, box, half) < 1e-4:
                hits[name] = hits.get(name, 0) + 1
                if VERB:
                    q = L.pivot_cf().inverted() @ p / L.LAUNCHER_SCALE
                    print("REPORTV %s local %.2f %.2f %.2f depth %.2f" % (name, q.x, q.y, q.z,
                          min(h - abs(a) for h, a in zip(half, box.inverted() @ p))))
    return hits


VERB = False
SURF_PARTS = ("Head", "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
              "LeftFoot", "RightFoot", "LeftUpperArm")
for kind in ("Ready", "ChargeLo", "ChargeHi", "Fire"):
    L.use_clip(kind)
    out = []
    hc_min, gap_max, gap_at = 9.0, 0.0, 0
    sw = {}
    for i in range(0, int(SPEC[kind] * 30) + 1, 1):
        L.goto(i / 30.0)
        hc_min = min(hc_min, head_clear())
        for part, d in surf_clear(SURF_PARTS).items():
            if part not in sw or d < sw[part][0]:
                sw[part] = (d, i)
        gp = gap()
        if gp > gap_max:
            gap_max, gap_at = gp, i
        if i % 3 == 0:
            h = body_hits()
            if h:
                out.append("%d:%s" % (i, h))
    print("REPORTC %s headclr_min %.2f gap_max %.2f@%d %s" % (kind, hc_min, gap_max, gap_at, " ".join(out)))
    print("REPORTSURF %s %s" % (kind, " ".join("%s %.2f@%d" % (p, d, f) for p, (d, f) in sorted(sw.items()) if d < 0.1)))
for k, v in dbg.items():
    print("REPORTK %s %s" % (k, json.dumps(v)))
L.finish(SPEC, OUT, extra_times=[0.1, 0.3, 0.4, 0.55, 0.85])
