"""Grass: the plain Cucumber - the whole set's reference silhouette."""
import bmesh, math

COLLECTION = "Cucumber"
NOTES = ("The base model every other cucumber in the set is a variation of: an 8-sided "
         "pillar 4.0 studs tall and 1.36 across, chamfered top and bottom, with a small "
         "square stem nub on its head and 18 raised light-green speckles scattered over "
         "its skin.  Facet 1 faces +Y.  Two parts: Body (with the nub) and Studs.")


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=7, per_row=3, z0=0.11, z1=0.90,
                 size=0.28, rise=0.055, seed=7)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    return c
