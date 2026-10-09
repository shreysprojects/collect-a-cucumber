"""Stone wall - the heavy upgrade: a battered plinth, a buttressed running-bond ashlar
face with deep recessed mortar joints, a corbelled iron parapet under a stone coping and a
chunky crenellated crown that tiles at x = +/-4."""
import bmesh
from mathutils import Matrix

COLLECTION = "StoneWall"

NOTES = (
    "Tiling wall segment, exactly 8 studs wide (x -4.00 .. 4.00), 8.00 tall, 2.64 deep "
    "(y -1.02 .. +1.62). Faces +Y: the batter, the buttress, the moss and every projecting "
    "ledge are on the +Y (attacker) side; the -Y side is a flat back with the same courses. "
    "WHY IT IS DEEP: this prop has to out-read the wooden wall as the upgrade, and both are "
    "8 x 8. Mass is the only axis left, so it is 2.64 deep against the timber wall's 1.36 - "
    "a battered plinth 2.43 deep at the ground, a face that leans back 0.48 over the four "
    "courses (1.16 -> 0.68), a centre buttress whose toe reaches y 1.62 and a cap that "
    "corbels back OUT to 1.02. Face-on you read the crown and the buttress; from any angle "
    "off-axis the sloped base and the overhanging cap show in the outline. "
    "VALUE IS BUILT, NOT PAINTED: the three stone hexes only span 30 render levels under "
    "this key/fill rig (the +Y face is lit by the fill alone), so every dark in this prop is "
    "a SHADOW, not a colour. Three sources: (1) every block is inset 0.07 per side, so each "
    "joint is a 0.14-wide slot 0.28..0.76 deep whose mouth faces +Y - the key sun is behind "
    "the wall and the fill comes in at 26 deg, so nothing reaches the bottom of a joint and "
    "every block is outlined in near-black; (2) the cap overhangs the top course by 0.34 and "
    "lays a dark band across it, which is what makes the light crown read against the sky; "
    "(3) the buttress stands 0.14..0.30 proud and throws a hard vertical shadow to its LEFT "
    "(the fill comes from the front-right), breaking the horizontal courses. "
    "TILING CONTRACT: the crenellation period is 4 studs and a MERLON is centred on the "
    "seam - each tile carries a 1.20-wide half merlon at x -4..-2.8 and 2.8..4, so two "
    "copies butt into one 2.40-wide merlon and the joint is buried inside solid stone; the "
    "crenels (1.60) sit wholly inside a tile at |x| 1.2..2.8. Merlons are wider than the "
    "gaps on purpose - a solid crown reads heavier than a comb. The masonry is a real "
    "running bond: 3-block courses (joint ON the seam, so the seam is just another 0.14 "
    "mortar joint) alternate with 4-block courses that carry a full block ACROSS the seam "
    "via a 1.26 half block at each end. The bond colours are FORCED, not chosen: requiring "
    "every block to differ from its neighbours, from the blocks it overlaps below and from "
    "the block it meets across the seam leaves exactly one solution, L/D/M over D/M/L/D, "
    "repeating every two courses. The plinth, the buttress and the coping are all full-width "
    "single prisms, so they weld tile-to-tile with no joint at all. "
    "ENVELOPE: stone_block's corner jitter is hard-clamped per block (_clamp) to x = +/-4, "
    "z >= 0 and z <= 8. Blocks that straddle the seam are clamped with snap = 0.16, which "
    "also pulls their chamfer back out flush to x = +/-4 - without it the 0.07-0.08 bevel "
    "would cut a groove down the middle of a block that two tiles share and the pair would "
    "read as two walls. Every other block, and all the moss, uses snap = 0 so their 0.07 "
    "joint insets are never flattened onto the seam. Nothing dips below z = 0. "
    "MortarCore is a hidden slab (y -0.57 .. 0.40, z 1.24 .. 6.12) that backs every joint "
    "slot so no daylight comes through the jittered gaps; it is only ever seen at the bottom "
    "of a shadowed slot, so it is the darkest thing in the palette (metal dark). "
    "The parapet band is IRON on purpose - a 3-colour running bond forces all three stone "
    "values into every course, so a stone-valued band would have sat on its own value - and "
    "it ties the wall to the turret's palette. It is built matte (metallic 0, roughness 0.9) "
    "and roofed by the stone coping: an earlier metallic band blew a specular highlight off "
    "its exposed top face and rendered as a pure white (255) stripe across the crenels. The "
    "coping now covers that face completely, so the crenel floor is stone, not iron. "
    "The buttress is MID stone. It overlaps a same-value block only on its LEFT flank in "
    "courses 1 and 3, which is exactly the side its own cast shadow falls on. "
    "Moss is four patches in two clumps plus one at the base, each 1.3..2.8 studs across and "
    "standing 0.17 proud - sized to read as growth rather than the green slivers a scatter "
    "of small lumps gave. Three of the five sit on LIGHT blocks, where the green also "
    "separates in value. "
    "No moving parts, no pivots - this prop is static, so no PIVOTS / STATES are exported. "
    "Tri note: MossPatches are D.rock at the library default subdiv=1, the bare 20-face "
    "icosahedron (5 lumps = 100 tris of the 956 total)."
)

