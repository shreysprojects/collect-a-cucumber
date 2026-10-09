"""Three tiki torches, side by side along X.

A  BambooTorch - a segmented bamboo pole, cord lashings at every joint, a woven twine
   collar with a loose knot tail, and a metal fuel bowl at the top.
B  TikiHead    - a carved wooden totem whose top two studs are a face, cut in three
   values so the features survive at distance: a wood_mid brow ridge, wood_dark sockets
   with pale pupils, a narrow wood_light nose clear of the mouth, a wide rectangular
   mouth with teeth, and a shallow fuel bowl on the crown.
C  Brazier     - a squat stone bowl on three splayed iron legs with a heaped bed of
   glowing coals filling the bowl mouth.

Every flame is three nested teardrop prisms (flame_tip outside, then flame_mid, then a
small flame_core), each one narrower AND thinner than the shell around it so the hot
centre stays buried in the orange and never pokes out as a flat white blade.
All three face +Y.
"""
import bmesh, math

COLLECTION = "TikiTorch"

NOTES = (
    "Three separable torch variants in one collection, split by the A_ / B_ / C_ part-name "
    "prefix; each is modelled about its own origin and then offset along X.\n"
    "A BambooTorch: x=+5, footprint ~1.1 dia, 5.24 tall, flame tops out at z 5.24.\n"
    "B TikiHead:    x= 0, footprint 1.6 x 1.3, 5.46 tall, face on the +Y side, "
    "flame tops out at z 5.46.\n"
    "C Brazier:     x=-5, footprint 1.85 dia over the legs, 1.64 tall, flame tops out at "
    "z 1.64.\n"
    "Nothing moves. The Neon parts (flames + coals) are the only emissive ones - hang a "
    "Roblox PointLight / Fire on the FlameAnchor pivot of each variant rather than on the "
    "mesh. Drop a variant into a game at its own origin (subtract its VARIANTS x)."
)

VARIANTS = {
    "A": {"name": "BambooTorch", "x": 5.0},
    "B": {"name": "TikiHead", "x": 0.0},
    "C": {"name": "Brazier", "x": -5.0},
}

# where the fire actually sits - anchor a light / particle emitter here
PIVOTS = {
    "A_FlameAnchor": (5.0, 0.0, 4.18),
    "B_FlameAnchor": (0.0, 0.0, 4.60),
    "C_FlameAnchor": (-5.0, 0.0, 0.90),
}

# (palette key, width x, height x, half-depth x width, emit, lean deg, spin deg, base lift)
# The depth column DECREASES inwards: every shell has to be thinner than the one wrapping
# it or the core shows through the orange as a flat blade.  Emit stays under 1.0 so
# flame_core renders as hot pale yellow instead of clipping to pure white.
_FLAME_SHELLS = (
    ("flame_tip", 1.00, 1.00, 0.28, 0.75, 4.0, 0.0, 0.00),
    ("flame_mid", 0.68, 0.70, 0.20, 0.85, -5.0, 16.0, 0.01),
    ("flame_core", 0.39, 0.39, 0.13, 0.95, 7.0, -22.0, 0.03),
)
_FLAME_NAMES = ("FlameTip", "FlameMid", "FlameCore")


def _finish(D, name, bm, c, ox, hexcol, **kw):
    """Slide a locally-built bmesh out to its variant origin, then make the object."""
    if abs(ox) > 1e-9:
        D.xform(bm, list(bm.verts), D.place((ox, 0.0, 0.0)))
    return D.new_obj(name, bm, c, hexcol, **kw)


def _flame(D, c, prefix, ox, base_z, width, height, spin0=0.0):
    """Three nested Neon teardrop prisms standing in a fuel bowl at (ox, 0, base_z)."""
    for (key, fw, fh, fd, em, lean, spin, lift), nm in zip(_FLAME_SHELLS, _FLAME_NAMES):
        w, h = width * fw, height * fh
        bm = bmesh.new()
        D.prism(bm, D.teardrop_pts(w, h, n=5), -width * fd, width * fd,
                matrix=D.place((ox, 0.0, base_z + lift * height + h / 2.0),
                               D.rot_euler(rx=90, ry=lean, rz=spin + spin0)))
        D.new_obj(prefix + nm, bm, c, D.C(key), rbx_material="Neon", emit=em,
                  roughness=0.30)


