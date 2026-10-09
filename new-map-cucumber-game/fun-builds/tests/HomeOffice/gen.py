"""HomeOffice headless tests (GrandfatherClock + GamingDesk), 2026-09-24.

Each test file runs in its own Luau process: run_<name>.luau = mock.luau + the module sources + both models'
parts.json (as Lua tables) + the test file.
    tests.luau        the GrandfatherClock
    gamingdesk.luau   the playable CUKE RUN (mock network, the gamer's GUI driven by a bot, spectators, the desk)
Every "GUIDUMP <name> <json>" line a test prints becomes a PNG in tests/HomeOffice/screens/: the monitor's three
screens side by side (desk_*, x3) or the gamer's CukeRun panel (gui_*, x1).

    py gen.py          (exit code 1 on any FAIL)
"""
import os
import json
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FB = os.path.dirname(os.path.dirname(HERE))
LUAU = r"C:\Users\shrey\.rokit\tool-storage\luau-lang\luau\0.739.0\luau.exe"
SOURCES = {
    "FunBuildKit": os.path.join(FB, "src", "FunBuildKit.lua"),
    "FunAssets": os.path.join(FB, "src", "FunAssets.lua"),
    "C_GamingDesk": os.path.join(FB, "src", "behaviours", "client", "GamingDesk.lua"),
    "S_GamingDesk": os.path.join(FB, "src", "behaviours", "server", "GamingDesk.lua"),
    "C_GrandfatherClock": os.path.join(FB, "src", "behaviours", "client", "GrandfatherClock.lua"),
}
MODELS = ["GamingDesk", "GrandfatherClock"]
TESTS = ["tests.luau", "gamingdesk.luau"]


def lua_long(s):
    eq = "=" * 6
    assert ("]" + eq + "]") not in s
    return "[" + eq + "[\n" + s + "]" + eq + "]"


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(float(v))
    if isinstance(v, str):
        return lua_long(v) if "\n" in v else json.dumps(v)
    raise TypeError(v)


def v3(v):
    return "Vector3.new(%s)" % ", ".join(repr(float(x)) for x in v)


def prelude():
    out = [open(os.path.join(HERE, "mock.luau"), encoding="utf-8").read(), "\nSOURCES = {}\n"]
    for name, path in SOURCES.items():
        out.append("SOURCES[%r] = %s\n" % (name, lua_long(open(path, encoding="utf-8").read())))
    out.append("MODELS = {}\n")
    for key in MODELS:
        info = json.load(open(os.path.join(FB, "models", "out", key + ".parts.json"), encoding="utf-8"))
        parts = []
        for p in info["parts"]:
            parts.append("{Name = %s, Shape = %s, Size = %s, CF = {%s}, Color = %s, Material = %s, T = %s, Collide = %s}" % (
                json.dumps(p["name"]), json.dumps(p["shape"]), v3(p["size"]),
                ", ".join(repr(float(x)) for x in p["cf"]), json.dumps(p["color"]), json.dumps(p["material"]),
                repr(float(p["transparency"])), "true" if p["collide"] else "false"))
        pivots = ", ".join("Pivot_%s = %s" % (k, v3(v)) for k, v in info["pivots"].items())
        attrs = ", ".join("%s = %s" % (k, lua_val(v)) for k, v in info["attrs"].items() if k != "Notes")
        out.append("MODELS[%r] = {Min = %s, Max = %s, Attrs = {%s%s%s}, Parts = {\n\t%s,\n}}\n" % (
            key, v3(info["min"]), v3(info["max"]), pivots, ", " if attrs else "", attrs, ",\n\t".join(parts)))
    return "".join(out)


