#!/usr/bin/env python3
"""Make a porting worksheet for a patch that does not apply to its target tree.

For every hunk of PATCH that does not apply to SRC (judged the same way `patch -p1 -F3`
does: the hunk's context must be findable, with up to three lines of it missing), write
the hunk and the region of the target file it should land in, side by side, into OUT.

usage: worksheet.py SRC PATCH OUT
"""
import re
import sys
from pathlib import Path

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def parse_patch(path):
    """[(file, [(lineno_in_patch, header, [lines])])]"""
    out, cur_file, cur = [], None, None
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("diff --git "):
            cur_file = line.split(" b/", 1)[-1]
            cur = []
            out.append((cur_file, cur))
        elif line.startswith("+++ ") or line.startswith("--- ") or line.startswith("index "):
            continue
        elif HUNK.match(line):
            cur.append([line, []])
        elif cur and cur[-1][1] is not None and line[:1] in (" ", "-", "+", "\\"):
            cur[-1][1].append(line)
    return out


def old_text(lines):
    return [l[1:] for l in lines if l[:1] in (" ", "-")]


def applies(lines, target_lines):
    """Does this hunk's old text occur in target_lines, allowing up to 3 missing context lines?"""
    old = old_text(lines)
    while old and old[0].startswith(""):
        break
    # try full, then progressively drop leading/trailing context lines (fuzz)
    for fuzz in range(0, 4):
        body = old[fuzz:len(old) - fuzz] if fuzz else old
        if not body:
            return True
        for i in range(0, len(target_lines) - len(body) + 1):
            if target_lines[i:i + len(body)] == body:
                return True
    return False


def main(src, patch, out):
    src = Path(src)
    chunks = parse_patch(patch)
    report = ["# Porting worksheet", "",
              "Hunks of `%s` that do not apply to `%s` even with three lines of fuzz."
              % (Path(patch).name, src.name), ""]
    total = bad = 0
    for name, hunks in chunks:
        target = src / name
        if not target.is_file():
            report += ["## %s — **file missing in the target tree**" % name, ""]
            bad += 1
            continue
        target_lines = target.read_text(encoding="utf-8", errors="replace").splitlines()
        for header, lines in hunks:
            total += 1
            if applies(lines, target_lines):
                continue
            bad += 1
            m = HUNK.match(header)
            at = int(m.group(1)) if m else 1
            lo, hi = max(0, at - 12), min(len(target_lines), at + 20)
            report += ["## %s" % name, "", "```diff", header]
            report += lines
            report += ["```", "", "target %s around line %d:" % (name, at), "", "```"]
            report += ["%5d| %s" % (i + 1, target_lines[i]) for i in range(lo, hi)]
            report += ["```", ""]
    report.insert(3, "**%d of %d hunks do not apply.**" % (bad, total))
    Path(out).write_text("\n".join(report) + "\n", encoding="utf-8", newline="\n")
    print("%s: %d of %d hunks do not apply" % (out, bad, total))


if __name__ == "__main__":
    main(*sys.argv[1:4])
