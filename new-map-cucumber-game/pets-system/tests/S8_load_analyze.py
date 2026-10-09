# S8 (2026-09-22): summarise the S8 load run next to the S0b baseline (same fields as
# S0_baseline_summary.json). Usage: python S8_load_analyze.py <scenario> ; scenario = solo | mp2
# Reads tests/S8_<scenario>_* files and S0_baseline_*; prints JSON (the report copies it into S8_load.md).
import json, statistics, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from S8_profile_summary import summary as script_summary

def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)

def stats(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return {"n": len(vals), "mean": round(statistics.mean(vals), 3), "median": round(statistics.median(vals), 3),
            "min": round(min(vals), 3), "max": round(max(vals), 3)}

def window(rows, a, b):
    return [r for r in rows if a <= r["t"] <= b]

def server_block(rows):
    return {
        "samples": len(rows),
        "DataSendKbps": stats([r["send"] for r in rows]),
        "Heartbeats_per_s": stats([r["fps"] for r in rows]),
        "MaxHeartbeatMs": stats([r["hbMaxMs"] for r in rows]),
        "HeartbeatTimeMs": stats([r["hbms"] for r in rows]),
        "PhysicsStepTimeMs": stats([r["phys"] for r in rows]),
        "InstanceCount": stats([r["inst"] for r in rows]),
        "LuaHeapMb": stats([r.get("luaHeapMb") for r in rows]),
        "gcKb": stats([r.get("gcKb") for r in rows]),
        "TotalMemoryMb": stats([r["mem"] for r in rows]),
        "ZombiesAlive_max": max([r["alive"] for r in rows] or [0]),
        "PlotPets": stats([r.get("plotPets") for r in rows]),
    }

def micro(p):
    d = load(p)
    fs = d["frame_summary"]
    groups = {g["group"]: g for g in d.get("top_groups", [])}
    groups.update({g["group"]: g for g in d.get("top_groups_by_exclusive", [])})
    def gi(name):
        g = groups.get(name)
        return [g["exclusive_us"], g["inclusive_us"]] if g else None
    script = groups.get("Script")
    return {"frames": fs["frames"], "p50_us": fs["p50_us"], "p95_us": fs["p95_us"], "max_us": fs["max_us"],
            "Script_excl_incl_us": gi("Script"), "Physics": gi("Physics"), "Network": gi("Network"),
            "Script_incl_per_frame_us": round(script["inclusive_us"] / fs["frames"]) if script else None,
            "event_limit_hit": d["counts"].get("event_limit_hit")}

def client_block(c, a=None, b=None):
    cols = c["Cols"]
    rows = [dict(zip(cols, r)) for r in c["Rows"]]
    if a is not None:
        rows = [r for r in rows if a <= r["t"] <= b]
    ev = {k: {"Count": v["Count"], "PerSecond": round(v["Count"] / c["WindowSeconds"], 3),
              "JsonBytesPerSecond": round(v["JsonBytes"] / c["WindowSeconds"], 1)} for k, v in c["Events"].items()}
    return {
        "WindowSeconds": round(c["WindowSeconds"], 1),
        "RemoteEventsReceived_per_s": round(c["PerSecond"], 3),
        "JsonBytes_per_s": round(sum(v["JsonBytes"] for v in c["Events"].values()) / c["WindowSeconds"], 1),
        "ByRemote": dict(sorted(ev.items(), key=lambda kv: -kv[1]["Count"])),
        "Heartbeats_per_s": stats([r["fps"] for r in rows]),
        "MaxHeartbeatMs": stats([r["hbMaxMs"] for r in rows]),
        "DataSendKbps": stats([r["send"] for r in rows]),
        "TotalMemoryMb": stats([r["mem"] for r in rows]),
        "LuaHeapMb": stats([r["luaHeapMb"] for r in rows]),
        "InstanceCount": stats([r["inst"] for r in rows]),
        "PetFxLocalDescendants": stats([r["fxParts"] for r in rows]),
        "PlayerGuiDescendants": stats([r["guiDesc"] for r in rows]),
        "PetCards": stats([r["petCards"] for r in rows if r["petCards"] >= 0]),
        "PetIncomePopups": stats([r["petPopups"] for r in rows if r["petPopups"] >= 0]),
        "CucumberIncomePopups": stats([r["incomePopups"] for r in rows if r["incomePopups"] >= 0]),
    }

if __name__ == "__main__":
    scen = sys.argv[1] if len(sys.argv) > 1 else "solo"
    here = os.path.dirname(os.path.abspath(__file__))
    os.chdir(here)
    out = {"scenario": scen}
    srv = load(f"S8_{scen}_server_sampler_raw.json")
    rows = srv["Rows"]
    raid_a = srv.get("RaidFiredSamplerT", 0)
    raid_b = float(sys.argv[2]) if len(sys.argv) > 2 else raid_a + 20
    out["ServerSampler"] = {
        "raid_window_t": [raid_a, raid_b],
        "raid_live": server_block(window(rows, raid_a, raid_b)),
        "after_raid_day_22s": server_block(window(rows, raid_b + 1.5, raid_b + 23.5)),
        "whole_run": server_block(rows),
        "ServerEvents_client_to_server": srv.get("ServerEvents"),
    }
    # pet-system diagnostics at the first and last diag rows
    diags = [r for r in rows if "diag" in r]
    if diags:
        out["PetDiag_first_last"] = {"first_t": diags[0]["t"], "first": diags[0]["diag"], "last_t": diags[-1]["t"], "last": diags[-1]["diag"]}
    for peer in ("server", "client1"):
        p = f"S8_{scen}_raid_micro_profiler_{peer}.json"
        if os.path.exists(p):
            out[f"micro_{peer}"] = micro(p)
    for name in (f"S8_{scen}_raid_script_profiler_server.json", f"S8_{scen}_day_script_profiler_server.json", f"S8_{scen}_day_script_profiler_client1.json"):
        if os.path.exists(name):
            out[name] = script_summary(name)
    for c in sorted(f for f in os.listdir(".") if f.startswith(f"S8_{scen}_client") and f.endswith("_raw.json")):
        out[c] = client_block(load(c))
    print(json.dumps(out, indent=1))
