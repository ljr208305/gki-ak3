#!/bin/bash
# 拉 susfs4ksu 全分支，查 6.1 分支的 SUSFS 2.2.0 提交
set -u
cd /root/gki-build || exit 1
rm -rf susfs4ksu.git
echo "=== clone ==="
git clone --bare --no-single-branch --filter=blob:none https://gitlab.com/simonpunk/susfs4ksu.git susfs4ksu.git 2>&1 | tail -3

echo
echo "=== 分支 ==="
git -C susfs4ksu.git for-each-ref --format='%(refname:short)' refs/heads | head -40

echo
echo "=== tag ==="
git -C susfs4ksu.git tag | tail -20

echo
echo "=== 6.1 分支最近提交的 SUSFS 版本 ==="
BR="origin/gki-android15-6.1"
if git -C susfs4ksu.git rev-parse --verify "$BR" >/dev/null 2>&1; then
  for c in $(git -C susfs4ksu.git rev-list "$BR" -n 40); do
    v=$(git -C susfs4ksu.git show "$c:include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/')
    d=$(git -C susfs4ksu.git log -1 --format='%ad %s' --date=short "$c" 2>/dev/null | cut -c1-70)
    echo "$c  v=$v  $d"
  done
else
  echo "没有 $BR，看所有含 6.1 的分支："
  git -C susfs4ksu.git for-each-ref --format='%(refname:short)' refs/heads | grep '6\.1'
fi
