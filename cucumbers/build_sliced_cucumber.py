"""Grass: Sliced Cucumber - one big disc standing, one leaning on it, two lying flat."""
import bmesh, math

COLLECTION = "SlicedCucumber"
NOTES = ("Four cut discs grouped on the ground: a big one STANDING with its cut face to "
         "+Y, a second tipped back against it, and two lying flat in front.  Dark-green "
         "rim with light-green speckles, pale yellow-green cut face with five square "
         "pips in a ring plus one in the middle.  Four parts, ~3.2 x 2.4 x 1.8 studs.")

# kind, (x, y, z), lean/tilt, turn/spin, radius, thickness, seed
DISCS = [
    ("stand", (0.50, -0.10, 0.86), -6.0, -12.0, 0.86, 0.44, 3),
    ("stand", (-0.66, 0.14, 0.62), 28.0, -34.0, 0.70, 0.40, 5),
    ("lay",   (-0.02, 1.02, 0.21), 0.0, 22.0, 0.74, 0.42, 9),
    ("lay",   (-1.38, 0.74, 0.19), 0.0, -38.0, 0.60, 0.38, 11),
]


def _discs(D):
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

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("cuke_dark"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for m, rad, th, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=5, size=0.21, rise=0.045,
                      seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.11)
    D.new_obj("Faces", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    for m, rad, th, _s in discs:
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=5, size=0.175, ring=0.42)
    D.new_obj("Seeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    return c