# ---------------------------------------------------------------- A: bamboo torch
def _bamboo_torch(D, c, ox):
    # ---- pole: one lathe, five internodes that swell toward each joint then step back in
    bm = bmesh.new()
    D.lathe(bm, [(0.000, 0.00), (0.215, 0.00),
                 (0.258, 0.90), (0.212, 0.98),
                 (0.250, 1.86), (0.206, 1.94),
                 (0.242, 2.82), (0.200, 2.90),
                 (0.234, 3.70), (0.000, 3.70)], segs=8)
    _finish(D, "A_Pole", bm, c, ox, D.C("bamboo"), rbx_material="Wood", roughness=0.62)

    # ---- cord: a dark wrap over every joint, a fat woven collar under the bowl, and one
    #      loose tail hanging off the collar (the prop's one asymmetry).  The collar is
    #      two stacked bands rather than a helix - a coil coarse enough to be cheap steps
    #      more than a half turn per segment and falls apart into loose chips on the pole.
    bm = bmesh.new()
    for z, ph in ((0.86, 0.00), (1.82, 0.30), (2.78, 0.60)):
        D.prism(bm, D.ngon_pts(8, 0.300, phase=ph), z, z + 0.11)
    D.prism(bm, D.ngon_pts(8, 0.300, phase=0.00), 3.02, 3.16)
    D.prism(bm, D.ngon_pts(8, 0.300, phase=0.40), 3.18, 3.32)
    D.tube(bm, [(0.20, 0.24, 3.14), (0.25, 0.31, 2.96), (0.20, 0.35, 2.82)],
           [0.075, 0.070, 0.050], segs=4)
    _finish(D, "A_Lashing", bm, c, ox, D.C("wood_dark"), rbx_material="Fabric",
            roughness=0.85)

    # ---- fuel bowl: hollow lathe, up the outside, over the rolled rim, back down inside
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 3.62), (0.24, 3.60), (0.46, 3.92), (0.53, 4.10),
                 (0.45, 4.14), (0.36, 3.96), (0.00, 3.88)], segs=8)
    _finish(D, "A_Bowl", bm, c, ox, D.C("metal_mid"), rbx_material="Metal",
            metallic=0.6, roughness=0.40)

    # base sits between the bowl floor (3.96) and the rolled rim (4.14) so the teardrop's
    # pointed foot is hidden in the bowl and the bulb clears the rim
    _flame(D, c, "A_", ox, 4.02, 0.64, 1.22, spin0=0.0)


# ---------------------------------------------------------------- B: carved tiki head
def _tiki_head(D, c, ox):
    # ---- dark timber: plinth, shaft, and the sunk features of the face.  The eye, mouth
    #      and nostril blocks stand 0.04 proud of the surface they sit on so they read as
    #      holes, not paint.  The eyes are kept inboard of x 0.60 - the head block's
    #      bevel eats the last 0.11 of the face, and an eye out on that chamfer reads as
    #      a chipped corner instead of a socket.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.80, -0.66, 0.00), (0.80, 0.66, 0.40), bevel=0.10)
    D.beveled_box(bm, (-0.60, -0.50, 0.36), (0.60, 0.50, 2.42), bevel=0.09)
    D.box(bm, (0.18, 0.28, 3.06), (0.60, 0.66, 3.40))          # eye, screen-left
    D.box(bm, (-0.60, 0.28, 3.02), (-0.18, 0.66, 3.36))        # eye, cut a touch lower
    D.box(bm, (-0.62, 0.26, 2.36), (0.62, 0.66, 2.84))         # mouth cavity
    D.box(bm, (0.05, 0.60, 3.02), (0.13, 0.78, 3.10))          # nostril, screen-left
    D.box(bm, (-0.13, 0.60, 3.02), (-0.05, 0.78, 3.10))        # nostril
    D.prism(bm, D.chevron_pts(0.56, 0.20, 0.08), -0.05, 0.05,
            matrix=D.place((0.04, 0.66, 4.02), D.rot_euler(rx=90)))
    _finish(D, "B_Post", bm, c, ox, D.C("wood_dark"), rbx_material="Wood", roughness=0.72)

    # ---- pale carving: the head block, the narrow nose and two tally chevrons cut into
    #      the shaft (offset off-centre, deliberately uneven).  The nose is 0.32 at the
    #      nostril line tapering to 0.22 at the bridge, and it stops at z 3.00 - a wide
    #      nose that runs down to the top lip merges with the mouth into one blob.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.76, -0.62, 2.34), (0.76, 0.62, 4.26), bevel=0.11)
    D.prism(bm, [(-0.16, -0.25), (0.16, -0.25), (0.16, -0.07),
                 (0.11, 0.25), (-0.11, 0.25), (-0.16, -0.07)], -0.07, 0.07,
            matrix=D.place((0.0, 0.69, 3.25), D.rot_euler(rx=90)))
    D.prism(bm, D.chevron_pts(0.62, 0.22, 0.09), -0.05, 0.05,
            matrix=D.place((0.06, 0.54, 1.34), D.rot_euler(rx=90)))
    D.prism(bm, D.chevron_pts(0.46, 0.17, 0.07), -0.05, 0.05,
            matrix=D.place((-0.04, 0.54, 1.86), D.rot_euler(rx=90)))
    _finish(D, "B_Head", bm, c, ox, D.C("wood_light"), rbx_material="Wood", roughness=0.68)

    # ---- the brow ridge, in the third wood value so brow / face / socket separate.  It
    #      is inset to x +/-0.70 (inside the head block) and only overhangs the face
    #      plane by 0.16 - any deeper and its cast shadow swallows the whole eye band.
    #      It is still the frontmost plane of the face: the nose stops at y 0.76.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.70, 0.40, 3.48), (0.70, 0.78, 3.94), bevel=0.10)
    _finish(D, "B_Brow", bm, c, ox, D.C("wood_mid"), rbx_material="Wood", roughness=0.70)

    # ---- cream inlay: four blunt teeth hanging from the top lip, plus a pupil block in
    #      each socket standing 0.03 proud of its floor so the eyes survive brow shadow
    bm = bmesh.new()
    D.slat_run(bm, (-0.54, 0.38, 2.58), (0.54, 0.70, 2.84), 4,
               gap_frac=0.30, axis='x', bevel=0.0)
    D.box(bm, (0.31, 0.60, 3.15), (0.47, 0.69, 3.31))
    D.box(bm, (-0.47, 0.60, 3.11), (-0.31, 0.69, 3.27))
    _finish(D, "B_TeethEyes", bm, c, ox, D.C("cloth_cream"),
            rbx_material="SmoothPlastic", roughness=0.45)

    # ---- shallow fuel dish on the crown
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 4.22), (0.28, 4.20), (0.48, 4.36), (0.54, 4.48),
                 (0.46, 4.52), (0.37, 4.38), (0.00, 4.32)], segs=8)
    _finish(D, "B_Bowl", bm, c, ox, D.C("metal_dark"), rbx_material="Metal",
            metallic=0.65, roughness=0.38)

    # base sits between the dish floor (4.38) and the rolled rim (4.52), as on A
    _flame(D, c, "B_", ox, 4.44, 0.60, 1.02, spin0=25.0)


