"""Snack vending machine: a chamfered red cabinet with a black recessed front frame, a
glazed product bay lined in white and holding four loaded shelves of cans, packets and
crisp bags, a black control column down the viewer's right side (keypad / coin slot /
card reader / coin cup / price readout), a lit SNACKS header light box and a pale steel
delivery flap hanging ajar in a dark chute.  Faces +Y."""
import bmesh, math, random

COLLECTION = "VendingMachine"

NOTES = (
    "3.20 wide (x) x 1.70 deep (y) x 6.56 tall, centred on x=0 / y=0, standing on z=0 on "
    "four short feet.  The whole front - glass, keypad, sign - faces +Y.\n"
    "MIRROR NOTE: the control column is at NEGATIVE x (x -1.34..-0.42), which is the "
    "player's RIGHT as they walk up to the machine; the glazed product bay is the wider "
    "bay at x -0.24..1.18.  Mirror the collection in X if you want a left-hand column.\n"
    "GlassPane (x -0.24..1.18, z 1.92..5.40, y 0.64..0.70) is Glass at transparency 0.6 - "
    "give it CanCollide=false if anything is ever meant to reach inside.  Behind it the "
    "cavity runs x -0.42..1.20, y -0.58..0.62, z 1.94..5.38 and its back / left / right "
    "walls are the WHITE Whitework liner, so the stock reads as bright colour against a "
    "lit field rather than against a black hole - do not repaint the liner dark.  The "
    "four Shelves are part of Steelwork; their top faces are z 2.02 / 2.88 / 3.74 / 4.60 "
    "and every product stands with its front face at y=0.50, 0.14 clear of the glass.  "
    "Shelf form alternates so the bay never reads as a bookshelf: cans (bottom), tall "
    "flat packets, cans, squat crisp bags (top).  Slot (shelf 1, position 3) is "
    "deliberately EMPTY - the sold-out gap - so do not 'fix' it.\n"
    "DeliveryFlap is the only moving part: a pale steel door with a grab lip along its "
    "bottom edge, modelled already tilted 22 deg back into the chute and hanging PROUD of "
    "the black chute wall (flap y 0.43..0.73, chute back wall at y 0.26) so the tilt and "
    "its shadow both read.  Hinge it on PIVOTS.FlapHinge about the WORLD X axis and drive "
    "it with STATES (degrees); items should be spawned at PIVOTS.DropPoint in the void "
    "between the chute wall and the flap (x -0.12..1.06, y 0.26..0.45, z 0.90..1.55).  "
    "Its own mesh is already at the Ajar angle, so a Motor6D/CFrame rig should treat "
    "STATES.FlapAjar as its rest pose.\n"
    "Emissive parts: SignPanel (neon_yellow, the light box face) and NeonText (neon_red - "
    "the SNACKS letters plus the 1.50 price readout in the column).  Flicker or recolour "
    "NeonText for a 'sold out' / 'exact change' state.  Nothing sits below z=0."
)

PIVOTS = {
    "FlapHinge": (0.47, 0.70, 1.58),    # top edge of the delivery flap, world X axis
    "DropPoint": (0.47, 0.36, 1.05),    # spawn a vended item here, inside the chute
    "CoinSlot": (-0.87, 0.90, 3.47),
    "CardSlot": (-0.91, 0.90, 2.94),
    "KeypadCentre": (-0.88, 0.92, 4.40),
}

STATES = {                              # degrees about PIVOTS.FlapHinge, world X
    "FlapShut": 0.0,
    "FlapAjar": -22.0,                  # as modelled
    "FlapOpen": -78.0,
}

