"""Desert: Desert Palm - a stepped tan trunk crowned with seven drooping fronds."""
import bmesh, math

COLLECTION = "DesertPalm"
NOTES = ("A crown-heavy desert palm: a SHORT chunky trunk under a wide canopy.  A "
         "two-step dark-brown plinth (2.1 across at the ground), then FOUR stacked tan "
         "trunk segments that taper 1.35 -> 0.87 across and drift a little toward +X so "
         "the trunk reads as chunky stepped segments rather than a smooth cone, topping "
         "out at z 10.30, then a short tapered collar at z 10.20-10.68 that the crown "
         "sprouts from.  Seven LONG serrated fronds (length ~ 3.8-3.9, width 0.85, droop "
         "2.2, pitch ~ 26) spray out every 51.4 deg with their bases at z ~ 10.3-10.5, "
         "arching up ~ 0.4 then falling away so every tip hangs to z ~ 6.4-6.9, clearly "
         "below its root - the four front ones in des_frond, the three back ones "
         "(yaw 218/270/321) in des_frond_dk so the crown has depth.  That makes the crown "
         "~ 8.5 across, about as wide as the tree is tall, so the palm reads as mostly "
         "canopy.  Two coconuts sit tucked under the crown on the camera (+Y) side at "
         "z ~ 6.5.  Footprint ~ 8.5 x 8.4, 7.7 tall, faces +Y, centred on x=0/y=0.  "
         "NOTE the height: a drooping frond can only rise ~ 0.4 above its root, so with "
         "the trunk top at ~ 6.8 the model tops out at ~ 7.7 rather than the 11-13 of the "
         "other trees - carrying a crown this wide AND a 12-stud top would put the crown "
         "root back at z ~ 11 and return the totem-pole silhouette.  FIVE parts: Base "
         "(the plinth PLUS the dark speckles up the trunk - same colour and material, so "
         "one object), Trunk, Fronds, FrondsBack, Coconuts.  The fronds are placed with "
         "matrices, so dryrun's bounding box and its min_z warning are local-space "
         "artefacts; no real geometry sits below z = 0.")

# six stacked trunk segments - chunky and stepped, tall enough to keep the palm
# in the set's 11-13 tree band while the big crown still dominates the top third:
# (z0, z1, width, centre x, centre y)
TRUNK = [
    (1.50, 3.00, 1.38, 0.00, 0.00),
    (2.96, 4.43, 1.28, 0.05, -0.02),
    (4.39, 5.86, 1.18, 0.09, -0.03),
    (5.82, 7.29, 1.08, 0.12, -0.04),
    (7.25, 8.72, 0.97, 0.15, -0.03),
    (8.68, 10.30, 0.87, 0.16, -0.02),
]

CROWN = (0.16, -0.02, 10.30)         # top of the trunk, where the fronds spring from

# (yaw deg, length, pitch deg, droop, base z, is a back frond)
FRONDS = [
    (12.86, 3.88, 26.0, 2.20, 10.32, False),
    (64.29, 3.80, 25.0, 2.15, 10.30, False),
    (115.71, 3.82, 25.0, 2.15, 10.30, False),
    (167.14, 3.90, 26.0, 2.18, 10.33, False),
    (218.57, 3.84, 28.0, 2.20, 10.44, True),
    (270.00, 3.92, 30.0, 2.20, 10.48, True),
    (321.43, 3.86, 28.0, 2.18, 10.44, True),
]

COCONUTS = [(0.60, 0.30, 9.86), (0.02, 0.52, 9.72)]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---- plinth, plus the dark scar speckles up the trunk -------------------
    bm = bmesh.new()
    D.stepped_base(bm, top_w=1.5, h=1.5, steps=2, grow=1.4, bevel=0.09)
    for i, (z0, z1, w, cx, cy) in enumerate(TRUNK):
        # the top segment keeps its front face clear - the coconuts hang there
        faces = ("+x", "-x") if i == len(TRUNK) - 1 else ("+y", "+x", "-x")
        D.box_studs(bm, (cx - w / 2, cy - w / 2, z0), (cx + w / 2, cy + w / 2, z1),
                    faces=faces, grid=(1, 2), size=0.30, rise=0.06,
                    seed=11 + i, margin=0.30)
    D.new_obj("Base", bm, c, D.C("des_trunk_dk"), rbx_material="Wood")

    # ---- the stepped trunk ---------------------------------------------------
    bm = bmesh.new()
    for (z0, z1, w, cx, cy) in TRUNK:
        D.beveled_box(bm, (cx - w / 2, cy - w / 2, z0), (cx + w / 2, cy + w / 2, z1),
                      bevel=0.10)
    D.branch_box(bm, (CROWN[0], CROWN[1], CROWN[2] - 0.10),
                 (CROWN[0], CROWN[1], CROWN[2] + 0.38), 0.92, 0.58, bevel=0.06)
    D.new_obj("Trunk", bm, c, D.C("des_trunk"), rbx_material="Wood")

    # ---- the crown of fronds -------------------------------------------------
    bm = bmesh.new()          # front fronds
    bmb = bmesh.new()         # the darker back ones
    for (yaw, length, pitch, droop, bz, back) in FRONDS:
        a = math.radians(yaw)
        base = (CROWN[0] + 0.22 * math.cos(a), CROWN[1] + 0.22 * math.sin(a), bz)
        D.palm_frond(bmb if back else bm, base=base, yaw_deg=yaw, pitch_deg=pitch,
                     length=length, width=0.85, thick=0.12, droop=droop, n=7, teeth=0.30)
    D.new_obj("Fronds", bm, c, D.C("des_frond"), rbx_material="LeafyGrass")
    D.new_obj("FrondsBack", bmb, c, D.C("des_frond_dk"), rbx_material="LeafyGrass")

    # ---- coconuts under the crown -------------------------------------------
    bm = bmesh.new()
    for (x, y, z) in COCONUTS:
        D.uvsphere(bm, (x, y, z), 0.30, segs=8, rings=5)
    D.new_obj("Coconuts", bm, c, D.C("des_coconut"), rbx_material="Wood")

    return c
