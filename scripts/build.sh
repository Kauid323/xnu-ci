#!/usr/bin/env bash
# Build the kernel with hackios's build script (same flags redwood uses) and collect the result.
#
# The target is "build" (= build_all_bootstrap), not "all": "all" is build_all plus config_all,
# and config_all is Apple's post-processing of the tree (regenerating the per-component Makefiles
# for installs). It runs the config(8) program a second time over the generated MASTER and dies
# with "config: line N: syntax error" -- after the kernel has been linked and stripped, so the
# only thing it costs is a red run and an empty artifact.
set -euo pipefail

export THEOS=${THEOS:-$PWD/theos}
export XNU_SRC=$PWD/src
export XNU_SDK_PATH="$THEOS/sdks/${XNU_SDK:-iPhoneOS16.5.sdk}"
export XNU_SDK_VERSION=${XNU_SDK_VERSION:-16.5}
export MACHINE=${MACHINE:-BCM2837}

JOBS=$(nproc) ./hackios/xnu-build.sh -j"$(nproc)" build

mkdir -p out
# Only regular files directly under BUILD/obj/<config>/: the same glob also matches the .link and
# .dSYM directories, and "cp" without -r then fails and takes the whole step with it.
n=0
while IFS= read -r f; do
  cp -v "$f" out/
  n=$((n + 1))
done < <(find src/BUILD/obj -mindepth 2 -maxdepth 2 -type f -name 'mach.*' 2>/dev/null)
if [ "$n" -eq 0 ]; then
  echo "no kernel in src/BUILD/obj"
  find src/BUILD -maxdepth 3 -name 'mach*' | head
  exit 1
fi
ls -la out/
