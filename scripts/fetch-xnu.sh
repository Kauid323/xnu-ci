#!/usr/bin/env bash
# Fetch an XNU tag and apply our patch to it.
# usage: fetch-xnu.sh [xnu-8020.140.41] [patches/hackios-8796.patch]
set -euo pipefail

TAG=${1:-xnu-8020.140.41}
PATCH=${2:-patches/hackios-8796.patch}

rm -rf src
curl -sSL -o xnu.tar.gz "https://codeload.github.com/apple-oss-distributions/xnu/tar.gz/refs/tags/${TAG}"
tar xzf xnu.tar.gz
mv "xnu-${TAG}" src

cd src
git init -q .
git add -A
git -c user.email=ci@local -c user.name=ci commit -qm "vanilla ${TAG}"

echo "== applying $PATCH"
if ! git apply --check "../${PATCH}" 2>../apply-check.log; then
  echo "the patch does not apply as-is; see the log. Porting is not done yet."
  cat ../apply-check.log
  exit 1
fi
git apply "../${PATCH}"
echo "== patch applied"
