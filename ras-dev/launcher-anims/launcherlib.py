"""launcherlib.py -- rig, launcher attachment, IK, clip keying, export and preview renders
for the RAS - Dev snowball launcher animations (30 launchers, one clip set each).

Coordinate contract (read this first)
-------------------------------------
* Everything an author passes in is ROBLOX space relative to the HumanoidRootPart (HRP):
      X = character's right, Y = up, Z = character's back (the character faces -Z).
* On the launch pad the character stands side-on (MountainConfig.LAUNCHER.PadStance Yaw -90):
      DOWN-TRACK (where the ball must fly) = (-1, 0, 0)  = the character's LEFT
      the pad CAMERA sits behind the track, about (13, 5.75, 0), looking toward (-3, 2, 0)
      the FLOOR is y = -3.0 (FLOOR_Y)
* Blender world = Roblox (x, -z, y).  Bones are named after the R15 parts; bone HEAD = the
  joint, bone-local axes == Roblox joint axes, so a pose bone's rotation_quaternion IS the
  Roblox joint Transform rotation and its location IS the Transform translation (studs).
* Extra bone "Launcher" (child of RightHand) = the launcher's GRIP PIVOT frame: the frame
  SERV_Launcher welds to the hand (hand * (0,-0.15,-0.35) * Angles(-80, 0, 90)).  Its pose is the
  LauncherGrip Motor6D Transform (the launcher turning in the hand).  Use it sparingly.
* Launcher-local points (Muzzle, Seat, Grip2, Tip ...) live in meta/<NN>.json in the PIVOT frame
  at TEMPLATE scale (1x); in the scene the launcher is scaled by LAUNCHER_SCALE (1.5), exactly
  as in game.

Clips per launcher (all 30 fps; loops must end where they start):
    Ready     loop  -- standing on the pad, launcher carried, before the player presses
    ChargeLo  loop  -- holding the button at 0 % charge  (same length as ChargeHi)
    ChargeHi  loop  -- holding at 100 % charge (the runtime blends Lo/Hi by the live charge)
    Fire      once  -- release -> the ball leaves at FIRE_AT -> follow-through -> relaxed
Run a build script headless:
    blender.exe -b LauncherAnims.blend --python launchers/NN/build.py
"""
import bpy
import bmesh
import json
import math
import os
from mathutils import Vector, Quaternion, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
MESH_DIR = os.path.join(HERE, "meshes")
META_DIR = os.path.join(HERE, "meta")
OUT_DIR = os.path.join(HERE, "out")

RIG_NAME = "R15Rig"
FPS = 30
BONES = [
    "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head",
    "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
    "Launcher",
]
EXPORT_BONES = [b for b in BONES if b != "HumanoidRootPart"]
# joint (bone head) rest positions, Roblox HRP-local
REST = {
    "HumanoidRootPart": (0.0, 0.0, 0.0),
    "LowerTorso": (0.0, -1.0, 0.0),
    "UpperTorso": (0.0, -0.6, 0.0),
    "Head": (0.0, 1.098, 0.0),
    "LeftUpperArm": (-0.9716, 0.8465, 0.0),
    "LeftLowerArm": (-1.4717, 0.0727, 0.0),
    "LeftHand": (-1.4717, -0.7343, 0.0),
    "RightUpperArm": (0.9716, 0.8465, 0.0),
    "RightLowerArm": (1.4721, 0.0726, 0.0),
    "RightHand": (1.4721, -0.7343, 0.0),
    "LeftUpperLeg": (-0.5, -1.0, 0.0),
    "LeftLowerLeg": (-0.5, -1.9207, 0.0),
    "LeftFoot": (-0.5, -2.9304, 0.0),
    "RightUpperLeg": (0.5, -1.0, 0.0),
    "RightLowerLeg": (0.5, -1.9206, 0.0),
    "RightFoot": (0.5, -2.9304, 0.0),
}
PARENT = {
    "LowerTorso": "HumanoidRootPart", "UpperTorso": "LowerTorso", "Head": "UpperTorso",
    "LeftUpperArm": "UpperTorso", "LeftLowerArm": "LeftUpperArm", "LeftHand": "LeftLowerArm",
    "RightUpperArm": "UpperTorso", "RightLowerArm": "RightUpperArm", "RightHand": "RightLowerArm",
    "LeftUpperLeg": "LowerTorso", "LeftLowerLeg": "LeftUpperLeg", "LeftFoot": "LeftLowerLeg",
    "RightUpperLeg": "LowerTorso", "RightLowerLeg": "RightUpperLeg", "RightFoot": "RightLowerLeg",
    "Launcher": "RightHand",
}
UPPER_ARM = 0.8465 - 0.0727
LOWER_ARM = 0.0727 + 0.7343
ARM_SIDE_OFFSET = 0.5
THIGH = 1.9207 - 1.0
SHIN = 2.9304 - 1.9207
FLOOR_Y = -3.0
ANKLE_REST = {"Left": (-0.5, -2.9304, 0.0), "Right": (0.5, -2.9304, 0.0)}
HAND_CENTER = (0.0, -0.25, 0.0)      # hand part centre relative to the wrist joint (hand frame)
LAUNCHER_SCALE = 1.5                 # MountainConfig.LAUNCHER.Scale
BALL_RADIUS = 0.667                  # ride ball at launch (2-stud template x BallScale 1/1.5)
DOWN_TRACK = Vector((-1.0, 0.0, 0.0))
CAMERA_GAME = ((13.0, 5.75, 0.0), (-3.0, 2.0, 0.0))   # pad camera: eye, look-at (Roblox HRP-local)
CAMERA_FRONT = ((-3.5, 1.2, -13.0), (-1.2, -0.4, -1.0))  # in front of the character (screen-right side)
CAMERA_TRACK = ((-14.0, 1.5, -2.0), (0.0, -0.3, -0.8))  # from down the track, looking back at the shooter
CAMERA_TOP = ((-1.0, 12.0, 0.01), (-1.0, 0.0, 0.0))
IDENT = Quaternion((1.0, 0.0, 0.0, 0.0))

# ---------------------------------------------------------------- basic maths
C3 = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))  # Roblox vector -> Blender vector


def r2b(v):
    return Vector((v[0], -v[2], v[1]))


def b2r(v):
    return Vector((v[0], v[2], -v[1]))


def rx(deg):
    return Quaternion((1.0, 0.0, 0.0), math.radians(deg))


def ry(deg):
    return Quaternion((0.0, 1.0, 0.0), math.radians(deg))


def rz(deg):
    return Quaternion((0.0, 0.0, 1.0), math.radians(deg))


def angles(xd, yd, zd):
    """Roblox CFrame.Angles(rad(x), rad(y), rad(z)) as a quaternion (= Rx * Ry * Rz)"""
    return rx(xd) @ ry(yd) @ rz(zd)


def cf(pos=(0.0, 0.0, 0.0), rot=None):
    """4x4 Roblox-space CFrame from a position and a Quaternion / 3x3"""
    m = Matrix.Identity(4)
    if rot is not None:
        r3 = rot.to_matrix() if isinstance(rot, Quaternion) else Matrix(rot)
        m = r3.to_4x4()
    m.translation = Vector(pos)
    return m


def cf_components(c):
    """Roblox CFrame:GetComponents() list -> 4x4"""
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c
    m = Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0.0, 0.0, 0.0, 1.0)))
    return m


def rbx_to_blender_matrix(m):
    """Roblox-space 4x4 -> Blender-space 4x4"""
    c4 = C3.to_4x4()
    return c4 @ m @ c4.transposed()


