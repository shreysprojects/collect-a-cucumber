"""Blender helpers for the 12-tier headband set (New Map Cucumber Game).

Re-exports everything from ../defenses/defenselib.py and adds the ring-specific helpers a
headband needs.  Same house conventions as the rest of the repo:

  * 1 Blender unit = 1 Roblox stud.  Blender Z up.
  * HEADBAND SPACE: the band is a ring centred on the ORIGIN, its axis along +Z (so +Z is
    "up" out of the top of the head), and the FRONT of the band - the forehead, where a
    centrepiece goes - faces **+Y**.
  * Roblox export is a pure rotation: (x, y, z)_rbx = (x, z, -y)_blender.  So Blender +Z
    (band axis) -> Roblox +Y (up) and Blender +Y (front) -> Roblox -Z, which is the
    direction an R15 character faces.  Both come out right with no extra rotation.
  * Per-object custom props rbx_hex / rbx_material / rbx_transparency carry the Roblox
    appearance so the installer can colour each MeshPart by name after the asset loads.

FIT: a default R15 head is 1.2 studs across with HatAttachment at (0, 0.6, 0) relative to
the head's centre.  The band wears at BAND_Z_ON_HEAD above the head centre, so the
accessory's Handle attachment goes at (0, BAND_Z_ON_HEAD, 0) in handle space.  R_IN is a
touch wider than the head at that height so the band never z-fights the face mesh.
"""
import sys, os, math, importlib.util

_HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else \
    r"C:\Users\shrey\OneDrive\Documents\RobloxGames\headbands"
_DEFLIB = os.path.join(os.path.dirname(_HERE), "defenses", "defenselib.py")

_spec = importlib.util.spec_from_file_location("defenselib", _DEFLIB)
_D = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_D)
sys.modules["defenselib"] = _D

# re-export the whole primitive library so build scripts only ever touch one module
globals().update({k: v for k, v in vars(_D).items() if not k.startswith("__")})

import bpy, bmesh, random                                    # noqa: E402
from mathutils import Vector, Matrix, Euler                  # noqa: E402

ROOT = _HERE

# ---------------------------------------------------------------- fit contract
HEAD_R = 0.60           # default R15 head half-width (head is 1.2 studs across)
R_IN = 0.63             # band inner radius - 0.03 of clearance over the head
R_OUT = 0.75            # band outer radius for a plain band (0.12 thick)
BAND_H = 0.26           # default band height along Z
BAND_Z_ON_HEAD = 0.28   # band centre, in studs above the head's centre, when worn
SEGS = 28               # ring segments - enough to read round at accessory scale


# ---------------------------------------------------------------- ring helpers
def on_ring(radius, angle_deg, z=0.0):
    """A point on the band's circle.  angle 0 = FRONT (+Y), and angle increases toward
    the wearer's LEFT (+X).  Use for placing decorations around the band."""
    a = math.radians(angle_deg)
    return (math.sin(a) * radius, math.cos(a) * radius, z)


def face_out(angle_deg, tilt_deg=0.0):
    """4x4 rotation for a decoration sitting at `angle_deg` on the ring, oriented so its
    local +Y points radially OUTWARD and its local +Z stays up.  `tilt_deg` leans it back."""
    return rot_euler(tilt_deg, 0, -angle_deg)                # noqa: F821  (from defenselib)


def ring_angles(n, span_deg=360.0, center_deg=0.0):
    """`n` angles spread over `span_deg`, centred on `center_deg`.  A full 360 span spaces
    them evenly all the way round; a smaller span makes an arc (a laurel, a row of gems)."""
    if n <= 0:
        return []
    if abs(span_deg) >= 359.999:
        return [center_deg + 360.0 * i / n for i in range(n)]
    if n == 1:
        return [center_deg]
    return [center_deg - span_deg / 2 + span_deg * i / (n - 1) for i in range(n)]


