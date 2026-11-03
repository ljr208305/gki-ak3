#!/bin/bash
# 对比各分支的 susfs 补丁是否依赖 fake_state
set -u
R=/root/gki-build/susfs4ksu.git

check() {
  local br="$1" c="$2" tag="$3"
  local f="kernel_patches/50_add_susfs_in_$br.patch"
  local n
  n=$(git -C "$R" show "$c:$f" 2>/dev/null | grep -c 'fake_state')
  local ver
  ver=$(git -C "$R" show "$c:kernel_patches/include/linux/susfs.h" 2>/dev/null | grep -m1 'SUSFS_VERSION' | sed 's/.*"\(.*\)".*/\1/')
  echo "$br  $tag  $ver  fake_state=$n"
}

check gki-android14-6.1  077730110ca6d389c6d39df4d43529b3189b5189  2.2.0
check gki-android14-6.1  a0ac906915c8a8d50d474dfb3cae478ef32edc1a  "2.3.0 HEAD"
check gki-android15-6.6  da55e071ad01fac61fafcfc2b0c66ac22f5c44bf  "2.2.0 ace6 用的"
check gki-android15-6.6  c7f670f57b7d43d75066b6657f8aee9cdf580d96 "2.3.0 HEAD"
