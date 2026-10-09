"""Painted garden watering can: tapered lathed body with a necked-in filling hole, a long
swan-neck spout carrying the rose out past the front, carry handle over the top and a grip
handle at the back.  Faces +Y (the spout and rose point +Y)."""
import bmesh, math

COLLECTION = "WateringCan"
NOTES = ("Sits on the ground, 2.0 studs tall to the top of the carry handle, body 1.48 wide. "
         "The spout swings out to y +2.1 and the rose lip reaches y +2.49 (z 1.09..1.77), so "
         "leave ~2.6 studs of clear ground in front of it.  The carry bar spans x -0.46..0.46 "
         "at z 1.92; the back grip is at y -0.86.  All one rigid prop, no moving parts.")


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    body = D.C("plastic_green")    # painted tin - the colour that carries the prop
    fit = D.C("iron_mid")          # every fitting: straps, handles, spout, rose
    dark = D.C("plastic_black")    # the perforated rose face
    bright = D.C("metal_light")    # bolt heads

    # ---- body: a taper, widest at the foot, necking in to a small filling hole so the
    # top is a shoulder and a dark bore instead of a wide flat plate of milk.
    bm = bmesh.new()
    D.lathe(bm, [(0.00, 0.00), (0.72, 0.00), (0.74, 0.12), (0.70, 0.70), (0.62, 1.35),
                 (0.42, 1.52), (0.34, 1.58),
                 (0.30, 1.55), (0.26, 1.05), (0.00, 1.00)], segs=12)
    D.new_obj("Body", bm, c, body, rbx_material="Metal", metallic=0.15, roughness=0.62)

    # ---- rolled rim round the filling hole, a waist strap and a foot strap
    bm = bmesh.new()
    D.lathe(bm, [(0.34, 1.44), (0.46, 1.50), (0.46, 1.58), (0.30, 1.62)], segs=12, cap=False)
    D.lathe(bm, [(0.66, 0.66), (0.76, 0.70), (0.76, 0.86), (0.66, 0.90)], segs=12, cap=False)
    D.lathe(bm, [(0.68, 0.01), (0.80, 0.05), (0.80, 0.17), (0.68, 0.21)], segs=12, cap=False)
    D.new_obj("Bands", bm, c, fit, rbx_material="Metal", metallic=0.25, roughness=0.5)

    # ---- swan neck: leaves the body low at the front, sweeps up past the shoulder and
    # levels off above rim height, 1.35 studs clear of the body front.
    bm = bmesh.new()
    pts = [(0.0, 0.30, 0.26), (0.0, 0.76, 0.34), (0.0, 1.24, 0.74),
           (0.0, 1.66, 1.22), (0.0, 1.94, 1.50), (0.0, 2.10, 1.54)]
    D.tube(bm, pts, [0.17, 0.15, 0.13, 0.115, 0.10, 0.095], segs=8)
    D.new_obj("Spout", bm, c, fit, rbx_material="Metal", metallic=0.25, roughness=0.5)

    # ---- rose head: a flared cup on the spout tip.  Its local +Z is the way the flare
    # opens, so rx=-115 aims it forward and 25 deg down - away from whoever is holding it.
    rose = D.place((0.0, 2.046, 1.565), D.rot_euler(rx=-115))
    bm = bmesh.new()
    D.lathe(bm, [(0.115, 0.00), (0.13, 0.08), (0.30, 0.20), (0.375, 0.31), (0.00, 0.31)],
            segs=10, matrix=rose)
    D.new_obj("RoseHead", bm, c, fit, rbx_material="Metal", metallic=0.25, roughness=0.5)

    # ---- the sprinkler plate: one chunky dark disc sunk in the flare, built in the rose's
    # own frame so it lands flush on the face instead of floating beside it.
    bm = bmesh.new()
    D.cyl(bm, (0.0, 0.0, 0.30), (0.0, 0.0, 0.35), 0.30, segs=10)
    D.xform(bm, list(bm.verts), rose)
    D.new_obj("RoseFace", bm, c, dark, rbx_material="Metal", metallic=0.2, roughness=0.6)

    # ---- carry handle: an arch over the filling hole, and a back grip
    bm = bmesh.new()
    arch = [(-0.52, 0.08, 1.40), (-0.46, -0.04, 1.78), (0.00, -0.08, 1.92),
            (0.46, -0.04, 1.78), (0.52, 0.08, 1.40)]
    D.tube(bm, arch, [0.08] * 5, segs=6)
    grip = [(0.00, -0.58, 1.26), (0.00, -0.86, 1.04), (0.00, -0.86, 0.66), (0.00, -0.60, 0.46)]
    D.tube(bm, grip, [0.08] * 4, segs=6)
    D.new_obj("Handles", bm, c, fit, rbx_material="Metal", metallic=0.25, roughness=0.5)

    # ---- bolt heads where the handles meet the body
    bm = bmesh.new()
    for p in ((-0.52, 0.08, 1.40), (0.52, 0.08, 1.40), (0.0, -0.60, 1.26), (0.0, -0.68, 0.46)):
        D.uvsphere(bm, p, 0.11, segs=6, rings=4)
    D.new_obj("Rivets", bm, c, bright, rbx_material="Metal", metallic=0.3, roughness=0.45)

    return c
