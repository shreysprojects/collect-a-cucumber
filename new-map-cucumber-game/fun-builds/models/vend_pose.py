"""vend_pose.py -- VendingMachine behaviour: solve + preview the "raise the snack to the mouth" arm pose.

Headless, read-only on the shared rig file (never saves it):
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b \
        ..\\..\\assets\\CucumberAnims.blend --python vend_pose.py

Uses assets/anims/r15animlib.py (the R15Rig armature: bone-local axes == Roblox joint axes, a bone's
pose quaternion IS the Roblox joint Transform rotation - the same pipeline CucumberLiftPoses uses).

How the sip works in game (behaviours/client/VendingMachine.lua):
  * the server welds the snack's invisible root in FRONT of the right fist, upright (root +Y = the
    snack's top), so it reads as "a can held at your side" while the arm hangs / swings;
  * during a sip every client blends the right arm (RightShoulder / RightElbow / RightWrist) and the
    Neck toward SIP_POSE (these quaternions) and swings the snack's weld so it runs from the fist to
    the lips: bottom against the fist (FIST_REACH from its centre), top on the mouth (computed live from
    the Head and RightHand CFrames, so it adapts to any R15 body).
This script IK-solves the arm so the fist centre sits snack length + FIST_REACH from the lips, prints the joint
quaternions (w, x, y, z) and renders renders/VendingMachine_hold_front.png + _sip_<tag>_*.png.
"""
import bpy
import bmesh
import math
import os
import sys
import json
from mathutils import Vector, Quaternion, Matrix

ANIMS = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\assets\anims"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "renders")
sys.path.insert(0, ANIMS)
import r15animlib as L  # noqa: E402

# ---- the held snack (hand-part space, Roblox axes, character scale 1) - keep in step with the server half
HAND_SIZE = Vector((1.0, 0.5, 1.0))          # the preview rig's RightHand block
CAN_H, CAN_D = 0.80, 0.44                    # SNACKS.Soda: length (root +Y), diameter
HOLD_Y = -0.05                               # snack centre below the hand centre
HOLD_GAP = 0.04                              # snack sinks this far into the fist's front face
FIST_REACH = 0.35                            # sip: the snack's bottom sits this far from the fist centre, toward the lips
MOUTH = Vector((0.0, 1.40, -0.66))           # lips, root-relative, rest head (head block centre y 1.7, front z -0.6)

# "a" is the one shipped in SIP_POSE (the fist up-right of the face, the snack angled down into the mouth: seen
# from the front and both sides). Rejected on renders (2026-09-24): the fist straight in front of the mouth (the
# blocky 1-stud fist hides the can) and the overhead chug (the arm cannot reach, the can floats off the lips).
# Try others with VEND_VARIANTS='[{"tag": "x", "dir": [..], "fwd": [..], "wrist": 0, "head": 12}]'.
VARIANTS = json.loads(os.environ.get("VEND_VARIANTS", "null") or "null") or [
    {"tag": "a", "dir": (0.60, 0.45, -0.45), "fwd": (-0.3, 0.2, 1.0), "wrist": 0.0, "head": 12.0},
]


def rest_hand_centre_rel():
    """hand block centre relative to the wrist joint (rest pose, hand frame == root frame)"""
    L.reset_pose()
    return Vector(L.PART_BLOCKS["RightHand"][0]) - L.joint("RightHand")


def hand_centre():
    return L.joint("RightHand") + L.frame_of("RightHand") @ hc


def solve(variant, iters=60):
    L.reset_pose()
    L.pose_head(pitch=variant["head"])
    mouth = L.joint("Head") + L.frame_of("Head") @ (MOUTH - rest_neck)   # the lips follow the head tilt
    grip = mouth + Vector(variant["dir"]).normalized() * (CAN_H + FIST_REACH)
    target = grip - hc
    hand_rot = {"Right": L.rx(variant["wrist"])}
    err = None
    for _ in range(iters):
        L.pose_arms({"Right": target}, fwd_world=variant["fwd"], hand_rot=hand_rot)
        e = grip - hand_centre()
        err = e.length
        if err < 0.004:
            break
        target = target + e * 0.8
    qs = {n: L.get_rot(n) for n in ("RightUpperArm", "RightLowerArm", "RightHand", "Head")}
    return qs, err, mouth, grip


def mesh_obj(name, build, color, bone=None):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    mat = bpy.data.materials.new(name + "Mat")
    mat.diffuse_color = color
    me.materials.append(mat)
    if bone:
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = L.rig()
        ob.parent = L.rig()
    return ob


