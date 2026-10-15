#!/bin/bash
# inspect-gpl-generation-gaps.sh — READ-ONLY generation-gap inspector for a candidate
# RT-AXE7800 GPL/source package.
#
#   usage: inspect-gpl-generation-gaps.sh <archive|extracted-dir> [--cache <dir>]
#
# COMPLEMENTS tools/verify-asus-gpl-drop.sh, it does not replace it. That tool establishes
# package IDENTITY and P0-P3 supply closure. This one answers the GENERATION questions it has
# no coverage of: the shared/libnvram invalid_* pair, the libwebapi 34-symbol shipping
# contract, and which S46 generation the package belongs to.
#
# Run the identity verifier FIRST. A package that fails identity is not evidence.
#
# GUARANTEES
#   - Never writes to, extracts into, or modifies the supplied package.
#   - Never stages anything into a build tree. Never uses donor binaries.
#   - Never reads embedded credential/API-key VALUES (carrier data symbols are reported by
#     existence and size only).
#   - No network access. No build.
#   - Decompresses the archive at most twice: once for a cached inventory, once for a single
#     targeted extraction of the files it needs.
#
# VERDICTS: PASS | FAIL | INCONCLUSIVE (default; absence alone is never FAIL).
set -uo pipefail

SRC=""; CACHE_DIR="${TMPDIR:-/tmp}/gpl-inspect-cache"
while [ $# -gt 0 ]; do
  case "$1" in
    --cache) CACHE_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) SRC="$1"; shift ;;
  esac
done
[ -n "$SRC" ] || { echo "usage: $(basename "$0") <archive|extracted-dir> [--cache <dir>]"; exit 2; }
[ -e "$SRC" ] || { echo "FATAL: no such path: $SRC"; exit 2; }
SRC=$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")

REPO=$(cd "$(dirname "$0")/.." && pwd)
CONTRACT="$REPO/repro/intake/libwebapi-shipping-contract.txt"
WORK=""; cleanup(){ [ -n "$WORK" ] && rm -rf "$WORK"; }; trap cleanup EXIT INT TERM
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gpl-inspect.XXXXXX")

say(){ printf '%s\n' "$*"; }
row(){ printf '  %-11s %s\n' "$1" "$2"; }

# ---------------------------------------------------------------- inventory (cached once)
say "== package =="
if [ -d "$SRC" ]; then
  MODE=dir; say "  kind    : extracted directory"; say "  path    : $SRC"
  INV="$WORK/inv.txt"; ( cd "$SRC" && find . -type f -o -type l ) | sed 's|^\./||' > "$INV"
else
  MODE=archive
  H=$(sha256sum "$SRC" | cut -d' ' -f1)
  say "  kind    : archive"; say "  file    : $(basename "$SRC")"
  say "  size    : $(stat -c%s "$SRC") bytes"; say "  sha256  : $H"
  say "  NOTE    : ASUS publishes no checksum for GPL packages; this is an acquisition"
  say "            fingerprint, not vendor authentication."
  mkdir -p "$CACHE_DIR"; INV="$CACHE_DIR/$H.inventory"
  if [ -s "$INV" ]; then
    say "  inventory: cached ($(wc -l < "$INV") entries) — archive not re-read"
  else
    say "  inventory: building once (large archives take minutes)…"
    case "$SRC" in
      *.tar.gz|*.tgz)   tar tzf "$SRC" ;; *.tar.bz2|*.tbz2) tar tjf "$SRC" ;;
      *.tar.xz|*.txz)   tar tJf "$SRC" ;; *.tar)            tar tf  "$SRC" ;;
      *.zip)            unzip -Z1 "$SRC" ;;
      *) echo "FATAL: unsupported archive type"; exit 2 ;;
    esac > "$INV" || { echo "FATAL: could not read archive"; rm -f "$INV"; exit 2; }
    say "  inventory: $(wc -l < "$INV") entries (cached at $INV)"
  fi
fi
ROOT=$(head -1 "$INV" | cut -d/ -f1)
say "  root    : ${ROOT:-<none>}"
say "  layout  : $(grep -qE 'prebuild/RT-AXE7800/' "$INV" && echo 'Merlin per-model' || echo 'raw-ASUS flat (or unknown)')"

