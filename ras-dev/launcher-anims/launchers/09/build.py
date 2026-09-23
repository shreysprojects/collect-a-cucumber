"""09 Hand Catapult -- wooden hand-held catapult: a frame on a handle, a cocked arm with a cup on top.

The player stands side-on on the pad (down-track = their LEFT, away from the camera; the camera
sees their right side / back).  The catapult is carried out in front of the belly like a waiter's
tray: the right fist on the handle, the left hand under the frame (meta Grip2), the device
pointing down-track and a little toward the character's front, ~1.4 studs out from the chest so
the frame, the arm and the cup (the ball sits ~3 studs above the grip) stay clear of the chest and
the head.  The pad camera sees the whole device screen-right of the body.
  Ready    held out like a tray, nose slightly down, the ball in the cup; breathing + weight shift.
  ChargeLo COCKING: the left hand hauls the catapult back -- on every heave the device comes in a
           little and tilts back (cup back toward the shoulder), its top leaning OUT away from the
           head, trembling with the tension.
  ChargeHi the same haul tilted much further back, knees bent and braced, a bigger faster-looking
           tremble (SAME cycle count as Lo so the runtime blend stays clean).
  Fire     wind-up (tilt further back, pull in, crouch, turn to the right) -> SNAP: both arms shove
           the catapult forward/up, the frame whips level pointing down-track -> the ball leaves the
           CUP at FireAt in a lob (elev ~37) -> the frame overshoots nose-down and the kick rocks
           the character back -> rebound -> settle to the tray hold.
Ball: always in the cup (Seat), flies from the Seat.

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

LID = 9
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_FRAME = 6
SPEC = {
    "Ready": 2.4, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.3,
    "FireAt": FIRE_FRAME / 30.0,
    "Ball": {"show": "Always", "start": "Seat", "grow": 1.0},
    "Fx": {"Style": "snow", "Color": [235, 245, 255]},
    "TwoHanded": True,
    "AllowFootLift": False,
    "Notes": "hand catapult: tray hold, hauled back + trembling to cock, snaps forward and lobs the ball from the cup",
}
FEET = {"Left": (-0.85, -0.25), "Right": (0.65, 0.35)}
AIM = (-9.0, 1.0, -2.0)          # head target down the track
EA = (0.0, 1.0, 0.0)             # right elbow pole: UP -> the elbow hangs down and out
LEA = (0.3, 1.0, 0.1)            # left elbow pole
report = {}
QREF = [None]
GRIP_Q = [None]
META = L.load_meta(LID)
G2 = META["Grip2"]["pos"]
SEAT = META["Seat"]["pos"]
OB = L.launcher_object()
VERTS = [v.co.copy() for v in OB.data.vertices][::3]


def intrusion():
    """same measure as the library's motion audit, for the current pose: (arm depth, where,
    launcher depth, where) with the realistic avatar sizes"""
    boxes = {n: (b, (L.Vector(L.AUDIT_SIZE[n]) * 0.5 if n in L.AUDIT_SIZE else h)) for n, b, h in L.body_boxes()}
    wa, wat = 0.0, ""
    for arm in L.AUDIT_ARMS:
        ab, ah = boxes[arm]
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for k in (-1, 0, 1):
                    pt = ab @ L.Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                    for body in ("UpperTorso", "Head", "LowerTorso"):
                        d = L._depth_inside(pt, *boxes[body])
                        if d > wa:
                            wa, wat = d, arm + ">" + body
    wl, wlt = 0.0, ""
    mw = OB.matrix_world
    for co in VERTS:
        pt = L.b2r(mw @ co)
        for body in ("UpperTorso", "Head"):
            d = L._depth_inside(pt, *boxes[body])
            if d > wl:
                wl, wlt = d, body
    return round(wa, 2), wat, round(wl, 2), wlt


def pose(yaw=-12.0, lean=-10.0, drop=0.15, back=0.05, side=0.0, rock=0.0,
         waist_yaw=0.0, waist_bend=-5.0,
         grip=(0.5, -0.3, -1.4), lyaw=15.0, elev=-10.0, roll=10.0,
         look=AIM, ea=EA, lea=LEA, audit=False):
    """one key pose: body (stance + waist), catapult in the right hand, left hand on Grip2, head"""
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side,
             root=L.ry(yaw) @ L.rz(rock) @ L.rx(lean), feet=FEET)
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend))
    info = L.hold(grip, yaw=lyaw, elev=elev, roll=roll, elbow_away=ea, grip_twist=GRIP_Q[0])
    for _ in range(3):                                # re-run: the hand-centre offset converges
        info["left"] = L.left_hand_to(key="Grip2", elbow_away=lea)
    L.head_look(target=look)
    q = L.get_rot("Launcher")
    if QREF[0] is None:
        QREF[0] = q.copy()
    info["turn_vs_ready"] = round(math.degrees((QREF[0].inverted() @ q).angle), 1)
    sd = L.launcher_dir(META["Seat"]["look"])
    info["seat_yaw"] = round(math.degrees(math.atan2(-sd.z, -sd.x)), 1)
    info["seat_elev"] = round(math.degrees(math.asin(sd.y)), 1)
    info["gap"] = round((L.hand_cf("Left").translation - L.launcher_point(G2)).length, 3)
    sw, tw = L.swing_twist(L.get_rot("RightHand"))
    info["sw_tw"] = [round(math.degrees(sw.angle), 1), round(math.degrees(tw.angle), 1)]
    info["lreach"] = round((L.launcher_point(G2) - L.joint("LeftUpperArm")).length, 2)
    info["bend_lr"] = [round(math.degrees(L.get_rot("LeftLowerArm").angle), 1), round(math.degrees(L.get_rot("RightLowerArm").angle), 1)]
    if audit:
        info["intr"] = intrusion()
    return info


# ------------------------------------------------------------------ poses (parameter dicts)
READY = dict(yaw=-12.0, lean=-10.0, drop=0.15, back=0.05, side=0.0, rock=0.0, waist_yaw=0.0,
             waist_bend=-5.0, grip=(0.5, -0.3, -1.4), lyaw=15.0, elev=-10.0, roll=10.0, look=AIM,
             ea=EA, lea=LEA)


def ready_p(ph):
    """ph 0..1 around the loop: breathing (2 breaths) + one slow weight shift"""
    br = 0.5 - 0.5 * math.cos(2.0 * math.pi * 2.0 * ph)      # 0..1, two breaths
    sw = math.sin(2.0 * math.pi * ph)                         # weight shift
    return dict(READY, yaw=-12.0 + 2.5 * sw, lean=-10.0 - 1.5 * br, drop=0.14 + 0.03 * br,
                side=0.05 * sw, waist_bend=-5.0 - 1.5 * br,
                grip=(0.5 + 0.02 * sw, -0.3 + 0.05 * br, -1.4), lyaw=15.0 + 2.0 * sw,
                elev=-10.0 - 2.0 * br, roll=10.0 + 1.5 * sw,
                look=(AIM[0], AIM[1] + 0.4 * br, AIM[2]))


GQ_MODE = os.environ.get("L09_GQ", "ready")
if GQ_MODE == "ident":
    GRIP_Q[0] = L.Quaternion((1.0, 0.0, 0.0, 0.0))
elif GQ_MODE == "ready":
    pose(**ready_p(0.0))
    GRIP_Q[0] = L.get_rot("Launcher").copy()
    QREF[0] = None

TREMBLE_CYCLES = 8.0             # per loop, SAME for Lo and Hi (the runtime blends them)


def cock_p(ph, depth):
    """ph 0..1 around the charge loop, depth 0 = ChargeLo, 1 = ChargeHi.
    A slow heave (the left hand hauls the catapult back against its arm: it comes in a little,
    tilts back, the top leaning out away from the head) + a tension tremble.  Same phase timing
    and cycle count for Lo and Hi; Hi = tilted further back, lower, bigger heave + tremble."""
    heave = 0.5 - 0.5 * math.cos(2.0 * math.pi * ph)          # 0 -> 1 -> 0
    tr = math.sin(2.0 * math.pi * TREMBLE_CYCLES * ph)
    tr2 = math.sin(2.0 * math.pi * TREMBLE_CYCLES * ph + 1.3)
    shiver = 2.0 + 3.0 * depth                                # elevation shiver, deg
    jit = 0.015 + 0.025 * depth                               # grip jitter, studs
    elev = 14.0 + 18.0 * depth + (8.0 + 2.0 * depth) * heave + shiver * tr
    return dict(yaw=-12.0 - 4.0 * depth - 2.0 * heave, lean=-7.0 - 1.0 * depth + (2.0 + 1.0 * depth) * heave,
                drop=0.28 + 0.27 * depth + (0.05 + 0.02 * depth) * heave, back=0.08 + 0.07 * depth,
                side=0.04 + 0.04 * depth + 0.3 * jit * tr2, rock=-1.5 - 2.0 * depth,
                waist_yaw=0.0, waist_bend=-3.0 + 1.0 * depth + (1.0 + 1.0 * depth) * heave + 0.2 * shiver * tr2,
                grip=(0.5 + 0.1 * depth + 0.05 * heave + jit * tr2,
                      -0.5 - 0.22 * depth + 0.05 * heave + jit * tr,
                      -1.35 + 0.05 * depth + (0.1 + 0.08 * depth) * heave),
                lyaw=17.0 + 3.0 * depth + 2.0 * heave + 0.3 * shiver * tr2,
                elev=elev, roll=20.0 + 8.0 * depth + (2.0 + 4.0 * depth) * heave + 0.4 * shiver * tr2,
                look=(AIM[0], AIM[1] - 0.3 * depth, AIM[2]), ea=EA, lea=LEA)


def mix(a, b, t):
    a = dict(READY, **a)
    b = dict(READY, **b)
    out = {}
    for k in a:
        if isinstance(a[k], tuple):
            out[k] = tuple(x + (y - x) * t for x, y in zip(a[k], b[k]))
        else:
            out[k] = a[k] + (b[k] - a[k]) * t
    return out


EASE = {
    "inout": lambda t: t * t * (3.0 - 2.0 * t),
    "snap": lambda t: 0.6 * t * t + 0.4 * t,       # quick, a little acceleration into the release
    "out": lambda t: 1.0 - (1.0 - t) ** 2,         # decelerate out of the previous key
}

AUDIT = os.environ.get("L09_AUDIT") == "1"

# ------------------------------------------------------------------ clips
L.new_clip("Ready")
report["ready_0"] = pose(**ready_p(0.0), audit=True)
n = int(round(SPEC["Ready"] * 30))
for f in range(0, n, 3):
    r = pose(**ready_p(f / n), audit=AUDIT)
    L.key(f)
    if AUDIT:
        print("REPORT ready f%d turn %s sw_tw %s" % (f, r["turn_vs_ready"], r["sw_tw"]))
    if f == n // 4:
        report["ready_%d" % f] = r
pose(**ready_p(0.0)); L.key(n)
L.make_cyclic("Ready")

for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind)
    n = int(round(SPEC[kind] * 30))
    for f in range(n):
        r = pose(**cock_p(f / n, depth), audit=(f in (0, n // 2)))
        L.key(f)
        if f in (0, n // 2):
            report["%s_%d" % (kind, f)] = r
    pose(**cock_p(0.0, depth)); L.key(n)
    L.make_cyclic(kind)

# Fire: key poses, then EVERY frame re-solved from eased parameters (hands stay on the catapult)
HI_PEAK = cock_p(0.5, 1.0)
FIRE_KEYS = [
    # 0.00 the ChargeHi pose, at its deepest heave
    (0, "inout", HI_PEAK),
    # 0.10 WIND-UP: tilted further back, pulled in, deeper crouch, the body coiled to the right
    (3, "out", dict(HI_PEAK, yaw=-24.0, elev=HI_PEAK["elev"] + 14.0, drop=HI_PEAK["drop"] + 0.16,
                    lean=HI_PEAK["lean"] - 2.0, back=HI_PEAK["back"] + 0.05, rock=-5.0,
                    waist_bend=HI_PEAK["waist_bend"] + 3.0, roll=HI_PEAK["roll"] + 3.0,
                    lyaw=HI_PEAK["lyaw"] + 3.0,
                    grip=(HI_PEAK["grip"][0] - 0.05, HI_PEAK["grip"][1] - 0.05, HI_PEAK["grip"][2] + 0.08))),
    # 0.20 SNAP (FireAt): both arms shove it forward/up, the frame whips level pointing
    #      down-track, the ball leaves the cup in a lob; the body turns into the shot
    (FIRE_FRAME, "snap", dict(yaw=-4.0, lean=-6.0, drop=0.38, back=0.05, side=0.0, rock=1.0,
                              waist_bend=0.0, grip=(0.35, -0.05, -1.6), lyaw=-10.0, elev=0.0, roll=15.0,
                              look=(-10.0, 4.0, -1.8))),
    # 0.30 overshoot: the frame dips nose-down, the kick rocks the character back
    (9, "out", dict(yaw=-15.0, lean=6.0, drop=0.33, back=0.22, side=0.14, rock=-8.0,
                    waist_bend=4.0, grip=(0.42, -0.2, -1.05), lyaw=2.0, elev=-28.0, roll=10.0,
                    look=(-10.0, 5.0, -1.5))),
    # 0.47 rebound
    (14, "inout", dict(yaw=-10.0, lean=-5.0, drop=0.22, back=0.06, side=0.08, rock=-3.0,
                       waist_bend=-2.0, grip=(0.48, -0.25, -1.42), lyaw=10.0, elev=-4.0, roll=9.0,
                       look=(-10.0, 3.0, -1.8))),
    # 0.73 settling
    (22, "inout", dict(yaw=-11.0, lean=-9.0, drop=0.17, back=0.04, side=0.03, rock=-1.0,
                       waist_bend=-4.5, grip=(0.5, -0.31, -1.4), lyaw=14.0, elev=-12.0, roll=10.0,
                       look=(-9.0, 1.6, -2.0))),
    # 1.30 back to Ready
    (39, "inout", ready_p(0.0)),
]
L.new_clip("Fire")
names = {0: "f0", 3: "windup", FIRE_FRAME: "snap", 9: "over", 14: "reb", 22: "settle"}
for (fa, _, pa), (fb, eb, pb) in zip(FIRE_KEYS[:-1], FIRE_KEYS[1:]):
    for f in range(fa, fb):
        t = EASE[eb]((f - fa) / float(fb - fa))
        r = pose(**mix(pa, pb, t), audit=(f in names or AUDIT))
        L.key(f)
        if AUDIT:
            print("REPORT fire f%d bend %s lreach %s intr %s gap %s" % (f, r["bend_lr"], r["lreach"], r.get("intr"), r["gap"]))
        if f in names:
            report[names[f]] = r
pose(**FIRE_KEYS[-1][2]); L.key(FIRE_KEYS[-1][0])
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in report.items():
    print("REPORT pose %s %s" % (k, json.dumps(v)))

if os.environ.get("L09_FAST") != "1":
    L.finish(SPEC, OUT, extra_times=[0.1, 0.133, 0.167, 0.3, 0.467])
