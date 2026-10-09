"""Light-up dance floor: 16 individually named Neon tiles in a 4 x 4 grid, set in a dark
chamfered frame on a grey plinth, with a thin dark edge band, four hex corner caps and a
little controller plate bolted to the front-right of the frame.

Faces +Y.  8 x 8 studs, 0.43 tall.  It ships as a lit CHECKERBOARD - eight cells glowing
pink/cyan, eight dark - because half the floor being dark is what makes it read as a
dance floor rather than a tiled tray.  The tiles are the point of the prop: the game
recolours them at runtime, so each one is its own object with a name that encodes its
grid cell (see NOTES / PATTERNS / TILE_KEYS / GLOW below).
"""
import bmesh, math

COLLECTION = "DanceFloor"

# ---------------------------------------------------------------- grid contract
GRID = 4
PITCH = 1.74          # tile centre -> tile centre
TILE = 1.60           # tile side; grout gap = PITCH - TILE = 0.14 everywhere, including
                      # the 0.14 margin between the outer tiles and the frame

#: the runtime colour cycle, in order.  Tile (row, col) carries CYCLE[(row + col) % 4].
#: Indices 0 and 2 are the two a checkerboard's LIT cells land on, so they hold the
#: pink/cyan pair - the furthest apart of the four at thumbnail size.  1 and 3 are the
#: shades the animator brings in when it lights the cells that ship dark.
CYCLE = ("neon_pink", "neon_purple", "neon_cyan", "neon_lime")

#: Build hex per CYCLE key.  The palette neons are all near-max-value hexes, and a Neon
#: face pointed straight up at the key light sums its diffuse (~0.95 of base under the
#: preview rig) AND its emission, so shipping D.C("neon_pink") at emit 0.9 puts every
#: channel past 1.0 and the tile renders as a white square with the hue surviving only
#: on the bevel.  These are the same four hues deepened to ~45 % value, which leaves the
#: sum room to land near 0.7 - a lit top around rgb 220 with the colour intact.
GLOW = {"neon_pink": "731e46", "neon_purple": "512973",
        "neon_cyan": "1c5f76", "neon_lime": "477323"}
DARK_TILE = "070911"   # an unlit cell: a cool near-black, a step darker than the frame
EMIT = 0.6             # bottom of the contract's 0.6-1.5 band, for the same reason
AMBER = "7a421d"       # neon_orange, deepened to match, for the power dot

# --- stack heights (studs) -------------------------------------------------------
SLAB = 4.00                       # metal_mid plinth: the full 8 x 8 footprint
SLAB_Z = 0.09
FRAME_OUT, FRAME_IN = 3.90, 3.55  # black frame rails: outer / inner half-extent
FRAME_Z0, FRAME_Z1 = 0.09, 0.36
DECK_Z0, DECK_Z1 = 0.04, 0.19     # black grout deck under the tile field
TILE_Z0, TILE_Z1 = 0.19, 0.34     # tiles sit 0.02 BELOW the frame lip
STRIP_IN, STRIP_OUT = 3.72, 3.87  # dark edge band on the frame's outer top
STRIP_Z0, STRIP_Z1 = 0.36, 0.39
CAP_C, CAP_R = 3.725, 0.19        # hex corner caps, centred on the rail centre line
CAP_Z0, CAP_Z1 = 0.36, 0.41
PLATE_X = -2.05                   # controller plate: NEGATIVE x = the viewer's RIGHT
PLATE_Z0, PLATE_Z1 = 0.36, 0.40
DOT_Z0, DOT_Z1 = 0.38, 0.43


def tile_x(col):
    """col 0 is the +X edge, which is the viewer's LEFT (they stand on the +Y side)."""
    return (GRID - 1) * PITCH / 2.0 - col * PITCH


def tile_y(row):
    """row 0 is the BACK of the floor, i.e. the most negative y."""
    return -(GRID - 1) * PITCH / 2.0 + row * PITCH


def tile_name(row, col):
    return "Tile_r%d_c%d" % (row, col)