# collect wanted members, extract ONCE
want(){ grep -E "$1" "$INV" | head -"${2:-4}"; }
NEED="$WORK/need.txt"; : > "$NEED"
want '(^|/)router/rc/Makefile$' 2 >> "$NEED"
want '(^|/)router/rc/rc\.h$' 2 >> "$NEED"
want '(^|/)router/libwebapi/(webapi|priv_webapi)\.c$' 4 >> "$NEED"
want '(^|/)router/libwebapi/.*priv_webapi\.o$' 4 >> "$NEED"
want '(^|/)router/rc/prebuild(/RT-AXE7800)?/(s46comm|s46map_rptd)\.o$' 6 >> "$NEED"
want '(^|/)router/shared/prebuild(/RT-AXE7800)?/.*\.o$' 40 >> "$NEED"
want '(^|/)router/shared/[a-z_]+\.c$' 60 >> "$NEED"
sort -u "$NEED" -o "$NEED"
EX="$WORK/ex"
mkdir -p "$EX"
if [ "$MODE" = dir ]; then
  while read -r m; do [ -n "$m" ] || continue; mkdir -p "$EX/$(dirname "$m")"; cp -p "$SRC/$m" "$EX/$m" 2>/dev/null; done < "$NEED"
else
  case "$SRC" in
    *.tar.gz|*.tgz) tar xzf "$SRC" -C "$EX" -T "$NEED" 2>/dev/null ;;
    *.tar.bz2|*.tbz2) tar xjf "$SRC" -C "$EX" -T "$NEED" 2>/dev/null ;;
    *.tar.xz|*.txz) tar xJf "$SRC" -C "$EX" -T "$NEED" 2>/dev/null ;;
    *.tar) tar xf "$SRC" -C "$EX" -T "$NEED" 2>/dev/null ;;
    *.zip) ( cd "$EX" && xargs -a "$NEED" -d'\n' unzip -qo "$SRC" 2>/dev/null ) ;;
  esac
fi
f(){ find "$EX" -path "*$1" -type f 2>/dev/null | head -1; }