def blender_to_rbx_matrix(m):
    c4 = C3.to_4x4()
    return c4.transposed() @ m @ c4


def look_frame(forward, up_hint=(0.0, 1.0, 0.0)):
    """3x3 (Roblox) whose -Z (LookVector) = forward and Y ~ up_hint, like CFrame.lookAt"""
    f = Vector(forward).normalized()
    u = Vector(up_hint)
    x = f.cross(u)
    if x.length < 1e-5:
        x = f.cross(Vector((0.0, 0.0, 1.0)))
    x.normalize()
    y = x.cross(f).normalized()
    return Matrix((x, y, -f)).transposed()


def angle_between(a, b):
    a, b = Vector(a), Vector(b)
    if a.length < 1e-9 or b.length < 1e-9:
        return 0.0
    return math.degrees(a.angle(b))


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3.0 - 2.0 * x)


# ---------------------------------------------------------------- scene objects
def rig():
    return bpy.data.objects[RIG_NAME]


def update():
    bpy.context.view_layer.update()


def G_GRIP():
    """SERV_Launcher.alignToHand fallback: hand part -> launcher pivot"""
    return cf((0.0, -0.15, -0.35), angles(-80.0, 0.0, 90.0))


def launcher_info(lid):
    with open(os.path.join(MESH_DIR, "launchers.json")) as f:
        data = json.load(f)
    name = launcher_name(lid)
    return name, data[name]


def launcher_name(lid):
    for fn in os.listdir(MESH_DIR):
        if fn.endswith(".obj") and fn.startswith("%02d_" % int(lid)):
            return fn[:-4]
    raise KeyError(lid)


def pivot_offset(lid):
    """PivotOffset (part space) at the in-game LAUNCHER_SCALE"""
    _, info = launcher_info(lid)
    po = cf_components(info["pivot"])
    po.translation = po.translation * LAUNCHER_SCALE
    return po


def load_meta(lid):
    path = os.path.join(META_DIR, "%02d.json" % int(lid))
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


# ---------------------------------------------------------------- building the .blend
def build_rig():
    """Creates the R15 armature (+ Launcher bone) from REST if it does not exist."""
    if RIG_NAME in bpy.data.objects:
        return rig()
    arm = bpy.data.armatures.new(RIG_NAME)
    ob = bpy.data.objects.new(RIG_NAME, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    with bpy.context.temp_override(**_ctx(ob)):
        bpy.ops.object.mode_set(mode='EDIT')
        if ob.mode != 'EDIT':
            raise RuntimeError("could not enter edit mode on the rig")
        for name in BONES:
            if name == "Launcher":
                continue
            eb = arm.edit_bones.new(name)
            head = r2b(REST[name])
            eb.head = head
            eb.tail = head + Vector((0.0, 0.0, 0.35))
            eb.roll = 0.0
        for name, parent in PARENT.items():
            if name == "Launcher":
                continue
            arm.edit_bones[name].parent = arm.edit_bones[parent]
            arm.edit_bones[name].use_connect = False
        # Launcher bone = the grip pivot frame at rest
        P = pivot_rest()
        eb = arm.edit_bones.new("Launcher")
        head = r2b(P.translation)
        R = P.to_3x3()
        eb.head = head
        eb.tail = head + C3 @ (R @ Vector((0.0, 0.35, 0.0)))
        eb.align_roll(C3 @ (R @ Vector((0.0, 0.0, 1.0))))
        eb.parent = arm.edit_bones["RightHand"]
        eb.use_connect = False
        bpy.ops.object.mode_set(mode='OBJECT')
    for pb in ob.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return ob


def pivot_rest():
    W = cf(REST["RightHand"])
    return W @ cf(HAND_CENTER) @ G_GRIP()


def _ctx(ob):
    win = bpy.context.window_manager.windows[0] if bpy.context.window_manager.windows else None
    ctx = {"active_object": ob, "object": ob, "selected_objects": [ob], "selected_editable_objects": [ob]}
    if win:
        ctx["window"] = win
        for area in win.screen.areas:
            if area.type == 'VIEW_3D':
                ctx["area"] = area
                for region in area.regions:
                    if region.type == 'WINDOW':
                        ctx["region"] = region
                break
    return ctx


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
# slightly slimmer than the part boxes so the preview reads like a real avatar
BLOCK_SHRINK = {"LeftUpperArm": 0.8, "LeftLowerArm": 0.75, "LeftHand": 0.7, "RightUpperArm": 0.8,
                "RightLowerArm": 0.75, "RightHand": 0.7}
BLOCK_COLORS = {"Head": (0.96, 0.8, 0.45, 1.0), "UpperTorso": (0.2, 0.42, 0.85, 1.0), "LowerTorso": (0.18, 0.3, 0.6, 1.0)}


def _material(name, color, image_path=None):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    if image_path:
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
        if tex is None:
            tex = nt.nodes.new("ShaderNodeTexImage")
        img = bpy.data.images.get(os.path.basename(image_path))
        if img is None:
            img = bpy.data.images.load(image_path)
        tex.image = img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def build_blocks():
    r = rig()
    for ob in list(bpy.data.objects):
        if ob.type == 'MESH' and ob.name.startswith("Blk_"):
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
        me.materials.append(_material(name + "Mat", color))
        vg = ob.vertex_groups.new(name=bone)
        vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = r
        ob.parent = r
        return ob

    for bone, (centre, size) in PART_BLOCKS.items():
        k = BLOCK_SHRINK.get(bone, 1.0)
        sz = (size[0] * k, size[1], size[2] * k)
        col = BLOCK_COLORS.get(bone)
        if col is None:
            col = (0.96, 0.8, 0.45, 1.0) if ("Arm" in bone or "Hand" in bone) else (0.25, 0.25, 0.3, 1.0)
        block("Blk_" + bone, bone, centre, sz, col)
    # a face so the facing reads in every render: eyes + a nose on the -Z side
    block("Blk_Nose", "Head", (0.0, 1.62, -0.66), (0.28, 0.22, 0.2), (0.9, 0.35, 0.25, 1.0))
    block("Blk_EyeL", "Head", (-0.25, 1.85, -0.61), (0.16, 0.16, 0.06), (0.05, 0.05, 0.05, 1.0))
    block("Blk_EyeR", "Head", (0.25, 1.85, -0.61), (0.16, 0.16, 0.06), (0.05, 0.05, 0.05, 1.0))


def import_launcher_meshes():
    """OBJ + texture per launcher -> mesh datablocks named after the launcher (Roblox part-local
    geometry at LAUNCHER_SCALE, converted to the Blender basis)."""
    for fn in sorted(os.listdir(MESH_DIR)):
        if not fn.endswith(".obj"):
            continue
        name = fn[:-4]
        if bpy.data.meshes.get("M_" + name):
            continue
        verts, uvs, faces = [], [], []
        with open(os.path.join(MESH_DIR, fn)) as f:
            for line in f:
                if line.startswith("v "):
                    _, x, y, z = line.split()
                    verts.append(r2b(Vector((float(x), float(y), float(z))) * LAUNCHER_SCALE))
                elif line.startswith("vt "):
                    _, u, v = line.split()
                    uvs.append((float(u), float(v)))
                elif line.startswith("f "):
                    idx = []
                    for tok in line.split()[1:]:
                        a = tok.split("/")
                        idx.append((int(a[0]) - 1, int(a[1]) - 1 if len(a) > 1 and a[1] else None))
                    faces.append(idx)
        me = bpy.data.meshes.new("M_" + name)
        bm = bmesh.new()
        bv = [bm.verts.new(v) for v in verts]
        bm.verts.ensure_lookup_table()
        uvl = bm.loops.layers.uv.new("UVMap")
        for fc in faces:
            try:
                face = bm.faces.new([bv[i] for i, _ in fc])
            except ValueError:
                continue
            for loop, (_, ti) in zip(face.loops, fc):
                if ti is not None:
                    loop[uvl].uv = uvs[ti]
        bm.to_mesh(me)
        bm.free()
        png = os.path.join(MESH_DIR, name + ".png")
        me.materials.append(_material("Mat_" + name, (0.8, 0.8, 0.8, 1.0), png if os.path.exists(png) else None))
        me.use_fake_user = True


def launcher_object():
    return bpy.data.objects.get("ActiveLauncher")


def use_launcher(lid):
    """Shows launcher `lid` in the right hand (object ActiveLauncher, parented to the Launcher bone)."""
    name, _ = launcher_info(lid)
    me = bpy.data.meshes["M_" + name]
    ob = launcher_object()
    if ob is None:
        ob = bpy.data.objects.new("ActiveLauncher", me)
        bpy.context.scene.collection.objects.link(ob)
    ob.data = me
    r = rig()
    saved = {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in r.pose.bones}
    reset_pose()
    ob.parent = r
    ob.parent_type = 'BONE'
    ob.parent_bone = "Launcher"
    ob.matrix_parent_inverse = Matrix.Identity(4)
    update()
    M = pivot_rest() @ pivot_offset(lid).inverted()
    ob.matrix_world = rbx_to_blender_matrix(M)
    update()
    for pb in r.pose.bones:
        pb.rotation_quaternion, pb.location = saved[pb.name]
    update()
    bpy.context.scene["launcher_id"] = int(lid)
    return ob


def build_props():
    for name in ("Ground", "TrackArrow", "Ball", "PadEdge"):
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
        me.materials.append(_material(name + "Mat", color))
        return ob

    mk("Ground", lambda bm: bmesh.ops.create_grid(bm, x_segments=12, y_segments=12, size=10.0,
                                                  matrix=Matrix.Translation((0.0, 0.0, FLOOR_Y))), (0.78, 0.8, 0.84, 1.0))
    # down-track arrow on the floor (-X)
    mk("TrackArrow", lambda bm: bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((-6.5, 0.0, FLOOR_Y + 0.02))
                                                      @ Matrix.Diagonal((8.0, 0.15, 0.02, 1.0))), (0.2, 0.75, 0.3, 1.0))
    ball = mk("Ball", lambda bm: bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=BALL_RADIUS),
              (0.97, 0.98, 1.0, 1.0))
    for p in ball.data.polygons:
        p.use_smooth = True


