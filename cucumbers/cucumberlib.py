"""Blender helpers for the 57-model cucumber set (8 biomes).

`proplib.py` (itself `defenselib.py` + the decorative primitives) re-exported, plus
`cukemath.py` (the palette and every numbers-only helper), plus the shapes that make
this set read as one family:

  * the signature cucumber body - an 8-sided tapered pillar with a stem nub
  * the raised square "studs" that speckle every surface in the set
  * the sliced-cucumber disc: dark rim, pale cut face, square pips
  * blocky stepped trunks, square branches and cube crowns
  * wrap ribbons (vine / bandage / flame), surface cracks, snow drifts, icicles,
    palm fronds, ice spires, coral arms, saucer canopies, basket weave, kanji

Conventions (identical to props/ and defenses/):
  * 1 Blender unit = 1 Roblox stud.  Z up, ground at z = 0.
  * Every model FACES +Y.  With the default phase, body facet 1 faces +Y.
  * Roblox export is a pure rotation: (x, y, z)_rbx = (x, z, -y)_blender.
  * Chunky low-poly, FLAT shaded, colour carried per object as custom props
    ("rbx_hex" / "rbx_material" / "rbx_transparency").
  * An R15 avatar is ~5 studs tall.
"""
import bpy, bmesh, math, random, sys, os, importlib.util
from mathutils import Vector, Matrix, Euler

ROOT = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\cucumbers"
_PROPLIB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\props\proplib.py"
_CUKEMATH = os.path.join(ROOT, "cukemath.py")


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    sys.modules[name] = m
    return m


_P = _load(_PROPLIB, "proplib")
_M = _load(_CUKEMATH, "cukemath")

# re-export every public proplib name (box, cyl, prism, lathe, foliage, report, render...)
for _k in dir(_P):
    if not _k.startswith("_"):
        globals()[_k] = getattr(_P, _k)

# ... then every public cukemath name (CUKE_PROFILE, cuke_point, cuke_stud_slots, ...)
for _k in dir(_M):
    if not _k.startswith("_"):
        globals()[_k] = getattr(_M, _k)

_base_new_obj = _P.new_obj
_base_report = _P.report

# proplib's 79 palette keys plus this set's ~130.
PALETTE = dict(_P.PALETTE)
PALETTE.update(_M.CUKE_PALETTE)


def C(key):
    """PALETTE lookup that fails loudly on a typo (returns a hex string)."""
    if key in PALETTE:
        return PALETTE[key]
    raise KeyError("no palette colour %r - keys: %s" % (key, ", ".join(sorted(PALETTE))))


def new_obj(name, bm, c, hexcol, rbx_material="SmoothPlastic", transparency=0.0,
            metallic=0.0, roughness=0.55, smooth=False, emit=None):
    return _base_new_obj(name, bm, c, hexcol, rbx_material=rbx_material,
                         transparency=transparency, metallic=metallic,
                         roughness=roughness, smooth=smooth, emit=emit)


def _bevel_verts(bm, vs, pre, offset, segments=1):
    """Bevel just the geometry in `vs` and return the live vert list afterwards.
    `pre` is the set of verts that existed BEFORE the primitive was built."""
    vset = set(vs)
    edges = [e for e in bm.edges if e.verts[0] in vset and e.verts[1] in vset]
    faces = [f for f in bm.faces if all(v in vset for v in f.verts)]
    bmesh.ops.bevel(bm, geom=vs + edges + faces, offset=offset, segments=segments,
                    profile=0.5, affect='EDGES', clamp_overlap=True)
    bm.verts.ensure_lookup_table()
    return [v for v in bm.verts if v not in pre]


# ================================================================= the body
def cuke_body(bm, h=None, r=None, profile=None, segs=None, phase=None, matrix=None,
              nub=None, nub_bevel=0.045, cap=True):
    """The signature cucumber: an 8-sided pillar, chamfered top and bottom, optionally
    with the little stem nub on top.

    `nub` = (width, height) of the stem cube, or True for the default, or None for none.
    Returns every vert it made."""
    h = _M.CUKE_H if h is None else h
    r = _M.CUKE_R if r is None else r
    segs = _M.CUKE_SEGS if segs is None else segs
    ph = _M.cuke_phase(segs) if phase is None else phase
    prof = profile or _M.CUKE_PROFILE
    vs = _P.lathe(bm, [(rr * r, zz * h) for rr, zz in prof], segs=segs, phase=ph, cap=cap)
    if nub:
        nw, nh = (0.44 * r, 0.42 * r) if nub is True else (float(nub[0]), float(nub[1]))
        top = h * prof[-1][1]
        vs += _P.beveled_box(bm, (-nw / 2, -nw / 2, top - 0.03), (nw / 2, nw / 2, top + nh),
                             bevel=nub_bevel)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