# ------------------------------------------------------------------------ render the dumps
def render(name, panels, scale):
    from PIL import Image, ImageDraw, ImageFont
    gap = 6
    width = sum(p["w"] for p in panels) + gap * (len(panels) - 1)
    height = max(p["h"] for p in panels)
    img = Image.new("RGB", (int(width), int(height)), (10, 10, 12))
    x0 = 0

    def font_of(sz):
        try:
            return ImageFont.truetype("arialbd.ttf", sz)
        except OSError:
            return ImageFont.load_default()

    for p in panels:
        canvas = Image.new("RGBA", (int(p["w"]), int(p["h"])), (0, 0, 0, 255))
        d = ImageDraw.Draw(canvas)
        for it in p["items"]:
            x, y, w, h = it["x"], it["y"], it["w"], it["h"]
            if w <= 0 or h <= 0:
                continue
            if it.get("text") is not None:
                if it["text"] == "":
                    continue
                lines = it["text"].split("\n")
                size = max(6, int(min(it.get("ts") or h * 0.9, h / len(lines) * 0.95)))
                font = font_of(size)
                tw = max(d.textlength(l, font=font) for l in lines)
                while tw > w and size > 6:
                    size -= 1
                    font = font_of(size)
                    tw = max(d.textlength(l, font=font) for l in lines)
                align = it.get("align", "Center")
                col = tuple(int(c * 255) for c in it["tc"]) + (int(255 * (1 - it.get("tt", 0))),)
                lh = size * 1.15
                ty = y + (h - lh * len(lines)) / 2
                for l in lines:
                    lw = d.textlength(l, font=font)
                    tx = x if align == "Left" else (x + w - lw if align == "Right" else x + (w - lw) / 2)
                    d.text((tx + 1, ty + 1), l, font=font, fill=(0, 0, 0, col[3]))
                    d.text((tx, ty), l, font=font, fill=col)
                    ty += lh
                continue
            r = it.get("r", 0)
            box = [x, y, x + w - 1, y + h - 1]
            if it.get("c") is not None:
                col = tuple(int(c * 255) for c in it["c"]) + (int(255 * (1 - it.get("bt", 0))),)
                layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
                ld = ImageDraw.Draw(layer)
                if r > 0:
                    ld.rounded_rectangle(box, radius=min(r, w / 2, h / 2), fill=col)
                else:
                    ld.rectangle(box, fill=col)
                canvas = Image.alpha_composite(canvas, layer)
                d = ImageDraw.Draw(canvas)
            if it.get("sc") is not None:
                scol = tuple(int(c * 255) for c in it["sc"]) + (255,)
                if r > 0:
                    d.rounded_rectangle(box, radius=min(r, w / 2, h / 2), outline=scol, width=max(1, int(it.get("st", 1))))
                else:
                    d.rectangle(box, outline=scol, width=max(1, int(it.get("st", 1))))
        img.paste(canvas.convert("RGB"), (int(x0), 0))
        x0 += p["w"] + gap
    img = img.resize((int(img.width * scale), int(img.height * scale)), Image.NEAREST)
    os.makedirs(os.path.join(HERE, "screens"), exist_ok=True)
    path = os.path.join(HERE, "screens", name + ".png")
    img.save(path)
    print("SCREEN " + path)


failed = False
head = prelude()
for test in TESTS:
    stem = os.path.splitext(test)[0]
    run = os.path.join(HERE, "run.luau" if stem == "tests" else "run_%s.luau" % stem)
    open(run, "w", encoding="utf-8").write(head + open(os.path.join(HERE, test), encoding="utf-8").read())
    print("== %s (%s)" % (test, os.path.basename(run)))
    res = subprocess.run([LUAU, run], capture_output=True, text=True)
    dumps = []
    for line in res.stdout.splitlines():
        if line.startswith("GUIDUMP "):
            _, name, payload = line.split(" ", 2)
            dumps.append((name, json.loads(payload)))
        else:
            print(line)
    sys.stdout.write(res.stderr)
    if res.returncode != 0 or "FAIL" in res.stdout:
        failed = True
    for name, panels in dumps:
        try:
            render(name, panels, 1 if name.startswith("gui") else 3)
        except Exception as e:  # noqa
            print("RENDER FAIL %s: %s" % (name, e))
            failed = True
print("ALL PASSED" if not failed else "FAIL")
sys.exit(1 if failed else 0)
