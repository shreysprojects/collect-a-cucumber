"""Offline pre-flight for a GUARDIAN build script - runs it WITHOUT Blender.

    py dryrun.py build_strawman.py        # one script
    py dryrun.py                          # every build_*.py in this folder

It fakes `bpy` / `bmesh` / `mathutils`, hands `build()` a stand-in for `guardianlib`
that knows every real API name, and reports what the script would make.  It imports
`gmath` FOR REAL, so the role palette, SPEC and every numbers-only helper behave here
exactly as they will inside Blender.

It catches, cheaply and in parallel-safe isolation:

  * syntax errors, NameErrors, calls to a primitive that does not exist
  * a role that is not in ROLES[guardian], a bad material / transparency
  * a part with no pivot, a pivot nowhere near its own geometry
  * a rig that has no root, two roots, a missing parent or a parent cycle
  * duplicate part names, a name with a space, a role containing an underscore
  * a missing `G.begin()` (the idempotency guarantee), a missing Hitbox
  * POSES that name a part that does not exist, or that omit Sit / Awake
  * geometry below the ground plane and a height that misses SPEC by > 25 %

It does NOT run real geometry, so the bounding box is an APPROXIMATION taken from the
literal coordinates passed to primitives, before any rot=/matrix= transform.  Treat it
as a smell test; `buildall.build_all()` inside Blender is the source of truth.
"""
import sys, os, re, ast, math, types, importlib.util, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
_GAMES = os.path.dirname(HERE)
DEFENSELIB = os.path.join(_GAMES, "defenses", "defenselib.py")
PROPLIB = os.path.join(_GAMES, "props", "proplib.py")
CUCUMBERLIB = os.path.join(_GAMES, "cucumbers", "cucumberlib.py")
CUKEMATH = os.path.join(_GAMES, "cucumbers", "cukemath.py")
GUARDIANLIB = os.path.join(HERE, "guardianlib.py")
GMATH = os.path.join(HERE, "gmath.py")

MATERIALS = {"SmoothPlastic", "Plastic", "Metal", "DiamondPlate", "CorrodedMetal", "Wood",
             "WoodPlanks", "Slate", "Concrete", "Brick", "Cobblestone", "Grass", "Sand",
             "Fabric", "Foil", "Glass", "Ice", "Marble", "Neon", "Pebble", "Granite",
             "Rock", "Sandstone", "Basalt", "CrackedLava", "Glacier", "Ground", "LeafyGrass",
             "Limestone", "Mud", "Pavement", "Salt", "Snow", "Asphalt", "Cardboard",
             "Carpet", "Ceramic Tiles", "Clay Roof Tiles", "Leather", "Plaster", "Rubber"}

PIVOT_SLACK = 1.6        # studs a pivot may sit outside its own part's bbox
TRI_MIN, TRI_MAX = 1200, 4600


# ---------------------------------------------------------------- fake mathutils
class V:
    __slots__ = ("x", "y", "z")

    def __init__(self, a=(0, 0, 0), b=None, c=None):
        if b is not None:
            self.x, self.y, self.z = float(a), float(b), float(c or 0)
        elif isinstance(a, V):
            self.x, self.y, self.z = a.x, a.y, a.z
        else:
            t = list(a) + [0, 0, 0]
            self.x, self.y, self.z = float(t[0]), float(t[1]), float(t[2])

    def __iter__(self): return iter((self.x, self.y, self.z))
    def __len__(self): return 3
    def __getitem__(self, i): return (self.x, self.y, self.z)[i]

    def __setitem__(self, i, v):
        setattr(self, ("x", "y", "z")[i], float(v))

    def __add__(self, o): o = V(o); return V((self.x + o.x, self.y + o.y, self.z + o.z))
    def __sub__(self, o): o = V(o); return V((self.x - o.x, self.y - o.y, self.z - o.z))
    def __neg__(self): return V((-self.x, -self.y, -self.z))
    def __mul__(self, s): return V((self.x * s, self.y * s, self.z * s))
    __rmul__ = __mul__
    def __truediv__(self, s): return V((self.x / s, self.y / s, self.z / s))
    def __repr__(self): return "V(%.2f, %.2f, %.2f)" % (self.x, self.y, self.z)

    @property
    def length(self): return math.sqrt(self.x ** 2 + self.y ** 2 + self.z ** 2)

    def normalized(self):
        L = self.length
        return V((0, 0, 0)) if L < 1e-12 else self / L

    def dot(self, o): o = V(o); return self.x * o.x + self.y * o.y + self.z * o.z

    def cross(self, o):
        o = V(o)
        return V((self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z,
                  self.x * o.y - self.y * o.x))

    def lerp(self, o, t): o = V(o); return self + (o - self) * t
    def copy(self): return V(self)
    def to_tuple(self, n=6): return (self.x, self.y, self.z)
    def rotation_difference(self, o): return M()
    def to_track_quat(self, *a): return M()


