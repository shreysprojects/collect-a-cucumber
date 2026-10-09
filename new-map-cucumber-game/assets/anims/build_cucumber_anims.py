"""build_cucumber_anims.py -- authors the two cucumber-collect clips on the R15Rig
(CucumberAnims.blend) and exports them:

  CucumberPickUp   1.4 s, one-shot : bend at the hips + waist, both hands to the
                   cucumber on the ground, close the grip, lift it to the chest
                   (server welds it to the shoulder at GRAB_T = 1.0 s), stand up with
                   the left hand steadying it on the shoulder.
  CucumberStruggle 1.0 s loop      : gripping pose -> deep pull-back lean with straight
                   arms (tremble) -> slips back toward the grip pose.

Outputs (assets/anims/): <Name>.json (15 fps pose samples: per bone quaternion w,x,y,z
+ optional translation, Roblox joint frames), <Name>.fbx (Roblox Animation Editor
"Import from FBX Animation") and preview_*.png renders.

Run inside Blender:  exec(open(r"...\\build_cucumber_anims.py").read())
"""
import bpy
import importlib
import os
import sys

HERE = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\assets\anims"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import r15animlib as L
importlib.reload(L)

FPS = 30
SAMPLE_FPS = 15
PICKUP_LEN = 1.4
STRUGGLE_LEN = 1.0
CUKE = L.CUKE_POS
GRIP_OPEN = {"Left": (-0.55, -2.02, -1.72), "Right": (0.55, -2.02, -1.72)}
GRIP_CLOSED = {"Left": (-0.42, -2.12, -1.78), "Right": (0.42, -2.12, -1.78)}
LIFT = {"Left": (-0.38, -0.95, -1.3), "Right": (0.38, -0.95, -1.3)}
CARRY_LEFT = (-1.05, 0.35, -0.72)

report = {}


def idle(arms_out=4.0):
    L.reset_pose()
    L.set_rot("LeftUpperArm", L.rz(-arms_out))
    L.set_rot("RightUpperArm", L.rz(arms_out))


def bent(hip_drop, root_pitch, waist_pitch, grip, head_target=CUKE, tag=None, hip_back=0.0):
    L.reset_pose()
    legs = L.pose_legs(hip_drop, root_pitch, hip_back=hip_back)
    L.set_rot("UpperTorso", L.rx(waist_pitch))
    arms = L.pose_arms(grip)
    pitch = L.pose_head(target=head_target)
    if tag:
        report[tag] = {"legs": legs, "arms": arms, "head_pitch": round(pitch, 1),
                       "wristL": [round(v, 2) for v in L.joint("LeftHand")],
                       "shoulderL": [round(v, 2) for v in L.joint("LeftUpperArm")]}
    return arms


r = L.rig()
r.location = (0.0, 0.0, 0.0)
L.preview_blocks()
L.props()

# ------------------------------------------------------------------ pick up
pick = L.new_action("CucumberPickUp", FPS)
idle()
L.key_all(0)
bent(0.22, -22.0, -68.0, GRIP_OPEN, tag="pick_reach")
L.key_all(13)                      # 0.433 s  hands arrive at the cucumber
bent(0.24, -24.0, -70.0, GRIP_CLOSED, tag="pick_grip")
L.key_all(21)                      # 0.700 s  grip closed
bent(0.12, -10.0, -32.0, LIFT, tag="pick_lift")
L.key_all(30)                      # 1.000 s  GRAB_T: load at the chest, server welds it to the shoulder
L.reset_pose()
L.pose_legs(0.0, 0.0)
L.set_rot("UpperTorso", L.rx(-3.0))
L.pose_arms({"Left": CARRY_LEFT})
L.set_rot("RightUpperArm", L.rz(4.0))
L.pose_head(pitch=4.0, yaw=8.0)
report["pick_end"] = {"wristL": [round(v, 2) for v in L.joint("LeftHand")]}
L.key_all(42)                      # 1.400 s  upright, left hand steadying the shoulder load

# ------------------------------------------------------------------ struggle (loop)
strug = L.new_action("CucumberStruggle", FPS)
bent(0.24, -24.0, -70.0, GRIP_CLOSED, tag="strug_grip")
L.key_all(0)
# the R15 arms are short: the hands only stay on the cucumber if the shoulders stay
# low, so the "pull" is a hips-back squat rock (hip_back) with the back still bent
bent(0.45, -14.0, -54.0, GRIP_CLOSED, tag="strug_pull", hip_back=0.38)
L.key_all(10)                      # 0.333 s  pull-back peak, arms straight
bent(0.48, -11.0, -51.0, GRIP_CLOSED, hip_back=0.42)
L.key_all(13)                      # tremble
bent(0.44, -16.0, -56.0, GRIP_CLOSED, hip_back=0.36)
L.key_all(16)
bent(0.47, -12.0, -52.0, GRIP_CLOSED, hip_back=0.40)
L.key_all(19)
bent(0.34, -20.0, -62.0, GRIP_CLOSED, tag="strug_slip", hip_back=0.15)
L.key_all(24)                      # 0.800 s  slips back toward the grip
bent(0.24, -24.0, -70.0, GRIP_CLOSED)
L.key_all(30)                      # 1.000 s  = frame 0 (seamless loop)

# ------------------------------------------------------------------ exports
out = {}
for act, length, loop in ((pick, PICKUP_LEN, False), (strug, STRUGGLE_LEN, True)):
    data = L.export_json(act, os.path.join(HERE, act.name + ".json"), SAMPLE_FPS, length, loop)
    out[act.name] = {"frames": len(data["frames"]), "loop": loop}
    try:
        L.export_fbx(act, os.path.join(HERE, act.name + ".fbx"), length)
        out[act.name]["fbx"] = True
    except Exception as e:  # noqa
        out[act.name]["fbx"] = str(e)

previews = []
for act, times in ((pick, (0.0, 0.433, 0.7, 1.0, 1.4)), (strug, (0.0, 0.333, 0.767))):
    for t in times:
        p = os.path.join(HERE, "preview_%s_%03d.png" % (act.name, int(round(t * 100))))
        try:
            L.render_frame(act, t, p)
            previews.append(os.path.basename(p))
        except Exception as e:  # noqa
            previews.append("%s: %s" % (os.path.basename(p), e))

L.use_action(pick)
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_mainfile()
print("REPORT", {"poses": report, "exports": out, "previews": previews})
