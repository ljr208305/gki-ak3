#!/bin/bash
# 导出 6.1 的 SUSFS v2.3.0（不依赖 fake_state，能编过）
set -u
R=/root/gki-build/susfs4ksu.git
C=a0ac906915c8a8d50d474dfb3cae478ef32edc1a
OUT=/mnt/f/GKI/patches/susfs/android14-6.1

echo "=== 版本确认 ==="
git -C "$R" show "$C:kernel_patches/include/linux/susfs.h" | grep -m1 SUSFS_VERSION
echo "fake_state 引用: $(git -C "$R" show "$C:kernel_patches/50_add_susfs_in_gki-android14-6.1.patch" | grep -c fake_state)"

mkdir -p "$OUT/fs" "$OUT/include/linux"
P=50_add_susfs_in_gki-android14-6.1.patch
git -C "$R" show "$C:kernel_patches/$P" > "$OUT/$P"
git -C "$R" show "$C:kernel_patches/fs/susfs.c" > "$OUT/fs/susfs.c"
git -C "$R" show "$C:kernel_patches/include/linux/susfs.h" > "$OUT/include/linux/susfs.h"
git -C "$R" show "$C:kernel_patches/include/linux/susfs_def.h" > "$OUT/include/linux/susfs_def.h"
echo "=== 导出 ==="
ls -l "$OUT" "$OUT/fs" "$OUT/include/linux"
