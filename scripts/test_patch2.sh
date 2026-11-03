#!/bin/bash
# 本地验证：prep + 打补丁
set -u
SRC=/mnt/f/GKI/_work/ace5src
PDIR=/mnt/f/GKI/patches/susfs/android14-6.1
P=$PDIR/50_add_susfs_in_gki-android14-6.1.patch.fixed

rm -rf /tmp/t5b
cp -r "$SRC" /tmp/t5b
python3 /mnt/f/GKI/scripts/patch_prep.py "$P" /tmp/t5b >/tmp/prep.log 2>&1
cat /tmp/prep.log

cd /tmp/t5b || exit 1
patch -p1 --forward < "$P.new" >/tmp/apply.log 2>&1
echo "patch exit=$?"
echo
echo "=== 各文件结果 ==="
grep -E 'patching file|FAILED|Hunk #' /tmp/apply.log | head -40
echo
echo "=== FAILED 计数: $(grep -c FAILED /tmp/apply.log) ==="
echo "=== 生成的 .rej ==="
find /tmp/t5b -name '*.rej' | head
