"""Garden scarecrow: a wooden cross-frame, a burlap sack head with a stitched face, a
patched shirt with stuffed sleeves over trouser legs, straw bursting from every opening,
a floppy straw hat worn at an angle and a crow perched on the high end of the cross-arm.

Faces +Y - the stitched face, the patches and the crow's beak all read from the front.
Remember the mirror trap: +X is the viewer's LEFT, so the crow (built at -X) perches on
the viewer's RIGHT."""
import bmesh, math, random

COLLECTION = "Scarecrow"
NOTES = (
    "Free-standing garden dressing, ~5.55 studs tall on a low dirt mound; footprint "
    "~3.6 wide across the arms x ~1.3 deep (the hat brim and the mound are the deep "
    "parts).  The post runs from z 0 up to z 4.72 inside the sack head; the cross-arm is "
    "lashed on at z 3.66 and tilts 6 deg, so the -X end - the viewer's RIGHT - rides high "
    "and carries the crow.  The shirt yoke swallows the beam (top at z 3.70, beam "
    "underside 3.44 at the shoulder) and the sleeves wrap it out to the wrist, so the "
    "arms grow out of the body, not the neck; the rope shows at the throat and the two "
    "wrists, not at the post, which the shirt now covers.  Nothing moves; sink the mound "
    "~0.05 into the turf so its rim does not float.  Parts are merged by colour, so a "
    "few objects carry more than one feature: 'RedCloth' = shirt body + yoke + both sleeves + both "
    "mitten cuffs + hat band + nose, 'Denim' = both trouser legs + the blue patch, "
    "'Burlap' = sack head + cinched neck + sackcloth patch, 'Stitching' = the face "
    "stitches and the dashes sewn round both patches."
)

# ---------------------------------------------------------------- layout constants
ARM_TILT = 6.0                       # degrees; the +X end of the cross-arm drops
ARM_C = (0.0, 0.08, 3.66)            # centre of the cross-arm
ARM_HALF = 1.55
_CA = math.cos(math.radians(ARM_TILT))
_SA = math.sin(math.radians(ARM_TILT))

SHOULDER_HALF = 0.90                 # the yoke overhangs the beam a little either side
SHOULDER_TOP = 3.70                  # above the beam's top at the shoulder - no gap
NECK_Z = 3.68                        # foot of the cinched sack neck, in the collar
CUFF_U = 1.42                        # mitten centre; caps the beam end at u 1.55
CROW_DZ = 0.40                       # crow rides on the padded sleeve, not bare wood

# one sleeve per side: (side, u0, u_mid, u1, half at shoulder, half at wrist,
# upper droop, lower droop).  The two sides differ so the arms are not a machined bar.
SLEEVES = (
    (1.0, 0.66, 1.02, 1.22, 0.215, 0.180, 2.0, 4.5),
    (-1.0, 0.64, 0.99, 1.20, 0.205, 0.172, -1.0, -2.5),
)

# chest patches: (cx, cz, w, h, ry, dashes, seed).  Deliberately different sizes,
# aspects and angles so neither reads as a label or a screen.
PATCH_Y = 0.405                      # slab centre; the shirt front face is y 0.40
PATCH_BURLAP = (0.40, 3.03, 0.34, 0.31, 8.0, 6, 3)
PATCH_DENIM = (-0.36, 2.60, 0.52, 0.28, -11.0, 7, 4)

HEAD_C = (0.05, 0.10, 4.44)          # sack head, nudged forward = slumped
HEAD_R = 0.58
HEAD_SY, HEAD_SZ = 0.86, 1.06

HAT_LOC = (0.05, 0.06, 4.86)
HAT_ROT = (-9.0, 7.0)                # rx (tips forward over the eyes), ry (cocked)


def arm_pt(u, dy=0.0, dz=0.0):
    """A point on the tilted cross-arm: `u` runs along it (+ = +X end), `dz` is up off
    its axis, `dy` is toward the viewer."""
    return (ARM_C[0] + u * _CA + dz * _SA,
            ARM_C[1] + dy,
            ARM_C[2] - u * _SA + dz * _CA)


def face_y(dx, dz):
    """Surface y of the sack head at an offset (dx, dz) from its centre - so a stitch
    lands ON the face instead of floating in front of it or sinking into it."""
    k = 1.0 - (dx / HEAD_R) ** 2 - (dz / (HEAD_R * HEAD_SZ)) ** 2
    return HEAD_C[1] + HEAD_R * HEAD_SY * math.sqrt(max(0.12, k))


PIVOTS = {"ArmCentre": ARM_C,
          "CrowPerch": arm_pt(-1.18, 0.10, CROW_DZ),
          "HatBase": HAT_LOC}


