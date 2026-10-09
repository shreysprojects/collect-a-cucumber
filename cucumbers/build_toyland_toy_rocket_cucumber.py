"""Toyland: the Toy Rocket Cucumber - a cucumber riding in a white toy rocket, red nose cone on."""
import bmesh, math

COLLECTION = "ToylandToyRocketCucumber"
NOTES = (
    "A cucumber riding in a toy rocket, standing upright on the rocket's blue base; the "
    "cucumber's head pokes out of the top wearing a red nose cone.  Everything is toy "
    "plastic (SmoothPlastic), no Neon.  "
    "BOTTOM TO TOP: a stepped toy_blue base - a narrow foot r 0.64 (z 0-0.12, the only "
    "thing touching z = 0) under a drum r 0.92 (z 0.12-0.50); the toy_white 8-sided hull "
    "(z 0.45-2.90), a chamfered bottom edge (r 0.94 -> 1.00 by z 0.51) barrelling out to "
    "1.08 (straight z 1.40-2.40) and back to 1.02 at the top; a toy_red band r 1.10 (z 2.80-3.00) round the hull's top "
    "edge; the cucumber head (cuke_green, 8-sided, r 0.78) rising from z 2.60 inside the "
    "hull to a rounded top at z 4.25; and a red 8-sided ogive nose cone (base r 0.62, "
    "z 4.21-5.16) sitting on it like a hat.  "
    "FRONT (+Y): a porthole centred on the hull's front facet at z 1.90 - a toy_blue ring "
    "(outer r 0.42, inner r 0.28, 0.08 proud) around a toy_blue_dk disc recessed 0.035 "
    "behind the ring's face.  FINS (toy_red): one at +X, one at -X and one on the FRONT, "
    "all swept down-and-out the way the tile draws them, their outer tips at z 0.05.  "
    "The side fins are 0.22 thick and reach ~0.75 out from the hull (x = +-1.72), "
    "leaving the body between z 0.34 (out of the blue drum) and z 1.20 (into the hull); "
    "the front fin is a wider tab, 0.52 thick, "
    "reaching ~0.47 out (face at y 1.46, top meets the hull at z 1.30) with a flat "
    "front face z 0.16-1.02 carrying a toy_yellow square (0.28, upper, z 0.74) and a "
    "toy_orange square (0.22, lower, z 0.36), 0.02 proud.  "
    "FACE on the head's +Y facet: two black toy_eye rounded squares 0.28 x 0.36 at "
    "x +-0.19, z 3.66 with white 0.10 highlights in their upper OUTER corners; a green "
    "snout block (0.26 wide, 0.14 proud, z 3.28-3.46, part of Head) with a dark open "
    "U-shaped mouth under it (0.30 wide, z 3.125-3.265); two small dark cheek squares at x +-0.245, "
    "z 3.34.  Mouth and cheeks are merged into Eyes.  Seven cuke_stud speckles on the "
    "head's other facets (none on the face facet).  "
    "Footprint about 3.44 (x) by 2.5 (y, -1.02 .. +1.48, the front fin makes it deeper in "
    "front), height 5.16, rocket axis on x = 0, y = 0.  Ten parts: Blue, PortholeGlass, "
    "Hull, Red, DotYellow, DotOrange, Head, HeadStuds, Eyes, EyeShine.  "
    "DEVIATIONS: body upright (the tile leans, REV3 rule 1).  Tile over brief: the front "
    "fin is a wide tab (tile) rather than a 0.22 fin, so the two dots fit on its face; "
    "the fins sweep downward (tile) instead of being plain wedges; the base has the "
    "tile's narrower foot under the drum; the tile's green snout above the mouth is "
    "added.  The brief's separate Base and Porthole-ring parts share colour + material, "
    "so they are merged into one part named Blue.  Eyes follow the REV3 'Faces' rule "
    "(black rounded square + white highlight) instead of the tile's white-sclera eyes, "
    "at 0.28 wide and +-0.19 so they nearly fit the head's 0.60-wide front facet "
    "(0.03 overhang onto the neighbouring facets).  The tile shows one cheek clearly; "
    "the brief's two symmetric cheeks are kept.  No exhaust flame (the tile has none).  "
    "Most parts are placed with matrices, so dryrun's bounding box is an approximation."
)

SEGS = 8
PHASE = math.pi / SEGS          # the set's lathe phase: a FLAT facet square on +Y (and +-X)
COS8 = math.cos(math.pi / SEGS)

# ---------------------------------------------------------------- the rocket
# (radius, z) profiles, revolved with PHASE so every facet lines up with the head's.
BASE_PROFILE = [(0.00, 0.00), (0.64, 0.00), (0.64, 0.12), (0.86, 0.12),
                (0.92, 0.18), (0.92, 0.50), (0.00, 0.50)]
