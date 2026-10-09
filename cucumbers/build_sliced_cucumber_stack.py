"""Grass: Sliced Cucumber Stack - four cut discs piled flat, each turned and nudged."""
import bmesh, math

COLLECTION = "SlicedCucumberStack"
NOTES = ("A neat pile of FOUR cut discs lying flat, one on top of another.  Each disc is "
         "spun a little about Z (0, 22, -16, 38 degrees) and nudged ~0.09 studs sideways "
         "from the one below, so the stack leans and every rim stays visible.  Bottom "
         "disc r 0.82, each one above 0.97x the one below; the discs are chunky pucks "
         "(0.68 -> 0.62 thick) so four of them make the 2.7-stud tower.  Dark-green rims "
         "with light-green square speckles, pale yellow-green cut faces with five pips in "
         "a ring plus one in the middle on BOTH faces of every disc - only the top disc's "
         "really show, the rest peek out of the joins.  Four parts, ~1.9 x 1.7 x 2.75 "
         "studs, nothing below z = 0 (the stack is lifted 0.05 so the underside pips of "
         "the bottom disc clear the ground).")

GAP = 0.02      # hairline between discs so the proud cut faces read as separate slices
LIFT = 0.05     # keeps the bottom disc's underside face + pips off the ground plane

# (x, y) centre, spin about Z (deg), radius, thickness, rim-speckle seed - bottom first
DISCS = [
    ((-0.09,  0.02),   0.0, 0.820, 0.68, 3),
    ((-0.01, -0.02),  22.0, 0.795, 0.66, 5),
    (( 0.08, -0.06), -16.0, 0.771, 0.64, 9),
    (( 0.16, -0.09),  38.0, 0.748, 0.62, 11),
]


def _stack(D):
    """Lay the discs up the z axis, each resting on the one below with a hairline gap."""
    out, z = [], LIFT
    for (x, y), spin, rad, th, seed in DISCS:
        cz = z + th / 2.0
        out.append((D.slice_lay((x, y, cz), spin_deg=spin), rad, th, seed))
        z = cz + th / 2.0 + GAP
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _stack(D)

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("cuke_dark"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for m, rad, th, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=5, size=0.24, rise=0.05,
                      seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.11, both=True)
    D.new_obj("Faces", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=5, size=0.175, ring=0.42,
                      both=True)
    D.new_obj("Seeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    return c
