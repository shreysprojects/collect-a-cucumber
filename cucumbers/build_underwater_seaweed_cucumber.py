"""Underwater: a cucumber whose skin ripples up and down like a frond of kelp."""
import bmesh, math

COLLECTION = "UnderwaterSeaweedCucumber"
NOTES = ("A 4.0-tall cucumber, ~1.55 across, whose sides RIPPLE like kelp: instead of "
         "cuke_body it is a 10-sided lathe of the standard CUKE_PROFILE resampled over 22 "
         "rows with every radius multiplied by 1 + 0.13*sin(zf*7*pi), so three and a half "
         "waves of bulge-and-waist run up the body.  Facet 1 still faces +Y (lathe phase "
         "36 deg).  A 0.30 stem nub on top takes it to z 4.38.  Twelve cuke_stud speckles "
         "(rows=6, per_row=2) sit on the facet centres, and four thin sea_weed_dk fin "
         "ridges run from zf 0.10 to 0.90 at angles 0, 72, 180 and 252 deg - the 0 and 180 "
         "pair sit dead on the screen-left / screen-right silhouette so the ripple reads "
         "as a wavy outline from 40 studs away.  Nothing below z = 0; 3 parts.")

SEGS = 10                        # a 10-sided body - rounder than the standard 8
PHASE = math.pi / 5.0            # 36 deg: puts facet 1 square on +Y, as the set expects
ROWS = 22                        # profile rows the ripple is sampled over
WOBBLE = 0.13                    # ripple amplitude as a fraction of the local radius
WAVES = 7.0                      # half-waves of sine up the height
NUB = (0.30, 0.38)               # stem cube on the head
FIN_ANGLES = (0.0, 72.0, 180.0, 252.0)


def _ripple_profile(D, rows=ROWS, amp=WOBBLE):
    """CUKE_PROFILE resampled over `rows` rows with a sine wobble on every radius.

    Returns (radius_fraction, height_fraction) pairs - the same units CUKE_PROFILE uses,
    so it can be handed straight to cuke_studs / surface_line as `profile=`."""
    prof = []
    for i in range(rows):
        zf = i / float(rows - 1)
        rf = D.cuke_radius(zf) * (1.0 + amp * math.sin(zf * WAVES * math.pi))
        prof.append((max(0.0, rf), zf))
    return prof


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R
    prof = _ripple_profile(D)

    # ---------------------------------------------------------------- body
    # The set's silhouette, lathed with a radius that swells and pinches up the height.
    bm = bmesh.new()
    D.lathe(bm, [(rf * R, zf * H) for rf, zf in prof], segs=SEGS, phase=PHASE, cap=True)
    top = prof[-1][1] * H
    nw, nh = NUB
    D.beveled_box(bm, (-nw / 2.0, -nw / 2.0, top - 0.03),
                  (nw / 2.0, nw / 2.0, top + nh), bevel=0.045)
    D.new_obj("Body", bm, c, D.C("sea_weed"), rbx_material="LeafyGrass")

    # ---------------------------------------------------------------- speckles
    # The set's signature raised squares, snapped to this body's 10 facet centres.
    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, rows=6, per_row=2, z0=0.12, z1=0.88,
                 size=0.28, rise=0.055, segs=SEGS, phase=PHASE, profile=prof, seed=21)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---------------------------------------------------------------- fin ridges
    # Four dark strips that follow the wobbled radius, so the ripple has an edge.
    bm = bmesh.new()
    n = 19
    for ang in FIN_ANGLES:
        pts = [(0.10 + 0.80 * (i / float(n - 1)), ang) for i in range(n)]
        D.surface_line(bm, pts, h=H, r=R, width=0.15, rise=0.055,
                       profile=prof, segs=SEGS, flat=False, taper=(1.0, 0.55))
    D.new_obj("Fins", bm, c, D.C("sea_weed_dk"), rbx_material="LeafyGrass")

    return c
