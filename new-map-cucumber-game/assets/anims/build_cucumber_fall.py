"""build_cucumber_fall.py -- authors CucumberFall on the R15Rig (CucumberAnims.blend):
the heavy-carry stumble. 2.4 s one-shot, 30 fps:

  0.000  carry pose (left hand steadying the shoulder load)
  0.233  trip: right foot catches, lean forward, right arm flies out
  0.467  FALL_DROP_T: pitched over, both arms flung forward, the cucumber leaves the shoulder
  0.733  face-plant: prone on the floor, arms out ahead, legs straight back
  0.900  settle (small bounce), head down
  1.000  dazed: head lifts
  1.267  push up to all fours (thighs vertical, shins flat behind, straight arms)
  1.467  right foot comes under
  1.667  crouch, both feet planted
  2.000  rising
  2.400  idle, arms relaxed

Outputs (assets/anims/): CucumberFall.json (15 fps samples), CucumberFall.fbx, preview_CucumberFall_*.png.
Run inside Blender:  exec(open(r"...\\build_cucumber_fall.py").read())
"""
import bpy
import importlib
import os
import sys
from mathutils import Vector

HERE = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\assets\anims"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import r15animlib as L
importlib.reload(L)

FPS = 30
SAMPLE_FPS = 15
FALL_LEN = 2.4
CARRY_LEFT = (-1.05, 0.35, -0.72)
REST = L.ANKLE_REST
report = {}
carry_local = None  # left wrist target in the UpperTorso frame (the load is welded to the torso)


