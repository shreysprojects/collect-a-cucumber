"""Merge guardians/manifest.json + guardians/fbx/asset-ids.json into install-payload.json,
the single file the Studio-side installer reads.

    py make_install.py

The payload is deliberately flat and pre-converted: every pivot is already in ROBLOX
space, so install.lua never has to know the Blender convention.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "manifest.json")
IDS = os.path.join(HERE, "fbx", "asset-ids.json")
OUT = os.path.join(HERE, "install-payload.json")


def rbx(p):
    """Blender (bx, by, bz) -> Roblox (bx, bz, -by).

    The FBX importer lands a Blender point at (-bx, bz, by); install.lua then yaws the
    whole model 180 degrees about Y, which flips x and z and gives the mapping above.
    After that the authored +Y front faces Roblox -Z, which is the model's LookVector."""
    return [round(p[0], 4), round(p[2], 4), round(-p[1], 4)]


def main():
    man = json.load(open(MANIFEST, encoding="utf-8"))
    ids = {k: str(v) for k, v in json.load(open(IDS, encoding="utf-8-sig")).items()}

    models = {}
    for name, m in man["models"].items():
        rig = {}
        for part, d in m["rig"].items():
            rig[part] = {
                "object": d["object"],          # the name the FBX arrives with
                "parent": d["parent"],
                "pivot": rbx(d["pivot"]),
                "role": d["role"],
                "hex": d["hex"],
                "material": d["material"],
                "transparency": d["transparency"],
                "sleep_hex": d.get("sleep_hex", ""),
                "sleep_material": d.get("sleep_material", ""),
                "moving": d.get("moving", True),
            }
        seats = {}
        for sname, s in m.get("seats", {}).items():
            srig = {}
            for part, d in s["rig"].items():
                srig[part] = {
                    "object": d["object"], "parent": d["parent"], "pivot": rbx(d["pivot"]),
                    "role": d["role"], "hex": d["hex"], "material": d["material"],
                    "transparency": d["transparency"],
                }
            seats[sname] = {"asset": ids.get(sname, ""), "rig": srig,
                            "parts": s["report"]["parts"]}
        models[name] = {
            "asset": ids.get(name, ""),
            "biome": m["biome"],
            "spec": m["spec"],
            "notes": m["notes"],
            "parts": m["report"]["parts"],
            "tris": m["report"]["tris"],
            "size": m["report"]["size_studs"],
            "rig": rig,
            "seats": seats,
            "poses": m.get("poses", {}),
            "pose_loc": m.get("pose_loc", {}),
        }

    missing = [n for n, m in models.items() if not m["asset"]]
    data = {"models": models, "roles": man["roles"], "sleep_look": man["sleep_look"],
            "space": man.get("space", {}), "missing_assets": missing}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    print("wrote %s (%d models, %d bytes)" % (OUT, len(models), os.path.getsize(OUT)))
    if missing:
        print("WARNING no asset id for:", ", ".join(missing))
    for n, m in sorted(models.items()):
        print("  %-10s asset %-16s %2d parts  seats %s"
              % (n, m["asset"], m["parts"], ", ".join(m["seats"])))


if __name__ == "__main__":
    main()
