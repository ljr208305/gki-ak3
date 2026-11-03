#!/bin/bash
# 找 android14-6.1 分支上 SUSFS 2.2.0 的提交（正确路径 kernel_patches/include/linux/susfs.h）
set -u
R=/root/gki-build/susfs4ksu.git

ver() {
  git -C "$R" show "$1:kernel_patches/include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/'
}

echo "=== 对照：用户包里那个 commit da55e071 ==="
echo "da55e071 版本 = $(ver da55e071ad01fac61fafcfc2b0c66ac22f5c44bf)"
echo "所在分支："
for b in $(git -C "$R" for-each-ref --format='%(refname:short)' refs/heads); do
  if git -C "$R" merge-base --is-ancestor da55e071ad01fac61fafcfc2b0c66ac22f5c44bf "$b" 2>/dev/null; then
    echo "   $b"
  fi
done

echo
echo "=== android14-6.1 分支上前 400 个提交里的版本分布（找 2.2.0）==="
found=""
n=0
for c in $(git -C "$R" rev-list gki-android14-6.1 -n 400); do
  v=$(ver "$c")
  [ -z "$v" ] && continue
  n=$((n+1))
  if [ "$v" = "2.2.0" ]; then
    d=$(git -C "$R" log -1 --format='%ad %s' --date=short "$c" | cut -c1-70)
    echo "  [2.2.0] $c  $d"
    [ -z "$found" ] && found="$c"
  fi
done
echo "扫到带版本号的提交 $n 个"
echo "最新的 2.2.0 提交: ${found:-<没找到>}"

echo
echo "=== android14-6.1 头部版本序列（最近 25 个带版本号的）==="
cnt=0
for c in $(git -C "$R" rev-list gki-android14-6.1 -n 400); do
  v=$(ver "$c")
  [ -z "$v" ] && continue
  echo "  $(git -C "$R" log -1 --format='%ad' --date=short "$c")  v=$v  ${c:0:10}"
  cnt=$((cnt+1))
  [ "$cnt" -ge 25 ] && break
done
