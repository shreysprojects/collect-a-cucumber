# S8 (2026-09-22): summarise raw capture_script_profiler JSON files the same way as S0b's
# by_script_us: total = sum of the category root nodes, per script = the root functions that carry
# a Name and no Source (the script-level entries). Usage: python S8_profile_summary.py file.json [...]
import json, sys
def summary(path):
    d = json.load(open(path))
    nodes = d["Nodes"]
    total = sum(nodes[c["NodeId"] - 1]["TotalDuration"] for c in d["Categories"])
    by = {}
    for f in d["Functions"]:
        if "Source" not in f and "Name" in f:
            by[f["Name"]] = by.get(f["Name"], 0) + f["TotalDuration"]
    dur = (d["SessionEndTime"] - d["SessionStartTime"]) / 1000.0
    return {"file": path, "seconds": dur, "total_us": total, "pct_of_one_core": round(total / (dur * 1e6) * 100, 2),
            "by_script_us": dict(sorted(by.items(), key=lambda kv: -kv[1])[:25])}
if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(json.dumps(summary(p)))
