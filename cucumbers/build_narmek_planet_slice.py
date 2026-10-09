"""Narmek: Planet Slice - a blue-green planet standing where the big disc would be,
with two cut cucumber discs lying flat at its feet."""
import bmesh, math

COLLECTION = "NarmekPlanetSlice"
NOTES = ("A narmek slice group, ~2.7 x 2.2 x 1.7 studs.  Instead of a big standing disc "
         "the group is led by a ROUND PLANET: a 10 x 7 uvsphere of radius 0.85 in ocean "
         "blue (nar_planet_b) resting on the ground at (0.13, -0.25, 0.86), wearing six "
         "raised green continent plates (nar_planet_g, 'Grass') and eight cyan speckles "
         "(nar_planet_c).  Two ordinary cut discs lie flat in front of it - one r 0.66 "
         "flat on the ground at screen-left, one r 0.54 tipped 9 degrees at screen-right "
         "- with nar_planet_b rims, nar_planet_g cut faces and nar_planet_c pips.  "
         "Five parts.  The cyan bits (planet speckles, rim speckles and disc pips) share "
         "one object because they share a colour and a material; the planet keeps the "
         "matte 'Plastic' material so it stays a part of its own against the "
         "'SmoothPlastic' disc rims it shares a colour with.  The discs tuck a little "
         "way under the planet's base bulge - that overlap sits on their far edges and "
         "is hidden by the ball from the +Y camera.")

# ---------------------------------------------------------------- the planet
PLANET = (0.13, -0.25, 0.86)          # centre; radius 0.85 puts its south pole on z = 0.01
PLANET_R = 0.85
PLANET_SEGS, PLANET_RINGS = 10, 7
SEAT = 0.965                          # where a patch's base sits, as a fraction of radius

# Facet-centre grid of a 10 x 7 uvsphere: latitude bands 180/7 = 25.714 deg apart,
# meridian centres every 36 deg, with +Y (the camera side) landing on lon 90.
# Remember the +X / screen-left trap: lon 0 is +X, which the render shows on the LEFT.
#           lat,    lon, size, aspect, spin
CONTINENTS = [
    ( 25.71,  90.0, 0.55, 1.10,   8.0),   # the big one, front and a little north
    (  0.00, 126.0, 0.47, 0.80, -14.0),   # equatorial, screen-right of it
    (-25.71,  54.0, 0.44, 1.35,  22.0),   # long southern landmass, screen-left
    ( 25.71,  18.0, 0.36, 0.95, -30.0),   # wrapping over the screen-left limb
    ( 51.43, 126.0, 0.34, 1.20,  16.0),   # northern island
    (-25.71, 162.0, 0.40, 0.70,  40.0),   # wrapping over the screen-right limb
]

#               lat,    lon
PLANET_STUDS = [( 51.43,  18.0), ( 25.71,  54.0), (-25.71, 126.0), (  0.00, 162.0),
                ( 25.71, 162.0), (-25.71, 198.0), ( 77.14,  90.0), (  0.00, 342.0)]

# ---------------------------------------------------------------- the discs
#    (x, y, z),            tilt,  spin, radius, thick, rim studs, pips, seed
DISCS = [
    ((-0.70, 0.41, 0.20),   0.0,  24.0,   0.66,  0.40, 4, 5,  4),
    (( 0.82, 0.53, 0.28),   9.0, -32.0,   0.54,  0.38, 3, 4,  8),
]


def _sphere_slot(lat_deg, lon_deg, seat=SEAT):
    """(surface point, outward normal) on the planet at a latitude / longitude."""
    la, lo = math.radians(lat_deg), math.radians(lon_deg)
    n = (math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la))
    rad = PLANET_R * seat
    return ((PLANET[0] + n[0] * rad, PLANET[1] + n[1] * rad, PLANET[2] + n[2] * rad), n)


def _discs(D):
    out = []
    for loc, tilt, spin, rad, th, studs, pips, seed in DISCS:
        out.append((D.slice_lay(loc, tilt_deg=tilt, spin_deg=spin), rad, th,
                    studs, pips, seed))
    return out


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)
    discs = _discs(D)

    # 1 - the planet itself, an ocean-blue ball resting on the ground
    bm = bmesh.new()
    D.uvsphere(bm, PLANET, PLANET_R, segs=PLANET_SEGS, rings=PLANET_RINGS)
    D.new_obj("Planet", bm, c, D.C("nar_planet_b"), rbx_material="Plastic")

    # 2 - green continents: big raised plates, stretched and spun so none reads square
    bm = bmesh.new()
    for lat, lon, size, aspect, spin in CONTINENTS:
        p, n = _sphere_slot(lat, lon)
        D.stud_patch(bm, p, n, size=size, rise=0.075, sink=0.22, bevel=0.035,
                     aspect=aspect, spin=spin)
    D.new_obj("Continents", bm, c, D.C("nar_planet_g"), rbx_material="Grass")

    # 3 - every cyan speckle in one object: the planet's, the rims', and the pips
    bm = bmesh.new()
    for lat, lon in PLANET_STUDS:
        p, n = _sphere_slot(lat, lon)
        D.stud_patch(bm, p, n, size=0.22, rise=0.055, sink=0.15, bevel=0.03)
    for m, rad, th, studs, pips, seed in discs:
        D.slice_studs(bm, radius=rad, thick=th, matrix=m, n=studs, size=0.19,
                      rise=0.045, seed=seed)
        D.slice_seeds(bm, radius=rad, thick=th, matrix=m, n=pips, size=0.145,
                      ring=0.42, both=False)
    D.new_obj("Studs", bm, c, D.C("nar_planet_c"), rbx_material="SmoothPlastic")

    # 4 - the dark-blue skin of the two lying discs
    bm = bmesh.new()
    for m, rad, th, _s, _p, _sd in discs:
        D.slice_disc(bm, radius=rad, thick=th, matrix=m)
    D.new_obj("Rims", bm, c, D.C("nar_planet_b"), rbx_material="SmoothPlastic")

    # 5 - their green cut faces (top only - the underside is on the ground)
    bm = bmesh.new()
    for m, rad, th, _s, _p, _sd in discs:
        D.slice_face(bm, radius=rad, thick=th, matrix=m, inset=0.11, both=False)
    D.new_obj("Faces", bm, c, D.C("nar_planet_g"), rbx_material="SmoothPlastic")

    return c