# ---- product bay layout -------------------------------------------------------------
SHELF_Z = (2.02, 2.88, 3.74, 4.60)      # shelf TOP faces
SLOTS = (6, 6, 5, 5)                    # product slots per shelf, bottom up
SHELF_FORM = ("can", "packet", "can", "bag")   # one silhouette per shelf, bottom up
EMPTY = {(1, 3)}                        # the one sold-out slot
PROD_KEYS = ("plastic_blue", "plastic_yellow", "plastic_green", "accent_orange")
PX0, PX1 = -0.20, 1.12                  # x span the products are spread across


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    red = D.C("plastic_red")        # cabinet body - the dominant mid value
    ink = D.C("plastic_black")      # frame, column, chute, recesses, feet
    steel = D.C("metal_light")      # kick plate, shelves, trim, coin/card furniture
    door = D.C("steel_bright")      # the delivery flap - one step LIGHTER than the trim
    pane = D.C("glass")
    white = D.C("plastic_white")    # keypad buttons + the lit bay liner
    lit = D.C("neon_yellow")        # header light box face
    glow = D.C("neon_red")          # SNACKS lettering + price digits

    PLASTIC = dict(rbx_material="SmoothPlastic", roughness=0.5)
    METAL = dict(rbx_material="Metal", metallic=0.55, roughness=0.4)

    # =========================================================== red cabinet shell
    # A plinth and a cornice both 3.20 wide, with the 3.04-wide body sunk between them,
    # so the silhouette has a foot and a hat instead of being one slab.
    bm = bmesh.new()
    D.box(bm, (-1.60, -0.78, 0.20), (1.60, 0.80, 0.68))                       # plinth
    D.beveled_box(bm, (1.34, -0.78, 0.68), (1.52, 0.80, 5.58), bevel=0.07)    # side wall +x
    D.beveled_box(bm, (-1.52, -0.78, 0.68), (-1.34, 0.80, 5.58), bevel=0.07)  # side wall -x
    D.box(bm, (-1.34, 0.52, 0.68), (1.34, 0.76, 0.86))                        # apron under flap
    D.box(bm, (-1.34, 0.52, 1.60), (1.34, 0.76, 1.74))                        # apron over flap
    D.box(bm, (1.06, 0.52, 0.86), (1.34, 0.76, 1.60))                         # apron +x of flap
    D.box(bm, (-1.34, 0.52, 0.86), (-0.12, 0.76, 1.60))                       # apron -x of flap
    D.beveled_box(bm, (-1.60, -0.78, 5.52), (1.60, 0.84, 5.76), bevel=0.09)   # cornice
    D.beveled_box(bm, (-1.52, -0.78, 5.76), (1.52, 0.74, 6.56), bevel=0.10)   # header box
    D.new_obj("Body", bm, c, red, **PLASTIC)

    # =========================================================== black frame / column / chute
    bm = bmesh.new()
    D.box(bm, (-1.40, -0.78, 0.68), (1.40, -0.58, 5.58))                      # back panel
    # the control column doubles as the -x wall of the display cavity
    D.beveled_box(bm, (-1.34, -0.58, 1.74), (-0.42, 0.84, 5.58), bevel=0.07)
    # the sill and head run the full depth, so they also floor and ceil the cavity
    D.beveled_box(bm, (-0.38, -0.58, 1.74), (1.34, 0.76, 1.94), bevel=0.06)   # frame sill
    D.beveled_box(bm, (-0.38, -0.58, 5.38), (1.34, 0.76, 5.58), bevel=0.06)   # frame head
    D.beveled_box(bm, (1.18, 0.58, 1.90), (1.34, 0.76, 5.42), bevel=0.05)     # frame bar +x
    D.box(bm, (-0.38, 0.58, 1.90), (-0.24, 0.76, 5.42))                       # frame bar -x
    # delivery chute: a back wall set well BACK of the flap plus a floor, so the flap
    # hangs proud in a real hole instead of being buried in a solid black slab.
    D.box(bm, (-0.12, 0.08, 0.86), (1.06, 0.26, 1.60))                        # chute back wall
    D.box(bm, (-0.12, 0.26, 0.86), (1.06, 0.54, 0.90))                        # chute floor
    D.box(bm, (-1.30, 0.74, 4.98), (-0.46, 0.82, 5.42))                       # price display face
    D.box(bm, (-1.10, 0.76, 3.42), (-0.64, 0.86, 3.52))                       # coin slot mouth
    D.box(bm, (-0.98, 0.76, 2.70), (-0.84, 0.86, 3.18))                       # card swipe channel
    D.box(bm, (-1.22, 0.56, 2.02), (-0.60, 0.84, 2.30))                       # coin-return hollow
    for (fx, fy) in ((1.30, 0.58), (-1.30, 0.58), (1.30, -0.56), (-1.30, -0.56)):
        D.box(bm, (fx - 0.16, fy - 0.16, 0.00), (fx + 0.16, fy + 0.16, 0.20))  # feet
    D.new_obj("DarkShell", bm, c, ink, rbx_material="SmoothPlastic", roughness=0.45)

    # =========================================================== bright metalwork
    bm = bmesh.new()
    D.beveled_box(bm, (-1.46, 0.78, 0.24), (1.46, 0.86, 0.62), bevel=0.05)    # kick plate
    for ztop in SHELF_Z:                                                       # four shelves
        D.box(bm, (-0.32, -0.40, ztop - 0.07), (1.20, 0.58, ztop))
    D.box(bm, (-0.42, 0.62, 1.74), (-0.38, 0.86, 5.58))                       # column/frame bead
    D.box(bm, (-1.20, 0.84, 3.50), (-0.62, 0.89, 3.60))                       # coin plate, upper
    D.box(bm, (-1.20, 0.84, 3.34), (-0.62, 0.89, 3.44))                       # coin plate, lower
    D.box(bm, (-1.16, 0.84, 2.72), (-0.96, 0.90, 3.16))                       # card reader jaw
    D.box(bm, (-0.86, 0.84, 2.72), (-0.66, 0.90, 3.16))                       # card reader jaw
    D.box(bm, (-1.26, 0.84, 1.94), (-0.56, 0.90, 2.02))                       # coin cup lip
    D.box(bm, (-1.26, 0.84, 2.30), (-0.56, 0.90, 2.38))                       # coin cup brow
    D.box(bm, (-1.34, 0.82, 4.92), (-0.42, 0.88, 4.98))                       # display rail
    D.box(bm, (-1.34, 0.82, 5.42), (-0.42, 0.88, 5.48))                       # display rail
    # hinge barrel, pulled forward to the mouth so it shows above the tilted flap
    D.box(bm, (-0.12, 0.62, 1.54), (1.06, 0.74, 1.60))
    D.new_obj("Steelwork", bm, c, steel, **METAL)

    # =========================================================== the pane
    # Clear glass, not tint, and at the transparent end of the contract range: this pane's
    # only job is to let the stock behind it read in full colour.
    bm = bmesh.new()
    D.box(bm, (-0.24, 0.64, 1.92), (1.18, 0.70, 5.40))
    D.new_obj("GlassPane", bm, c, pane, rbx_material="Glass", transparency=0.6,
              metallic=0.0, roughness=0.05)

    # =========================================================== the stock behind the glass
    # One bmesh per wrapper colour, walked shelf by shelf so no two neighbours match and
    # the warm pair (yellow / orange) never sits side by side.  Every item presents its
    # broad printed FACE to the glass; the silhouette changes shelf by shelf.
    rng = random.Random(20260909)
    bays = {k: bmesh.new() for k in PROD_KEYS}
    for s, ztop in enumerate(SHELF_Z):
        n = SLOTS[s]
        pitch = (PX1 - PX0) / n
        form = SHELF_FORM[s]
        for i in range(n):
            if (s, i) in EMPTY:
                continue
            cx = PX0 + pitch * (i + 0.5)
            bmp = bays[PROD_KEYS[(i + 2 * s) % 4]]
            if form == "can":                           # drink cans stood on end
                r = round(min(pitch * 0.40, 0.10), 3)
                h = round(rng.uniform(0.30, 0.38), 3)
                D.cyl(bmp, (cx, 0.50 - r, ztop), (cx, 0.50 - r, ztop + h), r, segs=8)
            else:
                if form == "bag":                       # squat, wide crisp bags
                    half = round(pitch * 0.46, 3)
                    h = round(rng.uniform(0.28, 0.34), 3)
                    d = round(rng.uniform(0.16, 0.22), 3)
                else:                                   # tall flat packets / bars
                    half = round(pitch * 0.44, 3)
                    h = round(rng.uniform(0.44, 0.60), 3)
                    d = round(rng.uniform(0.10, 0.16), 3)
                yaw = rng.choice((0.0, 0.0, 0.0, -4.0, 4.0))
                D.box(bmp, (cx - half, 0.50 - d, ztop), (cx + half, 0.50, ztop + h),
                      rot=(D.rot_euler(rz=yaw) if yaw else None))
    for k in PROD_KEYS:
        D.new_obj("Products" + k.split("_")[1].capitalize(), bays[k], c, D.C(k),
                  rbx_material="SmoothPlastic", roughness=0.42)

    # =========================================================== white plastic: keypad + bay liner
    # The liner is the whole point of the bay: a bright field behind the stock so the
    # wrappers read as colour through the glass instead of dissolving into a black cave.
    bm = bmesh.new()
    for (bx, bz) in D.grid_positions(3, 4, 0.26, 0.26, center=(-0.88, 4.40)):
        D.box(bm, (bx - 0.10, 0.84, bz - 0.10), (bx + 0.10, 0.92, bz + 0.10))   # keypad, 3 x 4
    D.box(bm, (-0.42, -0.58, 1.94), (1.20, -0.50, 5.38))                       # bay back wall
    D.box(bm, (-0.42, -0.50, 1.94), (-0.36, 0.56, 5.38))                       # bay liner -x
    D.box(bm, (1.18, -0.58, 1.86), (1.34, 0.62, 5.44))                         # bay liner +x
    D.new_obj("Whitework", bm, c, white, rbx_material="SmoothPlastic", roughness=0.42)

    # =========================================================== header light box + lettering
    bm = bmesh.new()
    D.beveled_box(bm, (-1.34, 0.74, 5.88), (1.34, 0.80, 6.42), bevel=0.05)
    D.new_obj("SignPanel", bm, c, lit, rbx_material="Neon", emit=0.85, roughness=0.3)

    bm = bmesh.new()
    D.stroke_text(bm, "SNACKS", (0.0, 0.835, 5.99), height=0.32, radius=0.055,
                  segs=3, plane='XZ')                        # 2.40 wide on a 2.68 panel
    D.stroke_text(bm, "1.50", (-0.88, 0.845, 5.12), height=0.15, radius=0.022,
                  segs=3, plane='XZ')                        # price readout in the column
    D.new_obj("NeonText", bm, c, glow, rbx_material="Neon", emit=1.3, roughness=0.3)

    # =========================================================== delivery flap, hung ajar
    # Panel and grab lip are both yawed 22 deg about the SAME axis; a rigid rotation is the
    # same whether each box turns about its own centre or the pair turns about the hinge,
    # so each literal is just its post-rotation position and every z stays above 0.
    # The panel sits at y 0.43..0.73 - clear of the chute wall at y 0.26 and just inside
    # the apron plane at y 0.76 - so the tilt, the highlight and the shadow all read.
    bm = bmesh.new()
    D.beveled_box(bm, (-0.10, 0.550, 0.944), (1.04, 0.610, 1.604), bevel=0.028,
                  rot=D.rot_euler(rx=-22))                   # the door itself
    D.beveled_box(bm, (-0.10, 0.4347, 0.9509), (1.04, 0.5747, 1.0109), bevel=0.02,
                  rot=D.rot_euler(rx=-22))                   # grab lip, proud along the bottom
    D.new_obj("DeliveryFlap", bm, c, door, rbx_material="Metal", metallic=0.2, roughness=0.45)

    return c