def measure(tag):
    L.update()
    out = {}
    for n in ("LowerTorso", "UpperTorso", "Head", "LeftHand", "RightHand", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"):
        out[n] = [round(v, 2) for v in L.joint(n)]
    report[tag] = out


def ankles(left=None, right=None):
    return {"Left": Vector(left) if left else REST["Left"], "Right": Vector(right) if right else REST["Right"]}


def carry_target():
    """world (root-relative) point for the left wrist that keeps it on the shoulder load"""
    return L.joint("UpperTorso") + L.frame_of("UpperTorso") @ carry_local


def carry_pose():
    L.reset_pose()
    L.pose_legs(0.0, 0.0)
    L.set_rot("UpperTorso", L.rx(-3.0))
    L.pose_arms({"Left": CARRY_LEFT})
    L.set_rot("RightUpperArm", L.rz(4.0))
    L.pose_head(pitch=4.0, yaw=8.0)


r = L.rig()
r.location = (0.0, 0.0, 0.0)
L.preview_blocks()
L.props()
cuke = bpy.data.objects.get("CukeStandIn")
if cuke:
    cuke.hide_render = True
    cuke.hide_viewport = True

carry_pose()
carry_local = L.frame_of("UpperTorso").inverted() @ (Vector(CARRY_LEFT) - L.joint("UpperTorso"))

fall = L.new_action("CucumberFall", FPS)

# 0.000 carry
carry_pose()
measure("carry")
L.key_all(0)

# 0.233 trip: right foot catches, lean, right arm out
L.reset_pose()
L.pose_legs(0.18, -14.0, ankle_targets=ankles(None, (0.5, -2.93, -0.85)))
L.set_rot("UpperTorso", L.rx(-14.0))
L.pose_arms({"Left": carry_target(), "Right": (1.45, -0.15, -1.05)})
L.pose_head(pitch=-12.0)
measure("trip")
L.key_all(7)

# 0.467 falling: pitched over, both arms flung ahead (the cucumber leaves the shoulder here)
L.reset_pose()
L.pose_legs(0.5, -32.0, ankle_targets=ankles((-0.5, -2.93, 0.3), (0.5, -2.93, -0.9)))
L.set_rot("UpperTorso", L.rx(-28.0))
L.pose_arms({"Left": (-1.25, -0.9, -2.2), "Right": (1.25, -0.9, -2.2)})
L.pose_head(pitch=-20.0)
measure("fall")
L.key_all(14)


def prone(hip_drop, head_pitch, hands_z=-3.2, hands_y=-2.65):
    L.reset_pose()
    L.pose_legs(hip_drop, -85.0, ankle_targets=ankles((-0.5, -2.5, 1.85), (0.5, -2.5, 1.85)), foot_flat=False)
    for side in ("Left", "Right"):
        L.set_rot(side + "Foot", L.rx(-35.0))  # toes trailing on the floor
    L.set_rot("UpperTorso", L.rx(-5.0))
    L.pose_arms({"Left": (-1.1, hands_y, hands_z), "Right": (1.1, hands_y, hands_z)})
    L.pose_head(pitch=head_pitch)


# 0.733 face-plant
prone(1.45, 8.0)
measure("plant")
L.key_all(22)
# 0.900 settle
prone(1.42, 2.0)
L.key_all(27)
# 1.000 dazed: head lifts
prone(1.45, 38.0)
L.key_all(30)

# 1.267 all fours: thighs vertical, shins flat behind, chest horizontal, straight arms
L.reset_pose()
L.pose_legs(0.58, -45.0, ankle_targets=ankles((-0.5, -2.5, 1.0), (0.5, -2.5, 1.0)), foot_flat=False)
for side in ("Left", "Right"):
    L.set_rot(side + "Foot", L.rx(-40.0))
L.set_rot("UpperTorso", L.rx(-40.0))
L.pose_arms({"Left": (-0.97, -2.75, -1.9), "Right": (0.97, -2.75, -1.9)})
L.pose_head(pitch=30.0)
measure("fours")
L.key_all(38)

# 1.467 right foot comes under
L.reset_pose()
L.pose_legs(0.7, -30.0, ankle_targets=ankles((-0.5, -2.6, 0.8), (0.5, -2.93, -0.5)), foot_flat=False)
L.set_rot("LeftFoot", L.rx(-40.0))
L.set_rot("RightFoot", L.frame_of("RightLowerLeg").inverted().to_quaternion())
L.set_rot("UpperTorso", L.rx(-35.0))
L.pose_arms({"Left": (-0.9, -2.3, -1.4), "Right": (0.9, -2.3, -1.4)})
L.pose_head(pitch=25.0)
measure("kneel")
L.key_all(44)

# 1.667 crouch, both feet planted
L.reset_pose()
L.pose_legs(0.75, -20.0)
L.set_rot("UpperTorso", L.rx(-30.0))
L.pose_arms({"Left": (-1.0, -1.6, -0.9), "Right": (1.0, -1.6, -0.9)})
L.pose_head(pitch=10.0)
measure("crouch")
L.key_all(50)

# 2.000 rising
L.reset_pose()
L.pose_legs(0.2, -6.0)
L.set_rot("UpperTorso", L.rx(-8.0))
L.pose_arms({"Left": (-1.3, -0.75, -0.45), "Right": (1.3, -0.75, -0.45)})
L.pose_head(pitch=0.0)
measure("rise")
L.key_all(60)

# 2.400 idle
L.reset_pose()
L.set_rot("LeftUpperArm", L.rz(-4.0))
L.set_rot("RightUpperArm", L.rz(4.0))
measure("idle")
L.key_all(72)

# ------------------------------------------------------------------ exports
out = {}
data = L.export_json(fall, os.path.join(HERE, "CucumberFall.json"), SAMPLE_FPS, FALL_LEN, False)
out["frames"] = len(data["frames"])
try:
    L.export_fbx(fall, os.path.join(HERE, "CucumberFall.fbx"), FALL_LEN)
    out["fbx"] = True
except Exception as e:  # noqa
    try:
        win = bpy.context.window_manager.windows[0]
        area = next(a for a in win.screen.areas if a.type == 'VIEW_3D')
        region = next(rg for rg in area.regions if rg.type == 'WINDOW')
        with bpy.context.temp_override(window=win, area=area, region=region, selected_objects=[r], active_object=r):
            L.export_fbx(fall, os.path.join(HERE, "CucumberFall.fbx"), FALL_LEN)
        out["fbx"] = "override"
    except Exception as e2:  # noqa
        out["fbx"] = "%s / %s" % (e, e2)

previews = []
for t in (0.0, 0.233, 0.467, 0.733, 1.0, 1.267, 1.467, 1.667, 2.0, 2.4):
    p = os.path.join(HERE, "preview_CucumberFall_%03d.png" % int(round(t * 100)))
    try:
        L.render_frame(fall, t, p, cam_from=(6.0, 6.5, 1.6), look_at=(0.0, 0.0, -1.2))
        previews.append(os.path.basename(p))
    except Exception as e:  # noqa
        previews.append("%s: %s" % (os.path.basename(p), e))

L.use_action(fall)
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_mainfile()
print("REPORT", {"poses": report, "exports": out, "previews": previews})