def build_scene(save_path=None):
    """One-time: rig + blocks + launcher meshes + props -> LauncherAnims.blend"""
    build_rig()
    build_blocks()
    import_launcher_meshes()
    build_props()
    use_launcher(1)
    scene = bpy.context.scene
    scene.render.fps = FPS
    if save_path:
        bpy.ops.wm.save_as_mainfile(filepath=save_path)


# ---------------------------------------------------------------- posing
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
    """posed joint position (bone head), Roblox HRP-local"""
    update()
    return b2r(rig().pose.bones[name].head)


def frame_of(name):
    """3x3 whose columns are the posed bone's local X / Y / Z axes in Roblox coords"""
    update()
    m = rig().pose.bones[name].matrix.to_3x3()
    X, Y, Z = b2r(m.col[0]), b2r(m.col[1]), b2r(m.col[2])
    return Matrix((X, Y, Z)).transposed()


def world_cf(name):
    """posed bone frame as a Roblox 4x4 (HRP-local)"""
    m = frame_of(name).to_4x4()
    m.translation = joint(name)
    return m


def hand_cf(side="Right"):
    return world_cf(side + "Hand") @ cf(HAND_CENTER)


def pivot_cf():
    """current launcher grip-pivot frame (Roblox 4x4, HRP-local)"""
    return world_cf("Launcher")


def launcher_point(p):
    """launcher-local point (pivot frame, template scale) -> Roblox HRP-local"""
    return pivot_cf() @ (Vector(p) * LAUNCHER_SCALE)


def launcher_dir(d):
    return (pivot_cf().to_3x3() @ Vector(d)).normalized()


def frame_quat(neg_y_dir, x_hint):
    u = Vector(neg_y_dir).normalized()
    Y = -u
    X = Vector(x_hint) - Vector(x_hint).dot(Y) * Y
    if X.length < 1e-6:
        X = Vector((1.0, 0.0, 0.0)) - Y.x * Y
    X.normalize()
    Z = X.cross(Y)
    return Matrix((X, Y, Z)).transposed().to_quaternion()


def solve_limb(d_local, L1, L2, fwd_local, bend=1.0):
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


ELBOW_GUARD = True  # never let the upper arm roll INTO the torso (see solve_arm)


def solve_arm(side, d_local, fwd_local, guard=None):
    """R15 arm IK (the elbow hangs 0.5 studs outside the shoulder). d_local = wrist target -
    shoulder in the UpperTorso frame; fwd_local = the direction the elbow bows AWAY from
    (an UP-ish vector gives natural down-and-out elbows).  With the guard on (default) a pole
    that would roll the upper arm inward (hinge axis pointing into the body, the arm block sunk
    in the chest, the elbow tucked at the middle) is mirrored, so the elbow stays down/out."""
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
    # The upper arm's 0.5-stud offset lies along +/- its hinge axis (+X for the right arm, -X for
    # the left), and both elbows flex forward about +X: a hinge pointing to the torso's -X side
    # sinks the upper arm into the chest (right) / folds the elbow the wrong way (left).
    if (ELBOW_GUARD if guard is None else guard) and n.x < -0.15:
        n = -n

    def frame(f, x):
        a1 = f.normalized()
        a2 = x - x.dot(a1) * a1
        if a2.length < 1e-6:
            a2 = Vector((0.0, 0.0, 1.0)) - a1.z * a1
        a2.normalize()
        return Matrix((a1, a2, a1.cross(a2))).transposed()

    R = frame(t, n) @ frame(p, Vector((1.0, 0.0, 0.0))).transposed()
    return R.to_quaternion(), Quaternion((1.0, 0.0, 0.0), theta), max(0.0, D - reach)


