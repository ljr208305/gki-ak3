#!/usr/bin/env bash
# F:\GKI 环境自检（在 WSL 里跑）：bash env_check.sh [--install]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GKI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PKGS="python3 git curl repo libelf-dev build-essential flex bison libssl-dev libncurses-dev lz4 zlib1g-dev libxml2-utils rsync unzip gawk dos2unix kmod libdw-dev elfutils dwarves jq ccache zip"
CMDS="git curl unzip zip python3 make patch awk find sed gcc ccache"

ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
bad()  { printf '\033[1;31m[!!]\033[0m %s\n' "$*"; }
note() { printf '\033[1;36m--\033[0m %s\n' "$*"; }

echo "================ F:\\GKI 环境自检 ================"
note "发行版: $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo unknown)"
note "内核  : $(uname -r)  $(uname -m)"
note "内存  : $(free -h 2>/dev/null | awk '/^Mem:/{print $2" total / "$7" 可用"}')"
note "CPU   : $(nproc) 核"
note "工程根: $GKI_ROOT"

echo
echo "---- 磁盘 ----"
df -h "$GKI_ROOT" 2>/dev/null | tail -1 | awk '{printf "工程分区 %s 总量 %s 可用 %s\n",$6,$2,$4}'
df -h "$HOME" 2>/dev/null | tail -1 | awk '{printf "源码分区 %s 总量 %s 可用 %s（源码区要 150G+）\n",$6,$2,$4}'

echo
echo "---- 工具 ----"
MISSING_CMD=""
for c in $CMDS; do
  if command -v "$c" >/dev/null 2>&1; then
    printf '  %-10s %s\n' "$c" "$(command -v "$c")"
  else
    bad "  $c 缺失"
    MISSING_CMD="$MISSING_CMD $c"
  fi
done
if command -v repo >/dev/null 2>&1; then
  ok "  repo       $(command -v repo)"
else
  note "  repo       未安装（构建脚本会自己下到 ~/gki-build/bin）"
fi

echo
echo "---- 依赖包 ----"
if command -v dpkg >/dev/null 2>&1; then
  MISSING_PKG=""
  for p in $PKGS; do
    if dpkg -s "$p" >/dev/null 2>&1; then
      printf '  %-18s 已装\n' "$p"
    else
      bad "  $p 缺失"
      MISSING_PKG="$MISSING_PKG $p"
    fi
  done
else
  note " 非 deb 系发行版，跳过包检查"
  MISSING_PKG=""
fi

echo
echo "---- 工程目录 ----"
for d in config scripts patches out logs; do
  if [ -d "$GKI_ROOT/$d" ]; then ok " $d"; else bad " $d 缺失"; fi
done
if [ -f "$GKI_ROOT/config/devices.json" ]; then
  ok " devices.json ($(grep -o '"id"' "$GKI_ROOT/config/devices.json" | wc -l) 台)"
else
  bad " devices.json 缺失"
fi
if [ -f "$GKI_ROOT/patches/susfs-v2.2.0/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch" ]; then
  ok " 本地 SUSFS 2.2.0 补丁（android15-6.6）"
else
  bad " 本地 SUSFS 2.2.0 补丁缺失"
fi

echo
echo "---- 网络 ----"
NETFAIL=0
for u in https://github.com https://gitlab.com https://storage.googleapis.com; do
  if curl -sfI --max-time 8 "$u" >/dev/null 2>&1; then ok " $u"; else bad " $u 不通"; NETFAIL=1; fi
done
if [ "$NETFAIL" = "1" ]; then
  echo "  DNS 挂了就修："
  echo "    bash $GKI_ROOT/scripts/wsl_fixnet.sh"
fi

echo
echo "---- 内存 ----"
MEMMB="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)"
SWAPMB="$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)"
echo "  内存 ${MEMMB}MB / swap ${SWAPMB}MB  自动并发会按内存算（每核约 1.9G）"
if [ "$MEMMB" -lt 12000 ]; then
  echo "  编 6.6 内核吃内存，Windows 侧 %USERPROFILE%\\.wslconfig 给 WSL 抬到 10G+、swap 给 16G："
  echo "    [wsl2]"
  echo "    memory=10GB"
  echo "    swap=16GB"
  echo "    processors=12"
  echo "  改完 wsl --shutdown 生效"
fi

echo
if [ -n "${MISSING_PKG:-}" ] || [ -n "$MISSING_CMD" ]; then
  echo "安装缺失依赖："
  echo "  sudo apt-get update && sudo apt-get install -y$PKGS"
  if [ "${1:-}" = "--install" ]; then
    echo "开始安装..."
    sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $PKGS
  else
    echo "（加 --install 让本脚本直接装）"
  fi
else
  ok "依赖齐全，直接 build"
fi
echo "=================================================="
