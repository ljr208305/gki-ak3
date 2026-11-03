#!/bin/bash
# git/github 连通性诊断
echo "=== 1) git ls-remote 默认 ==="
timeout 60 git ls-remote --heads https://github.com/OnePlusOSS/kernel_manifest 2>&1 | head -3
echo "rc=$?"
echo
echo "=== 2) git 强制 HTTP/1.1 ==="
timeout 60 git -c http.version=HTTP/1.1 ls-remote --heads https://github.com/OnePlusOSS/kernel_manifest 2>&1 | head -3
echo "rc=$?"
echo
echo "=== 3) curl 打 git smart-http 端点 ==="
timeout 30 curl -sI "https://github.com/OnePlusOSS/kernel_manifest.git/info/refs?service=git-upload-pack" 2>&1 | head -3
echo "rc=$?"
echo
echo "=== 4) git 代理/关键配置 ==="
git config --global --list 2>/dev/null | grep -iE 'proxy|http\.' || echo "(空)"
echo
echo "=== 5) 当前 sync 进程 ==="
pgrep -fa "repo/main.py" 2>/dev/null | head -3
