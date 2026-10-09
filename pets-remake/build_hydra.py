import sys, importlib, math
sys.path.insert(0, r"C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake")
import petlib; importlib.reload(petlib)
from petlib import *
import bmesh, bpy
from mathutils import Vector, Matrix

OUT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake"
C = coll("PurpleHydra"); clear_collection("PurpleHydra")
PURPLE = "5a3f9a"; DARK = "3f2c73"; BELLY = "b79ee8"; NEON = "c894ff"; EYE = "222226"; GLINT = "ececf3"
GREEN = "55a446"; FLESH = "c2d38a"; SEED = "f0eeca"

# body / belly / spots
bm = bmesh.new(); ico(bm, (0, 0, -0.8), (2.1, 2.2, 1.6), 3); new_obj("Body", bm, C, PURPLE)
bm = bmesh.new(); ico(bm, (0, 1.45, -1.0), (1.3, 0.55, 1.05), 2); new_obj("Belly", bm, C, BELLY)
bm = bmesh.new()
for p in ((1.35, -0.4, 0.25), (-1.4, -0.6, 0.15), (0.9, -1.4, 0.5), (-0.7, -1.5, 0.45), (1.7, 0.6, -0.9), (-1.75, 0.4, -1.0)):
    ico(bm, p, (0.34, 0.3, 0.3), 1)
new_obj("Spots", bm, C, BELLY)

# three necks + heads (explicit left/right so nothing is duplicated)
heads = [((0, 1.35, 2.85), 1.08), ((-2.05, 1.0, 2.3), 0.92), ((2.05, 1.0, 2.3), 0.92)]
necks = [(((0, 0.7, 0.3), (0, 1.15, 2.4)), (0.66, 0.52)),
         (((-0.9, 0.35, 0.2), (-1.85, 0.8, 2.0)), (0.6, 0.46)),
         (((0.9, 0.35, 0.2), (1.85, 0.8, 2.0)), (0.6, 0.46))]
bm = bmesh.new()
for (a, b), (r0, r1) in necks:
    tube(bm, [a, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2), b], [r0, (r0 + r1) / 2, r1], 8)
new_obj("Necks", bm, C, PURPLE)
bm = bmesh.new()
for (h, r) in heads:
    ico(bm, h, (r, r * 0.95, r * 0.92), 3)
new_obj("Heads", bm, C, PURPLE)
# horn nubs, eyes, glints per head
bm = bmesh.new()
for (h, r) in heads:
    for sx in (-1, 1):
        cone(bm, (h[0] + sx * 0.42 * r, h[1] - 0.1 * r, h[2] + 0.75 * r), (h[0] + sx * 0.7 * r, h[1] - 0.2 * r, h[2] + 1.35 * r), 0.2 * r, 0.03, 7)
new_obj("Horns", bm, C, DARK)
bm = bmesh.new()
for (h, r) in heads:
    for sx in (-1, 1):
        ico(bm, (h[0] + sx * 0.36 * r, h[1] + 0.85 * r, h[2] + 0.12 * r), (0.3 * r, 0.18 * r, 0.36 * r), 2)
new_obj("Eyes", bm, C, EYE)
bm = bmesh.new()
for (h, r) in heads:
    for sx in (-1, 1):
        ico(bm, (h[0] + sx * 0.3 * r, h[1] + 1.0 * r, h[2] + 0.26 * r), (0.09 * r, 0.06 * r, 0.09 * r), 1)
new_obj("Glints", bm, C, GLINT)

# neon back crest: sawtooth slab running from the tail root up to the centre neck
crest = [(0, -0.4), (0, 0), (0.4, 0.9), (0.8, 0.05), (1.3, 1.05), (1.8, 0.1), (2.3, 1.05), (2.8, 0.15), (3.2, 0.8), (3.5, 0.2), (3.5, -0.4)]
Mc = Matrix.Translation(Vector((0, -2.0, 0.25))) @ Matrix.Rotation(math.radians(14), 4, 'X') @ Matrix.Rotation(math.radians(90), 4, 'Z')
bm = bmesh.new(); slab(bm, crest, 0.2, Mc); new_obj("Crest", bm, C, NEON, "Neon")

