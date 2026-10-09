"""Offline pre-flight for a props build script - runs it WITHOUT Blender.

    py dryrun.py build_tree.py            # one script
    py dryrun.py                          # every build_*.py in this folder

It fakes `bpy` / `bmesh` / `mathutils`, hands `build()` a stand-in for proplib that knows
every real API name, and reports what the script would make.  It catches, cheaply and in
parallel-safe isolation:

  * syntax errors and NameErrors
  * calls to a lib function that does not exist (typo'd primitive)
  * a palette key that is not in PALETTE
  * a bad hex colour / unknown rbx_material / transparency out of range
  * duplicate or malformed part names
  * a missing `clear_collection` (the idempotency guarantee)
  * missing COLLECTION / NOTES / build exports, or build() not returning the collection
  * gross scale mistakes and geometry below the ground plane

It does NOT run real geometry, so the bounding box it prints is an APPROXIMATION taken
from the literal coordinates passed to primitives, before any rot=/matrix= transform.
Treat it as a smell test; `buildall.build_all()` inside Blender is the source of truth.
"""
import sys, os, re, ast, math, types, importlib.util, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
DEFENSELIB = os.path.join(os.path.dirname(HERE), "defenses", "defenselib.py")
PROPLIB = os.path.join(HERE, "proplib.py")

MATERIALS = {"SmoothPlastic", "Plastic", "Metal", "DiamondPlate", "CorrodedMetal", "Wood",
             "WoodPlanks", "Slate", "Concrete", "Brick", "Cobblestone", "Grass", "Sand",
             "Fabric", "Foil", "Glass", "Ice", "Marble", "Neon", "Pebble", "Granite",
             "Rock", "Sandstone", "Basalt", "CrackedLava", "Glacier", "Ground", "LeafyGrass",
             "Limestone", "Mud", "Pavement", "Salt", "Snow", "Asphalt", "Cardboard",
             "Carpet", "Ceramic Tiles", "Clay Roof Tiles", "Leather", "Plaster", "Rubber"}


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
        return V((self.y * o.z - self.z * o.y, self.z * o.x - self.x * o.z, self.x * o.y - self.y * o.x))

    def lerp(self, o, t): o = V(o); return self + (o - self) * t
    def copy(self): return V(self)
    def to_tuple(self, n=6): return (self.x, self.y, self.z)
    def rotation_difference(self, o): return M()
    def to_track_quat(self, *a): return M()


class M:
    """Opaque 4x4 stand-in: composes with @ and swallows everything."""
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
    bpy.context = types.SimpleNamespace(scene=types.SimpleNamespace(collection=None), view_layer=None)
    bpy.ops = _Anything("bpy.ops")
    bpy.types = _Anything("bpy.types")
    bpy.app = types.SimpleNamespace(version_string="dryrun", version=(5, 2, 0))
    sys.modules["bpy"] = bpy

    bm = types.ModuleType("bmesh")
    bm.new = lambda *a, **k: FakeBM()
    bm.ops = _Anything("bmesh.ops")
    bm.types = types.SimpleNamespace(BMVert=FakeVert, BMFace=object, BMEdge=object)
    sys.modules["bmesh"] = bm


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
    def layers_uv(self): return object()


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


# ---------------------------------------------------------------- recorder
class Recorder:
    def __init__(self):
        self.reset()

    def reset(self):
        self.parts = []
        self.errors = []
        self.warnings = []
        self.calls = {}
        self.cleared = []
        self.lo = [1e18, 1e18, 1e18]
        self.hi = [-1e18, -1e18, -1e18]
        self.part_lo = None

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
        if self.part_lo is None:
            self.part_lo = [t[0], t[1], t[2], t[0], t[1], t[2]]
        else:
            for i in range(3):
                self.part_lo[i] = min(self.part_lo[i], t[i])
                self.part_lo[3 + i] = max(self.part_lo[3 + i], t[i])

    def scan(self, args, kwargs):
        """Pull anything that looks like a 3-D point out of a call's arguments."""
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
    for path in (DEFENSELIB, PROPLIB):
        try:
            src = open(path, encoding="utf-8").read()
        except OSError:
            continue
        names |= set(re.findall(r"^def\s+(\w+)", src, re.M))
    return {n for n in names if not n.startswith("_")}


def _palette():
    src = open(PROPLIB, encoding="utf-8").read()
    m = re.search(r"^PALETTE\s*=\s*(\{.*?^\})", src, re.S | re.M)
    return ast.literal_eval(m.group(1)) if m else {}


API = _api_names()
PALETTE = _palette()

# pure-maths helpers reimplemented for real, so scripts can do arithmetic on the results
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
                                chevron_pts, grid_positions, catenary_pts, helix_pts, text_width)}
REAL["ring_positions"] = ngon_pts


class FakeObj:
    def __init__(self, name):
        self.name = name
        self.location = V()
        self.rotation_euler = V()
        self.scale = V((1, 1, 1))
        self.data = types.SimpleNamespace(polygons=[], materials=[])
        self._props = {}
    def __setitem__(self, k, v): self._props[k] = v
    def __getitem__(self, k): return self._props[k]
    def get(self, k, d=None): return self._props.get(k, d)


class FakeColl:
    def __init__(self, name):
        self.name = name
        self.objects = []