def tile_lit(row, col):
    """The BUILT state is PATTERNS['Checker']: the (row + col) even cells ship lit.

    Half the floor dark is what makes it read as a dance floor rather than a tiled tray -
    lit-vs-unlit is a far bigger step than any two hues of the same value can be."""
    return (row + col) % 2 == 0


#: part name -> the palette key whose hue that cell carries in the 4-colour cycle.  Only
#: the tile_lit() cells ship showing it; the rest ship DARK_TILE and this is the colour
#: the animator lights them with.
TILE_KEYS = {tile_name(r, c): CYCLE[(r + c) % len(CYCLE)]
             for r in range(GRID) for c in range(GRID)}

#: part name -> the exact hex the tile was built with (GLOW[key] lit, DARK_TILE unlit),
#: so a recolour can always get back to the shipped look.
TILE_HEX = {tile_name(r, c): (GLOW[CYCLE[(r + c) % len(CYCLE)]] if tile_lit(r, c)
                              else DARK_TILE)
            for r in range(GRID) for c in range(GRID)}

#: part name -> (x, y, z) of the tile's top-face centre, for anything that has to place
#: an effect, a footprint decal or a proximity prompt on a cell.
TILE_CENTRES = {tile_name(r, c): (round(tile_x(c), 3), round(tile_y(r), 3), TILE_Z1)
                for r in range(GRID) for c in range(GRID)}

#: Ready-made phase maps for the runtime animator.  Each is 16 ints in ROW-MAJOR order,
#: i.e. entry `row * 4 + col`; tiles sharing a value light together on the same beat.
PATTERNS = {
    "Checker": [(r + c) % 2 for r in range(GRID) for c in range(GRID)],
    "Cycle4":  [(r + c) % 4 for r in range(GRID) for c in range(GRID)],
    "Rows":    [r for r in range(GRID) for _c in range(GRID)],
    "Cols":    [c for _r in range(GRID) for c in range(GRID)],
    "Rings":   [int(max(abs(r - 1.5), abs(c - 1.5)) - 0.5)
                for r in range(GRID) for c in range(GRID)],
}

#: Transparency to tween a Neon tile to for each lighting level (Roblox convention).
STATES = {"On": 0.0, "Dim": 0.45, "Off": 0.85}

PIVOTS = {
    "FloorCentre": (0.0, 0.0, TILE_Z1),         # top face of the tile field, dead centre
    "TileR0C0": (tile_x(0), tile_y(0), TILE_Z1),  # BACK, viewer's LEFT
    "TileR3C3": (tile_x(3), tile_y(3), TILE_Z1),  # FRONT, viewer's RIGHT
    "Controller": (PLATE_X, CAP_C, DOT_Z1),     # the amber power dot on the front rail
}

