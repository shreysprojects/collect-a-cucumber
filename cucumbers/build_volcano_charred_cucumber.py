"""Volcano: the Charred Cucumber - charcoal skin cracked open by glowing lava."""
import bmesh, math

COLLECTION = "VolcanoCharredCucumber"
NOTES = (
    "A cucumber that has been burnt: the standard 4.0-tall, 1.36-across body is charred "
    "`vol_char_lt` charcoal on Basalt, but it is still unmistakably a cucumber - its "
    "stem nub and the shoulder lip under it are fresh `cuke_green`, and 15 bright "
    "`cuke_stud` GREEN speckles still glow out of the soot all the way round it, two of "
    "them on the front facet itself.  The signature is the web of molten cracks drawn on "
    "the skin in `vol_lava` (Neon, emit 0.9, 0.12 wide): one long spine snaking up the "
    "front from zf 0.12 to 0.88 - leaning to angle 78 through the middle of the body and "
    "over to 102 higher up - with FOUR branches forking off it, two down and around to "
    "screen-right (angles 124 and 137) and two out to screen-left (angles 40-45), so the "
    "char reads as separate plates with lava running between them.  No spikes.  The "
    "speckles are hand-filtered against the crack runs (a 6x3 lattice with every slot "
    "that would land on a split dropped or nudged sideways along its facet), so nothing "
    "green ever sits on top of the glow.  Footprint ~1.37 x 1.38, 4.44 tall to the top "
    "of the stem, nothing below z = 0, centred on x=0,y=0, facet 1 faces +Y.  4 parts: "
    "Body, Studs, Cracks, Stem."
)

H, R = 4.0, 0.68
SEGS = 8

# --- the lava web: [(height fraction, angle_deg)], +Y (the camera) is 90 deg -----------
# The spine wanders across the front facet (67.5-112.5 deg) rather than running dead
# centre: the two long leans are what leave room for green speckles on the front.
SPINE = [(0.12, 96), (0.20, 88), (0.26, 79), (0.36, 78), (0.46, 79), (0.52, 90),
         (0.58, 101), (0.68, 102), (0.76, 101), (0.83, 92), (0.88, 88)]
BRANCHES = [
    [(0.20, 88), (0.16, 101), (0.12, 113), (0.09, 124)],    # low, around to the right
    [(0.36, 78), (0.40, 64), (0.42, 52), (0.41, 40)],       # mid, out to the left
    [(0.58, 101), (0.63, 114), (0.67, 126), (0.68, 137)],   # high, around to the right
    [(0.26, 79), (0.22, 66), (0.17, 55), (0.14, 45)],       # low, out to the left
]
CRACKS = [SPINE] + BRANCHES

CRACK_W = 0.12          # brief: 0.12 wide
CRACK_RISE = 0.07       # thick = 0.14, so the strip still breaks the skin at a facet edge
                        # (the body is an 8-gon: 0.628 at a facet centre, 0.68 at its edge)

# Two speckles placed by hand on the FRONT facet (facet 1), in the gaps the leaning
# spine leaves: (height fraction, facet, degrees along the facet from its centre).
FRONT_STUDS = [(0.36, 1, 10.0), (0.67, 1, -10.0)]

STUD_SEED = 3
STUD_SIZE = 0.28
DZ_CLEAR = 0.075        # a speckle must keep this much height fraction from a crack ...
DA_CLEAR = 20.0         # ... or this many degrees around the body
DA_FACET = 9.0          # how far a speckle may slide along its facet (it must stay on it)


def _crack_samples():
    """Dense (height fraction, angle) samples of every crack run, for the clearance test."""
    out = []
    for ln in CRACKS:
        for i in range(len(ln) - 1):
            z0, a0 = ln[i]
            z1, a1 = ln[i + 1]
            for k in range(9):
                t = k / 8.0
                out.append((z0 + (z1 - z0) * t, a0 + (a1 - a0) * t))
    return out


def _adeg(a, b):
    """Absolute angular distance in degrees."""
    return abs((a - b + 180.0) % 360.0 - 180.0)


def _facet_angle(facet):
    """Outward angle (degrees) of the centre of `facet`.  facet 1 = +Y = 90 degrees."""
    return ((facet + 1) * 45.0) % 360.0


def _clear(zf, ang, samples, taken):
    """True if a speckle at (height fraction, angle) misses every crack and every
    speckle already placed."""
    for zc, ac in samples:
        if abs(zf - zc) < DZ_CLEAR and _adeg(ang, ac) < DA_CLEAR:
            return False
    for z2, f2, d2 in taken:
        if abs(zf - z2) < 0.16 and _adeg(ang, _facet_angle(f2) + d2) < 30.0:
            return False
    return True


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # ---------------------------------------------------------------- charred body
    # No nub here - the head is green and lives in the Stem part.
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=None)
    D.new_obj("Body", bm, c, D.C("vol_char_lt"), rbx_material="Basalt", roughness=0.86)

    # ---------------------------------------------------------------- green speckles
    # A 6 x 3 lattice, then every slot that would land on a lava run is nudged sideways
    # along its own facet and dropped if it still will not fit - about 15 survive.
    samples = _crack_samples()
    slots = list(FRONT_STUDS)
    for zf, facet in D.cuke_stud_slots(rows=6, per_row=3, z0=0.13, z1=0.89, segs=SEGS,
                                       seed=STUD_SEED, jitter=0.02):
        ac = _facet_angle(facet)
        for d in (0.0, DA_FACET, -DA_FACET):
            if _clear(zf, ac + d, samples, slots):
                slots.append((zf, facet, d))
                break

    bm = bmesh.new()
    inset = math.cos(math.pi / SEGS)
    for zf, facet, d in slots:
        ac = math.radians(_facet_angle(facet))
        p, n = D.cuke_facet_point(h=H, r=R, zf=zf, facet=facet)
        # slide along the facet PLANE (not around the circle) so the speckle stays flat
        run = D.cuke_radius(zf) * R * inset * math.tan(math.radians(d))
        p = (p[0] - math.sin(ac) * run, p[1] + math.cos(ac) * run, p[2])
        D.stud_patch(bm, p, n, size=STUD_SIZE, rise=0.055)
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic", roughness=0.5)

    # ---------------------------------------------------------------- lava cracks
    bm = bmesh.new()
    D.crack_lines(bm, CRACKS, h=H, r=R, width=CRACK_W, rise=CRACK_RISE)
    D.new_obj("Cracks", bm, c, D.C("vol_lava"), rbx_material="Neon", emit=0.65)

    # ---------------------------------------------------------------- green head
    # A fresh-green lip shelled 0.02 over the body's top chamfer, carrying the two-stage
    # stem nub: the one piece of the cucumber the fire did not reach.
    bm = bmesh.new()
    D.lathe(bm, [(0.000,        0.858 * H),
                 (0.970 * R + 0.020, 0.858 * H),
                 (0.970 * R + 0.020, 0.868 * H),
                 (0.880 * R + 0.018, 0.922 * H),
                 (0.700 * R + 0.016, 0.964 * H),
                 (0.480 * R + 0.013, 1.000 * H),
                 (0.000,        1.002 * H)],
            segs=SEGS, phase=D.cuke_phase(SEGS), cap=True)
    D.beveled_box(bm, (-0.16, -0.16, 3.96), (0.16, 0.16, 4.28), bevel=0.045)
    D.beveled_box(bm, (-0.095, -0.095, 4.25), (0.095, 0.095, 4.44), bevel=0.03)
    D.new_obj("Stem", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic", roughness=0.55)

    return c
