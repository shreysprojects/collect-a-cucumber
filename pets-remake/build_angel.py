import sys, importlib, math
sys.path.insert(0, r"C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake")
import petlib; importlib.reload(petlib)
from petlib import *
import bmesh, bpy
from mathutils import Vector, Matrix

OUT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake"
C = coll("HeavenlyAngel"); clear_collection("HeavenlyAngel")
WHITE = "f4f2ee"; CREAM = "fbfaf7"; LIGHT = "dfe2f2"; PINK = "f0b8c8"; GOLD = "ffd76b"
EYE = "222226"; GLINT = "ececf3"; GREEN = "55a446"; FLESH = "c2d38a"; SEED = "f0eeca"

# body / head / chest fluff
bm = bmesh.new(); ico(bm, (0, 0, -0.7), (1.55, 1.5, 1.35), 3); new_obj("Body", bm, C, WHITE)
bm = bmesh.new(); ico(bm, (0, 0.45, 1.45), (1.55, 1.45, 1.4), 3); new_obj("Head", bm, C, WHITE)
bm = bmesh.new(); ico(bm, (0, 1.3, -0.05), (0.72, 0.42, 0.48), 2); new_obj("ChestFluff", bm, C, CREAM)

# cat ears (outer) + pink bits (ear inners, cheeks, nose)
bm = bmesh.new(); cone(bm, (0.85, 0.3, 2.45), (1.15, 0.2, 3.5), 0.42, 0.03, 8); mirror_x(bm); new_obj("Ears", bm, C, WHITE)
bm = bmesh.new()
cone(bm, (0.86, 0.44, 2.5), (1.1, 0.34, 3.3), 0.24, 0.02, 8)
disc(bm, (0.98, 1.4, 1.22), 0.27, 0.12, (0.6, 0.8, 0.0), 10)
mirror_x(bm)
ico(bm, (0, 1.95, 1.38), (0.15, 0.1, 0.1), 1)
new_obj("Blush", bm, C, PINK)

# eyes + glints
bm = bmesh.new(); ico(bm, (0.55, 1.72, 1.65), (0.34, 0.2, 0.44), 2); mirror_x(bm); new_obj("Eyes", bm, C, EYE)
bm = bmesh.new(); ico(bm, (0.45, 1.9, 1.83), (0.1, 0.07, 0.1), 1); mirror_x(bm); new_obj("Glints", bm, C, GLINT)

# feathered angel wings + lighter inner feather layer
wing = [(0, 0), (0.3, 0.9), (1.2, 1.7), (2.6, 2.1), (3.8, 1.9), (3.3, 1.4), (3.9, 1.0), (3.2, 0.7), (3.6, 0.2), (2.8, 0.1),
        (3.0, -0.5), (2.2, -0.2), (2.2, -0.9), (1.5, -0.4), (1.3, -1.0), (0.7, -0.5), (0.5, -0.9), (0.2, -0.4)]
layer = [(0.5, 0.1), (1.3, 1.0), (2.5, 1.4), (3.2, 1.1), (2.9, 0.6), (2.5, 0.0), (2.0, -0.3), (1.4, -0.5), (0.8, -0.2)]
M = Matrix.Translation(Vector((1.15, -0.45, 0.55))) @ rot_euler(0, -35, -20)
bm = bmesh.new(); slab(bm, wing, 0.16, M); mirror_x(bm); new_obj("Wings", bm, C, CREAM)
bm = bmesh.new(); slab(bm, layer, 0.24, M); mirror_x(bm); new_obj("WingLayer", bm, C, LIGHT)

# neon gold halo + three little stars
bm = bmesh.new()
torus(bm, (0, 0.45, 3.3), 0.95, 0.12, rot_euler(-8, 0, 0), 16, 8)
for p in ((1.35, 0.2, 2.9), (-1.45, -0.1, 2.6), (0.95, -0.95, 2.25)):
    ico(bm, p, (0.15, 0.15, 0.15), 0)
new_obj("Halo", bm, C, GOLD, "Neon")

# cloud tail
bm = bmesh.new()
ico(bm, (0, -1.55, -0.5), (0.44, 0.44, 0.4), 1)
ico(bm, (0.25, -2.0, -0.2), (0.38, 0.38, 0.34), 1)
ico(bm, (-0.2, -2.3, 0.15), (0.3, 0.3, 0.28), 1)
new_obj("Tail", bm, C, CREAM)

# four paws
bm = bmesh.new()
for p in ((0.7, 0.75, -2.0), (-0.7, 0.75, -2.0), (0.75, -0.7, -2.0), (-0.75, -0.7, -2.0)):
    ico(bm, p, (0.5, 0.55, 0.36), 1)
new_obj("Legs", bm, C, WHITE)

# collar + cucumber-slice tag
bm = bmesh.new(); torus(bm, (0, 0.2, 0.35), 1.35, 0.18, rot_euler(-10, 0, 0), 16, 8); new_obj("Collar", bm, C, GREEN)
tag = (0, 1.5, -0.05)
bm = bmesh.new(); disc(bm, tag, 0.42, 0.2, (0, 1, 0), 12); new_obj("TagSkin", bm, C, GREEN)
bm = bmesh.new(); disc(bm, tag, 0.34, 0.25, (0, 1, 0), 12); new_obj("TagFlesh", bm, C, FLESH)
bm = bmesh.new()
for k in range(5):
    a = 2 * math.pi * k / 5 + math.pi / 2
    ico(bm, (tag[0] + 0.16 * math.cos(a), tag[1] + 0.13, tag[2] + 0.16 * math.sin(a)), (0.065, 0.045, 0.065), 1)
new_obj("TagSeeds", bm, C, SEED)

stats = export_luau("HeavenlyAngel", "Heavenly Angel", OUT + r"\HeavenlyAngel.lua", "PetAngel")
export_collection("HeavenlyAngel", OUT + r"\HeavenlyAngel.json")
export_fbx("HeavenlyAngel", OUT + r"\HeavenlyAngel.fbx")
render_preview("HeavenlyAngel", OUT + r"\HeavenlyAngel_preview.png", yaw_deg=35, pitch_deg=15)
bpy.ops.wm.save_as_mainfile(filepath=OUT + r"\pets.blend")
print(stats, sum(s[2] for s in stats))
