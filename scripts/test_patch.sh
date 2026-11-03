#!/bin/bash
# 在下载的 5 个真实源文件上试打修正后的补丁
cd /mnt/f/GKI/_work/ace5src || exit 1
P=/mnt/f/GKI/patches/susfs/android14-6.1/50_add_susfs_in_gki-android14-6.1.patch.fixed
patch -p1 --dry-run --forward < "$P" > /tmp/patchtest.log 2>&1
echo "patch exit=$?"
echo
echo "=== 我们关心的 5 个文件 ==="
grep -A2 -E 'patching file fs/(Makefile|exec\.c|namespace\.c|proc/base\.c|proc/task_mmu\.c)' /tmp/patchtest.log | head -60
echo
echo "=== 失败 hunk 数 ==="
grep -c 'FAILED' /tmp/patchtest.log
echo "=== 失败详情 ==="
grep -B1 'FAILED' /tmp/patchtest.log | head -40