def can_objs(prefix, centre, axis_up, bone=None):
    """a soda can (Roblox centre, Roblox axis = the can's top direction) as three meshes"""
    up = Vector(axis_up).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(L.r2b(up)).to_matrix().to_4x4()
    base = Matrix.Translation(L.r2b(centre)) @ rot
    objs = []

    def cyl(radius, depth, dz):
        return lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=radius,
                                                radius2=radius, depth=depth, matrix=base @ Matrix.Translation((0, 0, dz)))

    objs.append(mesh_obj(prefix + "Body", cyl(CAN_D / 2, CAN_H, 0.0), (0.30, 0.78, 0.27, 1.0), bone))
    objs.append(mesh_obj(prefix + "Band", cyl(CAN_D / 2 + 0.012, CAN_H * 0.38, 0.0), (0.95, 0.94, 0.92, 1.0), bone))
    objs.append(mesh_obj(prefix + "Lid", cyl(CAN_D * 0.43, 0.05, CAN_H / 2 + 0.02), (0.6, 0.65, 0.72, 1.0), bone))
    return objs


def render(path, cam_from, look_at, size=520):
    scene = bpy.context.scene
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        camd = bpy.data.cameras.new("PreviewCam")
        camd.lens = 40
        cam = bpy.data.objects.new("PreviewCam", camd)
        scene.collection.objects.link(cam)
    cam.location = Vector(cam_from)
    cam.rotation_euler = (Vector(look_at) - Vector(cam_from)).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.show_shadows = False
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def q4(q):
    q = q.normalized()
    return [round(q.w, 4), round(q.x, 4), round(q.y, 4), round(q.z, 4)]


if L.rig().animation_data is not None:
    L.rig().animation_data.action = None     # the file opens with a clip bound: it would override every pose we set
for name in ("CukeStandIn",):
    ob = bpy.data.objects.get(name)
    if ob:
        ob.hide_render = True
L.reset_pose()
rest_neck = L.joint("Head")
L.preview_blocks()
hc = rest_hand_centre_rel()
for part, col in (("Blk_RightHand", (0.95, 0.45, 0.15, 1.0)), ("Blk_RightLowerArm", (0.85, 0.7, 0.2, 1.0)),
                  ("Blk_RightUpperArm", (0.75, 0.6, 0.15, 1.0))):
    ob = bpy.data.objects.get(part)
    if ob:
        ob.data.materials[0].diffuse_color = col
print("REST shoulder", list(L.joint("RightUpperArm")), "elbow", list(L.joint("RightLowerArm")),
      "wrist", list(L.joint("RightHand")), "neck", list(rest_neck), "hand centre rel wrist", list(hc))

os.makedirs(OUT, exist_ok=True)
FRONT = ((3.6, 8.5, 2.6), (0.4, 0.0, 0.6))
SIDE = ((9.0, 1.4, 2.2), (0.4, 0.0, 0.6))
DEAD = ((0.3, 9.5, 1.8), (0.3, 0.0, 0.8))
LEFT = ((-5.5, 7.5, 2.4), (0.3, 0.0, 0.8))
# idle hold: the can skinned to the hand, upright in front of the fist
L.reset_pose()
hold_centre = L.joint("RightHand") + hc + Vector((0.0, HOLD_Y, -(HAND_SIZE.z * 0.5 + CAN_D * 0.5 - HOLD_GAP)))
held = can_objs("Held", hold_centre, (0, 1, 0), bone="RightHand")
render(os.path.join(OUT, "VendingMachine_hold_front.png"), *FRONT)
for ob in held:
    ob.hide_render = True
results = {}
for v in VARIANTS:
    qs, err, mouth, grip = solve(v)
    fist = hand_centre()
    d = (mouth - fist).normalized()
    centre = fist + d * (FIST_REACH + CAN_H * 0.5)
    sip = can_objs("Sip_" + v["tag"], centre, d)
    results[v["tag"]] = {"err": round(err, 4), "mouth": [round(c, 3) for c in mouth], "grip": [round(c, 3) for c in grip],
                         "variant": v, "q": {n: q4(q) for n, q in qs.items()}}
    render(os.path.join(OUT, "VendingMachine_sip_%s_front.png" % v["tag"]), *FRONT)
    render(os.path.join(OUT, "VendingMachine_sip_%s_side.png" % v["tag"]), *SIDE)
    render(os.path.join(OUT, "VendingMachine_sip_%s_dead.png" % v["tag"]), *DEAD)
    render(os.path.join(OUT, "VendingMachine_sip_%s_left.png" % v["tag"]), *LEFT)
    for ob in sip:
        ob.hide_render = True
print("SIP " + json.dumps(results))
