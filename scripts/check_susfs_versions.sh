#!/bin/bash
# 查 susfs4ksu 6.1 / 6.6 分支的 SUSFS 版本历史（bare 仓库，引用不带 origin/）
set -u
R=/root/gki-build/susfs4ksu.git

show_branch() {
  local br="$1" n="${2:-25}"
  echo "############ $br ############"
  if ! git -C "$R" rev-parse --verify "$br" >/dev/null 2>&1; then
    echo "(没有这个分支)"
    echo
    return
  fi
  for c in $(git -C "$R" rev-list "$br" -n "$n"); do
    v=$(git -C "$R" show "$c:include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/')
    d=$(git -C "$R" log -1 --format='%ad %s' --date=short "$c" 2>/dev/null | cut -c1-64)
    echo "$c  v=$v  $d"
  done
  echo
}

show_branch gki-android14-6.1 30
show_branch gki-android15-6.6 20

echo "############ android14-6.1 分支里所有 2.2.0 提交 ############"
for c in $(git -C "$R" rev-list gki-android14-6.1 -n 200); do
  v=$(git -C "$R" show "$c:include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/')
  if [ "$v" = "2.2.0" ]; then
    echo "  2.2.0 -> $c"
  fi
done
echo
echo "############ 分支上最高的 10 个版本号 ############"
for c in $(git -C "$R" rev-list gki-android14-6.1 -n 300); do
  v=$(git -C "$R" show "$c:include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/')
  [ -n "$v" ] && echo "$v"
done | sort -uV | tail -10
