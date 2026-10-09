"""Writes meta/NN.json for the 30 launchers: launcher-local points in the GRIP PIVOT frame at
TEMPLATE scale (1x).  Pivot frame of every template: -Y = the launcher's forward (barrel / blade /
cup end), -Z = the launcher's top, +X = its right side.
    Muzzle  {pos, look, up}  where the ball leaves and the direction it leaves in
    Seat    {pos, look, up}  where the ball rests while it is visible before the shot (optional)
    Grip2   {pos}            where the LEFT hand holds (optional)
    Tip     {pos}            a contact point (the shovel blade edge ...) (optional)
    Bands   [[x,y,z], ...]   elastic band anchors (slingshots: the fork tips) (optional)
    Kind    "open" (ball visible in a cup/blade/pouch), "barrel" (ball hidden until the muzzle),
            "rail" (ball rides on top, crossbows)
Muzzle positions of barrel launchers come from the mesh (far-end centroid = the barrel axis);
the open launchers use measured cup / blade / pouch centres.  Run inside Blender (MCP):
    exec(compile(open(p).read(), p, "exec"), {"__file__": p, "__name__": "__main__"})"""
import bpy
import json
import math
import os
import sys
import importlib
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)

R = L.BALL_RADIUS / L.LAUNCHER_SCALE   # ball radius at template scale (0.444)
FWD = [0.0, -1.0, 0.0]
UP = [0.0, 0.0, -1.0]


def pts_of(lid):
    name, info = L.launcher_info(lid)
    po1 = L.cf_components(info["pivot"])
    me = bpy.data.meshes["M_" + name]
    Mi = po1.inverted()
    return np.array([list(Mi @ (L.b2r(v.co) / L.LAUNCHER_SCALE)) for v in me.vertices])


def norm(v):
    v = np.array(v, dtype=float)
    return list(v / np.linalg.norm(v))


def rnd(v, k=3):
    return [round(float(x), k) for x in v]


def barrel(lid, x=0.0, z=None, inset=0.02):
    P = pts_of(lid)
    ymin = P[:, 1].min()
    far = P[P[:, 1] < ymin + 0.12]
    zz = far[:, 2].mean() if z is None else z
    return {"pos": rnd([x, ymin + inset, zz]), "look": FWD, "up": UP}


meta = {}
# ---- open launchers: the ball rests in the blade / cup / pouch, then is thrown
meta[1] = {  # Wooden Shovel: D-handle at the grip, straight shaft, flat blade (top face = -Z side)
    "Kind": "open",
    "Seat": {"pos": [0.0, -2.42, 0.56 - R], "look": norm([0, -1, -0.55]), "up": UP},
    "Muzzle": {"pos": [0.0, -2.55, 0.56 - R], "look": norm([0, -1, -0.55]), "up": UP},
    "Tip": {"pos": [0.0, -2.95, 0.72]},
    "Grip2": {"pos": [0.0, -0.85, 0.27]},
}
meta[2] = {  # Snow Scoop: dish at the end, open to -Z
    "Kind": "open",
    "Seat": {"pos": [0.0, -1.92, -0.12 - R * 0.55], "look": norm([0, -0.6, -1]), "up": [0, 1, 0]},
    "Muzzle": {"pos": [0.0, -1.92, -0.12 - R * 0.55], "look": norm([0, -0.6, -1]), "up": [0, 1, 0]},
    "Tip": {"pos": [0.0, -2.44, 0.05]},
}
meta[3] = {  # Snowball Flipper: curved arm up to a small cup (open to -Z)
    "Kind": "open",
    "Seat": {"pos": [0.0, -2.36, -1.49 - R * 0.75], "look": norm([0, -0.7, -1]), "up": [0, 1, 0]},
    "Muzzle": {"pos": [0.0, -2.36, -1.49 - R * 0.75], "look": norm([0, -0.7, -1]), "up": [0, 1, 0]},
}
meta[4] = {  # Leather Sling: two cords from the grip ring to a pouch (open to -Z)
    "Kind": "open",
    "Seat": {"pos": [0.0, -2.58, 0.19 - R * 0.55], "look": norm([0, -1, -0.3]), "up": UP},
    "Muzzle": {"pos": [0.0, -2.58, 0.19 - R * 0.55], "look": norm([0, -1, -0.3]), "up": UP},
}
for sid in (5, 6):  # Slingshots: Y frame along -Z, fork tips at x +-0.72, pouch behind (+Y)
    meta[sid] = {
        "Kind": "open",
        "Muzzle": {"pos": [0.0, -0.05, -1.25], "look": FWD, "up": UP},
        "Seat": {"pos": [0.0, 0.62, -1.25], "look": FWD, "up": UP},
        "Bands": [[-0.66, 0.0, -1.33], [0.66, 0.0, -1.33]],
    }