# symbol reader: prefer a cross-nm, fall back to host nm, else strings
NM=$(ls /opt/toolchains/crosstools-arm-gcc-*/usr/bin/*-nm 2>/dev/null | head -1)
[ -n "$NM" ] || NM=$(command -v nm || true)
defsyms(){ [ -n "$NM" ] && "$NM" --defined-only "$1" 2>/dev/null | awk '$2 ~ /^[TDRB]$/ {print $3}' | sort -u; }

# ------------------------------------------------------------------ 1. invalid_* pair
say ""; say "== 1. shared / libnvram private ABI =="
IPAIR="invalid_nvram_get_program invalid_program_check"
for s in $IPAIR; do
  SRCHIT=$(grep -rl "^[A-Za-z_].*\b$s[[:space:]]*(" "$EX" --include='*.c' 2>/dev/null | head -1)
  OBJHIT=""
  for o in $(find "$EX" -path '*shared/prebuild*' -name '*.o' 2>/dev/null); do
    defsyms "$o" | grep -qx "$s" && { OBJHIT="$o"; break; }
  done
  if [ -n "$SRCHIT" ]; then row "PASS" "$s — source definition in $(basename "$SRCHIT")"
  elif [ -n "$OBJHIT" ]; then row "PASS" "$s — authentic prebuilt defines it: $(basename "$OBJHIT") (sha256 $(sha256sum "$OBJHIT"|cut -c1-16))"
  else row "INCONCLUSIVE" "$s — no source definition and no shared/prebuild object defines it"; fi
done
say "  consumer of record: prebuilt libnvram.so; stock 388_25206 /lib/libnvram.so imports both."

# ------------------------------------------------------------------ 2. libwebapi
say ""; say "== 2. libwebapi (LIBWEBAPI-A) =="
grep -qE '(^|/)router/libwebapi/' "$INV" && row "present" "router/libwebapi/ in index" || row "INCONCLUSIVE" "router/libwebapi/ not in index — confirm layout before concluding"
W_C=$(f /libwebapi/webapi.c); P_C=$(f /libwebapi/priv_webapi.c); P_O=$(find "$EX" -path '*libwebapi*' -name 'priv_webapi.o' 2>/dev/null | head -1)
[ -n "$W_C" ] && row "present" "webapi.c" || row "absent" "webapi.c"
if [ -n "$P_C" ]; then row "PASS" "priv_webapi.c source supplied"
elif [ -n "$P_O" ]; then row "PASS" "priv_webapi.o supplied ($(stat -c%s "$P_O") B, sha256 $(sha256sum "$P_O"|cut -c1-16))"
else row "INCONCLUSIVE" "no priv_webapi source or object located"; fi
if [ -s "$CONTRACT" ]; then
  grep -v '^#' "$CONTRACT" | awk 'NF{print $1}' | sort -u > "$WORK/contract.txt"
  N=$(wc -l < "$WORK/contract.txt")
  : > "$WORK/have.txt"
  [ -n "$P_O" ] && defsyms "$P_O" >> "$WORK/have.txt"
  # Column-0 function definitions, with or without the return type on the same line
  # ("b64_decode(" and "int set_app_mnt(char *x)"); prototypes ending in ';' are excluded.
  for c in $W_C $P_C; do [ -n "$c" ] && grep -E '^[A-Za-z_][A-Za-z0-9_[:space:]*]*\(' "$c" 2>/dev/null \
    | grep -vE ';[[:space:]]*$' | sed -E 's/[[:space:]]*\(.*//; s/.*[^A-Za-z0-9_]//' >> "$WORK/have.txt"; done
  grep -v '^#' "$CONTRACT" | awk '$2=="OPEN"{print $1}' >> "$WORK/have.txt"
  sort -u "$WORK/have.txt" -o "$WORK/have.txt"
  MISS=$(comm -23 "$WORK/contract.txt" "$WORK/have.txt")
  M=$(printf '%s\n' "$MISS" | grep -c . || true)
  if [ "$M" = 0 ]; then row "PASS" "all $N shipping-contract symbols accounted for"
  else row "INCONCLUSIVE" "$M of $N contract symbols unaccounted for:"; printf '%s\n' "$MISS" | sed 's/^/                  /'; fi
else row "INCONCLUSIVE" "contract baseline missing: $CONTRACT"; fi
say "  Acceptance is the 34-symbol SAME-MODEL shipping contract, never another model's ABI."

# ------------------------------------------------------------------ 3. S46 generation
say ""; say "== 3. S46 generation (version numbers prove nothing) =="
RCMK=$(f /router/rc/Makefile); RCH=$(f /router/rc/rc.h)
GEN="UNDETERMINED"
if [ -n "$RCMK" ]; then
  grep -q 's46comm\.o' "$RCMK" && GEN="s46comm"
  grep -q 's46map_rptd\.o' "$RCMK" && { [ "$GEN" = s46comm ] && GEN="MIXED" || GEN="s46map_rptd"; }
  row "rc/Makefile" "s46comm=$(grep -c 's46comm\.o' "$RCMK")  s46map_rptd=$(grep -c 's46map_rptd\.o' "$RCMK")"
else row "INCONCLUSIVE" "rc/Makefile not located"; fi
if [ -n "$RCH" ]; then
  NEWA=0; OLDA=0
  for s in wan46det wan_hgw_detect get_s46_ra get_s46_prefix_host s46reset; do grep -q "\b$s\b" "$RCH" && NEWA=$((NEWA+1)); done
  for s in s46_jpne_hgw s46_jpne_maprules s46_jpne_report s46map_rptd_main check_s46map_rptd; do grep -q "\b$s\b" "$RCH" && OLDA=$((OLDA+1)); done
  row "rc/rc.h" "s46comm-generation API $NEWA/5   s46map_rptd-generation API $OLDA/5"
else row "INCONCLUSIVE" "rc/rc.h not located"; fi
SC=$(find "$EX" -name 's46comm.o' 2>/dev/null | head -1); SM=$(find "$EX" -name 's46map_rptd.o' 2>/dev/null | head -1)
[ -n "$SC" ] && row "supply" "s46comm.o present ($(stat -c%s "$SC") B, sha256 $(sha256sum "$SC"|cut -c1-16))"
[ -n "$SM" ] && row "supply" "s46map_rptd.o present ($(stat -c%s "$SM") B, sha256 $(sha256sum "$SM"|cut -c1-16))"
for o in $SC $SM; do
  [ -n "$NM" ] || continue
  D=$("$NM" -S --defined-only "$o" 2>/dev/null | grep -E ' D (JPNE_MF_CODE|JPIX_MF_CODE|OCN_API_KEY)$' | awk '{print $4"="strtonum("0x"$2)"B"}' | tr '\n' ' ')
  [ -n "$D" ] && row "carrier" "$(basename "$o"): $D  (existence/size only — values never read)"
done
case "$GEN:$SC" in
  s46comm:?*) row "PASS" "s46comm generation AND s46comm.o supplied" ;;
  s46comm:)   row "INCONCLUSIVE" "s46comm generation but no s46comm.o located" ;;
  s46map_rptd:*) row "FAIL" "s46map_rptd generation — same mismatch as GPL 388.34458" ;;
  *) row "INCONCLUSIVE" "generation undetermined ($GEN) — report the observed API set verbatim" ;;
esac

say ""; say "== summary =="
say "  Identity is NOT established here. Run tools/verify-asus-gpl-drop.sh and record"
say "  repro/intake/PACKAGE-PROVENANCE-CHECKLIST.md before treating any verdict as evidence."
say "  Absence alone is INCONCLUSIVE, never FAIL."
