"""r15animlib.py -- pose / two-bone IK / export helpers for the R15Rig armature
(CucumberAnims.blend, appended from BenchPress.blend).

Rig contract:
  * bones are named after the R15 parts, bone HEAD = the joint (the Roblox rig
    attachment), every bone points +Z with roll 0  ->  bone-local axes == Roblox
    joint axes (X right, Y up, Z back).
  * so a bone's pose rotation_quaternion IS the Roblox Pose.CFrame rotation and
    its bone-local location IS the Pose.CFrame translation (studs, Roblox x/y/z).
  * Roblox (x, y, z) <-> Blender (x, -z, y); the character faces Roblox -Z.

Run from Blender (the MCP bridge or the scripting workspace):
    import sys; sys.path.insert(0, r"...\\assets\\anims"); import r15animlib as L
"""
import bpy
import bmesh
import json
import math
from mathutils import Vector, Quaternion, Matrix

RIG_NAME = "R15Rig"
BONES = [
    "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
]
UPPER_ARM = 0.8465 - 0.0727   # shoulder -> elbow
LOWER_ARM = 0.0727 + 0.7343   # elbow -> wrist
THIGH = 1.9207 - 1.0          # hip -> knee
SHIN = 2.9304 - 1.9207        # knee -> ankle
FLOOR_Y = -3.0                # ground under the HumanoidRootPart (HipHeight 2 + half the root)
ANKLE_REST = {"Left": Vector((-0.5, -2.9304, 0.0)), "Right": Vector((0.5, -2.9304, 0.0))}
CUKE_POS = (0.0, -2.6, -1.8)  # stand-in cucumber centre (rbx, root-relative)
IDENT = Quaternion((1.0, 0.0, 0.0, 0.0))


def rig():
    return bpy.data.objects[RIG_NAME]


def b2r(v):
    return Vector((v.x, v.z, -v.y))


def r2b(v):
    return Vector((v[0], -v[2], v[1]))


def update():
    bpy.context.view_layer.update()


def rx(deg):
    return Quaternion((1.0, 0.0, 0.0), math.radians(deg))


def ry(deg):
    return Quaternion((0.0, 1.0, 0.0), math.radians(deg))


def rz(deg):
    return Quaternion((0.0, 0.0, 1.0), math.radians(deg))


def reset_pose():
    r = rig()
    for pb in r.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = IDENT.copy()
        pb.location = Vector((0.0, 0.0, 0.0))
        pb.scale = Vector((1.0, 1.0, 1.0))
    update()


def set_rot(name, q):
    rig().pose.bones[name].rotation_quaternion = Quaternion(q)


def get_rot(name):
    return rig().pose.bones[name].rotation_quaternion.copy()


def set_loc(name, p):
    rig().pose.bones[name].location = Vector((p[0], p[1], p[2]))


def joint(name):
    """posed joint position (bone head), Roblox coords relative to the root"""
    update()
    return b2r(rig().pose.bones[name].head)


def frame_of(name):
    """3x3 whose columns are the posed bone's local X / Y / Z axes in Roblox coords"""
    update()
    m = rig().pose.bones[name].matrix.to_3x3()
    X, Y, Z = b2r(m.col[0]), b2r(m.col[1]), b2r(m.col[2])
    return Matrix((X, Y, Z)).transposed()


def frame_quat(neg_y_dir, x_hint):
    """rotation whose local -Y points along neg_y_dir and whose local X ~ x_hint"""
    u = Vector(neg_y_dir).normalized()
    Y = -u
    X = Vector(x_hint) - Vector(x_hint).dot(Y) * Y
    if X.length < 1e-6:
        X = Vector((1.0, 0.0, 0.0)) - Y.x * Y
    X.normalize()
    Z = X.cross(Y)
    return Matrix((X, Y, Z)).transposed().to_quaternion()


