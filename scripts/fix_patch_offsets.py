#!/usr/bin/env python3
# 修正 unified diff 的 hunk 行号：在目标源码里重新定位每个 hunk
# 用法: fix_patch_offsets.py <patch> <srcdir> [--inplace] [--min-score 0.6]
import sys
import os
import re


def parse_hunks(lines):
    """返回 list of dict: {file_start, hunks:[{hdr_idx, old_start, old_count, new_start, new_count, body}]}"""
    out = []
    cur = None
    i = 0
    n = len(lines)
    while i < n:
        ln = lines[i]
        if ln.startswith('diff --git '):
            m = re.match(r'diff --git a/(\S+) b/(\S+)', ln)
            cur = {'path': m.group(2) if m else None, 'hunks': []}
            out.append(cur)
            i += 1
            continue
        if ln.startswith('@@') and cur is not None:
            m = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', ln)
            if not m:
                i += 1
                continue
            h = {
                'hdr_idx': i,
                'old_start': int(m.group(1)),
                'old_count': int(m.group(2)) if m.group(2) is not None else 1,
                'new_start': int(m.group(3)),
                'new_count': int(m.group(4)) if m.group(4) is not None else 1,
                'body': [],
            }
            i += 1
            while i < n:
                l2 = lines[i]
                if l2.startswith('@@') or l2.startswith('diff --git '):
                    break
                h['body'].append(l2)
                i += 1
            cur['hunks'].append(h)
            continue
        i += 1
    return out


def old_side(body):
    res = []
    for ln in body:
        if not ln:
            continue
        t = ln[0]
        if t == ' ':
            res.append(ln[1:].rstrip('\n'))
        elif t == '-':
            res.append(ln[1:].rstrip('\n'))
        elif t == '\\':
            continue
    return res


def locate(target, old_lines, min_pos):
    n = len(old_lines)
    if n == 0:
        return None, 0.0
    best_score = -1
    best_pos = None
    limit = len(target) - n
    for pos in range(min_pos, max(min_pos, limit) + 1):
        s = 0
        for k in range(n):
            if target[pos + k].rstrip() == old_lines[k].rstrip():
                s += 1
        if s > best_score:
            best_score = s
            best_pos = pos
        if s == n:
            break
    if best_pos is None:
        return None, 0.0
    return best_pos, best_score / n


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = [a for a in sys.argv[1:] if a.startswith('--')]
    if len(args) < 2:
        print(__doc__)
        return 1
    patch_path, src_dir = args[0], args[1]
    inplace = '--inplace' in flags
    min_score = 0.6
    for f in flags:
        if f.startswith('--min-score'):
            min_score = float(f.split('=')[1]) if '=' in f else min_score

    with open(patch_path, 'r', encoding='utf-8', errors='surrogateescape') as fh:
        lines = fh.readlines()

    groups = parse_hunks(lines)
    fixed = 0
    skipped = 0
    for g in groups:
        p = g['path']
        if not p:
            continue
        target_path = os.path.join(src_dir, p)
        if not os.path.isfile(target_path):
            continue
        with open(target_path, 'r', encoding='utf-8', errors='surrogateescape') as fh:
            target = fh.read().split('\n')
        cursor = 0
        for h in g['hunks']:
            old = old_side(h['body'])
            pos, score = locate(target, old, cursor)
            if pos is None or score < min_score:
                print(f'  [跳过] {p} @@ -{h["old_start"]} (匹配 {score:.0%})')
                skipped += 1
                continue
            new_line = pos + 1
            if new_line == h['old_start']:
                cursor = pos + len(old)
                continue
            hdr = lines[h['hdr_idx']]
            m = re.match(r'(@@ -)(\d+)(?:,(\d+))?( \+)(\d+)(?:,(\d+))?( @@.*)', hdr.rstrip('\n'))
            if m:
                rest = m.group(7)
                newhdr = f'@@ -{new_line},{h["old_count"]} +{new_line},{h["new_count"]}{rest}\n'
                lines[h['hdr_idx']] = newhdr
                print(f'  [修正] {p} @@ {h["old_start"]} -> {new_line}  (匹配 {score:.0%})')
                fixed += 1
            cursor = pos + len(old)

    out_path = patch_path if inplace else patch_path + '.fixed'
    with open(out_path, 'w', encoding='utf-8', errors='surrogateescape') as fh:
        fh.writelines(lines)
    print(f'\n修正 {fixed} 个 hunk，跳过 {skipped} 个 -> {out_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