def stance(hip_drop=0.0, hip_back=0.0, hip_side=0.0, root=None, feet=None, foot_yaw=None, foot_flat=True):
    """Legs + pelvis.  root = Quaternion (LowerTorso rotation relative to the HRP; e.g.
    ry(40) turns the whole body 40 degrees LEFT = toward the track, rx(-10) leans forward).
    hip_drop studs down, hip_back studs toward +Z (the character's back), hip_side toward +X.
    feet = {"Left": (x, z), "Right": (x, z)} ankle spots on the floor (default = rest).
    Knees bow toward each foot's toes (foot_yaw degrees, default follows the root yaw).
    Returns overreach per leg (0 = both ankles land exactly)."""
    q_root = Quaternion(root) if root is not None else IDENT.copy()
    set_loc("LowerTorso", (hip_side, -hip_drop, hip_back))
    set_rot("LowerTorso", q_root)
    out = {}
    yaw_root = math.degrees(2.0 * math.atan2(q_root.y, q_root.w)) if abs(q_root.w) > 1e-6 else 0.0
    for side in ("Left", "Right"):
        if feet and side in feet:
            fx, fz = feet[side]
            target = Vector((fx, ANKLE_REST[side][1], fz))
        else:
            target = Vector(ANKLE_REST[side])
        yaw = (foot_yaw or {}).get(side, yaw_root) if isinstance(foot_yaw, dict) else (foot_yaw if foot_yaw is not None else yaw_root)
        toe = ry(yaw) @ Vector((0.0, 0.0, -1.0))
        hip = joint(side + "UpperLeg")
        Mi = frame_of("LowerTorso").inverted()
        qu, ql, err = solve_limb(Mi @ (target - hip), THIGH, SHIN, Mi @ toe, bend=-1.0)
        set_rot(side + "UpperLeg", qu)
        set_rot(side + "LowerLeg", ql)
        if foot_flat:
            want = ry(yaw).to_matrix()
            set_rot(side + "Foot", (frame_of(side + "LowerLeg").inverted() @ want).to_quaternion())
        out[side] = round(err, 3)
    return out


def waist(q):
    """UpperTorso rotation relative to the LowerTorso (ry = twist left, rx = bend fwd(-)/back(+))"""
    set_rot("UpperTorso", Quaternion(q))
    update()


def head_look(target=None, yaw=None, pitch=None, max_yaw=80.0, max_pitch=50.0):
    """Turns the head toward a Roblox HRP-local point (or explicit yaw/pitch degrees)."""
    if target is not None:
        neck = joint("Head")
        d = frame_of("UpperTorso").inverted() @ (Vector(target) - neck - frame_of("UpperTorso") @ Vector((0.0, 0.6, 0.0)))
        yaw = math.degrees(math.atan2(-d.x, -d.z))
        flat = math.hypot(d.x, d.z)
        pitch = math.degrees(math.atan2(d.y, flat))
    yaw = max(-max_yaw, min(max_yaw, yaw or 0.0))
    pitch = max(-max_pitch, min(max_pitch, pitch or 0.0))
    set_rot("Head", ry(yaw) @ rx(pitch))
    update()
    return yaw, pitch


def arm_to(side, wrist_target, elbow_away=(0.0, 1.0, 0.0), hand_rot=None, guard=None):
    """Two-bone IK of one arm to a WRIST point (Roblox HRP-local).  The elbow bows AWAY from
    elbow_away (world dir): (0, 1, 0) = up = the elbow hangs down and out, the natural default;
    add a bit of +Z to push the elbow forward, -Z back.  The guard (on by default) mirrors any
    pole that would roll the upper arm into the chest.  hand_rot: world 3x3/Quaternion for the
    hand frame (None = straight wrist).  Returns (overreach, wrist error)."""
    sh = joint(side + "UpperArm")
    Mt = frame_of("UpperTorso")
    Mi = Mt.inverted()
    qu, ql, err = solve_arm(side, Mi @ (Vector(wrist_target) - sh), Mi @ Vector(elbow_away), guard)
    set_rot(side + "UpperArm", qu)
    set_rot(side + "LowerArm", ql)
    if hand_rot is None:
        set_rot(side + "Hand", IDENT)
    else:
        R = hand_rot.to_matrix() if isinstance(hand_rot, Quaternion) else Matrix(hand_rot)
        set_rot(side + "Hand", (frame_of(side + "LowerArm").inverted() @ R).to_quaternion())
    update()
    return round(err, 3), round((joint(side + "Hand") - Vector(wrist_target)).length, 3)


def _meta_frame(meta, key):
    """launcher-local frame from meta[key] = {pos, look, up} (pivot frame, template scale)"""
    e = meta[key]
    if not isinstance(e, dict):
        e = {"pos": e}
    # points without their own axes use the launcher's: forward -Y, top -Z
    R = look_frame(e.get("look", (0.0, -1.0, 0.0)), e.get("up", (0.0, 0.0, -1.0)))
    return cf(Vector(e["pos"]) * LAUNCHER_SCALE, R)


def swing_twist(q, axis=(0.0, 1.0, 0.0)):
    """splits q into swing @ twist, twist = rotation about axis (bone-local, +Y = along the bone)"""
    a = Vector(axis).normalized()
    v = Vector((q.x, q.y, q.z))
    p = a * v.dot(a)
    twist = Quaternion((q.w, p.x, p.y, p.z))
    if twist.magnitude < 1e-9:
        twist = IDENT.copy()
    twist.normalize()
    swing = q @ twist.inverted()
    return swing, twist


def clamp_wrist(q, max_bend=65.0, max_twist=100.0):
    """limits a hand rotation (relative to the forearm) to a human wrist: bend (swing) up to
    max_bend degrees, forearm roll (twist about the forearm) up to max_twist degrees"""
    swing, twist = swing_twist(q)
    sa = math.degrees(swing.angle)
    if sa > max_bend:
        swing = IDENT.slerp(swing, max_bend / sa)
    ta = math.degrees(twist.angle)
    if ta > 180.0:
        twist = -twist
        ta = math.degrees(twist.angle)
    if ta > max_twist:
        twist = IDENT.slerp(twist, max_twist / ta)
    return swing @ twist


def place_launcher(at, forward, up=(0.0, 1.0, 0.0), anchor="Muzzle", elbow_away=(-0.3, 1.0, 0.1),
                   max_wrist=65.0, max_twist=100.0, grip_twist=None, iterations=4):
    """Puts the launcher where you want it and solves the RIGHT arm.
      at       Roblox HRP-local point for the anchor ("Muzzle", "Seat", "Tip", "Pivot" or any
               key in meta/<NN>.json that has pos/look/up)
      forward  world direction the anchor's LOOK axis should point (e.g. DOWN_TRACK)
      up       world direction for the anchor's UP axis
    The hand takes the orientation (wrist bend up to max_wrist degrees, forearm roll up to
    max_twist); anything beyond that is put on the Launcher bone (the launcher turning in the
    grip -- keep grip_turn_deg small, under ~35, or it reads as the launcher sliding around in
    the hand; change the body / arm pose instead).  grip_twist forces an explicit Launcher-bone
    rotation (Quaternion).  Returns a dict of errors (studs / degrees): arm_overreach > 0 means
    the target is out of reach (move it closer to the shoulder)."""
    lid = bpy.context.scene["launcher_id"]
    meta = load_meta(lid)
    if anchor == "Pivot":
        A = cf((0.0, 0.0, 0.0), look_frame((0.0, -1.0, 0.0), (0.0, 0.0, -1.0)))
    else:
        A = _meta_frame(meta, anchor)
    want_anchor = cf(at, look_frame(forward, up))
    want_pivot = want_anchor @ A.inverted()          # pivot frame we want (Roblox HRP-local)
    G = G_GRIP()
    set_rot("Launcher", IDENT if grip_twist is None else grip_twist)
    info = {}
    for _ in range(iterations):
        grip_q = get_rot("Launcher")
        # hand part frame that would put the pivot there with the current grip rotation
        H = want_pivot @ cf((0.0, 0.0, 0.0), grip_q).inverted() @ G.inverted()
        W = H @ cf(HAND_CENTER).inverted()          # wrist joint frame
        err, werr = arm_to("Right", W.translation, elbow_away, None)
        # wrist: bend toward the wanted hand orientation, clamp, rest on the grip bone
        R_arm = frame_of("RightLowerArm")
        R_want = W.to_3x3()
        rel = (R_arm.inverted() @ R_want).to_quaternion()
        if grip_twist is None:
            rel = clamp_wrist(rel, max_wrist, max_twist)
        set_rot("RightHand", rel)
        update()
        if grip_twist is None:
            Hn = world_cf("RightHand") @ cf(HAND_CENTER)
            P0 = Hn @ G                              # pivot with no grip rotation
            gq = (P0.to_3x3().inverted() @ want_pivot.to_3x3()).to_quaternion()
            set_rot("Launcher", gq)
            update()
        info = {"arm_overreach": err, "wrist_err": werr}
    got = pivot_cf() @ A
    info["anchor_err"] = round((got.translation - Vector(at)).length, 3)
    info["dir_err_deg"] = round(angle_between(got.to_3x3() @ Vector((0.0, 0.0, -1.0)), forward), 1)
    info["wrist_bend_deg"] = round(math.degrees(get_rot("RightHand").angle), 1)
    info["grip_turn_deg"] = round(math.degrees(get_rot("Launcher").angle), 1)
    return info