HULL_PROFILE = [(0.00, 0.45), (0.94, 0.45), (1.00, 0.51), (1.04, 0.70), (1.07, 1.05),
                (1.08, 1.40), (1.08, 2.40), (1.05, 2.70), (1.02, 2.90), (0.00, 2.90)]
BAND_PROFILE = [(0.00, 2.80), (1.06, 2.80), (1.10, 2.84), (1.10, 2.96), (1.06, 3.00),
                (0.00, 3.00)]
HULL_FY = 1.08 * COS8           # the hull's front facet plane in its straight section

# porthole, built in its own frame (local +Z = out of the hull) and stood on the front facet
PORT_Z = 1.90
PORT_RING = [(0.42, -0.06), (0.42, 0.05), (0.39, 0.08), (0.31, 0.08), (0.28, 0.05),
             (0.28, 0.02), (0.00, 0.02)]
PORT_GLASS = [(0.00, -0.01), (0.275, -0.01), (0.275, 0.045), (0.00, 0.045)]
PORT_SEGS = 12

# fins: (radial distance u, height z) outlines, extruded +-thick/2 tangentially.  The inner
# edge (u 0.70) is buried in the hull/base; the tip at the outer bottom is the low point.
SIDE_FIN = [(0.70, 0.40), (1.58, 0.05), (1.72, 0.14), (1.72, 0.74), (1.62, 0.86),
            (0.70, 1.36)]
FRONT_FIN = [(0.70, 0.40), (1.34, 0.05), (1.46, 0.16), (1.46, 1.02), (1.36, 1.14),
             (0.70, 1.42)]
SIDE_FIN_T, FRONT_FIN_T = 0.22, 0.52
FIN_BEVEL = 0.045
FRONT_FACE_Y = 1.46             # the front fin's flat outer face
DOTS = [("DotYellow", "toy_yellow", 0.74, 0.28),     # (part, colour, z, size)
        ("DotOrange", "toy_orange", 0.36, 0.22)]

# ---------------------------------------------------------------- the cucumber head
HEAD_Z0, HEAD_H, HEAD_R = 2.60, 1.65, 0.78           # top at z 4.25
HEAD_PROFILE = [(0.00, 0.000), (1.00, 0.000), (1.00, 0.820), (0.95, 0.885),
                (0.85, 0.935), (0.68, 0.975), (0.48, 1.000), (0.00, 1.000)]
FY = HEAD_R * COS8              # the head's +Y facet plane (straight up to z 3.95)

NOSE_Z0 = 4.21                  # the cone sinks 0.04 into the head's flat top
NOSE_PROFILE = [(0.00, 0.00), (0.62, 0.00), (0.60, 0.16), (0.50, 0.46), (0.33, 0.72),
                (0.15, 0.89), (0.00, 0.95)]

# face, all on the +Y facet
EYE_X, EYE_Z, EYE_W, EYE_H = 0.19, 3.66, 0.28, 0.36
SHINE, SHINE_DX, SHINE_DZ = 0.10, 0.05, 0.085        # upper OUTER corner of each eye
SNOUT_LO = (-0.13, FY - 0.05, 3.28)
SNOUT_HI = (0.13, FY + 0.14, 3.46)
# open smile, flat top + rounded bottom, z 3.125-3.265: tucked under the snout (bottom
# 3.28) and kept above z 3.12, where the red band's lip starts to hide the facet from a
# camera looking down ~22 degrees
MOUTH_Z = 3.195
MOUTH_PTS = [(-0.15, 0.07), (0.15, 0.07), (0.12, -0.01), (0.06, -0.07),
             (-0.06, -0.07), (-0.12, -0.01)]
CHEEK_X, CHEEK_Z, CHEEK = 0.245, 3.34, 0.10

# speckles on the head: (height fraction of the head, facet).  Facet 1 (+Y) is the face.
HEAD_STUDS = [(0.43, 0), (0.46, 2), (0.70, 3), (0.66, 7), (0.47, 4), (0.44, 6),
              (0.64, 5)]

FRONT = (0.0, 1.0, 0.0)


