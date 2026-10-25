#!/usr/bin/env bash
# Install theos with its Linux toolchain (cctools/ld64) and one iOS SDK.
# usage: setup-theos.sh [iPhoneOS15.6.sdk]
set -euo pipefail

SDK=${1:-iPhoneOS15.6.sdk}
THEOS=${THEOS:-$PWD/theos}
export THEOS

if [ ! -x "$THEOS/toolchain/linux/iphone/bin/ld64" ]; then
  echo "== installing theos into $THEOS"
  # the official installer fetches the Linux toolchain and the current SDKs
  THEOS="$THEOS" bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/install/master/install.sh)" || true
fi

if [ ! -x "$THEOS/toolchain/linux/iphone/bin/ld64" ]; then
  echo "theos toolchain missing at $THEOS/toolchain/linux/iphone/bin — trying a plain clone + toolchain release"
  git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS" || true
  mkdir -p "$THEOS/toolchain/linux"
  curl -fsSL -o /tmp/toolchain.tar.gz \
    "https://github.com/theos/toolchain/releases/latest/download/linux-iphone-toolchain.tar.gz" || true
  [ -s /tmp/toolchain.tar.gz ] && tar xzf /tmp/toolchain.tar.gz -C "$THEOS/toolchain/linux"
fi

echo "== SDK $SDK"
mkdir -p "$THEOS/sdks"
if [ ! -d "$THEOS/sdks/$SDK" ]; then
  git clone --depth 1 https://github.com/theos/sdks.git /tmp/theos-sdks
  cp -a "/tmp/theos-sdks/$SDK" "$THEOS/sdks/"
fi

echo "== what we have"
ls -la "$THEOS/toolchain/linux/iphone/bin" | head -20
ls -d "$THEOS/sdks/$SDK"
"$THEOS/toolchain/linux/iphone/bin/ld64" -v 2>&1 | head -2 || true

test -x "$THEOS/toolchain/linux/iphone/bin/ld64"
test -d "$THEOS/sdks/$SDK"
