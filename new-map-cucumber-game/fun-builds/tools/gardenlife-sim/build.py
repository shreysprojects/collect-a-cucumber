"""GardenLife offline simulation (2026-09-24): mock Roblox + FunBuildKit + the Tree / Sunflower / Scarecrow / HayBale / Bush
behaviours, run in the Luau CLI:  py tools/gardenlife-sim/build.py  -> stats + ALL CHECKS PASSED. Test-only, nothing here ships."""
import os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
LUAU = r"C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"

def wrap(name, path):
    src = open(path, encoding="utf-8").read()
    src = re.sub(r"\brequire\(", "__require(", src)
    src = re.sub(r"\btypeof\(", "__typeof(", src)
    return '__modules["%s"] = (function()\n%s\nend)()\n' % (name, src)

PART = re.compile(r"^\s+(\S+) \[(\w+)\] pos \(([-\d.]+), ([-\d.]+), ([-\d.]+)\) size \(([-\d.]+), ([-\d.]+), ([-\d.]+)\) (\w+) ([0-9a-f]{6})")
ATTR = re.compile(r"^\s+@(Pivot_\w+) = \(([-\d.]+), ([-\d.]+), ([-\d.]+)\)")

def dump(name):
    parts, attrs = [], []
    for line in open(os.path.join(FB, "props-dump", name + ".txt"), encoding="utf-8"):
        m = PART.match(line)
        if m:
            n, cls, px, py, pz, sx, sy, sz, mat, col = m.groups()
            parts.append('{Name="%s",Class="%s",P={%s,%s,%s},S={%s,%s,%s},C="%s"}' % (n, cls, px, py, pz, sx, sy, sz, col))
        m = ATTR.match(line)
        if m:
            attrs.append('{"%s",%s,%s,%s}' % m.groups())
    return 'DUMPS["%s"] = {Parts={%s},Pivots={%s}}\n' % (name, ",".join(parts), ",".join(attrs))

out = [open(os.path.join(HERE, "mock.luau"), encoding="utf-8").read()]
out.append("local DUMPS = {}\n")
for n in ("Tree", "Sunflower", "Scarecrow", "HayBale", "Bush"):
    out.append(dump(n))
out.append(wrap("FunBuildKit", os.path.join(FB, "src", "FunBuildKit.lua")))
out.append(wrap("FunAssets", os.path.join(FB, "src", "FunAssets.lua")))
for side in ("client", "server"):
    d = os.path.join(FB, "src", "behaviours", side)
    for n in ("Tree", "Sunflower", "Scarecrow", "HayBale", "Bush"):
        p = os.path.join(d, n + ".lua")
        if os.path.exists(p):
            out.append(wrap(side + "/" + n, p))
out.append(open(os.path.join(HERE, sys.argv[1] if len(sys.argv) > 1 else "test.luau"), encoding="utf-8").read())
target = os.path.join(tempfile.gettempdir(), "gardenlife_run.luau")
open(target, "w", encoding="utf-8").write("\n".join(out))
r = subprocess.run([LUAU, target], capture_output=True, text=True)
print(r.stdout)
print(r.stderr)
sys.exit(r.returncode)