def solve_limb(d_local, L1, L2, fwd_local, bend=1.0):
    """Two-bone IK in the parent bone's frame.
    d_local = target - joint (parent-local, Roblox-like axes); the limb rests along -Y,
    the hinge is the upper bone's local X. bend=+1: middle joint bows AWAY from fwd
    (elbows), bend=-1: TOWARD fwd (knees). Returns (q_upper, q_lower, overreach)."""
    d = Vector(d_local)
    D = d.length
    if D < 1e-6:
        return IDENT.copy(), IDENT.copy(), 0.0
    Dc = min(max(D, abs(L1 - L2) + 1e-3), L1 + L2 - 1e-3)
    t = d / D
    n = t.cross(Vector(fwd_local))
    if n.length < 1e-4:
        n = Vector((1.0, 0.0, 0.0))
    n.normalize()
    a = math.acos(max(-1.0, min(1.0, (L1 * L1 + Dc * Dc - L2 * L2) / (2.0 * L1 * Dc))))
    b = math.acos(max(-1.0, min(1.0, (L2 * L2 + Dc * Dc - L1 * L1) / (2.0 * L2 * Dc))))
    u = Quaternion(n, -bend * a) @ t
    q_upper = frame_quat(u, n)
    q_lower = Quaternion((1.0, 0.0, 0.0), bend * (a + b))
    return q_upper, q_lower, max(0.0, D - (L1 + L2))


ARM_SIDE_OFFSET = 0.5  # the R15 elbow hangs 0.5 studs OUTSIDE the shoulder attachment


def solve_arm(side, d_local, fwd_local):
    """Arm IK honouring the R15 rest geometry: upper arm = (+-0.5, -UPPER_ARM, 0) slanting
    outward, forearm = (0, -LOWER_ARM, 0). The elbow folds forward (about the upper arm's
    local X, kept close to the hinge n = t x fwd so nothing twists). d_local = wrist target
    - shoulder in the UpperTorso frame. Returns (q_upper, q_lower, overreach)."""
    sx = -ARM_SIDE_OFFSET if side == "Left" else ARM_SIDE_OFFSET
    v1 = Vector((sx, -UPPER_ARM, 0.0))
    v2 = Vector((0.0, -LOWER_ARM, 0.0))
    d = Vector(d_local)
    D = d.length
    if D < 1e-6:
        return IDENT.copy(), IDENT.copy(), 0.0
    reach = math.sqrt(sx * sx + (UPPER_ARM + LOWER_ARM) ** 2)
    c = (D * D - v1.length_squared - v2.length_squared) / (2.0 * UPPER_ARM * LOWER_ARM)
    theta = math.acos(max(-1.0, min(1.0, c)))
    p = v1 + Quaternion((1.0, 0.0, 0.0), theta) @ v2
    t = d / D
    n = t.cross(Vector(fwd_local))
    if n.length < 1e-4:
        n = Vector((1.0, 0.0, 0.0))
    n.normalize()

    def frame(f, x):
        a1 = f.normalized()
        a2 = x - x.dot(a1) * a1
        if a2.length < 1e-6:
            a2 = Vector((0.0, 0.0, 1.0)) - a1.z * a1
        a2.normalize()
        return Matrix((a1, a2, a1.cross(a2))).transposed()

    R = frame(t, n) @ frame(p, Vector((1.0, 0.0, 0.0))).transposed()
    return R.to_quaternion(), Quaternion((1.0, 0.0, 0.0), theta), max(0.0, D - reach)


def pose_legs(hip_drop=0.0, root_pitch=0.0, ankle_targets=None, foot_flat=True, hip_back=0.0):
    """LowerTorso drops hip_drop studs (and slides hip_back studs toward +Z) and pitches
    root_pitch deg (negative = lean forward); both legs fold so the ankles stay planted;
    feet stay flat on the ground."""
    set_loc("LowerTorso", (0.0, -hip_drop, hip_back))
    set_rot("LowerTorso", rx(root_pitch))
    out = {}
    for side in ("Left", "Right"):
        hip = joint(side + "UpperLeg")
        Mi = frame_of("LowerTorso").inverted()
        target = Vector((ankle_targets or ANKLE_REST)[side])
        qu, ql, err = solve_limb(Mi @ (target - hip), THIGH, SHIN, Mi @ Vector((0.0, 0.0, -1.0)), bend=-1.0)
        set_rot(side + "UpperLeg", qu)
        set_rot(side + "LowerLeg", ql)
        if foot_flat:
            set_rot(side + "Foot", frame_of(side + "LowerLeg").inverted().to_quaternion())
        out[side] = round(err, 3)
    return out


