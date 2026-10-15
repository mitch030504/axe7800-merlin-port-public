# Merlin baseline for the 25206 port — decision record

**Recommendation: `asuswrt-merlin.ng` branch `3004.388`, pinned at `f94f6ff8ad` (388.13 alpha1,
2026-10-04).** It is the same ASUS 388 codebase as GPL 3.0.0.4.388.25206. On every measure
that can tell the candidates apart it is several times closer to the GPL than either 3006.102
candidate, and it never comes out worse.

The upstream research chose `3006.102-wifi6` @ `ccd139a3`, a reasonable choice while only
GPL 388.34458 was available. Now that a same-generation package exists, measurement favours
the 388 line.

## Candidates

| label | ref | version | note |
|---|---|---|---|
| pin | `ccd139a31d94` | 3006.102.8_2 (2026-07-28) | upstream research baseline |
| tip | `3006.102-wifi6` @ `2df5b849fd` | 3006.102.10 alpha1 (2026-10-04) | fast-forward of pin (+83 commits; 27 touch shared/rc/httpd/libwebapi) |
| m388 | `3004.388` @ `f94f6ff8ad` | 388.13 alpha1 (2026-10-04) | diverged from 3006.102 at `d2532f2089` (2024-06-07), +459 commits since |

Reference: GPL `3.0.0.4.388.25206-gcaa73b5` (see [`../intake/INTAKE-388_25206.md`](../intake/INTAKE-388_25206.md)).

## 1. Prebuilt link/ABI closure — by name: no difference

Consumers: the 136 ARM32 ELF files under the GPL's `release/src/router/*/prebuild/`. That is
76 relocatable objects (link-time) and 60 executables or `.so` files (run-time imports). They
import 1,238 symbols not provided by other prebuilts. **879** of these have an open C
definition in the GPL tree, so a Merlin tree must define them too.

| | pin | tip | m388 |
|---|---|---|---|
| open-provided symbols not defined by the candidate | 15 | 15 | 15 |

The 15 are the same in all three. All are libc functions (`alarm`, `memchr`, `openlog`,
`sysinfo`, …) that happen to have a source copy somewhere in the GPL tree, so they are not
real gaps. **Every candidate satisfies the 25206 prebuilts at symbol-name level.** Names alone
do not discriminate, so ABI shape decides.

Method: `nm -u` / `nm -D -u` on consumers, then column-0 non-static C definitions from
`git grep` (candidates) and from the extracted GPL. The script is kept with the evidence.

## 2. Header / struct ABI drift — decisive

Lines differing from the GPL (`diff | grep -c '^[<>]'`):

| header | pin | tip | m388 |
|---|---|---|---|
| `shared/shared.h` | 1351 | 1352 | **125** |
| `rc/rc.h` | 689 | 692 | **101** |
| `httpd/httpd.h` | 51 | 51 | **15** |
| `libwebapi/webapi.h` | 56 | 56 | **0** |
| `rc/sysdeps.h` | 50 | 50 | **0** |
| `shared/shutils.h` | 41 | 41 | **0** |
| `shared/wlif_utils.h` | 183 | 183 | **2** |
| `shared/notify_rc.h` | 12 | 12 | 12 |

Type definitions (struct/union/enum bodies, comments stripped, `#ifdef`s kept) that differ
from the GPL:

| header | pin / tip | m388 |
|---|---|---|
| `shared/shared.h` (42 types) | 9: `enum btn_id`, `enum led_id`, `enum wl_band_id`, `enum conndiagEvent`, `enum romaingEvent`, `struct ASUS_PP_table`, `struct __amaslib_notification__t_`, `AMASLIB_EVENT_T`, `rtk_stat_port_cntr_t` | 2: `enum conndiagEvent`, `struct ASUS_PP_table` |
| `rc/rc.h` (32) | 2: `backhaul_period_s/_t` | 0 |
| `httpd/httpd.h` (20) | 1: `model_stb_port` | 0 |
| `shared/wlif_utils.h` (25) | 2: `wlif_dpp_config_settings`, `wlif_dpp_creds_t` | 0 |
| `libwebapi/webapi.h` (2) | 1: `RWD_MAPPING_TABLE` | 0 |
| **total** | **15** | **2** |

