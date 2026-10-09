"""Farm: the Muddy Cucumber - a fresh cucumber straight out of the field, splattered."""
import bmesh, math

COLLECTION = "FarmMuddyCucumber"
NOTES = ("A standard 4.0-tall cuke_green body (1.36 across, stem nub on top, 4.30 to the "
         "top of the nub) wearing 11 dark farm_mud splats and 5 smaller farm_mud_lt "
         "highlights on top of them, so the mud reads two-tone rather than as flat "
         "stickers.  The splats are square patches snapped to the 8 body facets, each a "
         "different size (0.26-0.50 wide), squashed or stretched vertically (aspect "
         "0.68-1.40) and spun in the skin plane (+/- 34 deg) so no two are alike; 7 of "
         "the 11 sit below zf 0.36 - the cucumber is dirty from the ground UP.  Nine of "
         "them are on the five front-facing facets (7, 0, 1, 2, 3) so the splatter reads "
         "from the camera; two on the back give it depth.  All 21 standard cuke_stud "
         "speckles are kept, but the three whose facet slots landed under a splat are "
         "slid up or down their own facet until they clear it, so nothing z-fights and "
         "no clean skin is lost.  Footprint ~1.47 x 1.47, height 4.30 (lowest mud "
         "z = 0.17).  "
         "Centred on x=0, y=0, nothing below z=0, facet 1 faces +Y.  "
         "4 parts: Body (pillar + nub), Studs, Mud, MudHighlights.")

# --------------------------------------------------------------------------- mud
# (height fraction, facet, size, aspect, spin degrees).  Facet 1 is +Y (the front),
# 0 = +45, 2 = 135, 3 = -X, 7 = +X; 5 and 6 are round the back.
MUD = [
    (0.10, 1, 0.50, 0.80,   8.0),      # the big one, low on the front
    (0.15, 0, 0.44, 1.25, -18.0),
    (0.12, 7, 0.36, 0.72,  24.0),
    (0.21, 2, 0.46, 1.05,  13.0),
    (0.27, 3, 0.34, 0.88, -30.0),
    (0.32, 1, 0.34, 1.40,  17.0),      # a run dribbling up the front
    (0.35, 6, 0.38, 0.78,  27.0),
    (0.44, 0, 0.30, 1.15, -13.0),
    (0.50, 5, 0.32, 0.92,  33.0),
    (0.63, 2, 0.28, 1.30, -23.0),
    (0.81, 1, 0.26, 0.68,  19.0),      # one high fleck
]

# Lighter second layer: (index into MUD, tangent offset, z offset, size, aspect, spin).
MUD_LT = [
    (0,  0.08, -0.03, 0.20, 1.10,  34.0),
    (1, -0.07,  0.09, 0.18, 0.85, -22.0),
    (2,  0.05,  0.00, 0.16, 1.05, -30.0),
    (3,  0.08,  0.07, 0.19, 1.20,  15.0),
    (5, -0.05, -0.05, 0.15, 0.90,  40.0),
]

MUD_RISE, MUD_LT_RISE = 0.060, 0.105

STUD_ROWS, STUD_PER_ROW = 7, 3
STUD_Z0, STUD_Z1, STUD_SIZE = 0.11, 0.90, 0.28
STUD_SEED = 7


def _blocked(h):
    """Per facet, the height-fraction spans a speckle must keep out of."""
    out = {}
    half_stud = STUD_SIZE / 2.0
    for zf, facet, size, aspect, spin in MUD:
        a = math.radians(spin)
        # vertical half-extent of the spun patch, in world studs, then in zf
        v = (size * aspect / 2.0) * abs(math.cos(a)) + (size / 2.0) * abs(math.sin(a))
        pad = (v + half_stud) / float(h) + 0.012
        out.setdefault(facet, []).append((zf - pad, zf + pad))
    return out


def _clear(zf, facet, blocked, lo=0.07, hi=0.94):
    """Nearest height fraction on this facet clear of every splat, or None."""
    spans = blocked.get(facet, [])
    if all(not (a <= zf <= b) for a, b in spans):
        return zf
    cands = []
    for a, b in spans:
        cands += [a - 1e-4, b + 1e-4]
    best, best_d = None, 1e9
    for cand in cands:
        if cand < lo or cand > hi:
            continue
        if any(a <= cand <= b for a, b in spans):
            continue
        d = abs(cand - zf)
        if d < best_d:
            best, best_d = cand, d
    return best


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    h, r = D.CUKE_H, D.CUKE_R

    # ---------------------------------------------------------------- body
    bm = bmesh.new()
    D.cuke_body(bm, h=h, r=r, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---------------------------------------------------------------- speckles
    # Standard scatter, then anything buried under a splat is slid along its own
    # facet until it is clear (dropped if it cannot be).
    blocked = _blocked(h)
    slots = []
    for zf, facet in D.cuke_stud_slots(STUD_ROWS, STUD_PER_ROW, STUD_Z0, STUD_Z1,
                                       D.CUKE_SEGS, True, STUD_SEED, 0.018):
        moved = _clear(zf, facet, blocked)
        if moved is not None:
            slots.append((moved, facet))

    bm = bmesh.new()
    D.cuke_studs(bm, h=h, r=r, size=STUD_SIZE, rise=0.055, slots=slots)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---------------------------------------------------------------- mud
    bm = bmesh.new()
    points = []
    for zf, facet, size, aspect, spin in MUD:
        p, n = D.cuke_facet_point(h=h, r=r, zf=zf, facet=facet)
        points.append((p, n, facet))
        D.stud_patch(bm, p, n, size=size, rise=MUD_RISE, sink=0.075,
                     bevel=0.035, aspect=aspect, spin=spin)
    D.new_obj("Mud", bm, c, D.C("farm_mud"), rbx_material="Mud", roughness=0.92)

    # ---------------------------------------------------------------- mud highlights
    bm = bmesh.new()
    for idx, dx, dz, size, aspect, spin in MUD_LT:
        p, n, facet = points[idx]
        a = D.cuke_facet_angle(facet, D.CUKE_SEGS)
        tx, ty = -math.sin(a), math.cos(a)          # tangent, in the skin plane
        q = (p[0] + tx * dx, p[1] + ty * dx, p[2] + dz)
        D.stud_patch(bm, q, n, size=size, rise=MUD_LT_RISE, sink=0.09,
                     bevel=0.03, aspect=aspect, spin=spin)
    D.new_obj("MudHighlights", bm, c, D.C("farm_mud_lt"), rbx_material="Mud",
              roughness=0.88)

    return c