def direction(yaw=0.0, elev=0.0):
    """world unit vector from two angles in degrees:
         yaw   0 = DOWN-TRACK (-X, the character's left, away from the camera)
              +90 = the character's FRONT (-Z, screen-right in the pad camera)
              -90 = the character's BACK (+Z), 180 = toward the camera (+X)
         elev  + = up, - = down"""
    y, e = math.radians(yaw), math.radians(elev)
    flat = Vector((-math.cos(y), 0.0, -math.sin(y)))
    return (flat * math.cos(e) + Vector((0.0, math.sin(e), 0.0))).normalized()


def up_for(forward, roll=0.0):
    """the 'top' direction for a launcher pointing along forward: as upright as possible, then
    rolled `roll` degrees about forward (+ = clockwise seen from behind the launcher)"""
    f = Vector(forward).normalized()
    side = f.cross(Vector((0.0, 1.0, 0.0)))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    up = side.cross(f).normalized()
    if roll:
        up = Quaternion(f, math.radians(roll)) @ up
    return up


def hold(at, yaw=0.0, elev=0.0, roll=0.0, anchor="Pivot", **kw):
    """place_launcher with angles: the anchor's look axis points along direction(yaw, elev) and
    the launcher's top is up (rolled by roll).  anchor "Pivot" = the grip (at = where the right
    hand's grip point goes; look = the launcher's forward axis).  Extra keywords go to
    place_launcher (elbow_away, max_wrist, grip_twist ...)."""
    fwd = direction(yaw, elev)
    return place_launcher(at=at, forward=fwd, up=up_for(fwd, roll), anchor=anchor, **kw)


def left_hand_to(point=None, key="Grip2", elbow_away=(0.3, 1.0, 0.1), palm_toward=None, offset=(0.0, 0.0, 0.0)):
    """LEFT hand grabs the launcher at meta[key] (or a Roblox HRP-local point).  The wrist is
    placed so the hand CENTRE lands on the point.  palm_toward: optional world direction the
    palm (hand -X for the left hand) faces.  Returns (overreach, error)."""
    lid = bpy.context.scene["launcher_id"]
    if point is None:
        meta = load_meta(lid)
        e = meta[key]
        pos = e["pos"] if isinstance(e, dict) else e
        point = launcher_point(pos)
    point = Vector(point) + Vector(offset)
    # first pass: straight wrist, then aim the hand
    wrist = point - Vector(HAND_CENTER)
    err = arm_to("Left", wrist, elbow_away, None)
    for _ in range(2):
        R = frame_of("LeftHand")
        wrist = point - R @ Vector(HAND_CENTER)
        hand_rot = None
        if palm_toward is not None:
            y = -(frame_of("LeftLowerArm") @ Vector((0.0, 1.0, 0.0)))  # along the forearm, away from the elbow
            y = -y
            x = -Vector(palm_toward).normalized()
            x = (x - x.dot(y) * y)
            if x.length > 1e-4:
                x.normalize()
                z = x.cross(y)
                hand_rot = Matrix((x, y, z)).transposed()
        err = arm_to("Left", wrist, elbow_away, hand_rot)
    return err


# ---------------------------------------------------------------- clips
CLIP_KINDS = ("Ready", "ChargeLo", "ChargeHi", "Fire")


def clip_name(kind, lid=None):
    lid = lid if lid is not None else bpy.context.scene["launcher_id"]
    return "L%02d_%s" % (int(lid), kind)


def new_clip(kind):
    r = rig()
    if r.animation_data is None:
        r.animation_data_create()
    name = clip_name(kind)
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    r.animation_data.action = act
    try:
        slot = act.slots[0] if len(act.slots) else act.slots.new(id_type='OBJECT', name=r.name)
        r.animation_data.action_slot = slot
    except Exception:
        pass
    bpy.context.scene.render.fps = FPS
    return act


def key(frame):
    """keys every bone (rotation + location) at frame (30 fps)"""
    r = rig()
    for name in BONES:
        pb = r.pose.bones[name]
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def fcurves(action):
    """every F-curve of an action (slotted actions in Blender 4.4+ keep them in channel bags)"""
    out = []
    try:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
    except AttributeError:
        pass
    if not out:
        try:
            out = list(action.fcurves)
        except AttributeError:
            pass
    return out


def make_cyclic(kind):
    """loop clips: cyclic F-curves so the auto handles flow through the seam (no stop at the loop
    point).  Key the first pose again on the last frame before calling this."""
    act = bpy.data.actions[clip_name(kind)]
    for fc in fcurves(act):
        if not any(m.type == 'CYCLES' for m in fc.modifiers):
            fc.modifiers.new('CYCLES')
        for kp in fc.keyframe_points:
            kp.handle_left_type = 'AUTO_CLAMPED'
            kp.handle_right_type = 'AUTO_CLAMPED'
        fc.update()


def set_interpolation(kind, mode='BEZIER', handles='AUTO_CLAMPED', frames=None):
    """changes keys of a clip: mode BEZIER / LINEAR / CONSTANT; handles AUTO_CLAMPED (eases into
    every key) or AUTO (flows through keys, may overshoot a little).  frames = only those keys."""
    act = bpy.data.actions[clip_name(kind)]
    for fc in fcurves(act):
        for kp in fc.keyframe_points:
            if frames is not None and int(round(kp.co.x)) not in frames:
                continue
            kp.interpolation = mode
            kp.handle_left_type = handles
            kp.handle_right_type = handles
        fc.update()


def use_clip(kind_or_action):
    act = kind_or_action if isinstance(kind_or_action, bpy.types.Action) else bpy.data.actions[clip_name(kind_or_action)]
    r = rig()
    if r.animation_data is None:
        r.animation_data_create()
    r.animation_data.action = act
    try:
        if len(act.slots):
            r.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    return act


def goto(t):
    scene = bpy.context.scene
    f = t * FPS
    scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
    update()


def snapshot():
    """current pose -> {bone: (quat, loc)}"""
    r = rig()
    return {pb.name: (pb.rotation_quaternion.copy(), pb.location.copy()) for pb in r.pose.bones}


def restore(snap):
    r = rig()
    for pb in r.pose.bones:
        q, l = snap[pb.name]
        pb.rotation_quaternion = q
        pb.location = l
    update()


def blend_snapshots(a, b, t):
    out = {}
    for k in a:
        qa, la = a[k]
        qb, lb = b[k]
        if qa.dot(qb) < 0.0:
            qb = -qb
        out[k] = (qa.slerp(qb, t), la.lerp(lb, t))
    return out


