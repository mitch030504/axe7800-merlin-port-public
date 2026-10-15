#!/bin/bash
# RT-AXE7800 clean replay v12 — Asuswrt-Merlin 3004.388 + authentic ASUS GPL 388.25206 supply.
#
#   usage: replay.sh <fresh-merlin-worktree> <gpl-root>
#
#   <fresh-merlin-worktree>  asuswrt-merlin.ng worktree at MERLIN_PIN, git status empty
#   <gpl-root>               extracted GPL_RT-AXE7800_3.0.0.4.388.25206-gcaa73b5.tgz
#                            (the directory that contains release/). Read-only here.
#
# One pass: pin -> model integration -> manifest-verified GPL supply -> patches -> assertions.
# Deliberately NOT done: no synthetic/stub objects, no donor binaries from other models or
# forks, no feature disabling beyond Merlin's standard per-model deltas, nothing flashed.
set -euo pipefail
WT="$(cd "${1:?usage: replay.sh <fresh-merlin-worktree> <gpl-root>}" && pwd)"
GPL="$(cd "${2:?usage: replay.sh <fresh-merlin-worktree> <gpl-root>}" && pwd)"
MERLIN_PIN=f94f6ff8ad96f7366847103e13e69bbd2e651165
RP="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$RP/supply-manifest.tsv"
log(){ printf '  %s\n' "$*"; }

cd "$WT"
echo "== A: preflight =="
[ "$(git rev-parse HEAD)" = "$MERLIN_PIN" ] || { echo "FATAL: worktree not at Merlin pin $MERLIN_PIN"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "FATAL: worktree not pristine"; exit 1; }
[ -d "$GPL/release/src-rt-5.04axhnd.675x" ] || { echo "FATAL: not a GPL root: $GPL"; exit 1; }
grep -q '^EXTENDNO=25206-gcaa73b5$' "$GPL/release/src/router/extendno.conf" \
  || { echo "FATAL: GPL tree is not 388.25206-gcaa73b5"; exit 1; }
[ -f "$MANIFEST" ] || { echo "FATAL: committed supply manifest missing"; exit 1; }
log "pin OK, pristine OK, GPL 25206-gcaa73b5 OK, manifest OK"

echo "== B: model integration =="
for p in "$RP"/patches/0001-*.patch; do git apply "$p"; log "$(basename "$p")"; done

echo "== C: authentic GPL supply, manifest-verified =="
nf=0; nl=0; declare -A bycat=()
while IFS=$'\t' read -r typ h sz src dst cat; do
  case "$typ" in \#*|"") continue;; esac
  s="$GPL/release/$src"; d="release/$dst"
  mkdir -p "$(dirname "$d")"
  if [ "$typ" = F ]; then
    [ -f "$s" ] && [ ! -L "$s" ] || { echo "FATAL: GPL file missing: $src"; exit 1; }
    [ "$(sha256sum "$s" | cut -d' ' -f1)" = "$h" ] || { echo "FATAL: sha256 mismatch: $src"; exit 1; }
    rm -f "$d"; cp -p "$s" "$d"; chmod u+w "$d"; nf=$((nf+1))
  elif [ "$typ" = L ]; then
    [ "$(readlink "$s")" = "$h" ] || { echo "FATAL: symlink target mismatch: $src"; exit 1; }
    rm -f "$d"; ln -s "$h" "$d"; nl=$((nl+1))
  else echo "FATAL: bad manifest row: $typ"; exit 1; fi
  bycat[$cat]=$(( ${bycat[$cat]:-0} + 1 ))
done < "$MANIFEST"
log "staged $nf files + $nl symlinks, every file sha256-verified against the committed manifest"
for c in RSD DRV HOST DNGL BOOT HNDX PB MODEL; do log "  $c: ${bycat[$c]:-0}"; done

echo "== D: source adaptation patches =="
for p in "$RP"/patches/0[0-9][0-9][0-9]-*.patch; do
  case "$(basename "$p")" in 0001-*) continue;; esac
  git apply "$p"; log "$(basename "$p")"
done

echo "== E: assertions =="
ST=$(sed -e ':a' -e '/\\$/N; s/\\\n//; ta' release/src-rt/target.mak | grep -E '^export RT-AXE7800 \+= ')
for tok in 'BUILD_NAME="RT-AXE7800"' 'DHDAP=y' 'HND_WL=y' 'SWITCH2="BCM53134"' 'DHD_6715B0=y'; do
  echo "$ST" | grep -qF -- "$tok" || { echo "FATAL: stanza token missing: $tok"; exit 1; }
done
log "target stanza tokens OK"
[ "$(git grep -l 'synthetic-empty-diagnostic' -- release 2>/dev/null | wc -l)" = 0 ] \
  && [ -z "$(grep -rl 'synthetic-empty-diagnostic' release/src/router/*/prebuild/RT-AXE7800 2>/dev/null)" ] \
  || { echo "FATAL: synthetic diagnostic marker present"; exit 1; }
log "synthetic marker scan: 0"
n_sh=$(ls release/src/router/shared/prebuild/RT-AXE7800/*.o | wc -l)
n_rc=$(ls release/src/router/rc/prebuild/RT-AXE7800/*.o | wc -l)
[ "$n_sh" = 17 ] || { echo "FATAL: shared supply $n_sh != 17"; exit 1; }
log "shared supply = 17, rc supply = $n_rc"
nm --defined-only release/src/router/shared/prebuild/RT-AXE7800/spwenc.o | grep -q ' T invalid_nvram_get_program$' \
  && nm --defined-only release/src/router/shared/prebuild/RT-AXE7800/spwenc.o | grep -q ' T invalid_program_check$' \
  || { echo "FATAL: invalid_* pair not supplied"; exit 1; }
[ -f release/src/router/libwebapi/prebuild/RT-AXE7800/priv_webapi.o ] || { echo "FATAL: priv_webapi.o not supplied"; exit 1; }
[ -f release/src/router/rc/prebuild/RT-AXE7800/s46comm.o ] || { echo "FATAL: s46comm.o not supplied"; exit 1; }
log "gap closures present: invalid_* (spwenc.o), priv_webapi.o, s46comm.o"
echo "REPLAY v12 COMPLETE"
