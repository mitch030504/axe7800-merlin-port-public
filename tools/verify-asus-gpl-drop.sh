#!/bin/bash
# verify-asus-gpl-drop.sh — READ-ONLY verifier for an ASUS GPL drop (RT-AXE7800 / BCM6756, ARM32)
#
#   usage: verify-asus-gpl-drop.sh <archive|extracted-directory>
#   archives: .tar.gz .tgz .tar.bz2 .tbz2 .tar.xz .txz .tar .zip
#
# Never writes to, extracts into, or modifies the supplied package. When bytes must be
# inspected a COPY is extracted to a mktemp dir removed on EXIT/INT/TERM. No network access.
#
# Exit codes
#   0  every CURRENT_REQUIRED_P0 build input satisfied (valid ARM32 object OR acceptable source)
#   1  one or more CURRENT_REQUIRED_P0 inputs missing / wrong architecture
#   2  unsupported or malformed input
#   3  internal tool failure
#   4  package contains absolute or traversing paths (refused before extraction)
#
# Statuses: PRESENT | MISSING | WRONG ARCH | SOURCE AVAILABLE | UNKNOWN
set -euo pipefail

SRC="${1:-}"
[ -n "$SRC" ] || { echo "usage: $0 <asus-gpl-archive-or-directory>"; exit 2; }
[ -e "$SRC" ] || { echo "FATAL: no such path: $SRC"; exit 2; }

WANT_ARCH_RE='ELF 32-bit.*ARM'
# Known-stock RT-AXE7800 6715b0 dongle firmware (from verified 3.0.0.4.388_25206).
# Informational only - never affects the exit code.
RUNTIME_FW_PATH_RE='(^|/)dongle/sysdeps/RT-AXE7800/6715b0/rtecdc\.bin$'
RUNTIME_FW_STOCK_SHA256='d4c760d14b4d953df716f6787af5f9b94d311c75143bc2a3521af29a9a7eca81' 

# Objects the CURRENT verified RT-AXE7800 configuration actually requires.
CURRENT_REQUIRED_P0="api-broadcom.o tcode.o amas_utils.o private.o"
# Shipped for both BCM6756 models but NOT reached by the current config (feature-gated).
FEATURE_GATED_EXPECTED="uu_utils.o notify_ahs.o amas_wgn_shared.o spwenc.o"
# Present only in the BCM4912 (GT-AX6000) donor; absent from BOTH BCM6756 17-object sets.
# Informational only - never affects the exit code.
NON_6756_OPTIONAL="amas_apg_shared.o"
# Full BCM6756-style shared/prebuild inventory (as shipped for RT-AX58U_V2 / TUF-AX3000_V2).
FULL_6756_SET="amas_dwb.o amas_utils.o amas_wgn_shared.o api-broadcom.o bcmutils.o \
bcmwifi_channels.o bcmxtlv.o ethctl_cmd.o ethswctl.o notify_ahs.o notify_rc.o nvpriv.o \
private.o shutils_private.o spwenc.o tcode.o uu_utils.o"

# Path-QUALIFIED acceptable source alternatives. A bare basename match is NOT sufficient:
# e.g. shared/sysdeps/lantiq/private.c and shared/sysdeps/qca/private.c exist tree-wide but are
# other-platform implementations and must never satisfy the Broadcom RT-AXE7800 private.o.
# Format: "<object>|<anchored-regex-of-acceptable-path>"
SRC_ALT_QUALIFIED="
api-broadcom.o|(^|/)release/src/router/shared/sysdeps/api-broadcom\.c$
amas_utils.o|(^|/)release/src/router/shared/amas_utils\.c$
tcode.o|(^|/)release/src/router/shared/tcode\.c$
uu_utils.o|(^|/)release/src/router/shared/uu_utils\.c$
"
# Objects with NO trustworthy published Broadcom source path. Any candidate is reported as
# SOURCE CANDIDATE - NEEDS REVIEW and is NEVER counted as satisfying the requirement.
NO_TRUSTED_SRC_PATH="private.o"
# Paths explicitly rejected as other-platform implementations.
SRC_REJECT_RE="(^|/)release/src/router/shared/sysdeps/(lantiq|qca|ralink|realtek|alpine)/"

