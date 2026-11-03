#!/bin/bash
# GitHub Actions runner 腾磁盘：内核源码要 60G+，默认 runner 不够
set -u

echo "== 清理前 =="
df -h /

sudo swapoff -a 2>/dev/null || true
sudo rm -f /swapfile 2>/dev/null || true

for p in \
  /usr/share/dotnet \
  /usr/local/lib/android \
  /opt/ghc \
  /usr/local/share/boost \
  /opt/hostedtoolcache/CodeQL \
  /usr/local/lib/R \
  /usr/lib/jvm \
  /opt/microsoft \
  /usr/share/miniconda \
  /usr/local/share/powershell \
  /usr/local/share/chromium \
  /opt/google/chrome \
  /usr/share/swift \
  /usr/local/aws-cli \
  /opt/az; do
  sudo rm -rf "$p" 2>/dev/null || true
done

if [ -n "${AGENT_TOOLSDIRECTORY:-}" ]; then
  sudo rm -rf "$AGENT_TOOLSDIRECTORY" 2>/dev/null || true
fi

sudo apt-get clean 2>/dev/null || true
sudo rm -rf /var/lib/apt/lists/* 2>/dev/null || true

echo "== 清理后 =="
df -h /
