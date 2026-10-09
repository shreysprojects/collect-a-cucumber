"""vend_drop_preview.py -- strobe render of the VendingMachine drop animation (fun-builds, 2026-09-24).

A Python port of DropCF / FlapDelta from src/behaviours/client/VendingMachine.lua drawn onto the real prop
(props/build_vending_machine.py via proplib), to check in pictures that the snack starts over its stock slot,
falls in front of the shelves and behind the glass, vanishes into the cabinet and lands in the chute, and
that the DeliveryFlap opens INTO the chute. Headless, a fresh empty scene, nothing saved:

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python vend_drop_preview.py

Writes renders/VendingMachine_drop_<spot>_front.png / _three.png and renders/VendingMachine_flap_open.png.
KEEP THE CONSTANTS BELOW IN STEP WITH THE LUA if either changes.
"""
import bpy
import bmesh
import importlib.util
import math
import os
import sys
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "renders")
PROPS = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\props"


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


bpy.ops.wm.read_factory_settings(use_empty=True)
D = _load(os.path.join(PROPS, "proplib.py"), "proplib")
VM = _load(os.path.join(PROPS, "build_vending_machine.py"), "build_vending_machine")
VM.build(D)

# ---- the Lua constants (authored Roblox frame, scale 1)
PUSH_AT, FALL_AT, GRAVITY = 0.2, 0.55, 48.0
TAKE_AT, FLY_AT = 1.18, 1.3
FLAP_OPEN_AT, FLAP_OPEN_TIME, FLAP_RELEASE_AT = 1.0, 0.18, 1.45
FLAP_DAMP, FLAP_W, FLAP_SETTLE = 3.0, 2 * math.pi / 0.55, 1.6
BAY_FLOOR_Y, HIDDEN_Y, CHUTE_FLOOR_Y = 1.94, 1.62, 0.90
CHUTE_MOUTH = (0.0, 1.20, -0.98)
STOCK_FRONT_Z, FALL_FRONT_Z, GROW = -0.50, -0.60, 0.006
DROP = (0.47, 1.05, -0.36)
SPOTS = {
    "soda_low": dict(kind="Soda", X=0.350, Y=2.02, R=0.088, H=0.378),
    "cola_mid": dict(kind="Cola", X=0.724, Y=3.74, R=0.100, H=0.316),
    "chips_top": dict(kind="Chips", X=0.724, Y=4.60, W=0.242, H=0.327, D=0.168),
}
COLORS = {"Soda": "56c440", "Cola": "c82028", "Chips": "f2c13d"}


def smooth(u):
    u = max(0.0, min(1.0, u))
    return u * u * (3 - 2 * u)


def angles(rx, ry, rz):
    return Matrix.Rotation(rx, 3, 'X') @ Matrix.Rotation(ry, 3, 'Y') @ Matrix.Rotation(rz, 3, 'Z')


def item_dims(spot):
    if spot["kind"] == "Chips":
        w, h, d = spot["W"] + 2 * GROW, spot["H"] + 2 * GROW, spot["D"] + 2 * GROW
        return dict(half=h / 2, depth=d / 2, lying=w / 2, size=(w, h, d))
    r, h = spot["R"] + GROW, spot["H"] + 2 * GROW
    return dict(half=h / 2, depth=r, lying=r, r=r, h=h)


def vend(spot, roll=1):
    it = item_dims(spot)
    v = dict(spot=spot, it=it, roll=roll)
    v["Y0"] = spot["Y"] + it["half"]
    v["RestY"] = CHUTE_FLOOR_Y + it["lying"]
    v["Z0"] = STOCK_FRONT_Z + (it["depth"] - GROW) - 0.008
    v["Z1"] = FALL_FRONT_Z + it["depth"]
    v["LandT"] = FALL_AT + math.sqrt(2 * max(v["Y0"] - v["RestY"], 0) / GRAVITY)
    return v


def drop_cf(v, t):
    """(position, 3x3 rotation) in the Roblox authored frame, or None after the chute (mirrors DropCF)"""
    x0, dx, dz = v["spot"]["X"], DROP[0], DROP[2]
    if t < PUSH_AT:
        return Vector((x0, v["Y0"], v["Z0"])), Matrix.Identity(3)
    if t < FALL_AT:
        u = (t - PUSH_AT) / (FALL_AT - PUSH_AT)
        yaw = math.sin(u * math.pi * 3) * math.radians(5) * (1 - u)
        tip = math.radians(-8) * max(0.0, min(1.0, (u - 0.6) / 0.4))
        return Vector((x0, v["Y0"], v["Z0"] + (v["Z1"] - v["Z0"]) * smooth(u))), angles(tip, yaw, 0)
    if t < v["LandT"]:
        tf = t - FALL_AT
        y = max(v["Y0"] - 0.5 * GRAVITY * tf * tf, v["RestY"])
        p = max(0.0, min(1.0, (BAY_FLOOR_Y - y) / (BAY_FLOOR_Y - HIDDEN_Y)))
        roll = (1 - p) * min(tf / 0.3, 1) * 28 + p * 90
        return (Vector((x0 + (dx - x0) * p, y, v["Z1"] + (dz - v["Z1"]) * p)),
                angles(math.radians(-8) * (1 - p), 0, math.radians(roll * v["roll"])))
    if t < TAKE_AT:
        u = t - v["LandT"]
        hop = 0.07 * math.sin(math.pi * u / 0.16) if u < 0.16 else (0.022 * math.sin(math.pi * (u - 0.16) / 0.1) if u < 0.26 else 0)
        return Vector((dx, v["RestY"] + hop, dz)), angles(0, 0, math.radians(90 * v["roll"]))
    if t < FLY_AT:
        u = (t - TAKE_AT) / (FLY_AT - TAKE_AT)
        a = Vector((dx, v["RestY"], dz))
        b = Vector((dx, CHUTE_MOUTH[1], CHUTE_MOUTH[2]))
        return a.lerp(b, smooth(u)), angles(0, 0, math.radians(90 * v["roll"]) * (1 - smooth((u - 0.4) / 0.6)))
    return None


