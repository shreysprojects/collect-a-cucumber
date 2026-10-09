"""Desert: the Prickly Cucumber - a green body bristling with cream desert spines."""
import bmesh, math

COLLECTION = "DesertPricklyCucumber"
NOTES = ("A standard 4.0-tall cucumber body in cuke_green, still clearly a cucumber, "
         "wearing 15 hard cream spines that point out and slightly UP - 5 rows of 3, "
         "snapped to the 8 body facets so they ring it evenly, tips reaching about 0.93 "
         "from the axis.  Between them 12 dull olive speckles (rows=6, per_row=2, "
         "size=0.24) so the skin still shows; any speckle that would have landed under a "
         "spine base is slid up or down its own facet until it is clear, so nothing "
         "interpenetrates.  Footprint ~1.9 x 1.9, total height 4.30 to the top of the "
         "stem nub.  Centred on x=0, y=0, nothing below z=0, facet 1 faces +Y.  "
         "3 parts: Body (pillar + nub), Studs, Spikes.")

SPIKE_ROWS, SPIKE_PER_ROW = 5, 3
SPIKE_Z0, SPIKE_Z1 = 0.14, 0.88
SPIKE_SEED = 4

STUD_ROWS, STUD_PER_ROW = 6, 2
STUD_Z0, STUD_Z1 = 0.11, 0.90
STUD_SEED = 7

GAP = 0.085                          # clear height-fraction gap between a stud and a spine


def _slide(zf, facet, spikes, lo=0.07, hi=0.94):
    """Nearest height fraction on this facet that clears every spine base on it."""
    near = sorted(z for z, f in spikes if f == facet)
    cands = [zf] + [z - GAP for z in near] + [z + GAP for z in near]
    best, best_d = None, 1e9
    for cand in cands:
        if cand < lo or cand > hi:
            continue
        if all(abs(cand - z) >= GAP - 1e-6 for z in near):
            d = abs(cand - zf)
            if d < best_d:
                best, best_d = cand, d
    return zf if best is None else best


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    h, r = D.CUKE_H, D.CUKE_R

    # ---------------------------------------------------------------- body
    bm = bmesh.new()
    D.cuke_body(bm, h=h, r=r, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---------------------------------------------------------------- speckles
    # Exactly the slots `spike_ring` will use below (same rows / seed / jitter),
    # so the studs can be nudged off them.
    spikes = D.cuke_stud_slots(SPIKE_ROWS, SPIKE_PER_ROW, SPIKE_Z0, SPIKE_Z1,
                               D.CUKE_SEGS, True, SPIKE_SEED, 0.012)

    slots = D.cuke_stud_slots(STUD_ROWS, STUD_PER_ROW, STUD_Z0, STUD_Z1,
                              D.CUKE_SEGS, True, STUD_SEED, 0.018)
    slots = [(_slide(zf, facet, spikes), facet) for zf, facet in slots]

    bm = bmesh.new()
    D.cuke_studs(bm, h=h, r=r, size=0.24, rise=0.05, slots=slots)
    D.new_obj("Studs", bm, c, D.C("des_olive"), rbx_material="SmoothPlastic")

    # ---------------------------------------------------------------- spines
    bm = bmesh.new()
    D.spike_ring(bm, h=h, r=r, rows=SPIKE_ROWS, per_row=SPIKE_PER_ROW,
                 z0=SPIKE_Z0, z1=SPIKE_Z1, length=0.34, base_r=0.15,
                 segs_spike=4, droop=-0.15, seed=SPIKE_SEED)
    D.new_obj("Spikes", bm, c, D.C("des_spike"), rbx_material="Sandstone",
              roughness=0.72)

    return c
