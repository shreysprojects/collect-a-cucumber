"""Samurai: Sliced Cucumber - three big cut discs with two garden stones at the base."""
import bmesh, math

COLLECTION = "SamuraiSlicedCucumber"
NOTES = ("Three cut discs, bigger than the grass set's four: one STANDING at the back "
         "(r 0.88) with its cut face to +Y and leaning back 7 degrees, and two lying "
         "flat in front of it (r 0.80 and r 0.72), each spun a different way so all "
         "three rims read.  Standard grass slice colours - dark-green rim, light-green "
         "rim speckles, pale cut face, five square pips in a ring plus one in the "
         "middle.  What makes it samurai rather than grass: two small grey sam_rock "
         "garden stones (0.47 and 0.37 across) set at the base, one out to screen-left "
         "behind the near disc, one to screen-right in front, like the raked stones of "
         "a zen garden.  Five parts, ~3.3 x 2.3 x 1.8 studs, nothing below z = 0.")

# kind, (x, y, z), lean/tilt, turn/spin, radius, thickness, seed
DISCS = [
    ("stand", (0.18, -0.34, 0.92), 7.0, -13.0, 0.88, 0.46, 3),
    ("lay", (-0.62, 0.50, 0.26), 0.0, 24.0, 0.80, 0.44, 7),
    ("lay", (0.80, 0.92, 0.24), 0.0, -37.0, 0.72, 0.40, 11),
]

# (x, y, z), radius, (sx, sy, sz), spin_deg, seed
STONES = [
    ((-1.34, -0.32, 0.20), 0.20, (1.18, 1.00, 0.74), 24.0, 21),
    ((1.42, 0.18, 0.18), 0.17, (1.10, 1.06, 0.78), -38.0, 29),
]

REF_R = 0.80            # the set's standard slice radius - detail sizes scale off it


def _discs(D):
    """(matrix, radius, thickness, seed, standing?) for every disc in the group."""
    out = []
    for kind, loc, lean, turn, rad, th, seed in DISCS:
        stand = kind == "stand"
        m = (D.slice_stand(loc, lean_deg=lean, turn_deg=turn) if stand
             else D.slice_lay(loc, tilt_deg=lean, spin_deg=turn))
        out.append((m, rad, th, seed, stand))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _discs(D)

    # ---- the dark skin of every slice ------------------------------------------
    bm = bmesh.new()
    for m, rad, th, _s, _st in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("cuke_dark"), rbx_material="SmoothPlastic")

    # ---- the set's signature speckles, on the rims ------------------------------
    bm = bmesh.new()
    for m, rad, th, seed, _st in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=5, size=0.21 * rad / REF_R,
                      rise=0.045, seed=seed)
    D.new_obj("RimStuds", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- the pale cut faces ------------------------------------------------------
    bm = bmesh.new()
    for m, rad, th, _s, _st in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.11)
    D.new_obj("Faces", bm, c, D.C("cuke_pale"), rbx_material="SmoothPlastic")

    # ---- the pips.  Both faces on the standing disc (its back edge shows with the
    #      13-degree turn); top face only on the two that lie face-down on the ground.
    bm = bmesh.new()
    for m, rad, th, _s, stand in discs:
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=5,
                      size=0.175 * rad / REF_R, ring=0.42, both=stand)
    D.new_obj("Seeds", bm, c, D.C("cuke_seed"), rbx_material="SmoothPlastic")

    # ---- the two zen-garden stones ----------------------------------------------
    bm = bmesh.new()
    for loc, rad, scale, spin, seed in STONES:
        D.rock(bm, loc, rad, seed=seed, jitter=0.27, subdiv=1, scale=scale,
               rot=D.rot_euler(0.0, 0.0, spin))
    D.new_obj("Stones", bm, c, D.C("sam_rock"), rbx_material="Rock", roughness=0.72)

    return c
