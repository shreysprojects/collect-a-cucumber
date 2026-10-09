"""Builds run.luau = mock.luau + embedded module sources + the models' parts.json (as Lua tables) + tests.luau.

    py gen.py && "C:\\Users\\shrey\\.rokit\\tool-storage\\luau-lang\\luau\\0.739.0\\luau.exe" run.luau
"""
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
SOURCES = {
    "FunBuildKit": os.path.join(FB, "src", "FunBuildKit.lua"),
    "FunAssets": os.path.join(FB, "src", "FunAssets.lua"),
    "C_Aquarium": os.path.join(FB, "src", "behaviours", "client", "Aquarium.lua"),
    "S_Aquarium": os.path.join(FB, "src", "behaviours", "server", "Aquarium.lua"),
    "C_PottedPlant": os.path.join(FB, "src", "behaviours", "client", "PottedPlant.lua"),
}
MODELS = ["Aquarium", "PottedPlant"]


def lua_long(s):
    eq = "=" * 6
    assert ("]" + eq + "]") not in s
    return "[" + eq + "[\n" + s + "]" + eq + "]"


def num(v):
    return repr(float(v))


out = [open(os.path.join(HERE, "mock.luau"), encoding="utf-8").read(), "\nSOURCES = {}\n"]
for name, path in SOURCES.items():
    out.append("SOURCES[%r] = %s\n" % (name, lua_long(open(path, encoding="utf-8").read())))
out.append("MODELS = {}\n")
for key in MODELS:
    info = json.load(open(os.path.join(FB, "models", "out", key + ".parts.json"), encoding="utf-8"))
    parts = []
    for p in info["parts"]:
        parts.append("{Name = %r, Shape = %r, Size = Vector3.new(%s), CF = {%s}, T = %s, Collide = %s}" % (
            p["name"], p["shape"], ", ".join(num(v) for v in p["size"]), ", ".join(num(v) for v in p["cf"]),
            num(p["transparency"]), "true" if p["collide"] else "false"))
    pivots = ", ".join("Pivot_%s = Vector3.new(%s)" % (k, ", ".join(num(c) for c in v)) for k, v in info["pivots"].items())
    attrs = ", ".join("%s = %s" % (k, json.dumps(v)) for k, v in info["attrs"].items() if isinstance(v, (int, float, str)))
    out.append("MODELS[%r] = {Min = Vector3.new(%s), Max = Vector3.new(%s), Attrs = {%s, %s}, Parts = {\n\t%s,\n}}\n" % (
        key, ", ".join(num(c) for c in info["min"]), ", ".join(num(c) for c in info["max"]), pivots, attrs,
        ",\n\t".join(parts)))
out.append(open(os.path.join(HERE, "tests.luau"), encoding="utf-8").read())
open(os.path.join(HERE, "run.luau"), "w", encoding="utf-8").write("".join(out))
print("wrote run.luau")
