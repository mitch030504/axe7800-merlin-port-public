#!/usr/bin/env python3
"""Compare the COMPILED code (as built for RT-AXE7800) of rc boot-path functions, stock vs Merlin.

usage: init-path-objcmp.py <objdump> <stock-router-dir> <merlin-router-dir> <names-file>

For each function name, locate the object defining it in each build tree (rc/*.o, shared/*.o,
excluding prebuild copies), disassemble just that function with relocations, and normalise:
drop addresses, raw bytes, PC-relative offsets and local labels; keep mnemonics, operands that
are registers/immediates, and relocation target symbols (local string labels resolved to their
text). Only relocations inside the function's own address range are kept, and branch targets and
literal-pool PC-relative addends are treated as layout. Reports SAME-CODE, DIFFERENT-CODE
(+changed instruction count), or ABSENT (not compiled for this model) per function. The names file
takes the first word of each line.
"""
import os, re, sys, subprocess, glob, difflib
from elftools.elf.elffile import ELFFile

OD, S, M, names_file = sys.argv[1:5]
names = [l.split()[0] for l in open(names_file) if l.strip()]

def objects(root):
    objs = [o for d in ('rc', 'shared') for o in glob.glob(os.path.join(root, d, '*.o'))]
    where = {}
    for o in objs:
        out = subprocess.run(['nm', '--defined-only', o], capture_output=True, text=True).stdout
        for l in out.splitlines():
            p = l.split()
            if len(p) == 3 and p[1] in 'Tt':
                where.setdefault(p[2], o)
    return where


_strcache = {}
def local_strings(obj):
    """Map local data symbols (.LCnnn, __func__.N, .rodata.*) to the bytes they point at, so
    compiler-local label numbering is replaced by the actual string content."""
    if obj in _strcache: return _strcache[obj]
    m = {}
    with open(obj, 'rb') as f:
        e = ELFFile(f)
        st = e.get_section_by_name('.symtab')
        for sym in st.iter_symbols():
            n = sym.name
            if not (n.startswith('.LC') or '__func__' in n or n.startswith('.rodata')): continue
            shn = sym['st_shndx']
            if not isinstance(shn, int): continue
            data = e.get_section(shn).data()
            off = sym['st_value']; end = data.find(b'\0', off)
            m[n] = data[off:end if end >= 0 else len(data)][:80].decode('latin1')
        # section symbols such as .rodata.__func__.17538 are referenced by section name
        for sec in e.iter_sections():
            if sec.name.startswith('.rodata') and sec.name not in m and sec['sh_type'] == 'SHT_PROGBITS':
                data = sec.data(); end = data.find(b'\0')
                m[sec.name] = data[:end if end >= 0 else len(data)][:80].decode('latin1')
    _strcache[obj] = m
    return m

def disasm(obj, fn):
    out = subprocess.run([OD, '-dr', '--no-show-raw-insn', f'--disassemble={fn}', obj],
                         capture_output=True, text=True).stdout
    ins = []
    # binutils 2.32 prints relocations of the whole section with --disassemble=<fn>; keep only
    # those whose offset lies inside the function's own instruction range.
    addrs = [int(a, 16) for a in re.findall(r'^\s+([0-9a-f]+):\s+(?!R_ARM_)', out, re.M)]
    lo, hi = (min(addrs), max(addrs) + 4) if addrs else (0, 0)
    for l in out.splitlines():
        m = re.match(r'\s+([0-9a-f]+):\s+(R_ARM_\w+)\s+(\S+)', l)
        if m and not lo <= int(m.group(1), 16) < hi:
            continue
        if m:                                   # relocation line: keep target symbol
            m = re.match(r'\s+[0-9a-f]+:\s+(R_ARM_\w+)\s+(\S+)', l)
            tgt = m.group(2); base = re.sub(r"[+-]0x[0-9a-f]+$", "", tgt)
            strs = local_strings(obj)
            if base in strs: tgt = 'STR:' + repr(strs[base]) + tgt[len(base):]
            ins.append(f'RELOC {m.group(1)} {tgt}'); continue
        if l.startswith('Disassembly of section') or not l.strip(): continue
        m = re.match(r'\s+[0-9a-f]+:\s+(.*)', l)
        if m:
            t = m.group(1)
            t = re.sub(r'<[^>]*>', '', t)            # symbolic labels
            t = re.sub(r';.*$', '', t).strip()        # comments with addresses
            t = re.sub(r'^(b[a-z.]*\s+)[0-9a-f]+$', r'\1ADDR', t)  # branch targets of any length
            t = re.sub(r'\b[0-9a-f]{3,}\b', 'ADDR', t)  # addresses
            t = re.sub(r'\[pc, #-?\d+\]', '[pc,#OFF]', t)
            ins.append(' '.join(t.split()))
    # a literal-pool word followed by a relocation holds a PC-relative addend: layout, not code
    return ['.word REL' if x.startswith('.word') and i + 1 < len(ins) and ins[i + 1].startswith('RELOC')
            else x for i, x in enumerate(ins)]

ws, wm = objects(S), objects(M)
for n in names:
    a, b = ws.get(n), wm.get(n)
    if not a and not b:
        print(f'{n:40} ABSENT in both (not compiled for this model)'); continue
    if not a or not b:
        print(f'{n:40} ONLY-IN-{"MERLIN" if b else "STOCK"} ({os.path.relpath(b or a, M if b else S)})'); continue
    da, db = disasm(a, n), disasm(b, n)
    if da == db:
        print(f'{n:40} SAME-CODE ({len(da)} insns)')
    else:
        ch = sum(1 for x in difflib.ndiff(da, db) if x[:1] in '+-')
        print(f'{n:40} DIFFERENT-CODE ({ch} changed of {len(da)}/{len(db)} insns)')