class M:
    """Opaque 4x4 stand-in: composes with @ and swallows everything."""
    def __init__(self, *a, **k): pass
    def __matmul__(self, o): return o if isinstance(o, V) else M()
    def __rmatmul__(self, o): return o if isinstance(o, V) else M()
    def to_3x3(self): return M()
    def to_4x4(self): return M()
    def to_matrix(self): return M()
    def to_euler(self, *a): return (0.0, 0.0, 0.0)
    def inverted(self): return M()
    @staticmethod
    def Translation(v): return M()
    @staticmethod
    def Identity(n=4): return M()
    @staticmethod
    def Diagonal(v): return M()
    @staticmethod
    def Rotation(*a): return M()
    @staticmethod
    def Scale(*a): return M()


class E:
    def __init__(self, *a, **k): pass
    def to_matrix(self): return M()
    def to_quaternion(self): return M()


class _Anything:
    """Absorbs any attribute access / call and returns something harmless."""
    def __init__(self, name="?"): self._n = name
    def __getattr__(self, k): return _Anything(self._n + "." + k)
    def __call__(self, *a, **k): return {"verts": [], "geom": [], "faces": []}
    def __iter__(self): return iter(())


class FakeVert:
    __slots__ = ("co",)
    def __init__(self, co=(0, 0, 0)): self.co = V(co)


class _Seq(list):
    def new(self, *a, **k):
        v = FakeVert(a[0] if a else (0, 0, 0))
        REC.note_point(v.co)
        self.append(v)
        return v
    def ensure_lookup_table(self): pass
    def verify(self): return object()


class FakeBM:
    def __init__(self):
        self.verts = _Seq()
        self.edges = _Seq()
        self.faces = _Seq()
        self.verts.layers = _Anything("layers")
        self.loops = _Anything("loops")
    def to_mesh(self, me): pass
    def free(self): pass
    def normal_update(self): pass


def _install_fakes():
    mu = types.ModuleType("mathutils")
    mu.Vector, mu.Matrix, mu.Euler, mu.Quaternion = V, M, E, M
    mu.geometry = types.ModuleType("mathutils.geometry")
    sys.modules["mathutils"] = mu

    class _Data:
        objects = {}
        collections = {}
        materials = {}
        meshes = {}

    bpy = types.ModuleType("bpy")
    bpy.data = _Data()
    bpy.context = types.SimpleNamespace(scene=types.SimpleNamespace(collection=None),
                                        view_layer=None)
    bpy.ops = _Anything("bpy.ops")
    bpy.types = _Anything("bpy.types")
    bpy.app = types.SimpleNamespace(version_string="dryrun", version=(5, 2, 0))
    sys.modules["bpy"] = bpy

    bm = types.ModuleType("bmesh")
    bm.new = lambda *a, **k: FakeBM()
    bm.ops = _Anything("bmesh.ops")
    bm.types = types.SimpleNamespace(BMVert=FakeVert, BMFace=object, BMEdge=object)
    sys.modules["bmesh"] = bm


