#!/bin/bash
# 从 susfs4ksu 的 gki-android14-6.1 分支导出 SUSFS v2.2.0 补丁包
set -u
R=/root/gki-build/susfs4ksu.git
OUT=/mnt/f/GKI/patches/susfs-v2.2.0/kernel_patches

echo "=== 定位 2.3.0 bump 提交 ==="
BUMP=$(git -C "$R" rev-parse 5727f79)
PARENT=$(git -C "$R" rev-parse 5727f79^)
echo "2.3.0 bump = $BUMP"
echo "它的父提交 = $PARENT"

echo
echo "=== 确认父提交的版本号 ==="
git -C "$R" show "$PARENT:kernel_patches/include/linux/susfs.h" | grep -m2 'SUSFS_VERSION'

echo
echo "=== 确认最新 2.2.0 提交（在 2.2.0 区间内取最新）==="
# 从 bump 的父往前找，第一个 SUSFS_VERSION 为 v2.2.0 的提交
TARGET=""
for c in $(git -C "$R" rev-list "$PARENT" -n 30); do
  v=$(git -C "$R" show "$c:kernel_patches/include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/')
  echo "  ${c:0:10}  v=$v"
  if [ "$v" = "v2.2.0" ] || [ "$v" = "2.2.0" ]; then
    TARGET="$c"
    break
  fi
done
[ -n "$TARGET" ] || { echo "没找到 2.2.0"; exit 1; }
echo "采用提交: $TARGET"
git -C "$R" log -1 --format='  %ad %s' --date=short "$TARGET"

echo
echo "=== 该提交下 kernel_patches 目录内容 ==="
git -C "$R" ls-tree --name-only "$TARGET:kernel_patches" | head -20

echo
echo "=== 导出 ==="
mkdir -p "$OUT/fs" "$OUT/include/linux"
P="50_add_susfs_in_gki-android14-6.1.patch"
git -C "$R" show "$TARGET:kernel_patches/$P" > "$OUT/$P" 2>/dev/null && echo "  $P  $(wc -c < "$OUT/$P") 字节" || echo "  [X] $P 取不到"
git -C "$R" show "$TARGET:kernel_patches/fs/susfs.c" > "$OUT/fs/susfs.c" 2>/dev/null && echo "  fs/susfs.c  $(wc -c < "$OUT/fs/susfs.c") 字节" || echo "  [X] fs/susfs.c"
git -C "$R" show "$TARGET:kernel_patches/include/linux/susfs.h" > "$OUT/include/linux/susfs.h" 2>/dev/null && echo "  include/linux/susfs.h" || echo "  [X] susfs.h"
git -C "$R" show "$TARGET:kernel_patches/include/linux/susfs_def.h" > "$OUT/include/linux/susfs_def.h" 2>/dev/null && echo "  include/linux/susfs_def.h" || echo "  [X] susfs_def.h"

echo
echo "=== 导出后的目录 ==="
ls -la "$OUT" "$OUT/fs" "$OUT/include/linux" 2>/dev/null
echo
echo "=== 补丁头几行 ==="
head -12 "$OUT/$P" 2>/dev/null
