#!/usr/bin/env python3
"""Compare every function on Merlin's rc boot path with the stock GPL 25206 source.

usage: init-path-compare.py <gpl-router-dir> <merlin-router-dir> <gpl-prebuild-dir-root>

Takes the functions called directly from rc/init.c sysinit() and init_main() in the Merlin
tree, finds each definition (brace-matched, comments stripped, whitespace normalised) in
rc/, rc/sysdeps/, shared/ and shared/sysdeps/broadcom/ of both trees, and classifies it:
IDENTICAL, DIFFERS (+changed line count), PREBUILT (only in ASUS 25206 prebuilt objects, which
Merlin links unchanged), INLINE/MACRO, or UNDEFINED (call compiled out for this model; the
link succeeded). Preprocessor conditionals are kept: they are part of the definition.
"""
import os, re, sys, subprocess, difflib, glob

G, M, PB = sys.argv[1], sys.argv[2], sys.argv[3]
DIRS = ['rc', 'rc/sysdeps', 'shared', 'shared/sysdeps/broadcom']

def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', ' ', s, flags=re.S)
    return re.sub(r'//[^\n]*', ' ', s)


def match_brace(src, i):
    """Return index just past the brace block starting after position i (depth 1 at i).
    Preprocessor-aware: braces are counted only in the first branch of each #if chain,
    and string/char literals are skipped."""
    depth, n = 1, len(src)
    skip = []            # stack of booleans: are we in a non-first #if branch?
    line_start = True
    while i < n and depth:
        ch = src[i]
        if line_start:
            j = i
            while j < n and src[j] in ' \t': j += 1
            if j < n and src[j] == '#':
                e = src.find('\n', j); e = n if e < 0 else e
                d = src[j+1:e].strip()
                if d.startswith(('if', 'ifdef', 'ifndef')): skip.append(any(skip))
                elif d.startswith(('elif', 'else')):
                    if skip: skip[-1] = True
                elif d.startswith('endif'):
                    if skip: skip.pop()
                i = e; line_start = True; continue
        line_start = (ch == '\n')
        if ch in '"\'':
            q = ch; i += 1
            while i < n and src[i] != q:
                if src[i] == '\\': i += 1
                i += 1
            i += 1; continue
        if not (skip and skip[-1]):
            if ch == '{': depth += 1
            elif ch == '}': depth -= 1
        i += 1
    return i

def defs(root):
    out = {}
    for d in DIRS:
        for f in glob.glob(os.path.join(root, d, '*.c')):
            src = strip_comments(open(f, errors='replace').read())
            for m in re.finditer(r'^[A-Za-z_][\w \t\*]*?\b(\w+)\s*\([^;{)]*\)\s*\{', src, re.M):
                name = m.group(1)
                i = match_brace(src, m.end())
                body = [l.strip() for l in src[m.start():i].splitlines() if l.strip()]
                out.setdefault(name, []).append(body)
    return out

def calls(root, fn_regex):
    src = strip_comments(open(os.path.join(root, 'rc/init.c'), errors='replace').read())
    m = re.search(fn_regex, src, re.M)
    start = src.index('{', m.end() - 1) + 1
    i = match_brace(src, start)
    seen = []
    for c in re.findall(r'\b([a-z_]\w*)\s*\(', src[start:i]):
        if c not in seen and c not in ('if', 'for', 'while', 'switch', 'return', 'sizeof', 'defined'):
            seen.append(c)
    return seen

prebuilt = set()
for o in glob.glob(os.path.join(PB, '*/prebuild/*.o')):
    for l in subprocess.run(['nm', '--defined-only', o], capture_output=True, text=True).stdout.splitlines():
        p = l.split()
        if len(p) == 3 and p[1] == 'T':
            prebuilt.add(p[2])

gd, md = defs(G), defs(M)
names = []
for rx in (r'^static void sysinit\(void\)', r'^int init_main\(int argc[^)]*\)'):
    for c in calls(M, rx):
        if c not in names:
            names.append(c)

libc = {'printf', 'snprintf', 'sprintf', 'strlen', 'strcmp', 'strncmp', 'strcpy', 'strlcpy', 'mkdir',
        'chmod', 'umask', 'symlink', 'unlink', 'sleep', 'system', 'putenv', 'setrlimit', 'signal',
        'sigemptyset', 'sigaddset', 'sigprocmask', 'closedir', 'perror', 'stime', 'klogctl', 'chroot',
        'chdir', 'sync', 'exit', 'kill', 'nvram_get', 'nvram_set', 'nvram_unset', 'nvram_safe_get',
        'nvram_set_int', 'nvram_get_int', 'nvram_match', 'nvram_commit', 'eval', '_eval', 'dbg',
        '_dprintf', 'f_write_string', 'f_write', 'f_read', 'logmessage', 'foreach', 'ifconfig',
        'killall_tk', 'modprobe', 'modprobe_r', 'reboot', 'chld_reap'}
for n in names:
    if n in libc:
        continue
    g, m = gd.get(n), md.get(n)
    if g and m:
        if g == m:
            st = 'IDENTICAL'
        else:
            a, b = max(g, key=len), max(m, key=len)
            ch = sum(1 for x in difflib.ndiff(a, b) if x[:1] in '+-')
            st = f'DIFFERS ({ch} lines)'
    elif n in prebuilt:
        st = 'PREBUILT (ASUS 25206 object, linked unchanged)'
    elif m and not g:
        st = 'MERLIN-ONLY source'
    elif g and not m:
        st = 'STOCK-ONLY source'
    else:
        st = 'UNDEFINED/INLINE (compiled out or header inline for this model)'
    print(f'{n:40} {st}')
