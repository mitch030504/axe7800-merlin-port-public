# Pre-flash audit — Merlin RT-AXE7800 image (v12)

**Verdict: every check that can be made without booting the image has passed, after three
corrections found by this audit (radio firmware, U-Boot NAND fix, kernel/driver NAND and
platform fixes).** What remains is behaviour at boot and run time, which only hardware can
establish. The owner has **no UART**, so recovery from a non-booting image relies on ASUS
rescue mode in U-Boot. That must be confirmed on the unit before any flash.

**Coverage:** [`COVERAGE.md`](COVERAGE.md) puts every stage of the flash, boot and first run
against every property class. Each cell is verified, not verifiable offline (with the reason), or
not applicable, and four independent walks checked that the matrix is complete.

Subject: `RT-AXE7800_3004_388.13_alpha1_nand_squashfs.pkgtb` from `clean-replay-v12` with
patches 0001–0008. Baseline: the unmodified GPL 25206 stock build, whose `rc`, `httpd`,
`libnvram.so` and `libwebapi.so` were confirmed **on the owner's router** to be byte-identical to
the running retail firmware.

## A. Hardware facts read from the owner's router (read-only SSH)

Commands were limited to reads (`cat`, `dmesg`, `ubinfo`, `nvram get/show` piped to key names
only, `sha256sum`). Nothing was written, set or restarted.

| fact | value | consequence |
|---|---|---|
| firmware | `RT-AXE7800`, `3.0.0.4.388_25206-gcaa73b5` (`extendno=25206-gcaa73b5`) | exactly the GPL generation used |
| NAND | **Macronix MX30LF2G28AD**, 256 MiB SLC, 128 KiB blocks, BCH-8 | this is the part ASUS's MXIC workarounds name (`MX30LFxG28AD`), so patches 0007/0008 are required for this unit |
| flash layout | `loader` 2 MiB; UBI `image` 252 MiB: `metadata1/2`, `bootfs1/2`, `rootfs1/2`, `data`, `defaults`, `jffs2` | matches the image's FIT layout |
| boot state | metadata `COMMITTED=2 VALID=1,2 SEQ=3,4`; running `rootfs2` | an upgrade writes slot 1 |
| space | slot 1 = 455 LEBs (≈56.5 MB); UBI free 416 LEBs (50.4 MiB) | Merlin needs ≈447 LEBs, which fits with large headroom |
| U-Boot env | `bootcmd=printenv;run once;sdk boot_img`, `bootdelay=3`, `boardid=RT_AXE7800`, `IMAGE=NAND:2M,254M,255M` | standard Broadcom slot boot |
| live drivers | `wl`, `dhd`, `archer`, `bcm_enet`, `pktflow`, … (67 modules) | all present in the Merlin image |
| retail vs GPL build | `wl.ko`, `dhd.ko`: same size and symbol set, differ only in the embedded build date. `rtecdc.bin` (6715b0): same size, **14 bytes** differ (build date/time string and its checksum) | the GPL Wi-Fi stack the Merlin image uses is functionally the retail one |

## B. Image structure and acceptance

