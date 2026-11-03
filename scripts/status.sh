#!/bin/bash
# 构建进度速查：bash scripts/status.sh
echo "=== 编译进程 ==="
ps aux | grep -E 'make|clang|lld|repo' | grep -v grep | head -8
N=$(ps aux | grep -E 'clang|cc1' | grep -v grep | wc -l)
echo "clang 进程数: $N"
echo
echo "=== 源码体积 ==="
du -sh /root/gki-build/src/* 2>/dev/null
echo
echo "=== 磁盘 ==="
df -h / | tail -1
echo
echo "=== 最新日志 ==="
LOG=$(ls -t /mnt/f/GKI/logs/build-*.log 2>/dev/null | head -1)
echo "$LOG"
tail -25 "$LOG" 2>/dev/null
echo
echo "=== 产物 ==="
ls -lh /mnt/f/GKI/out/ 2>/dev/null | tail -5
