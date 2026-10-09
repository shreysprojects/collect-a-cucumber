"""Builds run.luau = mock.luau + embedded module sources + prop dumps (as Lua tables) + tests.luau."""
import os, re
HERE = os.path.dirname(os.path.abspath(__file__))
FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
SOURCES = {
    "FunBuildKit": os.path.join(FB, "src", "FunBuildKit.lua"),
    "FunAssets": os.path.join(FB, "src", "FunAssets.lua"),
    "C_Lantern": os.path.join(FB, "src", "behaviours", "client", "Lantern.lua"),
    "C_TikiTorch": os.path.join(FB, "src", "behaviours", "client", "TikiTorch.lua"),
    "C_Fountain": os.path.join(FB, "src", "behaviours", "client", "Fountain.lua"),
    "C_Pond": os.path.join(FB, "src", "behaviours", "client", "Pond.lua"),
    "S_Fountain": os.path.join(FB, "src", "behaviours", "server", "Fountain.lua"),
}
DUMPS = ["Lantern", "TikiTorch", "Fountain", "Pond"]

def lua_long(s):
    eq = "=" * 6
    assert ("]" + eq + "]") not in s
    return "[" + eq + "[\n" + s + "]" + eq + "]"

V = r"\(\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\)"
out = [open(os.path.join(HERE, "mock.luau"), encoding="utf-8").read(), "\nSOURCES = {}\n"]
for name, path in SOURCES.items():
    out.append("SOURCES[%r] = %s\n" % (name, lua_long(open(path, encoding="utf-8").read())))
out.append("DUMPS = {}\n")
for d in DUMPS:
    lines = open(os.path.join(FB, "props-dump", d + ".txt"), encoding="utf-8").read().splitlines()
    attrs, parts = [], []
    for ln in lines:
        m = re.match(r"\s*@(Pivot_\w+) = " + V, ln)
        if m:
            attrs.append("%s = Vector3.new(%s, %s, %s)" % m.groups())
            continue
        m = re.match(r"\s*(\w+) \[MeshPart\] pos " + V + r" size " + V + r" (\w+) (\w+) T([\d.]+) collide=(\w+)", ln)
        if m:
            g = m.groups()
            parts.append("{Name = %r, Pos = Vector3.new(%s, %s, %s), Size = Vector3.new(%s, %s, %s), T = %s, Collide = %s}"
                         % (g[0], g[1], g[2], g[3], g[4], g[5], g[6], g[9], g[10]))
    out.append("DUMPS[%r] = {Attrs = {%s}, Parts = {\n\t%s,\n}}\n" % (d, ", ".join(attrs), ",\n\t".join(parts)))
out.append(open(os.path.join(HERE, "tests.luau"), encoding="utf-8").read())
open(os.path.join(HERE, "run.luau"), "w", encoding="utf-8").write("".join(out))
print("wrote run.luau")