# ---------------------------------------------------------------- sampling / export
def sample_clip(kind, length):
    use_clip(kind)
    r = rig()
    frames = []
    n = int(round(length * FPS))
    for i in range(n + 1):
        goto(i / FPS)
        row = []
        prev = None
        for name in EXPORT_BONES:
            pb = r.pose.bones[name]
            q = pb.rotation_quaternion.normalized()
            p = pb.location
            row.append([round(q.w, 4), round(q.x, 4), round(q.y, 4), round(q.z, 4),
                        round(p.x, 4), round(p.y, 4), round(p.z, 4)])
        frames.append(row)
    return frames


def world_track(kind, length, key_name, fps=FPS):
    """samples the world (HRP-local) frame of a launcher meta point through a clip"""
    use_clip(kind)
    lid = bpy.context.scene["launcher_id"]
    meta = load_meta(lid)
    out = []
    n = int(round(length * fps))
    for i in range(n + 1):
        goto(i / fps)
        if key_name in ("LeftHand", "RightHand"):
            m = hand_cf(key_name[:-4])
        else:
            m = pivot_cf() @ _meta_frame(meta, key_name)
        out.append(m)
    return out


def export(spec, path=None):
    """spec = {"Ready": len, "ChargeLo": len, "ChargeHi": len, "Fire": len, "FireAt": t,
               "BallAppearAt": t|None, "Ball": {...}, "Notes": "..."}  -> out/NN.json"""
    lid = bpy.context.scene["launcher_id"]
    name, info = launcher_info(lid)
    meta = load_meta(lid)
    data = {"id": int(lid), "name": name, "fps": FPS, "bones": EXPORT_BONES, "meta": meta,
            "spec": {k: v for k, v in spec.items()}, "clips": {}}
    for kind in CLIP_KINDS:
        if kind in spec:
            data["clips"][kind] = {"length": spec[kind], "frames": sample_clip(kind, spec[kind])}
    os.makedirs(OUT_DIR, exist_ok=True)
    path = path or os.path.join(OUT_DIR, "%02d.json" % int(lid))
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    return path


# ---------------------------------------------------------------- checks
def body_boxes():
    """current world boxes of the body blocks (for clearance checks): list of (name, 4x4, half-size)"""
    out = []
    for bone, (centre, size) in PART_BLOCKS.items():
        m = world_cf(bone)
        rest_joint = Vector(REST[bone])
        local = Vector(centre) - rest_joint
        k = BLOCK_SHRINK.get(bone, 1.0)
        half = Vector((size[0] * k, size[1], size[2] * k)) * 0.5
        box = m @ cf(local)
        out.append((bone, box, half))
    return out


def point_box_distance(p, box, half):
    q = box.inverted() @ Vector(p)
    d = Vector((max(abs(q.x) - half.x, 0.0), max(abs(q.y) - half.y, 0.0), max(abs(q.z) - half.z, 0.0)))
    return d.length


def clearance(p, skip=()):
    """distance from a point to the nearest body block (0 = inside)"""
    best, who = 1e9, None
    for name, box, half in body_boxes():
        if name in skip:
            continue
        d = point_box_distance(p, box, half)
        if d < best:
            best, who = d, name
    return best, who


def launcher_lowest_y():
    ob = launcher_object()
    update()
    mw = ob.matrix_world
    return min(b2r(mw @ v.co).y for v in ob.data.vertices)


AUDIT_SIZE = {"UpperTorso": (1.7, 1.6, 0.95), "LowerTorso": (1.6, 0.4, 0.95), "Head": (1.2, 1.2, 1.2),
              "LeftUpperArm": (0.55, 0.8, 0.55), "LeftLowerArm": (0.5, 0.78, 0.5), "LeftHand": (0.45, 0.5, 0.5),
              "RightUpperArm": (0.55, 0.8, 0.55), "RightLowerArm": (0.5, 0.78, 0.5), "RightHand": (0.45, 0.5, 0.5)}
AUDIT_ARMS = ("LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand")
AUDIT_JOINTS = ("LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
                "Head", "UpperTorso", "LowerTorso")


def _depth_inside(p, box, half):
    q = box.inverted() @ p
    dx, dy, dz = half.x - abs(q.x), half.y - abs(q.y), half.z - abs(q.z)
    return min(dx, dy, dz) if (dx > 0 and dy > 0 and dz > 0) else 0.0


