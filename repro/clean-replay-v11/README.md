> **SUPERSEDED by [`clean-replay-v12`](../clean-replay-v12/README.md).** After ASUS supplied GPL 388.25206,
> the port moved to Merlin `3004.388` with a same-generation supply and now builds a complete image.
> v11 is kept for the record; its frontier (`invalid_*`, `priv_webapi`, `s46comm`) is closed by the 25206 package.

# clean-replay-v11 — fully deterministic RT-AXE7800 integration replay

One script, one pass, zero manual steps: pinned RMerlin `ccd139a31d` → complete legitimate
integration state → ONE build establishes the natural blocker.

    ./replay.sh <fresh-worktree> [supply-cache]

## What it reproduces (everything previous lineages did by hand)

| step | content | source of truth |
|---|---|---|
| A | preflight: pin, pristine tree, GNUton objects, manifest, cache | committed pins |
| B | model integration: patches 0001/0002, `router-sysdep.rt-axe7800` (857 files from GNUton `92e9b311`), chip-scoped binaries, 4 wiring symlinks, lzop host-tool symlink, 14 authentic UI files | git objects, all sha256-verified |
| C | **142 authentic GPL objects**, each verified against the committed `supply-manifest.txt` before staging | ASUS GPL 388.34458 via verified cache |
| D | patch series 0003–0009 (replay fixes + configclosure stanza) then 0007/0008 (source adaptations) | committed patches |
| E | assertions: stanza tokens, synthetic-marker scan 0, probe-symbol scan 0, quarantined hashes absent, supply counts 16/42, guards present | self-check, aborts on any failure |

## Patch series

| # | patch | origin |
|---|---|---|
| 0001 | RT-AXE7800 target stanza | clean-replay-v2 |
| 0002 | phy chip-scoped prebuilt selector | clean-replay-v2 |
| 0003 | wlan `setuplink` order-only edge | clean-replay-v5 |
| 0004 | wlan/nvram prebuilt `all_tags` | clean-replay-v6 |
| 0005 | bcm_util bcm963xx include path | clean-replay-v9 |
| 0006 | odmpid | clean-replay-v10 |
| 0009 | **configclosure accepted stanza** (PROXYSTA=y, AMAS=y, SW_HW_AUTH=y, TPVPN=n) — previously existed only as live worktree state, captured here for the first time | this version |
| 0007 | `get_fh_if_prefix_by_unit` → `RTCONFIG_MULTILAN_CFG` guard | abi-guard-v2 |
| 0008 | `hnd_boardid_cmp` → `defined(RTBE96U)` scope | abi-guard-v2 |

## External authentic input

ASUS `GPL_RT-AXE7800_3.0.0.4.388.34458-g90b8ce5.tgz`
sha256 `6fe789e03d64393cfb6faba18c75edac42ecfe69af80aef18acd4f53d0793355`.

The replay accepts a persistent local cache (`~/gpl-supply-cache`, with a
`PROVENANCE.txt`) but **never trusts it**: every staged file is re-verified against the
committed manifest hash at replay time and any mismatch aborts. Content is authenticated by
hash, not by directory history. No GPL binaries are committed to this repository.

## Determinism proof (two independent fresh lineages, 2026-08-20)

`axe7800-clean-replay-v11` (first run, pre-0009) and `axe7800-clean-replay-v11r2` (final)
were both created fresh from the pin with 0 initial status entries. In both, the replay ran
end-to-end with **zero manual intervention**, and the three adapted sources came out
byte-identical (`misc.c` 996d4b0b…, `broadcom.c` 71b52acd…, `model.c` 2abd7e6c…).

The first run exposed the one remaining un-captured piece of state — the configclosure
stanza — because its build raced to `libwebapi` under a leaked-default configuration.
That gap became patch 0009; the fixed replay was then re-proven in the second fresh lineage.

## Clean validation build result (v11r2, single pass)

    make[5]: *** [Makefile:77: write_smb_conf] Error 1     (libdisk, Makefile:11583)

    undefined reference to `invalid_nvram_get_program'
    undefined reference to `invalid_program_check'

Exactly two unresolved symbols, at the natural `write_smb_conf` link boundary, demanded by
the prebuilt `libnvram.so`. In the whole log, `get_fh_if_prefix_by_unit` and
`hnd_boardid_cmp` appear as undefined **zero** times, and the built `libshared.so` carries
none of the four in its dynamic table. Synthetic-marker scan after the build: **0**.

**This freshly demonstrates the two-symbol frontier from a fully reproducible,
uncontaminated state.** Both symbols are PRIVATE-SUPPLY (see
`repro/source-adaptation-v1/evidence/private-abi-three-blockers.md`): no open caller,
demanded by the closed prebuilt `libnvram.so`, exercised by stock `/lib/libnvram.so`,
validation semantics — not to be stubbed, guessed, or bypassed. Behind them, in parallel
branches of the same build: `libwebapi/priv_webapi.o` and `rc/s46comm.o`, both awaiting the
a current-generation ASUS RT-AXE7800 388_25xxx source package.
