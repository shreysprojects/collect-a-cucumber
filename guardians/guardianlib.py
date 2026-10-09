"""Blender helpers for the ten biome guardians.

Everything `cucumberlib` exports (which is everything `proplib` and `defenselib` export)
is re-exported here, so a build script only ever touches `G.<something>`.  On top of
that this file adds the three things the guardians need and the cucumbers did not:

  1. `G.part(...)` - a part whose ORIGIN IS ITS JOINT, named `<Prefix>_<Part>_<Role>`,
     with its rig parent recorded on the object.  The FBX pipeline drops materials, so
     the colour comes back from the role name; the pivot and parent come back from the
     custom properties and from `manifest.json`.
  2. `G.apply_pose(...)` - pose the model by rotating parts about those pivots, which is
     how a build gets checked: if a pose looks right, the pivots are right.
  3. the shapes ten guardians need - fur and straw tufts, boulder seams, crescents,
     barnacles, pincers, horns, worm rings, mittens, fins, diamonds, tassels.

Conventions (identical to the cucumber set):
  * 1 Blender unit = 1 Roblox stud.  Z up, ground at z = 0, nothing below it.
  * Every guardian FACES +Y.  The FBX importer yaws 180 degrees, so the authored +Y
    front lands on Roblox -Z - which IS the model's LookVector.  Author +Y, get -Z.
  * Flat shaded, one flat colour per piece, box-projected UVs, triangulated.
  * An R15 avatar is ~5 studs tall; `build_stage()` puts one in every render.
  * The +X / screen-left trap: renders look down -Y, so +X appears on the LEFT.
"""
import bpy, bmesh, math, random, sys, importlib.util
from mathutils import Vector, Matrix, Euler

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\guardians"
_CUCUMBERLIB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\cucumbers\cucumberlib.py"
_GMATH = ROOT + r"\gmath.py"


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    sys.modules[name] = m
    return m


_CL = _load(_CUCUMBERLIB, "cucumberlib")
for _k in dir(_CL):                       # box, cyl, prism, lathe, tube, rock, render...
    if not _k.startswith("_"):
        globals()[_k] = getattr(_CL, _k)

from gmath import *                        # noqa: F401,F403  (roles, spec, pure maths)
_GM = _load(_GMATH, "gmath")

_cl_new_obj = _CL.new_obj
MOVING_DEFAULT = True


# ================================================================ the part registry
# Filled by begin()/part(); also mirrored onto each object's custom properties so the
# manifest can be rebuilt from a saved .blend without re-running the build scripts.
REG = {}            # collection -> {"guardian":, "prefix":, "parts": [...]}


def begin(collection, guardian, prefix=None):
    """Start (or restart) a collection.  Clears it, so every build is idempotent."""
    if guardian not in ROLES:
        raise KeyError("unknown guardian %r - known: %s" % (guardian, ", ".join(sorted(ROLES))))
    _CL.clear_collection(collection)
    c = _CL.coll(collection)
    REG[collection] = {"guardian": guardian, "prefix": prefix or collection, "parts": []}
    return c


def part(name, bm, c, role, pivot, parent=None, material=None, transparency=0.0,
         moving=None, emit=None, roughness=0.55, metallic=0.0, smooth=False,
         hex_override=None):
    """Finish `bm` into a guardian part whose ORIGIN sits at `pivot`.

    `name`   - the joint's name, e.g. "Arm_L" or "Jaw_Upper" (no guardian, no colour).
    `role`   - a key in ROLES[guardian]; it becomes the last token of the object name
               and is how Roblox gets the colour back after the FBX drops it.
    `pivot`  - (x, y, z) in WORLD space: the point this piece rotates about.  Geometry
               is authored in world space as usual; this function moves it so the
               object's origin lands exactly on the joint.
    `parent` - the part NAME this one hangs off in the rig ("Torso"), or None for the
               root.  Motor6Ds are built straight from this in Studio.
    """
    reg = REG.get(c.name)
    if reg is None:
        raise RuntimeError("call G.begin(%r, guardian) before making parts" % c.name)
    g = reg["guardian"]
    hexcol = hex_override or role_hex(g, role)
    mat = material or ("Neon" if is_neon(g, role) else "SmoothPlastic")
    if emit is None and mat == "Neon":
        emit = 0.62                      # over ~0.65 a warm hue renders as pale yellow
    full = "%s_%s_%s" % (reg["prefix"], name, role)

    p = Vector(pivot)
    if p.length > 1e-9:
        bmesh.ops.transform(bm, matrix=Matrix.Translation(-p), verts=list(bm.verts))
    obj = _cl_new_obj(name + "_" + role, bm, c, hexcol, rbx_material=mat,
                      transparency=transparency, metallic=metallic, roughness=roughness,
                      smooth=smooth, emit=emit)
    obj.name = full
    obj.data.name = full
    obj.location = tuple(p)
    if transparency >= 0.99:
        obj.hide_render = True           # the hitbox must not block its own hero render

    sl = sleep_look(g, role)
    obj["rbx_guardian"] = g
    obj["rbx_part"] = name
    obj["rbx_role"] = role
    obj["rbx_parent"] = parent or ""
    obj["rbx_pivot"] = [round(float(v), 4) for v in p]
    obj["rbx_moving"] = bool(MOVING_DEFAULT if moving is None else moving)
    obj["rbx_order"] = len(reg["parts"])
    if sl:
        obj["rbx_sleep_hex"], obj["rbx_sleep_material"] = sl[0], sl[1]
    reg["parts"].append({"name": name, "role": role, "parent": parent or None,
                         "pivot": list(obj["rbx_pivot"]), "object": full})
    return obj


