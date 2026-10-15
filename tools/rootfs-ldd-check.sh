#!/bin/bash
# rootfs-ldd-check.sh — run `ldd -r` semantics on every dynamic ELF of an ARM rootfs, using the
# rootfs's OWN dynamic loader under qemu-arm user-mode emulation (read-only on the rootfs).
#
#   usage: rootfs-ldd-check.sh <rootfs-dir>      (run inside tools/build-env/Dockerfile.verify)
#
# LD_TRACE_LOADED_OBJECTS + LD_BIND_NOW + LD_WARN makes glibc's ld.so map every DT_NEEDED
# library, perform ALL relocations (functions and data, including symbol VERSION checks) and print
# a line for each failure, without running the program. This is what the router's loader does.
# Output (tab-separated): NOTFOUND <elf> <lib> | UNDEF <elf> <symbol> | VERSION <elf> <message>
set -uo pipefail
FS="$(cd "${1:?rootfs}" && pwd)"
LD=$(cd "$FS" && ls lib/ld-linux*.so* 2>/dev/null | head -1)
[ -n "$LD" ] || { echo "FATAL: no lib/ld-linux*.so* in $FS" >&2; exit 2; }
n=0; bad=0
while IFS= read -r -d '' f; do
  rel="/${f#$FS/}"
  head -c4 "$f" | grep -q $'\x7fELF' || continue
  # programs only: loading a program resolves its whole DT_NEEDED closure together, as on the
  # router; shared objects checked alone report normal under-linking.
  readelf -l "$f" 2>/dev/null | grep -q 'Requesting program interpreter' || continue
  n=$((n+1))
  out=$(timeout 60 qemu-arm-static -L "$FS" \
        -E LD_TRACE_LOADED_OBJECTS=1 -E LD_BIND_NOW=1 -E LD_WARN=1 -E LD_LIBRARY_PATH=/lib:/usr/lib \
        "$FS/$LD" "$rel" 2>&1)
  rc=$?
  echo "$out" | sed -n 's/^\s*\(\S\+\) => not found.*/NOTFOUND\t'"${rel//\//\\/}"'\t\1/p'
  echo "$out" | sed -n 's/^undefined symbol: \([^ \t]\+\).*/UNDEF\t'"${rel//\//\\/}"'\t\1/p'
  echo "$out" | grep -E "version .* not (found|defined)" | sed "s|^|VERSION\t$rel\t|"
  if [ $rc -ne 0 ] && ! echo "$out" | grep -q '=>\|statically linked'; then
    echo -e "LOADFAIL\t$rel\trc=$rc $(echo "$out" | head -1 | cut -c1-120)"
  fi
done < <(find "$FS" -type f -print0 | LC_ALL=C sort -z)
echo "# dynamic programs checked: $n" >&2