# ---------------------------------------------------------------- recorder
class Recorder:
    def __init__(self):
        self.reset()

    def reset(self):
        self.parts = []
        self.errors = []
        self.warnings = []
        self.calls = {}
        self.begun = []
        self.lo = [1e18, 1e18, 1e18]
        self.hi = [-1e18, -1e18, -1e18]
        self.part_bb = None
        self.coll_bb = {}          # collection -> [minx, miny, minz, maxx, maxy, maxz]

    def note_coll(self, cn, bb):
        if not bb:
            return
        cur = self.coll_bb.get(cn)
        if cur is None:
            self.coll_bb[cn] = list(bb)
        else:
            for i in range(3):
                cur[i] = min(cur[i], bb[i])
                cur[3 + i] = max(cur[3 + i], bb[3 + i])

    def note_point(self, p):
        try:
            t = (float(p[0]), float(p[1]), float(p[2]))
        except Exception:
            return
        for i in range(3):
            if not (-1e6 < t[i] < 1e6):
                return
        for i in range(3):
            self.lo[i] = min(self.lo[i], t[i])
            self.hi[i] = max(self.hi[i], t[i])
        if self.part_bb is None:
            self.part_bb = [t[0], t[1], t[2], t[0], t[1], t[2]]
        else:
            for i in range(3):
                self.part_bb[i] = min(self.part_bb[i], t[i])
                self.part_bb[3 + i] = max(self.part_bb[3 + i], t[i])

    def scan(self, args, kwargs):
        def walk(o, depth=0):
            if depth > 3:
                return
            if isinstance(o, V):
                self.note_point(o)
            elif isinstance(o, (tuple, list)):
                if len(o) == 3 and all(isinstance(x, (int, float)) for x in o):
                    self.note_point(o)
                else:
                    for x in o:
                        walk(x, depth + 1)
        for a in args:
            walk(a)
        for a in kwargs.values():
            walk(a)


REC = Recorder()


# ---------------------------------------------------------------- the fake lib
def _api_names():
    names = set()
    for path in (DEFENSELIB, PROPLIB, CUCUMBERLIB, CUKEMATH, GUARDIANLIB, GMATH):
        try:
            src = open(path, encoding="utf-8").read()
        except OSError:
            continue
        names |= set(re.findall(r"^def\s+(\w+)", src, re.M))
    return {n for n in names if not n.startswith("_")}


def _palette():
    out = {}
    for path, var in ((PROPLIB, "PALETTE"), (CUKEMATH, "CUKE_PALETTE")):
        try:
            src = open(path, encoding="utf-8").read()
        except OSError:
            continue
        m = re.search(r"^%s\s*=\s*(\{.*?^\})" % var, src, re.S | re.M)
        if m:
            out.update(ast.literal_eval(m.group(1)))
    return out


