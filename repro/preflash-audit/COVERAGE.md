# Pre-flash audit: coverage matrix

Subject: `RT-AXE7800_3004_388.13_alpha1_nand_squashfs.pkgtb` (v12e, sha256 `1ec1b5d1…`).

Reference images:
- the unmodified GPL 25206 stock build;
- the owner's router's own retail volumes (`bootfs2`, `rootfs2`, `/dev/mtd1`), read over a read-only
  SSH session ([`evidence/router-commands.txt`](evidence/router-commands.txt)).

Every cell in the matrix ends in one state:

- **V**: verified offline, with the evidence named.
- **NV**: not verifiable offline, with the concrete reason.
- **N/A**: the property does not apply to that stage.

The audit stops when no cell is open.

Sources referenced in the cells:
- §A–§J are the sections of [`README.md`](README.md).
- **E14** is [`evidence/session-2026-10-14-verified-cells.md`](evidence/session-2026-10-14-verified-cells.md).
- **E15** is [`evidence/session-2026-10-15-verified-cells.md`](evidence/session-2026-10-15-verified-cells.md).

## Stages

S1 upload in the stock web UI → S2 image validation → S3 flash write and metadata → S4 reboot and
slot selection (loader/TPL) → S5 ATF → S6 U-Boot proper (env, rescue, kernel load) → S7 kernel
boot (DTB, cmdline, built-in drivers) → S8 module loading → S9 rootfs and `rc` init (NVRAM, JFFS,
migration of the existing stock settings) → S10 services (Wi-Fi, switch/LAN/WAN, `httpd`/login)
→ S11 steady state → S12 way back (Merlin → stock, rescue).

## Matrix

| | format / compatibility | provenance vs retail | symbol / ABI | config / data | resource limits | failure / recovery |
|---|---|---|---|---|---|---|
| **S1** upload | **V** stock `httpd` accepts a `.pkgtb` whose FIT description is `RT-AXE7800`; `check_imagefile()` returns 0 on this platform (§B, §J) | **N/A** stock code does the work (`httpd` byte-identical to retail) | **N/A** | **V** upload does not touch NVRAM (§J) | **V** streamed into flash by `inc_uploadImg`, no RAM staging or size cap; `MemAvailable` 267 MB (E14 S1) | **V** a failed upload leaves the running slot untouched; only the inactive slot is written (§J) |
| **S2** validation | **V** every subimage `hash-1` (sha256) matches (§B, §G) | **V** retail carries no FIT signatures, so the loader accepts hash-only images (§H) | **N/A** | **V** configuration holds only `description bootfs rootfs compatible`, no `loader` (§J) | **V** slot 1 = 455 LEBs, Merlin needs ≈447 (§A) | **V** `public.pem` / `rsasign` used only by online upgrade (§J) |
| **S3** write + metadata | **V** writes `bootfs`/`rootfs` volumes 3/4 or 5/6 + metadata, matching this router (§J) | **N/A** stock flasher | **N/A** | **V** `data`, `defaults`, `jffs2` never written; loader not written (§J, §B) | **V** UBI free 416 LEBs (§A) | **V** manual upgrade sets `BOOT_SET_NEW_IMAGE_ONCE`: old image stays committed, boot reason `ACTIVATE` (E14 S3/S4) |
| **S4** slot selection | **V** router's TPL/SPL (2019.07, 15 Dec 2022) already boots the 25206-generation `bootfs`; same slot strings (E14 S4) | **V** loader is not replaced (§B) | **V** nested `bootfs` FIT has the same images and configurations as stock ([`bootfs-contents.txt`](evidence/bootfs-contents.txt)) | **V** U-Boot env untouched (§A) | **N/A** | **V** activation is one-shot; a power cycle or a reboot before `rc` commits boots stock (E14 S3/S4) |
| **S5** ATF | **V** same FIT node and load config (§B) | **V** **byte-proven**: GPL rebuild = retail except the 10-byte timestamp; Merlin's = GPL rebuild with Merlin's version string except the 7-byte timestamp (E15 S5) | **V** same code | **N/A** | **N/A** | **V** same code as retail, so the same behaviour |
| **S6** U-Boot | **V** `fdt_uboot` identical (§B, §H) | **V** 12 differing bytes vs retail, all in the build banner, patch 0007 included (E14 S6/S12) | **V** same binary apart from the banner | **V** compiled-in defaults identical; `secboot=1` not enforced by retail (§H) | **N/A** | **V** ASUS rescue code byte-identical to retail (E14 S6/S12). **NV** whether rescue works on *this unit*: needs the owner's button test (§E.1) |
| **S7** kernel | **V** LZO `kernel` subimage; `fdt_RT_AXE7800` identical (§B) | **V** retail `Image` = stock size, 8 string lines differ (banner, initramfs mtimes); Merlin's deltas attributed (E14 S7) | **V** one vermagic; `CONFIG_MODVERSIONS` off in both (§C) | **V** running config = stock `.config`; Merlin's 34 lines reviewed (§J); cmdline from identical DTB, `CONFIG_CMDLINE` not forced (E14 S7) | **V** `Image` 11,761,836 B vs 11,761,976 B | **NV** boot on silicon: no UART, QEMU has no BCM6756 model. A failure here falls back to stock (S4) |
| **S8** modules | **V** 0 unresolved symbols across 153 modules (§C, §G) | **V** `wl.ko`/`dhd.ko` = retail apart from build date; `rtecdc.bin` = GPL copy, 14 B build stamp vs retail (§A, §C) | **V** struct agreement rests on identical `include/` trees and config (§C) | **V** every module loaded on the router today, and every module stock `rc` names, exists (§I) | **N/A** | **NV** driver behaviour on hardware. Falls back to stock if it stops `rc` before the commit (S4) |
| **S9** rootfs + `rc` init | **V** `/sbin/init → rc`, same rootfs skeleton (§C, E15 walk b) | **V** init path: 52 functions compile to the same code as stock, the rest attributed; `init-broadcom.o`, `ate.o`, `spwenc.o`, `gpy211_war.o` are the 25206 prebuilts; platform layer 435/442 same code, 7 attributed (E15 walks c, d) | **V** loader check, 267 programs, 0 Merlin findings; static ABI closure identical; `nvram show` reaches `invalid_program_check` (§C) | **V** NVRAM encryption in unchanged `spwenc.o`; erase/format triggers unchanged; migrations reviewed (`adjust_merlin_config`, sched v1→v2, `computer_name`); 16 default-value differences, factory-reset only (E14 S9, E15 item 10, §D) | **V** same `jffs2` UBIFS volume and tmpfs layout (§I) | **V** `sync_boot_state()` compiles to the same code as stock and commits only after `start_misc_services()` (E14, E15 walk c). **NV** run-time behaviour of `rc` |
| **S10** services | **V** web UI: no JS parse errors; one new lint note, in minified `Chart.js` (E15 item 11) | **V** `init_switch`, `config_switch`, `start_wl`, `init_wl` same code as stock; RT-AXE7800 port table identical; STP stays off (E15 walks c, d) | **V** libwebapi 34/34 contract ([intake](../intake/INTAKE-388_25206.md)); AiMesh prebuilts resolve (§C) | **V** `http_passwd` read identically (E14 S9); router's NVRAM kept by a web upgrade (§D) | **N/A** (S11) | **NV** Wi-Fi, switch and UI behaviour at run time |
| **S11** steady state | **N/A** | **V** Broadcom userspace (`wdtctl`) identical to the GPL (§I) | **V** as S9 | **V** Merlin extras (Tor, NFS, ntpd, SNMP) default off; `sshd_enable` kept from the router (E15 item 12) | **V** router baseline 182 MB used of 508 MB, 147 processes; Merlin adds `haveged` (100 KB) (E15 item 12, [`router-resources.txt`](evidence/router-resources.txt)) | **NV** long-run stability, memory growth and Merlin's `rc` watchdog semantics on this SoC |
| **S12** way back | **V** Merlin's `httpd` upload check accepts the stock image (§I) | **V** rescue code = retail (S6) | **N/A** | **V** NVRAM kept; all 56 stock-only keys referenced by 25206 prebuilts are set on this router (§D) | **V** same slot layout as the stock image | **V** boot-once fallback before commit (S4); rescue from U-Boot (S6). **NV** rescue on this unit (§E.1) |

