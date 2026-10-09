"""Wooden wall - the cheap early-game barricade: an 8 x 8 hand-built timber palisade."""
import bmesh
from mathutils import Matrix

COLLECTION = "WoodenWall"
NOTES = (
    "TILING: every full-width member (Frame back-slab + ground sill, both front rails, both "
    "back rails, both iron bands) runs from x = -4.000 to x = +4.000 and stops there, so two "
    "copies placed 8 studs apart butt with no gap and no overlap. The pickets themselves stop "
    "at x = +/-3.92, which makes the tile-seam gap 0.16 studs - inside the 0.16..0.20 range of "
    "the interior plank gaps - so the seam vanishes into the plank rhythm. Picket pitch is "
    "exactly 1.000 stud (8 per tile), so the sharpened crest repeats with a period dividing 8. "
    "SEAM: the bevelled TIMBER members (sill, front rails, back rails) meet tile-to-tile as a "
    "0.18-wide 0.09-deep chamfer groove. That is deliberate and correct - it reads as the butt "
    "joint between two 8-stud beams. The IRON BANDS are plain D.box, no bevel, exactly so they "
    "do NOT get that groove: banding is flat stock and a notch chipped out of it every 8 studs "
    "reads as a defect, not a joint. Their end faces are coplanar at x = +/-4 and the band runs "
    "unbroken down a whole wall. "
    "BOX: x -4.00..+4.00, y -0.68..+0.68 (1.36 deep, centred on y = 0), z 0.000..8.000. "
    "Nothing dips below z = 0; max z = 8.000 is the tip of pickets 2 and 3. Max y = +0.68 is "
    "the nail heads, min y = -0.68 the back rails - the depth is unchanged from the first pass. "
    "FACING: +Y is the weathered / attacked side and carries the front rails, the diagonal "
    "brace, the iron bands, the brace straps and every nail head. -Y is the dark back slab "
    "banded by two LIGHT back rails at the same heights as the front pair, so the wall reads "
    "from behind as well - it is meant to stand in open field, seen from both sides. "
    "DETERMINISM: the per-plank width jitter, the two leaning planks and the broken plank are "
    "a baked literal table (PLANKS / CHIP_CORE / CHIP_FACE), not a runtime RNG - the build is "
    "bit-identical every run and every coordinate is hand-checkable. No random module is used. "
    "VALUE - a 3-step ladder, and the whole point of the second pass. LIGHT c08a4e (L 145): "
    "picket face boards and the back rails. MID 8a5a2b (L 97): picket sides and sharpened "
    "tips, exposed as a 0.10 margin all round each face board. DARK 6b4423 (L 74): ALL "
    "structural timber - frame, sill, both front rails AND the diagonal brace. The structure "
    "is therefore ~2:1 darker than the picket field it crosses. Previously the rails and brace "
    "were 8a5a2b and measured the SAME rendered luminance as the plank faces (105 vs 104), so "
    "the wall flattened into one tan slab and the brace survived only on its lit edge; now the "
    "two horizontals and the diagonal are a dark graphic that holds at line-up distance. "
    "IRONWORK is Metal-mid 6c7789 - a cool grey that separates from warm wood in hue as well "
    "as value, and actually reads as iron; Metal-dark 3b4350 was reading as navy paint. The "
    "3b4350 bolt heads now sit ON the mid-grey bands and straps, which is where a dark accent "
    "belongs. The four straps riding the diagonal are the brightest things on the wall, so "
    "they pin the brace even when it is only a few pixels wide. The only close pair (core mid "
    "vs back slab dark) is an internal face contact at the bottom of a 0.36-deep shadow slot, "
    "never a silhouette edge. "
    "The diagonal brace is 0.04 shallower than the front rails so their front faces are never "
    "coplanar where they cross - no z-fighting at the two brace/rail joints."
)