| check | result |
|---|---|
| top-level FIT | `RT-AXE7800`, images `bootfs_6756_a0+` + `nand_squashfs`, config `conf_6756_a0+_nand_squashfs`, same `compatible` and 937-byte header as stock. No loader node, so the 2 MiB `loader` partition (SPL/TPL) is not written |
| **bootfs contents** | a nested FIT with **ATF, U-Boot proper, U-Boot DTB, the kernel, and the board DTBs**, the same set of images and configurations as stock. **Correction to the first audit:** flashing *does* replace the U-Boot proper and ATF that run from that slot, and ASUS rescue mode lives in that U-Boot. Their sources were therefore audited (section D) |
| packed device trees | `fdt_RT_AXE7800` **identical** to stock (`b8fba56a…`); `fdt_uboot` identical |
| FIT hashes | every subimage `hash-1` (sha256) matches its data, in both stock and Merlin, so U-Boot's verification will pass |
| stock upload check | `httpd` accepts a `.pkgtb` whose FIT description equals `RT-AXE7800` (board-id check only on XT8_V2), so the Merlin image matches. The upgrade runs `bcm_flasher … 1` (`reboot_new`): write the inactive slot, then boot it |
| fallback | **Correction: there is an automatic fallback until `rc` commits.** The manual upgrade sets `BOOT_SET_NEW_IMAGE_ONCE`, so the old slot stays committed and the boot reason is `ACTIVATE`. The TPL boots the new slot once and clears the reason. `rc`'s `sync_boot_state()` commits the running image after `start_misc_services()`; it compiles to the same code in Merlin as in stock. A failure before that point boots stock again on the next reboot or power cycle. After it, recovery is Merlin's web UI or ASUS rescue mode (`asus_rescue`, TFTP on `192.168.1.1`), whose U-Boot code is byte-identical to retail's ([E14](evidence/session-2026-10-14-verified-cells.md)). (The first audit read the stale `TODO` above that TPL code and missed the logic below it.) |

## C. Userspace and kernel modules (each run on stock first, as a calibration)

| check | result |
|---|---|
| kernel modules present | every stock module present; Merlin adds 22 |
| module symbol resolution (`depmod -e -F System.map`, sensitivity-tested by deleting a used symbol) | **0 unresolved** in stock (128) and Merlin (150). One vermagic for all: `4.19.183 SMP preempt mod_unload ARMv7 p2v8`. `CONFIG_MODVERSIONS` is off in both, so CRCs are not checked; struct compatibility for the prebuilt drivers rests on identical kernel `include/` trees and a config that differs only in options that do not alter structures they use |
| real loader resolution (image's own `ld-linux.so.3` under qemu-arm, `LD_BIND_NOW` + `LD_WARN`, including symbol versions; [`tools/rootfs-ldd-check.sh`](../../tools/rootfs-ldd-check.sh)) | **267 programs, 0 Merlin-specific findings**. Both images share one pre-existing vendor defect (`lld2d` → `libbcm_crc.so`) |
| static ABI closure | identical to stock |
| execution under qemu-arm | `busybox`, shell arithmetic, `openssl`, `curl`, `iptables`, `dnsmasq`, `dropbear`, `openvpn`, `ip`, `tc` run. **`nvram show` reaches ASUS's private `invalid_program_check` in Merlin's `libshared.so` with output identical to stock**: the original v11 blocker, exercised at run time |
| symlinks and permissions | `/sbin/init → rc`, `/bin/sh → busybox`, the loader and the `rc`/`httpd` modes match stock. Stock-only links are features Merlin omits (`nordvpn`, `sendfeedback`, `firmware_check_update`, `telnetd`/`tftpd` applets), zoneinfo aliases, `/opt` and replaced library versions. The loader check confirms no program needs the libraries Merlin dropped |
| radio firmware | **Correction (DNGL):** now the GPL 25206 `rtecdc.bin` (`d5b3b559…`) instead of Merlin's own |

## D. Generation mix: where Merlin's source is older or newer than ASUS 25206

| area | finding | action |
|---|---|---|
| `rc` hardware bring-up | the linked `init-broadcom.o` and `ate.o` are **byte-identical to ASUS's 25206 prebuilts** (Merlin's Makefile prefers the prebuilt). Merlin's other RT-AXE7800/6756-touching changes (`AllLED` for the WAN LED, `noconsole` from the U-Boot env, Wi-Fi re-init for *other* models) are benign | none |
| `httpd` | `web-broadcom.o` is compiled from Merlin's source (web UI, not the boot path) | noted |
| U-Boot proper (in bootfs) | ASUS 25206 `lib/hashtable.c` fills the exported environment with `0xFF` as a **workaround for MXIC NAND failing to write zeros**; Merlin's did not. ASUS's TPL bad-block-table support is also missing from Merlin | **patch 0007** takes ASUS's versions |
| kernel / drivers | ASUS 25206 adds an **MXIC UBI `sync_erase` retry** (`ubi/wl.c`), an **MXIC NAND write-block OOB retry** (`bcm63xx_flash.c`), a `siutils` crystal-glitch delay, and `hostapd`/`wpa_supplicant` `eloop` signal unblocking. Merlin lacked all of them. All are pure additions | **patch 0008** takes ASUS's versions (+79/−0 lines) |
| kernel differences kept | Merlin's WireGuard, `sch_cake`, `deDupTx`, `brcmnand`/`xport` log levels | none |
| NVRAM defaults | stock 1,462 keys, Merlin 1,650. 93 stock-only keys, 56 referenced by 25206 prebuilts, **all 56 already set on this router**, and a web-UI upgrade keeps NVRAM. They belong to features Merlin omits (feedback, `dblog`, AHS, NordVPN/TPVPN, auto-update, VPN Fusion). Residual case: a factory reset under Merlin leaves them unset; ASUS code reads them with `nvram_safe_get` | noted |