TMP=""; INDEX=""
cleanup(){ [ -n "${TMP:-}" ] && rm -rf -- "$TMP"; [ -n "${INDEX:-}" ] && rm -f -- "$INDEX"; return 0; }
trap cleanup EXIT INT TERM

echo "=============================================================="
echo " ASUS GPL drop verifier — RT-AXE7800 / BCM6756 (ARM32)"
echo " package : $SRC"
echo " mode    : READ-ONLY (package is never modified)"
echo "=============================================================="

INDEX=$(mktemp) || { echo "FATAL: mktemp failed"; exit 3; }
KIND=""
if [ -d "$SRC" ]; then
  KIND=dir
  ( cd "$SRC" && find . \( -type f -o -type l \) -print ) | sed 's|^\./||' > "$INDEX" || { echo "FATAL: cannot index directory"; exit 3; }
else
  case "$SRC" in
    *.tar.gz|*.tgz)   KIND=tar; tar -tzf "$SRC" ;;
    *.tar.bz2|*.tbz2) KIND=tar; tar -tjf "$SRC" ;;
    *.tar.xz|*.txz)   KIND=tar; tar -tJf "$SRC" ;;
    *.tar)            KIND=tar; tar -tf  "$SRC" ;;
    *.zip)            KIND=zip; unzip -Z1 "$SRC" ;;
    *) echo "FATAL: unsupported archive type (need .tar.gz/.tgz/.tar.bz2/.tar.xz/.tar/.zip or a directory)"; exit 2 ;;
  esac > "$INDEX" 2>/dev/null || { echo "FATAL: malformed or unreadable archive"; exit 2; }
fi

if grep -qE '(^|/)\.\./|^/' "$INDEX"; then
  echo "FATAL: package contains absolute or traversing paths - refusing to extract"; exit 4
fi
LC_ALL=C sort -o "$INDEX" "$INDEX"
TOTAL=$(wc -l < "$INDEX")
[ "$TOTAL" -gt 0 ] || { echo "FATAL: package indexed as empty"; exit 2; }
echo "package kind: $KIND ; entries indexed: $TOTAL"
echo

extract_one(){ # $1 = member path -> prints local readable path (or nothing)
  local p="$1"
  if [ "$KIND" = dir ]; then printf '%s\n' "$SRC/$p"; return 0; fi
  [ -n "$TMP" ] || TMP=$(mktemp -d) || return 0
  case "$KIND" in
    tar) tar -xf "$SRC" -C "$TMP" -- "$p" 2>/dev/null || return 0 ;;
    zip) unzip -o -q -d "$TMP" "$SRC" "$p" 2>/dev/null || return 0 ;;
  esac
  [ -f "$TMP/$p" ] && printf '%s\n' "$TMP/$p"
  return 0
}

LAST_STATUS=""
report_obj(){ # $1 = member path
  local ap="$1" lp sz sha ft st syms
  LAST_STATUS="UNKNOWN"
  lp=$(extract_one "$ap")
  if [ -z "$lp" ] || [ ! -f "$lp" ]; then echo "      status: UNKNOWN (could not read member)"; return 0; fi
  sz=$(stat -c%s "$lp"); sha=$(sha256sum "$lp" | cut -d' ' -f1); ft=$(file -b "$lp")
  if printf '%s' "$ft" | grep -qE "$WANT_ARCH_RE"; then st="PRESENT"
  elif printf '%s' "$ft" | grep -q "ELF"; then st="WRONG ARCH"
  else st="UNKNOWN"; fi
  LAST_STATUS="$st"
  echo "      status: $st"
  echo "      path  : $ap"
  echo "      size  : $sz    sha256: $sha"
  printf '      type  : %.100s\n' "$ft"
  if printf '%s' "$ft" | grep -q ELF; then
    syms=$(nm -g --defined-only "$lp" 2>/dev/null | awk '$2 ~ /^[TDBRW]$/{print $3}' | LC_ALL=C sort -u | head -25 || true)
    [ -n "$syms" ] || syms=$(readelf --dyn-syms -W "$lp" 2>/dev/null | awk '$4=="FUNC" && $8!=""{print $8}' | LC_ALL=C sort -u | head -25 || true)
    if [ -n "$syms" ]; then
      echo "      defined global symbols (first 25):"
      printf '%s\n' "$syms" | sed 's/^/        /'
    else
      echo "      defined global symbols: (none readable / stripped)"
    fi
  fi
  return 0
}