def band(bm, r_in=R_IN, r_out=R_OUT, z0=None, z1=None, segs=SEGS,
         arc_deg=360.0, center_deg=0.0, bulge=0.0, seed=None, jitter=0.0):
    """The core headband ring: an annulus (or an arc of one) from z0 to z1.

    `bulge` swells the outer radius at the ring's mid-height so the band reads as soft
    cloth rather than a flat washer - 0 keeps it a hard-edged ring (metal, stone).
    `jitter` + `seed` roughen the outer radius per segment (straw, rock, fur)."""
    z0 = -BAND_H / 2 if z0 is None else z0
    z1 = BAND_H / 2 if z1 is None else z1
    full = abs(arc_deg) >= 359.999
    n = max(3, int(segs if full else max(3, round(segs * abs(arc_deg) / 360.0))))
    rng = random.Random(seed if seed is not None else 0)
    steps = n if full else n + 1
    a0 = center_deg - (0.0 if full else arc_deg / 2)
    da = (360.0 / n) if full else (arc_deg / n)
    rows = []          # [ (inner_bot, inner_top, outer_bot, outer_mid, outer_top) ]
    for i in range(steps):
        a = math.radians(a0 + da * i)
        s, c = math.sin(a), math.cos(a)
        ro = r_out + (rng.uniform(-jitter, jitter) if jitter else 0.0)
        row = {
            "ib": bm.verts.new((s * r_in, c * r_in, z0)),
            "it": bm.verts.new((s * r_in, c * r_in, z1)),
            "ob": bm.verts.new((s * ro, c * ro, z0)),
            "ot": bm.verts.new((s * ro, c * ro, z1)),
        }
        if bulge > 1e-6:
            rm = ro + bulge
            row["om"] = bm.verts.new((s * rm, c * rm, (z0 + z1) / 2))
        rows.append(row)
    pairs = [(i, (i + 1) % steps) for i in range(steps)] if full else \
            [(i, i + 1) for i in range(steps - 1)]
    for i, j in pairs:
        A, B = rows[i], rows[j]
        bm.faces.new((A["ib"], A["it"], B["it"], B["ib"]))            # inner wall
        bm.faces.new((A["ot"], A["ob"], B["ob"], B["ot"]))            # outer wall (flipped)
        bm.faces.new((A["ib"], B["ib"], B["ob"], A["ob"]))            # bottom rim
        bm.faces.new((A["it"], A["ot"], B["ot"], B["it"]))            # top rim
        if bulge > 1e-6:
            bm.faces.new((A["ob"], A["om"], B["om"], B["ob"]))
            bm.faces.new((A["om"], A["ot"], B["ot"], B["om"]))
    if not full:                                                       # cap the two ends
        for row, flip in ((rows[0], False), (rows[-1], True)):
            quad = (row["ib"], row["ob"], row["ot"], row["it"])
            bm.faces.new(tuple(reversed(quad)) if flip else quad)
    out = [v for r in rows for v in r.values()]
    return out


def stripe(bm, r_in, r_out, z0, z1, segs=SEGS, arc_deg=360.0, center_deg=0.0):
    """A thin concentric ring - a painted stripe, a piping, a metal rim.  Same shape as
    band() with no bulge; give it a radius a hair outside the band it sits on."""
    return band(bm, r_in, r_out, z0, z1, segs=segs, arc_deg=arc_deg, center_deg=center_deg)


def stud_ring(bm, n, radius, z=0.0, size=0.07, kind="sphere", start_deg=0.0,
              segs=6, rings=4):
    """`n` rivets / beads / gems evenly round the band.  kind: sphere | cube | cone | gem."""
    made = []
    for a in ring_angles(n, 360.0, start_deg):
        p = on_ring(radius, a, z)
        if kind == "cube":
            made += cube(bm, p, size * 1.6, rot=face_out(a))           # noqa: F821
        elif kind == "cone":
            tip = on_ring(radius + size * 2.2, a, z)
            made += cone(bm, p, tip, size, 0.0, segs=segs)             # noqa: F821
        elif kind == "gem":
            made += octa_gem(bm, p, size, a)
        else:
            made += uvsphere(bm, p, size, segs=segs, rings=rings)      # noqa: F821
    return made


