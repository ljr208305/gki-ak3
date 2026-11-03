#!/bin/bash
# 对比 v1.5.7 / v2.2.0 / v2.3.0 的 SUSFS 开关，并导出 1.5.7
set -u
R=/root/gki-build/susfs4ksu.git
BR=gki-android14-6.1
P=kernel_patches/50_add_susfs_in_gki-android14-6.1.patch

list_opts() {
  git -C "$R" show "$1:$P" 2>/dev/null | grep -o 'CONFIG_KSU_SUSFS_[A-Z_0-9]*' | sort -u
}

echo "=== v1.5.7 (c75391d3ee) ==="
list_opts c75391d3ee
echo
echo "=== v2.2.0 (077730110c) ==="
list_opts 077730110ca6d389c6d39df4d43529b3189b5189
echo
echo "=== v2.3.0 (a0ac906915) ==="
list_opts a0ac906915c8a8d50d474dfb3cae478ef32edc1a

echo
echo "=== 差异：2.2.0 有而 1.5.7 没有 ==="
comm -13 <(list_opts c75391d3ee) <(list_opts 077730110ca6d389c6d39df4d43529b3189b5189)
echo
echo "=== 差异：2.3.0 有而 2.2.0 没有 ==="
comm -13 <(list_opts 077730110ca6d389c6d39df4d43529b3189b5189) <(list_opts a0ac906915c8a8d50d474dfb3cae478ef32edc1a)

echo
echo "=== 导出 v1.5.7 到 patches/susfs/android14-6.1 ==="
C=c75391d3ee
OUT=/mnt/f/GKI/patches/susfs/android14-6.1
rm -rf "$OUT"
mkdir -p "$OUT/fs" "$OUT/include/linux"
git -C "$R" show "$C:$P" > "$OUT/50_add_susfs_in_gki-android14-6.1.patch"
git -C "$R" show "$C:kernel_patches/fs/susfs.c" > "$OUT/fs/susfs.c"
git -C "$R" show "$C:kernel_patches/include/linux/susfs.h" > "$OUT/include/linux/susfs.h"
git -C "$R" show "$C:kernel_patches/include/linux/susfs_def.h" > "$OUT/include/linux/susfs_def.h"
ls -l "$OUT" "$OUT/fs" "$OUT/include/linux"
echo "版本: $(grep -m1 SUSFS_VERSION "$OUT/include/linux/susfs.h")"
echo "fake_state: $(grep -c fake_state "$OUT/50_add_susfs_in_gki-android14-6.1.patch")"
