"""build_cucumber_lift.py -- authors the click-to-lift clip on the R15Rig (CucumberAnims.blend).

  CucumberLift 1.4 s, one-shot, PROGRESS-DRIVEN: the client scrubs the first LIFT_LEN
  second by the lift bar (0 = hands on the cucumber on the ground, 1 = load held at the
  chest, standing), then plays the last HOIST_LEN second once as the load goes onto the
  left shoulder (the server welds it there at the end).

    t 0.00  deep squat, both hands closed on the cucumber (the old struggle grip)
    t 0.33  standing up, arms straight down, the load at the knees
    t 0.60  nearly upright, the load hanging at the thighs (the reference screenshot)
    t 1.00  upright, elbows bent, the load hugged at the chest
    t 1.40  carry pose: left hand steadying the load on the shoulder, right arm relaxed

Outputs (assets/anims/): CucumberLift.json (15 fps pose samples, Roblox joint frames),
CucumberLift.fbx, preview_CucumberLift_*.png.

Run headless:  blender -b CucumberAnims.blend --python build_cucumber_lift.py
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
LIFT_LEN = 1.0
HOIST_LEN = 0.4
TOTAL = LIFT_LEN + HOIST_LEN
CUKE = L.CUKE_POS
GRIP = {"Left": (-0.42, -2.12, -1.78), "Right": (0.42, -2.12, -1.78)}
KNEE = {"Left": (-0.5, -1.45, -1.2), "Right": (0.5, -1.45, -1.2)}
THIGH = {"Left": (-0.52, -0.7, -1.05), "Right": (0.52, -0.7, -1.05)}  # 2026-09-18: a touch higher, the rise reads on every click
CHEST = {"Left": (-0.45, 0.3, -0.95), "Right": (0.45, 0.3, -0.95)}  # 2026-09-18: the real chest (was -0.2 = belly), hands visibly UP at the full bar (user)
CARRY_LEFT = (-1.05, 0.35, -0.72)

report = {}


def bent(hip_drop, root_pitch, waist_pitch, grip, head_target=None, tag=None, hip_back=0.0, head_pitch=None):
    L.reset_pose()
    legs = L.pose_legs(hip_drop, root_pitch, hip_back=hip_back)
    L.set_rot("UpperTorso", L.rx(waist_pitch))
    arms = L.pose_arms(grip)
    if head_pitch is not None:
        pitch = L.pose_head(pitch=head_pitch)
    else:
        pitch = L.pose_head(target=head_target or CUKE)
    if tag:
        report[tag] = {"legs": legs, "arms": arms, "head_pitch": round(pitch or 0.0, 1),
                       "wristL": [round(v, 2) for v in L.joint("LeftHand")],
                       "wristR": [round(v, 2) for v in L.joint("RightHand")],
                       "shoulderL": [round(v, 2) for v in L.joint("LeftUpperArm")]}
    return arms


r = L.rig()
r.location = (0.0, 0.0, 0.0)
L.preview_blocks()
L.props()

lift = L.new_action("CucumberLift", FPS)
# 0.00 s: deep grip on the ground (hips back so the short arms reach)
bent(0.45, -14.0, -54.0, GRIP, tag="lift_grip", hip_back=0.38)
L.key_all(0)
# 0.33 s: rising, the load at the knees, arms straight down
bent(0.30, -12.0, -34.0, KNEE, head_target=(0.0, -1.45, -1.5), tag="lift_knee", hip_back=0.18)
L.key_all(10)
# 0.60 s: nearly upright, the load hanging at the thighs
bent(0.14, -7.0, -18.0, THIGH, head_target=(0.0, -0.95, -1.4), tag="lift_thigh", hip_back=0.06)
L.key_all(18)
# 1.00 s: upright, elbows bent, the load hugged at the chest, eyes ahead
bent(0.03, -2.0, -5.0, CHEST, tag="lift_chest", head_pitch=-4.0)
L.key_all(30)
# 1.40 s: the carry pose (left hand steadying the shoulder load)
L.reset_pose()
L.pose_legs(0.0, 0.0)
L.set_rot("UpperTorso", L.rx(-3.0))
L.pose_arms({"Left": CARRY_LEFT})
L.set_rot("RightUpperArm", L.rz(4.0))
L.pose_head(pitch=4.0, yaw=8.0)
report["lift_carry"] = {"wristL": [round(v, 2) for v in L.joint("LeftHand")]}
L.key_all(42)

out = {}
data = L.export_json(lift, os.path.join(HERE, "CucumberLift.json"), SAMPLE_FPS, TOTAL, False)
out["frames"] = len(data["frames"])
try:
    L.export_fbx(lift, os.path.join(HERE, "CucumberLift.fbx"), TOTAL)
    out["fbx"] = True
except Exception as e:  # noqa
    out["fbx"] = str(e)

previews = []
for t in (0.0, 0.333, 0.6, 1.0, 1.4):
    p = os.path.join(HERE, "preview_CucumberLift_%03d.png" % int(round(t * 100)))
    try:
        L.render_frame(lift, t, p, cam_from=(7.6, 8.4, 1.6), look_at=(0.0, -0.6, -1.0))
        previews.append(os.path.basename(p))
    except Exception as e:  # noqa
        previews.append("%s: %s" % (os.path.basename(p), e))

L.use_action(lift)
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_mainfile()
print("REPORT", {"poses": report, "exports": out, "previews": previews})
