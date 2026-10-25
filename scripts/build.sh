#!/usr/bin/env bash
# Build the kernel with hackios's build script (same flags redwood uses) and collect the result.
set -euo pipefail

export THEOS=${THEOS:-$PWD/theos}
export XNU_SRC=$PWD/src
export XNU_SDK_PATH="$THEOS/sdks/${XNU_SDK:-iPhoneOS15.6.sdk}"
export XNU_SDK_VERSION=${XNU_SDK_VERSION:-15.6}
export MACHINE=${MACHINE:-BCM2837}

JOBS=$(nproc) ./hackios/xnu-build.sh -j"$(nproc)"

mkdir -p out
cp -v src/BUILD/obj/*/mach.* out/ 2>/dev/null || cp -v src/BUILD/obj/*/kernel.* out/ 2>/dev/null || {
  echo "no kernel in src/BUILD/obj"; find src/BUILD -maxdepth 3 -name 'mach*' | head; exit 1; }
ls -la out/