def _fin(D, bm, outline, thick, yaw_deg):
    """One fin: `outline` in (u, z) extruded +-thick/2, every edge chamfered like a
    beveled_box, then swung so +u points along `yaw_deg` (0 = +X, 90 = +Y)."""
    pre = set(bm.verts)
    vs = D.prism(bm, outline, -thick / 2.0, thick / 2.0)
    vset = set(vs)
    edges = [e for e in bm.edges if e.verts[0] in vset and e.verts[1] in vset]
    faces = [f for f in bm.faces if all(v in vset for v in f.verts)]
    bmesh.ops.bevel(bm, geom=vs + edges + faces, offset=FIN_BEVEL, segments=1,
                    profile=0.5, affect='EDGES', clamp_overlap=True)
    bm.verts.ensure_lookup_table()
    live = [v for v in bm.verts if v not in pre]
    # Rx(90) stands the outline up (local y -> world z, extrusion -> tangential), then
    # Rz(yaw) swings local +x (the radial u) round to the fin's bearing.
    D.xform(bm, live, D.place((0.0, 0.0, 0.0), D.rot_euler(90.0, 0.0, yaw_deg)))


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    port_m = D.place((0.0, HULL_FY, PORT_Z), D.rot_euler(-90.0, 0.0, 0.0))  # +Z -> +Y

    # ---- blue: the stepped base + the porthole ring (same colour + material) ----
    bm = bmesh.new()
    D.lathe(bm, BASE_PROFILE, segs=SEGS, phase=PHASE)
    D.lathe(bm, PORT_RING, segs=PORT_SEGS, matrix=port_m)
    D.new_obj("Blue", bm, c, D.C("toy_blue"), rbx_material="SmoothPlastic")

    # ---- the porthole's recessed dark disc --------------------------------------
    bm = bmesh.new()
    D.lathe(bm, PORT_GLASS, segs=PORT_SEGS, matrix=port_m)
    D.new_obj("PortholeGlass", bm, c, D.C("toy_blue_dk"), rbx_material="SmoothPlastic")

    # ---- the white hull ---------------------------------------------------------
    bm = bmesh.new()
    D.lathe(bm, HULL_PROFILE, segs=SEGS, phase=PHASE)
    D.new_obj("Hull", bm, c, D.C("toy_white"), rbx_material="SmoothPlastic")

    # ---- red: top band, three fins, nose cone -----------------------------------
    bm = bmesh.new()
    D.lathe(bm, BAND_PROFILE, segs=SEGS, phase=PHASE)
    _fin(D, bm, SIDE_FIN, SIDE_FIN_T, 0.0)          # +X (screen-left)
    _fin(D, bm, SIDE_FIN, SIDE_FIN_T, 180.0)        # -X (screen-right)
    _fin(D, bm, FRONT_FIN, FRONT_FIN_T, 90.0)       # +Y, the front tab
    D.lathe(bm, NOSE_PROFILE, segs=SEGS, phase=PHASE,
            matrix=D.place((0.0, 0.0, NOSE_Z0)))
    D.new_obj("Red", bm, c, D.C("toy_red"), rbx_material="SmoothPlastic")

    # ---- the two squares on the front fin's face --------------------------------
    for part, key, z, size in DOTS:
        bm = bmesh.new()
        D.stud_patch(bm, (0.0, FRONT_FACE_Y, z), FRONT, size=size, rise=0.02,
                     sink=0.05, bevel=0.015)
        D.new_obj(part, bm, c, D.C(key), rbx_material="SmoothPlastic")

    # ---- the cucumber head + its snout ------------------------------------------
    head_m = D.place((0.0, 0.0, HEAD_Z0))
    bm = bmesh.new()
    D.cuke_body(bm, h=HEAD_H, r=HEAD_R, profile=HEAD_PROFILE, nub=None, matrix=head_m)
    D.beveled_box(bm, SNOUT_LO, SNOUT_HI, bevel=0.045)
    D.new_obj("Head", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=HEAD_H, r=HEAD_R, profile=HEAD_PROFILE, slots=HEAD_STUDS,
                 size=0.26, rise=0.055, matrix=head_m)
    D.new_obj("HeadStuds", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- face: eyes + open mouth + cheeks (one dark part), then the highlights --
    bm = bmesh.new()
    for s in (1.0, -1.0):
        D.stud_patch(bm, (s * EYE_X, FY, EYE_Z), FRONT, size=EYE_W, aspect=EYE_H / EYE_W,
                     rise=0.05, sink=0.07, bevel=0.035)
        D.stud_patch(bm, (s * CHEEK_X, FY, CHEEK_Z), FRONT, size=CHEEK, rise=0.03,
                     sink=0.05, bevel=0.02)
    D.prism(bm, MOUTH_PTS, -0.06, 0.04,
            matrix=D.place((0.0, FY, MOUTH_Z)) @ D.surface_frame(FRONT))
    D.new_obj("Eyes", bm, c, D.C("toy_eye"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for s in (1.0, -1.0):                            # +x eye's outer side is +x
        D.stud_patch(bm, (s * (EYE_X + SHINE_DX), FY + 0.05, EYE_Z + SHINE_DZ), FRONT,
                     size=SHINE, rise=0.02, sink=0.03, bevel=0.012)
    D.new_obj("EyeShine", bm, c, D.C("toy_eye_hl"), rbx_material="SmoothPlastic")

    return c