## E. Before any flash (owner's checklist)

1. **Confirm rescue mode works on this unit, while still on stock.** Power off, hold reset, power
   on, keep holding until the power LED blinks slowly. Set the PC to a static 192.168.1.x
   address and confirm ASUS Firmware Restoration (or TFTP to 192.168.1.1) sees the router.
   Abort without uploading. **If this cannot be confirmed, do not flash.**
2. Keep `RT-AXE7800_3.0.0.4_388_25206` from ASUS at hand for rescue.
3. Flash **only** `RT-AXE7800_3004_388.13_alpha1_nand_squashfs.pkgtb`, never a `*_loader*` or
   `bcm96756GW_*` file.
4. If the router does not come up after the flash, **power-cycle it once**. Until Merlin's `rc`
   has committed the new image, the loader boots the old stock slot again (section B). If stock
   does not come back either, use rescue mode (step 1).

## F. Residual risks (hardware-only)

- Nothing has booted this image. Kernel, driver and daemon behaviour at run time are unverified.
- U-Boot proper equals retail's apart from its build banner. ATF is byte-proven to be retail's
  code (section H). Their behaviour on this unit, including rescue mode, is still untested.
- The automatic fallback covers failures **before** `rc` commits the new image (section B). A
  failure after the commit needs the web UI or rescue mode.
- Merlin's userspace has no field history on the BCM6756: no model Merlin 3004.388 supports uses it.
- Merlin's open userspace (merged up to 388_25633) runs against 25206 prebuilts. Symbol, version,
  struct and NVRAM-key agreement are verified; semantic agreement is not.

## G. Final image (`v12e`, patches 0001–0008)

`RT-AXE7800_3004_388.13_alpha1_nand_squashfs.pkgtb`, sha256
`1ec1b5d1b6b965bc684d1b667c1f1e0d743cbeae16e3e9e732c2b96ff32f0561`, 56,726,740 B. Single-pass
build, 0 errors. Re-verified on this exact image:

- FIT hashes match. `fdt_RT_AXE7800` and `fdt_uboot` are identical to stock. U-Boot contains ASUS rescue mode.
- `depmod`: 0 unresolved across 153 modules. Loader check (267 programs) and static ABI closure are identical to stock.
- The NAND fixes are present in the compiled output: `vmlinux` and `bcm63xx_flash.o` carry the MXIC write-retry path; U-Boot `hashtable.o` calls `memset(…, 0xff, …)`; `ubi/wl.o` was rebuilt from the patched source.

## H. Full audit: boot chain against the router's own retail image (read-only)

The retail `bootfs2` volume was read from the router (`cat /dev/ubi0_5`, a read only) and
compared with the stock GPL build and the Merlin image:

| item | retail (on router) | stock GPL build | Merlin v12e |
|---|---|---|---|
| FIT signatures (`/configurations/*/signature-*`) | **none** | none | none |
| U-Boot DTB `/signature` key node | **none** | none | none |
| `fdt_RT_AXE7800` | `b8fba56a…` | identical | identical |
| `fdt_uboot` | `4a5f7055…` | identical | identical |
| U-Boot proper (2,645,152 B) | reference | 11 bytes differ (build banner) | 12 bytes differ (build banner) |
| ATF / SP_MIN (24,872 B) | `v2.2(debug):asuswrt_3.0.0.4.388rc1-dirty` | rebuilt with retail's version string: **10 bytes differ, all in the `Built :` timestamp** | rebuilt with Merlin's version string: **7 bytes differ from the image's ATF, all in the timestamp** |

- **Secure boot:** the U-Boot env has `secboot=1` (read by ASUS's `autoboot.o`), but the retail
  image this router boots today carries no signatures, so its loader accepts a hash-only
  `bootfs`. Signature enforcement is therefore not a risk for this image.
- **U-Boot proper** is the retail binary apart from the build banner.
- **ATF, byte-proven:** ATF was built from scratch through the real `make atf` target, with a
  fresh `armtf` directory each time. With retail's version string it reproduces the router's ATF
  except for the 10-byte build timestamp. With Merlin's version string it reproduces the Merlin
  image's ATF except for the timestamp. The `armtf` trees are identical, so Merlin's ATF is
  retail's code. The 1,318/1,902-byte counts first reported here came only from the
  version-string length shifting the layout ([E15](evidence/session-2026-10-15-verified-cells.md)).

## I. Full audit: remaining platform and runtime surfaces

| surface | finding |
|---|---|
| Broadcom `userspace/`, `make.common`, `make.hndrt`, `make.modsw`, `chip_profile.mak`, `targets/96756GW` | identical to GPL apart from one include directory |
| `build/Makefile` | Merlin installs platform files to `/rom/{bin,modules,scripts}` instead of `/opt/…` (Merlin keeps `/opt` for Entware). Stock's only `/opt` files are factory stress-test scripts. No ASUS binary references `/opt/{scripts,bin,modules}` (only Merlin's `amtm`) |
| `/rom/etc` | differs only in `image_version`, `profile`, `services` and a newer CA bundle; stock-only `patch.version` is read only by the diagnostic `brcmsysinfo.sh` |
| JFFS/UBIFS storage | same `jffs2` UBI volume and UBIFS logic; Merlin adds an idle-wait retry, an NVRAM commit and its `/jffs/{scripts,configs,addons}` folders. NVRAM goes through the 25206 prebuilt `libnvram.so` (identical to the router's) |
| kernel modules `rc` loads | all 45 module names stock `rc` references exist in the Merlin image; none Merlin's `rc` references is missing; **every module loaded on the router right now** exists in the Merlin image |
| path back to stock | Merlin's `httpd` upload check is identical to stock's for this model (FIT description `RT-AXE7800`), so if Merlin boots, stock 25206 can be reinstalled from Merlin's web UI without rescue mode |

## J. Final round: retail rootfs and kernel, write path, upload gate

| check | finding |
|---|---|
| **running kernel config** (`/proc/config.gz` on the router) | **identical** to the stock GPL build's `.config` (0 differing lines). Merlin's 34 differing lines are the reviewed Merlin options |
| **retail rootfs** (`rootfs2`, read from the router) vs stock GPL build | 2,443 of 2,564 files byte-identical. 120 differ: 90 ELFs with identical symbol sets (build stamps); 3 Broadcom `.ko` that differ only by a `srcversion` tag (ASUS compiled from source, the GPL links the prebuilt objects); `libshared.so`/`wget` with different glibc symbol-version references, all resolved by the image's loader (loader check); strip/linker marker differences; libnl static archives, `modules.dep`, the per-build random `dh2048.pem`, `image_version`, `rtecdc.bin` (build date) and `public.pem` (below). Retail-only: `bin/hw_accel_dump.sh` (debug script) and the `bin/archer → archerctl` link. GPL-build-only: extra `depmod` index files |
| `/usr/sbin/public.pem` | the key for `check_rsasign`, used **only** by ASUS's online-upgrade scripts (`webs_upgrade.sh`, `sig_upgrade.sh`). Neither `httpd`'s source, its prebuilt objects nor the retail `httpd` references `rsasign`. A manual upload is not signature-checked |
| **upload gate** `check_imagefile()` | lives in ASUS's closed `shared/prebuild/private.o` (linked by stock and Merlin). Disassembly: it calls `get_model()`, prints a message and **returns 0 unconditionally** on this platform. The manual-upgrade gate is therefore only the FIT description check, which Merlin passes, followed by the flasher's per-segment SHA-256 verification |
| **what the flasher writes** (`bcm_imgif_pkgtb.c`) | only `bootfs1/rootfs1` or `bootfs2/rootfs2` (volume IDs 3/4 or 5/6, matching this router) via `ubirmvol`/`ubimkvol`/`ubiupdatevol` for the inactive slot, after SHA-256 verification of each segment, plus the slot metadata. `loader` is written only if the image's configuration has a `loader` property; the Merlin image's has only `description bootfs rootfs compatible`. **`data`, `defaults` and `jffs2`** (settings, calibration, MACs) **are never touched** |

**Not verifiable offline:** whether the image boots and behaves (kernel, drivers, `rc` init,
Wi-Fi, switch). QEMU cannot emulate the BCM6756, and the user has no UART.

Evidence: [`evidence/`](evidence/).

## K. Coverage pass: remaining cells and four completeness walks

Details: [`COVERAGE.md`](COVERAGE.md), [E14](evidence/session-2026-10-14-verified-cells.md),
[E15](evidence/session-2026-10-15-verified-cells.md).

| check | finding |
|---|---|
| upload resources | the 6756 manual upload streams through `inc_uploadImg` but the flasher stages whole segments in `/var` temp files (about 54 MiB vs 254 MB tmpfs); `MemAvailable` 267 MB (corrected, see evidence/codex-independent-audit-2026-10-15.md) |
| ATF | byte-proven (section H) |
| U-Boot / rescue | 12 bytes differ from retail, all in the build banner |
| retail kernel | the decompressed `Image` is the stock build's size; 8 string lines differ (banner, initramfs mtimes). Command line comes from the identical DTB |
| NVRAM encryption / login | in the unchanged 25206 `spwenc.o`; `http_passwd` read identically |
| first-boot migration | the same conversions as stock, plus Merlin's versioned `adjust_merlin_config`; no erase or format |
| NVRAM default values | 16 of 1,369 shared keys differ, 3 used by prebuilts (`ntp_server1`, `sshd_port`, `wgc_alive`); relevant only after a factory reset |
| web UI | ASUS's ESLint check, run offline: no parse errors; one new note, in minified `Chart.js` |
| resources | router uses 182 of 508 MB; Merlin's extra daemons are off by default |
| walk (a) boot log | all 1,201 `dmesg` lines map to existing cells |
| walk (b) file tree | same skeleton; `/opt` is Entware's symlink; `/ftpclient` is Merlin's cloud-sync client |
| walk (c) `rc` init, compiled | 98 functions: 52 compile to the same code as stock; `init_switch`, `config_switch`, `init_wl`, `start_wl`, `sync_boot_state` are among them. The 16 that differ are Merlin features or codegen, each attributed |
| walk (d) platform layer, compiled | 442 Broadcom-specific functions: 435 compile to the same code as stock; 7 are newer ASUS code paths that take stock's path or only report on this router's settings. The RT-AXE7800 port table is identical, and br0 STP stays off |

