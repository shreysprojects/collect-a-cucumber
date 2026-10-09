"""Toyland: the Lego Cucumber - a bumpy, checkered cucumber on a white peg, capped with a
yellow toy brick."""
import bmesh, math, random

COLLECTION = "ToylandLegoCucumber"
NOTES = (
    "A toy-brick cucumber.  The set's standard upright body (h 4.0, r 0.68, 8 facets, "
    "facet 1 = +Y, NO stem nub) in cuke_green stands on a small white toy_white PEG "
    "(r 0.22, 12-sided, chamfered foot, z 0 .. 0.18, its top 0.02 up inside the body's "
    "flat base), so the whole body is lifted 0.16 and runs z 0.16 .. 4.16.  The peg is "
    "the only thing touching the ground (lowest point exactly z = 0); from the hero camera "
    "only its lower ~0.09 shows as a white sliver under the body, as in the tile.  "
    "CHECKER: the tile's body is a checkerboard of bright and dark squares, so 36 flush "
    "nar_alien_grn cells (0.02 proud, one per facet, 9 bands from zf 0.032 to 0.922 - "
    "7 even bands over the straight part plus one on each chamfered shoulder, the "
    "shoulder cells laid flat on the sloped facet) alternate with the bare cuke_green "
    "skin.  BUMPS: 21 chunky raised squares in cuke_mid, DARKER than the body the way "
    "the tile's lumps read - the exact slots of cuke_studs(rows 7, per_row 3, z0 0.11, "
    "z1 0.90, seed 4), 0.09 proud, but each one 0.27-0.33 wide and, on the straight "
    "middle rows only (zf 0.2 .. 0.8), up to 1.3x taller than wide, because the tile's "
    "lumps are irregular; every bump is laid on the real (sloped) facet plane, so the "
    "top and bottom rows sit flush on the shoulders instead of floating off them.  "
    "BRICK: a toy_yellow bevelled plate 1.10 x 1.10 x 0.34 sitting on the body's flat "
    "top, tipped 8 degrees about X TOWARD THE VIEWER (front edge low, so its top face and "
    "stud show from the front camera); its pivot is sunk 0.06 below the body top (z 4.10) "
    "so the tilted plate swallows the whole top disc (every top vert >= 0.017 inside it) "
    "with no wedge of daylight under it, while the highest bump still clears its "
    "underside by ~0.05; the plate spans z 4.02 .. 4.51.  BRICKSTUD: one round "
    "toy_yellow_dk stud r 0.26 on the plate's top centre, 12-sided, 0.18 visible height "
    "(0.02 more sunk into the plate) with a small chamfered top edge, same tilt, top at "
    "z 4.65.  Overall 1.44 x 1.44 x 4.65 (the width is the bumps on the +-X / +-Y "
    "facets), centred on x = 0, y = 0, ~1690 tris.  Six parts: Peg, Body, Checker, Bumps, "
    "Brick, BrickStud.  Departures from the brief, all from the tile: the Checker part "
    "(the brief does not mention the tile's checker) and the bump size/aspect jitter; "
    "the brief's 'tilted 8 degrees' gave no direction, toward the viewer was chosen.  "
    "The brick and stud are placed with a matrix, so dryrun's bounding box under-reads "
    "the height."
)

# ---------------------------------------------------------------- the peg / lift
LIFT = 0.16                       # the body stands on the peg
PEG_R = 0.22
PEG_PROFILE = [(0.0, 0.0), (0.18, 0.0), (PEG_R, 0.04), (PEG_R, LIFT + 0.02),
               (0.0, LIFT + 0.02)]

