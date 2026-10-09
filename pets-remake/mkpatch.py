"""Turn local script edits into SURGICAL find/replace patches for pets-remake/apply_patches.lua
(2026-09-18). Use it when another session may be editing the same Studio scripts: instead of
pushing whole sources (which silently reverts their work), each changed hunk is sent as
{old, new} with 2 lines of context and applied to whatever the LIVE Source is at push time.

    py mkpatch.py <orig_dir> <patched_dir> <out.json> Name.lua=game.Path.To.Script ...

orig_dir holds the sources as pulled from Studio (receive.ps1 mirrors, LF), patched_dir the
edited copies. Every `old` must be unique in the original or the script stops.
"""
import difflib, json, os, sys


def main():
    orig_dir, patched_dir, out = sys.argv[1:4]
    entries = []
    for spec in sys.argv[4:]:
        name, path = spec.split("=", 1)
        a = open(os.path.join(orig_dir, name), encoding="utf-8").read().replace("\r\n", "\n")
        b = open(os.path.join(patched_dir, name), encoding="utf-8").read().replace("\r\n", "\n")
        al, bl = a.split("\n"), b.split("\n")
        edits = []
        for group in difflib.SequenceMatcher(None, al, bl, autojunk=False).get_grouped_opcodes(2):
            i1, i2, j1, j2 = group[0][1], group[-1][2], group[0][3], group[-1][4]
            old, new = "\n".join(al[i1:i2]), "\n".join(bl[j1:j2])
            if a.count(old) != 1:
                sys.exit("%s: hunk at line %d is not unique - widen the context" % (name, i1 + 1))
            edits.append({"old": old, "new": new})
        entries.append({"path": path, "file": name, "edits": edits})
        print(name, len(edits), "edits")
    json.dump(entries, open(out, "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