# ---------------------------------------------------------------- palette
LIGHT = "b9b3a7"    # stone light
MID = "8f8a80"      # stone mid
DARK = "6b675f"     # stone dark
IRON = "3b4350"     # metal dark
MOSS = "5f8f4a"     # moss accent

# ---------------------------------------------------------------- envelope (studs)
X_END = 4.00        # tiling planes - NOTHING may cross these
Y_BACK = -0.85      # flat back face of every course
Y_FRONT = (1.16, 1.00, 0.84, 0.68)   # battered course fronts, bottom -> top (0.16 per step)
Y_CORE_B, Y_CORE_F = -0.57, 0.40     # hidden slab behind the joint slots
Y_MERLON = 0.84     # merlons are inset 0.08 from the coping's top face
JOINT = 0.07        # mortar inset per block side -> 0.14 joints, the wall's only real darks
Z_PLINTH = 1.30     # top of the plinth = bed of course 0
COURSE_H = 1.20
Z_BAND0, Z_BAND1 = 6.10, 6.45        # iron parapet band
Z_COPE1 = 6.75                       # top of the coping = crenel floor
Z_TOP = 8.00                         # merlon tops
SNAP = 0.16         # >= max chamfer (0.08) + max jitter (0.04): welds the tiling faces
PROUD = 0.17        # how far a moss patch stands off the face it grows on

# Cross-sections are given as (y, z) and extruded along X by prism(), so the faces on the
# tiling planes stay dead flat and un-chamfered.  Same axis swap defenselib.wedge() uses.
_MX = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

# Battered base: 2.43 deep on the ground, splaying back to meet the course-0 face and
# leaving a 0.14 ledge in front of it.
PLINTH = [(-0.95, 0.00), (1.48, 0.00), (1.48, 0.30), (1.30, 0.95),
          (1.30, 1.30), (-0.85, 1.30), (-0.85, 0.40), (-0.95, 0.30)]

# Centre buttress, x -0.85..0.85.  STEPPED, not smoothly battered: three stages, each
# ending in a sloped weathering shelf, dying into the wall under the corbel at z 6.10.
# The first version was a single smooth prism in MID stone, which rendered as a flat
# featureless plank laid over the courses - same value as the blocks it crossed and no
# facet breaks to catch the light.  Steps + shelves give it a silhouette; DARK gives it
# the value separation.  It stands 0.56-0.72 proud of the course faces (1.16 -> 0.68) the
# whole way up, so it always throws a hard vertical shadow.
BUT_HALF = 0.85
BUTTRESS = [(0.20, 0.00), (1.78, 0.00), (1.78, 1.24),     # base spur, proud of the plinth toe (1.48)
            (1.58, 1.56), (1.58, 3.30),                    # shelf -> stage 1
            (1.38, 3.62), (1.38, 5.00),                    # shelf -> stage 2
            (1.20, 5.28), (1.20, 5.92),                    # shelf -> stage 3
            (0.72, 6.10), (0.20, 6.10)]                    # top weathering, under the corbel