NOTES = (
    "Footprint 8.0 x 8.0 studs, x -4..4 and y -4..4, 0.43 studs tall, nothing below z=0. "
    "Walking surface is the tile tops at z=0.34; the black frame lip stands 0.02 proud of "
    "them at z=0.36 and the hex corner caps top out at 0.41 (the amber power dot at 0.43). "
    "Four copies butt cleanly on the 8-stud grid.\n"
    "\n"
    "GRID CONVENTION - this is the contract, do not re-derive it. The 16 tiles are named "
    "Tile_r<row>_c<col>, row and col 0..3, each one its OWN object so the game can recolour "
    "cells independently.  ROW 0 IS THE BACK of the floor (most negative y) and rows count "
    "forward toward the player: row 0 y=-2.61, row 1 y=-0.87, row 2 y=+0.87, row 3 y=+2.61. "
    "COL 0 IS THE +X EDGE, which is the viewer's LEFT because they stand on the +Y side and "
    "look down -Y: col 0 x=+2.61, col 1 x=+0.87, col 2 x=-0.87, col 3 x=-2.61.  So "
    "Tile_r0_c0 is the far corner on the player's left and Tile_r3_c3 is the near corner on "
    "their right.  Tiles are 1.60 square with a uniform 0.14 dark grout gap between them "
    "and the same 0.14 margin out to the frame, so the grid stays legible from directly "
    "above.  TILE_CENTRES in this module has every cell's top-face centre.\n"
    "\n"
    "BUILT STATE - a real lit floor is half dark, so the shipped look is "
    "PATTERNS['Checker']: the eight (row+col)-even cells ship LIT and the other eight "
    "ship unlit in DARK_TILE, a cool near-black that sits a step below the frame.  That "
    "lit/unlit step is what reads as a dance floor at 40 studs; hue alone cannot do it. "
    "The lit cells alternate CYCLE[0] neon_pink and CYCLE[2] neon_cyan down the "
    "diagonals, so the floor still shows two obviously different colours.\n"
    "\n"
    "COLOUR - every tile is rbx_material Neon at emit 0.6 (EMIT), including the dark "
    "ones, so the animator can light ANY cell without swapping its material.  The build "
    "hexes come from GLOW, not straight from the palette: the palette neons are "
    "near-max-value, and a Neon face pointed straight up sums diffuse AND emission, so "
    "D.C('neon_pink') at emit 0.9 blew every channel past 1.0 and all sixteen tiles "
    "rendered as white squares.  GLOW holds the same four hues at ~45 % value, which is "
    "the headroom that emission needs; DO NOT re-raise emit or swap GLOW back for raw "
    "palette keys.  TILE_KEYS maps each part name to the palette key whose hue that cell "
    "carries in the cycle, and TILE_HEX to the exact hex it was built with, so a recolour "
    "can always get back to the shipped look.  Anything driving these at runtime should "
    "use GLOW[key] rather than the raw palette hex for the same reason.\n"
    "\n"
    "RECOLOUR INTENT - the animator should set BrickColor/Color on the tile parts (and "
    "optionally tween Transparency between the STATES values On 0.0 / Dim 0.45 / Off 0.85) "
    "rather than moving anything; no part of this prop is meant to hinge or slide. "
    "PATTERNS holds five ready-made phase maps in ROW-MAJOR order (index = row*4 + col): "
    "Checker (2 phases - the shipped built state), Cycle4 for a four-hue diagonal chase, "
    "Rows and Cols for wipes front-to-back or left-to-right, and Rings for an inner-2x2 / "
    "outer-ring pulse. Step a counter each beat and colour tile i by "
    "(PATTERNS[p][i] + beat) % phases.  Leave the grout, frame and trim alone: their "
    "darkness is what makes the tiles pop, and nothing on this prop may out-value a lit "
    "tile.\n"
    "\n"
    "PARTS - 20 objects. 16 Tile_* (Neon). Frame (plastic_black SmoothPlastic) is the four "
    "chamfered frame rails PLUS the grout deck slab under the tile field, merged because "
    "they share a colour and material.  Trim (metal_mid Metal) is the low plinth that "
    "shows as a 0.10-wide kick around the base, the four hex corner caps, and the "
    "controller plate - it is deliberately the brightest NON-emissive value on the prop "
    "so the caps read as bolted-down fittings against the black frame from every angle, "
    "not only the two that catch the key light.  EdgeStrip (metal_dark Metal) is the thin "
    "band round the frame's outer top; it is kept dark and rough on purpose - as bright "
    "chrome it out-valued the tiles and the eye went to the border instead of the floor. "
    "PowerLight (Neon, AMBER) is the single indicator dot.\n"
    "\n"
    "The controller plate + power dot sit on the front rail at x=-2.05, i.e. OFF CENTRE to "
    "the viewer's RIGHT - the one deliberate asymmetry, and the thing that says 'this floor "
    "is powered'.  Mirror the prop in X if you need the controller on the other side; "
    "everything else is four-fold symmetric, but note that mirroring also swaps the "
    "meaning of the col index, so remap the tile names if you do."
)


def _rails():
    """The four chamfered frame rails as (lo, hi) corner pairs."""
    o, i, z0, z1 = FRAME_OUT, FRAME_IN, FRAME_Z0, FRAME_Z1
    return [((-o, i, z0), (o, o, z1)),        # front, +Y
            ((-o, -o, z0), (o, -i, z1)),      # back, -Y
            ((i, -i, z0), (o, i, z1)),        # +X, the viewer's left
            ((-o, -i, z0), (-i, i, z1))]      # -X, the viewer's right


