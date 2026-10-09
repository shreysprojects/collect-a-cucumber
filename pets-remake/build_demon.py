import sys, importlib, math
sys.path.insert(0, r"C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake")
import petlib; importlib.reload(petlib)
from petlib import *
import bmesh, bpy
from mathutils import Vector, Matrix

OUT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\pets-remake"
C = coll("RedDemon"); clear_collection("RedDemon")
RED = "c4403a"; NAVY = "2b2745"; NEON = "ff6a5c"; BELLY = "e58a80"; BONE = "e6e3de"; EYE = "222226"; GLINT = "ececf3"
GREEN = "55a446"; FLESH = "c2d38a"; SEED = "f0eeca"

# body / belly / head
bm = bmesh.new(); ico(bm, (0, 0, -0.9), (1.9, 1.7, 1.55), 3); new_obj("Body", bm, C, RED)
bm = bmesh.new(); ico(bm, (0, 1.15, -0.75), (1.15, 0.5, 1.0), 2); new_obj("Belly", bm, C, BELLY)
bm = bmesh.new(); ico(bm, (0, 0.45, 1.35), (1.65, 1.5, 1.45), 3); new_obj("Head", bm, C, RED)
# horns, eyes, glints, fangs (mirrored)
bm = bmesh.new(); cone(bm, (0.8, 0.35, 2.35), (1.35, 0.2, 3.55), 0.34, 0.03, 8); mirror_x(bm); new_obj("Horns", bm, C, NAVY)
bm = bmesh.new(); ico(bm, (0.55, 1.75, 1.6), (0.36, 0.22, 0.46), 2); mirror_x(bm); new_obj("Eyes", bm, C, EYE)
bm = bmesh.new(); ico(bm, (0.45, 1.95, 1.78), (0.11, 0.08, 0.11), 1); mirror_x(bm); new_obj("Glints", bm, C, GLINT)
bm = bmesh.new(); cone(bm, (0.38, 1.72, 1.02), (0.38, 1.78, 0.6), 0.13, 0.02, 6); mirror_x(bm); new_obj("Fangs", bm, C, BONE)
# bat wings + neon ember membrane (thicker so it shows on both faces)
wing = [(0, 0.0), (0.5, 0.9), (1.4, 1.6), (2.6, 1.9), (3.6, 1.6), (3.1, 0.9), (3.7, 0.2), (3.0, -0.1), (3.2, -0.9), (2.3, -0.6), (1.9, -1.3), (1.1, -0.7), (0.4, -0.9)]
ember = [(0.7, 0.15), (1.5, 1.0), (2.5, 1.35), (3.0, 0.9), (2.7, 0.4), (2.9, -0.4), (2.2, -0.2), (1.6, -0.8), (1.0, -0.4)]
M = Matrix.Translation(Vector((1.35, -0.55, 0.4))) @ rot_euler(0, -25, -28)
bm = bmesh.new(); slab(bm, wing, 0.16, M); mirror_x(bm); new_obj("Wings", bm, C, NAVY)
bm = bmesh.new(); slab(bm, ember, 0.24, M); mirror_x(bm); new_obj("WingEmber", bm, C, NEON, "Neon")
# tail + spade tip
pts = [(0, -1.4, -1.3), (0, -2.3, -1.7), (0, -3.1, -1.4), (0, -3.5, -0.6), (0, -3.4, 0.3)]
bm = bmesh.new(); tube(bm, pts, [0.32, 0.28, 0.22, 0.16, 0.1], 8); new_obj("Tail", bm, C, NAVY)
spade = [(0, -0.1), (0.5, 0.45), (0, 1.25), (-0.5, 0.45)]
M2 = Matrix.Translation(Vector((0, -3.4, 0.2))) @ rot_euler(-15, 0, 0)
bm = bmesh.new(); slab(bm, spade, 0.18, M2); new_obj("TailTip", bm, C, RED)
# feet
bm = bmesh.new(); ico(bm, (0.8, 0.35, -2.55), (0.6, 0.72, 0.36), 1); mirror_x(bm); new_obj("Feet", bm, C, NAVY)
# collar + cucumber-slice tag (house signature)
bm = bmesh.new(); torus(bm, (0, 0.15, 0.35), 1.5, 0.2, rot_euler(-10, 0, 0), 16, 8); new_obj("Collar", bm, C, GREEN)
bm = bmesh.new(); disc(bm, (0, 1.6, -0.05), 0.46, 0.22, (0, 1, 0), 12); new_obj("TagSkin", bm, C, GREEN)
bm = bmesh.new(); disc(bm, (0, 1.6, -0.05), 0.37, 0.27, (0, 1, 0), 12); new_obj("TagFlesh", bm, C, FLESH)
bm = bmesh.new()
for k in range(5):
    a = 2 * math.pi * k / 5 + math.pi / 2
    ico(bm, (0.17 * math.cos(a), 1.74, -0.05 + 0.17 * math.sin(a)), (0.07, 0.05, 0.07), 1)
new_obj("TagSeeds", bm, C, SEED)

stats = export_luau("RedDemon", "Red Demon", OUT + r"\RedDemon.lua", "PetDemon")
export_collection("RedDemon", OUT + r"\RedDemon.json")
export_fbx("RedDemon", OUT + r"\RedDemon.fbx")
render_preview("RedDemon", OUT + r"\RedDemon_preview.png", yaw_deg=35, pitch_deg=15)
bpy.ops.wm.save_as_mainfile(filepath=OUT + r"\pets.blend")
print(stats, sum(s[2] for s in stats))
