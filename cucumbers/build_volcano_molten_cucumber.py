"""Volcano: the Molten Cucumber - a GREEN cucumber with lava pouring down it from the top."""
import bmesh, math

COLLECTION = "VolcanoMoltenCucumber"
NOTES = (
    "A perfectly ordinary green cucumber that has had molten rock poured over its head.  "
    "The body is the set's standard pillar - cuke_green, h 4.0, r 0.68, SmoothPlastic, "
    "with the usual (0.30, 0.30) stem nub - and it keeps its cuke_stud speckles, so it "
    "reads as the same fruit as the grass-biome Cucumber; the volcano is an OVERLAY, not "
    "a recolour, and roughly two thirds of the green is still visible.\n"
    "Over its head sits a lava cap: an 8-sided lathe in phase with the body's facets, "
    "starting buried inside the body at zf 0.858, swelling out to an overhanging lip at "
    "1.10 x the body radius (z 3.74) and doming up to a rim at z 4.68 that folds back "
    "into a shallow molten dish - vol_lava (ff6a1e), Neon at emit 0.95, the vivid orange "
    "of the reference rather than the pale yellow a higher emit washes it out to.\n"
    "Six drips run out from under that lip and down the skin, each a 4-point tube that "
    "hugs the body (D.cuke_point offset 0.045) and tapers 0.125-0.155 down to 0.05: the "
    "hero drip runs down the dead-front facet all the way to zf 0.34, the two flanking "
    "front drips stop at 0.42 and 0.50, and the +X / -X / back drips stop at 0.56-0.58 so "
    "the pour reads on the silhouette from every side.  The drips share vol_lava/Neon with "
    "the cap, so per the merge rule they are ONE object (LavaFlow) - the cap and what runs "
    "off it are one flow.\n"
    "A hotter vol_lava_hot (ffa42b, Neon emit 1.15) piece picks out the two places the "
    "lava is still liquid: a narrow band standing proud of the overhanging lip, and the "
    "little pool sitting in the dish at the summit.\n"
    "Sixteen cuke_stud speckles are placed by hand rather than scattered, every one on a "
    "facet the lava does not cover, so no speckle is wasted under a drip: a full ring "
    "round the lower body and then only the two back facets (4 and 6) above zf 0.5.\n"
    "4 parts (Body, Studs, LavaFlow, LavaLip), 4 colours, about 1.75 x 1.75 x 4.68 studs, "
    "centred on x = 0 / y = 0, facing +Y, nothing below z = 0.  The drips and speckles are "
    "placed with surface maths and matrices, so dryrun's bounding box is an approximation."
)

# ---------------------------------------------------------------- the lava cap
# (radius / CUKE_R, z / CUKE_H).  Buried in the body at the bottom, out over the lip,
# up to the rim - the top of the model at 1.170 H = 4.68 - then back down into the dish.
CAP = [
    (0.00, 0.858),      # a flat underside, hidden inside the body's shoulder
    (0.74, 0.858),
    (1.02, 0.888),      # out past the skin
    (1.10, 0.934),      # the overhanging lip the drips leave from
    (1.05, 0.992),
    (0.92, 1.060),
    (0.70, 1.124),
    (0.44, 1.170),      # the rim
    (0.30, 1.156),      # ... and back down inside
    (0.00, 1.142),
]

# The proud band round the lip, and the pool sitting in the dish - both vol_lava_hot.
LIP_BAND = [(1.055, 0.898), (1.150, 0.932), (1.055, 0.966)]
POOL = [(0.00, 1.134), (0.40, 1.138), (0.40, 1.152), (0.00, 1.158)]

# ---------------------------------------------------------------- the drips
LIP_R, LIP_Z = 1.045, 0.922     # where a drip leaves the cap (fractions of R / H)
SHOULDER_ZF = 0.845             # where it first touches the body's skin
HUG = 0.045                     # how far proud of the skin the drip's spine runs

# (body facet, height fraction it reaches, sideways wobble deg, radius at the top).
# Facet 1 = +Y (dead front), 0 = 45 deg, 2 = 135, 7 = +X, 3 = -X, 5 = the back.
DRIPS = [
    (1, 0.34, -6.0, 0.155),     # the hero: longest and fattest, straight down the front
    (0, 0.50,  5.0, 0.140),
    (2, 0.42, -4.0, 0.145),
    (7, 0.58,  6.0, 0.125),     # the flanks read on the silhouette
    (3, 0.56, -5.0, 0.130),
    (5, 0.48,  4.0, 0.135),     # one round the back so it pours from every side
]

# ---------------------------------------------------------------- the speckles
# (height fraction, facet).  Hand-placed so none is buried under a drip: facets 4 and 6
# carry no lava at all, the rest are only used below where their drip ends.
STUDS = [
    (0.12, 1), (0.15, 7), (0.18, 4), (0.22, 2), (0.25, 0), (0.28, 6),
    (0.31, 3), (0.34, 5), (0.38, 7), (0.41, 0), (0.44, 4), (0.47, 3),
    (0.52, 6), (0.58, 4), (0.66, 6), (0.74, 4),
]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R, SEGS = D.CUKE_H, D.CUKE_R, D.CUKE_SEGS
    ph = D.cuke_phase(SEGS)

    # ---- the cucumber, entirely ordinary ----------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic",
              roughness=0.52)

    # ---- its speckles, kept off the lava ----------------------------------
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, size=0.28, rise=0.055, slots=STUDS)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic",
              roughness=0.52)

    # ---- the cap and everything that runs off it (one colour, one object) --
    bm = bmesh.new()
    D.lathe(bm, [(rr * R, zz * H) for rr, zz in CAP], segs=SEGS, phase=ph)

    for facet, end_zf, wobble, rtop in DRIPS:
        deg = math.degrees(D.cuke_facet_angle(facet, SEGS))
        a = math.radians(deg)
        mid_zf = end_zf + (SHOULDER_ZF - end_zf) * 0.45
        pts = [
            (math.cos(a) * LIP_R * R, math.sin(a) * LIP_R * R, LIP_Z * H),
            D.cuke_point(h=H, r=R, zf=SHOULDER_ZF, angle_deg=deg + wobble * 0.15,
                         offset=HUG),
            D.cuke_point(h=H, r=R, zf=mid_zf, angle_deg=deg + wobble * 0.60, offset=HUG),
            D.cuke_point(h=H, r=R, zf=end_zf, angle_deg=deg + wobble, offset=HUG),
        ]
        D.tube(bm, pts, [rtop, rtop * 0.86, rtop * 0.55, 0.05], segs=6)

    D.new_obj("LavaFlow", bm, c, D.C("vol_lava"), rbx_material="Neon", emit=0.65)

    # ---- the two places it is still liquid --------------------------------
    bm = bmesh.new()
    D.lathe(bm, [(rr * R, zz * H) for rr, zz in LIP_BAND], segs=SEGS, phase=ph)
    D.lathe(bm, [(rr * R, zz * H) for rr, zz in POOL], segs=SEGS, phase=ph)
    D.new_obj("LavaLip", bm, c, D.C("vol_lava_hot"), rbx_material="Neon", emit=0.65)

    return c
