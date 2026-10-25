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

JOBS=$(nproc) ./hackios/xnu-deps/setup.sh
