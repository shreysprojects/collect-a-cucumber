import os, json, re
SRC = r"C:\Users\shrey\RAS\src"
def ck(b):
    h = 0
    for x in b: h = (h*31 + x) % 2147483647
    return h
scripts = []   # (instancePath, className, len, ck)
dirs = {}      # instancePath -> {"ignore": bool, "children": set()}
def inst_path(rel_parts):
    # src/StarterPlayer/StarterPlayerScripts/... -> StarterPlayer.StarterPlayerScripts...
    return ".".join(rel_parts)
def script_class(fname):
    if fname.endswith(".server.luau"): return "Script", fname[:-len(".server.luau")]
    if fname.endswith(".client.luau"): return "LocalScript", fname[:-len(".client.luau")]
    if fname.endswith(".luau"): return "ModuleScript", fname[:-len(".luau")]
    return None, None
for root, dnames, fnames in os.walk(SRC):
    rel = os.path.relpath(root, SRC)
    parts = [] if rel == "." else rel.split(os.sep)
    if not parts:  # src root: its dirs are the services
        continue
    ipath = inst_path(parts)
    meta = {}
    if "init.meta.json" in fnames:
        meta = json.load(open(os.path.join(root, "init.meta.json")))
    children = set()
    for d in dnames: children.add(d)
    for f in fnames:
        if f.startswith("init.") and f.endswith(".luau"):
            cls, _ = script_class(f)
            b = open(os.path.join(root, f), "rb").read().replace(b"\r\n", b"\n")
            scripts.append((ipath, cls, len(b), ck(b)))
            continue
        if f.endswith(".meta.json"): continue
        cls, name = script_class(f)
        if cls:
            children.add(name)
            b = open(os.path.join(root, f), "rb").read().replace(b"\r\n", b"\n")
            scripts.append((ipath + "." + name, cls, len(b), ck(b)))
        elif f.endswith(".model.json"):
            children.add(f[:-len(".model.json")])
        elif f.endswith(".rbxm") or f.endswith(".rbxmx"):
            children.add(re.sub(r"\.rbxmx?$", "", f))
        else:
            children.add(f)
    dirs[ipath] = {"ignore": bool(meta.get("ignoreUnknownInstances", False)), "children": sorted(children)}
# services carry $ignoreUnknownInstances true in the project file
for svc in ["ReplicatedFirst", "ReplicatedStorage", "ServerStorage", "ServerScriptService", "StarterPlayer", "StarterPlayer.StarterPlayerScripts"]:
    if svc in dirs: dirs[svc]["ignore"] = True
lines = ["local SCRIPTS = {"]
for p, c, n, h in sorted(scripts):
    lines.append('\t{"%s","%s",%d,%d},' % (p, c, n, h))
lines.append("}")
lines.append("local DIRS = {")
for p in sorted(dirs):
    d = dirs[p]
    lines.append('\t["%s"] = {ignore=%s, children={%s}},' % (p, "true" if d["ignore"] else "false", ",".join('"%s"' % c for c in d["children"])))
lines.append("}")
open("manifest.lua", "w", newline="\n").write("\n".join(lines) + "\n")
print(len(scripts), "scripts;", len(dirs), "dirs;", os.path.getsize("manifest.lua"), "bytes")
