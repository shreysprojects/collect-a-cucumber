"""Re-run every launchers/NN/build.py headless, N at a time; print a one-line summary each."""
import concurrent.futures as cf, json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
ids = sys.argv[1].split(",") if len(sys.argv) > 1 and sys.argv[1] else ["%02d" % i for i in range(1, 31)]
workers = int(sys.argv[2]) if len(sys.argv) > 2 else 8
def run(i):
    t = time.time()
    p = subprocess.run([BLENDER, "-b", os.path.join(HERE, "LauncherAnims.blend"), "--python", os.path.join(HERE, "launchers", i, "build.py")],
                       capture_output=True, text=True, errors="replace", timeout=1500)
    rep_path = os.path.join(HERE, "launchers", i, "report.json")
    fresh = os.path.exists(rep_path) and os.path.getmtime(rep_path) > t
    if not fresh:
        tail = [l for l in (p.stdout + p.stderr).splitlines() if "Error" in l or "Traceback" in l or l.strip().startswith("File")][-4:]
        return "%s FAILED %.0fs: %s" % (i, time.time() - t, " | ".join(tail)[:300])
    r = json.load(open(rep_path))
    aud = {k: v for k, v in r.items() if k.endswith("_audit")}
    arm = max((v["arm_in_body"] for v in aud.values()), default=0)
    lau = max((v["launcher_in_body"] for v in aud.values()), default=0)
    flips = sum(len(v["flips"]) for v in aud.values()); snaps = sum(len(v["snaps"]) for v in aud.values())
    return "%s %.0fs P=%d W=%d yaw=%s elev=%s clear=%s arm=%.2f launcher=%.2f flips=%d snaps=%d | %s" % (
        i, time.time() - t, len(r["problems"]), len(r["warnings"]), r.get("fire_yaw_off_track_deg"), r.get("fire_elevation_deg"),
        r.get("ball_body_clearance"), arm, lau, flips, snaps, "; ".join(r["problems"])[:160])
with cf.ThreadPoolExecutor(workers) as ex:
    for line in ex.map(run, ids):
        print(line, flush=True)
