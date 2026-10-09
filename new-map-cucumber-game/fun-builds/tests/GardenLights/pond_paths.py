"""Pond water outline (authored ROBLOX frame: x, z = -blender_y) + candidate koi loops.
Replicates build_pond.py's _rings() exactly, then checks every sampled fish pose (body
length included) stays inside the waterline with a margin. Writes pond_paths.png."""
import math, random, sys
from PIL import Image, ImageDraw

N = 9; SEED = 20260909; RX, RY = 5.49, 3.93; SPAN_X, SPAN_Y = 8.96, 6.36; BAY_AT = 2; BAY_R = 0.46

def ngon_pts(n, radius, phase=0.0, center=(0, 0)):
    return [(center[0] + math.cos(phase + 2 * math.pi * i / n) * radius,
             center[1] + math.sin(phase + 2 * math.pi * i / n) * radius) for i in range(n)]

def rings():
    rng = random.Random(SEED)
    base = ngon_pts(N, 1.0, phase=0.13)
    outer, inner = [], []
    for k, (bx, by) in enumerate(base):
        a = math.atan2(by, bx) + rng.uniform(-0.15, 0.15)
        r = rng.uniform(0.70, 1.20)
        f = rng.uniform(0.72, 0.81)
        if k == BAY_AT:
            r = BAY_R
        ox, oy = math.cos(a) * RX * r, math.sin(a) * RY * r
        outer.append((ox, oy)); inner.append((ox * f, oy * f))
        rng.uniform(0.0, 0.36)
    xs = [p[0] for p in outer]; ys = [p[1] for p in outer]
    cx, cy = (min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5
    sx, sy = SPAN_X / (max(xs) - min(xs)), SPAN_Y / (max(ys) - min(ys))
    outer = [((x - cx) * sx, (y - cy) * sy) for (x, y) in outer]
    inner = [((x - cx) * sx, (y - cy) * sy) for (x, y) in inner]
    return outer, inner

outer, inner = rings()
water = [(x * 1.008, -y * 1.008) for (x, y) in inner]   # roblox (x, z)
outerR = [(x, -y) for (x, y) in outer]
PADS = [(-2.00, 1.20, 0.68), (-0.55, 1.76, 0.46), (2.25, 0.92, 0.52), (0.65, -1.53, 0.58), (-2.10, -0.45, 0.40)]
PADS = [(x, -y, r) for (x, y, r) in PADS]
print("water polygon (roblox x,z):")
for p in water: print("  (%.3f, %.3f)" % p)
xs = [p[0] for p in water]; zs = [p[1] for p in water]
print("water bbox x %.2f..%.2f z %.2f..%.2f" % (min(xs), max(xs), min(zs), max(zs)))

def inside(pt, poly):
    x, y = pt; c = False; n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]; x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1: c = not c
    return c

def seg_dist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def edge_dist(p, poly):
    return min(seg_dist(p, poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))

# ---- koi loops: MUST mirror Pond.lua's FISH table ------------------------------------
# path(s): centre + (rx*cos(s), rz*sin(k*s)) rotated by rot (deg); k = 1 ellipse, k = 2 figure-eight
FISH = [
    # name, centre(x,z), rx, rz, rot, k, len
    ("Fish1", (1.30, -0.10), 1.25, 0.80, -20, 1, 1.04 * 1.00),
    ("Fish2", (-0.70, 1.05), 1.10, 0.45, 10, 2, 1.04 * 0.94),
    ("Fish3", (-1.75, -0.35), 0.70, 0.95, 0, 1, 1.04 * 0.84),
]
if len(sys.argv) > 1:
    exec(open(sys.argv[1]).read())

def path(f, s):
    _, c, rx, rz, rot, k, _ = f
    x, z = rx * math.cos(s), rz * math.sin(k * s)
    a = math.radians(rot)
    return (c[0] + x * math.cos(a) - z * math.sin(a), c[1] + x * math.sin(a) + z * math.cos(a))

ok = True
for f in FISH:
    worst = 9
    for i in range(720):
        s = 2 * math.pi * i / 720
        p = path(f, s); q = path(f, s + 1e-3)
        d = (q[0] - p[0], q[1] - p[1]); L = math.hypot(*d); d = (d[0] / L, d[1] / L)
        half = f[6] * 0.5 + 0.25   # half body + tail
        for pt in (p, (p[0] + d[0] * half, p[1] + d[1] * half), (p[0] - d[0] * half, p[1] - d[1] * half)):
            if not inside(pt, water):
                worst = -1
            else:
                worst = min(worst, edge_dist(pt, water))
    print("%s min clearance to waterline %.2f" % (f[0], worst))
    if worst < 0.2: ok = False
# fish vs fish closest approach over a shared clock with the Lua speeds
SPEED = {"Fish1": 2 * math.pi / 13.0, "Fish2": 2 * math.pi / 17.0, "Fish3": -2 * math.pi / 11.0}

# ---- picture ----------------------------------------------------------------------------
S = 70; W = int(10.5 * S); H = int(7.5 * S)
img = Image.new("RGB", (W, H), (30, 34, 44)); d = ImageDraw.Draw(img)
def px(p): return (W / 2 + p[0] * S, H / 2 + p[1] * S)
d.polygon([px(p) for p in outerR], fill=(110, 81, 56))
d.polygon([px(p) for p in water], fill=(47, 158, 196))
for (x, z, r) in PADS:
    d.ellipse([px((x - r, z - r)), px((x + r, z + r))], outline=(47, 107, 44), width=3)
cols = [(255, 138, 61), (242, 239, 228), (255, 200, 61)]
for f, col in zip(FISH, cols):
    pts = [px(path(f, 2 * math.pi * i / 200)) for i in range(201)]
    d.line(pts, fill=col, width=2)
for name, (x, z) in (("F1", (1.42, -0.16)), ("F2", (-1.04, 1.14)), ("F3", (-2.12, -0.16))):
    c = px((x, z)); d.ellipse([c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4], fill=(255, 0, 0)); d.text((c[0] + 5, c[1]), name, fill=(255, 255, 255))
d.text((10, 10), "+X right, +Z down (front = -Z = top)", fill=(255, 255, 255))
img.save(sys.argv[2] if len(sys.argv) > 2 else "pond_paths.png")
print("OK" if ok else "CLEARANCE FAIL")
