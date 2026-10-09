"""Desert: Wrapped Cucumber - a mummy bound up in three broad cream bandage bands."""
import bmesh, math, random

COLLECTION = "DesertWrappedCucumber"
NOTES = ("A standard 4.0-stud cucumber body wrapped like a mummy: three broad cream "
         "bandage bands (0.62 wide, 1.15 turns each) spiral up it at overlapping height "
         "ranges and staggered phases, hiding a little over half the skin, each band "
         "hemmed top and bottom by a thin darker edge line.  Green body and its light "
         "speckles only show through the gaps between the wraps - the speckle slots are "
         "filtered against the band paths so none is buried.  Faces +Y, footprint "
         "~1.6 x 1.6 studs, 4.3 tall including the stem nub.  Four parts: Body, Studs, "
         "Bands, BandEdges.")

# ---- the wrap ----------------------------------------------------------------
BAND_W, BAND_T, BAND_TURNS = 0.62, 0.12, 1.15   # band width / thickness / turns
BAND_OFFSET = 0.07                              # how far the band floats off the facets
BAND_N = 22                                     # path samples per band
EDGE_W, EDGE_T, EDGE_N = 0.11, 0.06, 16         # the thin hem line along each band edge
EDGE_INSET = 0.74                               # hem sits 74% of the way out to the edge

# (z0, z1, phase_deg, taper) - the three bands of the brief, overlapping by ~0.08
BANDS = [
    (0.08, 0.42, -20.0, (0.88, 1.00)),          # first turn, tapering in at the start
    (0.34, 0.68, 100.0, None),
    (0.60, 0.94, 220.0, (1.00, 0.88)),          # last turn, tapering out at the head
]

STUD_COUNT, STUD_SEED = 11, 17


def _band_edge(D, z0, z1):
    """How far a band's edge sits from its centreline: (height fraction, degrees).

    The ribbon's width runs perpendicular to both the path tangent and the surface
    normal, so on a shallow spiral it is nearly vertical but rakes back along the path -
    both offsets are needed to lay the hem lines exactly on the band's edges."""
    zm = (z0 + z1) / 2.0
    rad = D.cuke_radius(zm) * D.CUKE_R * math.cos(math.pi / D.CUKE_SEGS) + BAND_OFFSET
    a = rad * 2.0 * math.pi * BAND_TURNS          # horizontal run of the whole spiral
    b = D.CUKE_H * (z1 - z0)                      # ... and its rise
    L = math.hypot(a, b)
    return (BAND_W / 2.0) * (a / L) / D.CUKE_H, math.degrees((BAND_W / 2.0) * (b / L) / rad)


def _covered(D, ang_deg, zf, pad=0.0):
    """True if a band crosses the skin at this (angle, height) - i.e. it is hidden."""
    for z0, z1, phase, _t in BANDS:
        dzf, _da = _band_edge(D, z0, z1)
        for k in range(-2, 3):
            t = (ang_deg + 360.0 * k - phase) / (360.0 * BAND_TURNS)
            if -0.002 <= t <= 1.002:
                zb = z0 + (z1 - z0) * min(1.0, max(0.0, t))
                if abs(zf - zb) < dzf + pad:
                    return True
    return False


def _stud_slots(D):
    """(height fraction, facet) speckle slots that land in the GAPS between the wraps,
    weighted toward the three facets the camera sees and never two on top of each other."""
    rng = random.Random(STUD_SEED)
    cand = []
    for facet in range(D.CUKE_SEGS):
        ang = math.degrees(D.cuke_facet_angle(facet))
        front = 0.0 if facet in (0, 1, 2) else (0.40 if facet in (3, 7) else 0.85)
        zf = 0.07
        while zf <= 0.93:
            cand.append((rng.random() + front, round(zf, 4), facet, ang))
            zf += 0.045
    cand.sort()
    keep = []
    for _score, zf, facet, ang in cand:
        if _covered(D, ang, zf, 0.055):                       # buried under a band
            continue
        if any(f == facet and abs(z - zf) < 0.15 for z, f in keep):
            continue
        if any((f - facet) % D.CUKE_SEGS in (1, D.CUKE_SEGS - 1) and abs(z - zf) < 0.08
               for z, f in keep):
            continue
        keep.append((zf, facet))
        if len(keep) >= STUD_COUNT:
            break
    return sorted(keep)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R

    # ---- the cucumber under the wrap --------------------------------------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=(0.30, 0.30))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    bm = bmesh.new()
    D.cuke_studs(bm, h=H, r=R, size=0.28, rise=0.055, slots=_stud_slots(D))
    D.new_obj("Studs", bm, c, D.C("cuke_stud"), rbx_material="SmoothPlastic")

    # ---- three bandage bands ----------------------------------------------
    bm = bmesh.new()
    for z0, z1, phase, taper in BANDS:
        D.wrap_ribbon(bm, h=H, r=R, z0=z0, z1=z1, turns=BAND_TURNS, width=BAND_W,
                      thick=BAND_T, n=BAND_N, phase_deg=phase, offset=BAND_OFFSET,
                      taper=taper)
    D.new_obj("Bands", bm, c, D.C("des_bandage"), rbx_material="Fabric")

    # ---- the darker hem down both edges of every band ----------------------
    bm = bmesh.new()
    edge_off = BAND_OFFSET + BAND_T / 2.0 + EDGE_T / 2.0 - 0.02
    for z0, z1, phase, _t in BANDS:
        dzf, dang = _band_edge(D, z0, z1)
        dzf, dang = dzf * EDGE_INSET, dang * EDGE_INSET
        for s in (1.0, -1.0):                     # -1 = lower edge, +1 = upper edge
            D.wrap_ribbon(bm, h=H, r=R, z0=z0 + s * dzf, z1=z1 + s * dzf,
                          turns=BAND_TURNS, width=EDGE_W, thick=EDGE_T, n=EDGE_N,
                          phase_deg=phase - s * dang, offset=edge_off)
    D.new_obj("BandEdges", bm, c, D.C("des_bandage_d"), rbx_material="Fabric")

    return c
