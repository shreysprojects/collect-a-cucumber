"""Merge cucumbers/manifest.json + cucumbers/fbx/asset-ids.json into ONE payload the
Studio-side installer pulls over the loopback server.

    py make_install.py            # writes install-payload.json, prints what is missing

The installer needs, per model: the asset id it was uploaded as, and every part's Roblox
appearance BY PART NAME - because the FBX import loses all colour and material and every
part arrives grey Plastic.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "manifest.json")
ASSET_IDS = os.path.join(HERE, "fbx", "asset-ids.json")
OUT = os.path.join(HERE, "install-payload.json")

# biome -> the x row the model is laid out on in Workspace
BIOME_ORDER = ["grass", "desert", "volcano", "narmek", "samurai", "farm", "snow",
               "underwater"]


def main():
    man = json.load(open(MANIFEST, encoding="utf-8-sig"))
    ids = json.load(open(ASSET_IDS, encoding="utf-8-sig")) if os.path.exists(ASSET_IDS) else {}

    # part appearance, keyed by model then by the part's SHORT name
    by_model = {}
    for row in man["parts"]:
        coll = row["collection"]
        short = row["name"].split(".", 1)[1] if "." in row["name"] else row["name"]
        by_model.setdefault(coll, {})[short] = {
            "hex": row["hex"],
            "material": row["material"],
            "transparency": round(float(row.get("transparency", 0.0)), 4),
        }

    models, missing_id, missing_parts = {}, [], []
    for name, rep in man["models"].items():
        aid = ids.get(name)
        if not aid:
            missing_id.append(name)
            continue
        parts = by_model.get(name)
        if not parts:
            missing_parts.append(name)
            continue
        models[name] = {
            "assetId": int(aid),
            "biome": rep.get("biome", "?"),
            "archetype": rep.get("archetype", "?"),
            "tris": rep.get("tris", 0),
            "size": rep.get("size_studs", [0, 0, 0]),
            "notes": (rep.get("notes", "") or "")[:900],
            "parts": parts,
        }

    payload = {
        "models": models,
        "biomeOrder": BIOME_ORDER,
        "count": len(models),
        "totalTris": sum(m["tris"] for m in models.values()),
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, separators=(",", ":"))

    print("wrote %s  (%d models, %d tris, %.1f KB)"
          % (OUT, len(models), payload["totalTris"], os.path.getsize(OUT) / 1024.0))
    if missing_id:
        print("NO ASSET ID (%d): %s" % (len(missing_id), ", ".join(sorted(missing_id))))
    if missing_parts:
        print("NO PARTS IN MANIFEST (%d): %s" % (len(missing_parts), ", ".join(sorted(missing_parts))))
    orphan = sorted(set(ids) - set(man["models"]))
    if orphan:
        print("asset id with no manifest entry: %s" % ", ".join(orphan))
    return 0 if models else 1


if __name__ == "__main__":
    sys.exit(main())
