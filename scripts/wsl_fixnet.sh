#!/bin/bash
# WSL 网络/DNS 修复（构建前必须能访问 github/gitlab）
set -u
CONF=/etc/systemd/resolved.conf

echo "== 清理上次写坏的行 =="
sed -i '/^n\[Resolve\]/d' "$CONF" 2>/dev/null || true
sed -i '/^nDNS=/d' "$CONF" 2>/dev/null || true
sed -i '/^nFallbackDNS=/d' "$CONF" 2>/dev/null || true

if ! grep -qE '^DNS=' "$CONF"; then
  echo "== 写入上游 DNS =="
  {
    echo ""
    echo "[Resolve]"
    echo "DNS=223.5.5.5 119.29.29.29"
    echo "FallbackDNS=8.8.8.8 1.1.1.1"
  } >> "$CONF"
fi

echo "== resolved.conf =="
tail -6 "$CONF"

echo "== 重启 systemd-resolved =="
systemctl restart systemd-resolved 2>/dev/null || echo "没有 systemd-resolved，跳过"
sleep 2

echo "== 解析测试 =="
getent hosts github.com || echo RESOLVE_FAIL

echo "== HTTP 测试 =="
curl -sI --max-time 15 https://raw.githubusercontent.com/Numbersf/Action-Build/SukiSU-Ultra/FILE.md 2>/dev/null | head -2 || echo CURL_FAIL

echo "== git 测试 =="
timeout 30 git ls-remote --heads https://github.com/OnePlusOSS/kernel_manifest 2>&1 | head -3 || echo GIT_FAIL
