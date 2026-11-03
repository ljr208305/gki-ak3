#!/usr/bin/env python3
# SUSFS 补丁预处理：
#   1) 删掉 fs/namespace.c 和 fs/proc/base.c 里两个 include 区 hunk（基线差异，打不上）
#   2) 直接往源码里插入对应的 include / extern 声明（幂等）
# 用法: patch_prep.py <patchfile> <common_dir>
import sys
import os
import re

DROP = {
    'fs/namespace.c': [32],
    'fs/proc/base.c': [100],
}

INSERTS = {
    'fs/namespace.c': [
        ('#include <linux/mnt_idmapping.h>', [
            '#ifdef CONFIG_KSU_SUSFS',
            '#include <linux/susfs_def.h>',
            '#endif // #ifdef CONFIG_KSU_SUSFS',
        ]),
        ('#include "internal.h"', [
            '',
            '#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT',
            'extern bool susfs_is_current_ksu_domain(void);',
            'extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;',
            '',
            '#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */',
            '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT',
        ]),
    ],
    'fs/proc/base.c': [
        ('#include <linux/cpufreq_times.h>', [
            '#if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)',
            '#include <linux/susfs_def.h>',
            '#endif // susfs',
            '',
        ]),
    ],
}


def strip_hunks(path):
    with open(path, 'r', encoding='utf-8', errors='surrogateescape') as f:
        lines = f.readlines()
    out = []
    i = 0
    n = len(lines)
    cur = None
    dropped = 0
    while i < n:
        ln = lines[i]
        if ln.startswith('diff --git '):
            m = re.match(r'diff --git a/(\S+) b/', ln)
            cur = m.group(1) if m else None
        if ln.startswith('@@') and cur in DROP:
            m = re.match(r'@@ -(\d+)', ln)
            if m and int(m.group(1)) in DROP[cur]:
                dropped += 1
                i += 1
                while i < n and not (lines[i].startswith('@@') or lines[i].startswith('diff --git ')):
                    i += 1
                continue
        out.append(ln)
        i += 1
    with open(path + '.new', 'w', encoding='utf-8', errors='surrogateescape') as f:
        f.writelines(out)
    print(f'  删除 hunk {dropped} 个 -> {path}.new')


def insert_blocks(common):
    for rel, rules in INSERTS.items():
        target = os.path.join(common, rel)
        if not os.path.isfile(target):
            print(f'  [skip] 没有 {rel}')
            continue
        with open(target, 'r', encoding='utf-8', errors='surrogateescape') as f:
            lines = f.read().split('\n')
        changed = 0
        for anchor, block in rules:
            if any(b.strip() and b.strip() in '\n'.join(lines) for b in block[:1]):
                print(f'  [已存在] {rel} <- {block[0]}')
                continue
            pos = None
            for idx, l in enumerate(lines):
                if l.strip() == anchor.strip():
                    pos = idx
                    break
            if pos is None:
                print(f'  [找不到锚点] {rel}: {anchor}')
                continue
            lines[pos + 1:pos + 1] = block
            changed += 1
            print(f'  [插入] {rel} after {anchor} (+{len(block)} 行)')
        if changed:
            with open(target, 'w', encoding='utf-8', errors='surrogateescape') as f:
                f.write('\n'.join(lines))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    strip_hunks(sys.argv[1])
    insert_blocks(sys.argv[2])
    return 0


if __name__ == '__main__':
    sys.exit(main())
