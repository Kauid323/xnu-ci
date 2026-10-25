import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else '/tmp/verify'
srcdir = 'hackios/xnu/files'

hdrs = set()
for dp, dn, fn in os.walk(root):
    for f in fn:
        rel = os.path.relpath(os.path.join(dp, f), root)
        hdrs.add(rel.replace(os.sep, '/'))
basenames = set(h.split('/')[-1] for h in hdrs)

missing = {}
count = 0
for dp, dn, fn in os.walk(srcdir):
    for f in fn:
        p = os.path.join(dp, f)
        try:
            t = open(p, encoding='utf-8', errors='ignore').read()
        except OSError:
            continue
        count += 1
        for m in re.finditer(r'#\s*include\s*[<"]([^>"]+)[>"]', t):
            h = m.group(1)
            if h in hdrs:
                continue
            if h.split('/')[-1] in basenames:
                continue
            missing.setdefault(h, []).append(os.path.relpath(p, srcdir))

for h in sorted(missing):
    users = sorted(set(missing[h]))
    print('%-46s %s' % (h, ', '.join(users[:3])))
print('files scanned: %d, missing headers: %d' % (count, len(missing)))