def _stitch(D, bm, center, size, ry=0.0):
    """One thin dark thread box, tilted in the XZ plane."""
    cx, cy, cz = center
    sx, sy, sz = size
    D.box(bm, (cx - sx / 2, cy - sy / 2, cz - sz / 2),
          (cx + sx / 2, cy + sy / 2, cz + sz / 2), rot=D.rot_euler(ry=ry))


def _sleeve_seg(D, bm, u0, u1, half_y, tilt, bevel=0.055):
    """One stuffed sleeve segment swallowing the cross-arm between u0 and u1.  It is
    fatter than the beam (half 0.14 x 0.13) so no timber shows through, and carries its
    own droop so the cloth is not parallel to the stick inside it."""
    cx, cy, cz = arm_pt((u0 + u1) / 2.0)
    hu = abs(u1 - u0) / 2.0
    D.beveled_box(bm, (cx - hu, cy - half_y, cz - half_y + 0.02),
                  (cx + hu, cy + half_y, cz + half_y - 0.02),
                  bevel=bevel, rot=D.rot_euler(ry=tilt))


def _patch_slab(D, bm, patch):
    """The patch itself: a thin off-axis square standing proud of the shirt front."""
    cx, cz, w, h, ry = patch[:5]
    D.box(bm, (cx - w / 2, PATCH_Y - 0.035, cz - h / 2),
          (cx + w / 2, PATCH_Y + 0.035, cz + h / 2), rot=D.rot_euler(ry=ry))


def _patch_stitches(D, bm, patch, inset=0.04):
    """Short dashes sewn just inside a patch's edge, walked round its perimeter and each
    kicked a few degrees off the run so the line looks hand-sewn, not machined."""
    cx, cz, w, h, ry, n, seed = patch
    hw, hh = max(0.02, w / 2 - inset), max(0.02, h / 2 - inset)
    ca, sa = math.cos(math.radians(ry)), math.sin(math.radians(ry))
    rng = random.Random(seed)
    peri = 4.0 * (hw + hh)
    for i in range(n):
        t = peri * (i + 0.5) / n
        if t < 2 * hw:                              # bottom edge, running +X
            lx, lz, flat = -hw + t, -hh, True
        elif t < 2 * hw + 2 * hh:                   # +X edge, running up
            lx, lz, flat = hw, -hh + (t - 2 * hw), False
        elif t < 4 * hw + 2 * hh:                   # top edge, running -X
            lx, lz, flat = hw - (t - 2 * hw - 2 * hh), hh, True
        else:                                       # -X edge, running down
            lx, lz, flat = -hw, hh - (t - 4 * hw - 2 * hh), False
        size = (0.09, 0.05, 0.045) if flat else (0.045, 0.05, 0.09)
        kick = (12.0 if i % 2 else -12.0) * rng.uniform(0.6, 1.0)
        _stitch(D, bm, (cx + lx * ca + lz * sa, PATCH_Y + 0.05, cz - lx * sa + lz * ca),
                size, ry=ry + kick)


