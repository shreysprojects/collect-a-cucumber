"""Underwater: Bubble Slice - the SlicedCucumber group blown in glass, like drifting bubbles."""
import bmesh, math

COLLECTION = "UnderwaterBubbleSlice"
NOTES = ("The SlicedCucumber arrangement as glassy bubbles: four cut discs grouped on the "
         "ground - a big one STANDING with its cut face to +Y, a second tipped back "
         "against it, and two lying flat in front.  Every disc is run at segs=14 with a "
         "fat 0.09 rim chamfer instead of the usual 10-sided coin, so the rims read round "
         "and blown rather than cut.  Rim is mid aqua glass (sea_bubble, Roblox material "
         "Glass, transparency 0.42) speckled with the set's raised squares in pale "
         "ice-blue (sea_bubble_lt, Glass, transparency 0.15 - nearly solid, so the "
         "speckle still reads against the see-through rim); the cut face is the same pale "
         "blue blown thinner (sea_bubble_lt, Glass, transparency 0.35) and the five ring "
         "pips plus the centre one are OPAQUE white (snow_white, SmoothPlastic) - the one "
         "solid thing in the model, so the pips read as light caught inside the bubble.  "
         "Four parts, ~3.2 x 2.4 x 1.8 studs, sitting on z = 0.  Every disc is placed "
         "with a matrix, so dryrun's bounding box and its min_z warning are not "
         "meaningful here; the two lying discs rest exactly on the ground (centre height "
         "= half thickness).")

SEGS = 14           # rounder than the standard 10 - these are bubbles, not coins
RIM_BEVEL = 0.09    # a fat chamfer on the rim so the edge catches light like glass

# kind, (x, y, z), lean/tilt, turn/spin, radius, thickness, seed
DISCS = [
    ("stand", (0.50, -0.10, 0.86), -6.0, -12.0, 0.86, 0.44, 3),
    ("stand", (-0.66, 0.14, 0.62), 28.0, -34.0, 0.70, 0.40, 5),
    ("lay",   (-0.02, 1.02, 0.21), 0.0, 22.0, 0.74, 0.42, 9),
    ("lay",   (-1.38, 0.74, 0.19), 0.0, -38.0, 0.60, 0.38, 11),
]


def _discs(D):
    """(matrix, radius, thickness, seed) for each disc, in the SlicedCucumber layout."""
    out = []
    for kind, loc, lean, turn, rad, th, seed in DISCS:
        m = (D.slice_stand(loc, lean_deg=lean, turn_deg=turn) if kind == "stand"
             else D.slice_lay(loc, tilt_deg=lean, spin_deg=turn))
        out.append((m, rad, th, seed))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _discs(D)

    # --- the skin, blown in aqua glass: 14-sided drums with a fat rounded chamfer --
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_disc(bm, radius=rad, thick=th, segs=SEGS, matrix=m, bevel=RIM_BEVEL)
    D.new_obj("Rims", bm, c, D.C("sea_bubble"), rbx_material="Glass",
              transparency=0.42, roughness=0.32)

    # --- the set's speckle, here reading as highlights on the bubble's skin --------
    bm = bmesh.new()
    for m, rad, th, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, segs=SEGS, matrix=m, n=5, size=0.21,
                      rise=0.045, seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("sea_bubble_lt"), rbx_material="Glass",
              transparency=0.15, roughness=0.32)

    # --- the cut face: the same pale blue blown thinner, proud inside the rim ------
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_face(bm, radius=rad, thick=th, segs=SEGS, matrix=m, inset=0.11,
                     proud=0.025)
    D.new_obj("Faces", bm, c, D.C("sea_bubble_lt"), rbx_material="Glass",
              transparency=0.35, roughness=0.32)

    # --- pips: the one OPAQUE thing here, so the face still reads as a slice -------
    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=5, size=0.175, ring=0.42,
                      proud=0.03)
    D.new_obj("Seeds", bm, c, D.C("snow_white"), rbx_material="SmoothPlastic",
              roughness=0.32)

    return c