# ---------------------------------------------------------------- the checker
# (zf_lo, zf_hi) bands: the bottom chamfer, seven even bands over the straight part of
# the profile (0.082 .. 0.858), then the top shoulder.  Above 0.922 the body curls in
# under the brick, so it stays bare.
_MAIN_LO, _MAIN_HI, _MAIN_N = 0.082, 0.858, 7
BANDS = ([(0.032, _MAIN_LO)]
         + [(_MAIN_LO + (_MAIN_HI - _MAIN_LO) * i / _MAIN_N,
             _MAIN_LO + (_MAIN_HI - _MAIN_LO) * (i + 1) / _MAIN_N) for i in range(_MAIN_N)]
         + [(_MAIN_HI, 0.922)])
CELL_GAP_W = 0.06                 # skin left showing across a facet (both edges)
CELL_GAP_H = 0.05                 # ... and up it
CELL_RISE, CELL_SINK = 0.02, 0.03

# ---------------------------------------------------------------- the bumps
BUMP_SEED = 4                     # the brief's cuke_studs slots, placed by hand
BUMP_VARY_SEED = 40
BUMP_SIZE = (0.27, 0.33)
BUMP_TALL = (1.0, 1.3)            # height / width, straight middle rows only
BUMP_TALL_ZF = (0.2, 0.8)
BUMP_RISE, BUMP_SINK = 0.09, 0.07

# ---------------------------------------------------------------- the brick
BRICK_W, BRICK_T = 1.10, 0.34
BRICK_TILT = -8.0                 # about X; negative tips the top face toward +Y
BRICK_SINK = 0.06                 # pivot below the body top so the tilt leaves no gap
STUD_R, STUD_H, STUD_CH, STUD_SINK = 0.26, 0.18, 0.035, 0.02


def _facet_frame(D, H, R, zf_lo, zf_hi, facet):
    """The strip of facet `facet` between height fractions zf_lo and zf_hi, measured on
    the REAL facet plane (the chord of the lathe profile between those heights - each
    facet band of the lathed 8-gon is a flat trapezoid), so a square laid on it sits
    flat even on a sloped shoulder.  Already lifted onto the peg.

      mid    - centre of the strip on the facet's centre line
      up     - unit vector running UP the facet (up the slope)
      elev   - how far the outward normal is tilted above horizontal, degrees
               (+ on the top shoulder, - on the bottom chamfer, 0 on the straight part)
      yaw    - facet bearing - 90, degrees (turns local +Y onto the facet's outward axis)
      slant  - length of the strip along the slope
      narrow - facet width at the strip's narrower end"""
    k = math.cos(math.pi / D.CUKE_SEGS)
    ra = D.cuke_radius(zf_lo) * R * k            # facet-centre (in)radius at each end
    rb = D.cuke_radius(zf_hi) * R * k
    za, zb = zf_lo * H + LIFT, zf_hi * H + LIFT
    dr, dz = rb - ra, zb - za
    slant = math.hypot(dr, dz)
    a = D.cuke_facet_angle(facet)
    ca, sa = math.cos(a), math.sin(a)
    rm, zm = (ra + rb) / 2.0, (za + zb) / 2.0
    return {"mid": (ca * rm, sa * rm, zm),
            "up": (ca * dr / slant, sa * dr / slant, dz / slant),
            "elev": math.degrees(math.atan2(-dr, dz)),
            "yaw": math.degrees(a) - 90.0,
            "slant": slant,
            "narrow": 2.0 * min(ra, rb) * math.tan(math.pi / D.CUKE_SEGS)}


