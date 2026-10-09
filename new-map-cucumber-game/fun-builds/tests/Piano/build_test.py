"""Assemble run_test.luau for the Piano package: inlined sources + the built model (out/Piano.parts.json) +
the shared mock runtime (tests/DJBooth/mock.luau, read-only) + the scenario (test.luau). Then:
    luau.exe tests/Piano/run_test.luau
"""
import json
import os

FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
HERE = os.path.dirname(os.path.abspath(__file__))

SRC = {
    "Kit": r"src\FunBuildKit.lua",
    "FunAssets": r"src\FunAssets.lua",
    "Service": r"src\FunBuildService.server.lua",
    "Client": r"src\FunBuildClient.client.lua",
    "PianoServer": r"src\behaviours\server\Piano.lua",
    "PianoClient": r"src\behaviours\client\Piano.lua",
}


def longstr(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def piano_dump():
    with open(os.path.join(FB, "models", "out", "Piano.parts.json"), encoding="utf-8") as f:
        info = json.load(f)
    pivots = ", ".join('Pivot_%s = {%s}' % (k, ", ".join(repr(float(c)) for c in v)) for k, v in info["pivots"].items())
    parts = ",\n\t".join('{name = "%s", pos = {%s, %s, %s}, size = {%s, %s, %s}}' % (
        p["name"], p["cf"][0], p["cf"][1], p["cf"][2], p["size"][0], p["size"][1], p["size"][2]) for p in info["parts"])
    return "{attrs = {%s, Cost = %s}, min = {%s}, max = {%s}, parts = {\n\t%s}}" % (
        pivots, info["attrs"].get("Cost", 0), ", ".join(map(str, info["min"])), ", ".join(map(str, info["max"])), parts)


out = ["local SRC = {"]
for k, rel in SRC.items():
    with open(os.path.join(FB, rel), encoding="utf-8") as f:
        out.append("\t%s = %s," % (k, longstr(f.read())))
out.append("}")
out.append("local DUMP = {Piano = %s}" % piano_dump())
with open(os.path.join(FB, "tests", "DJBooth", "mock.luau"), encoding="utf-8") as f:
    out.append("local M = (function()\n" + f.read() + "\nend)()")
with open(os.path.join(HERE, "test.luau"), encoding="utf-8") as f:
    out.append(f.read())
with open(os.path.join(HERE, "run_test.luau"), "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print("wrote", os.path.join(HERE, "run_test.luau"))