class FakeD:
    PALETTE = PALETTE
    TILE = 8.0
    STUDS_TILE = 2.0
    ROOT = HERE
    FONT_GAP, FONT_W = FONT_GAP, FONT_W
    Vector, Matrix, Euler = V, M, E

    def __init__(self):
        self._colls = {}

    # -- real behaviour where it matters -------------------------------------
    def C(self, key):
        if key not in PALETTE:
            REC.errors.append("palette key %r does not exist" % key)
            return "ff00ff"
        return PALETTE[key]

    def coll(self, name):
        REC.calls["coll"] = REC.calls.get("coll", 0) + 1
        c = self._colls.setdefault(name, FakeColl(name))
        return c

    def clear_collection(self, name):
        REC.cleared.append(name)
        return self.coll(name)

    def new_obj(self, name, bm, c, hexcol, rbx_material="SmoothPlastic", transparency=0.0,
                metallic=0.0, roughness=0.55, smooth=False, emit=None, **kw):
        h = str(hexcol).lstrip("#")
        if not re.fullmatch(r"[0-9a-fA-F]{6}", h):
            REC.errors.append("part %r: %r is not a 6-digit hex colour" % (name, hexcol))
        if rbx_material not in MATERIALS:
            REC.errors.append("part %r: rbx_material %r is not a Roblox material" % (name, rbx_material))
        if not (0.0 <= float(transparency) <= 1.0):
            REC.errors.append("part %r: transparency %r outside 0..1" % (name, transparency))
        if emit is not None and not (0.0 <= float(emit) <= 3.0):
            REC.warnings.append("part %r: emit=%s (over ~1.6 clips to white)" % (name, emit))
        if emit is not None and float(emit) > 1.6:
            REC.warnings.append("part %r: emit=%s clips to white; use 0.6-1.5" % (name, emit))
        if " " in name or not name:
            REC.errors.append("part name %r must be non-empty with no spaces" % name)
        if name in [p["name"] for p in REC.parts]:
            REC.errors.append("duplicate part name %r" % name)
        bb = REC.part_lo
        REC.part_lo = None
        REC.parts.append({"name": name, "hex": h, "material": rbx_material,
                          "transparency": float(transparency), "bbox": bb,
                          "coll": getattr(c, "name", "?")})
        o = FakeObj(getattr(c, "name", "?") + "." + name)
        if hasattr(c, "objects"):
            c.objects.append(o)
        return o

    def report(self, name):
        return {"collection": name, "parts": len(REC.parts), "tris": 0,
                "size_studs": [0, 0, 0], "min_z": 0, "per_part": {}}

    def bounds(self, name):
        return V(REC.lo), V(REC.hi)

    def manifest(self, names):
        return []

    def build_stage(self, *a, **k): return FakeColl("_Stage")
    def render(self, *a, **k): return ""
    def export_fbx(self, *a, **k): return ""
    def hex_to_rgb(self, h): return (0.5, 0.5, 0.5)
    def material(self, *a, **k): return object()

    def rot_euler(self, rx=0, ry=0, rz=0): return M()
    def aim(self, d, up=(0, 0, 1)): return M()
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
                return [FakeVert() for _ in range(4)]
            rec.__name__ = k
            return rec
        raise AttributeError(
            "proplib has no %r - check the API list in PROPS.md (near-miss: %s)"
            % (k, ", ".join(sorted(n for n in API if n[:3] == k[:3])) or "none"))


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

    for attr in ("COLLECTION", "NOTES", "build"):
        if not hasattr(mod, attr):
            out["errors"].append("module does not export %s" % attr)
    if out["errors"]:
        return out

    D = FakeD()
    try:
        res = mod.build(D)
    except Exception:
        out["errors"].append("build() raised:\n" + traceback.format_exc())
        return out

    cn = mod.COLLECTION
    if cn not in REC.cleared:
        out["errors"].append("build() never calls D.clear_collection(%r) - not idempotent" % cn)
    if res is None:
        out["errors"].append("build() must return the collection (return c)")
    if not REC.parts:
        out["errors"].append("build() created no parts")
    bad_coll = sorted({p["coll"] for p in REC.parts} - {cn})
    if bad_coll:
        out["errors"].append("parts written into unexpected collection(s): %s" % ", ".join(bad_coll))

    lo, hi = REC.lo, REC.hi
    if lo[0] < 1e17:
        size = [round(hi[i] - lo[i], 2) for i in range(3)]
        out["size"] = size
        out["min_z"] = round(lo[2], 3)
        out["center_xy"] = [round((lo[0] + hi[0]) / 2, 2), round((lo[1] + hi[1]) / 2, 2)]
        if lo[2] < -0.35:
            out["warnings"].append("geometry reaches z=%.2f - nothing may sit below the ground "
                                   "plane unless NOTES says so" % lo[2])
        if max(size) > 40:
            out["warnings"].append("approx size %s studs - an R15 avatar is only 5 tall" % size)
    out["parts"] = len(REC.parts)
    out["materials"] = sorted({p["material"] for p in REC.parts})
    out["colours"] = len({p["hex"] for p in REC.parts})
    out["calls"] = dict(sorted(REC.calls.items(), key=lambda kv: -kv[1]))
    out["errors"] += REC.errors
    out["warnings"] += REC.warnings
    for extra in ("PIVOTS", "STATES", "VARIANTS"):
        if hasattr(mod, extra):
            out[extra] = getattr(mod, extra)
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
            print("  parts %s   approx size %s   min_z %s   centre_xy %s"
                  % (r["parts"], r.get("size"), r.get("min_z"), r.get("center_xy")))
            print("  materials: %s   distinct colours: %s" % (", ".join(r["materials"]), r["colours"]))
        for k in ("PIVOTS", "STATES", "VARIANTS"):
            if k in r:
                print("  %s = %s" % (k, r[k]))
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