meta[7] = {  # Spring Scoop: spring arm to a cup (open to -Z)
    "Kind": "open",
    "Seat": {"pos": [0.0, -1.86, -1.60 - R * 0.75], "look": norm([0, -0.7, -1]), "up": [0, 1, 0]},
    "Muzzle": {"pos": [0.0, -1.86, -1.60 - R * 0.75], "look": norm([0, -0.7, -1]), "up": [0, 1, 0]},
}
meta[9] = {  # Hand Catapult: frame + cocked arm with a cup at the top (open to -Z)
    "Kind": "open",
    "Seat": {"pos": [0.0, -1.62, -1.76 - R * 0.7], "look": norm([0, -1, -0.8]), "up": [0, 1, 0]},
    "Muzzle": {"pos": [0.0, -1.62, -1.76 - R * 0.7], "look": norm([0, -1, -0.8]), "up": [0, 1, 0]},
}
# ---- rail: the ball sits on the bolt rail in front of the string
for cid in (8, 21):
    meta[cid] = {
        "Kind": "rail",
        "Seat": {"pos": [0.0, -1.05, -1.15 - R], "look": FWD, "up": UP},
        "Muzzle": {"pos": [0.0, -1.79, -1.15 - R], "look": FWD, "up": UP},
    }
# ---- barrels: pistol grip at the pivot, barrel forward along -Y
for bid in (10, 12, 13, 14, 16, 17, 19, 20, 22, 23, 26, 27, 29):
    meta[bid] = {"Kind": "barrel", "Muzzle": barrel(bid)}
meta[11] = {"Kind": "barrel", "Muzzle": barrel(11, x=0.35, z=-0.85), "Muzzle2": barrel(11, x=-0.35, z=-0.85)}
meta[18] = {"Kind": "barrel", "Muzzle": barrel(18, z=-1.0)}      # Thunder Coil: through the coil rings
meta[28] = {"Kind": "barrel", "Muzzle": barrel(28, z=-0.99)}     # Nebula Accelerator: through the rings
meta[24] = {"Kind": "barrel", "Muzzle": barrel(24, z=-1.04)}     # Dragon Launcher: out of the mouth
meta[25] = {"Kind": "barrel", "Muzzle": barrel(25, z=-1.0)}      # Aurora Prism: between the crystals
meta[30] = {"Kind": "barrel", "Muzzle": barrel(30, z=-0.88), "Back": {"pos": [0.0, 1.35, -0.88], "look": [0, 1, 0], "up": UP}}
# pistol grips: the left hand supports under the barrel / at the front grip
for bid in (10, 11, 13, 14, 16, 19, 20, 22, 26, 27, 29, 18, 23, 24, 25, 28, 30, 17, 8, 21):
    P = pts_of(bid)
    meta[bid]["Grip2"] = {"pos": [0.0, -0.95, -0.35]}
# ---- mortar: tube tilted up-forward on a tripod base (the pivot).  The rim line was measured on
# the side view (out/inspect/sheet_13-18.png): (-0.084, -2.257) .. (-1.498, -1.40) in (y, z);
# the axis is its outward normal, 31 degrees forward of the launcher's top.
axis = np.array(norm([0.0, -0.518, -0.855]))
c_rim = np.array([0.0, -0.79, -1.83])
meta[15] = {"Kind": "barrel", "Muzzle": {"pos": rnd(c_rim), "look": rnd(axis), "up": rnd([0.0, 0.855, -0.518])},
            "Grip2": {"pos": [-0.78, -0.62, -1.25]}}

os.makedirs(L.META_DIR, exist_ok=True)
for lid, m in meta.items():
    name, _ = L.launcher_info(lid)
    m["Name"] = name
    with open(os.path.join(L.META_DIR, "%02d.json" % lid), "w") as f:
        json.dump(m, f, indent=1)
print("wrote", len(meta), "mortar axis", rnd(axis), "rim", rnd(c_rim))
