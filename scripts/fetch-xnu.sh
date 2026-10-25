#!/usr/bin/env bash
# Fetch an XNU tag, put the redwood work on top of it, and (when hackios is checked out next to
# us) the new files that the patch refers to but does not carry.
#
# The redwood work is two things, as in hackios/xnu/apply.sh:
#   redwood.patch  changes to Apple's own files        -> patches/hackios-*.patch
#   files/         files Apple's tree does not have    -> hackios/xnu/files/
#
# usage: fetch-xnu.sh [xnu-8020.140.41] [patches/hackios-8020.patch]
set -euo pipefail

TAG=${1:-xnu-8020.140.41}
PATCH=${2:-patches/hackios-8020.patch}
NEWFILES=${NEWFILES:-hackios/xnu/files}

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

if [ -d "../${NEWFILES}" ]; then
  n=$(find "../${NEWFILES}" -type f | wc -l)
  echo "== copying $n new files from $NEWFILES"
  cp -a "../${NEWFILES}/." .
else
  echo "!! $NEWFILES is missing: the patch refers to files that are not here"
  echo "   (bsd/dev/redwood_*.c, bsd/miscfs/apfs/*, iokit/Kernel/Mini*.cpp, ...)"
  exit 1
fi

# Files that have to be written for 8020 rather than taken from hackios: same path, our version
# wins. Kept as whole files, not as a patch, because these are files Apple's tree does not have.
if [ -d ../overrides ]; then
  n=$(find ../overrides -type f | wc -l)
  echo "== overriding $n file(s) from overrides/"
  cp -a ../overrides/. .
fi

# everything the patch and files/ are supposed to provide, checked before the compiler finds out
echo "== checking the tree is complete"
missing=0
while read -r f; do
  case "$f" in
    \#*|'') continue ;;
  esac
  if [ ! -e "$f" ]; then echo "   missing: $f"; missing=$((missing + 1)); fi
done <<'EOF'
bsd/dev/redwood_lx.c
bsd/dev/redwood_apfs_check.c
bsd/miscfs/apfs/apfs_vfsops.c
bsd/miscfs/ramfs/ramfs.c
bsd/pthread/pthread_kext_static.c
iokit/Kernel/GenericARMPE.cpp
osfmk/arm64/generic_arm64_support.c
osfmk/arm64/psci_smp.c
osfmk/arm64/loader_return.c
libkern/amfi/miniamfi.c
EOF
[ "$missing" -eq 0 ] || { echo "!! $missing expected file(s) absent"; exit 1; }
echo "== tree complete"
