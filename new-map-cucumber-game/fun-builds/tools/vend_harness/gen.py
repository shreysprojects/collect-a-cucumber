import os
FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds\src"
MODS = {
    "FunBuildKit": os.path.join(FB, "FunBuildKit.lua"),
    "FunAssets": os.path.join(FB, "FunAssets.lua"),
    "VendServer": os.path.join(FB, "behaviours", "server", "VendingMachine.lua"),
    "VendClient": os.path.join(FB, "behaviours", "client", "VendingMachine.lua"),
}
NAMES = ["game", "workspace", "Instance", "Vector3", "CFrame", "Color3", "Vector2", "NumberRange", "NumberSequence",
         "NumberSequenceKeypoint", "ColorSequence", "Enum", "typeof", "task", "require", "warn"]
HERE = os.path.dirname(os.path.abspath(__file__))
for name, path in MODS.items():
    src = open(path, encoding="utf-8").read()
    head = "--!nocheck\nreturn function(env)\n\tlocal " + ", ".join(NAMES) + " = " + ", ".join("env." + n for n in NAMES) + "\n"
    open(os.path.join(HERE, "mod_" + name + ".luau"), "w", encoding="utf-8").write(head + src + "\nend\n")
print("ok")