# Path-qualified source lookup.
# Sets SRC_VERDICT to ACCEPT | REVIEW | NONE and SRC_PATH to the candidate (if any).
find_src_alt(){ # $1 = object
  local o="$1" line obj re hit cand
  SRC_VERDICT="NONE"; SRC_PATH=""
  # objects with no trustworthy published Broadcom source path
  case " $NO_TRUSTED_SRC_PATH " in
    *" $o "*)
      cand=$(grep -E "(^|/)${o%.o}\.c$" "$INDEX" | head -5 || true)
      if [ -n "$cand" ]; then SRC_VERDICT="REVIEW"; SRC_PATH="$cand"; fi
      return 0 ;;
  esac
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    obj=${line%%|*}; re=${line#*|}
    [ "$obj" = "$o" ] || continue
    hit=$(grep -E "$re" "$INDEX" | head -1 || true)
    if [ -n "$hit" ]; then
      if printf '%s' "$hit" | grep -qE "$SRC_REJECT_RE"; then
        SRC_VERDICT="REVIEW"; SRC_PATH="$hit"
      else
        SRC_VERDICT="ACCEPT"; SRC_PATH="$hit"
      fi
      return 0
    fi
    # basename exists somewhere but not at an acceptable path -> needs review, not accepted
    cand=$(grep -E "(^|/)${o%.o}\.c$" "$INDEX" | head -3 || true)
    if [ -n "$cand" ]; then SRC_VERDICT="REVIEW"; SRC_PATH="$cand"; fi
    return 0
  done <<< "$SRC_ALT_QUALIFIED"
  return 0
}

# Raw-ASUS flat layout (<component>/prebuild/<obj>, no per-model directory) is accepted only
# when the package's own model-conditional rc object proves which model it was built for:
# every model-name string compiled into rc/prebuild/init-broadcom.o must be RT-AXE7800.
# A path or filename alone never establishes this.
RAW_FLAT_OK=no; RAW_FLAT_WHY="no Merlin per-model layout and no flat identity marker"
if ! grep -qE 'shared/prebuild/RT-AXE7800/' "$INDEX"; then
  ib=$(grep -E '(^|/)release/src/router/rc/prebuild/init-broadcom\.o$' "$INDEX" | head -1 || true)
  if [ -n "$ib" ]; then
    ibp=$(extract_one "$ib")
    if [ -n "$ibp" ] && [ -f "$ibp" ]; then
      models=$(strings -a "$ibp" | grep -oE '\b(RT|GT|TUF|XT|ET|RP|BR|BM|XD|EBA)-[A-Z0-9_]+\b' | grep -E 'AX|AC|BE' | LC_ALL=C sort -u | tr '\n' ' ' || true)
      if [ "$models" = "RT-AXE7800 " ]; then
        RAW_FLAT_OK=yes; RAW_FLAT_WHY="rc/prebuild/init-broadcom.o model strings = RT-AXE7800 only"
      else
        RAW_FLAT_WHY="rc/prebuild/init-broadcom.o model strings: ${models:-none}"
      fi
    fi
  fi