# ================================================================= studs
def surface_frame(normal, up=(0.0, 0.0, 1.0)):
    """A 4x4 taking local +Z onto `normal` and local +Y onto `up` projected into the
    surface plane - so a square built in local XY stays UPRIGHT on the surface.

    `proplib.aim()` picks an arbitrary roll, which leaves square speckles landing as
    random diamonds; this is what every stud, pip and patch in the set uses instead."""
    n = Vector(normal)
    if n.length < 1e-9:
        n = Vector((0.0, 0.0, 1.0))
    n = n.normalized()
    u = Vector(up)
    if abs(u.normalized().dot(n)) > 0.985:          # normal is parallel to `up`
        u = Vector((0.0, 1.0, 0.0)) if abs(n.z) > 0.5 else Vector((0.0, 0.0, 1.0))
    t = u.cross(n)
    if t.length < 1e-9:
        t = Vector((1.0, 0.0, 0.0))
    t = t.normalized()
    b = n.cross(t).normalized()
    return Matrix(((t.x, b.x, n.x, 0.0), (t.y, b.y, n.y, 0.0),
                   (t.z, b.z, n.z, 0.0), (0.0, 0.0, 0.0, 1.0)))


def stud_patch(bm, point, normal, size=0.26, rise=0.055, sink=0.07, bevel=0.03,
               aspect=1.0, spin=0.0, up=(0.0, 0.0, 1.0)):
    """ONE raised square speckle sitting flat and UPRIGHT on a surface.

    `point` is on the surface, `normal` points out of it.  `aspect` stretches the stud
    along its local Y (the `up` direction), `spin` (degrees) turns it in the surface
    plane."""
    n = Vector(normal)
    if n.length < 1e-9:
        n = Vector((0.0, 0.0, 1.0))
    n = n.normalized()
    d = float(rise) + float(sink)
    vs = _P.beveled_box(bm, (-size / 2.0, -size * aspect / 2.0, -d / 2.0),
                        (size / 2.0, size * aspect / 2.0, d / 2.0), bevel=bevel)
    m = (Matrix.Translation(Vector(point) + n * (float(rise) - d / 2.0))
         @ surface_frame(n, up) @ Matrix.Rotation(math.radians(float(spin)), 4, 'Z'))
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def cuke_studs(bm, h=None, r=None, size=0.26, rise=0.055, rows=6, per_row=3,
               z0=0.14, z1=0.88, segs=None, phase=None, profile=None, seed=1,
               stagger=True, jitter=0.018, skip=0.0, bevel=0.03, matrix=None, slots=None):
    """Scatter the speckles over a cucumber body.

    Pass `slots` = [(height_fraction, facet_index), ...] to place them by hand instead."""
    h = _M.CUKE_H if h is None else h
    r = _M.CUKE_R if r is None else r
    segs = _M.CUKE_SEGS if segs is None else segs
    use = slots if slots is not None else _M.cuke_stud_slots(rows, per_row, z0, z1, segs,
                                                             stagger, seed, jitter, skip)
    vs = []
    for zf, facet in use:
        p, n = _M.cuke_facet_point(h, r, zf, facet, profile, 0.0, segs, phase)
        vs += stud_patch(bm, p, n, size=size, rise=rise, bevel=bevel)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


_FACE_AXES = {
    "+x": ((1, 0, 0), (0, 1, 0), (0, 0, 1)), "-x": ((-1, 0, 0), (0, 1, 0), (0, 0, 1)),
    "+y": ((0, 1, 0), (1, 0, 0), (0, 0, 1)), "-y": ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
    "+z": ((0, 0, 1), (1, 0, 0), (0, 1, 0)), "-z": ((0, 0, -1), (1, 0, 0), (0, 1, 0)),
}


def box_studs(bm, lo, hi, faces=("+x", "-x", "+y", "-y", "+z"), per_face=3, size=0.3,
              rise=0.05, seed=1, margin=0.26, bevel=0.035, matrix=None, grid=None):
    """Scatter speckles over the faces of a box - crown cubes, hay bales, ice blocks.

    `margin` is the fraction of each half-extent kept clear at the rim.  `grid` = (nx, ny)
    lays them on a lightly jittered lattice instead of at random."""
    lo, hi = Vector(lo), Vector(hi)
    ctr, ext = (lo + hi) / 2.0, (hi - lo) / 2.0
    rng = random.Random(seed)
    vs = []
    for f in faces:
        n, ua, va = (Vector(v) for v in _FACE_AXES[f])
        hu = abs(ua.dot(ext)) * (1.0 - margin)
        hv = abs(va.dot(ext)) * (1.0 - margin)
        base = Vector((ctr.x + n.x * ext.x, ctr.y + n.y * ext.y, ctr.z + n.z * ext.z))
        if grid:
            nx, ny = grid
            spots = []
            for j in range(ny):
                for i in range(nx):
                    u = ((i - (nx - 1) / 2.0) / ((nx - 1) / 2.0)) if nx > 1 else 0.0
                    v = ((j - (ny - 1) / 2.0) / ((ny - 1) / 2.0)) if ny > 1 else 0.0
                    spots.append((u * hu + rng.uniform(-0.12, 0.12) * hu,
                                  v * hv + rng.uniform(-0.12, 0.12) * hv))
        else:
            spots = [(rng.uniform(-hu, hu), rng.uniform(-hv, hv)) for _ in range(per_face)]
        for u, v in spots:
            vs += stud_patch(bm, base + ua * u + va * v, n, size=size, rise=rise,
                             bevel=bevel)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