def pose_arms(targets, fwd_world=(0.0, 0.0, -1.0), hand_rot=None):
    """targets = {"Left": wrist point, "Right": wrist point} (rbx root-relative).
    Elbows bow away from fwd_world. Returns {side: (overreach, wrist error)}."""
    out = {}
    for side, target in targets.items():
        sh = joint(side + "UpperArm")
        Mi = frame_of("UpperTorso").inverted()
        qu, ql, err = solve_arm(side, Mi @ (Vector(target) - sh), Mi @ Vector(fwd_world))
        set_rot(side + "UpperArm", qu)
        set_rot(side + "LowerArm", ql)
        set_rot(side + "Hand", (hand_rot or {}).get(side, IDENT))
        out[side] = (round(err, 3), round((joint(side + "Hand") - Vector(target)).length, 3))
    return out


def probe(hip_drop, root_pitch, waist_pitch, grip, hip_back=0.0):
    """pose + measure (for tuning): arm reach errors, shoulder / wrist / knee spots"""
    reset_pose()
    pose_legs(hip_drop, root_pitch, hip_back=hip_back)
    set_rot("UpperTorso", rx(waist_pitch))
    arms = pose_arms(grip)
    return {"arms": arms,
            "shoulderL": [round(v, 2) for v in joint("LeftUpperArm")],
            "wristL": [round(v, 2) for v in joint("LeftHand")],
            "kneeL": [round(v, 2) for v in joint("LeftLowerLeg")],
            "head": [round(v, 2) for v in joint("Head")]}


def pose_head(target=None, pitch=None, yaw=0.0, min_pitch=-55.0, max_pitch=40.0):
    if pitch is None and target is not None:
        neck = joint("Head")
        d = frame_of("UpperTorso").inverted() @ (Vector(target) - neck)
        pitch = math.degrees(math.atan2(d.y, -d.z)) if (abs(d.z) > 1e-6 or abs(d.y) > 1e-6) else 0.0
        pitch = max(min_pitch, min(max_pitch, pitch))
    set_rot("Head", ry(yaw) @ rx(pitch or 0.0))
    return pitch


# ---------------------------------------------------------------- actions / keys
def new_action(name, fps=30):
    r = rig()
    if r.animation_data is None:
        r.animation_data_create()
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    r.animation_data.action = act
    try:  # slotted actions (Blender 4.4+)
        slot = act.slots[0] if len(act.slots) else act.slots.new(id_type='OBJECT', name=r.name)
        r.animation_data.action_slot = slot
    except Exception:
        pass
    bpy.context.scene.render.fps = fps
    return act


def key_all(frame):
    r = rig()
    for name in BONES:
        pb = r.pose.bones[name]
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def use_action(action):
    r = rig()
    r.animation_data.action = action
    try:
        if r.animation_data.action_slot is None and len(action.slots):
            r.animation_data.action_slot = action.slots[0]
    except Exception:
        pass


def goto(t_seconds):
    scene = bpy.context.scene
    f = t_seconds * scene.render.fps
    scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
    update()


def sample(action, fps_out, length):
    use_action(action)
    frames = []
    n = int(round(length * fps_out))
    r = rig()
    for i in range(n + 1):
        t = i / fps_out
        goto(t)
        poses = {}
        for name in BONES:
            pb = r.pose.bones[name]
            q = pb.rotation_quaternion.normalized()
            entry = {"q": [round(q.w, 5), round(q.x, 5), round(q.y, 5), round(q.z, 5)]}
            p = pb.location
            if p.length > 1e-4:
                entry["p"] = [round(p.x, 4), round(p.y, 4), round(p.z, 4)]
            poses[name] = entry
        frames.append({"t": round(t, 4), "poses": poses})
    return frames


def export_json(action, path, fps_out, length, loop, priority="Action"):
    data = {"name": action.name, "fps": fps_out, "length": length, "loop": loop,
            "priority": priority, "frames": sample(action, fps_out, length)}
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    return data


def export_fbx(action, path, length):
    use_action(action)
    scene = bpy.context.scene
    scene.frame_start = 0
    scene.frame_end = int(round(length * scene.render.fps))
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=False, object_types={'ARMATURE', 'MESH'},
        bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
        bake_anim_use_all_bones=True, bake_anim_force_startend_keying=True,
        add_leaf_bones=False, armature_nodetype='NULL', axis_forward='-Z', axis_up='Y',
        apply_unit_scale=True)


