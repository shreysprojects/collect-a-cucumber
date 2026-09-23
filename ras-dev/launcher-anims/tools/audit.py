"""Audit every exported clip set (out/NN.json) on the rig, frame by frame, for things a preview
sheet hides:
  * body interpenetration: arm / hand blocks inside the UpperTorso / Head / LowerTorso boxes,
    launcher mesh vertices inside the torso / head
  * IK pops: a joint turning more than POP_DEG between two 30 fps frames (elbows / shoulders /
    wrists), except the launcher grip bone
Writes out/audit.json and prints one line per launcher.  Run in Blender (MCP or -b)."""
import bpy
import json
import math
import os
import sys
import importlib
from mathutils import Vector, Quaternion

HERE = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\ras-dev\launcher-anims"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import launcherlib as L
importlib.reload(L)

PEN_LIMIT = 0.15        # studs of penetration that start to show
SPIKE_DEG = 30.0        # a one-frame turn this big ...
SPIKE_RATIO = 3.0       # ... and this many times its neighbours' = an IK snap, not a fast swing
FLIP_DEG = 25.0         # elbow bend jumping this much and straight back within 2 frames = a flip
# realistic avatar part sizes (the preview blocks are fatter than real R15 bodies)
REAL_SIZE = {"UpperTorso": (1.7, 1.6, 0.95), "LowerTorso": (1.6, 0.4, 0.95), "Head": (1.2, 1.2, 1.2),
             "LeftUpperArm": (0.55, 0.8, 0.55), "LeftLowerArm": (0.5, 0.78, 0.5), "LeftHand": (0.45, 0.5, 0.5),
             "RightUpperArm": (0.55, 0.8, 0.55), "RightLowerArm": (0.5, 0.78, 0.5), "RightHand": (0.45, 0.5, 0.5)}