# Corbelled iron band: flush with the top course at its underside, kicking out to 0.94.
BAND = [(-0.85, 6.10), (0.68, 6.10), (0.94, 6.30), (0.94, 6.45),
        (-0.94, 6.45), (-0.94, 6.30)]

# Stone coping over the band - it roofs the iron and is the floor of every crenel.
COPING = [(-1.02, 6.45), (1.02, 6.45), (1.02, 6.64), (0.92, 6.75),
          (-0.92, 6.75), (-1.02, 6.64)]

# ---------------------------------------------------------------- running bond
THIRD = 8.0 / 3.0                                        # 2.667 - the full block length
A_EDGES = (-4.0, -THIRD / 2.0, THIRD / 2.0, 4.0)         # 3 blocks, joint on the seam
B_EDGES = (-4.0, -THIRD, 0.0, THIRD, 4.0)                # 4 blocks, block across the seam

# (bed z, x edges, colour per block).  This is the ONLY assignment that satisfies all three
# rules at once - differ from your neighbour, from what you overlap below, and from what you
# meet across the seam - so the bond repeats every two courses:
#   course 0/2  L | D | M            (seam pair M|L)
#   course 1/3  D | M | L | D        (seam pair D|D - one block split over two tiles)
COURSES = (
    (1.30, A_EDGES, ("L", "D", "M")),
    (2.50, B_EDGES, ("D", "M", "L", "D")),
    (3.70, A_EDGES, ("L", "D", "M")),
    (4.90, B_EDGES, ("D", "M", "L", "D")),
)

# merlons: 1.20-wide halves on the seam + a 2.40-wide centre -> 4-stud period, 1.60 crenels
MERLONS = ((-4.00, -2.80), (-1.20, 1.20), (2.80, 4.00))

# moss: (x, z, face_y it grows on, radius, (sx, sy, sz), seed)
MOSS_LUMPS = (
    (-2.60, 1.55, 1.16, 0.40, (2.40, 0.50, 1.00), 11),   # bottom-left clump, on course 0
    (-1.90, 1.30, 1.16, 0.32, (2.20, 0.50, 0.90), 12),   #   "     spilling over the plinth
    (1.95, 3.15, 1.00, 0.34, (2.00, 0.50, 1.05), 13),    # mid-right clump, on course 1
    (1.35, 2.90, 1.00, 0.26, (1.90, 0.48, 0.85), 14),    #   "     creeping up the buttress
    (3.15, 0.75, 1.355, 0.30, (1.90, 0.45, 0.90), 15),   # damp patch on the plinth batter
)


def _clamp(verts, snap=0.0, x_lim=X_END, z_min=0.0, z_max=Z_TOP):
    """Hard-guarantee the envelope AFTER stone_block's corner jitter: nothing may cross a
    tiling plane, sink under the floor or push past the 8-stud height.

    `snap` additionally pulls any vertex within that distance of a tiling plane flat ONTO
    it.  Only the blocks that STRADDLE the seam get it: their chamfer (0.07-0.08) plus
    jitter (0.04) would otherwise leave a groove down the middle of a block two tiles share,
    so butted copies would read as two walls.  Everything else - the blocks whose 0.07 joint
    inset must survive, and all the moss - is clamped with snap = 0."""
    for v in verts:
        if v.co.x > x_lim - snap:
            v.co.x = x_lim
        elif v.co.x < -x_lim + snap:
            v.co.x = -x_lim
        if v.co.z > z_max:
            v.co.z = z_max
        elif v.co.z < z_min:
            v.co.z = z_min
    return verts