def _tuft(D, bm, base, direction, length, n=4, seed=1, r=0.075, spread=0.30):
    """A little burst of straw cones from `base`, leaning along `direction`."""
    rng = random.Random(seed)
    bx, by, bz = base
    dx, dy, dz = direction
    L = math.sqrt(dx * dx + dy * dy + dz * dz) or 1.0
    dx, dy, dz = dx / L, dy / L, dz / L
    for _ in range(n):
        s = length * rng.uniform(0.70, 1.0)
        D.cone(bm,
               (bx + rng.uniform(-0.05, 0.05), by + rng.uniform(-0.06, 0.06),
                bz + rng.uniform(-0.05, 0.05)),
               (bx + dx * s + rng.uniform(-spread, spread) * s,
                by + dy * s + rng.uniform(-spread, spread) * s,
                bz + dz * s + rng.uniform(-spread, spread) * s),
               r * rng.uniform(0.8, 1.2), 0.0, segs=4)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    wood = D.C("wood_dark")
    ropec = D.C("rope")
    burlap = D.C("canvas")
    red = D.C("cloth_red")
    blue = D.C("cloth_blue")
    strawc = D.C("straw")
    hayc = D.C("hay")
    dark = D.C("plastic_black")
    dirtc = D.C("dirt")
    beakc = D.C("warning_yellow")

    hat_m = D.place(HAT_LOC, D.rot_euler(rx=HAT_ROT[0], ry=HAT_ROT[1]))

    # ---- low dirt mound, squashed in Y so the footprint stays shallow
    bm = bmesh.new()
    D.lathe(bm, [(0.78, 0.0), (0.66, 0.17), (0.34, 0.32), (0.0, 0.39)], segs=9,
            matrix=D.place((0.06, -0.05, 0.0), scale=(1.0, 0.66, 1.0)))
    D.new_obj("DirtMound", bm, c, dirtc, rbx_material="Ground", roughness=0.95)

    # ---- the frame: one post, one cross-arm hung 6 deg off level
    bm = bmesh.new()
    D.beveled_box(bm, (-0.19, -0.19, 0.0), (0.19, 0.19, 4.72), bevel=0.06)
    D.beveled_box(bm, (-ARM_HALF, -0.06, 3.53), (ARM_HALF, 0.22, 3.79), bevel=0.05,
                  rot=D.rot_euler(ry=ARM_TILT))
    D.new_obj("Frame", bm, c, wood, rbx_material="Wood", roughness=0.85)

    # ---- rope: the cinch in the sack's throat and one turn round each wrist, binding
    #      sleeve to stick.  The turns that lash the cross-arm to the post are inside the
    #      shirt yoke now, so they are not built - there would be nothing to see.
    bm = bmesh.new()
    D.torus(bm, (0.05, 0.10, NECK_Z + 0.16), 0.205, 0.045, seg_major=8, seg_minor=3)
    for (s, _u0, _um, u1, _hyu, _hyl, _dru, _drl) in SLEEVES:
        D.torus(bm, arm_pt(s * (u1 + 0.02)), 0.195, 0.045, seg_major=8, seg_minor=3,
                rot=D.rot_euler(ry=90.0 + ARM_TILT))
    D.new_obj("Lashing", bm, c, ropec, rbx_material="Fabric", roughness=0.9)

    # ---- red cloth: shirt body and yoke, both sleeves and mittens, hat band, nose.
    #      The yoke runs up past the beam's top at the shoulder, so the arms come out of
    #      the body instead of leaving a strip of daylight under the crossbeam.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.78, -0.34, 2.26), (0.78, 0.40, 3.36), bevel=0.11)
    D.beveled_box(bm, (-SHOULDER_HALF, -0.32, 3.20), (SHOULDER_HALF, 0.38, SHOULDER_TOP),
                  bevel=0.13)
    for (s, u0, um, u1, hy_up, hy_lo, dr_up, dr_lo) in SLEEVES:
        _sleeve_seg(D, bm, s * u0, s * um, hy_up, ARM_TILT + dr_up, bevel=0.06)
        _sleeve_seg(D, bm, s * (um - 0.04), s * u1, hy_lo, ARM_TILT + dr_lo)
        # the mitten: fatter than the wrist it follows, and long enough to cap the beam
        cx, cy, cz = arm_pt(s * CUFF_U)
        D.beveled_box(bm, (cx - 0.16, cy - 0.205, cz - 0.19),
                      (cx + 0.16, cy + 0.205, cz + 0.19), bevel=0.06,
                      rot=D.rot_euler(ry=ARM_TILT + dr_lo))
    D.lathe(bm, [(0.485, 0.09), (0.485, 0.23)], segs=8, matrix=hat_m, cap=False)
    ny = face_y(0.0, -0.05)
    D.cone(bm, (HEAD_C[0], ny - 0.16, 4.39), (HEAD_C[0], ny + 0.11, 4.33), 0.12, 0.0, segs=3)
    D.new_obj("RedCloth", bm, c, red, rbx_material="Fabric", roughness=0.8)

    # ---- denim: two trouser legs (one hitched higher) and the big blue patch
    bm = bmesh.new()
    D.beveled_box(bm, (0.10, -0.24, 1.02), (0.64, 0.30, 2.40), bevel=0.09)
    D.beveled_box(bm, (-0.66, -0.26, 1.24), (-0.12, 0.28, 2.40), bevel=0.09)
    _patch_slab(D, bm, PATCH_DENIM)
    D.new_obj("Denim", bm, c, blue, rbx_material="Fabric", roughness=0.85)

    # ---- burlap: the sack head, the cinched neck under it, one sackcloth patch.
    #      The neck is a closed solid pinched in the middle - a sack throat with a
    #      rope-tied waist - not an open shell you can see the inside of.
    bm = bmesh.new()
    D.rock(bm, HEAD_C, HEAD_R, seed=7, jitter=0.10, subdiv=1,
           scale=(1.0, HEAD_SY, HEAD_SZ))
    D.lathe(bm, [(0.0, 0.0), (0.34, 0.02), (0.19, 0.16), (0.31, 0.30), (0.0, 0.32)],
            segs=8, matrix=D.place((0.05, 0.10, NECK_Z)))
    _patch_slab(D, bm, PATCH_BURLAP)
    D.new_obj("Burlap", bm, c, burlap, rbx_material="Fabric", roughness=0.95)

    # ---- straw: both cuffs, a ruff at the neck, the shirt hem, a few wisps at the base
    bm = bmesh.new()
    for i, u in enumerate((1.50, -1.50)):
        s = 1.0 if u > 0 else -1.0
        _tuft(D, bm, arm_pt(u, 0.0, 0.0), (s, 0.0, -0.12), 0.22, n=4, seed=11 + i,
              r=0.08, spread=0.30)
    # three uneven wisps escaping the neck tie - forward and out, never an even ring
    for (b, t, r) in (((0.26, 0.20, 3.80), (0.58, 0.44, 3.72), 0.080),
                      ((-0.14, 0.24, 3.78), (-0.36, 0.52, 3.74), 0.070),
                      ((0.06, 0.30, 3.82), (0.11, 0.72, 3.71), 0.090)):
        D.cone(bm, b, t, r, 0.0, segs=4)
    rng = random.Random(5)
    for hx in (-0.68, -0.38, -0.08, 0.22, 0.48, 0.70):
        D.cone(bm, (hx, rng.uniform(-0.10, 0.28), 2.33),
               (hx + rng.uniform(-0.13, 0.13), rng.uniform(-0.18, 0.38),
                2.33 - rng.uniform(0.26, 0.40)), 0.085, 0.0, segs=4)
    for (ox, oy) in D.ring_positions(3, 0.40, phase=0.9, center=(0.04, -0.04)):
        D.cone(bm, (ox, oy * 0.66, 0.18), (ox * 1.5, oy * 1.0, 0.50), 0.07, 0.0, segs=4)
    D.new_obj("StrawTufts", bm, c, strawc, rbx_material="Grass", roughness=0.95)

    # ---- straw hat: lathed crown, wide brim with a deterministic droop wave
    bm = bmesh.new()
    D.lathe(bm, [(0.0, 0.02), (0.46, 0.04), (0.44, 0.50), (0.30, 0.66), (0.0, 0.68)],
            segs=8, matrix=hat_m)
    brim = D.lathe(bm, [(0.34, 0.10), (0.68, -0.02), (0.66, -0.10), (0.34, 0.00)], segs=8)
    for k in (1, 2):
        for j, v in enumerate(brim[k * 8:(k + 1) * 8]):
            v.co.z += 0.075 * math.sin(2.0 * (2.0 * math.pi * j / 8.0) + 0.7)
    D.xform(bm, brim, hat_m)
    D.new_obj("StrawHat", bm, c, hayc, rbx_material="Grass", roughness=0.95)

    # ---- stitching: two X eyes, a stitched grin, dashes sewn round both patches
    bm = bmesh.new()
    for ex in (0.285, -0.185):
        ez = 0.20
        ey = face_y(ex - HEAD_C[0], ez)
        for a in (44.0, -44.0):
            _stitch(D, bm, (ex, ey, HEAD_C[2] + ez), (0.23, 0.20, 0.055), ry=a)
    for t in (-1.0, -0.34, 0.34, 1.0):
        gx = HEAD_C[0] + 0.30 * t
        gz = 4.10 + 0.12 * t * t
        _stitch(D, bm, (gx, face_y(gx - HEAD_C[0], gz - HEAD_C[2]), gz),
                (0.17, 0.20, 0.05), ry=-math.degrees(math.atan(0.8 * t)))
    for patch in (PATCH_BURLAP, PATCH_DENIM):
        _patch_stitches(D, bm, patch)
    D.new_obj("Stitching", bm, c, dark, rbx_material="Fabric", roughness=0.7)

    # ---- the crow, perched on the high (-X, viewer's right) end, facing out
    bx, by, bz = arm_pt(-1.18, 0.10, CROW_DZ)
    bm = bmesh.new()
    D.uvsphere(bm, (bx, by, bz), 0.25, segs=6, rings=4, scale=(1.15, 0.80, 0.92))
    hx, hy, hz = bx - 0.30, by + 0.05, bz + 0.21
    D.ico(bm, (hx, hy, hz), 0.17, subdiv=0)
    D.wedge(bm, (bx + 0.10, by - 0.13, bz - 0.11), (bx + 0.56, by + 0.13, bz + 0.12),
            rise='-X')
    D.wedge(bm, (bx - 0.16, by + 0.09, bz - 0.10), (bx + 0.18, by + 0.19, bz + 0.11),
            rise='-X')
    D.new_obj("Crow", bm, c, dark, rbx_material="SmoothPlastic", roughness=0.5)

    bm = bmesh.new()
    D.cone(bm, (hx - 0.04, hy + 0.07, hz - 0.01), (hx - 0.22, hy + 0.22, hz - 0.05),
           0.075, 0.0, segs=4)
    D.box(bm, (hx - 0.14, hy + 0.09, hz + 0.04), (hx - 0.07, hy + 0.15, hz + 0.10))
    D.new_obj("CrowBeak", bm, c, beakc, rbx_material="SmoothPlastic", roughness=0.45)

    return c