# ================================================================= the slice
def slice_disc(bm, center=(0, 0, 0), radius=None, thick=None, segs=None, matrix=None,
               bevel=0.05, phase=None):
    """The dark rim of a cut slice: a short n-sided drum whose axis is LOCAL Z, so by
    default it lies flat like a coin.  Stand it up with `matrix=D.slice_stand(loc)`."""
    radius = _M.SLICE_R if radius is None else radius
    thick = _M.SLICE_T if thick is None else thick
    segs = _M.SLICE_SEGS if segs is None else segs
    ph = math.pi / float(segs) if phase is None else phase
    pre = set(bm.verts)
    vs = _P.prism(bm, _P.ngon_pts(segs, radius, phase=ph), -thick / 2.0, thick / 2.0)
    if bevel > 1e-5:
        vs = _bevel_verts(bm, vs, pre, min(bevel, thick * 0.34))
    m = Matrix.Translation(Vector(center))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def slice_face(bm, center=(0, 0, 0), radius=None, thick=None, segs=None, inset=0.12,
               proud=0.02, matrix=None, both=True, phase=None):
    """The pale cut face(s): a slightly smaller disc standing proud of each flat end."""
    radius = _M.SLICE_R if radius is None else radius
    thick = _M.SLICE_T if thick is None else thick
    segs = _M.SLICE_SEGS if segs is None else segs
    ph = math.pi / float(segs) if phase is None else phase
    pts = _P.ngon_pts(segs, radius * (1.0 - inset), phase=ph)
    vs = []
    for s in ((1.0, -1.0) if both else (1.0,)):
        z = s * thick / 2.0
        lo, hi = sorted((z - 0.03 * s, z + proud * s))
        vs += _P.prism(bm, pts, lo, hi)
    m = Matrix.Translation(Vector(center))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def slice_seeds(bm, center=(0, 0, 0), radius=None, thick=None, n=5, size=0.135,
                ring=0.40, rise=0.024, matrix=None, both=True, centre_seed=True,
                phase_deg=18.0, proud=0.02, bevel=0.02):
    """The little square pips on a cut face: `n` in a ring plus one in the middle."""
    radius = _M.SLICE_R if radius is None else radius
    thick = _M.SLICE_T if thick is None else thick
    vs = []
    for s in ((1.0, -1.0) if both else (1.0,)):
        z = s * (thick / 2.0 + proud)
        spots = [(0.0, 0.0)] if centre_seed else []
        for i in range(n):
            a = math.radians(phase_deg) + 2 * math.pi * i / float(n)
            spots.append((math.cos(a) * radius * ring, math.sin(a) * radius * ring))
        for x, y in spots:
            vs += stud_patch(bm, (x, y, z), (0, 0, s), size=size, rise=rise, sink=0.05,
                             bevel=bevel)
    m = Matrix.Translation(Vector(center))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def slice_studs(bm, center=(0, 0, 0), radius=None, thick=None, n=6, size=0.18,
                rise=0.045, segs=None, matrix=None, seed=1, phase=None, bevel=0.025):
    """The speckles on a slice's RIM (its skin), snapped to rim facets."""
    radius = _M.SLICE_R if radius is None else radius
    thick = _M.SLICE_T if thick is None else thick
    segs = _M.SLICE_SEGS if segs is None else segs
    ph = math.pi / float(segs) if phase is None else phase
    rng = random.Random(seed)
    step = max(1, int(round(segs / float(max(1, n)))))
    start = rng.randint(0, segs - 1)
    rr = radius * math.cos(math.pi / float(segs))
    vs = []
    for i in range(n):
        k = (start + i * step) % segs
        a = ph + (2.0 * k + 1.0) * math.pi / float(segs)
        p = (math.cos(a) * rr, math.sin(a) * rr, rng.uniform(-0.22, 0.22) * thick)
        vs += stud_patch(bm, p, (math.cos(a), math.sin(a), 0.0), size=size, rise=rise,
                         sink=0.05, bevel=bevel)
    m = Matrix.Translation(Vector(center))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def slice_lay(loc, tilt_deg=0.0, spin_deg=0.0):
    """Matrix for a slice LYING FLAT (a coin on the ground) at `loc`, optionally tipped."""
    return _P.place(loc, _P.rot_euler(tilt_deg, 0.0, spin_deg))


