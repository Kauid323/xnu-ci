#!/usr/bin/env bash
# hackios's xnu-deps: host tools (mig, unifdef, tcsh...), the two static libraries built against
# the kernel's own headers, and the SDK that Apple's internal one has and the public one lacks.
set -euo pipefail

export THEOS=${THEOS:-$PWD/theos}
export XNU_SRC=$PWD/src
export XNU_SDK_PATH="$THEOS/sdks/${XNU_SDK:-iPhoneOS16.5.sdk}"
export XNU_SDK_VERSION=${XNU_SDK_VERSION:-16.5}

echo "XNU_SRC=$XNU_SRC"
echo "XNU_SDK_PATH=$XNU_SDK_PATH"
test -d "$XNU_SRC"
test -d "$XNU_SDK_PATH"

# glibc has no strlcpy/strlcat (they are BSD). 8020's SETUP/replacecontents uses strlcat, so the
# first host tool the build compiles fails to link. hostcompat.h is force-included into every
# host tool (`HOST_CC=clang -include .../hostcompat.h` in hackios/xnu-build.sh), which is exactly
# where the rest of the glibc gaps are filled in, so the shim goes there.
HC=hackios/xnu-deps/hostinc/hostcompat.h
[ -f "$HC" ] || { echo "!! $HC is missing: the host tools will not link"; exit 1; }
if ! grep -q 'host_strlcat' "$HC"; then
  echo "== adding strlcpy/strlcat to $HC"
  python3 - "$HC" <<'PY'
import sys
p = sys.argv[1]
src = open(p).read()
shim = '''
/* glibc has no strlcpy/strlcat (they are BSD); XNU 8020's SETUP/replacecontents uses strlcat */
static inline size_t host_strlcpy(char *d, const char *s, size_t n) {
	size_t l = strlen(s);
	if (n) { size_t c = l < n - 1 ? l : n - 1; memcpy(d, s, c); d[c] = 0; }
	return l;
}
static inline size_t host_strlcat(char *d, const char *s, size_t n) {
	size_t dl = strnlen(d, n);
	if (dl == n) return n + strlen(s);
	return dl + host_strlcpy(d + dl, s, n - dl);
}
#define strlcpy host_strlcpy
#define strlcat host_strlcat
'''
i = src.rstrip().rfind('#endif')
if i < 0:
    sys.exit('no closing #endif in ' + p)
open(p, 'w').write(src[:i] + shim + '\n' + src[i:])
PY
fi

set +e
JOBS=$(nproc) ./hackios/xnu-deps/setup.sh
rc=$?
set -e
if [ $rc -ne 0 ]; then
  for f in hackios/xnu-deps/exporthdrs.log hackios/xnu-deps/build/pthread/build.log; do
    [ -f "$f" ] || continue
    echo "======== $f (tail)"
    tail -80 "$f"
  done
  echo "======== what the export left behind"
  echo "-- BUILD/obj:"; ls "$XNU_SRC/BUILD/obj" 2>/dev/null | head -20
  echo "-- anything named EXPORT_HDRS:"; find "$XNU_SRC/BUILD" -maxdepth 5 -type d -name 'EXPORT_HDRS' 2>/dev/null | head
  echo "-- its contents:"; find "$XNU_SRC/BUILD" -maxdepth 7 -type d -path '*EXPORT_HDRS*' 2>/dev/null | head -30
  echo "-- exporthdrs.log: $(wc -l < hackios/xnu-deps/exporthdrs.log 2>/dev/null) lines"
  exit $rc
fi