# ---------------------------------------------------------------- preview props / render
PART_BLOCKS = {  # approximate R15 block rig: rbx centre, size (root-relative, rest pose)
    "Head": ((0.0, 1.7, 0.0), (1.2, 1.2, 1.2)),
    "UpperTorso": ((0.0, 0.2, 0.0), (2.0, 1.6, 1.0)),
    "LowerTorso": ((0.0, -0.8, 0.0), (2.0, 0.4, 1.0)),
    "LeftUpperArm": ((-1.47, 0.45, 0.0), (1.0, 0.8, 1.0)),
    "LeftLowerArm": ((-1.47, -0.33, 0.0), (1.0, 0.78, 1.0)),
    "LeftHand": ((-1.47, -0.98, 0.0), (1.0, 0.5, 1.0)),
    "RightUpperArm": ((1.47, 0.45, 0.0), (1.0, 0.8, 1.0)),
    "RightLowerArm": ((1.47, -0.33, 0.0), (1.0, 0.78, 1.0)),
    "RightHand": ((1.47, -0.98, 0.0), (1.0, 0.5, 1.0)),
    "LeftUpperLeg": ((-0.5, -1.46, 0.0), (1.0, 0.9, 1.0)),
    "LeftLowerLeg": ((-0.5, -2.42, 0.0), (1.0, 1.0, 1.0)),
    "LeftFoot": ((-0.5, -2.85, 0.0), (1.0, 0.3, 1.0)),
    "RightUpperLeg": ((0.5, -1.46, 0.0), (1.0, 0.9, 1.0)),
    "RightLowerLeg": ((0.5, -2.42, 0.0), (1.0, 1.0, 1.0)),
    "RightFoot": ((0.5, -2.85, 0.0), (1.0, 0.3, 1.0)),
}
BLOCK_COLORS = {"Head": (0.95, 0.8, 0.25, 1.0), "UpperTorso": (0.2, 0.45, 0.85, 1.0), "LowerTorso": (0.2, 0.7, 0.3, 1.0)}


def preview_blocks():
    """replace the appended R15_* meshes with clean blocks skinned 1:1 to their bones"""
    r = rig()
    for ob in list(bpy.data.objects):
        if ob.type == 'MESH' and (ob.name.startswith("R15_") or ob.name.startswith("Blk_")):
            bpy.data.objects.remove(ob, do_unlink=True)

    def block(name, bone, centre, size, color):
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        m = Matrix.Translation(r2b(centre)) @ Matrix.Diagonal((size[0], size[2], size[1], 1.0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=m)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        mat = bpy.data.materials.new(name + "Mat")
        mat.diffuse_color = color
        me.materials.append(mat)
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = r
        ob.parent = r
        return ob

    for bone, (centre, size) in PART_BLOCKS.items():
        col = BLOCK_COLORS.get(bone, (0.95, 0.8, 0.25, 1.0) if "Arm" in bone or "Hand" in bone else (0.2, 0.7, 0.3, 1.0))
        block("Blk_" + bone, bone, centre, size, col)
    block("Blk_Nose", "Head", (0.0, 1.55, -0.72), (0.35, 0.25, 0.3), (0.9, 0.3, 0.25, 1.0))


def props():
    for name in ("Ground", "CukeStandIn"):
        ob = bpy.data.objects.get(name)
        if ob:
            bpy.data.objects.remove(ob, do_unlink=True)

    def mk(name, build, color):
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
        return ob

    mk("Ground", lambda bm: bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=5.0,
                                                  matrix=Matrix.Translation((0.0, 0.0, FLOOR_Y))), (0.35, 0.5, 0.25, 1.0))
    cm = Matrix.Translation(r2b(CUKE_POS)) @ Matrix.Rotation(math.radians(90.0), 4, 'Y')
    mk("CukeStandIn", lambda bm: bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12,
                                                       radius1=0.4, radius2=0.4, depth=2.35, matrix=cm), (0.2, 0.6, 0.2, 1.0))


def render_frame(action, t_seconds, path, size=480, cam_from=(5.2, 6.0, 0.9), look_at=(0.0, 0.8, -1.3)):
    scene = bpy.context.scene
    use_action(action)
    goto(t_seconds)
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        camd = bpy.data.cameras.new("PreviewCam")
        camd.lens = 38
        cam = bpy.data.objects.new("PreviewCam", camd)
        scene.collection.objects.link(cam)
    cam.location = Vector(cam_from)
    cam.rotation_euler = (Vector(look_at) - Vector(cam_from)).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.show_shadows = True
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