# ---------------------------------------------------------------- C: stone brazier
def _brazier(D, c, ox):
    # ---- squat stone bowl, hollow lathe with a thick rolled lip.  The lip tops out at
    #      z 0.90, low enough that a player at eye height sees the fuel burning inside
    #      instead of a rim and a shadow.
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 0.30), (0.36, 0.26), (0.74, 0.58), (0.92, 0.86),
                 (0.82, 0.90), (0.70, 0.76), (0.40, 0.54), (0.00, 0.48)], segs=8)
    _finish(D, "C_Bowl", bm, c, ox, D.C("stone_mid"), rbx_material="Slate", roughness=0.88)

    # ---- three stubby splayed legs on flat foot pads: two toward the viewer, one behind,
    #      each cut a slightly different thickness so the tripod is not machine-perfect.
    #      The legs start at z 0.08 and stand on the pads - a splayed cylinder tilts its
    #      bottom cap ~17 deg, which pushes its low corner under the ground plane.
    bm = bmesh.new()
    legs = D.ring_positions(3, 0.56, phase=math.radians(30))
    t0 = 0.08 / 0.52                      # fraction of the leg axis spent inside the pad
    for (lx, ly), r0, r1 in zip(legs, (0.21, 0.225, 0.20), (0.150, 0.160, 0.142)):
        fx, fy = lx * (1.0 - 0.28 * t0), ly * (1.0 - 0.28 * t0)
        D.cyl(bm, (fx, fy, 0.08), (lx * 0.72, ly * 0.72, 0.52),
              r0 + (r1 - r0) * t0, segs=6, r2=r1)
        D.prism(bm, D.ngon_pts(6, 0.23, phase=0.40, center=(fx, fy)), 0.0, 0.08)
    _finish(D, "C_Legs", bm, c, ox, D.C("iron_dark"), rbx_material="Metal",
            metallic=0.55, roughness=0.52)

    # ---- heaped ember bed filling the bowl mouth plus two lumps of coal, off-centre.
    #      The bed tops out 0.02 above the rim and the lumps break the rim line, so the
    #      fire visibly stands on burning fuel from any angle a player can reach.
    bm = bmesh.new()
    D.prism(bm, D.star_pts(6, 0.62, 0.42, phase=0.30), 0.62, 0.92)
    D.prism(bm, D.ngon_pts(6, 0.15, phase=0.40, center=(-0.16, 0.10)), 0.88, 1.02)
    D.prism(bm, D.ngon_pts(6, 0.12, phase=0.90, center=(0.14, -0.12)), 0.88, 1.00)
    _finish(D, "C_Coals", bm, c, ox, D.C("neon_orange"), rbx_material="Neon", emit=0.90,
            roughness=0.40)

    # the teardrop's pointed foot sits inside the ember bed so the fire grows out of it
    _flame(D, c, "C_", ox, 0.74, 0.54, 0.90, spin0=-15.0)


# ---------------------------------------------------------------- entry point
def build(D):
    """D is the imported proplib module.  Returns the collection."""
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    _bamboo_torch(D, c, VARIANTS["A"]["x"])
    _tiki_head(D, c, VARIANTS["B"]["x"])
    _brazier(D, c, VARIANTS["C"]["x"])

    return c