# ---------------------------------------------------------------- frames of reference
# prism() extrudes a 2-D profile along +Z; this matrix re-maps it so the profile lives in
# the XZ plane (a wall elevation) and the extrusion runs along Y (the wall's depth).
# Same trick defenselib.wedge() uses for its '+X' / '-X' branch:  (x, z, y) -> (x, y, z)
_XZ = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

# depth layers, back -> front.  Symmetric: -0.68 .. +0.68 = 1.36 studs deep, centred on y=0.
Y_BACK = -0.68      # REAR PLANE: back-rail rear face (unchanged, box still 1.36 deep)
Y_BACKR = -0.56     # back rail front  = back slab rear  (rails stand 0.12 proud)
Y_BACK1 = -0.44     # back slab front  = plank core rear
Y_CORE1 = -0.08     # plank core front = plank face rear
Y_FACE1 = 0.16      # plank face front = rail rear
Y_BRACE1 = 0.42     # diagonal brace front (0.04 shy of the rails on purpose)
Y_RAIL1 = 0.46      # rail front       = iron band rear
Y_STRAP1 = 0.58     # brace strap front
Y_BAND1 = 0.60      # iron band front
NAIL_LEN = 0.08     # how far a nail head stands proud (0.60 -> 0.68 / 0.58 -> 0.66)

# ---------------------------------------------------------------- baked plank table
# (left_x, right_x, lean_shear_at_tip, tip_z)  -- pitch 1.0, slot centres -3.5 .. +3.5.
# Widths 0.78 .. 0.85, gaps 0.16 .. 0.20.  Planks 2 and 5 lean; their top edges land
# 0.098 / 0.108 clear of the neighbouring picket, so nothing interpenetrates.
PLANKS = [
    (-3.92, -3.08, 0.00, 7.94),
    (-2.91, -2.07, 0.00, 7.88),
    (-1.89, -1.11, -0.09, 8.00),   # leans left
    (-0.93, -0.10, 0.00, 8.00),
    (1.11, 1.89, 0.09, 7.91),      # leans right
    (2.08, 2.91, 0.00, 7.97),
    (3.10, 3.92, 0.00, 7.90),
]
# The broken picket occupies slot 4 (x 0.10 .. 0.95): snapped off at ~6.0, notched.
CHIP_CORE = [(0.10, 0.0), (0.95, 0.0), (0.95, 5.10), (0.56, 5.58), (0.30, 6.02), (0.10, 5.74)]
CHIP_FACE = [(0.20, 0.50), (0.85, 0.50), (0.85, 4.95), (0.20, 4.95)]

SHOULDER = 0.75     # how far below the tip the sharpened taper starts
FACE_INSET = 0.10   # face board inset from the core edge, per side (mid-tone margin)
FACE_Z0 = 0.50      # face board starts here (hidden behind the 0.62-tall sill)
FACE_DROP = 0.06    # face board stops this far below the core shoulder

# horizontal cross-rails on the outer face
RAIL_A = (1.70, 2.50)
RAIL_B = (5.00, 5.80)
BAND_A = (1.92, 2.28)   # iron band inside rail A, 0.22 of timber showing above and below
BAND_B = (5.22, 5.58)

# diagonal cross-brace: a parallelogram with vertical end cuts at x = +/-3.5
BRACE_X = 3.5
BRACE_Z0 = 2.40         # bottom edge at x = -3.5 (overlaps rail A, 1.70..2.50)
BRACE_Z1 = 4.90         # bottom edge at x = +3.5 (overlaps rail B, 5.00..5.80)
BRACE_T = 0.58          # vertical thickness (~0.52 measured perpendicular)

# ironwork x positions - period 2 studs, which divides 8, so the bolt rhythm carries
# across a tile seam (... -3, -1, 1, 3 | 5, 7 ...) without a beat.
IRON_X = (-3.0, -1.0, 1.0, 3.0)