def motion_audit(kind, length):
    """Frame-by-frame check of one clip on realistic avatar proportions: arm parts / launcher
    sunk in the torso or head, one-frame IK snaps (a joint turning > 30 deg in a frame while its
    neighbours barely move) and elbow flips (the bend jumping > 25 deg and straight back)."""
    frames = sample_clip(kind, length)
    use_clip(kind)
    lob = launcher_object()
    verts = [v.co.copy() for v in lob.data.vertices]
    verts = verts[::max(1, len(verts) // 120)]
    worst_arm, arm_at, worst_l, l_at = 0.0, "", 0.0, ""
    for fi in range(0, len(frames), 3):
        goto(fi / FPS)
        boxes = {n: (b, (Vector(AUDIT_SIZE[n]) * 0.5 if n in AUDIT_SIZE else h)) for n, b, h in body_boxes()}
        for arm in AUDIT_ARMS:
            ab, ah = boxes[arm]
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    for k in (-1, 0, 1):
                        pt = ab @ Vector((i * ah.x * 0.8, j * ah.y * 0.8, k * ah.z * 0.8))
                        for body in ("UpperTorso", "Head", "LowerTorso"):
                            d = _depth_inside(pt, *boxes[body])
                            if d > worst_arm:
                                worst_arm, arm_at = d, "%s in %s @%.2fs" % (arm, body, fi / FPS)
        mw = lob.matrix_world
        for co in verts:
            pt = b2r(mw @ co)
            for body in ("UpperTorso", "Head"):
                d = _depth_inside(pt, *boxes[body])
                if d > worst_l:
                    worst_l, l_at = d, "launcher in %s @%.2fs" % (body, fi / FPS)
    snaps, flips = [], []
    for j, name in enumerate(EXPORT_BONES):
        if name not in AUDIT_JOINTS:
            continue
        d = [0.0]
        for fi in range(1, len(frames)):
            qa, qb = Quaternion(frames[fi - 1][j][:4]), Quaternion(frames[fi][j][:4])
            a = math.degrees(qa.rotation_difference(qb).angle)
            d.append(min(a, 360.0 - a))
        for fi in range(1, len(d)):
            nb = [d[k] for k in (fi - 2, fi - 1, fi + 1, fi + 2) if 0 < k < len(d)]
            med = sorted(nb)[len(nb) // 2] if nb else 0.0
            if d[fi] > 30.0 and d[fi] > 3.0 * max(med, 1.0):
                snaps.append("%s %.0fdeg @%.2fs" % (name, d[fi], fi / FPS))
        if name.endswith("LowerArm"):
            bend = [math.degrees(Quaternion(fr[j][:4]).angle) for fr in frames]
            bend = [min(b, 360.0 - b) for b in bend]
            for fi in range(1, len(bend) - 2):
                a1 = bend[fi] - bend[fi - 1]
                for k in (1, 2):
                    a2 = bend[fi + k] - bend[fi + k - 1]
                    if abs(a1) > 25.0 and abs(a2) > 25.0 and a1 * a2 < 0:
                        flips.append("%s %.0f/%.0f @%.2fs" % (name, a1, a2, fi / FPS))
                        break
    return {"arm_in_body": round(worst_arm, 2), "arm_in_body_at": arm_at,
            "launcher_in_body": round(worst_l, 2), "launcher_in_body_at": l_at,
            "snaps": snaps[:6], "flips": flips[:6]}


def check(spec):
    """Automated review of the authored clips.  Returns a dict; 'problems' lists hard failures."""
    lid = bpy.context.scene["launcher_id"]
    meta = load_meta(lid)
    rep = {"problems": [], "warnings": []}
    # loops close
    for kind in ("Ready", "ChargeLo", "ChargeHi"):
        if kind not in spec:
            rep["problems"].append("missing clip " + kind)
            continue
        fr = sample_clip(kind, spec[kind])
        a, b = fr[0], fr[-1]
        worst = 0.0
        for ja, jb in zip(a, b):
            qa, qb = Quaternion(ja[:4]), Quaternion(jb[:4])
            ang = math.degrees(qa.rotation_difference(qb).angle)
            worst = max(worst, min(ang, 360.0 - ang))  # q and -q are the same rotation
        rep[kind + "_loop_seam_deg"] = round(worst, 2)
        if worst > 1.0:
            rep["problems"].append("%s does not loop (seam %.1f deg)" % (kind, worst))
    if spec.get("ChargeLo") != spec.get("ChargeHi"):
        rep["problems"].append("ChargeLo and ChargeHi must have the same length")
    # fire direction + clearance at the fire moment
    if "Fire" in spec and "FireAt" in spec:
        use_clip("Fire")
        goto(spec["FireAt"])
        mz = pivot_cf() @ _meta_frame(meta, "Muzzle")
        look = mz.to_3x3() @ Vector((0.0, 0.0, -1.0))
        flat = Vector((look.x, 0.0, look.z))
        rep["fire_muzzle_pos"] = [round(v, 2) for v in mz.translation]
        rep["fire_dir"] = [round(v, 3) for v in look]
        rep["fire_yaw_off_track_deg"] = round(angle_between(flat, DOWN_TRACK), 1) if flat.length > 1e-4 else 90.0
        rep["fire_elevation_deg"] = round(math.degrees(math.asin(max(-1.0, min(1.0, look.normalized().y)))), 1)
        if rep["fire_yaw_off_track_deg"] > 20.0:
            rep["problems"].append("muzzle points %.0f deg off the track at FireAt" % rep["fire_yaw_off_track_deg"])
        if rep["fire_elevation_deg"] < -15.0 or rep["fire_elevation_deg"] > 55.0:
            rep["problems"].append("fire elevation %.0f deg is outside -15..55" % rep["fire_elevation_deg"])
        start = mz.translation
        if spec.get("Ball", {}).get("start") == "Seat":
            start = seat_point(spec)
        c, who = clearance(start + look.normalized() * 0.1)
        rep["ball_start"] = [round(v, 2) for v in start]
        rep["ball_body_clearance"] = round(c - BALL_RADIUS, 2)
        rep["ball_nearest_part"] = who
        if c - BALL_RADIUS < -0.35:
            rep["problems"].append("ball starts inside the body (%s, %.2f)" % (who, c - BALL_RADIUS))
        if start.y - BALL_RADIUS < FLOOR_Y - 0.05:
            rep["problems"].append("ball starts under the floor")
        # the flight path must not pass through the body for the first 4 studs
        worst = 9.0
        for i in range(1, 9):
            p = start + look.normalized() * (0.5 * i)
            c, who2 = clearance(p)
            worst = min(worst, c - BALL_RADIUS)
        rep["flight_clearance"] = round(worst, 2)
        if worst < -0.2:
            rep["problems"].append("flight path hits the body (%.2f)" % worst)
    # frame-by-frame body / IK audit (realistic avatar sizes)
    for kind in CLIP_KINDS:
        if kind not in spec:
            continue
        a = motion_audit(kind, spec[kind])
        rep[kind + "_audit"] = a
        if a["flips"]:
            rep["problems"].append("%s: elbow flips (IK popping between straight and bent): %s" % (kind, ", ".join(a["flips"][:3])))
        if a["snaps"]:
            rep["warnings"].append("%s: one-frame joint snaps: %s" % (kind, ", ".join(a["snaps"][:3])))
        if a["arm_in_body"] > 0.25:
            rep["warnings"].append("%s: arm sunk %.2f studs into the body (%s)" % (kind, a["arm_in_body"], a["arm_in_body_at"]))
        if a["launcher_in_body"] > 0.2:
            rep["warnings"].append("%s: launcher %.2f studs inside the body (%s)" % (kind, a["launcher_in_body"], a["launcher_in_body_at"]))
    # the launcher's turn in the hand is judged against how it sits in the Ready pose
    grip_ref = None
    if "Ready" in spec:
        use_clip("Ready")
        goto(0.0)
        grip_ref = get_rot("Launcher")
    # floor + feet + reach over every clip
    for kind in CLIP_KINDS:
        if kind not in spec:
            continue
        use_clip(kind)
        low, feet_drift, hand_gap, grip_turn, bend = 9.0, 0.0, 0.0, 0.0, 0.0
        n = int(round(spec[kind] * FPS))
        for i in range(0, n + 1, 2):
            goto(i / FPS)
            low = min(low, launcher_lowest_y())
            g = get_rot("Launcher")
            grip_turn = max(grip_turn, math.degrees((grip_ref.inverted() @ g).angle if grip_ref else g.angle))
            sw, _ = swing_twist(get_rot("RightHand"))
            bend = max(bend, math.degrees(sw.angle))
            for side in ("Left", "Right"):
                a = joint(side + "Foot")
                feet_drift = max(feet_drift, abs(a.y - ANKLE_REST[side][1]))
            if meta.get("Grip2") and spec.get("TwoHanded", True):
                g2 = meta["Grip2"]
                g2 = g2["pos"] if isinstance(g2, dict) else g2
                gap = (hand_cf("Left").translation - launcher_point(g2)).length
                hand_gap = max(hand_gap, gap)
        rep[kind + "_launcher_lowest_y"] = round(low, 2)
        rep[kind + "_ankle_lift"] = round(feet_drift, 2)
        rep[kind + "_max_grip_turn_deg"] = round(grip_turn, 1)
        rep[kind + "_max_wrist_bend_deg"] = round(bend, 1)
        if grip_turn > 60.0:
            rep["warnings"].append("%s: the launcher turns %.0f deg in the hand (vs Ready)" % (kind, grip_turn))
        if bend > 80.0:
            rep["warnings"].append("%s: the right wrist bends %.0f deg" % (kind, bend))
        if meta.get("Grip2") and spec.get("TwoHanded", True):
            rep[kind + "_left_hand_gap"] = round(hand_gap, 2)
        if low < FLOOR_Y - 0.25:
            rep["problems"].append("%s: launcher sinks %.2f studs into the floor" % (kind, FLOOR_Y - low))
        if feet_drift > 0.35 and not spec.get("AllowFootLift"):
            rep["warnings"].append("%s: a foot leaves its spot by %.2f studs" % (kind, feet_drift))
    return rep


# ---------------------------------------------------------------- previews
def _camera(eye, look_at, lens=None, fov_deg=None):
    scene = bpy.context.scene
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        camd = bpy.data.cameras.new("PreviewCam")
        cam = bpy.data.objects.new("PreviewCam", camd)
        scene.collection.objects.link(cam)
    camd = cam.data
    if fov_deg is not None:
        camd.sensor_fit = 'VERTICAL'
        camd.angle_y = math.radians(fov_deg)
    elif lens is not None:
        camd.sensor_fit = 'AUTO'
        camd.lens = lens
    e, l = r2b(eye), r2b(look_at)
    cam.location = e
    cam.rotation_euler = (l - e).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    return cam


VIEWS = {
    # the in-game pad camera, cropped around the character (same eye, narrower field of view)
    "game": (CAMERA_GAME[0], (-1.5, 0.3, 0.0), None, 30.0),
    # the full in-game frame (FieldOfView 70): how small it all really is
    "gamewide": (CAMERA_GAME[0], CAMERA_GAME[1], None, 70.0),
    "front": (CAMERA_FRONT[0], CAMERA_FRONT[1], 28.0, None),
    # from down the track: a correct shot comes straight at this camera
    "track": (CAMERA_TRACK[0], CAMERA_TRACK[1], 30.0, None),
    "top": (CAMERA_TOP[0], CAMERA_TOP[1], 28.0, None),
}


def seat_point(spec):
    """where the ball rests before the shot (Roblox HRP-local): spec Ball.hand == "Left" = in the
    left hand at Ball.offset (hand part frame), else the launcher's Seat (or Muzzle)"""
    lid = bpy.context.scene["launcher_id"]
    meta = load_meta(lid)
    ball = spec.get("Ball", {})
    if ball.get("hand") == "Left":
        return (hand_cf("Left") @ cf(Vector(ball.get("offset", (0.0, -0.45, 0.0))))).translation
    key = "Seat" if meta.get("Seat") else "Muzzle"
    return (pivot_cf() @ _meta_frame(meta, key)).translation


def ball_world_at(kind, t, spec):
    """where the preview ball is at clip time t (None = hidden)"""
    lid = bpy.context.scene["launcher_id"]
    meta = load_meta(lid)
    ball = spec.get("Ball", {})
    show = ball.get("show", "Never")
    fire_at = spec.get("FireAt", 0.3)
    if kind == "Fire" and t >= fire_at:
        cur = t
        goto(fire_at)
        mz = pivot_cf() @ _meta_frame(meta, "Muzzle")
        start = mz.translation
        if ball.get("start") == "Seat":
            start = seat_point(spec)
        look = (mz.to_3x3() @ Vector((0.0, 0.0, -1.0))).normalized()
        goto(cur)
        dt = t - fire_at
        return start + look * (32.0 * dt) + Vector((0.0, -0.5 * 196.2 * 0.25 * dt * dt, 0.0))
    visible = (show == "Always") or (show == "Charge" and kind in ("ChargeLo", "ChargeHi", "Fire")) \
        or (show == "Fire" and kind == "Fire" and t >= spec.get("BallAppearAt", fire_at))
    if not visible:
        return None
    return seat_point(spec)


def render_sheet(spec, path, view="game", kinds=None, per_clip=6, size=(360, 202), extra_times=None):
    """Renders a contact sheet: one row per clip, per_clip evenly spaced frames (+ the fire moment
    for Fire).  Also writes each clip's frames at the chosen view.  Returns the PNG path."""
    import numpy as np
    scene = bpy.context.scene
    kinds = kinds or [k for k in CLIP_KINDS if k in spec]
    eye, look, lens, fov = VIEWS[view]
    _camera(eye, look, lens=lens, fov_deg=fov)
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.show_shadows = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    ball = bpy.data.objects.get("Ball")
    rows = []
    # per-process scratch file: many headless Blenders render at the same time
    tmp = os.path.join(OUT_DIR, "_tmp_render_%s_%d.png" % (bpy.context.scene.get("launcher_id", 0), os.getpid()))
    os.makedirs(OUT_DIR, exist_ok=True)
    for kind in kinds:
        length = spec[kind]
        times = [length * i / max(per_clip - 1, 1) for i in range(per_clip)]
        if kind == "Fire" and "FireAt" in spec:
            times = sorted(set([round(t, 3) for t in times] + [round(spec["FireAt"], 3)]))
            if extra_times:
                times = sorted(set(times + [round(t, 3) for t in extra_times]))
        row = []
        for t in times:
            use_clip(kind)
            goto(t)
            p = ball_world_at(kind, t, spec)
            use_clip(kind)
            goto(t)
            if ball:
                ball.hide_render = p is None
                if p is not None:
                    ball.location = r2b(p)
            scene.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(tmp, check_existing=False)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(size[1], size[0], 4)
            bpy.data.images.remove(img)
            px = _label(px, "%s %.2fs" % (kind, t), fire=(kind == "Fire" and abs(t - spec.get("FireAt", -1)) < 1e-3))
            row.append(px)
        rows.append(row)
    cols = max(len(r) for r in rows)
    H, W = size[1], size[0]
    sheet = np.ones((H * len(rows), W * cols, 4), dtype=np.float32)
    for ri, row in enumerate(rows):
        for ci, px in enumerate(row):
            y0 = (len(rows) - 1 - ri) * H
            sheet[y0:y0 + H, ci * W:(ci + 1) * W] = px
    out = bpy.data.images.new("sheet", width=W * cols, height=H * len(rows), alpha=True)
    out.pixels = sheet.ravel()
    out.filepath_raw = path
    out.file_format = 'PNG'
    out.save()
    bpy.data.images.remove(out)
    if os.path.exists(tmp):
        os.remove(tmp)
    if ball:
        ball.hide_render = False
    return path


_FONT = {
    "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"], "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"], "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "001", "001", "001"], "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"], ".": ["000", "000", "000", "000", "010"], "s": ["000", "011", "110", "011", "110"],
    " ": ["000", "000", "000", "000", "000"],
}


def _label(px, text, fire=False):
    """burns the time into the top-left corner (tiny bitmap font); fire frames get a red border"""
    H, W, _ = px.shape
    scale = 3
    x = 4
    t = text.split(" ")[-1]
    for ch in t:
        g = _FONT.get(ch)
        if not g:
            x += 4 * scale
            continue
        for gy, rowbits in enumerate(g):
            for gx, bit in enumerate(rowbits):
                if bit == "1":
                    y0 = H - 4 - (gy + 1) * scale
                    px[y0:y0 + scale, x + gx * scale:x + (gx + 1) * scale, :3] = 0.0
                    px[y0:y0 + scale, x + gx * scale:x + (gx + 1) * scale, 3] = 1.0
        x += 4 * scale
    if fire:
        px[:3, :, :3] = (1.0, 0.1, 0.1)
        px[-3:, :, :3] = (1.0, 0.1, 0.1)
        px[:, :3, :3] = (1.0, 0.1, 0.1)
        px[:, -3:, :3] = (1.0, 0.1, 0.1)
    return px


# ---------------------------------------------------------------- one call at the end of a build
def finish(spec, out_dir, views=("game", "front", "track"), extra_times=None, per_clip=6):
    """check + export + preview sheets.  Writes out/NN.json (the clip export), and in out_dir:
    report.json and sheet_<view>.png per view.  Prints 'REPORT {json}'.  Returns the report."""
    rep = check(spec)
    rep["export"] = export(spec)
    rep["sheets"] = []
    for view in views:
        path = os.path.join(out_dir, "sheet_%s.png" % view)
        render_sheet(spec, path, view=view, per_clip=per_clip, extra_times=extra_times)
        rep["sheets"].append(path)
    with open(os.path.join(out_dir, "report.json"), "w") as f:
        json.dump(rep, f, indent=1)
    print("REPORT " + json.dumps(rep))
    return rep