fi
echo "raw-ASUS flat layout accepted: $RAW_FLAT_OK ($RAW_FLAT_WHY)"
shared_obj_re(){ # $1 = object -> regex for an accepted shared prebuild location
  if [ "$RAW_FLAT_OK" = yes ]; then printf '(shared/prebuild/RT-AXE7800/|(^|/)release/src/router/shared/prebuild/)%s$' "$1"
  else printf 'shared/prebuild/RT-AXE7800/%s$' "$1"; fi
}
echo

check_object(){ # $1 = object name ; prints status, sets RESULT
  local o="$1" hits n=0 satisfied=no alt
  RESULT="MISSING"
  echo "--- $o ---"
  hits=$(grep -E "shared/prebuild/RT-AXE7800/${o}$" "$INDEX" || true)
  if [ -z "$hits" ] && [ "$RAW_FLAT_OK" = yes ]; then
    hits=$(grep -E "(^|/)release/src/router/shared/prebuild/${o}$" "$INDEX" || true)
    [ -n "$hits" ] && echo "      layout: raw-ASUS flat (identity: $RAW_FLAT_WHY)"
  fi
  if [ -n "$hits" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      report_obj "$h"
      [ "$LAST_STATUS" = "PRESENT" ] && satisfied=yes
      n=$((n+1))
      [ "$n" -ge 3 ] && break
    done <<< "$hits"
    [ "$satisfied" = yes ] && RESULT="PRESENT" || RESULT="WRONG ARCH"
  else
    find_src_alt "$o"
    if [ "$SRC_VERDICT" = "ACCEPT" ]; then
      echo "      status: SOURCE AVAILABLE (path-qualified)"
      echo "      source: $SRC_PATH"
      RESULT="SOURCE AVAILABLE"; satisfied=yes
    elif [ "$SRC_VERDICT" = "REVIEW" ]; then
      echo "      status: SOURCE CANDIDATE - NEEDS REVIEW (not counted as satisfied)"
      while IFS= read -r l; do [ -n "$l" ] && echo "        candidate: $l"; done <<< "$SRC_PATH"
      echo "        reason: not at an accepted path for this object (other-platform or unexpected location)"
      RESULT="NEEDS REVIEW"
    else
      echo "      status: MISSING (no object under shared/prebuild/RT-AXE7800/, no acceptable source)"
      local other; other=$(grep -E "/${o}$" "$INDEX" | head -5 || true)
      if [ -n "$other" ]; then
        echo "      other copies of this filename in package:"
        while IFS= read -r l; do [ -n "$l" ] && echo "        $l"; done <<< "$other"
      fi
      RESULT="MISSING"
    fi
  fi
  return 0
}

echo "=============================================================="
echo " P0 — CURRENT_REQUIRED_P0 (required by the verified RT-AXE7800 config)"
echo "=============================================================="
FAIL=0; SAT=0
for o in $CURRENT_REQUIRED_P0; do
  check_object "$o"
  case "$RESULT" in
    PRESENT|"SOURCE AVAILABLE") SAT=$((SAT+1)) ;;
    *) FAIL=$((FAIL+1)) ;;
  esac
done
echo
echo "  CURRENT_REQUIRED_P0: $SAT satisfied, $FAIL unsatisfied (of 4)"

echo
echo "=============================================================="
echo " FEATURE_GATED_EXPECTED (shipped for other BCM6756 models;"
echo " NOT required by the current config — never affects exit code)"
echo "=============================================================="
for o in $FEATURE_GATED_EXPECTED; do
  if grep -qE "$(shared_obj_re "$o")" "$INDEX"; then
    echo "  PRESENT              $o"
  else
    find_src_alt "$o"
    case "$SRC_VERDICT" in
      ACCEPT) echo "  SOURCE AVAILABLE     $o  ($SRC_PATH)" ;;
      REVIEW) echo "  NEEDS REVIEW         $o" ;;
      *)      echo "  MISSING (gated off)  $o" ;;
    esac
  fi
done
echo
echo "  -- NON_6756_OPTIONAL (present only in the BCM4912 donor; not part of either"
echo "     BCM6756 17-object set; informational, never affects exit code) --"
for o in $NON_6756_OPTIONAL; do
  if grep -qE "$(shared_obj_re "$o")" "$INDEX"; then
    echo "  PRESENT              $o"
  else
    echo "  ABSENT (expected)    $o"
  fi