def _brace_mid(x):
    """Centre-line height of the diagonal brace at a given x."""
    t = (x + BRACE_X) / (2.0 * BRACE_X)
    return BRACE_Z0 + t * (BRACE_Z1 - BRACE_Z0) + BRACE_T * 0.5


def build(D):
    """D is the imported defenselib module.  Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- Frame: back slab (blocks light through every picket gap) + ground sill ----
    bm = bmesh.new()
    D.box(bm, (-4.0, Y_BACKR, 0.0), (4.0, Y_BACK1, 7.05))
    D.beveled_box(bm, (-4.0, Y_BACK, 0.0), (4.0, Y_RAIL1, 0.62), bevel=0.09)
    D.new_obj("Frame", bm, c, "6b4423", rbx_material="Wood", roughness=0.85)

    # ---- Back rails: a wall in open field is seen from behind too ------------------
    # Same z as the front pair (RAIL_A / RAIL_B) so they read as through-members, and
    # LIGHT timber on the dark slab - c08a4e (L 145) over 6b4423 (L 74), a 2:1 step.
    # They stand 0.12 proud of the slab and stop dead at x = +/-4, so they still tile.
    bm = bmesh.new()
    for z0, z1 in (RAIL_A, RAIL_B):
        D.beveled_box(bm, (-4.0, Y_BACK, z0), (4.0, Y_BACKR, z1), bevel=0.05)
    D.new_obj("BackRails", bm, c, "c08a4e", rbx_material="Wood", roughness=0.85)

    # ---- Plank cores: the full picket silhouette with sharpened tops --------------
    bm = bmesh.new()
    for l, r, s, ztip in PLANKS:
        zsh = ztip - SHOULDER
        o_sh = s * zsh / ztip                       # lean offset at the shoulder
        xm = 0.5 * (l + r)
        D.prism(bm, [(l, 0.0), (r, 0.0),
                     (r + o_sh, zsh), (xm + s, ztip), (l + o_sh, zsh)],
                Y_BACK1, Y_CORE1, matrix=_XZ)
    D.prism(bm, CHIP_CORE, Y_BACK1, Y_CORE1, matrix=_XZ)
    D.new_obj("PlankCores", bm, c, "8a5a2b", rbx_material="WoodPlanks", roughness=0.85)

    # ---- Plank faces: lighter face boards, inset so the core reads as the plank side
    bm = bmesh.new()
    for l, r, s, ztip in PLANKS:
        ztop = ztip - SHOULDER - FACE_DROP
        ob = s * FACE_Z0 / ztip
        ot = s * ztop / ztip
        D.prism(bm, [(l + FACE_INSET + ob, FACE_Z0), (r - FACE_INSET + ob, FACE_Z0),
                     (r - FACE_INSET + ot, ztop), (l + FACE_INSET + ot, ztop)],
                Y_CORE1, Y_FACE1, matrix=_XZ)
    D.prism(bm, CHIP_FACE, Y_CORE1, Y_FACE1, matrix=_XZ)
    D.new_obj("PlankFaces", bm, c, "c08a4e", rbx_material="WoodPlanks", roughness=0.8)

    # ---- Two horizontal cross-rails + one diagonal brace, all on the +Y face ------
    bm = bmesh.new()
    for z0, z1 in (RAIL_A, RAIL_B):
        D.beveled_box(bm, (-4.0, Y_FACE1, z0), (4.0, Y_RAIL1, z1), bevel=0.09)
    D.prism(bm, [(-BRACE_X, BRACE_Z0), (BRACE_X, BRACE_Z1),
                 (BRACE_X, BRACE_Z1 + BRACE_T), (-BRACE_X, BRACE_Z0 + BRACE_T)],
            Y_FACE1, Y_BRACE1, matrix=_XZ)
    D.new_obj("RailsBrace", bm, c, "6b4423", rbx_material="Wood", roughness=0.8)

    # ---- Iron bands over the rails ------------------------------------------------
    # D.box, NOT beveled_box: a chamfer on a full-width member leaves a V-groove at the
    # tile seam.  On the timber that reads as a beam butt joint (fine); on continuous
    # iron banding it reads as a chip every 8 studs (not fine).  Plain end faces are
    # coplanar at x = +/-4, so the banding runs unbroken along a whole wall.
    bm = bmesh.new()
    for z0, z1 in (BAND_A, BAND_B):
        D.box(bm, (-4.0, Y_RAIL1, z0), (4.0, Y_BAND1, z1))
    D.new_obj("IronBands", bm, c, "6c7789", rbx_material="Metal",
              metallic=0.7, roughness=0.4)

    # ---- Iron straps clamping the diagonal brace ----------------------------------
    bm = bmesh.new()
    for x in IRON_X:
        zm = _brace_mid(x)
        D.beveled_box(bm, (x - 0.19, Y_BRACE1, zm - 0.19),
                      (x + 0.19, Y_STRAP1, zm + 0.19), bevel=0.05)
    D.new_obj("BraceStraps", bm, c, "6c7789", rbx_material="Metal",
              metallic=0.7, roughness=0.4)

    # ---- Nail / bolt heads --------------------------------------------------------
    bm = bmesh.new()
    for z0, z1 in (BAND_A, BAND_B):
        zc = 0.5 * (z0 + z1)
        for x in IRON_X:
            D.cone(bm, (x, Y_BAND1, zc), (x, Y_BAND1 + NAIL_LEN, zc),
                   0.15, r_tip=0.06, segs=4)
    for x in IRON_X:
        zm = _brace_mid(x)
        D.cone(bm, (x, Y_STRAP1, zm), (x, Y_STRAP1 + NAIL_LEN, zm),
               0.13, r_tip=0.05, segs=4)
    D.new_obj("Nails", bm, c, "3b4350", rbx_material="Metal",
              metallic=0.8, roughness=0.4)

    return c


# ---------------------------------------------------------------- audit
# part          colour role                 hex      pieces                     tris
# ------------------------------------------------------------------------------------
# Frame         Wood dark  (frame/shadow)   6b4423   back slab 12 + sill 44       56
# BackRails     Wood light (rear banding)   c08a4e   2 bev boxes                  88
# PlankCores    Wood mid   (plank sides)    8a5a2b   7 x 5-gon prism (16) +
#                                                    1 x 6-gon broken (20)       132
# PlankFaces    Wood light (plank faces)    c08a4e   8 x 4-gon prism (12)         96
# RailsBrace    Wood dark  (structure)      6b4423   2 bev boxes 88 + brace 12   100
# IronBands     Metal mid  (iron banding)   6c7789   2 PLAIN boxes (12)           24
# BraceStraps   Metal mid  (iron straps)    6c7789   4 bev boxes                 176
# Nails         Metal dark (bolt heads)     3b4350   12 x 4-seg truncated cone   144
# ------------------------------------------------------------------------------------
# 8 parts, 816 tris  (budget 900).  Pass 1 was 7 parts / 792: the back rails cost +88 and
# dropping the bevel off the iron bands paid -64 of it back.
#
# bounds  x -4.00 .. +4.00   y -0.68 .. +0.68   z 0.000 .. 8.000   min_z = 0.0
# Depth ledger (all inside the unchanged 1.36):  back rails -0.68..-0.56 | back slab
# -0.56..-0.44 | plank cores -0.44..-0.08 | plank faces -0.08..0.16 | brace 0.16..0.42 |
# front rails 0.16..0.46 | straps 0.42..0.58 | bands 0.46..0.60 | nail heads out to 0.68.
# beveled_box clamps: sill 0.09 (min dim 0.62), front rails 0.09 (min dim 0.30 -> cap
# 0.12), straps 0.05 (min dim 0.16 -> cap 0.064) - those stand; back rails ask 0.05 on a
# 0.12 min dim so they clamp to 0.048, which is what is wanted anyway.
