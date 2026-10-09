"""Museum display case: a dark metal plinth with a recessed toe kick and a chamfered top,
a deep-red velvet pad carrying a stepped display column, four slim brass corner posts,
five glass panes and a stepped brass crown with a brass spotlight hooked forward off its
back.  A dark downlight hood under the ceiling throws a visible cone of light down onto
the column.  Faces +Y."""
import bmesh, math

COLLECTION = "GlassCase"
NOTES = (
    "4 wide (x) x 3 deep (y) x 5.98 tall, centred on x=0/y=0, standing on z=0.  The front - "
    "the brass TROPHY nameplate and the lock plate - faces +Y.  The interior holds only the "
    "stepped display column, so the game can drop an item onto PIVOTS.DisplayPoint at "
    "runtime: that is the brass cap ring on top of the column at z 3.05, and the clear "
    "display volume above it is x -1.75..1.75, y -1.25..1.25, z 3.05..4.35 (the downlight "
    "collar hangs down to z 4.39).  Give GlassPanes and LightBeam CanCollide=false - "
    "LightBeam is the decorative cone of light between the downlight and the column and a "
    "spawned item stands inside it.  SpotLens carries BOTH Neon lenses: the downlight "
    "inside the case and the brass spotlight on the crown."
)
PIVOTS = {"DisplayPoint": (0.0, 0.0, 3.05)}


def _unit(a, b):
    """Unit vector a -> b.  Both lamps are canted in the YZ plane."""
    d = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    L = math.sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
    return (d[0] / L, d[1] / L, d[2] / L)


def _along(p, u, t):
    """`t` studs from p along unit vector u."""
    return (p[0] + u[0] * t, p[1] + u[1] * t, p[2] + u[2] * t)


