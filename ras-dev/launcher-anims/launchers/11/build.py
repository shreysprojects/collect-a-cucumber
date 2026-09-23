"""11 Twin Snow Blaster -- blue double-barrel blaster.

Concept: a two-barrel snow blaster held with both hands (right hand on the pistol grip, left hand
under the barrels at Grip2).  The character stands side-on, the blaster sits on its FRONT side
(screen-right in the pad camera) and points down the track (into the screen).
  Ready    carried low across the hips with both hands, barrels angled at the snow, gentle
           breathing sway of the barrels.
  ChargeLo hip-aim down the track, sweeping the barrels slightly left/right like tracking a target.
  ChargeHi wider, lower stance, a bigger sweep and a fast tension shake.
  Fire     brace -> BANG (barrel 1, FireAt) kick up/back -> recover -> BANG (barrel 2, +0.1 s) a
           bigger kick -> settle to the low carry.
Ball: hidden until it pops out of the Muzzle (barrel 1); Muzzle2 = the second barrel's puff.
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

LID = 11
OUT = os.path.dirname(os.path.abspath(__file__))
L.use_launcher(LID)

FIRE_F = 5                      # frame of the first shot
SECOND_F = 8                    # frame of the second shot (0.1 s later)
SPEC = {
    "Ready": 2.0, "ChargeLo": 1.2, "ChargeHi": 1.2, "Fire": 1.4,
    "FireAt": round(FIRE_F / 30.0, 3),
    "SecondShotAt": round(SECOND_F / 30.0, 3),
    "Ball": {"show": "Never", "start": "Muzzle"},
    "Fx": {"Style": "smoke", "Color": [235, 245, 255]},
    "TwoHanded": True,
    "Notes": "twin blaster: hip-aim sweep while charging, double shot (Muzzle then Muzzle2 0.1 s later)",
}
FEET_LO = {"Left": (-0.85, -0.35), "Right": (0.65, 0.45)}
FEET_HI = {"Left": (-1.15, -0.45), "Right": (0.9, 0.55)}
LOOK_TRACK = (-10.0, 0.5, -1.2)
LELB = (0.3, 1.0, -0.4)          # UP-ish pole for the left arm (elbow down, under the barrels)
ELB = (-1.15, 1.0, 0.0)         # UP-ish pole: right elbow hangs down and out, clear of the housing
MAXW = 65.0
QREF = None                     # fixed grip turn, measured from the reference hip aim below
report = {}


def lerp(a, b, t):
    return a + (b - a) * t


def lerp3(a, b, t):
    return tuple(lerp(x, y, t) for x, y in zip(a, b))


def feet_for(depth):
    return {s: lerp3(FEET_LO[s], FEET_HI[s], depth)[:2] for s in FEET_LO}


def body(yaw, lean, drop, back=0.1, waist_yaw=0.0, waist_bend=-6.0, depth=0.0, side=0.0):
    L.reset_pose()
    L.stance(hip_drop=drop, hip_back=back, hip_side=side, root=L.ry(yaw) @ L.rx(lean), feet=feet_for(depth))
    L.waist(L.ry(waist_yaw) @ L.rx(waist_bend))


HEAD_W = None                   # when set: the head keeps this WORLD orientation (Fire kicks)


def hands(look=LOOK_TRACK):
    gap = L.left_hand_to(key="Grip2", elbow_away=LELB)
    if HEAD_W is not None:
        P = L.frame_of("UpperTorso")
        L.set_rot("Head", (P.inverted() @ HEAD_W).to_quaternion())
        L.update()
    else:
        L.head_look(target=look)
    return gap


AIM_YAW, AIM_LEAN, AIM_WYAW, AIM_BEND = 20.0, -9.0, 0.0, -8.0
GZ = -1.45                      # grip distance in front of the body
ROLL = 28.0                   # cant: hopper rolled toward the character's front, away from the head


def aim(sweep=0.0, depth=0.0, shake=(0.0, 0.0), recoil=0.0, kick=0.0, lean_add=0.0, side=0.0):
    """hip aim down the track.  sweep degrees (+ = toward the character's front),
    depth 0..1 = charge, shake = (dy, dyaw) small jitter, recoil 0..1 = grip shoved back, kick
    = extra muzzle elevation degrees, side = hip-to-hip weight shift (studs, + = right)"""
    def pose_body(rc):
        body(yaw=AIM_YAW - 0.8 * sweep, lean=AIM_LEAN - 4.0 * depth + lean_add + 13.0 * rc,
             drop=0.2 + 0.4 * depth, back=0.1 + 0.08 * depth + 0.12 * rc,
             waist_yaw=AIM_WYAW - 0.5 * sweep - 8.0 * rc, waist_bend=AIM_BEND - 3.0 * depth + 7.0 * rc,
             depth=depth, side=side)
    grip = Vector((0.45, -0.95 - 0.35 * depth + shake[0], GZ + 0.1 * depth - 0.005 * sweep))
    if recoil > 0.0:
        # the recoil rides the chest: keep the grip where it sat relative to the UpperTorso, then
        # shove it back / up toward the shoulder a little (the arms COMPRESS, never straighten)
        pose_body(0.0)
        local = L.frame_of("UpperTorso").inverted() @ (grip - L.joint("RightUpperArm"))
        pose_body(recoil)
        grip = L.joint("RightUpperArm") + L.frame_of("UpperTorso") @ local + Vector((0.06, 0.06, 0.2)) * recoil
    else:
        pose_body(0.0)
    grip = tuple(grip)
    info = L.hold(grip, yaw=sweep + shake[1], elev=6.0 + kick, roll=ROLL, elbow_away=ELB, grip_twist=QREF, max_wrist=MAXW)
    info["lgap"] = hands()
    return info


def carry(b, s=0.0, gz=-1.36):
    """Ready: low carry at the hips, barrels angled at the snow ahead; b 0..1 breathing,
    s -1..1 = the barrels' lazy side-to-side sway"""
    body(yaw=8.0 - 5.0 * s, lean=-13.5 - 1.2 * b, drop=0.12 + 0.07 * b, waist_yaw=-2.0 - 5.0 * s,
         waist_bend=-14.0 + 1.0 * b)
    info = L.hold((0.12, -1.02 + 0.07 * b, gz + 0.03 * s), yaw=7.0 + 14.0 * s, elev=-14.0 - 5.0 * b,
                  roll=ROLL, elbow_away=ELB, grip_twist=QREF)
    info["lgap"] = hands((-8.0, -1.6, -2.0 - 0.5 * s))
    return info


# reference hold: let the solver find the natural grip turn for the hip aim, then keep that SAME
# turn in every pose (the wrist does the rest), so the launcher never slides around in the hand
MAXW = 45.0
aim()
MAXW = 65.0
QREF = L.get_rot("Launcher").copy()
print("POSE QREF", [round(v, 3) for v in QREF])

# ------------------------------------------------------------------ Ready
L.new_clip("Ready")
report["ready0"] = carry(0.0, 0.0); L.key(0)
report["ready1"] = carry(1.0, 1.0); L.key(15)
carry(0.0, 0.0); L.key(30)
report["ready3"] = carry(1.0, -1.0); L.key(45)
carry(0.0, 0.0); L.key(60)
L.make_cyclic("Ready")

# ------------------------------------------------------------------ Charge (Lo / Hi share phase)
N = 36                          # 1.2 s
for kind, depth in (("ChargeLo", 0.0), ("ChargeHi", 1.0)):
    L.new_clip(kind)
    amp = 10.0 + 6.0 * depth                 # sweep amplitude (deg)
    sh = 0.0 + 1.0 * depth                   # shake amount
    for f in range(0, N, 3):
        ph = f / N
        sn = math.sin(2.0 * math.pi * ph)
        sweep = amp * sn + 0.4 * amp         # biased toward the front: barrels stay screen-right of the head
        jit = ((0.1 * sh) * (1 if (f // 3) % 2 == 0 else -1), (5.0 * sh) * (1 if (f // 3) % 4 < 2 else -1))
        if f == 0:
            jit = (0.0, 0.0)
        r = aim(sweep=sweep, depth=depth, shake=jit, side=-(0.07 + 0.05 * depth) * sn)
        if f in (0, 9, 27):
            report["%s_%d" % (kind, f)] = r
        L.key(f)
    aim(sweep=0.4 * amp, depth=depth); L.key(N)
    L.make_cyclic(kind)

# ------------------------------------------------------------------ Fire
L.new_clip("Fire")
aim(sweep=6.4, depth=1.0); L.key(0)                           # the charge pose (ChargeHi f0)
aim(sweep=2.0, depth=1.0, lean_add=-2.5, shake=(-0.03, 0.0)); L.key(2)   # lock on
aim(sweep=0.5, depth=1.0, lean_add=-3.5, shake=(-0.05, 0.0)); L.key(FIRE_F - 1)   # brace, squeeze
report["shot1"] = aim(depth=0.95, lean_add=-3.0); L.key(FIRE_F)   # BANG 1 (barrel 1)
HEAD_W = L.frame_of("Head").copy()                            # the eyes stay on target through the kicks
aim(depth=0.95, lean_add=-3.0)
print("HEADCHECK", round(max(abs(a - b) for ra, rb in zip(L.frame_of("Head"), HEAD_W) for a, b in zip(ra, rb)), 4))
report["kick1"] = aim(depth=0.9, recoil=0.6, kick=10.0); L.key(FIRE_F + 1)
aim(depth=0.88, recoil=0.3, kick=5.0); L.key(SECOND_F - 1)     # recover a little
report["shot2"] = aim(depth=0.85, recoil=0.15, kick=2.5); L.key(SECOND_F)   # BANG 2 (barrel 2)
report["kick2"] = aim(depth=0.8, recoil=0.9, kick=14.0); L.key(SECOND_F + 1)
report["rise2"] = aim(depth=0.72, recoil=1.0, kick=17.0); L.key(SECOND_F + 3)   # the heavier kick carries on up
aim(depth=0.55, recoil=0.5, kick=9.0); L.key(18)              # settle
HEAD_W = None
aim(depth=0.3, recoil=0.1, kick=-4.0); L.key(26)
carry(0.8, gz=-1.5); L.key(32)                          # lower it out in front, clear of the arm
report["lower"] = carry(0.4); L.key(37)
carry(0.0); L.key(42)
L.set_interpolation("Fire", 'BEZIER', 'AUTO_CLAMPED')

for k, v in report.items():
    print("POSE", k, v)
L.finish(SPEC, OUT, extra_times=[SPEC["SecondShotAt"], (FIRE_F + 1) / 30.0, (SECOND_F + 1) / 30.0])
