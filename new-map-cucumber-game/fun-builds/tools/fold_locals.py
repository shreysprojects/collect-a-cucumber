"""fold_locals.py -- move chosen top-level constants of a Luau module into one table (Studio's compiler allows at most
200 locals per function; a module's top level counts). fun-builds, 2026-09-24.

    py fold_locals.py <file.lua> <TableName> NAME1 NAME2 ...

* every `local A, B = x, y` declaration whose names are ALL in the list becomes `T.A, T.B = x, y`
  (a mixed line is refused - fix it by hand first)
* `local T = {}` is inserted just before the first such declaration
* every other use `NAME` (not after `.` / `:` / a word char) becomes `T.NAME`, outside string literals and comments
Writes the file in place (a .bak copy next to it) and prints what changed.
"""
import re
import shutil
import sys

path, table, names = sys.argv[1], sys.argv[2], sys.argv[3:]
nameset = set(names)
src = open(path, encoding="utf-8").read()
crlf = "\r\n" in src
lines = src.replace("\r\n", "\n").split("\n")

decl_re = re.compile(r"^local ([\w, ]+?)\s*=(.*)$")
first_decl = None
out = []
changed_decl = 0


def rename_code(segment):
    """rename the names in a piece of CODE (no strings / comments inside)"""
    def sub(m):
        return table + "." + m.group(0)
    pattern = r"(?<![\.\w:])(" + "|".join(re.escape(n) for n in sorted(nameset, key=len, reverse=True)) + r")\b"
    return re.sub(pattern, lambda m: table + "." + m.group(1), segment)


def rename_line(line):
    """rename outside string literals and -- comments (single-line strings only; this module has no long strings
    on lines that use these names)"""
    res, i, n = [], 0, len(line)
    code_start = 0
    while i < n:
        ch = line[i]
        if ch == "-" and line[i:i + 2] == "--":
            res.append(rename_code(line[code_start:i]))
            res.append(line[i:])
            return "".join(res)
        if ch in ("'", '"'):
            res.append(rename_code(line[code_start:i]))
            j = i + 1
            while j < n and line[j] != ch:
                j += 2 if line[j] == "\\" else 1
            res.append(line[i:j + 1])
            i = j + 1
            code_start = i
            continue
        i += 1
    res.append(rename_code(line[code_start:]))
    return "".join(res)


in_block = False  # inside a --[[ ... ]] / --[==[ ... ]==] comment or a [[ ... ]] long string: leave it alone
block_end = None
for idx, line in enumerate(lines):
    if in_block:
        out.append(line)
        if block_end in line:
            in_block = False
        continue
    opener = re.search(r"(--)?\[(=*)\[", line)
    if opener and (opener.group(1) or line.strip().startswith("[[")):
        close = "]" + opener.group(2) + "]"
        if close not in line[opener.end():]:
            in_block, block_end = True, close
            out.append(line)
            continue
    m = decl_re.match(line)
    if m:
        declared = [x.strip() for x in m.group(1).split(",")]
        hit = [x for x in declared if x in nameset]
        if hit:
            if len(hit) != len(declared):
                sys.exit("mixed declaration on line %d: %s" % (idx + 1, line))
            if first_decl is None:
                first_decl = len(out)
            out.append(", ".join(table + "." + x for x in declared) + " =" + rename_line(m.group(2)))
            changed_decl += 1
            continue
    out.append(rename_line(line))

if first_decl is None:
    sys.exit("no declaration found for the given names")
out.insert(first_decl, "local %s = {} -- 2026-09-24: look / layout constants folded into one table (Studio allows 200 top-level locals)" % table)
shutil.copyfile(path, path + ".bak")
text = "\n".join(out)
if crlf:
    text = text.replace("\n", "\r\n")
open(path, "w", encoding="utf-8", newline="").write(text)
print("declarations folded:", changed_decl, "names:", len(nameset))
