"""Trace which #include chain pulls a given header into a translation unit.

usage: inctrace.py <tree> <source.c> <target-substring> [include-dir ...]

Approximates the XNU kernel include search order: -I dirs are searched in the order given,
and a quoted include also searches the directory of the including file first.
"""
import os
import sys

tree = sys.argv[1]
src = sys.argv[2]
target = sys.argv[3]
incdirs = sys.argv[4:] or ['osfmk', 'bsd', 'libkern', 'osfmk/libsa', 'EXTERNAL_HEADERS']


def resolve(name, curdir, quoted):
    cands = []
    if quoted:
        cands.append(os.path.join(tree, curdir, name))
    cands += [os.path.join(tree, d, name) for d in incdirs]
    for c in cands:
        c = os.path.normpath(c)
        if os.path.isfile(c):
            return c
    return None


def includes(path):
    out = []
    try:
        with open(path, encoding='utf-8', errors='ignore') as f:
            for line in f:
                s = line.lstrip()
                if s.startswith('#include') or s.startswith('#import'):
                    rest = s[8:].strip()
                    if rest[:1] in '<"':
                        q = rest[0] == '"'
                        end = rest.find('>' if rest[0] == '<' else '"')
                        if end > 0:
                            out.append((rest[1:end], q))
    except OSError:
        pass
    return out


start = os.path.join(tree, src)
queue = [(start, [start])]
seen = {start}
while queue:
    path, chain = queue.pop(0)
    if target in os.path.relpath(path, tree).replace(os.sep, '/'):
        print(' -> '.join(os.path.relpath(p, tree).replace(os.sep, '/') for p in chain))
        break
    curdir = os.path.dirname(os.path.relpath(path, tree))
    for inc, q in includes(path):
        nxt = resolve(inc, curdir, q)
        if nxt and nxt not in seen:
            seen.add(nxt)
            queue.append((nxt, chain + [nxt]))
else:
    print('not reachable: %s (visited %d files)' % (target, len(seen)))
