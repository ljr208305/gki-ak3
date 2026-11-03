#!/bin/bash
# 遍历 6.1 分支所有 rebase 点，找基线接近 6.1.118 且不依赖 fake_state 的补丁
set -u
R=/root/gki-build/susfs4ksu.git
BR=gki-android14-6.1

echo "=== 所有 Rebase 提交 ==="
git -C "$R" log "$BR" --format='%H|%ad|%s' --date=short --grep='Rebase' -i | head -20

echo
echo "=== 逐个看父提交（rebase 前的基线）==="
printf '%-12s %-8s %-12s %-6s %s\n' "commit" "ver" "fake_state" "date" "subject"
for c in $(git -C "$R" log "$BR" --format='%H' --grep='Rebase' -i | head -8); do
  P=$(git -C "$R" rev-parse "$c^" 2>/dev/null) || continue
  v=$(git -C "$R" show "$P:kernel_patches/include/linux/susfs.h" 2>/dev/null | grep -m1 SUSFS_VERSION | sed 's/.*"\(.*\)".*/\1/')
  fs=$(git -C "$R" show "$P:kernel_patches/50_add_susfs_in_gki-android14-6.1.patch" 2>/dev/null | grep -c fake_state)
  d=$(git -C "$R" log -1 --format='%ad' --date=short "$P")
  s=$(git -C "$R" log -1 --format='%s' "$P" | cut -c1-40)
  printf '%-12s %-8s %-12s %-6s %s\n' "${P:0:10}" "${v:-none}" "$fs" "$d" "$s"
done