def flap_delta(t, rest=-22.0, open_=-78.0, shut=0.0):
    OPEN, SHUT = open_ - rest, shut - rest
    if t < FLAP_OPEN_AT:
        return 0.0
    if t < FLAP_OPEN_AT + FLAP_OPEN_TIME:
        u = (t - FLAP_OPEN_AT) / FLAP_OPEN_TIME
        return OPEN * (1 - (1 - u) * (1 - u))
    if t < FLAP_RELEASE_AT:
        return OPEN
    tr = t - FLAP_RELEASE_AT
    if tr >= FLAP_SETTLE:
        return 0.0
    return min(OPEN * math.exp(-FLAP_DAMP * tr) * math.cos(FLAP_W * tr), SHUT)


R2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Roblox authored -> Blender


def add_item(coll, name, v, pos, rot, color):
    bm = bmesh.new()
    it = v["it"]
    if v["spot"]["kind"] == "Chips":
        w, h, d = it["size"]
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Diagonal((w, h, d, 1.0)))
    else:
        # cylinder along the Roblox local Y
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=it["r"], radius2=it["r"],
                              depth=it["h"], matrix=Matrix.Rotation(math.radians(-90), 4, 'X'))
    for vert in bm.verts:
        vert.co = R2B @ (rot @ vert.co + pos)
    D.new_obj(name, bm, coll, color, rbx_material="SmoothPlastic")


def flap_open(delta_deg):
    """turn the DeliveryFlap mesh object about the hinge (Blender X == Roblox authored X)"""
    ob = next(o for o in bpy.data.objects if o.name.endswith("DeliveryFlap"))
    h = Vector((0.47, 0.70, 1.58))
    ob.matrix_world = Matrix.Translation(h) @ Matrix.Rotation(math.radians(delta_deg), 4, 'X') @ Matrix.Translation(-h)


os.makedirs(OUT, exist_ok=True)
report = {}
for tag, spot in SPOTS.items():
    coll_name = "Strobe_" + tag
    coll = D.coll(coll_name)
    v = vend(spot, roll=1)
    times = [0.0, 0.40, 0.55] + [FALL_AT + k * (v["LandT"] - FALL_AT) / 5 for k in range(1, 5)] + [v["LandT"] + 0.02, 1.24, 1.29]
    rows = []
    for i, t in enumerate(times):
        cf = drop_cf(v, t)
        if cf is None:
            continue
        pos, rot = cf
        add_item(coll, "%s_%02d" % (tag, i), v, pos, rot, COLORS[spot["kind"]])
        rows.append((round(t, 3), [round(c, 3) for c in pos]))
    report[tag] = {"LandT": round(v["LandT"], 3), "Y0": round(v["Y0"], 3), "RestY": round(v["RestY"], 3), "path": rows}
    flap_open(0.0)
    D.render(["VendingMachine", coll_name], os.path.join(OUT, "VendingMachine_drop_%s_front.png" % tag), size=(720, 900),
             yaw_deg=0, pitch_deg=4, margin=0.62, with_stage=False, focus=(0.4, 0.3, 3.0))
    D.render(["VendingMachine", coll_name], os.path.join(OUT, "VendingMachine_drop_%s_three.png" % tag), size=(720, 900),
             yaw_deg=-40, pitch_deg=10, margin=0.62, with_stage=False, focus=(0.4, 0.3, 3.0))
    for lc in bpy.context.view_layer.layer_collection.children:
        if lc.name == coll_name:
            lc.exclude = True

# the flap wide open with the snack lying in the chute (t = 1.1)
coll = D.coll("Strobe_open")
v = vend(SPOTS["soda_low"], roll=1)
pos, rot = drop_cf(v, 1.1)
add_item(coll, "open_can", v, pos, rot, COLORS["Soda"])
flap_open(flap_delta(1.2))
D.render(["VendingMachine", "Strobe_open"], os.path.join(OUT, "VendingMachine_flap_open.png"), size=(720, 720),
         yaw_deg=-25, pitch_deg=16, margin=0.36, with_stage=False, focus=(0.47, 0.6, 1.2))
peak = max((flap_delta(FLAP_RELEASE_AT + k / 200.0), k / 200.0) for k in range(0, 400))
print("FLAP open", flap_delta(1.2), "first swing peak", peak, "settled", flap_delta(FLAP_RELEASE_AT + FLAP_SETTLE - 0.01))
print("DROP " + repr(report))
