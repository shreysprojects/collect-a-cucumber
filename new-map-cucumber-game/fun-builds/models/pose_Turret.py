"""pose_Turret.py (DefTurret): build the Turret, pose the rig like DefenceService.PoseTurret (yaw Head*, pitch Barrel* about the
HeadTrunnion X axis, then yaw) and render the pose shots into FB/models/renders/Turret_pose_*.png."""
import bpy, sys, os, math, importlib.util
from mathutils import Matrix, Vector

FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
GAMES = r"C:\Users\shrey\OneDrive\Documents\RobloxGames"
OUT = os.path.join(FB, "models", "renders")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
only = set(args)


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
D = _load(os.path.join(GAMES, "defenses", "defenselib.py"), "defenselib")
D.bpy = bpy
P = _load(os.path.join(FB, "models", "primlib.py"), "primlib")
B = _load(os.path.join(FB, "models", "build_Turret.py"), "build_Turret")
info = B.build(D, P)
ty = [p for p in info["parts"] if p["name"] == "HeadTrunnion"][0]["cf"][1]


def aim_focus(yaw, rx, ry, rz):
    """Roblox authored point (rest pose, yaw 0) -> Blender point after the head yaws by `yaw`."""
    a = math.radians(yaw)
    bx, by = rx, -rz
    return (bx * math.cos(a) - by * math.sin(a), bx * math.sin(a) + by * math.cos(a), ry)


# tag, head yaw, barrel pitch, camera yaw, camera pitch, margin, focus
poses = [
    ("pose_up", 35, 45, 30, 20, 1.12, None),
    ("pose_down", -70, -25, -40, 14, 1.12, None),
    ("pose_side", 90, 20, 0, 10, 1.12, None),
    # the Spawnling-bash pose: MinPitch with the barrels over a lip corner, seen side-on, close
    ("pose_bash", 22.5, -25, 67.5, 6, 0.5, aim_focus(22.5, 0.0, 2.3, -2.3)),
]
coll = bpy.data.collections["Turret"]
for tag, yaw, pitch, cam_yaw, cam_pitch, margin, focus in poses:
    if only and tag not in only:
        continue
    Y = Matrix.Rotation(math.radians(yaw), 4, 'Z')
    T = Matrix.Translation(Vector((0, 0, ty)))
    Pm = T @ Matrix.Rotation(math.radians(pitch), 4, 'X') @ T.inverted()
    for o in coll.objects:
        n = o.name.split(".", 1)[1]
        if n.startswith("Head"):
            o.matrix_world = Y
        elif n.startswith("Barrel"):
            o.matrix_world = Y @ Pm
        else:
            o.matrix_world = Matrix.Identity(4)
    D.render(["Turret"], os.path.join(OUT, "Turret_%s.png" % tag), size=(720, 600), yaw_deg=cam_yaw,
             pitch_deg=cam_pitch, margin=margin, with_stage=False, show_ref=False, focus=focus)
print("POSED OK")
