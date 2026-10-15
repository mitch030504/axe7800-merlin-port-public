#!/usr/bin/env python3
"""Compare struct/union/enum bodies in a header between GPL and candidate copies.
usage: struct-drift.py <gpl-header> <label>=<candidate-header> ...
A body is compared after stripping comments and collapsing whitespace. Preprocessor lines are
kept, because #ifdef-guarded members change layout depending on RTCONFIG_*."""
import re, sys

def bodies(path):
    try:
        src = open(path, errors='replace').read()
    except OSError:
        return None
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.S)
    src = re.sub(r'//[^\n]*', ' ', src)
    out = {}
    for m in re.finditer(r'\b(struct|union|enum)\s+([A-Za-z_]\w*)\s*\{', src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            depth += {'{': 1, '}': -1}.get(src[i], 0); i += 1
        body = re.sub(r'\s+', ' ', src[m.end():i - 1]).strip()
        out[f'{m.group(1)} {m.group(2)}'] = body
    # typedef struct { ... } name;
    for m in re.finditer(r'typedef\s+(struct|union|enum)\s*(\w*)\s*\{', src):
        i, depth = m.end(), 1
        while i < len(src) and depth:
            depth += {'{': 1, '}': -1}.get(src[i], 0); i += 1
        tail = re.match(r'\s*(\w+)', src[i:])
        name = tail.group(1) if tail else m.group(2) or '?'
        out.setdefault(f'typedef {name}', re.sub(r'\s+', ' ', src[m.end():i - 1]).strip())
    return out

g = bodies(sys.argv[1])
if g is None:
    sys.exit(f"cannot read {sys.argv[1]}")
for arg in sys.argv[2:]:
    label, path = arg.split('=', 1)
    c = bodies(path)
    if c is None:
        print(f'  {label}: header absent'); continue
    diff = sorted(k for k in g if k in c and g[k] != c[k])
    gone = sorted(k for k in g if k not in c)
    print(f'  {label}: {len(g)} types in GPL; differ={len(diff)} absent={len(gone)}'
          + (f'  differ: {", ".join(diff[:12])}' if diff else ''))
