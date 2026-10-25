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

# Three things the xnu-deps scripts (written for 8796) and the Linux toolchain do not expect:
#
# 1. osfmk/libsa/string.h gained `#include <san/memintrinsics.h>` under #ifdef PRIVATE, and it is
#    exported as EXPORT_HDRS/osfmk/string.h. Both hand-written compile lines in xnu-deps put
#    osfmk/bsd/libkern/pexpert/iokit/security on the include path but not san, so the first
#    compile against the exported headers dies. Add the one -I.
for f in hackios/xnu-deps/setup.sh hackios/xnu-deps/build/pthread/build.sh; do
  [ -f "$f" ] || { echo "!! $f is missing"; exit 1; }
  sed -i 's|-I\$hdrs/security|-I$hdrs/security -I$hdrs/san|g; s|-I\$E/security|-I$E/security -I$E/san|g' "$f"
  grep -q '\-I\$hdrs/san\|\-I\$E/san' "$f" || { echo "!! could not add -I.../san to $f"; exit 1; }
  echo "== $f: san headers added to the include path"
done

# 2. xnu-clang drops -enable-trivial-auto-var-init-zero-knowing-it-will-be-removed-from-clang,
#    assuming Apple's clang (which enables -ftrivial-auto-var-init=zero without it). Ubuntu's
#    clang 14 refuses -ftrivial-auto-var-init=zero unless that flag is there, so keep it.
XC=hackios/xnu-deps/host/bin/xnu-clang
[ -f "$XC" ] || { echo "!! $XC is missing: nothing can be compiled"; exit 1; }
sed -i '/-enable-trivial-auto-var-init-zero-knowing-it-will-be-removed-from-clang) ;;/d' "$XC"
if grep -q 'trivial-auto-var-init-zero-knowing' "$XC"; then
  echo "!! xnu-clang still filters the auto-var-init escape flag"; exit 1
fi
echo "== $XC: -enable-trivial-auto-var-init-zero-... is passed through"

# 3. glibc has no strlcpy/strlcat (they are BSD). 8020's SETUP/replacecontents uses strlcat, so
#    the first host tool the build compiles fails to link. hostcompat.h is force-included into
#    every host tool (`HOST_CC=clang -include .../hostcompat.h` in hackios/xnu-build.sh), which
#    is exactly where the rest of the glibc gaps are filled in, so the shim goes there.
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

# stage 1 and stage 2 separately: the include-path fix above has to be in place before stage 2
# compiles anything against the exported headers.
set +e
JOBS=$(nproc) ./hackios/xnu-deps/setup.sh --stage1
rc=$?
if [ $rc -eq 0 ]; then
  JOBS=$(nproc) ./hackios/xnu-deps/setup.sh --stage2
  rc=$?
fi
set -e
if [ $rc -ne 0 ]; then
  for f in hackios/xnu-deps/exporthdrs.log hackios/xnu-deps/build/pthread/build.log; do
    [ -f "$f" ] || continue
    echo "======== $f (tail)"
    tail -80 "$f"
  done
  echo "======== what the export left behind"
  echo "-- BUILD/obj:"; ls "$XNU_SRC/BUILD/obj" 2>/dev/null | head -20
  find "$XNU_SRC/BUILD" -maxdepth 7 -type d -path '*EXPORT_HDRS*' 2>/dev/null | head -30
  exit $rc
fi