This is the criterion that matters for prebuilt objects. Enum values such as `led_id`,
`btn_id` and `wl_band_id`, and struct layouts, are compiled into the ASUS `.o` files. A
mismatch links cleanly and then misbehaves at runtime: the wrong LED, the wrong band index,
corrupted fields. The two m388 differences are in the CONNDIAG event enum and the privacy-policy table. They
are small and can be reconciled against the GPL in Phase 4.

## 3. Source / Makefile generation drift

Per component, files present in the GPL (`.c .h Makefile .asp .js`, excluding `prebuild/`):

| component | GPL files | identical pin/tip/m388 | differing pin/tip/m388 | diff lines pin/tip/m388 |
|---|---|---|---|---|
| shared | 187 | 76 / 76 / **111** | 54 / 54 / **21** | 11273 / 11336 / **1347** |
| rc | 137 | 48 / 47 / **79** | 80 / 81 / **49** | 35720 / 36294 / **6831** |
| httpd | 35 | 24 / 24 / **26** | 8 / 8 / **6** | 7480 / 7490 / **1385** |
| libwebapi | 3 | 0 / 0 / **1** | 3 / 3 / **2** | 659 / 659 / **62** |
| libdisk | 15 | 9 / 9 / **14** | 6 / 6 / **1** | 284 / 284 / **64** |
| www | 471 | 168 / 168 / **242** | 202 / 202 / **154** | 50409 / 50922 / **18873** |

Remaining m388 differences include Merlin's own feature work, which every candidate carries.
The 3006 surplus is the generation gap.

## 4. SDK and drivers

| | pin / tip | m388 |
|---|---|---|
| Broadcom SDK (`version.make`) | 5.04L.02p1 | 5.04L.02p1 |
| wl `impl87` `EPI_VERSION_STR` | 17.10.188.6401 (r808804) | 17.10.188.6401 (r808804) |
| `kernel/dts/6756` + `targets/96756GW` vs GPL | 61 lines differ | **identical** |

The driver and SDK level is the same everywhere. The 6756 device tree and the 96756GW profile
match the GPL byte for byte only on m388.

## 5. Port effort

| item | pin / tip | m388 |
|---|---|---|
| HND-96756 stanza present | no | no (same work either way) |
| patch 0007 `get_fh_if_prefix_by_unit` guard | needed (cross-product dependency exists) | **not needed**: neither m388 nor the GPL has the function |
| patch 0008 `hnd_boardid_cmp` guard | applies | applies, but **unnecessary with 25206**: GPL prebuilts define `hnd_boardid_cmp` |
| patches 0003–0006, 0009 | depend on GNUton TUF-AX3000_V2 platform tree | same; replaced by GPL 25206 platform files in v12 |
| GNUton donor platform files | required (v11) | not required: GPL ships `archer.o`, `bcm_enet.o`, `bcmmcast.o`, `bcm_cleds.o`, `bcm_license.o`, phy prebuilts, `router-sysdep` |

## 6. Maintenance

Both branches are active: since 2026-07-01, 88 commits on 3004.388 and 112 on 3006.102-wifi6,
and both were last updated 2026-10-04. ASUS ships RT-AXE7800 on the 388 line (retail 388_25206),
so the 3004.388 branch is the one that tracks this model's vendor code.

## Decision

| criterion | winner |
|---|---|
| name-level closure | tie |
| header/struct ABI | **m388** (2 vs 15 type mismatches) |
| source generation | **m388** (5–8× less drift) |
| SDK/drivers | tie; DTS/profile identical only on m388 |
| port effort | **m388** (0007 unnecessary) |
| maintenance | tie |

Use **3004.388 @ `f94f6ff8ad`**. pin and tip are equivalent to each other on every measure,
so moving within the 3006 line would not help.

Risk accepted: work done on the 3006 line (`clean-replay-v11`) does not carry over directly.
Its patches 0007/0008 and the GNUton platform import fall away. 0001's target stanza is
rewritten from ASUS's 25206 `target.mak`.
