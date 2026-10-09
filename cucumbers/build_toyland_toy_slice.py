"""Toyland: Toy Slice - one chunky cucumber slice standing on its edge, cut face to +Y."""
import bmesh, math, random

COLLECTION = "ToylandToySlice"
NOTES = ("One chunky cucumber slice standing on its edge, cut face to +Y (the game lays an "
         "upright disc flat in the field; the index card shows it standing, like the tile). "
         "A 10-sided dark-green rind drum (r 0.86, 0.46 thick, toy_green_dk) with seven "
         "lighter-green speckles round its skin; a bright light-green cut face on BOTH sides "
         "(toy_face_lt, inset 0.15); on each face a pale centre disc (r 0.45, toy_spoke) "
         "carrying six lime teardrop seed chambers that point in at a small pale hub, so the "
         "pale shows between them as six radial spokes; and a ring of ten small lime squares "
         "along the face's edge where it meets the rind (the tile's 'lighter squares on the "
         "rind'). Footprint ~1.73 (X) x 0.58 (Y) x 1.70 (Z) studs, disc centre at z 0.845; the "
         "lowest point is the chamfered bottom vertex of the rind, a flat strip on z = 0. "
         "Y-extent 0.58 < 0.45 x 1.70, so the game's lay-flat test fires. 4 parts. "
         "Deviations from the brief, all because the tile disagrees: SIX spokes/chambers, not "
         "eight (the tile has six); the brief's square Seeds are the tile's six lime teardrop "
         "chambers instead (hub ~0.11, chambers out to r 0.40, pale disc r 0.45, not spokes to "
         "0.78 of the face radius); the pale centre is ONE disc (part PaleCentre) with the "
         "chambers on it, the spokes and hub being the pale left between them; the chambers "
         "and the face-edge squares are the tile's lime, which is cuke_stud, the same colour "
         "+ material as the rim speckles, so rule 5 merges all three into one part 'Lime' "
         "(4 parts, not 5); face inset 0.15, not 0.10 (the tile's rind ring is ~15 % of the "
         "radius). The disc centre sits at R - 0.05*sin(18 deg) = 0.8445, not R: the rind's "
         "0.05 chamfer lifts the true lowest point 0.0155 above the bare 10-gon vertex. "
         "Everything is placed with matrices, so dryrun's bbox and min_z are not meaningful.")

# --- the disc ----------------------------------------------------------------------
R = 0.86                    # a touch chunkier than the standard 0.80
T = 0.46
SEGS = 10                   # the lib's rind 10-gon; its default phase puts a vertex straight
                            # DOWN once the disc is stood up (local +Y -> world -Z)
RIM_BEVEL = 0.05            # slice_disc's own default, passed explicitly to keep ZC in step
# bevelling the downward vertex's edge chamfers it 0.05 along each side, which lifts the
# lowest point by bevel*sin(pi/segs); sit the centre that much lower so it lands on z = 0
ZC = R - RIM_BEVEL * math.sin(math.pi / SEGS)

INSET = 0.15
FACE_PROUD = 0.02           # slice_face's own default
T2 = T / 2.0
FACE_R = R * (1.0 - INSET)                          # face 10-gon circumradius 0.731
FACE_AP = FACE_R * math.cos(math.pi / SEGS)         # ... and its apothem 0.695
FACE_TOP = T2 + FACE_PROUD                          # 0.25 in the disc's local Z

# --- the pattern on each cut face (disc-local studs, +Z = the face) ---------------------
PALE_R = 0.45               # the pale centre disc
PALE_SEGS = 12
CHAMBERS = 6                # lime teardrops, pointed end at the hub
CH_R0, CH_R1 = 0.115, 0.405     # radial span of each teardrop (tip .. round end)
CH_W = 0.25                 # teardrop_pts width parameter (widest ~0.205): the chambers
                            # take ~2/3 of the arc at their widest, the pale spokes ~1/3
CH_PHASE = 0.0              # chambers at local 0/60/..: screen-left and -right, 4 diagonals;
                            # the pale spokes between them point straight up and down
