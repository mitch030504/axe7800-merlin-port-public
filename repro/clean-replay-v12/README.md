# clean-replay-v12 — Merlin 3004.388 + authentic GPL 388.25206 supply

Supersedes [`clean-replay-v11`](../clean-replay-v11/README.md). v11 hit the limits of what GPL
388.34458 could provide. v12 is built on the matching same-generation package
`GPL_RT-AXE7800_3.0.0.4.388.25206-gcaa73b5.tgz` (intake:
[`../intake/INTAKE-388_25206.md`](../intake/INTAKE-388_25206.md)) and on the Merlin baseline
chosen by measurement in [`../baseline-analysis/BASELINE-DECISION.md`](../baseline-analysis/BASELINE-DECISION.md).

    git -C asuswrt-merlin.ng worktree add --detach ../v12 f94f6ff8ad
    ./replay.sh ../v12 <extracted-gpl-root>          # the dir that contains release/
    # then, in the build container (tools/build-env):
    cd release/src-rt-5.04axhnd.675x && make rt-axe7800

## What changed from v11

| | v11 | v12 |
|---|---|---|
| Merlin base | 3006.102-wifi6 @ `ccd139a3` | **3004.388 @ `f94f6ff8ad`** (same 388 codebase as the GPL) |
| authentic supply | 142 objects from GPL 388.34458, via an unpublished manifest and cache | **1,098 entries from GPL 388.25206**, committed [`supply-manifest.tsv`](supply-manifest.tsv), re-verified on every replay |
| platform tree | GNUton `router-sysdep.tuf-ax3000_v2` (different model, other fork) | the GPL's own 6756 `router-sysdep`, verbatim |
| kernel driver objects | GNUton TUF-AX3000_V2 copies plus symlinks | the GPL's own 6756 `bcmdrivers` objects |
| target stanza | hand-assembled (0001 + 0009) | ASUS 25206 `target.mak` stanza with Merlin's standard per-model deltas |
| patches 0002–0008 | needed | not carried. 0007 (`get_fh_if_prefix_by_unit`) has no counterpart in 3004.388. 0008 (`hnd_boardid_cmp`) is provided by the 25206 prebuilts. 0002–0006 targeted the GNUton platform tree |

**No donor binaries from other models or forks.** Every staged binary comes from the
same-model ASUS package and is sha256-checked against the committed manifest.

## Supply manifest

[`gen-supply-manifest.sh`](gen-supply-manifest.sh) `<gpl-root> <pristine-merlin-pin>` produces it.
Rows: `F sha256 size gpl-path merlin-path category` or `L target - gpl-path merlin-path category`.

| category | rows | rule |
|---|---|---|
| RSD | 812 | GPL `router-sysdep/**` → `router-sysdep.rt-axe7800/**`. Merlin swaps this per-model tree in at build time. It matches Merlin's GT-AX6000 copy in 771/809 files; the rest are 6756 binaries and ASUS's 6756/RT-AXE7800 additions (`scripts/Makefile` chip list, `dhd_monitor.c` instance base) |
| DRV | 25 | GPL `bcmdrivers` ELF objects that the Merlin pin lacks (`archer.o`, `bcm_cleds.o`) or has built for other chips (`pktflow.o`, `bcm_enet.o`, `bcm_bpm.o`, phy prebuilts, …) |
| HOST | 4 | GPL `hostTools/prebuilt/*`, laid out the way Merlin's `hostTools/Makefile` reads them: `lzop` and `addvtoken` per-model (`prebuilt/RT-AXE7800/`), and `execstack` and `libelf.so` flat (absent from Merlin, needed by `build_execstack` in `full_buildimage`). The other five are byte-identical to Merlin's flat copies and are not staged |
| BOOT | 24 | GPL `bootloaders/obj/**` (u-boot / nand_spl / emmc_spl board objects) → `bootloaders/obj.rt-axe7800/**`, which Merlin's `bootloaders/Makefile` copies over `obj/` at configure time |
| HNDX | 45 | GPL `src/router/hnd_extra/**` (absent from Merlin) |
| PB | 169 | every GPL `…/prebuild\|prebuilt/<f>` → `…/prebuild\|prebuilt/RT-AXE7800/<f>`, Merlin's per-model convention (verified for all 53 directories) |
| DNGL | 1 | GPL `dongle/sysdeps/default/6715b0/rtecdc.bin` → `dongle/sysdeps/RT-AXE7800/6715b0/` (the radio firmware the stock 25206 build installs; added by the [pre-flash audit](../preflash-audit/README.md)) |
| MODEL | 18 | `www/sysdep/RT-AXE7800/**` UI and the RT-AXE7800 6715b0 MFG dongle image |