def _square(D, bm, fr, w, h, rise, sink, bevel):
    """One raised square on a facet strip: `w` across the facet, `h` up it, from `sink`
    inside the skin to `rise` proud of it, centred on the strip.

    Built in a local frame - X across, Y out of the skin, Z up the slope, pivot at the
    square's lower edge - then rot_euler(elev, 0, yaw) = Rz(yaw) @ Rx(elev): Rx tips
    local Y (the outward normal) up by `elev` (and local Z back along the slope with
    it), Rz swings local Y round onto the facet's bearing.  Same result as
    D.stud_patch, but the lowest local corner sits at z = 0 rather than below it."""
    mx, my, mz = fr["mid"]
    ux, uy, uz = fr["up"]
    half = h / 2.0
    pivot = (mx - ux * half, my - uy * half, mz - uz * half)
    lo, hi = (-w / 2.0, -sink, 0.0), (w / 2.0, rise, h)
    if bevel > 0.0:
        vs = D.beveled_box(bm, lo, hi, bevel=bevel)
    else:
        vs = D.box(bm, lo, hi)
    D.xform(bm, vs, D.place(pivot, D.rot_euler(fr["elev"], 0.0, fr["yaw"])))
    return vs


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    H, R = D.CUKE_H, D.CUKE_R
    segs = D.CUKE_SEGS

    # ---- the white peg the cucumber stands on -------------------------------
    bm = bmesh.new()
    D.lathe(bm, PEG_PROFILE, segs=12)
    D.new_obj("Peg", bm, c, D.C("toy_white"), rbx_material="SmoothPlastic")

    # ---- the body, lifted onto the peg, no nub (the brick replaces it) ------
    bm = bmesh.new()
    D.cuke_body(bm, h=H, r=R, nub=None, matrix=D.place((0.0, 0.0, LIFT)))
    D.new_obj("Body", bm, c, D.C("cuke_green"), rbx_material="SmoothPlastic")

    # ---- the checker: bright flush cells on alternate facet/band squares ----
    bm = bmesh.new()
    for bi, (lo, hi) in enumerate(BANDS):
        for f in range(segs):
            if (bi + f) % 2:
                continue
            fr = _facet_frame(D, H, R, lo, hi, f)
            _square(D, bm, fr, fr["narrow"] - CELL_GAP_W, fr["slant"] - CELL_GAP_H,
                    CELL_RISE, CELL_SINK, 0.0)
    D.new_obj("Checker", bm, c, D.C("nar_alien_grn"), rbx_material="SmoothPlastic")

    # ---- the chunky dark bumps ----------------------------------------------
    rng = random.Random(BUMP_VARY_SEED)
    bm = bmesh.new()
    for zf, facet in D.cuke_stud_slots(rows=7, per_row=3, z0=0.11, z1=0.90,
                                       seed=BUMP_SEED):
        size = rng.uniform(*BUMP_SIZE)
        tall = rng.uniform(*BUMP_TALL)            # always drawn: keeps the stream stable
        aspect = tall if BUMP_TALL_ZF[0] <= zf <= BUMP_TALL_ZF[1] else 1.0
        half = size * aspect / 2.0 / H
        fr = _facet_frame(D, H, R, zf - half, zf + half, facet)
        _square(D, bm, fr, size, size * aspect, BUMP_RISE, BUMP_SINK, 0.035)
    D.new_obj("Bumps", bm, c, D.C("cuke_mid"), rbx_material="SmoothPlastic")

    # ---- the yellow brick, tipped toward the viewer -------------------------
    # built round its own bottom-centre, then pivoted onto the body top
    m = D.place((0.0, 0.0, H + LIFT - BRICK_SINK), D.rot_euler(BRICK_TILT, 0.0, 0.0))
    hw = BRICK_W / 2.0
    bm = bmesh.new()
    vs = D.beveled_box(bm, (-hw, -hw, 0.0), (hw, hw, BRICK_T), bevel=0.07)
    D.xform(bm, vs, m)
    D.new_obj("Brick", bm, c, D.C("toy_yellow"), rbx_material="SmoothPlastic")

    # ---- its one round stud, same tilt --------------------------------------
    z0 = BRICK_T - STUD_SINK
    z1 = BRICK_T + STUD_H
    bm = bmesh.new()
    D.lathe(bm, [(0.0, z0), (STUD_R, z0), (STUD_R, z1 - STUD_CH),
                 (STUD_R - STUD_CH, z1), (0.0, z1)], segs=12, matrix=m)
    D.new_obj("BrickStud", bm, c, D.C("toy_yellow_dk"), rbx_material="SmoothPlastic")

    return c
