"""HomeHearth headless test: builds run.luau = mock.luau + embedded module sources + the two models' parts.json
(as Lua tables) + tests.luau, then runs it with the Luau CLI.

    py gen.py          (writes run.luau and runs it; exit code 1 on any FAIL)
"""
import os
import json
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FB = os.path.dirname(os.path.dirname(HERE))
LUAU = r"C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
SOURCES = {
    "FunBuildKit": os.path.join(FB, "src", "FunBuildKit.lua"),
    "FunAssets": os.path.join(FB, "src", "FunAssets.lua"),
    "C_Fireplace": os.path.join(FB, "src", "behaviours", "client", "Fireplace.lua"),
    "S_Fireplace": os.path.join(FB, "src", "behaviours", "server", "Fireplace.lua"),
    "C_FloorLamp": os.path.join(FB, "src", "behaviours", "client", "FloorLamp.lua"),
    "S_FloorLamp": os.path.join(FB, "src", "behaviours", "server", "FloorLamp.lua"),
}
MODELS = ["Fireplace", "FloorLamp"]


def lua_long(s):
    eq = "=" * 6
    assert ("]" + eq + "]") not in s
    return "[" + eq + "[\n" + s + "]" + eq + "]"


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v))
    if isinstance(v, str):
        return lua_long(v) if "\n" in v else json.dumps(v)
    raise TypeError(v)


out = [open(os.path.join(HERE, "mock.luau"), encoding="utf-8").read(), "\nSOURCES = {}\n"]
for name, path in SOURCES.items():
    out.append("SOURCES[%r] = %s\n" % (name, lua_long(open(path, encoding="utf-8").read())))
out.append("MODELS = {}\n")
for key in MODELS:
    info = json.load(open(os.path.join(FB, "models", "out", key + ".parts.json"), encoding="utf-8"))
    parts = []
    for p in info["parts"]:
        parts.append("{Name = %s, Shape = %s, Size = Vector3.new(%s), CF = {%s}, Color = %s, Material = %s, T = %s, Collide = %s}" % (
            json.dumps(p["name"]), json.dumps(p["shape"]), ", ".join(repr(float(x)) for x in p["size"]),
            ", ".join(repr(float(x)) for x in p["cf"]), json.dumps(p["color"]), json.dumps(p["material"]),
            repr(float(p["transparency"])), "true" if p["collide"] else "false"))
    pivots = ", ".join("Pivot_%s = Vector3.new(%s)" % (k, ", ".join(repr(float(x)) for x in v)) for k, v in info["pivots"].items())
    attrs = ", ".join("%s = %s" % (k, lua_val(v)) for k, v in info["attrs"].items() if k != "Notes")
    out.append("MODELS[%r] = {Attrs = {%s%s%s}, Parts = {\n\t%s,\n}}\n" % (key, pivots, ", " if attrs else "", attrs, ",\n\t".join(parts)))
out.append(open(os.path.join(HERE, "tests.luau"), encoding="utf-8").read())
run = os.path.join(HERE, "run.luau")
open(run, "w", encoding="utf-8").write("".join(out))
print("wrote run.luau")
res = subprocess.run([LUAU, run], capture_output=True, text=True)
sys.stdout.write(res.stdout)
sys.stdout.write(res.stderr)
sys.exit(0 if res.returncode == 0 and "FAIL" not in res.stdout else 1)