def build(D):
    D.clear_collection(COLLECTION)
    c = D.coll(COLLECTION)

    dark = D.C("metal_dark")        # plinth + the display column
    ink = D.C("iron_dark")          # engraved lettering / keyhole / downlight hood
    brass = D.C("brass")            # frame, trim, crown, spotlight
    velvet = "7e2029"               # deep burgundy - palette cloth_red washes out to pink
    pane = D.C("glass_tint")        # the five panes
    warm = D.C("lamp_warm")         # both lamp lenses + the beam

    PX, PY = 1.82, 1.32             # corner-post centres
    POST_TOP = 5.22
    SILL_TOP = 1.34
    GLASS_TOP = 5.18
    GLASS_BOT = 1.32
    CROWN_TOP = 5.44                # the spotlight is mounted on this

    # the downlight hanging off the ceiling, canted forward so it aims at the column
    HOOD_A, HOOD_B = (0.0, -0.28, 5.06), (0.0, -0.18, 4.62)
    hood_u = _unit(HOOD_A, HOOD_B)
    # the crown spotlight: neck sitting on the upright, mouth hooked forward and down
    SPOT_A, SPOT_B = (0.0, -0.93, 5.82), (0.0, -0.33, 5.72)
    spot_u = _unit(SPOT_A, SPOT_B)

    # ---- plinth: recessed toe kick, main body, chamfered overhanging top ------------
    bm = bmesh.new()
    D.box(bm, (-1.64, -1.14, 0.00), (1.64, 1.14, 0.26))                          # toe kick
    D.beveled_box(bm, (-1.88, -1.38, 0.24), (1.88, 1.38, 0.94), bevel=0.08)      # body
    D.beveled_box(bm, (-2.00, -1.50, 0.94), (2.00, 1.50, 1.20), bevel=0.13)      # chamfer cap
    D.new_obj("Plinth", bm, c, dark, rbx_material="Metal", metallic=0.45, roughness=0.5)

    # ---- brass on the plinth: a reveal line under the cap, the nameplate, and (off to
    #      the viewer's RIGHT, i.e. -x) a lock escutcheon - the one asymmetric detail ---
    bm = bmesh.new()
    D.box(bm, (-1.92, 1.34, 0.80), (1.92, 1.42, 0.90))                           # front reveal
    D.box(bm, (-1.92, -1.42, 0.80), (1.92, -1.34, 0.90))                         # back reveal
    D.box(bm, (1.84, -1.42, 0.80), (1.92, 1.42, 0.90))                           # +x reveal
    D.box(bm, (-1.92, -1.42, 0.80), (-1.84, 1.42, 0.90))                         # -x reveal
    D.beveled_box(bm, (-1.24, 1.34, 0.28), (1.24, 1.44, 0.78), bevel=0.06)       # nameplate
    D.box(bm, (-1.68, 1.34, 0.36), (-1.40, 1.46, 0.72))                          # lock plate
    D.new_obj("PlinthTrim", bm, c, brass, rbx_material="Metal", metallic=0.75, roughness=0.32)

    # ---- velvet display pad ---------------------------------------------------------
    bm = bmesh.new()
    D.beveled_box(bm, (-1.68, -1.18, 1.20), (1.68, 1.18, 1.40), bevel=0.09)
    D.new_obj("VelvetPad", bm, c, velvet, rbx_material="Fabric", roughness=0.95)

    # ---- the display column: base plate, slim shaft, brass cap ring on top -----------
    #      Dark on purpose: it is lit from directly above, and a light metal here clipped
    #      to white.  The bright accent is the brass cap ring, built with the frame below.
    bm = bmesh.new()
    D.lathe(bm, [(0.02, 1.38), (0.75, 1.38), (0.75, 1.54), (0.60, 1.60),
                 (0.34, 1.72), (0.34, 2.86), (0.02, 2.86)], segs=10)
    D.new_obj("Pedestal", bm, c, dark, rbx_material="Metal", metallic=0.45, roughness=0.5)

    # ---- brass: four slim posts, the glazing sill, the stepped crown, the crown
    #      spotlight, the downlight rim and the cap ring on the column ------------------
    bm = bmesh.new()
    for (sx, sy) in ((PX, PY), (-PX, PY), (PX, -PY), (-PX, -PY)):
        D.prism(bm, D.rounded_rect_pts(0.26, 0.26, 0.07, segs=2, center=(sx, sy)),
                1.20, POST_TOP)
    D.box(bm, (-PX, 1.26, 1.20), (PX, 1.38, SILL_TOP))                           # sill front
    D.box(bm, (-PX, -1.38, 1.20), (PX, -1.26, SILL_TOP))                         # sill back
    D.box(bm, (1.76, -PY, 1.20), (1.88, PY, SILL_TOP))                           # sill +x
    D.box(bm, (-1.88, -PY, 1.20), (-1.76, PY, SILL_TOP))                         # sill -x
    D.beveled_box(bm, (-2.00, -1.50, 5.18), (2.00, 1.50, 5.32), bevel=0.09)      # crown, step 1
    D.beveled_box(bm, (-1.66, -1.18, 5.30), (1.66, 1.18, CROWN_TOP), bevel=0.07)  # crown, step 2
    # the spotlight the brief asks for, OUTSIDE on the crown: a mounting boss set back at
    # -y, a short upright, and a shade canted forward over the case.  Asymmetric in y, so
    # the silhouette hooks forward instead of reading as another lantern.
    D.beveled_box(bm, (-0.42, -1.20, 5.40), (0.42, -0.66, 5.56), bevel=0.06)     # mount boss
    D.cyl(bm, (0.0, -0.93, 5.44), (0.0, -0.93, 5.80), 0.10, segs=6)              # upright
    D.cyl(bm, SPOT_A, SPOT_B, 0.16, segs=8, r2=0.26)                             # shade
    # thin brass rim around the mouth of the dark downlight hood inside the case
    D.cyl(bm, HOOD_B, _along(HOOD_B, hood_u, 0.09), 0.54, segs=8, r2=0.66, cap=False)
    # cap ring on top of the display column - DisplayPoint sits on its top face
    D.lathe(bm, [(0.02, 2.82), (0.62, 2.88), (0.62, 2.99), (0.56, 3.05), (0.02, 3.05)],
            segs=10)
    D.new_obj("BrassFrame", bm, c, brass, rbx_material="Metal", metallic=0.75, roughness=0.32)

    # ---- the downlight hood: dark, so it separates from the tinted pane in front of it -
    bm = bmesh.new()
    D.cyl(bm, HOOD_A, HOOD_B, 0.26, segs=8, r2=0.54)
    D.new_obj("LampHood", bm, c, ink, rbx_material="Metal", metallic=0.4, roughness=0.45)

    # ---- the five panes -------------------------------------------------------------
    bm = bmesh.new()
    D.box(bm, (-1.78, 1.28, GLASS_BOT), (1.78, 1.36, GLASS_TOP))                 # front
    D.box(bm, (-1.78, -1.36, GLASS_BOT), (1.78, -1.28, GLASS_TOP))               # back
    D.box(bm, (1.78, -1.28, GLASS_BOT), (1.86, 1.28, GLASS_TOP))                 # +x
    D.box(bm, (-1.86, -1.28, GLASS_BOT), (-1.78, 1.28, GLASS_TOP))               # -x
    D.box(bm, (-1.86, -1.36, 5.06), (1.86, 1.36, GLASS_TOP))                     # top
    D.new_obj("GlassPanes", bm, c, pane, rbx_material="Glass", transparency=0.5,
              metallic=0.0, roughness=0.12)

    # ---- both lenses, each square to its own lamp axis --------------------------------
    bm = bmesh.new()
    D.cyl(bm, _along(HOOD_B, hood_u, 0.01), _along(HOOD_B, hood_u, 0.05),
          0.45, segs=8)                                                          # downlight
    D.cyl(bm, _along(SPOT_B, spot_u, -0.07), _along(SPOT_B, spot_u, -0.03),
          0.21, segs=8)                                                          # crown spot
    D.new_obj("SpotLens", bm, c, warm, rbx_material="Neon", emit=1.0, roughness=0.3)

    # ---- the beam: a soft cone of light filling the air between lamp and column -------
    bm = bmesh.new()
    D.cyl(bm, (0.0, -0.16, 4.54), (0.0, 0.0, 3.08), 0.40, segs=10, r2=0.78, cap=False)
    D.new_obj("LightBeam", bm, c, warm, rbx_material="Neon", transparency=0.8, emit=1.1,
              roughness=0.4)

    # ---- engraved lettering + the dark keyhole in the lock plate ---------------------
    bm = bmesh.new()
    D.stroke_text(bm, "TROPHY", (0.0, 1.455, 0.39), height=0.28, radius=0.034,
                  segs=3, plane='XZ')
    D.box(bm, (-1.58, 1.42, 0.46), (-1.50, 1.48, 0.62))
    D.new_obj("Engraving", bm, c, ink, rbx_material="Metal", metallic=0.3, roughness=0.6)

    return c