def build(D):
    """D is the imported defenselib module. Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # -------------------------------------------------- 1. battered plinth (x-extruded)
    bm = bmesh.new()
    D.prism(bm, PLINTH, -X_END, X_END, matrix=_MX)
    D.new_obj("Plinth", bm, c, DARK, rbx_material="Slate", roughness=0.88)

    # -------------------------------------------------- 2. hidden core behind the joints
    bm = bmesh.new()
    D.box(bm, (-X_END, Y_CORE_B, Z_PLINTH - 0.06), (X_END, Y_CORE_F, Z_BAND0 + 0.02))
    D.new_obj("MortarCore", bm, c, IRON, rbx_material="Concrete", roughness=0.95)

    # -------------------------------------------------- 3. ashlar courses, running bond
    # Blocks are inset JOINT per side (except where they straddle the seam) so every joint
    # is a real slot, not a chamfer crease - that slot is where this wall's darks live.
    packs = {"L": [], "M": [], "D": []}
    for ci, (bed, edges, cols) in enumerate(COURSES):
        seam_block = (len(edges) == 5)          # a B course: end halves cross x = +/-4
        n = len(edges) - 1
        for bi in range(n):
            x0 = edges[bi] + (0.0 if (seam_block and bi == 0) else JOINT)
            x1 = edges[bi + 1] - (0.0 if (seam_block and bi == n - 1) else JOINT)
            snap = SNAP if (seam_block and bi in (0, n - 1)) else 0.0
            packs[cols[bi]].append((x0, x1, bed + JOINT, bed + COURSE_H - JOINT,
                                    Y_FRONT[ci], snap, 40 + 10 * ci + bi))
    for key, name, hexcol in (("L", "BlocksLight", LIGHT),
                              ("M", "BlocksMid", MID),
                              ("D", "BlocksDark", DARK)):
        bm = bmesh.new()
        for x0, x1, z0, z1, y_face, snap, seed in packs[key]:
            _clamp(D.stone_block(bm, (x0, Y_BACK, z0), (x1, y_face, z1),
                                 seed=seed, jitter=0.04, bevel=0.07), snap=snap)
        D.new_obj(name, bm, c, hexcol, rbx_material="Slate", roughness=0.85)

    # -------------------------------------------------- 4. centre buttress
    bm = bmesh.new()
    D.prism(bm, BUTTRESS, -BUT_HALF, BUT_HALF, matrix=_MX)
    D.new_obj("Buttress", bm, c, DARK, rbx_material="Slate", roughness=0.88)

    # -------------------------------------------------- 5. corbelled iron parapet band
    # matte on purpose: metallic + low roughness mirrored the sun and rendered white.
    bm = bmesh.new()
    D.prism(bm, BAND, -X_END, X_END, matrix=_MX)
    D.new_obj("ParapetBand", bm, c, IRON, rbx_material="Metal", metallic=0.0, roughness=0.90)

    # -------------------------------------------------- 6. stone coping / crenel floor
    bm = bmesh.new()
    D.prism(bm, COPING, -X_END, X_END, matrix=_MX)
    D.new_obj("Coping", bm, c, MID, rbx_material="Slate", roughness=0.85)

    # -------------------------------------------------- 7. crenellations
    bm = bmesh.new()
    for i, (x0, x1) in enumerate(MERLONS):
        snap = 0.0 if (x0 > -X_END and x1 < X_END) else SNAP
        _clamp(D.stone_block(bm, (x0, -Y_MERLON, Z_COPE1), (x1, Y_MERLON, Z_TOP),
                             seed=81 + i, jitter=0.04, bevel=0.08), snap=snap)
    D.new_obj("Merlons", bm, c, LIGHT, rbx_material="Slate", roughness=0.85)

    # -------------------------------------------------- 8. weathering: moss
    bm = bmesh.new()
    for x, z, y_face, r, s, seed in MOSS_LUMPS:
        # rock() jitters each unit vertex by +/-0.28, so its half-depth is at most
        # r * sy * 1.28; sit the lump so exactly PROUD of it stands off the face.
        y = y_face + PROUD - r * s[1] * 1.28
        _clamp(D.rock(bm, (x, y, z), r, seed=seed, jitter=0.28, scale=s))
    D.new_obj("MossPatches", bm, c, MOSS, rbx_material="Grass", roughness=0.98)

    return c


# ---------------------------------------------------------------------------------------
# PART LIST - name / colour role / hex / build / approx tris
#   (44 per beveled_box or stone_block, 12 per box, 4n-4 per n-gon prism,
#    20 per D.rock at subdiv=1 - the bare icosahedron)
#
#   Plinth        stone dark    6b675f  8-gon x-prism, 2.43 -> 2.01 deep .......  28
#   MortarCore    metal dark    3b4350  1 hidden box behind every joint .......  12
#   BlocksLight   stone light   b9b3a7  4 stone_blocks ........................ 176
#   BlocksMid     stone mid     8f8a80  4 stone_blocks ........................ 176
#   BlocksDark    stone dark    6b675f  6 stone_blocks ........................ 264
#   Buttress      stone mid     8f8a80  8-gon x-prism, x -0.75..0.75 ..........  28
#   ParapetBand   metal dark    3b4350  6-gon x-prism corbel [Metal, matte] ...  20
#   Coping        stone mid     8f8a80  6-gon x-prism, roofs the iron .........  20
#   Merlons       stone light   b9b3a7  2 half merlons on the seam + 1 centre .. 132
#   MossPatches   moss          5f8f4a  5 flattened rocks [Grass] ............. 100
#
#   10 parts, 956 tris of a 1000 budget.
#   Bounding box  x -4.00 .. 4.00  |  y -1.02 .. 1.62  |  z 0.00 .. 8.00
#                 = 8.00 wide x 2.64 deep x 8.00 tall.   min_z = 0.000.
#   (y +1.62 is the buttress toe, -1.02 the coping's back lip; the widest MASONRY is the
#    plinth at -0.95 .. 1.48.  Worst case after jitter: blocks |y| <= 1.20, moss y <= 1.53.)
#
# ELEVATION (bottom to top), every step a real ledge:
#   0.00 plinth, battered 1.48 -> 1.30 ....................... 1.30 tall
#   1.30 four ashlar courses, fronts 1.16 / 1.00 / 0.84 / 0.68  1.20 each, blocks 1.06
#   6.10 iron corbel band, kicks out to 0.94 ................. 0.35
#   6.45 stone coping, kicks out to 1.02, top = crenel floor .. 0.30
#   6.75 merlons ............................................. 1.25 tall, 2.40 wide
#   The buttress runs 0.00 -> 6.10 under the centre merlon, always 0.14..0.30 proud.
#
# WHERE THE DARKS COME FROM (the +Y face never sees the key sun - it is fill-lit only, so
# a painted value ladder spans barely 30 render levels and geometry has to do the work):
#   every block outlined by a 0.14-wide slot, 0.28 deep at the top course and 0.76 at the
#   bottom | a 0.34 cap overhang shading most of course 3 | the buttress's vertical shadow
#   on its left flank | the plinth ledge and every batter step reading as a dark line.
#
# BOND / VALUE AUDIT - each block against its neighbour, what it overlaps below, and what
# it meets across the seam.  Nominal edges (before the 0.07 joint inset):
#   c0 [-4,-1.33]L [-1.33,1.33]D [1.33,4]M            seam M|L
#   c1 [-4,-2.67]D [-2.67,0]M [0,2.67]L [2.67,4]D     seam D|D (one block, two tiles)
#   c2 = c0, c3 = c1.
#   Vertical: c1's M spans c0's L and D; c1's L spans c0's D and M; c2's L spans c1's D and
#   M; c2's D spans c1's M and L; c2's M spans c1's L and D.  No repeat anywhere.
#   The one same-value contact left is the DARK plinth under c0's DARK centre block: the
#   buttress covers x -0.75..0.75 of it, leaving two 0.51-wide strips, and the left strip is
#   under the bottom-left moss clump.
#
# STACKING - nothing floats, nothing is unsupported: ground -> plinth 1.30 -> four courses
#   -> band 6.10 -> coping 6.45 -> merlons 6.75 .. 8.00.  Moss is embedded 0.26..0.34 into
#   the face it grows on even in its thinnest jitter case, so no patch can float off.
# ---------------------------------------------------------------------------------------
