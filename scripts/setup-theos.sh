#!/usr/bin/env bash
# Install theos with its Linux toolchain (cctools/ld64) and one iOS SDK.
#
# The URLs are the ones the official installer (theos/theos:bin/install-theos) uses for a Linux
# x86_64/arm64 host without Swift support:
#   theos      git clone https://github.com/theos/theos
#   toolchain  https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-<arch>.tar.xz
#              (needs libtinfo6; unpacks to $THEOS/toolchain/linux/iphone)
#   SDKs       https://github.com/theos/sdks   (one directory per SDK)
#
# usage: setup-theos.sh [iPhoneOS16.5.sdk]
set -euo pipefail

SDK=${1:-iPhoneOS16.5.sdk}
THEOS=${THEOS:-$PWD/theos}
export THEOS
ARCH=$(uname -m)
CCTOOLS=$THEOS/toolchain/linux/iphone/bin

echo "== theos into $THEOS"
if [ ! -d "$THEOS/makefiles" ]; then
  git clone --recursive --depth 1 https://github.com/theos/theos.git "$THEOS"
fi

echo "== toolchain ($ARCH)"
if [ ! -x "$CCTOOLS/clang" ]; then
  sudo apt-get install -y --no-install-recommends libtinfo6 || true
  mkdir -p "$THEOS/toolchain"
  curl -fsSL -o /tmp/iostoolchain.tar.xz \
    "https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-$ARCH.tar.xz"
  tar xJf /tmp/iostoolchain.tar.xz -C "$THEOS/toolchain/"
  rm -f /tmp/iostoolchain.tar.xz
fi
if [ ! -x "$CCTOOLS/clang" ]; then
  echo "!! no clang in $CCTOOLS"; ls -la "$THEOS/toolchain" 2>/dev/null; exit 1
fi

echo "== SDK $SDK"
mkdir -p "$THEOS/sdks"
if [ ! -d "$THEOS/sdks/$SDK" ]; then
  rm -rf /tmp/theos-sdks
  git clone --depth 1 https://github.com/theos/sdks.git /tmp/theos-sdks
  if [ ! -d "/tmp/theos-sdks/$SDK" ]; then
    echo "!! no $SDK in theos/sdks"; ls /tmp/theos-sdks | head -30; exit 1
  fi
  cp -a "/tmp/theos-sdks/$SDK" "$THEOS/sdks/"
fi

echo "== what we have"
ls "$CCTOOLS" | head -20
ls -d "$THEOS/sdks/$SDK"
"$CCTOOLS/ld64" -v 2>&1 | head -2 || true

test -x "$CCTOOLS/ld64" -o -x "$CCTOOLS/ld"
test -d "$THEOS/sdks/$SDK"
echo "== theos ready"