def hitbox(c, lo, hi, pivot=None, parent=None, name="Hitbox", role="Invisible"):
    """The invisible query box.  Sized to the whole guardian, never rendered."""
    bm = bmesh.new()
    _CL.box(bm, lo, hi, None)
    mid = ((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0, (lo[2] + hi[2]) / 2.0)
    return part(name, bm, c, role, pivot or mid, parent=parent, transparency=1.0,
                moving=False)


def root_part(c, lo, hi, name="Root", role="Invisible"):
    """The rig root - an invisible box at hip height that becomes HumanoidRootPart."""
    return hitbox(c, lo, hi, parent=None, name=name, role=role)


# ================================================================ posing / checking
def _parts_of(cname):
    out = {}
    for o in bpy.data.collections[cname].objects:
        if o.type == 'MESH' and o.get("rbx_part"):
            out[o["rbx_part"]] = o
    return out


def rest(cname):
    """Put every part back where it was built."""
    for o in bpy.data.collections[cname].objects:
        if o.type == 'MESH' and o.get("rbx_pivot") is not None:
            o.matrix_world = Matrix.Translation(Vector(tuple(o["rbx_pivot"])))
    bpy.context.view_layer.update()


def apply_pose(cname, pose, extra_loc=None):
    """Rotate parts about their own pivots, carrying children along.

    `pose` maps a part name to (rx, ry, rz) in DEGREES (XYZ order, applied in the part's
    REST world frame).  `extra_loc` maps a part name to a (dx, dy, dz) offset applied
    after its rotation - for a hover, a crouch, a rock pile collapsing into itself.

    A part's mesh is stored relative to its pivot, so this is exactly the transform the
    Motor6D chain will apply in Roblox: if the pose reads right here, the rig is right.
    """
    objs = _parts_of(cname)
    parent = {n: (o["rbx_parent"] or None) for n, o in objs.items()}
    cache = {}

    def acc(n):
        """The 4x4 that maps a REST world point of `n` (or its subtree) to posed world."""
        if n in cache:
            return cache[n]
        o = objs[n]
        p = Vector(tuple(o["rbx_pivot"]))
        rx, ry, rz = pose.get(n, (0.0, 0.0, 0.0))
        r = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_matrix().to_4x4()
        local = Matrix.Translation(p) @ r @ Matrix.Translation(-p)
        if extra_loc and n in extra_loc:
            local = Matrix.Translation(Vector(extra_loc[n])) @ local
        up = parent.get(n)
        m = (acc(up) @ local) if (up and up in objs) else local
        cache[n] = m
        return m

    for n, o in objs.items():
        o.matrix_world = acc(n) @ Matrix.Translation(Vector(tuple(o["rbx_pivot"])))
    bpy.context.view_layer.update()
    return cache


def rig_tree(cname):
    """{part: {parent, role, pivot, object}} straight off the objects in the .blend."""
    out = {}
    for o in sorted(bpy.data.collections[cname].objects, key=lambda o: o.get("rbx_order", 0)):
        if o.type != 'MESH' or not o.get("rbx_part"):
            continue
        out[o["rbx_part"]] = {"parent": o["rbx_parent"] or None, "role": o["rbx_role"],
                              "pivot": [round(float(v), 4) for v in o["rbx_pivot"]],
                              "object": o.name, "moving": bool(o.get("rbx_moving", True)),
                              "hex": o.get("rbx_hex", "ffffff"),
                              "material": o.get("rbx_material", "SmoothPlastic"),
                              "transparency": float(o.get("rbx_transparency", 0.0)),
                              "sleep_hex": o.get("rbx_sleep_hex", ""),
                              "sleep_material": o.get("rbx_sleep_material", ""),
                              "tris": len(o.data.polygons)}
    return out


def check_rig(cname):
    """Problems a build script can create and a render will not show."""
    tree = rig_tree(cname)
    bad = []
    for n, d in tree.items():
        p = d["parent"]
        if p and p not in tree:
            bad.append("%s: parent %r does not exist" % (n, p))
        seen, cur = {n}, p
        while cur:
            if cur in seen:
                bad.append("%s: parent cycle through %s" % (n, cur))
                break
            seen.add(cur)
            cur = tree.get(cur, {}).get("parent")
    roots = [n for n, d in tree.items() if not d["parent"]]
    if len(roots) != 1:
        bad.append("expected exactly one root part, found %s" % (roots or "none"))
    return bad


# ================================================================ shapes: soft stuff
def tuft(bm, base, direction=(0, 0, 1), n=5, length=0.8, width=0.16, spread_deg=55.0,
         seed=1, segs=3, vary=0.35, curve=0.0):
    """A burst of tapering spikes from one point - straw at a wrist, fur on a shoulder,
    a hay tuft, a tail brush.  `spread_deg` is the half-angle of the cone."""
    rng = random.Random(seed)
    dirs = sphere_dirs(n, seed=seed, cone_deg=max(2.0, spread_deg * 2.0), axis=direction)
    out = []
    for i, d in enumerate(dirs):
        L = length * (1.0 - vary + 2.0 * vary * rng.random())
        tip = (base[0] + d[0] * L, base[1] + d[1] * L, base[2] + d[2] * L - curve * L)
        out += _CL.cyl(bm, base, tip, width * (0.8 + 0.4 * rng.random()), segs=segs, r2=0.0)
    return out


def spike_shard(bm, base, tip, width, thick=None, roll_deg=0.0):
    """A flat triangular shard - one scale of a yeti's fur, a straw blade, an ice flake.
    Cheaper and blockier than a cone: 4 faces."""
    b, t = Vector(base), Vector(tip)
    d = t - b
    if d.length < 1e-9:
        return []
    thick = width * 0.45 if thick is None else thick
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-6:
        side = d.cross(Vector((0, 1, 0)))
    side = side.normalized()
    fwd = d.normalized().cross(side).normalized()
    if roll_deg:
        a = math.radians(roll_deg)
        side, fwd = (side * math.cos(a) + fwd * math.sin(a)), (fwd * math.cos(a) - side * math.sin(a))
    vs = [bm.verts.new(b + side * (width / 2.0) + fwd * (thick / 2.0)),
          bm.verts.new(b - side * (width / 2.0) + fwd * (thick / 2.0)),
          bm.verts.new(b - side * (width / 2.0) - fwd * (thick / 2.0)),
          bm.verts.new(b + side * (width / 2.0) - fwd * (thick / 2.0))]
    apex = bm.verts.new(t)
    bm.faces.new(tuple(reversed(vs)))
    for i in range(4):
        bm.faces.new((vs[i], vs[(i + 1) % 4], apex))
    return vs + [apex]


def fur_coat(bm, center, radii, n=24, length=0.9, width=0.5, seed=1, cone_deg=180.0,
             axis=(0, 0, 1), vary=0.3, out_bias=0.55, shard=True, droop=0.0):
    """Shaggy spikes all over an ellipsoid - the yeti's whole silhouette.

    Each spike roots on the surface and points OUT, tilted by `out_bias` toward the
    surface normal (1.0 = straight out, 0.0 = straight along `axis`)."""
    rng = random.Random(seed)
    dirs = sphere_dirs(n, seed=seed, cone_deg=cone_deg, axis=axis)
    roots = ellipsoid_points(center, radii, dirs)
    ax = norm3(axis)
    out = []
    for i, (d, r) in enumerate(zip(dirs, roots)):
        L = length * (1.0 - vary + 2.0 * vary * rng.random())
        v = norm3((d[0] * out_bias + ax[0] * (1 - out_bias),
                   d[1] * out_bias + ax[1] * (1 - out_bias),
                   d[2] * out_bias + ax[2] * (1 - out_bias)))
        tip = (r[0] + v[0] * L, r[1] + v[1] * L, r[2] + v[2] * L - droop * L)
        root = (r[0] - d[0] * L * 0.28, r[1] - d[1] * L * 0.28, r[2] - d[2] * L * 0.28)
        if shard:
            out += spike_shard(bm, root, tip, width * (0.75 + 0.5 * rng.random()),
                               roll_deg=rng.uniform(0, 180))
        else:
            out += _CL.cyl(bm, root, tip, width * 0.5, segs=3, r2=0.0)
    return out


def blob(bm, center, radii, seed=1, jitter=0.16, subdiv=1):
    """A faceted lump: `rock` with per-axis radii instead of one radius."""
    return _CL.rock(bm, center, 1.0, seed=seed, jitter=jitter, subdiv=subdiv, scale=radii)


def puff(bm, center, radius, seed=1, blobs=3, spread=0.55):
    """A little cloud - steam from a nose, dust at a foot, a snow burst."""
    return _CL.foliage(bm, center, radius, seed=seed, blobs=blobs, spread=spread,
                       jitter=0.22, subdiv=1)


def tassel(bm, top, length=0.9, n=3, width=0.13, spread=0.22, seed=1, sway=0.0):
    """Hanging strips - a rope tassel, a ribbon end, a torn hem."""
    rng = random.Random(seed)
    out = []
    for i in range(n):
        a = 2.0 * math.pi * i / float(n) + rng.random()
        off = (math.cos(a) * spread, math.sin(a) * spread, 0.0)
        L = length * (0.75 + 0.5 * rng.random())
        base = (top[0] + off[0] * 0.3, top[1] + off[1] * 0.3, top[2])
        tip = (base[0] + off[0] + sway, base[1] + off[1], base[2] - L)
        out += _CL.cyl(bm, base, tip, width, segs=4, r2=width * 0.45)
    return out


# ================================================================ shapes: hard stuff
def seam_strip(bm, a, b, width=0.22, thick=None, segs=4, bulge=1.0):
    """The glowing lava seam that fills the gap between two boulders.  A short fat tube
    is right: it reads as light leaking out of a crack from every angle."""
    thick = width if thick is None else thick
    pts = chain_points(a, b, 3)
    rs = [width * 0.55, width * 0.5 * (1.0 + bulge), width * 0.55]
    return _CL.tube(bm, pts, rs, segs=segs)


def boulder_cluster(bm, slots, radius=0.9, seed=1, jitter=0.3, scale=(1, 1, 1),
                    vary=0.35, subdiv=1):
    """Several jittered boulders in one mesh - Ember's limbs, a rock pile, rubble."""
    rng = random.Random(seed)
    out = []
    for i, s in enumerate(slots):
        r = radius * (1.0 - vary + 2.0 * vary * rng.random())
        out += _CL.rock(bm, s, r, seed=seed * 97 + i, jitter=jitter, subdiv=subdiv,
                        scale=scale)
    return out


def crescent(bm, center=(0, 0, 0), r_out=1.0, r_in=0.8, offset=0.42, thick=0.5,
             open_deg=150.0, n=14, rot=None, plane="XZ"):
    """A crescent moon standing in the XZ plane (horns up) by default."""
    prof = crescent_profile(r_out, r_in, offset, n, open_deg)
    if plane == "XZ":       # profile y -> world z, extruded along y (a rotation, det +1)
        m = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    else:                                   # lying flat, extruded up Z
        m = Matrix.Identity(4)
    mat = Matrix.Translation(Vector(center)) @ (rot or Matrix.Identity(4)) @ m
    return _CL.prism(bm, prof, -thick / 2.0, thick / 2.0, matrix=mat)


def hex_prism(bm, center, radius, height, axis=(0, 0, 1), sides=6, phase=0.0, taper=1.0):
    """An n-sided plate/peg pointing along `axis` - a bolt head, an eye plate, a pip."""
    base = ngon_pts(sides, radius, phase=phase)
    mat = Matrix.Translation(Vector(center)) @ _CL.aim(axis)
    vs = _CL.prism(bm, base, -height / 2.0, height / 2.0, matrix=mat)
    if taper != 1.0:
        top = [v for v in vs if (Vector(v.co) - Vector(center)).dot(Vector(norm3(axis))) > 0]
        for v in top:
            c = Vector(center) + Vector(norm3(axis)) * (height / 2.0)
            v.co = c + (Vector(v.co) - c) * taper
    return vs


def diamond(bm, center, radius=0.3, length=0.8, axis=(0, 0, 1), sides=4, phase=0.0,
            squash=1.0):
    """A four-point star gem - Orbit's starlight pips, a crystal, a glint."""
    mat = Matrix.Translation(Vector(center)) @ _CL.aim(axis)
    ring = [bm.verts.new(mat @ Vector((math.cos(phase + 2 * math.pi * i / sides) * radius,
                                       math.sin(phase + 2 * math.pi * i / sides) * radius * squash,
                                       0.0))) for i in range(sides)]
    top = bm.verts.new(mat @ Vector((0, 0, length / 2.0)))
    bot = bm.verts.new(mat @ Vector((0, 0, -length / 2.0)))
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((ring[i], ring[j], top))
        bm.faces.new((ring[j], ring[i], bot))
    return ring + [top, bot]


def ring_band(bm, center, axis=(0, 0, 1), radius=0.4, minor=0.09, seg_major=12,
              seg_minor=5):
    """A torus around an arbitrary axis - a nose ring, a rope band, a key loop."""
    return _CL.torus(bm, center, radius, minor, rot=_CL.aim(axis),
                     seg_major=seg_major, seg_minor=seg_minor)


def horn(bm, base, tip, r0=0.34, r1=0.03, bow=(0, 0, 0), n=6, segs=6, power=1.2):
    """A tapering, optionally curved horn / tusk / spine."""
    pts = chain_points(base, tip, n, bow=bow)
    return _CL.tube(bm, pts, taper(r0, r1, n, power=power), segs=segs)


def limb(bm, a, b, r0, r1=None, segs=6, bow=(0, 0, 0), n=4):
    """A tapering limb segment as a low-poly tube - arms, legs, stalks, necks."""
    r1 = r0 if r1 is None else r1
    pts = chain_points(a, b, n, bow=bow)
    return _CL.tube(bm, pts, taper(r0, r1, n), segs=segs)


def claw_jaw(bm, hinge, tip, width=0.55, thick=0.5, curve=0.25, teeth=0, side=1,
             root_w=None):
    """One half of a pincer: a wedge from the hinge to a point, bowed sideways so the
    two halves meet only at the tip.  `side` mirrors the bow."""
    root_w = width if root_w is None else root_w
    h, t = Vector(hinge), Vector(tip)
    d = (t - h)
    L = d.length
    if L < 1e-9:
        return []
    fwd = d.normalized()
    up = Vector((0, 0, 1)) if abs(fwd.z) < 0.9 else Vector((0, 1, 0))
    side_v = fwd.cross(up).normalized()
    up = side_v.cross(fwd).normalized()
    pts, rs = [], []
    for i in range(5):
        f = i / 4.0
        p = h + fwd * (L * f) + side_v * (side * curve * L * math.sin(math.pi * f) * 0.5)
        pts.append(tuple(p))
        rs.append(max(0.02, (root_w * (1.0 - f) + width * 0.10 * f) * 0.5))
    out = _CL.tube(bm, pts, rs, segs=5)
    if teeth:
        for i in range(teeth):
            f = 0.3 + 0.6 * i / float(max(1, teeth - 1))
            p = h + fwd * (L * f) + side_v * (side * curve * L * math.sin(math.pi * f) * 0.5)
            q = p - side_v * side * (root_w * 0.42)
            out += _CL.cyl(bm, tuple(p), tuple(q), root_w * 0.13, segs=3, r2=0.0)
    return out


def barnacle(bm, center, normal=(0, 0, 1), r_out=0.26, r_in=0.13, height=0.16, segs=8):
    """A crusted ring nub with a hollow middle - the discs all over the crab's shell."""
    prof = [(0.0, 0.0), (r_out, 0.0), (r_out * 0.96, height), (r_in, height),
            (r_in * 0.92, height * 0.35), (0.0, height * 0.30)]
    mat = Matrix.Translation(Vector(center)) @ _CL.aim(normal)
    return _CL.lathe(bm, prof, segs=segs, matrix=mat)


def stud_bump(bm, center, normal=(0, 0, 1), radius=0.16, height=0.14, segs=5, taper=0.55):
    """A blunt raised stud - a club's studs, a rivet, a wart."""
    prof = [(0.0, 0.0), (radius, 0.0), (radius * taper, height), (0.0, height)]
    mat = Matrix.Translation(Vector(center)) @ _CL.aim(normal)
    return _CL.lathe(bm, prof, segs=segs, matrix=mat)


def patch(bm, center, normal=(0, 0, 1), radius=0.5, height=0.14, seed=1, jitter=0.22,
          segs=7):
    """A flat irregular shell stuck on a surface - moss on a shoulder, mud, a scab."""
    rng = random.Random(seed)
    pts = [(math.cos(2 * math.pi * i / segs) * radius * (1.0 - jitter + 2 * jitter * rng.random()),
            math.sin(2 * math.pi * i / segs) * radius * (1.0 - jitter + 2 * jitter * rng.random()))
           for i in range(segs)]
    mat = Matrix.Translation(Vector(center)) @ _CL.aim(normal)
    return _CL.prism(bm, pts, 0.0, height, matrix=mat)


def cross_glyph(bm, center, normal=(0, 1, 0), arm=0.28, thick=0.09, depth=0.06,
                spin_deg=0.0):
    """A + (or, at spin 45, an X) lying on a surface - a stitched mouth, an eye cross,
    a button.  Two crossed bars, so it reads at 100 studs."""
    m = _CL.surface_frame(normal) if hasattr(_CL, "surface_frame") else _CL.aim(normal)
    mat = Matrix.Translation(Vector(center)) @ m @ Matrix.Rotation(math.radians(spin_deg), 4, 'Z')
    out = _CL.box(bm, (-arm, -thick / 2.0, -depth / 2.0), (arm, thick / 2.0, depth / 2.0))
    out += _CL.box(bm, (-thick / 2.0, -arm, -depth / 2.0), (thick / 2.0, arm, depth / 2.0))
    bmesh.ops.transform(bm, matrix=mat, verts=out)
    return out


def plate(bm, pts2d, thick, at=(0, 0, 0), normal=(0, 1, 0), spin_deg=0.0):
    """Extrude a 2-D outline into a flat plate - a fin, a jaw petal, a visor, an armour
    scale, a sign.  `normal` is the direction the plate's THICKNESS runs, so the outline
    lies in the plane perpendicular to it; `spin_deg` rolls the outline about it.  With
    the default (0, 1, 0) the outline is drawn in world XZ facing the camera."""
    m = _CL.surface_frame(normal) if hasattr(_CL, "surface_frame") else _CL.aim(normal)
    mat = Matrix.Translation(Vector(at)) @ m @ Matrix.Rotation(math.radians(spin_deg), 4, 'Z')
    return _CL.prism(bm, pts2d, -thick / 2.0, thick / 2.0, matrix=mat)


def mitten(bm, center, size=(0.7, 0.55, 0.8), thumb=0.3, bevel=0.14, facing=(0, 1, 0)):
    """A toy robot's fist - a bevelled box with a thumb nub on one side."""
    sx, sy, sz = size
    out = _CL.beveled_box(bm, (center[0] - sx / 2, center[1] - sy / 2, center[2] - sz / 2),
                          (center[0] + sx / 2, center[1] + sy / 2, center[2] + sz / 2),
                          bevel=bevel)
    if thumb > 0:
        f = norm3(facing)
        c = (center[0] + f[0] * sx * 0.35 + 0.0, center[1] + f[1] * sy * 0.35,
             center[2] + sz * 0.18)
        out += _CL.cyl(bm, c, (c[0] + f[0] * thumb, c[1] + f[1] * thumb, c[2] + thumb * 0.25),
                       thumb * 0.42, segs=6, r2=thumb * 0.3)
    return out


def worm_ring(bm, center, axis=(0, 0, 1), radius=1.2, thick=0.55, lip=0.12, segs=10,
              spikes=0, spike_len=0.35, phase=0.0):
    """One armoured body ring of the sand worm: a short drum with a raised leading lip
    and optional backward-swept spikes."""
    prof = [(0.0, -thick / 2.0), (radius, -thick / 2.0), (radius + lip, 0.0),
            (radius, thick / 2.0), (0.0, thick / 2.0)]
    mat = Matrix.Translation(Vector(center)) @ _CL.aim(axis)
    out = _CL.lathe(bm, prof, segs=segs, matrix=mat)
    for i in range(spikes):
        a = phase + 2 * math.pi * i / float(spikes)
        base = Vector((math.cos(a) * radius, math.sin(a) * radius, 0.0))
        tip = Vector((math.cos(a) * (radius + spike_len), math.sin(a) * (radius + spike_len),
                      -spike_len * 0.55))
        out += _CL.cyl(bm, tuple(mat @ base), tuple(mat @ tip), thick * 0.22, segs=4, r2=0.0)
    return out


def tooth_ring(bm, center, axis=(0, 0, 1), radius=1.0, n=8, length=0.42, width=0.16,
               phase=0.0, inward=0.35):
    """A ring of tooth pegs pointing inward-and-forward - a maw."""
    mat = Matrix.Translation(Vector(center)) @ _CL.aim(axis)
    out = []
    for i in range(n):
        a = phase + 2 * math.pi * i / float(n)
        b = Vector((math.cos(a) * radius, math.sin(a) * radius, 0.0))
        t = Vector((math.cos(a) * radius * (1.0 - inward), math.sin(a) * radius * (1.0 - inward),
                    length))
        out += _CL.cyl(bm, tuple(mat @ b), tuple(mat @ t), width, segs=4, r2=width * 0.12)
    return out


def swirl(bm, top, bottom, r0=0.9, r1=0.05, turns=1.1, n=14, segs=6, wobble=0.25):
    """A tapering corkscrew tail - Orbit's lower body, smoke, a genie's wisp."""
    pts, rs = [], []
    for i in range(n):
        t = i / float(n - 1)
        p = lerp3(top, bottom, t)
        a = 2.0 * math.pi * turns * t
        w = wobble * (1.0 - t) * (r0)
        pts.append((p[0] + math.cos(a) * w, p[1] + math.sin(a) * w, p[2]))
        rs.append(r0 + (r1 - r0) * (t ** 0.8))
    return _CL.tube(bm, pts, rs, segs=segs)


def face_text(bm, text, center, normal=(0, 1, 0), height=0.6, radius=0.05, segs=4,
              spin_deg=0.0, depth=0.0):
    """Stroke letters raised on a surface - the A B C on a toy block."""
    pre = set(bm.verts)
    _CL.stroke_text(bm, text, origin=(0, 0, 0), height=height, radius=radius, segs=segs,
                    plane='XZ', center=True)
    new = [v for v in bm.verts if v not in pre]
    m = _CL.surface_frame(normal) if hasattr(_CL, "surface_frame") else _CL.aim(normal)
    # stroke_text writes in the XZ plane, read from +Y, so its screen-right is -X.
    # surface_frame maps local +Z onto `normal` and local +Y onto `up`, so the glyph
    # needs (x, y, z) -> (-x, z, y): screen-right -> +X, glyph up -> +Y, normal -> +Z.
    # (det +1, so it is a rotation and the letters are not mirrored.)
    flip = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    mat = (Matrix.Translation(Vector(center) + Vector(norm3(normal)) * depth) @ m
           @ Matrix.Rotation(math.radians(spin_deg), 4, 'Z') @ flip
           @ Matrix.Translation(Vector((0, 0, -height / 2.0))))
    bmesh.ops.transform(bm, matrix=mat, verts=new)
    return new


def plank(bm, a, b, w=0.34, t=0.26, bevel=0.04):
    """A square-section wooden beam between two points - the scarecrow's cross pole,
    a fence rail, a torii lintel."""
    av, bv = Vector(a), Vector(b)
    d = bv - av
    L = d.length
    if L < 1e-9:
        return []
    mat = Matrix.Translation((av + bv) / 2.0) @ _CL.aim(d)
    pre = set(bm.verts)
    _CL.beveled_box(bm, (-w / 2, -t / 2, -L / 2), (w / 2, t / 2, L / 2), bevel=bevel)
    new = [v for v in bm.verts if v not in pre]
    bmesh.ops.transform(bm, matrix=mat, verts=new)
    return new


def shell_fan(bm, center, normal=(0, 1, 0), radius=2.0, ribs=7, thick=0.35, spread_deg=150.0,
              rise=0.35):
    """A scallop shell - the crab's nook, a clam, a fan.  Ribbed half-disc."""
    out = []
    m = _CL.surface_frame(normal) if hasattr(_CL, "surface_frame") else _CL.aim(normal)
    base = Matrix.Translation(Vector(center)) @ m
    half = math.radians(spread_deg) / 2.0
    for i in range(ribs):
        a = -half + 2 * half * i / float(max(1, ribs - 1))
        tipr = radius * (0.82 + 0.18 * math.cos(a * 1.2))
        p0 = Vector((0, 0, 0))
        p1 = Vector((math.sin(a) * tipr, math.cos(a) * tipr, rise * math.cos(a)))
        pts = [tuple(base @ p0.lerp(p1, t)) for t in (0.0, 0.5, 1.0)]
        out += _CL.tube(bm, pts, [thick * 0.35, thick * 0.55, thick * 0.32], segs=5)
    return out


# ================================================================ the render look
# The concept sheets are flat, evenly lit and sit on a light grey card.  defenselib's
# preview rig is a moody 3/4 key on a dark blue floor, which reads a warm brick red as
# muddy purple and made the first Strawman review chase colour bugs that were not there.
# These two overrides put the render in the same light as the art it is checked against.
# Sum these with the world ambient and keep the total near 1.0: a flat Roblox colour has
# to come back off the render as ITSELF or a colour review is worthless.  Key 1.55 +
# fill 0.7 + rim 0.25 + 0.22 ambient reads a 140,60,50 shirt as brick, not pink or plum.
LIGHT_KEY, LIGHT_FILL, LIGHT_RIM, WORLD_BG = 1.55, 0.70, 0.25, 0.22


def _guardian_lights():
    key = bpy.data.objects.get("PreviewSun")
    if key is None:
        key = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", 'SUN'))
        bpy.context.scene.collection.objects.link(key)
    key.data.energy = LIGHT_KEY
    key.data.angle = math.radians(18)
    key.rotation_euler = (math.radians(56), math.radians(6), math.radians(-30))
    fill = bpy.data.objects.get("PreviewFill")
    if fill is None:
        fill = bpy.data.objects.new("PreviewFill", bpy.data.lights.new("PreviewFill", 'SUN'))
        bpy.context.scene.collection.objects.link(fill)
    fill.data.energy = LIGHT_FILL               # down the camera axis: no dead front
    fill.data.angle = math.radians(40)
    fill.rotation_euler = (math.radians(76), math.radians(0), math.radians(170))
    rim = bpy.data.objects.get("PreviewRim")
    if rim is None:
        rim = bpy.data.objects.new("PreviewRim", bpy.data.lights.new("PreviewRim", 'SUN'))
        bpy.context.scene.collection.objects.link(rim)
    rim.data.energy = LIGHT_RIM
    rim.rotation_euler = (math.radians(44), math.radians(0), math.radians(56))


_CL._lights = _guardian_lights
try:
    import defenselib as _DL
    _DL._lights = _guardian_lights
except Exception:
    _DL = None
for _m in (_CL, sys.modules.get("proplib"), sys.modules.get("defenselib")):
    if _m is None:
        continue
    if hasattr(_m, "_lights"):
        _m._lights = _guardian_lights
    if hasattr(_m, "_setup_world") and not getattr(_m, "_guardian_world_patched", False):
        _m._setup_world = (lambda scene, bg=None, _b=_m._setup_world:
                           _b(scene, bg=(WORLD_BG, WORLD_BG * 1.02, WORLD_BG * 1.06)))
        _m._guardian_world_patched = True


# ================================================================ reporting
def report(cname):
    return _CL.report(cname)


def build_stage(size=26.0, ref_at=(-6.5, 5.0, 0.0)):
    """A light card floor and a 5-stud avatar, to match the concept sheets."""
    sx, sy = size if isinstance(size, (tuple, list)) else (size, size)
    c = _CL.coll("_Stage")
    _CL.clear_collection("_Stage")
    bm = bmesh.new()
    _CL.box(bm, (-sx / 2, -sy / 2, -0.25), (sx / 2, sy / 2, 0.0))
    _cl_new_obj("Floor", bm, c, "b3b0aa", roughness=0.96)
    bm = bmesh.new()                       # R15 blockout: 5 studs tall, 2 wide, 1 deep
    _CL.box(bm, (-1.0, -0.5, 0.0), (1.0, 0.5, 3.5))
    _CL.box(bm, (-0.6, -0.4, 3.5), (0.6, 0.4, 5.0))
    _CL.box(bm, (-1.5, -0.35, 1.9), (-1.0, 0.35, 3.5))
    _CL.box(bm, (1.0, -0.35, 1.9), (1.5, 0.35, 3.5))
    o = _cl_new_obj("ScaleRef", bm, c, "c85a5a", roughness=0.85)
    o.location = tuple(ref_at)
    return c


def summary(cname):
    r = _CL.report(cname)
    r["rig"] = check_rig(cname)
    return r