def _real(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    sys.modules[name] = m
    return m


API = _api_names()
PALETTE = _palette()
GM = _real(GMATH, "gmath")            # the real thing: roles, SPEC, pure maths


# pure-maths helpers from proplib reimplemented for real, so a script can do arithmetic
def ngon_pts(n, radius, phase=0.0, center=(0, 0)):
    return [(center[0] + math.cos(phase + 2 * math.pi * i / n) * radius,
             center[1] + math.sin(phase + 2 * math.pi * i / n) * radius) for i in range(n)]


def arc_pts(center, radius, a0, a1, n=8, ry=None):
    cx, cy = center
    ry = radius if ry is None else ry
    a0, a1 = math.radians(a0), math.radians(a1)
    return [(cx + math.cos(a0 + (a1 - a0) * i / (n - 1.0)) * radius,
             cy + math.sin(a0 + (a1 - a0) * i / (n - 1.0)) * ry) for i in range(n)]


def rounded_rect_pts(w, h, r, segs=3, center=(0, 0)):
    cx, cy = center
    r = max(0.0, min(r, 0.499 * min(w, h)))
    hw, hh = w / 2.0 - r, h / 2.0 - r
    out = []
    for (ox, oy, a0) in ((hw, hh, 0), (-hw, hh, 90), (-hw, -hh, 180), (hw, -hh, 270)):
        if r <= 1e-6:
            out.append((cx + ox, cy + oy))
        else:
            out += [(cx + p[0], cy + p[1]) for p in arc_pts((ox, oy), r, a0, a0 + 90, max(2, segs))]
    return out


def star_pts(n, r_out, r_in, phase=0.0, center=(0, 0)):
    out = []
    for i in range(2 * n):
        a = phase + math.pi * i / n
        rr = r_out if i % 2 == 0 else r_in
        out.append((center[0] + math.cos(a) * rr, center[1] + math.sin(a) * rr))
    return out


def teardrop_pts(w, h, n=10, center=(0, 0)):
    out = []
    for i in range(n):
        t = math.pi * i / (n - 1.0)
        x = math.sin(t) * (w / 2.0) * (1.0 - 0.85 * (i / (n - 1.0)) ** 2)
        y = -h / 2.0 + h * (i / (n - 1.0))
        out.append((center[0] + x, center[1] + y))
    for i in range(n - 2, 0, -1):
        t = math.pi * i / (n - 1.0)
        x = math.sin(t) * (w / 2.0) * (1.0 - 0.85 * (i / (n - 1.0)) ** 2)
        y = -h / 2.0 + h * (i / (n - 1.0))
        out.append((center[0] - x, center[1] + y))
    return out


def chevron_pts(width, depth, thickness, tip_at=+1):
    w, d, t = width / 2.0, depth, thickness
    s = 1 if tip_at >= 0 else -1
    return [(-w, 0.0), (0.0, s * d), (w, 0.0), (w, -s * t), (0.0, s * (d - t)), (-w, -s * t)]


def grid_positions(nx, ny, sx, sy, center=(0, 0), stagger=False):
    out = []
    for j in range(ny):
        y = center[1] + (j - (ny - 1) / 2.0) * sy
        off = (sx / 2.0 if (stagger and j % 2) else 0.0)
        for i in range(nx):
            out.append((center[0] + (i - (nx - 1) / 2.0) * sx + off, y))
    return out


def catenary_pts(a, b, sag, n=10):
    a, b = V(a), V(b)
    out = []
    for i in range(n):
        t = i / (n - 1.0)
        p = a.lerp(b, t)
        p.z -= sag * 4.0 * t * (1.0 - t)
        out.append(tuple(p))
    return out


def helix_pts(base, top, radius, turns=3.0, n=24, phase=0.0, radius2=None):
    a, b = V(base), V(top)
    r2 = radius if radius2 is None else radius2
    out = []
    for i in range(n):
        t = i / (n - 1.0)
        c = a.lerp(b, t)
        ang = phase + 2 * math.pi * turns * t
        r = radius + (r2 - radius) * t
        out.append((c.x + math.cos(ang) * r, c.y + math.sin(ang) * r, c.z))
    return out


FONT_GAP, FONT_W = 0.30, 1.0


def text_width(text, height=1.0, gap=FONT_GAP, width=FONT_W):
    n = len(text)
    return height * (n * width + max(0, n - 1) * gap) if n else 0.0


REAL = {f.__name__: f for f in (ngon_pts, arc_pts, rounded_rect_pts, star_pts, teardrop_pts,
                                chevron_pts, grid_positions, catenary_pts, helix_pts,
                                text_width)}
REAL["ring_positions"] = ngon_pts
for _n in dir(GM):                     # every numbers-only guardian helper, for real
    if not _n.startswith("_") and callable(getattr(GM, _n)):
        REAL[_n] = getattr(GM, _n)
_CONSTS = {n: getattr(GM, n) for n in dir(GM) if n.isupper() and not n.startswith("_")}
try:                                   # cukemath constants too (CUKE_H, SLICE_R, ...)
    _CM = _real(CUKEMATH, "cukemath")
    for _n in dir(_CM):
        if not _n.startswith("_") and callable(getattr(_CM, _n)):
            REAL.setdefault(_n, getattr(_CM, _n))
    _CONSTS.update({n: getattr(_CM, n) for n in dir(_CM) if n.isupper() and not n.startswith("_")})
except Exception:
    pass


class FakeObj:
    def __init__(self, name):
        self.name = name
        self.location = V()
        self.rotation_euler = V()
        self.scale = V((1, 1, 1))
        self.hide_render = False
        self.data = types.SimpleNamespace(polygons=[], materials=[], name=name)
        self._props = {}
    def __setitem__(self, k, v): self._props[k] = v
    def __getitem__(self, k): return self._props[k]
    def get(self, k, d=None): return self._props.get(k, d)


class FakeColl:
    def __init__(self, name):
        self.name = name
        self.objects = []


class FakeG:
    PALETTE = PALETTE
    TILE = 8.0
    STUDS_TILE = 2.0
    ROOT = HERE
    FONT_GAP, FONT_W = FONT_GAP, FONT_W
    Vector, Matrix, Euler = V, M, E
    MOVING_DEFAULT = True
    locals().update(_CONSTS)          # ROLES, SPEC, GUARDIANS, CUKE_H, ...

    def __init__(self):
        self._colls = {}
        self.REG = {}

    # -- real behaviour where it matters -------------------------------------
    def C(self, key):
        if key not in PALETTE:
            REC.errors.append("palette key %r does not exist" % key)
            return "ff00ff"
        return PALETTE[key]

    def coll(self, name):
        return self._colls.setdefault(name, FakeColl(name))

    def clear_collection(self, name):
        return self.coll(name)

    def begin(self, collection, guardian, prefix=None):
        if guardian not in GM.ROLES:
            REC.errors.append("unknown guardian %r" % guardian)
        REC.begun.append(collection)
        self.REG[collection] = {"guardian": guardian, "prefix": prefix or collection,
                                "parts": []}
        return self.coll(collection)

    def part(self, name, bm, c, role, pivot, parent=None, material=None, transparency=0.0,
             moving=None, emit=None, roughness=0.55, metallic=0.0, smooth=False,
             hex_override=None):
        cn = getattr(c, "name", "?")
        reg = self.REG.get(cn)
        if reg is None:
            REC.errors.append("part %r: G.begin(%r, ...) was never called" % (name, cn))
            g = None
        else:
            g = reg["guardian"]
        hexcol = hex_override
        if hexcol is None and g:
            try:
                hexcol = GM.role_hex(g, role)
            except KeyError as e:
                REC.errors.append(str(e).strip('"'))
                hexcol = "ff00ff"
        hexcol = hexcol or "ff00ff"
        mat = material or (("Neon" if (g and GM.is_neon(g, role)) else "SmoothPlastic"))
        if mat not in MATERIALS:
            REC.errors.append("part %r: rbx_material %r is not a Roblox material" % (name, mat))
        if not re.fullmatch(r"[0-9a-fA-F]{6}", str(hexcol).lstrip("#")):
            REC.errors.append("part %r: %r is not a 6-digit hex colour" % (name, hexcol))
        if not (0.0 <= float(transparency) <= 1.0):
            REC.errors.append("part %r: transparency %r outside 0..1" % (name, transparency))
        if emit is not None and float(emit) > 1.6:
            REC.warnings.append("part %r: emit=%s clips to white; use 0.6-1.5" % (name, emit))
        if not name or " " in name or not re.fullmatch(r"[A-Za-z0-9_]+", name or ""):
            REC.errors.append("part name %r must be letters/digits/underscore, no spaces" % name)
        if "_" in str(role):
            REC.errors.append("role %r must be ONE token - it is the last piece of the "
                              "part name and that is how Roblox finds the colour" % role)
        if any(p["name"] == name and p["coll"] == cn for p in REC.parts):
            REC.errors.append("duplicate part name %r in %s" % (name, cn))
        try:
            piv = (float(pivot[0]), float(pivot[1]), float(pivot[2]))
        except Exception:
            REC.errors.append("part %r: pivot %r is not an (x, y, z)" % (name, pivot))
            piv = (0.0, 0.0, 0.0)
        bb = REC.part_bb
        REC.part_bb = None
        REC.note_coll(cn, bb)
        if bb:
            for i, ax in enumerate("xyz"):
                if piv[i] < bb[i] - PIVOT_SLACK or piv[i] > bb[3 + i] + PIVOT_SLACK:
                    REC.warnings.append(
                        "part %r: pivot %s=%.2f is %.2f studs outside its own geometry "
                        "(%.2f..%.2f) - is the joint in the right place?"
                        % (name, ax, piv[i],
                           max(bb[i] - piv[i], piv[i] - bb[3 + i]), bb[i], bb[3 + i]))
        REC.parts.append({"name": name, "role": role, "parent": parent, "pivot": piv,
                          "hex": str(hexcol).lstrip("#"), "material": mat,
                          "transparency": float(transparency), "bbox": bb, "coll": cn,
                          "object": "%s_%s_%s" % (reg["prefix"] if reg else "?", name, role)})
        o = FakeObj("%s_%s_%s" % (reg["prefix"] if reg else "?", name, role))
        if hasattr(c, "objects"):
            c.objects.append(o)
        return o

    def hitbox(self, c, lo, hi, pivot=None, parent=None, name="Hitbox", role="Invisible"):
        REC.scan((lo, hi), {})
        mid = ((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0, (lo[2] + hi[2]) / 2.0)
        return self.part(name, FakeBM(), c, role, pivot or mid, parent=parent,
                         transparency=1.0, moving=False)

    def root_part(self, c, lo, hi, name="Root", role="Invisible"):
        return self.hitbox(c, lo, hi, parent=None, name=name, role=role)

    def new_obj(self, *a, **k):
        REC.errors.append("use G.part(...) for guardian pieces, not new_obj - every part "
                          "needs a pivot, a role and a rig parent")
        return FakeObj("?")

    def report(self, name):
        return {"collection": name, "parts": len(REC.parts), "tris": 0,
                "size_studs": [0, 0, 0], "min_z": 0, "per_part": {}}

    def bounds(self, name):
        return V(REC.lo), V(REC.hi)

    def rig_tree(self, name):
        return {p["name"]: p for p in REC.parts}

    def check_rig(self, name):
        return []

    def apply_pose(self, *a, **k): return {}
    def rest(self, *a, **k): return None
    def manifest(self, names): return []
    def build_stage(self, *a, **k): return FakeColl("_Stage")
    def render(self, *a, **k): return ""
    def export_fbx(self, *a, **k): return ""
    def hex_to_rgb(self, h): return (0.5, 0.5, 0.5)
    def material(self, *a, **k): return object()
    def rot_euler(self, rx=0, ry=0, rz=0): return M()
    def aim(self, d, up=(0, 0, 1)): return M()
    def surface_frame(self, n, up=(0, 0, 1)): return M()

    def place(self, loc=(0, 0, 0), rot=None, scale=1.0):
        REC.note_point(loc)
        return M()

    def xform(self, bm, verts, matrix): return verts
    def translate(self, bm, verts, offset): return verts
    def mirror_x(self, bm, verts): return list(verts)

    # -- everything else -----------------------------------------------------
    def __getattr__(self, k):
        if k in REAL:
            return REAL[k]
        if k in API:
            def rec(*a, **kw):
                REC.calls[k] = REC.calls.get(k, 0) + 1
                REC.scan(a, kw)
                _hint(k, a, kw)
                return [FakeVert() for _ in range(4)]
            rec.__name__ = k
            return rec
        raise AttributeError(
            "guardianlib has no %r - check the API list in GUARDIAN-BUILD.md "
            "(near-miss: %s)" % (k, ", ".join(sorted(n for n in API if n[:3] == k[:3])) or "none"))


# --------------------------------------------------------------- shape hints
# Helpers that take their extent as a keyword rather than as points, so REC.scan
# cannot see how big they are.
def _pt(o, d=(0.0, 0.0, 0.0)):
    try:
        return (float(o[0]), float(o[1]), float(o[2]))
    except Exception:
        return d


def _grow(c, r):
    REC.note_point((c[0] - r, c[1] - r, c[2] - r))
    REC.note_point((c[0] + r, c[1] + r, c[2] + r))


def _hint(name, a, kw):
    g = lambda k, i, d=None: kw.get(k, a[i] if len(a) > i else d)
    try:
        if name in ("tuft", "fur_coat"):
            c = _pt(g("center", 1) if name == "fur_coat" else g("base", 1))
            r = float(kw.get("length", 0.9))
            rad = kw.get("radii")
            if rad:
                r += max(float(x) for x in rad)
            _grow(c, r)
        elif name in ("blob", "puff"):
            c = _pt(g("center", 1))
            r = kw.get("radii") or kw.get("radius", 0.5)
            r = max(float(x) for x in r) if isinstance(r, (tuple, list)) else float(r)
            _grow(c, r)
        elif name in ("crescent",):
            c = _pt(g("center", 1))
            _grow(c, float(kw.get("r_out", 1.0)))
        elif name in ("hex_prism", "diamond", "ring_band", "barnacle", "stud_bump",
                      "patch", "cross_glyph", "shell_fan", "worm_ring", "tooth_ring"):
            c = _pt(g("center", 1) if name not in ("cross_glyph",) else g("center", 1))
            r = float(kw.get("radius", kw.get("r_out", kw.get("arm", 0.4))))
            _grow(c, max(r, float(kw.get("length", 0.0)), float(kw.get("height", 0.0))))
        elif name == "boulder_cluster":
            for s in (g("slots", 1) or []):
                _grow(_pt(s), float(kw.get("radius", 0.9)))
        elif name == "face_text":
            _grow(_pt(g("center", 2)), float(kw.get("height", 0.6)))
    except Exception:
        pass


# ---------------------------------------------------------------- runner
def check(path):
    REC.reset()
    name = os.path.basename(path)
    out = {"file": name, "ok": False, "errors": [], "warnings": []}
    try:
        spec = importlib.util.spec_from_file_location("dryrun_" + name[:-3], path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception:
        out["errors"].append("import failed:\n" + traceback.format_exc())
        return out

    for attr in ("COLLECTION", "GUARDIAN", "NOTES", "build"):
        if not hasattr(mod, attr):
            out["errors"].append("module does not export %s" % attr)
    if out["errors"]:
        return out

    G = FakeG()
    try:
        res = mod.build(G)
    except Exception:
        out["errors"].append("build() raised:\n" + traceback.format_exc())
        return out

    cn, gd = mod.COLLECTION, mod.GUARDIAN
    if cn not in REC.begun:
        out["errors"].append("build() never calls G.begin(%r, %r) - not idempotent" % (cn, gd))
    if res is None:
        out["errors"].append("build() must return the collection (return c)")
    if not REC.parts:
        out["errors"].append("build() created no parts")
    bad_coll = sorted({p["coll"] for p in REC.parts} - set(REC.begun))
    if bad_coll:
        out["errors"].append("parts written into a collection that was never begun: %s"
                             % ", ".join(bad_coll))
    stray = sorted(set(REC.begun) - {cn} - {cn + "_Seat", cn + "_Extra"})
    if stray:
        out["warnings"].append("collections outside the <Guardian>/_Seat/_Extra naming: %s"
                               % ", ".join(stray))

    # ---- the rig, per collection --------------------------------------------
    main = [p for p in REC.parts if p["coll"] == cn]
    byname = {p["name"]: p for p in main}
    for coll in sorted({p["coll"] for p in REC.parts}):
        grp = [p for p in REC.parts if p["coll"] == coll]
        known = {p["name"]: p for p in grp}
        roots = [p["name"] for p in grp if not p["parent"]]
        if len(roots) != 1:
            out["errors"].append("%s: expected exactly ONE root part (parent=None), found %s"
                                 % (coll, roots or "none"))
        for p in grp:
            if p["parent"] and p["parent"] not in known:
                out["errors"].append("%s part %r: parent %r does not exist (parts: %s)"
                                     % (coll, p["name"], p["parent"], ", ".join(known)))
        for p in grp:                                     # cycles
            seen, cur = {p["name"]}, p["parent"]
            while cur and cur in known:
                if cur in seen:
                    out["errors"].append("%s part %r: parent cycle through %r"
                                         % (coll, p["name"], cur))
                    break
                seen.add(cur)
                cur = known[cur]["parent"]
        for p in grp:
            if p["transparency"] >= 0.99 and p["name"] not in ("Hitbox", "Root"):
                out["warnings"].append("%s part %r is invisible but is not the Hitbox or Root"
                                       % (coll, p["name"]))
    if not any(p["name"] == "Hitbox" for p in main):
        out["errors"].append("no part called Hitbox - every guardian needs one invisible "
                             "box for queries")
    if not any(p["name"] == "Root" for p in main):
        out["errors"].append("no part called Root - the rig needs an invisible root")
    if cn + "_Seat" not in REC.begun:
        out["warnings"].append("no %s_Seat collection - every guardian needs its seat prop" % cn)

    # ---- the poses ----------------------------------------------------------
    poses = getattr(mod, "POSES", None)
    if not isinstance(poses, dict) or not poses:
        out["errors"].append("module must export POSES = {'Sit': {...}, 'Awake': {...}} - "
                             "the asleep and awake states the brief asks for")
    else:
        for want in ("Sit", "Awake"):
            if want not in poses:
                out["errors"].append("POSES has no %r entry" % want)
        for pname, pose in poses.items():
            if not isinstance(pose, dict):
                out["errors"].append("POSES[%r] must be {part: (rx, ry, rz)}" % pname)
                continue
            for k, v in pose.items():
                if k not in byname:
                    out["errors"].append("POSES[%r] rotates %r, which is not a part" % (pname, k))
                elif not (isinstance(v, (tuple, list)) and len(v) == 3):
                    out["errors"].append("POSES[%r][%r] must be (rx, ry, rz) degrees" % (pname, k))

    # ---- size, per collection -----------------------------------------------
    out["sizes"] = {}
    for coll, bb in sorted(REC.coll_bb.items()):
        out["sizes"][coll] = {"size": [round(bb[3 + i] - bb[i], 2) for i in range(3)],
                              "min_z": round(bb[2], 3),
                              "centre_xy": [round((bb[0] + bb[3]) / 2, 2),
                                            round((bb[1] + bb[4]) / 2, 2)]}
        if bb[2] < -0.35:
            out["warnings"].append("%s reaches z=%.2f - nothing may sit below the ground "
                                   "plane unless NOTES says so" % (coll, bb[2]))
    bb = REC.coll_bb.get(cn)
    if bb:
        out["size"] = [round(bb[3 + i] - bb[i], 2) for i in range(3)]
        out["min_z"] = round(bb[2], 3)
        out["center_xy"] = [round((bb[0] + bb[3]) / 2, 2), round((bb[1] + bb[4]) / 2, 2)]
        spec = GM.SPEC.get(gd)
        if spec:
            want, got = spec["stand"], bb[5] - max(0.0, bb[2])
            if got < want * 0.75 or got > want * 1.25:
                out["warnings"].append("approx height %.1f studs, SPEC says %.1f for %s "
                                       "(the dry run ignores rot=/matrix=, so check the "
                                       "Blender build before chasing this)" % (got, want, gd))
    out["parts"] = len(main)
    out["all_parts"] = len(REC.parts)
    out["roles"] = sorted({p["role"] for p in main})
    out["materials"] = sorted({p["material"] for p in REC.parts})
    out["calls"] = dict(sorted(REC.calls.items(), key=lambda kv: -kv[1]))
    out["rig"] = ["%s < %s" % (p["name"], p["parent"] or "ROOT") for p in main]
    out["errors"] += REC.errors
    out["warnings"] += REC.warnings
    out["ok"] = not out["errors"]
    return out


def main(argv):
    _install_fakes()
    files = argv[1:] or sorted(f for f in os.listdir(HERE) if re.fullmatch(r"build_\w+\.py", f))
    bad = 0
    for f in files:
        p = f if os.path.isabs(f) else os.path.join(HERE, f)
        r = check(p)
        flag = "PASS" if r["ok"] else "FAIL"
        print("=" * 72)
        print("%s  %s" % (flag, r["file"]))
        if "parts" in r:
            print("  parts %s (%s with seat/extra)   approx size %s   min_z %s   centre_xy %s"
                  % (r["parts"], r["all_parts"], r.get("size"), r.get("min_z"),
                     r.get("center_xy")))
            for coll, d in r.get("sizes", {}).items():
                print("    %-20s %s  min_z %s" % (coll, d["size"], d["min_z"]))
            print("  materials: %s" % ", ".join(r["materials"]))
            print("  roles: %s" % ", ".join(r["roles"]))
            print("  rig: %s" % "; ".join(r["rig"]))
        for w in r["warnings"]:
            print("  WARN  " + w)
        for e in r["errors"]:
            print("  ERROR " + e)
        if not r["ok"]:
            bad += 1
    print("=" * 72)
    print("%d/%d passed" % (len(files) - bad, len(files)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