## Cells that cannot be verified offline, and why

| cell | reason | mitigation in place |
|---|---|---|
| S7, S8, S9, S10, S11 run-time behaviour | needs BCM6756 silicon: the owner has no UART, and QEMU cannot emulate the SoC, its NAND controller, Runner/Archer or the Wi-Fi offload | anything that stops boot before `rc` commits falls back to stock on reboot or power cycle (S3/S4). After the commit, the way back is Merlin's web UI or rescue mode |
| S6, S12 rescue on this unit | ASUS rescue is in the U-Boot code (byte-identical to retail), but whether the unit enters it can only be tested at the button | owner's checklist §E.1, done on stock before any flash |
| Merlin userspace semantics | Merlin is a different firmware. Symbols, versions, structs, NVRAM keys, the init path and the platform layer are verified; the semantics of every Merlin feature are not. No model Merlin 3004.388 lists as supported uses the BCM6756 | Merlin's extra services are off by default; the boot/commit/rescue cells above |

## Method and completeness

1. The matrix: every stage crossed with every property class, each cell filled from evidence.
2. Four independent walks re-derived the cells (E15):
   - (a) every subsystem in the router's 1,201-line boot log;
   - (b) every top-level directory of the image;
   - (c) every function `rc` runs at init, compared as source and as compiled code;
   - (d) every function in the Broadcom platform objects, compared as compiled code.

   Walk (c) found the platform-layer row, which (d) then covered. Walks (a), (b) and (d) found
   nothing outside the matrix.
3. Corrections made along the way, kept visible:
   - "no automatic fallback" was wrong: the upgrade is boot-once until `rc` commits (E14 S3/S4).
   - ATF was first reported as "strongly indicated". It is now byte-proven (E15 S5).
   - The compiled-code comparison first counted relocations from the whole section, which
     overstated five functions as different. It now limits relocations to each function (E15 walk c).

No open cell remains. The NV cells need hardware and are listed above with their reasons.
