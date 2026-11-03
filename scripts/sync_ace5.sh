#!/bin/bash
# 只同步 ace5（6.1.118）源码到本地，用于本地复现补丁冲突
set -u
FILE=oneplus_ace5
MAP=/mnt/f/GKI/config/manifest-map.tsv
LINE=$(awk -F'\t' -v f="$FILE" '$1==f{print $2 "|" $3; exit}' "$MAP")
OWNER=$(echo "$LINE" | cut -d'|' -f1)
BR=$(echo "$LINE" | cut -d'|' -f2)
BR=${BR#*/}
FULLBR=$(awk -F'\t' -v f="$FILE" '$1==f{print $3; exit}' "$MAP")
echo "owner=$OWNER branch=$FULLBR"

SRC=/root/gki-build/src/$BR
echo "SRC=$SRC"
mkdir -p "$SRC"
cd "$SRC" || exit 1

if [ ! -d .repo ]; then
  repo init -u "https://github.com/$OWNER.git" -b "$FULLBR" -m "$FILE.xml" --depth=1 --no-clone-bundle --no-tags
fi

for i in 1 2 3 4 5; do
  echo "=== sync 第 $i 次 ==="
  if repo sync -c -j4 --no-clone-bundle --no-tags --force-sync; then
    echo "SYNC_OK"
    break
  fi
  sleep 30
done

echo "=== 结果 ==="
du -sm "$SRC" 2>/dev/null
ls "$SRC/kernel_platform/common/Makefile" 2>/dev/null && echo "common 就位"
grep -m1 '^BRANCH=' "$SRC/kernel_platform/common/build.config.constants" 2>/dev/null