# wings + neon glow inset
wing = [(0, 0.0), (0.55, 1.0), (1.6, 1.8), (3.0, 2.2), (4.1, 1.8), (3.6, 1.0), (4.3, 0.2), (3.5, -0.1), (3.7, -1.0), (2.7, -0.7), (2.2, -1.5), (1.3, -0.8), (0.45, -1.0)]
glow = [(0.8, 0.2), (1.7, 1.15), (2.9, 1.55), (3.45, 1.0), (3.1, 0.45), (3.35, -0.45), (2.55, -0.25), (1.85, -0.95), (1.15, -0.45)]
M = Matrix.Translation(Vector((1.55, -0.7, 0.35))) @ rot_euler(0, -22, -30)
bm = bmesh.new(); slab(bm, wing, 0.16, M); mirror_x(bm); new_obj("Wings", bm, C, DARK)
bm = bmesh.new(); slab(bm, glow, 0.24, M); mirror_x(bm); new_obj("WingGlow", bm, C, NEON, "Neon")

# tail + neon leaf fin
pts = [(0, -2.1, -1.2), (0, -3.2, -1.55), (0, -4.0, -1.1), (0, -4.45, -0.35)]
bm = bmesh.new(); tube(bm, pts, [0.48, 0.4, 0.28, 0.14], 8); new_obj("Tail", bm, C, PURPLE)
leaf = [(0, -0.2), (-0.55, 0.5), (-0.25, 1.5), (0.35, 0.65)]
Mt = Matrix.Translation(Vector((0, -4.35, -0.3))) @ Matrix.Rotation(math.radians(90), 4, 'Z')
bm = bmesh.new(); slab(bm, leaf, 0.18, Mt); new_obj("TailFin", bm, C, NEON, "Neon")

# four stubby legs
bm = bmesh.new()
for p in ((1.2, 0.95, -2.3), (-1.2, 0.95, -2.3), (1.3, -1.05, -2.3), (-1.3, -1.05, -2.3)):
    ico(bm, p, (0.62, 0.7, 0.4), 1)
new_obj("Legs", bm, C, DARK)

# collar on the centre neck + cucumber-slice tag
bm = bmesh.new(); torus(bm, (0, 0.92, 1.35), 0.78, 0.16, rot_euler(-14, 0, 0), 16, 8); new_obj("Collar", bm, C, GREEN)
tag = (0, 1.72, 1.2)
bm = bmesh.new(); disc(bm, tag, 0.42, 0.2, (0, 1, 0), 12); new_obj("TagSkin", bm, C, GREEN)
bm = bmesh.new(); disc(bm, tag, 0.34, 0.25, (0, 1, 0), 12); new_obj("TagFlesh", bm, C, FLESH)
bm = bmesh.new()
for k in range(5):
    a = 2 * math.pi * k / 5 + math.pi / 2
    ico(bm, (tag[0] + 0.16 * math.cos(a), tag[1] + 0.13, tag[2] + 0.16 * math.sin(a)), (0.065, 0.045, 0.065), 1)
new_obj("TagSeeds", bm, C, SEED)

stats = export_luau("PurpleHydra", "Purple Hydra", OUT + r"\PurpleHydra.lua", "PetHydra")
export_collection("PurpleHydra", OUT + r"\PurpleHydra.json")
export_fbx("PurpleHydra", OUT + r"\PurpleHydra.fbx")
render_preview("PurpleHydra", OUT + r"\PurpleHydra_preview.png", yaw_deg=35, pitch_deg=15)
bpy.ops.wm.save_as_mainfile(filepath=OUT + r"\pets.blend")
print(stats, sum(s[2] for s in stats))