ARM_PARTS = ("LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand")
BODY_PARTS = ("UpperTorso", "Head", "LowerTorso")
POP_JOINTS = ("LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "Head", "UpperTorso", "LowerTorso")


def apply_frame(bones, row):
    r = L.rig()
    for name, v in zip(bones, row):
        pb = r.pose.bones[name]
        pb.rotation_quaternion = Quaternion((v[0], v[1], v[2], v[3]))
        pb.location = Vector((v[4], v[5], v[6]))
    L.update()


def box_points(box, half, n=3):
    pts = []
    for i in range(n):
        for j in range(n):
            for k in range(n):
                f = Vector(((i / (n - 1) - 0.5) * 2 * half.x * 0.85,
                            (j / (n - 1) - 0.5) * 2 * half.y * 0.85,
                            (k / (n - 1) - 0.5) * 2 * half.z * 0.85))
                pts.append(box @ f)
    return pts


def depth_inside(p, box, half):
    q = box.inverted() @ p
    dx, dy, dz = half.x - abs(q.x), half.y - abs(q.y), half.z - abs(q.z)
    if dx > 0 and dy > 0 and dz > 0:
        return min(dx, dy, dz)
    return 0.0


def audit(lid):
    path = os.path.join(L.OUT_DIR, "%02d.json" % lid)
    with open(path) as f:
        data = json.load(f)
    L.use_launcher(lid)
    bones = data["bones"]
    lob = L.launcher_object()
    verts = [v.co.copy() for v in lob.data.vertices]
    step = max(1, len(verts) // 250)
    verts = verts[::step]
    out = {"id": lid, "name": data["name"], "clips": {}}
    for kind, clip in data["clips"].items():
        frames = clip["frames"]
        worst_arm, worst_arm_at, worst_l, worst_l_at = 0.0, None, 0.0, None
        pops = []
        prev = None
        for fi, row in enumerate(frames):
            apply_frame(bones, row)
            boxes = {n: (b, (Vector(REAL_SIZE[n]) * 0.5 if n in REAL_SIZE else h)) for n, b, h in L.body_boxes()}
            for arm in ARM_PARTS:
                ab, ah = boxes[arm]
                for p in box_points(ab, ah):
                    for body in BODY_PARTS:
                        bb, bh = boxes[body]
                        d = depth_inside(p, bb, bh)
                        if d > worst_arm:
                            worst_arm, worst_arm_at = d, "%s in %s @%.2fs" % (arm, body, fi / data["fps"])
            mw = lob.matrix_world
            for co in verts:
                p = L.b2r(mw @ co)
                for body in ("UpperTorso", "Head"):
                    bb, bh = boxes[body]
                    d = depth_inside(p, bb, bh)
                    if d > worst_l:
                        worst_l, worst_l_at = d, "launcher in %s @%.2fs" % (body, fi / data["fps"])
            prev = row
        # IK snaps: per-joint frame-to-frame turn series
        fps = data["fps"]
        for j, name in enumerate(bones):
            if name not in POP_JOINTS:
                continue
            d = [0.0]
            for fi in range(1, len(frames)):
                qa, qb = Quaternion(frames[fi - 1][j][:4]), Quaternion(frames[fi][j][:4])
                a = math.degrees(qa.rotation_difference(qb).angle)
                d.append(min(a, 360.0 - a))
            for fi in range(1, len(d)):
                nb = [d[k] for k in (fi - 2, fi - 1, fi + 1, fi + 2) if 0 < k < len(d)]
                med = sorted(nb)[len(nb) // 2] if nb else 0.0
                if d[fi] > SPIKE_DEG and d[fi] > SPIKE_RATIO * max(med, 1.0):
                    pops.append("%s spike %.0fdeg @%.2fs" % (name, d[fi], fi / fps))
            if name.endswith("LowerArm"):
                bend = [math.degrees(Quaternion(fr[j][:4]).angle) for fr in frames]
                bend = [min(b, 360.0 - b) for b in bend]
                for fi in range(1, len(bend) - 2):
                    a1 = bend[fi] - bend[fi - 1]
                    for k in (1, 2):
                        a2 = bend[fi + k] - bend[fi + k - 1]
                        if abs(a1) > FLIP_DEG and abs(a2) > FLIP_DEG and a1 * a2 < 0:
                            pops.append("%s flip %.0f/%.0f @%.2fs" % (name, a1, a2, fi / fps))
                            break
        out["clips"][kind] = {
            "arm_in_body": round(worst_arm, 2), "arm_in_body_at": worst_arm_at,
            "launcher_in_body": round(worst_l, 2), "launcher_in_body_at": worst_l_at,
            "pops": pops[:8], "pop_count": len(pops),
        }
    return out


results = []
ids = [int(x) for x in os.environ.get("AUDIT_IDS", "").split(",") if x.strip()] or list(range(1, 31))
for lid in ids:
    try:
        r = audit(lid)
    except Exception as e:  # noqa
        r = {"id": lid, "error": str(e)}
    results.append(r)
    flags = []
    for kind, c in r.get("clips", {}).items():
        if c["arm_in_body"] > PEN_LIMIT:
            flags.append("%s arm %.2f (%s)" % (kind, c["arm_in_body"], c["arm_in_body_at"]))
        if c["launcher_in_body"] > PEN_LIMIT:
            flags.append("%s launcher %.2f (%s)" % (kind, c["launcher_in_body"], c["launcher_in_body_at"]))
        if c["pop_count"]:
            flags.append("%s pops %d: %s" % (kind, c["pop_count"], ", ".join(c["pops"][:3])))
    print("%02d %s | %s" % (lid, r.get("name", r.get("error")), "; ".join(flags) or "clean"))
with open(os.path.join(L.OUT_DIR, "audit_%s.json" % (os.environ.get("AUDIT_IDS", "all").replace(",", "-"))), "w") as f:
    json.dump(results, f, indent=1)
L.reset_pose()
