#!/usr/bin/env python3
"""Runtime ABI closure of a firmware root filesystem (read-only).

usage: rootfs-abi-closure.py <rootfs-dir> [--readelf <readelf>]

Models the dynamic loader: for every dynamically linked EXECUTABLE (ET_EXEC/PIE with an
interpreter), load its transitive DT_NEEDED closure (standard lib dirs plus in-rootfs
RUNPATH/RPATH) together with the interpreter, and require that every undefined, non-weak
dynamic symbol imported by the executable OR by any library in that closure is defined
somewhere in the closure (global scope). Shared libraries are therefore judged in the context
of the programs that load them, since under-linked .so files are normal. dlopen()ed plugins
are outside this model.

Exit 0 when nothing is unresolved, 1 otherwise. Output: one line per unresolved symbol and a
summary. Missing sonames are reported separately.
"""
import os, re, subprocess, sys, collections

root = sys.argv[1].rstrip('/')
readelf = 'readelf'
if '--readelf' in sys.argv:
    readelf = sys.argv[sys.argv.index('--readelf') + 1]
LIBDIRS = ['/lib', '/usr/lib', '/lib32', '/usr/lib32', '/usr/local/lib']

def is_elf(p):
    try:
        with open(p, 'rb') as f:
            return f.read(4) == b'\x7fELF'
    except OSError:
        return False

def dyn(p):
    out = subprocess.run([readelf, '-d', '-W', p], capture_output=True, text=True).stdout
    needed = re.findall(r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]', out)
    rpaths = re.findall(r'\((?:RUNPATH|RPATH)\)\s+Library (?:runpath|rpath): \[([^\]]+)\]', out)
    return needed, [d for r in rpaths for d in r.split(':')], ('Dynamic section at offset' in out)

def syms(p):
    out = subprocess.run([readelf, '--dyn-syms', '-W', p], capture_output=True, text=True).stdout
    und, dfn = set(), set()
    for l in out.splitlines():
        f = l.split()
        if len(f) < 8 or not f[0].rstrip(':').isdigit():
            continue
        bind, ndx, name = f[4], f[6], f[7].split('@')[0]
        if not name:
            continue
        if ndx == 'UND':
            if bind != 'WEAK':
                und.add(name)
        elif bind in ('GLOBAL', 'WEAK', 'GNU_UNIQUE'):
            dfn.add(name)
    return und, dfn

files = []
for dp, dn, fn in os.walk(root):
    for f in fn:
        p = os.path.join(dp, f)
        if not os.path.islink(p) and is_elf(p):
            files.append(p)

info = {}
for p in files:
    needed, rp, isdyn = dyn(p)
    if not isdyn:
        continue
    u, d = syms(p)
    info[p] = (needed, rp, u, d)

def resolve(soname, rpaths):
    for d in rpaths + LIBDIRS:
        c = root + d + '/' + soname
        if os.path.exists(c):
            return os.path.realpath(c)
    return None

def interp(p):
    out = subprocess.run([readelf, '-l', '-W', p], capture_output=True, text=True).stdout
    m = re.search(r'Requesting program interpreter: ([^\]]+)\]', out)
    return m.group(1) if m else None

missing_so = collections.defaultdict(set)
unresolved = collections.defaultdict(set)
for p, (needed, rp, und, dfn) in info.items():
    ip = interp(p)
    if ip is None:
        continue                      # shared object: judged via the executables that load it
    closure = [p]
    ld = os.path.realpath(root + ip) if os.path.exists(root + ip) else None
    if ld in info:
        closure.append(ld)
    seen, queue = set(closure), list(needed)
    while queue:
        so = queue.pop()
        r = resolve(so, rp)
        if r is None:
            missing_so[so].add(os.path.relpath(p, root)); continue
        if r in seen or r not in info:
            continue
        seen.add(r); closure.append(r); queue.extend(info[r][0])
    provided = set().union(*(info[c][3] for c in closure))
    for c in closure:
        for s in info[c][2] - provided:
            unresolved[os.path.relpath(c, root)].add(s)

for so, users in sorted(missing_so.items()):
    print(f'MISSING-SONAME\t{so}\t{",".join(sorted(users)[:5])}')
for f, ss in sorted(unresolved.items()):
    for s in sorted(ss):
        print(f'UNRESOLVED\t{f}\t{s}')
n = sum(len(v) for v in unresolved.values())
print(f'# dynamic ELFs: {len(info)}; unresolved symbols: {n} in {len(unresolved)} files; '
      f'missing sonames: {len(missing_so)}', file=sys.stderr)
sys.exit(1 if n or missing_so else 0)