## Target stanza (patch 0001)

ASUS 25206 `HND-96756_BASE` and the RT-AXE7800 stanza, with exactly the delta that Merlin
3004.388 applies to **every** other HND model. That delta was measured from GT-AX6000,
RT-AX86U_PRO and RT-AX88U_PRO, GPL against Merlin:

- turned off: `AHS CLOUDCHECK FORCE_AUTO_UPGRADE FRS_FEEDBACK FRS_LIVE_UPDATE IG_SITE2SITE SMARTSYNCBASE VPN_FUSION WEBDAV VISUALIZATION`
- removed: `IPV6S46 OCNVC DSLITE` (Merlin drops the Japanese-ISP S46 stack on all models)
- added: `DNSPRIVACY IPSET NANO NFS NTPD SNMPD TOR UPNPIGD2`

## Known ABI notes (25206 supply vs 3004.388 headers)

3004.388 has merged GPL **388_25633**, which is newer than the 25206 supply. The two type
differences found by the baseline analysis are:

- `enum conndiagEvent`: Merlin appends `EID_CD_PRINT_STA_INFO` before `EID_CD_MAX`. Existing
  values are unchanged, and the 25206 `conn_diag` ignores the new event. **Benign.**
- `enum ASUS_PP_*` and `struct ASUS_PP_table`: the 25206 `spwenc.o` defines `ASUS_PP_t[]`
  with 0-based ids and 12-byte entries. Merlin's 25633 header has 1-based ids, two more ids
  and a `force_sign` field (16 bytes). The only open-source callers that pass these ids
  (`aws-iot`, `uploader`) are not enabled for RT-AXE7800. **Latent.** It is reconciled in a
  patch once the build reaches the boundary.

## Source adaptation patches

The first clean v12 build got past the whole v11 frontier. `libshared.so` links and exports
`invalid_nvram_get_program`/`invalid_program_check`, `libdisk/write_smb_conf` links, and
`libwebapi.so` builds. It then stopped at the `rc` link with four undefined references:

    rc.o:       undefined reference to `firmware_webs_update_main'
    init.c:     undefined reference to `init_asus_pp_eula'
    watchdog.c: undefined reference to `set_eth1_pause'
    watchdog.c: undefined reference to `memleakdbg'

All four have the same cause. Each is a call that Merlin 3004.388 picked up when it merged
newer ASUS GPLs (`firmware_webs_update`, `set_eth1_pause` and `memleakdbg` in 388_25523;
`init_asus_pp_eula` in 388_25633). ASUS's own 25206 sources contain **none** of these call
sites. Their providers exist only in other models' newer-generation prebuilts. The faithful
port for a 25206-supplied model is therefore to not make those calls, exactly like the
stock 25206 firmware. Nothing is stubbed or reimplemented.

