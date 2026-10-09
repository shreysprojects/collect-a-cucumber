"""Assemble run_test.luau for the HomeLaundry package (WashingMachine + Dryer), fun-builds 2026-09-24:
inlined sources (the REAL FunBuildKit / FunAssets / FunBuildService / FunBuildClient + the four laundry modules)
+ the two models from models/out/<Key>.parts.json + the mock runtime + the scenario (test.luau).

    py tests\\HomeLaundry\\build_test.py && luau tests\\HomeLaundry\\run_test.luau
(run.ps1 does both.)
"""
import os
import json

FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
HERE = os.path.dirname(os.path.abspath(__file__))

SRC = {
    "Kit": r"src\FunBuildKit.lua",
    "FunAssets": r"src\FunAssets.lua",
    "Service": r"src\FunBuildService.server.lua",
    "Client": r"src\FunBuildClient.client.lua",
    "WMServer": r"src\behaviours\server\WashingMachine.lua",
    "DryerServer": r"src\behaviours\server\Dryer.lua",
    "WMClient": r"src\behaviours\client\WashingMachine.lua",
    "DryerClient": r"src\behaviours\client\Dryer.lua",
}


def longstr(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


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
    raise TypeError(type(v))


def model(key):
    with open(os.path.join(FB, "models", "out", key + ".parts.json"), encoding="utf-8") as f:
        info = json.load(f)
    return lua({"key": info["key"], "parts": info["parts"], "pivots": info["pivots"], "attrs": info["attrs"],
                "min": info["min"], "max": info["max"]})


out = ["local SRC = {"]
for k, rel in SRC.items():
    with open(os.path.join(FB, rel), encoding="utf-8") as f:
        out.append("\t%s = %s," % (k, longstr(f.read())))
out.append("}")
out.append("local MODELS = {WashingMachine = %s, Dryer = %s}" % (model("WashingMachine"), model("Dryer")))
with open(os.path.join(HERE, "mock.luau"), encoding="utf-8") as f:
    out.append("local M = (function()\n" + f.read() + "\nend)()")
with open(os.path.join(HERE, "test.luau"), encoding="utf-8") as f:
    out.append(f.read())
with open(os.path.join(HERE, "run_test.luau"), "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print("built", os.path.join(HERE, "run_test.luau"))
