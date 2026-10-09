"""Kitchen (Fridge / Microwave) offline harness, fun-builds 2026-09-24: wraps the real modules so test.luau can run them
on mocks, and turns models/out/<Key>.parts.json into a Luau table (the real part names, sizes and authored CFrames).
    py gen.py   (run.ps1 does it for you)"""
import os, json

FB = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(FB, "src")
HERE = os.path.dirname(os.path.abspath(__file__))
MODS = {
    "FunBuildKit": os.path.join(SRC, "FunBuildKit.lua"),
    "FunAssets": os.path.join(SRC, "FunAssets.lua"),
    "FridgeServer": os.path.join(SRC, "behaviours", "server", "Fridge.lua"),
    "FridgeClient": os.path.join(SRC, "behaviours", "client", "Fridge.lua"),
    "MicrowaveServer": os.path.join(SRC, "behaviours", "server", "Microwave.lua"),
    "MicrowaveClient": os.path.join(SRC, "behaviours", "client", "Microwave.lua"),
}
NAMES = ["game", "workspace", "Instance", "Vector3", "CFrame", "Color3", "Vector2", "UDim2", "NumberRange", "NumberSequence",
         "NumberSequenceKeypoint", "ColorSequence", "Enum", "typeof", "task", "require", "warn", "os"]
for name, path in MODS.items():
    src = open(path, encoding="utf-8").read()
    head = "--!nocheck\nreturn function(env)\n\tlocal " + ", ".join(NAMES) + " = " + ", ".join("env." + n for n in NAMES) + "\n"
    open(os.path.join(HERE, "mod_" + name + ".luau"), "w", encoding="utf-8").write(head + src + "\nend\n")


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ", ".join("[%s] = %s" % (json.dumps(k), lua(x)) for k, x in v.items()) + "}"
    return "nil"


for key in ("Fridge", "Microwave"):
    info = json.load(open(os.path.join(FB, "models", "out", key + ".parts.json"), encoding="utf-8"))
    attrs = {k: v for k, v in info.get("attrs", {}).items() if k != "Notes"}
    data = {"parts": [{"name": p["name"], "size": p["size"], "cf": p["cf"], "collide": bool(p.get("collide", True))}
                      for p in info["parts"]],
            "pivots": info.get("pivots", {}), "attrs": attrs, "min": info["min"], "max": info["max"]}
    open(os.path.join(HERE, "parts_" + key + ".luau"), "w", encoding="utf-8").write("--!nocheck\nreturn " + lua(data) + "\n")
print("ok")