| patch | change | evidence |
|---|---|---|
| [0002](patches/0002-rc-scope-post-25206-call-sites-out-for-RTAXE7800.patch) | `rc`: scope the four call sites out on `RTAXE7800` (`check_eth1_pause` falls back to TUF-AX3000_V2 only) | GPL 25206 `rc/{rc,init,watchdog}.c` have none of them; no 25206 object defines them |
| [0003](patches/0003-shared-ASUS_PP-ABI-matches-25206-supply-on-RTAXE7800.patch) | `shared.h`: on `RTAXE7800`, use the 25206 `ASUS_PP_*` ids (0-based) and 12-byte `struct ASUS_PP_table`, and hide `init_asus_pp_eula` | the supplied `spwenc.o` defines `ASUS_PP_t[]`; `priv_webapi.o`/`web_hook.o` consume the ids |

| [0004](patches/0004-httpd-scope-nvram_modify_log-out-for-RTAXE7800.patch) | `httpd`: scope the four `nvram_modify_log`/`handle_nvram_modify_log` calls out on `RTAXE7800` | added in the 388_25633 merge; defined only by newer `web_hook.o` of other models; 25206 `web.c` has neither. `activity_obj` is still allocated and freed unconditionally |

| [0005](patches/0005-asd-classic-asd-for-25206-supply-ASD21-n.patch) | build: honour `ASD21=n` (unset `RTCONFIG_ASD_2_1`) and set it in the RT-AXE7800 stanza | Merlin's HND `config_base` enables ASD 2.1 for every model because their newer supplies ship `asd2.1/prebuild/<model>`. The 25206 package supplies classic `asd/prebuild/{asd,libasd.so}` and an empty `asd2.1/`. The existing Makefile could only switch the flag on |
| [0006](patches/0006-router-Makefile-fix-libcap-ng-install-recipe.patch) | `router/Makefile`: add the missing `;` after the `install`/`$(STRIP)` lines of the `libdrop_ambient` block in `libcap-ng-install` | **Merlin bug, not model-specific.** Without the separators the three lines run as one `install` command (`install: cannot stat 'cd'`) whenever `libdrop_ambient.so` is built. Upstreamable as-is |

| [0007](patches/0007-u-boot-take-ASUS-25206-NAND-fixes-hashtable-MXIC-WAR-and-TPL-BBT.patch) | U-Boot: ASUS 25206 `lib/hashtable.c` (0xFF environment fill, a **workaround for MXIC NAND failing to write zeros**) and `brcmnand_spl.c` (TPL bad-block table) | found by the [pre-flash audit](../preflash-audit/README.md); the owner's router has an MXIC MX30LF2G28AD |
| [0008](patches/0008-platform-take-ASUS-25206-hardware-fixes-MXIC-NAND-xtal-eloop.patch) | kernel/drivers: ASUS 25206 MXIC UBI `sync_erase` retry, MXIC NAND write-block OOB retry, `siutils` crystal-glitch delay, `hostapd`/`wpa_supplicant` `eloop` signal unblocking | same; pure additions (+79/−0) |

The second clean build (`v12b`, after moving `hnd_extra/prebuilt` into
`router-sysdep.rt-axe7800`) compiled `httpd` and failed only at its link, on those two symbols.
[`scan-generation-gaps.py`](scan-generation-gaps.py) then listed every remaining Merlin call
into a private symbol that other models' prebuilts define and the 25206 supply does not. No
other hit is compiled for RT-AXE7800: `rc` already links, the `httpd` link reported only these
two, and the built `libshared.so` does not import the two `shared/` candidates.

0003 was not a link failure. It closes the latent mismatch recorded above, so that open code
built for this model sees the same ABI as the supplied objects.

## Build result: complete Merlin image

**`RT-AXE7800_3004_388.13_alpha1_nand_squashfs.pkgtb`**, built independently on two hosts.
It is **not flash-tested and must not be flashed.** Runtime behaviour on hardware is unestablished.

