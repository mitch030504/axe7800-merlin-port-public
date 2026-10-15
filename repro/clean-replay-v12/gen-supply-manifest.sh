#!/bin/bash
# Generate the authentic-supply manifest for clean-replay-v12.
#
#   usage: gen-supply-manifest.sh <gpl-root> <merlin-pin-worktree> > supply-manifest.tsv
#
#   <gpl-root>             extracted GPL_RT-AXE7800_3.0.0.4.388.25206-gcaa73b5.tgz (contains release/)
#   <merlin-pin-worktree>  pristine asuswrt-merlin.ng worktree at the v12 pin
#
# Read-only on both inputs. Every row maps one GPL file to its Merlin destination:
#   F <sha256> <size> <gpl-path> <merlin-path>     regular file
#   L <link-target> - <gpl-path> <merlin-path>    symlink (recreated verbatim)
#
# Categories (column 6):
#   RSD   GPL src-rt/router-sysdep/**           -> router-sysdep.rt-axe7800/**  (Merlin swaps it in per model)
#   DRV   GPL bcmdrivers ELF objects that the Merlin pin lacks or has built for another chip
#   HOST  GPL hostTools/prebuilt/*              -> per-model (lzop, addvtoken) or flat, per Merlin's hostTools/Makefile
#   DNGL  GPL dongle/sysdeps/default/**        -> dongle/sysdeps/RT-AXE7800/** (radio firmware stock uses)
#   BOOT  GPL bootloaders/obj/**             -> bootloaders/obj.rt-axe7800/** (Merlin layout)
#   HNDX  GPL src/router/hnd_extra/prebuilt/** -> router-sysdep.rt-axe7800/hnd_extra/prebuilt/** (Merlin layout)
#   PB    GPL src/router/**/prebuild|prebuilt/* -> .../prebuild|prebuilt/RT-AXE7800/*
#   MODEL GPL src/router files whose path names RT-AXE7800 and are absent from Merlin
set -euo pipefail
G="$(cd "${1:?gpl-root}" && pwd)/release"
M="$(cd "${2:?merlin-worktree}" && pwd)/release"
[ -d "$G/src-rt-5.04axhnd.675x" ] || { echo "FATAL: not a GPL root: $1" >&2; exit 2; }
[ -d "$M/src-rt-5.04axhnd.675x" ] || { echo "FATAL: not a Merlin worktree: $2" >&2; exit 2; }
H=src-rt-5.04axhnd.675x
R=src/router

row(){ # $1=category $2=gpl-rel $3=merlin-rel
  local s="$G/$2"
  if [ -L "$s" ]; then printf 'L\t%s\t-\t%s\t%s\t%s\n' "$(readlink "$s")" "$2" "$3" "$1"
  else printf 'F\t%s\t%s\t%s\t%s\t%s\n' "$(sha256sum "$s" | cut -d' ' -f1)" "$(stat -c%s "$s")" "$2" "$3" "$1"; fi
}

echo "# clean-replay-v12 supply manifest — GPL 3.0.0.4.388.25206-gcaa73b5"
echo "# tgz sha256 1ed8272456e5a6392e2df210a83e0df5e93be7b05dc11550013d8d311e89c019"
echo "# merlin pin $(git -C "$2" rev-parse HEAD)"
echo "# type	sha256|target	size	gpl-path	merlin-path	category"

( cd "$G" && find "$H/router-sysdep" \( -type f -o -type l \) | LC_ALL=C sort ) | while read -r f; do
  row RSD "$f" "$H/router-sysdep.rt-axe7800/${f#$H/router-sysdep/}"; done

( cd "$G" && find "$H/bcmdrivers" -type f | LC_ALL=C sort ) | while read -r f; do
  head -c4 "$G/$f" | grep -q $'\x7fELF' || continue
  if [ ! -e "$M/$f" ] || ! cmp -s "$G/$f" "$M/$f"; then row DRV "$f" "$f"; fi
done

# Merlin's hostTools/Makefile reads lzop (and addvtoken) from prebuilt/$(BUILD_NAME)/ and the rest
# flat from prebuilt/. Per-model where Merlin keeps a per-model copy for another model; otherwise
# flat, and only when Merlin's flat copy is absent or different.
( cd "$G" && find "$H/hostTools/prebuilt" -maxdepth 1 -type f | LC_ALL=C sort ) | while read -r f; do
  b=$(basename "$f")
  if ls "$M/$H/hostTools/prebuilt"/*/"$b" >/dev/null 2>&1; then row HOST "$f" "$H/hostTools/prebuilt/RT-AXE7800/$b"
  elif [ ! -e "$M/$f" ] || ! cmp -s "$G/$f" "$M/$f"; then row HOST "$f" "$f"; fi
done

# 6715b0/43684 dongle firmware: the stock 25206 build installs the GPL's sysdeps/default copy; Merlin
# would otherwise install ITS default (same version string, different bytes, newer generation).
# Merlin's Makefile prefers dongle/sysdeps/$(BUILD_NAME)/<chip>/, so map default -> RT-AXE7800.
DG="$H/bcmdrivers/broadcom/net/wl/impl87/sys/src/dongle/sysdeps"
( cd "$G" && find "$DG/default" -type f | LC_ALL=C sort ) | while read -r f; do
  row DNGL "$f" "$DG/RT-AXE7800/${f#$DG/default/}"; done

# Bootloader objects: Merlin's bootloaders/Makefile copies obj.<lowercase model>/* over obj/;
# ASUS ships the model's set directly in obj/.
( cd "$G" && find "$H/bootloaders/obj" -type f | LC_ALL=C sort ) | while read -r f; do
  row BOOT "$f" "$H/bootloaders/obj.rt-axe7800/${f#$H/bootloaders/obj/}"; done

# Merlin keeps ONE hnd_extra/prebuilt per model inside router-sysdep.<model>/; platform.mak
# copies the chip objects and wlc_types.h out of $(TOP_PLATFORM)/hnd_extra/prebuilt. ASUS
# splits the same set between router-sysdep/ and src/router/hnd_extra/ (no name overlap).
( cd "$G" && find "$R/hnd_extra/prebuilt" \( -type f -o -type l \) | LC_ALL=C sort ) | while read -r f; do
  row HNDX "$f" "$H/router-sysdep.rt-axe7800/hnd_extra/prebuilt/${f#$R/hnd_extra/prebuilt/}"; done

( cd "$G" && find "$R" \( -path "$R/hnd_extra" -o -path "$R/prebuilt" \) -prune -o \
    \( -type f -o -type l \) \( -path '*/prebuild/*' -o -path '*/prebuilt/*' \) -print | LC_ALL=C sort ) |
while read -r f; do
  d=$(echo "$f" | sed -E 's#^(.*/prebuil[dt])/.*#\1#'); rest=${f#$d/}
  row PB "$f" "$d/RT-AXE7800/$rest"
done

( cd "$G" && find "$R" \( -type f -o -type l \) | grep -iE 'rt-axe7800|rtaxe7800|rt_axe7800' | LC_ALL=C sort ) |
while read -r f; do
  [ -e "$M/$f" ] || [ -L "$M/$f" ] || row MODEL "$f" "$f"; done