TEETH = SEGS                # one lime square per face facet, at the facet middles
TOOTH_IN = 0.025            # centred just inside the face edge, lapping onto the rind
TOOTH_SEED = 17
STUD_SEED = 23              # slice_studs start facet 4: keeps the two bottom facets bare, so
                            # no speckle pokes below the rind's ground contact


def _pale_side(D, bm):
    """The pale centre disc on the local +Z face."""
    return D.prism(bm, D.ngon_pts(PALE_SEGS, PALE_R, phase=math.pi / PALE_SEGS),
                   FACE_TOP - 0.01, FACE_TOP + 0.02)


def _lime_side(D, bm, rng):
    """Six teardrop chambers on the pale disc + ten squares along the face edge (+Z face)."""
    vs = []
    # chambers: teardrop_pts is round at -Y, pointed at +Y; map its +Y onto -radial so the
    # point aims at the hub and the round end sits out toward the pale disc's rim
    h = CH_R1 - CH_R0
    rc = (CH_R0 + CH_R1) / 2.0
    prof = D.teardrop_pts(CH_W, h, n=6)
    for i in range(CHAMBERS):
        a = math.radians(CH_PHASE + 360.0 * i / CHAMBERS)
        ux, uy = math.cos(a), math.sin(a)           # radial
        vx, vy = -uy, ux                            # tangential
        pts = [(rc * ux + x * vx - y * ux, rc * uy + x * vy - y * uy) for x, y in prof]
        vs += D.prism(bm, pts, FACE_TOP + 0.01, FACE_TOP + 0.04)
    # face-edge squares: straddle the face's straight edges, mostly on the face, lapping
    # a little onto the rind; bottoms buried in the rind cap, tops 0.02 above the face
    for k in range(TEETH):
        a_deg = 360.0 * k / TEETH + rng.uniform(-5.0, 5.0)
        a = math.radians(a_deg)
        s = rng.uniform(0.09, 0.115)
        r = FACE_AP / math.cos(math.radians(a_deg - 360.0 * k / TEETH)) - TOOTH_IN
        cx, cy = r * math.cos(a), r * math.sin(a)
        vs += D.beveled_box(bm, (cx - s / 2.0, cy - s / 2.0, T2 - 0.03),
                            (cx + s / 2.0, cy + s / 2.0, FACE_TOP + 0.02), bevel=0.02,
                            rot=D.rot_euler(0.0, 0.0, a_deg))
    return vs


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    m = D.slice_stand((0.0, 0.0, ZC), lean_deg=0.0)
    back = D.rot_euler(0.0, 180.0, 0.0)     # local (x, y, z) -> (-x, y, -z): the +Z face
                                            # pattern turned onto the -Z face (a rotation,
                                            # not a mirror, so the windings stay outward)

    # --- rind: the dark drum ------------------------------------------------------------
    bm = bmesh.new()
    D.slice_disc(bm, radius=R, thick=T, segs=SEGS, bevel=RIM_BEVEL, matrix=m)
    D.new_obj("Rim", bm, c, D.C("toy_green_dk"), rbx_material="SmoothPlastic")

    # --- the bright light-green cut faces --------------------------------------------------
    bm = bmesh.new()
    D.slice_face(bm, radius=R, thick=T, segs=SEGS, inset=INSET, proud=FACE_PROUD, matrix=m)
    D.new_obj("Face", bm, c, D.C("toy_face_lt"), rbx_material="SmoothPlastic")

    # --- the pale centre (hub + spokes = the pale left between the chambers) -------------
    bm = bmesh.new()
    vs = _pale_side(D, bm)
    vb = _pale_side(D, bm)
    D.xform(bm, vb, back)
    D.xform(bm, vs + vb, m)
    D.new_obj("PaleCentre", bm, c, D.C("toy_spoke"), rbx_material="SmoothPlastic")

    # --- lime: seed chambers + face-edge squares (both faces) + the rind speckles --------
    bm = bmesh.new()
    rng = random.Random(TOOTH_SEED)
    vs = _lime_side(D, bm, rng)
    vb = _lime_side(D, bm, rng)
    D.xform(bm, vb, back)
    D.xform(bm, vs + vb, m)
    D.slice_studs(bm, radius=R, thick=T, segs=SEGS, matrix=m, n=7, size=0.20, seed=STUD_SEED)
    D.new_obj("Lime", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