def _strips():
    """The four edge-strip bands as (lo, hi) corner pairs."""
    o, i, z0, z1 = STRIP_OUT, STRIP_IN, STRIP_Z0, STRIP_Z1
    return [((-o, i, z0), (o, o, z1)),
            ((-o, -o, z0), (o, -i, z1)),
            ((i, -i, z0), (o, i, z1)),
            ((-o, -i, z0), (-i, i, z1))]


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    # Value ladder, darkest first, and nothing non-emissive climbs past a lit tile:
    #   Frame (black) < EdgeStrip (metal_dark) < Trim (metal_mid) < the lit tiles.
    black = D.C("plastic_black")     # darkest value: frame + grout, so the tiles pop
    band = D.C("metal_dark")         # a dull grey line on the frame edge, not a mirror
    fitting = D.C("metal_mid")       # brightest non-emissive: plinth, caps, plate

    # ---- black body: grout deck under the tile field + the four chamfered frame rails
    bm = bmesh.new()
    D.box(bm, (-FRAME_IN, -FRAME_IN, DECK_Z0), (FRAME_IN, FRAME_IN, DECK_Z1))
    for (lo, hi) in _rails():
        D.beveled_box(bm, lo, hi, bevel=0.07)
    D.new_obj("Frame", bm, c, black, rbx_material="SmoothPlastic", roughness=0.5)

    # ---- metal_mid: low plinth trim, four hex corner caps, controller plate.  Rough and
    # only lightly metallic: a mirror finish here reads as a specular flash on the two
    # faces that catch the key and vanishes into the frame on the other two.
    bm = bmesh.new()
    D.box(bm, (-SLAB, -SLAB, 0.0), (SLAB, SLAB, SLAB_Z))
    for (sx, sy) in ((CAP_C, CAP_C), (-CAP_C, CAP_C), (CAP_C, -CAP_C), (-CAP_C, -CAP_C)):
        D.prism(bm, D.ngon_pts(6, CAP_R, phase=math.radians(30), center=(sx, sy)),
                CAP_Z0, CAP_Z1)
    D.prism(bm, D.rounded_rect_pts(1.20, 0.28, 0.09, segs=2, center=(PLATE_X, CAP_C)),
            PLATE_Z0, PLATE_Z1)
    D.new_obj("Trim", bm, c, fitting, rbx_material="Metal", metallic=0.3, roughness=0.65)

    # ---- thin band round the frame's outer top edge.  Dark and rough: as bright steel
    # it blew to pure white on the two rails facing the key and out-valued the tiles.
    bm = bmesh.new()
    for (lo, hi) in _strips():
        D.box(bm, lo, hi)
    D.new_obj("EdgeStrip", bm, c, band, rbx_material="Metal", metallic=0.2, roughness=0.75)

    # ---- the controller's power dot
    bm = bmesh.new()
    D.cyl(bm, (PLATE_X, CAP_C, DOT_Z0), (PLATE_X, CAP_C, DOT_Z1), 0.085, segs=6)
    D.new_obj("PowerLight", bm, c, AMBER, rbx_material="Neon", emit=0.7, roughness=0.8)

    # ---- the 16 tiles, one object each: the Checker pattern IS the built state, so half
    # ship lit off the cycle and half ship dark.  Rough, because at roughness 0.4 the key
    # light's specular lobe put a white sheen across every upward-facing top.
    h = TILE / 2.0
    for row in range(GRID):
        for col in range(GRID):
            name = tile_name(row, col)
            cx, cy = tile_x(col), tile_y(row)
            bm = bmesh.new()
            D.beveled_box(bm, (cx - h, cy - h, TILE_Z0), (cx + h, cy + h, TILE_Z1),
                          bevel=0.055)
            D.new_obj(name, bm, c, TILE_HEX[name], rbx_material="Neon",
                      emit=EMIT, roughness=0.8)

    return c