def slice_stand(loc, lean_deg=0.0, turn_deg=0.0):
    """Matrix for a slice STANDING UP with its cut face toward +Y (the camera).

    Positive `lean_deg` tips the top of the disc AWAY from the viewer; `turn_deg`
    swings it round the vertical."""
    return _P.place(loc, _P.rot_euler(-90.0 + lean_deg, 0.0, turn_deg))


# ================================================================= trees
def stepped_base(bm, top_w, h, steps=3, grow=1.32, bevel=0.06, z0=0.0, center=(0, 0),
                 depth_ratio=1.0):
    """The stacked plinth every tree in this set stands on: `steps` boxes, each `grow`
    times wider than the one above it, `top_w` across at the top, `h` tall in total."""
    cx, cy = center
    vs = []
    sh = h / float(steps)
    for i in range(steps):
        k = steps - 1 - i                       # 0 = top step
        w = top_w * (grow ** k)
        d = w * depth_ratio
        z = z0 + i * sh
        vs += _P.beveled_box(bm, (cx - w / 2, cy - d / 2, z),
                             (cx + w / 2, cy + d / 2, z + sh + 0.012), bevel=bevel)
    return vs


def blocky_trunk(bm, z0, z1, w0, w1=None, blocks=3, bevel=0.06, center=(0, 0), seed=0,
                 jitter=0.0, twist=0.0, depth_ratio=1.0):
    """A trunk of stacked boxes tapering from `w0` at the bottom to `w1` at the top."""
    cx, cy = center
    w1 = w0 if w1 is None else w1
    rng = random.Random(seed)
    vs = []
    sh = (z1 - z0) / float(blocks)
    for i in range(blocks):
        t = (i + 0.5) / float(blocks)
        w = w0 + (w1 - w0) * t
        d = w * depth_ratio
        dx, dy = rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter)
        rot = (_P.rot_euler(0, 0, twist * (i - (blocks - 1) / 2.0))
               if abs(twist) > 1e-6 else None)
        vs += _P.beveled_box(bm, (cx + dx - w / 2, cy + dy - d / 2, z0 + i * sh),
                             (cx + dx + w / 2, cy + dy + d / 2, z0 + (i + 1) * sh + 0.014),
                             bevel=bevel, rot=rot)
    return vs