def octa_gem(bm, loc, r, angle_deg=0.0, point=1.5, flat=0.75):
    """A faceted gem/stud that points radially outward from the band - the classic
    pyramid-stud and diamond-boss shape.  `point` how far the outward tip sticks out."""
    m = Matrix.Translation(Vector(loc)) @ face_out(angle_deg)
    pts = [(0, r * point, 0), (0, -r * flat, 0),
           (r, 0, 0), (-r, 0, 0), (0, 0, r), (0, 0, -r)]
    v = [bm.verts.new(m @ Vector(p)) for p in pts]
    tip, back = v[0], v[1]
    ring = [v[2], v[4], v[3], v[5]]
    for i in range(4):
        a, b = ring[i], ring[(i + 1) % 4]
        bm.faces.new((a, b, tip))
        bm.faces.new((b, a, back))
    return v


def leaf(bm, loc, length, width, angle_deg=0.0, tilt_deg=0.0, curl_deg=0.0, thick=0.035):
    """A pointed leaf blade lying against the band, tip pointing up-and-out.  Built as a
    flat 6-gon prism so it stays cheap; `curl_deg` rolls the tip outward."""
    hw = width / 2
    prof = [(0.0, 0.0), (hw * 0.75, length * 0.22), (hw, length * 0.55),
            (0.0, length), (-hw, length * 0.55), (-hw * 0.75, length * 0.22)]
    m = Matrix.Translation(Vector(loc)) @ face_out(angle_deg) @ \
        rot_euler(90 - tilt_deg, 0, 0) @ rot_euler(0, curl_deg, 0)     # noqa: F821
    return prism(bm, prof, -thick / 2, thick / 2, matrix=m)            # noqa: F821


def knot(bm, loc, size, angle_deg=0.0, tail_len=0.42, tail_drop=0.30, seed=1):
    """A cloth knot with two tails - the bandana tie.  Lump plus two tapered tubes."""
    made = list(ico(bm, loc, size, subdiv=1, scale=(1.0, 0.85, 0.9)))  # noqa: F821
    base = Vector(loc)
    d = Vector((math.sin(math.radians(angle_deg)), math.cos(math.radians(angle_deg)), 0)).normalized()
    side = Vector((-d.y, d.x, 0))
    for k, (sp, dz) in enumerate(((1.0, 0.0), (-0.8, -tail_drop))):
        p0 = base + d * size * 0.7
        p1 = base + d * (size * 0.7 + tail_len * 0.55) + side * (sp * size * 0.9) + Vector((0, 0, dz * 0.45))
        p2 = base + d * (size * 0.7 + tail_len) + side * (sp * size * 1.7) + Vector((0, 0, dz))
        made += tube(bm, [p0, p1, p2], [size * 0.62, size * 0.42, 0.02], segs=6)  # noqa: F821
    return made


# ---------------------------------------------------------------- stage / render
def build_head_stage(show_head=True):
    """A grey head proxy at the origin so every headband render shows the fit.  The proxy
    is an egg 1.2 studs across whose CENTRE sits at z = -BAND_Z_ON_HEAD, i.e. the band is
    modelled where it will actually sit when worn."""
    c = coll("_Head")                                                  # noqa: F821
    clear_collection("_Head")                                          # noqa: F821
    if not show_head:
        return c
    bm = bmesh.new()
    uvsphere(bm, (0, 0, -BAND_Z_ON_HEAD), HEAD_R, segs=20, rings=14,   # noqa: F821
             scale=(1.0, 0.98, 1.12))
    new_obj("Head", bm, c, "c8b28a", roughness=0.85, smooth=True)      # noqa: F821
    bm = bmesh.new()
    box(bm, (-0.30, -0.62, -0.62), (0.30, -0.30, -0.34))               # noqa: F821  neck-ish block, back
    new_obj("Neck", bm, c, "9c8a6a", roughness=0.9)                    # noqa: F821
    return c


def report_fit(coll_name):
    """Bounds plus the numbers that decide whether it will actually sit on a head."""
    mins, maxs = bounds(coll_name)                                     # noqa: F821
    rep = report(coll_name)                                            # noqa: F821
    inner = 9e9
    for o in bpy.data.collections[coll_name].objects:
        if o.type != 'MESH':
            continue
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            # the tightest point ANYWHERE on the band is what decides head clearance
            inner = min(inner, math.hypot(p.x, p.y))
    rep["min_radius_at_band_height"] = round(inner, 3) if inner < 9e8 else None
    rep["head_clearance"] = round(inner - HEAD_R, 3) if inner < 9e8 else None
    rep["z_range"] = [round(mins.z, 3), round(maxs.z, 3)]
    return rep
