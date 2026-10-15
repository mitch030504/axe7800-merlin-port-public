#!/usr/bin/env python3
"""Find Merlin open-source calls into private symbols the 25206 supply does not provide.

usage: scan-generation-gaps.py <merlin-worktree> <gpl-root> [donor-model ...]

A symbol is a candidate when it is DEFINED by a per-model prebuilt object that the Merlin tree
ships for another model (default donors: GT-AX6000 RT-AX86U_PRO RT-AX88U_PRO, the newest 388
generation in 3004.388), is NOT defined by any 25206 prebuilt for the same component, and is
referenced from Merlin's open .c sources of that component. Each candidate is a call site that
Merlin picked up from a newer ASUS GPL than 25206. The output is a list to review, not a verdict.
"""
import os, re, subprocess, sys, collections

wt, gpl = sys.argv[1], sys.argv[2]
donors = sys.argv[3:] or ['GT-AX6000', 'RT-AX86U_PRO', 'RT-AX88U_PRO']
R = os.path.join(wt, 'release/src/router')
GR = os.path.join(gpl, 'release/src/router')

def defined(path):
    p = subprocess.run(['nm', '--defined-only', '-g', path], capture_output=True, text=True)
    return {l.split()[-1] for l in p.stdout.splitlines() if len(l.split()) == 3}

def prebuild_dirs(root):
    for dp, dn, fn in os.walk(root):
        if os.path.basename(dp) in ('prebuild', 'prebuilt'):
            yield dp

# 25206 supply, per component directory (path relative to router/, prebuild dir stripped)
supply = collections.defaultdict(set)
for d in prebuild_dirs(GR):
    comp = os.path.relpath(os.path.dirname(d), GR)
    for dp, dn, fn in os.walk(d):
        for f in fn:
            if f.endswith('.o') or '.so' in f:
                supply[comp] |= defined(os.path.join(dp, f))
all_supply = set().union(*supply.values())

donor_defs = collections.defaultdict(lambda: collections.defaultdict(set))  # comp -> sym -> donors
for d in prebuild_dirs(R):
    comp = os.path.relpath(os.path.dirname(d), R)
    for m in donors:
        md = os.path.join(d, m)
        if not os.path.isdir(md):
            continue
        for f in os.listdir(md):
            if f.endswith('.o'):
                for s in defined(os.path.join(md, f)):
                    donor_defs[comp][s].add(f'{m}/{f}')

hits = []
for comp, syms in sorted(donor_defs.items()):
    missing = {s for s in syms if s not in all_supply}
    if not missing:
        continue
    cdir = os.path.join(R, comp)
    rx = re.compile(r'\b(' + '|'.join(sorted(map(re.escape, missing))) + r')\s*\(')
    for dp, dn, fn in os.walk(cdir):
        if 'prebuild' in dp:
            continue
        for f in fn:
            if not f.endswith('.c'):
                continue
            path = os.path.join(dp, f)
            for i, line in enumerate(open(path, errors='replace'), 1):
                for m in rx.finditer(line):
                    hits.append((comp, m.group(1), os.path.relpath(path, R), i,
                                 ','.join(sorted(syms[m.group(1)]))))
for h in hits:
    print('\t'.join(map(str, h)))
print(f'# {len(hits)} call sites, {len({(h[0], h[1]) for h in hits})} symbols', file=sys.stderr)