def branch_box(bm, a, b, w0, w1=None, bevel=0.0, spin=0.0):
    """A tapered SQUARE-section beam from a to b - branches, arms, struts, ladder rails."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    if L < 1e-6:
        return []
    w1 = w0 if w1 is None else w1
    h0, h1 = w0 / 2.0, w1 / 2.0
    pre = set(bm.verts)
    vb = [bm.verts.new(p) for p in ((-h0, -h0, 0.0), (h0, -h0, 0.0), (h0, h0, 0.0),
                                    (-h0, h0, 0.0))]
    vt = [bm.verts.new(p) for p in ((-h1, -h1, L), (h1, -h1, L), (h1, h1, L),
                                    (-h1, h1, L))]
    bm.faces.new(tuple(reversed(vb)))
    bm.faces.new(tuple(vt))
    for i in range(4):
        bm.faces.new((vb[i], vb[(i + 1) % 4], vt[(i + 1) % 4], vt[i]))
    vs = vb + vt
    if bevel > 1e-5:
        vs = _bevel_verts(bm, vs, pre, min(bevel, min(w0, w1) * 0.35))
    m = Matrix.Translation(a) @ _P.aim(d) @ Matrix.Rotation(math.radians(spin), 4, 'Z')
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def crown_cube(bm, center, size, bevel=0.11, rot=None, squash=1.0):
    """One chunky foliage cube.  `size` is a scalar or (sx, sy, sz)."""
    s = size if isinstance(size, (tuple, list)) else (size, size, size * squash)
    cx, cy, cz = center
    return _P.beveled_box(bm, (cx - s[0] / 2, cy - s[1] / 2, cz - s[2] / 2),
                          (cx + s[0] / 2, cy + s[1] / 2, cz + s[2] / 2), bevel=bevel,
                          rot=rot)


def crown_cluster(bm, center, size, spots, bevel=0.11, seed=1, jitter=0.0):
    """Several crown cubes at `spots` offsets from `center`.

    `spots` = [(dx, dy, dz)] or [(dx, dy, dz, size_multiplier)]."""
    rng = random.Random(seed)
    cx, cy, cz = center
    vs = []
    for s in spots:
        k = s[3] if len(s) > 3 else 1.0
        j = (rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter),
             rng.uniform(-jitter, jitter))
        vs += crown_cube(bm, (cx + s[0] + j[0], cy + s[1] + j[1], cz + s[2] + j[2]),
                         size * k, bevel=bevel)
    return vs


# ================================================================= ribbons & vines
def ribbon(bm, frames, width, thick, cap=True, taper=None):
    """Loft a rectangular strip along `frames` = [(point, out_normal), ...].

    The strip's flat face points along each frame's normal; its width runs perpendicular
    to both the path tangent and that normal.  `taper` = (start_mult, end_mult)."""
    pts = [Vector(p) for p, _ in frames]
    nms = [Vector(n).normalized() for _, n in frames]
    n = len(pts)
    if n < 2:
        return []
    rings = []
    for i in range(n):
        t = (pts[1] - pts[0]) if i == 0 else \
            (pts[-1] - pts[-2]) if i == n - 1 else (pts[i + 1] - pts[i - 1])
        if t.length < 1e-9:
            t = Vector((0, 0, 1))
        t = t.normalized()
        u = t.cross(nms[i])
        if u.length < 1e-9:
            u = Vector((0, 0, 1)).cross(nms[i])
        u = u.normalized()
        w = width
        if taper:
            f = i / float(n - 1)
            w = width * (taper[0] + (taper[1] - taper[0]) * f)
        a, b = u * (w / 2.0), nms[i] * (thick / 2.0)
        rings.append([bm.verts.new(pts[i] - a - b), bm.verts.new(pts[i] + a - b),
                      bm.verts.new(pts[i] + a + b), bm.verts.new(pts[i] - a + b)])
    for i in range(n - 1):
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
    if cap:
        bm.faces.new(tuple(reversed(rings[0])))
        bm.faces.new(tuple(rings[-1]))
    return [v for ring in rings for v in ring]


def wrap_ribbon(bm, h=None, r=None, z0=0.10, z1=0.92, turns=1.6, width=0.42,
                thick=0.13, n=34, phase_deg=-40.0, profile=None, offset=0.06,
                segs=None, taper=None, cap=True):
    """A flat band spiralling up a cucumber: the vine, the bandage, the flame ribbon."""
    h = _M.CUKE_H if h is None else h
    r = _M.CUKE_R if r is None else r
    segs = _M.CUKE_SEGS if segs is None else segs
    return ribbon(bm, _M.wrap_frames(h, r, z0, z1, turns, n, phase_deg, profile, offset,
                                     segs), width, thick, cap=cap, taper=taper)


def leaf_blade(bm, length=0.9, width=0.55, thick=0.09, matrix=None, ridge=0.06,
               notch=0.30, tip=0.18):
    """A faceted low-poly leaf pointing along +Y, lying in the XY plane, with a raised
    centre ridge.  Place it with `matrix=D.place(loc, D.rot_euler(...))`."""
    w, L = width / 2.0, length
    vs = _P.prism(bm, [(0.0, 0.0), (w * 0.62, L * notch), (w, L * 0.55), (tip * w, L * 0.90),
                       (0.0, L), (-tip * w, L * 0.90), (-w, L * 0.55), (-w * 0.62, L * notch)],
                  -thick / 2.0, thick / 2.0)
    if ridge > 1e-5:
        vs += _P.prism(bm, [(0.0, 0.0), (w * 0.22, L * 0.5), (0.0, L * 0.95),
                            (-w * 0.22, L * 0.5)], -thick / 2.0, thick / 2.0 + ridge)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=vs)
    return vs


# ================================================================= surface detail
def surface_line(bm, pts_surface, h=None, r=None, width=0.10, rise=0.02, profile=None,
                 segs=None, offset=0.0, thick=None, flat=True, taper=None):
    """Lay a strip along a cucumber's skin.  `pts_surface` = [(height_frac, angle_deg)].

    For lava cracks, glowing veins, mud runs, lightning bolts - anything DRAWN on the
    body rather than stuck to it."""
    h = _M.CUKE_H if h is None else h
    r = _M.CUKE_R if r is None else r
    segs = _M.CUKE_SEGS if segs is None else segs
    frames = [(_M.cuke_point(h, r, zf, ang, profile, offset, segs, flat),
               _M.cuke_normal(ang)) for zf, ang in pts_surface]
    return ribbon(bm, frames, width, (rise * 2.0 if thick is None else thick), cap=True,
                  taper=taper)


def crack_lines(bm, lines, h=None, r=None, width=0.10, rise=0.02, profile=None,
                segs=None, offset=0.0, taper=None):
    """Several `surface_line`s in one call: `lines` = [[(height_frac, angle_deg), ...]]."""
    vs = []
    for ln in lines:
        if len(ln) >= 2:
            vs += surface_line(bm, ln, h, r, width, rise, profile, segs, offset,
                               taper=taper)
    return vs


def spike_ring(bm, h=None, r=None, rows=4, per_row=3, z0=0.16, z1=0.86, length=0.30,
               base_r=0.13, segs_spike=4, segs=None, phase=None, profile=None, seed=1,
               stagger=True, droop=0.0, sink=0.04):
    """Cactus / charred / ice spikes standing out of a body, snapped to facet centres."""
    h = _M.CUKE_H if h is None else h
    r = _M.CUKE_R if r is None else r
    segs = _M.CUKE_SEGS if segs is None else segs
    vs = []
    for zf, facet in _M.cuke_stud_slots(rows, per_row, z0, z1, segs, stagger, seed, 0.012):
        p, n = _M.cuke_facet_point(h, r, zf, facet, profile, -sink, segs, phase)
        d = (Vector(n) + Vector((0, 0, -droop))).normalized()
        vs += _P.spike(bm, p, tuple(Vector(p) + d * length), base_r, segs=segs_spike)
    return vs


def snow_slab(bm, lo, hi, thick=0.26, overhang=0.06, drips=3, drip_len=0.34, seed=1,
              bevel=0.06, sides=("-y",)):
    """A drift of snow sitting on a box, spilling over the edges with a few drips."""
    lo, hi = Vector(lo), Vector(hi)
    o = overhang
    vs = _P.beveled_box(bm, (lo.x - o, lo.y - o, hi.z - 0.03),
                        (hi.x + o, hi.y + o, hi.z + thick), bevel=bevel)
    rng = random.Random(seed)
    for s in sides:
        horiz = s in ("-y", "+y")
        span = (hi.x - lo.x) if horiz else (hi.y - lo.y)
        start = lo.x if horiz else lo.y
        for i in range(drips):
            u = start + span * (i + 0.5 + rng.uniform(-0.16, 0.16)) / float(drips)
            w = span * rng.uniform(0.16, 0.26)
            L = drip_len * rng.uniform(0.6, 1.15)
            if horiz:
                y = (lo.y - o) if s == "-y" else (hi.y + o)
                vs += _P.beveled_box(bm, (u - w / 2, y - 0.11, hi.z - L),
                                     (u + w / 2, y + 0.11, hi.z + thick * 0.7), bevel=0.05)
            else:
                x = (lo.x - o) if s == "-x" else (hi.x + o)
                vs += _P.beveled_box(bm, (x - 0.11, u - w / 2, hi.z - L),
                                     (x + 0.11, u + w / 2, hi.z + thick * 0.7), bevel=0.05)
    return vs


def cuke_snow_cap(bm, h=None, r=None, thick=0.34, drips=4, drip_len=0.55, seed=1,
                  segs=None, phase=None, profile=None, top_zf=0.86, spread=1.14):
    """A cap of snow over a cucumber's head, with tongues running down its sides."""
    h = _M.CUKE_H if h is None else h
    r = _M.CUKE_R if r is None else r
    segs = _M.CUKE_SEGS if segs is None else segs
    ph = _M.cuke_phase(segs) if phase is None else phase
    prof = profile or _M.CUKE_PROFILE
    top = h * prof[-1][1]
    base_r = _M.cuke_radius(top_zf, prof) * r * spread
    z = top_zf * h
    vs = _P.lathe(bm, [(0.0, z), (base_r, z + 0.05), (base_r, z + thick * 0.55),
                       (base_r * 0.84, top + thick * 0.75), (base_r * 0.5, top + thick),
                       (0.0, top + thick)], segs=segs, phase=ph)
    rng = random.Random(seed)
    step = max(1, segs // max(1, drips))
    for i in range(drips):
        facet = (i * step + rng.randint(0, 1)) % segs
        a = math.degrees(_M.cuke_facet_angle(facet, segs, ph))
        zf = top_zf - rng.uniform(0.10, 0.26)
        p = _M.cuke_point(h, r, zf, a, prof, 0.03, segs, True)
        w = rng.uniform(0.20, 0.32)
        vs += _P.tube(bm, [(p[0], p[1], z + 0.06), (p[0], p[1], p[2] + 0.14),
                           (p[0], p[1], p[2])], [w * 1.3, w, w * 0.4], segs=5)
    return vs


def icicle(bm, top, length, radius=0.10, segs=5, tilt=(0.0, 0.0)):
    """One hanging icicle: a spike pointing down, with an optional lean."""
    t = Vector(top)
    return _P.spike(bm, tuple(t), tuple(t + Vector((tilt[0], tilt[1], -length))), radius,
                    segs=segs)


def icicle_row(bm, a, b, count=4, length=0.55, radius=0.11, seed=1, vary=0.42, segs=5):
    """A row of icicles hanging along the segment a -> b."""
    a, b = Vector(a), Vector(b)
    rng = random.Random(seed)
    vs = []
    for i in range(count):
        p = a.lerp(b, (i + 0.5) / float(count))
        vs += icicle(bm, tuple(p), length * (1.0 + rng.uniform(-vary, vary)),
                     radius * (1.0 + rng.uniform(-0.2, 0.2)), segs=segs)
    return vs


def crystal_spire(bm, base=(0, 0, 0), height=1.6, radius=0.30, segs=6, taper=0.58,
                  tip=0.34, rot=None, matrix=None):
    """A pointed ice / gem crystal: an n-gon shaft that narrows into a facetted point.

    Built standing on `base`; `rot` leans it about that base, `matrix` applies last."""
    shaft = height * (1.0 - tip)
    vs = _P.lathe(bm, [(0.0, 0.0), (radius * 0.92, 0.0), (radius, shaft * 0.22),
                       (radius * taper, shaft),
                       (radius * taper * 0.62, shaft + tip * height * 0.45),
                       (0.0, height)], segs=segs, phase=math.pi / segs)
    m = Matrix.Translation(Vector(base)) @ (rot if rot is not None else Matrix.Identity(4))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def gem(bm, center, radius=0.22, segs=6, squash=1.25, rot=None):
    """A faceted crystal lump - the alien gems, the meteor shards, a cut jewel."""
    m = Matrix.Translation(Vector(center)) @ (rot if rot is not None else Matrix.Identity(4))
    return _P.lathe(bm, [(0.0, -radius * squash * 0.55), (radius * 0.7, -radius * 0.3),
                         (radius, 0.0), (radius * 0.62, radius * 0.5),
                         (0.0, radius * squash)],
                    segs=segs, phase=math.pi / segs, matrix=m)


def palm_frond(bm, base=(0, 0, 0), yaw_deg=0.0, pitch_deg=18.0, length=2.6, width=0.62,
               thick=0.10, droop=0.9, n=6, teeth=0.26):
    """A drooping palm / kelp frond: a tapering strip that bends down, with a serrated
    outline.  `yaw_deg` swings it round Z, `pitch_deg` lifts its root off horizontal."""
    frames, zs = [], []
    for i in range(n):
        t = i / float(n - 1)
        x = length * t
        z = math.sin(math.radians(pitch_deg)) * length * t - droop * (t ** 2)
        frames.append(((x, 0.0, z), (0.0, 0.0, 1.0)))
        zs.append(z)
    vs = ribbon(bm, frames, width, thick, taper=(1.0, 0.22))
    if teeth > 1e-4:
        for i in range(1, n):
            t = (i - 0.3) / float(n - 1)
            x = length * t
            z = math.sin(math.radians(pitch_deg)) * length * t - droop * (t ** 2)
            w = width * (1.0 - 0.78 * t) / 2.0
            for s in (1, -1):
                vs += _P.prism(bm, [(x - teeth * 0.5, s * w), (x + teeth * 0.5, s * w),
                                    (x, s * (w + teeth))], z - thick / 2.0, z + thick / 2.0)
    bmesh.ops.transform(bm, matrix=_P.place(base, _P.rot_euler(0, 0, yaw_deg)), verts=vs)
    return vs


def coral_arm(bm, base=(0, 0, 0), direction=(0, 0, 1), length=1.1, radius=0.17, depth=2,
              branches=2, spread=42.0, shrink=0.62, seed=1, segs=5, curl=0.18):
    """A branching staghorn-coral arm: `depth` levels of `branches` each."""
    rng = random.Random(seed)
    vs = []

    def grow(p, d, L, rr, lvl):
        d = Vector(d).normalized()
        mid = Vector(p) + d * (L * 0.55)
        end = Vector(p) + d * L + Vector((0, 0, curl * L))
        vs.extend(_P.tube(bm, [tuple(p), tuple(mid), tuple(end)],
                          [rr, rr * 0.82, rr * 0.55], segs=segs))
        if lvl <= 0:
            return
        for i in range(branches):
            a = math.radians(spread * (1.0 + rng.uniform(-0.35, 0.35)))
            yaw = (2 * math.pi * i / branches + rng.uniform(-0.4, 0.4))
            axis = Vector((math.cos(yaw), math.sin(yaw), 0.0))
            grow(tuple(end), tuple((d * math.cos(a) + axis * math.sin(a)).normalized()),
                 L * shrink, rr * 0.66, lvl - 1)

    grow(base, direction, length, radius, depth)
    return vs


def disc_canopy(bm, center=(0, 0, 0), radius=1.5, thick=0.34, rim=0.20, segs=12,
                dome=0.0, matrix=None):
    """The saucer / galaxy-disc canopy: a flat n-gon plate with a thicker rim band."""
    prof = [(0.0, -thick * 0.34), (radius * 0.72, -thick * 0.5), (radius, -rim * 0.5),
            (radius, rim * 0.5), (radius * 0.72, thick * 0.5)]
    prof += ([(radius * 0.40, thick * 0.5 + dome * 0.7), (0.0, thick * 0.5 + dome)]
             if dome > 1e-5 else [(0.0, thick * 0.5)])
    vs = _P.lathe(bm, prof, segs=segs, phase=math.pi / segs)
    m = Matrix.Translation(Vector(center))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


def weave_panel(bm, lo, hi, rows=4, cols=5, depth=0.10, gap=0.035, axis="y", bevel=0.03):
    """Basket weave: a checkerboard of strips, alternate cells standing proud."""
    lo, hi = Vector(lo), Vector(hi)
    vs = []
    if axis == "y":
        W, H = (hi.x - lo.x) / float(cols), (hi.z - lo.z) / float(rows)
        for j in range(rows):
            for i in range(cols):
                out = depth if (i + j) % 2 == 0 else 0.0
                vs += _P.beveled_box(bm, (lo.x + i * W + gap, lo.y - out,
                                          lo.z + j * H + gap),
                                     (lo.x + (i + 1) * W - gap, hi.y + out,
                                      lo.z + (j + 1) * H - gap), bevel=bevel)
    else:
        W, H = (hi.y - lo.y) / float(cols), (hi.z - lo.z) / float(rows)
        for j in range(rows):
            for i in range(cols):
                out = depth if (i + j) % 2 == 0 else 0.0
                vs += _P.beveled_box(bm, (lo.x - out, lo.y + i * W + gap,
                                          lo.z + j * H + gap),
                                     (hi.x + out, lo.y + (i + 1) * W - gap,
                                      lo.z + (j + 1) * H - gap), bevel=bevel)
    return vs


# ================================================================= kanji
# 侍 ("samurai") as box strokes in a 0..1 x 0..1 glyph box: (x0, z0, x1, z1, weight).
# Drawn in the XZ plane so it reads from -Y; mirrored below so it reads from +Y, which
# is where this set's camera and every model's front are.
_KANJI_SHI = [
    (0.20, 0.88, 0.20, 0.26, 0.075),    # left radical: the long vertical
    (0.04, 0.62, 0.26, 0.80, 0.070),    # left radical: the top tick
    (0.44, 0.84, 0.96, 0.84, 0.072),    # top horizontal
    (0.44, 0.60, 0.96, 0.60, 0.072),    # second horizontal
    (0.38, 0.36, 1.00, 0.36, 0.072),    # third (longest) horizontal
    (0.70, 0.94, 0.70, 0.10, 0.078),    # the long vertical through them
    (0.48, 0.12, 0.94, 0.12, 0.070),    # bottom horizontal
]


def kanji_samurai(bm, origin=(0, 0, 0), size=1.0, thick=0.06, matrix=None, strokes=None,
                  face="+y"):
    """Draw 侍 as chunky box strokes standing in the XZ plane.

    `face='+y'` (the default) mirrors it so it reads correctly to a viewer at +Y."""
    s = -1.0 if face == "+y" else 1.0
    vs = []
    for (x0, z0, x1, z1, w) in (strokes or _KANJI_SHI):
        a = Vector((s * (x0 - 0.5) * size, 0.0, (z0 - 0.5) * size))
        b = Vector((s * (x1 - 0.5) * size, 0.0, (z1 - 0.5) * size))
        d = b - a
        L = max(d.length, 1e-4)
        t = w * size
        m = Matrix.Translation((a + b) / 2.0) @ Matrix.Rotation(-math.atan2(d.z, d.x), 4, 'Y')
        vv = _P.beveled_box(bm, (-L / 2 - t * 0.3, -thick / 2, -t / 2),
                            (L / 2 + t * 0.3, thick / 2, t / 2), bevel=t * 0.18)
        bmesh.ops.transform(bm, matrix=m, verts=vv)
        vs += vv
    m = Matrix.Translation(Vector(origin))
    if matrix is not None:
        m = matrix @ m
    bmesh.ops.transform(bm, matrix=m, verts=vs)
    return vs


# ================================================================= reporting
def report(coll_name):
    return _base_report(coll_name)


def build_stage(size=26.0, ref_at=(-6.5, 5.0, 0.0)):
    return _P.build_stage(size=size, ref_at=ref_at)