done

echo
echo "=============================================================="
echo " Completeness: full BCM6756-style shared/prebuild inventory (17)"
echo "=============================================================="
have=0; miss=""
for o in $FULL_6756_SET; do
  if grep -qE "$(shared_obj_re "$o")" "$INDEX"; then have=$((have+1)); else miss="$miss $o"; fi
done
echo "  present: $have of 17"
[ -n "$miss" ] && echo "  absent :$miss"
if [ "$have" -eq 17 ]; then echo "  => complete BCM6756-style directory supplied"; else echo "  => directory is NOT the complete 17-object set (informational only)"; fi

echo
echo "=============================================================="
echo " RUNTIME_CRITICAL (informational - does NOT affect the exit code)"
echo "=============================================================="
rt_hit=$(grep -E "$RUNTIME_FW_PATH_RE" "$INDEX" | head -1 || true)
if [ -z "$rt_hit" ]; then
  echo "  MISSING   dongle/sysdeps/RT-AXE7800/6715b0/rtecdc.bin"
  echo "            WARNING: wl1 (PCIe 5 GHz DHD radio) firmware absent."
  echo "            The published firmware ships this at rom/etc/wlan/dhd/6715b0/rtecdc.bin."
  echo "            Runtime/build asset - not counted as a P0 build input."
else
  rt_lp=$(extract_one "$rt_hit")
  if [ -n "$rt_lp" ] && [ -f "$rt_lp" ]; then
    rt_sha=$(sha256sum "$rt_lp" | cut -d" " -f1)
    if [ "$rt_sha" = "$RUNTIME_FW_STOCK_SHA256" ]; then
      echo "  HASH-MATCH-KNOWN-STOCK  $rt_hit"
    else
      echo "  PRESENT   $rt_hit"
      echo "            sha256=$rt_sha (does not match the known 388_25206 stock firmware)"
    fi
    echo "            size=$(stat -c%s "$rt_lp")"
  else
    echo "  UNKNOWN   $rt_hit (present in index but unreadable)"
  fi
fi

echo
echo "=============================================================="
echo " ADDITIONAL RT-AXE7800 MODEL-SPECIFIC PATHS"
echo "=============================================================="
EXTRA="release/src/router/rc/prebuild/RT-AXE7800
release/src/router/httpd/prebuild/RT-AXE7800
release/src/router/protect_srv/lib/prebuild/RT-AXE7800
release/src/router/bsd/prebuilt/RT-AXE7800
release/src/router/networkmap/prebuild/RT-AXE7800
release/src/router/fsmd/prebuild/RT-AXE7800
release/src/router/www/sysdep/RT-AXE7800
release/src/router/rom/apps_scripts/runin/RT-AXE7800
release/src-rt-5.04axhnd.675x/hostTools/prebuilt/RT-AXE7800
release/src-rt-5.04axhnd.675x/router-sysdep.rt-axe7800"
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  hits=$(grep -E "(^|/)${dir}(/|$)" "$INDEX" | head -50 || true)
  if [ -z "$hits" ]; then
    printf '  %-9s %s\n' "MISSING" "$dir"
  else
    printf '  %-9s %s (%s entries)\n' "PRESENT" "$dir" "$(printf '%s\n' "$hits" | grep -c . || true)"
  fi
done <<< "$EXTRA"

echo
echo "=============================================================="
echo " ALL RT-AXE7800 / RTAXE7800 PATHS IN PACKAGE"
echo "=============================================================="
grep -iE "RT[-_]?AXE7800" "$INDEX" | LC_ALL=C sort | head -80 || true
echo "  ... total RT-AXE7800-related entries: $(grep -icE "RT[-_]?AXE7800" "$INDEX" || true)"

echo
echo "=============================================================="
echo " Package opened read-only; no file in it was modified."
echo "=============================================================="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
