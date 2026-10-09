"""Assemble run_test.luau: inlined sources + parsed prop dumps + mock runtime + scenario."""
import os, re, sys

FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
HERE = os.path.dirname(os.path.abspath(__file__))

SRC = {
    "Kit": r"src\FunBuildKit.lua",
    "FunAssets": r"src\FunAssets.lua",
    "Service": r"src\FunBuildService.server.lua",
    "Client": r"src\FunBuildClient.client.lua",
    "DJServer": r"src\behaviours\server\DJBooth.lua",
    "DJClient": r"src\behaviours\client\DJBooth.lua",
    "Floor": r"src\behaviours\client\DanceFloor.lua",
}


def longstr(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


VEC = re.compile(r"^\s*@(\w+) = \(([-\d.]+), ([-\d.]+), ([-\d.]+)\)\s*$")
NUM = re.compile(r"^\s*@(State_\w+|Cost) = ([-\d.]+)\s*$")
PART = re.compile(r"^\s*(\S+) \[(\w+)\] pos \(([-\d.]+), ([-\d.]+), ([-\d.]+)\) size \(([-\d.]+), ([-\d.]+), ([-\d.]+)\) (\w+) ([0-9a-fA-F]{6}) T([\d.]+)")


def dump(name):
    attrs, parts = [], []
    with open(os.path.join(FB, "props-dump", name + ".txt"), encoding="utf-8") as f:
        for line in f:
            m = VEC.match(line)
            if m and m.group(1).startswith("Pivot_"):
                attrs.append('%s = {%s, %s, %s}' % m.groups())
                continue
            m = NUM.match(line)
            if m:
                attrs.append('%s = %s' % m.groups())
                continue
            m = PART.match(line)
            if m:
                g = m.groups()
                parts.append('{name = "%s", pos = {%s, %s, %s}, size = {%s, %s, %s}, mat = "%s", color = "%s", t = %s}'
                             % (g[0], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9], g[10]))
    return "{attrs = {%s}, parts = {\n\t%s}}" % (", ".join(attrs), ",\n\t".join(parts))


out = ["local SRC = {"]
for k, rel in SRC.items():
    with open(os.path.join(FB, rel), encoding="utf-8") as f:
        out.append("\t%s = %s," % (k, longstr(f.read())))
out.append("}")
out.append("local DUMP = {DJBooth = %s, DanceFloor = %s}" % (dump("DJBooth"), dump("DanceFloor")))
with open(os.path.join(HERE, "mock.luau"), encoding="utf-8") as f:
    out.append("local M = (function()\n" + f.read() + "\nend)()")
with open(os.path.join(HERE, "test.luau"), encoding="utf-8") as f:
    out.append(f.read())
with open(os.path.join(HERE, "run_test.luau"), "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print("built", os.path.join(HERE, "run_test.luau"))