| build | host | image sha256 | size |
|---|---|---|---|
| `v12b` | workstation (32 threads) | `a4f62801b303c02a4aab6b19bcb7bcdb4c8434a71dbede0e410196ea4d5373be` | 56,720,028 |
| `v12r` | second machine (own Merlin clone from GitHub, own Docker image, GPL zip re-hashed there) | `ce2cccbb84ce08e2639748f7e680a0c04c568750ccef7a1ec29ecdf91f63bacc` | 56,723,912 |
| **`v12c`** | second machine, **single pass**: fresh worktree → `replay.sh` (final manifest, patches 0001–0006) → one `make rt-axe7800`, zero manual steps, 0 make errors, 24m33s | `d024f7cef6c9b6c07063d458b5eafb2bbb36870369eeae2936af2dfbd7640971` | 56,735,608 |

Image hashes differ because ASUS/Broadcom image tooling embeds build time and build-root
paths. The stock GPL image is not hash-reproducible either. Contents were compared instead.

### Verification

| check | result |
|---|---|
| adapted sources (all 8 files touched by patches 0001–0006), all three builds | **identical** sha256 |
| single-pass `v12c` vs `v12r` | same 2,656 files. 2,592 byte-identical. The other 64: 59 ELFs with identical symbol sets and 5 build-stamp text files. ABI closure identical to stock |
| rootfs file list, both hosts | **identical**, 2,656 files |
| rootfs contents | 2,601 byte-identical. The other 55: 6 text files with build time/path (`image_version`, `motd`, `modules.dep`, …) and 49 ELFs whose dynamic symbol **sets are identical** (only addresses shift, from embedded build-root path strings). For `libshared.so` the sole difference is the embedded build timestamp |
| runtime ABI closure ([`tools/rootfs-abi-closure.py`](../../tools/rootfs-abi-closure.py), loader model) | Merlin rootfs result **identical to the stock 25206 rootfs**: no new unresolved symbol in 619 dynamic ELFs. Both share the same pre-existing vendor gaps (5 symbols in `libbcm_flashutil.so`/`libbcm_boardctl.so`, `lld2d` → `libbcm_crc.so`) — [`evidence/`](evidence/) |
| `invalid_nvram_get_program` / `invalid_program_check` | defined by Merlin's `libshared.so`, imported by prebuilt `libnvram.so` |
| libwebapi shipping contract | `libwebapi.so` exports 91 symbols (retail: 91); **0 of 34** contract symbols missing |
| S46 | `rc` links with 25206 `s46comm.o` (Merlin stanza drops `IPV6S46`, as for every Merlin model) |
| radio firmware | `rom/etc/wlan/dhd/6715b0/rtecdc.bin` present |

### Iterations (each one a clean, explained stop)

| run | stop | resolution |
|---|---|---|
| v12a #1 | `rc` link: 4 post-25206 symbols | patch 0002 (+0003 ABI) |
| v12a #2 | `httpd`: `wlc_types.h` not found | manifest: `hnd_extra/prebuilt` belongs inside `router-sysdep.rt-axe7800` |
| v12b #1 | `httpd` link: `nvram_modify_log` | patch 0004 |
| v12b #2 | install: `asd2.1-install` | patch 0005 |
| v12b #3 | install: `libcap-ng-install` | patch 0006 (Merlin bug) |
| v12r #2 | image: `build_execstack` | manifest: HOST layout per Merlin's `hostTools/Makefile` |
| v12r #3 | u-boot: `obj.rt-axe7800/*` missing | manifest: `BOOT` category |
| v12r #4, v12b #5 | — | **complete image** |
| v12c (single pass, final recipe) | — | **complete image, first try** |
| **v12e** (single pass, patches 0001–0008, **current**) | — | **complete image** `1ec1b5d1b6b965bc684d1b667c1f1e0d743cbeae16e3e9e732c2b96ff32f0561` (56,726,740 B); FIT hashes valid, 0 unresolved module symbols, loader and ABI closure identical to stock, NAND fixes verified in the compiled objects |
| v12d (single pass, + `DNGL`) | — | **complete image**; 6715b0 `rtecdc.bin` now the stock-build copy (`d5b3b559…`); ABI closure identical to stock |
