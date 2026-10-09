# Wraps the scripts under test as modules that take their Roblox globals from an env table (DefenceFX harness).
import os
FB = r"C:\Users\shrey\OneDrive\Documents\RobloxGames\new-map-cucumber-game\fun-builds"
MODS = {
    "kit": os.path.join(FB, "src", "FunBuildKit.lua"),
    "client": os.path.join(FB, "src", "DefenceFXClient.client.lua"),
    "server": os.path.join(FB, "patched", "DefenceService.server.lua"),
    "server_live": os.path.join(FB, "live", "DefenceService.server.lua"),
}
NAMES = ["game", "workspace", "Instance", "Vector3", "CFrame", "Color3", "Vector2", "NumberRange", "NumberSequence",
         "NumberSequenceKeypoint", "ColorSequence", "Enum", "typeof", "task", "require", "warn", "print", "os", "script",
         "RaycastParams", "TweenInfo"]
HERE = os.path.dirname(os.path.abspath(__file__))
for name, path in MODS.items():
    src = open(path, encoding="utf-8").read()
    head = "--!nocheck\nreturn function(env)\n\tlocal " + ", ".join(NAMES) + " = " + ", ".join("env." + n for n in NAMES) + "\n"
    open(os.path.join(HERE, "mod_" + name + ".luau"), "w", encoding="utf-8").write(head + src + "\nend\n")
print("ok")
