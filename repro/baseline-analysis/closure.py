#!/usr/bin/env python3
"""Prebuilt link/ABI closure: GPL 25206 prebuilts vs open-source definitions in candidate trees.

usage: closure.py <gpl-release-dir> <merlin-git-dir> <outdir> <label>=<ref> [...]

For every 25206 prebuilt consumer we collect the symbols it IMPORTS:
  link-time : relocatable .o under release/src/router/*/prebuild/ (nm -u)
  run-time  : ELF executables / .so under release/src/router/*/prebuild/ (dynamic undefined)
A symbol is "open-provided in GPL" when a column-0, non-static C definition of it exists in the
GPL's own release/src/router sources. Those are exactly the symbols a Merlin tree must also
define. For each candidate we report which of them its sources do NOT define.
"""
import os, re, subprocess, sys, json, collections

gpl, gitdir, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
cands = [a.split('=', 1) for a in sys.argv[4:]]
os.makedirs(outdir, exist_ok=True)
ROUTER = os.path.join(gpl, 'src/router')

FUNC_RE = re.compile(r'^(?!static\b|extern\b|typedef\b|#|return\b|if\b|else\b|while\b|for\b|switch\b)'
                     r'[A-Za-z_][A-Za-z0-9_ \t\*]*?\b([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(')
KR_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(')
VAR_RE = re.compile(r'^(?!static\b|extern\b|typedef\b|#|struct\s+\w+\s*\{|enum\b|union\b)'
                    r'[A-Za-z_][A-Za-z0-9_ \t\*]*?\b([A-Za-z_][A-Za-z0-9_]*)[ \t]*(\[[^\]]*\])*[ \t]*(=|;)')

def names_from_lines(lines):
    out = set()
    for ln in lines:
        s = ln.rstrip('\n')
        if not s or s[0] in ' \t{}/#*':
            continue
        if s.rstrip().endswith(';') and '(' in s:
            continue  # prototype
        m = FUNC_RE.match(s) or KR_RE.match(s)
        if m:
            out.add(m.group(1)); continue
        m = VAR_RE.match(s)
        if m:
            out.add(m.group(1))
    return out

def defs_dir(root):
    out = set()
    for dp, dn, fn in os.walk(root):
        if '/prebuild' in dp:
            continue
        for f in fn:
            if f.endswith(('.c', '.cpp', '.cc')):
                try:
                    with open(os.path.join(dp, f), errors='replace') as fh:
                        out |= names_from_lines(fh)
                except OSError:
                    pass
    return out

def defs_git(ref):
    p = subprocess.run(['git', '--git-dir', gitdir, 'grep', '-hI', '-E', r'^[A-Za-z_]', ref, '--',
                        'release/src/router/*.c', 'release/src/router/*.cpp', 'release/src/router/*.cc'],
                       capture_output=True, text=True, errors='replace')
    return names_from_lines(p.stdout.splitlines())

def nm(args, path):
    p = subprocess.run(['nm'] + args + [path], capture_output=True, text=True, errors='replace')
    return p.stdout.splitlines()

def is_elf(path):
    try:
        with open(path, 'rb') as fh:
            return fh.read(4) == b'\x7fELF'
    except OSError:
        return False

# ---- consumers
consumers = {}
for comp in sorted(os.listdir(ROUTER)):
    pb = os.path.join(ROUTER, comp, 'prebuild')
    if not os.path.isdir(pb):
        continue
    for dp, dn, fn in os.walk(pb):
        for f in fn:
            path = os.path.join(dp, f)
            if os.path.islink(path) or not is_elf(path):
                continue
            rel = os.path.relpath(path, ROUTER)
            ftype = subprocess.run(['file', '-b', path], capture_output=True, text=True).stdout
            if 'ARM' not in ftype or '32-bit' not in ftype:
                continue
            if 'relocatable' in ftype:
                und = {l.split()[-1] for l in nm(['-u'], path) if l.strip()}
                dfn = {l.split()[-1] for l in nm(['--defined-only', '-g'], path) if l.strip()}
                consumers[rel] = ('link', und, dfn)
            else:
                und = {l.split()[-1].split('@')[0] for l in nm(['-D', '-u'], path) if l.strip()}
                dfn = {l.split()[-1].split('@')[0] for l in nm(['-D', '--defined-only'], path) if l.strip()}
                consumers[rel] = ('run', und, dfn)

prebuilt_defined = set()
for kind, und, dfn in consumers.values():
    prebuilt_defined |= dfn

gpl_defs = defs_dir(ROUTER)
need = collections.defaultdict(set)   # symbol -> consumers
for rel, (kind, und, dfn) in consumers.items():
    for s in und:
        if s in prebuilt_defined:
            continue
        need[s].add(rel)
open_needed = {s for s in need if s in gpl_defs}
summary = {'consumers': len(consumers),
           'link_consumers': sum(1 for v in consumers.values() if v[0] == 'link'),
           'run_consumers': sum(1 for v in consumers.values() if v[0] == 'run'),
           'imported_symbols_not_from_prebuilts': len(need),
           'open_provided_in_gpl': len(open_needed),
           'candidates': {}}

for label, ref in cands:
    d = defs_git(ref)
    missing = sorted(s for s in open_needed if s not in d)
    by_cons = collections.defaultdict(list)
    for s in missing:
        for c in need[s]:
            by_cons[c].append(s)
    summary['candidates'][label] = {'ref': ref, 'missing': len(missing)}
    with open(os.path.join(outdir, f'missing-{label}.txt'), 'w') as fh:
        for s in missing:
            fh.write(f"{s}\t{','.join(sorted(need[s]))}\n")

with open(os.path.join(outdir, 'open-needed.txt'), 'w') as fh:
    for s in sorted(open_needed):
        fh.write(f"{s}\t{','.join(sorted(need[s]))}\n")
json.dump(summary, open(os.path.join(outdir, 'summary.json'), 'w'), indent=1)
print(json.dumps(summary, indent=1))
