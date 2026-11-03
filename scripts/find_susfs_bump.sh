#!/bin/bash
# 找 android14-6.1 分支上版本号变更点，定位 2.2.0 时代
set -u
R=/root/gki-build/susfs4ksu.git
BR=gki-android14-6.1

echo "=== 提交标题含 version / bump 的（近 40 条）==="
git -C "$R" log "$BR" --oneline -i --grep='version' -n 40 2>/dev/null

echo
echo "=== 版本号文件变更历史（-S SUSFS_VERSION，近 15 次）==="
git -C "$R" log "$BR" --format='%h %ad %s' --date=short -S 'SUSFS_VERSION' -n 15 -- kernel_patches/include/linux/susfs.h 2>/dev/null

echo
echo "=== 抽查一批较老提交的版本号 ==="
for c in $(git -C "$R" rev-list "$BR" --skip=300 -n 40); do
  v=$(git -C "$R" show "$c:kernel_patches/include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/')
  [ -z "$v" ] && continue
  echo "  $(git -C "$R" log -1 --format='%ad' --date=short "$c")  v=$v  ${c:0:10}"
done
