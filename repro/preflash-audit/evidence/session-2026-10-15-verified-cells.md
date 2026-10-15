# Cells verified on 2026-10-15

Continuation of [`session-2026-10-14-verified-cells.md`](session-2026-10-14-verified-cells.md). Router
access stayed read-only; every remote command is in [`router-commands.txt`](router-commands.txt).

## S5 — ATF, byte-proven

The build that produced the earlier "1,902 / 1,318 B differ" figures had not reproduced ASUS's
environment. This time ATF was built from scratch through the real bootloader target:

    make atf BUILD_NAME=RT-AXE7800 PROFILE=96756GW BUILD_STRING=<version>

This ran in the stock GPL tree (`axe7800-build` container, GPL toolchain), with a fresh, unbuilt copy
of `bootloaders/armtf` bind-mounted for each run. Nothing in the tree was cleaned or deleted.

| comparison | size | differing bytes | where |
|---|---|---|---|
| retail ATF (router `bootfs2`, `3f876c04…`) vs rebuild with `BUILD_STRING=asuswrt_3.0.0.4.388rc1-dirty` (`978b7858…`) | 24,872 = 24,872 | **10** | offsets 21008–21023, all inside `Built : 21:21:35, May  6 2026` vs `Built : 05:31:57, Oct 15 2026` |
| Merlin v12e ATF (from the `.pkgtb`, `18130187…`) vs rebuild with `BUILD_STRING=3004.388.12_2-40-gf94f6ff8ad-dirty` (`b59a2f71…`) | 24,872 = 24,872 | **7** | offsets 21008–21023, all inside `Built : …` |

The GPL `armtf` sources reproduce the retail ATF exactly, apart from the build timestamp. Merlin's
ATF is that same source and toolchain with a different version string: Merlin's `armtf` tree is
identical to the GPL's (0 differences). So the ATF in the Merlin image **is the retail code**. The
earlier byte counts came only from the version-string length shifting the layout.

## S9 — NVRAM default values (item 10)

The default tables were dumped with [`tools/nvram-defaults-dump.c`](../../../tools/nvram-defaults-dump.c),
compiled against each tree's `defaults.c` and run under qemu-arm. Of the **1,369 keys present in both
tables**, **16 have different values**:
[`nvram-default-value-diffs.tsv`](nvram-default-value-diffs.tsv). Three of them are referenced by
25206 prebuilt objects:

| key | stock | Merlin | effect |
|---|---|---|---|
| `ntp_server1` | `time.nist.gov` | empty | Merlin's second NTP server is empty by default; `ntp_server0` is the same |
| `sshd_port` | empty | `22` | port used only when SSH is enabled |
| `wgc_alive` | `0` | `25` | WireGuard client keepalive, used only when a WireGuard client is enabled |

Defaults apply only to keys missing from NVRAM, which means a factory reset or a key that has never
been set. A web-UI upgrade keeps the router's existing NVRAM. None of the 16 affects boot,
interfaces or storage.

## S10 — web UI (item 11)

- ASUS's own GitHub JS check (ESLint, `no-empty` and parse errors) was replicated offline in
  `node:20.18.0-bookworm-slim`, with the GitHub posting step removed and the dictionary keys
  regex-escaped. It was run over the installed `www` of both images:
  [`www-js-check-stock.json`](www-js-check-stock.json),
  [`www-js-check-merlin.json`](www-js-check-merlin.json).
  - **No parse errors** in either image.
  - Stock has 9 "Empty block statement" findings in 4 files. Merlin has the same 9; its `state.js`
    finding is the same code at line 1215 instead of 1275.
  - Merlin's only new finding is in the minified third-party `js/Chart.js` (81:341).
- The installed wireless pages derive from `www/sysdep/RT-AXE7800` in both builds.
- `btnPressed.png`, `btnReleased.png` and `position.png` are missing in **both** stock and Merlin,
  and no page references them.
- How the UI behaves at run time cannot be checked offline.

## S11 — resources (item 12)

- Router today (retail 25206): 508,152 kB RAM, 182,328 kB used without buffers/cache, 325,824 kB
  free with cache, `MemAvailable` 267,252 kB, 147 processes:
  [`router-resources.txt`](router-resources.txt).
- Merlin's extra services are off by default: `Tor_enable=0`, `nfsd_enable=0`, `ntpd_enable=0`,
  `snmpd_enable=0`, `sshd_enable=0` (`shared/defaults.c`). The router keeps its own `sshd_enable`
  across the upgrade.
- Always on: `haveged` (`/usr/sbin/haveged`, 100,464 B), the entropy daemon.

## Step 3 — adversarial walks

### (a) Router boot log, 1,201 `dmesg` lines, by subsystem

| subsystem (dmesg prefixes) | cell | why the Merlin image cannot differ silently |
|---|---|---|
| early boot, memory map, `psci`, `smp`, `cpuidle`, `arch_timer`, `bcm_rsvmem`, `log_buf_len` | S5/S7 | ATF byte-proven; DTB identical; kernel config identical |
| `bcm63xx_nand`, `nand`, `ubi0`, `UBIFS`, `squashfs`, `jffs2`, `mtdoops` | S3/S7/S9 | MXIC fixes (0007/0008); storage paths identical (`ubifs.c`); flasher write set |
| `pinctrl-bcmbca`, `bcm-bca-gpio`, `bca_extintr`, `bcm-bca-leds`, `bca_led_*`, `brcm-ephyled`, `bcm_i2c`, `bcm63xx-hsspi`, `brcmboard`, `pmc`, `brcm_otp`, `iproc-rng200`, `broadcomThermalDrv` | S7/S8 | built-ins from an identical config and DTB; modules present with 0 unresolved symbols (`depmod`) |
| `pci`, `pcieport`, `bcm-pcie`, `dhd*`, `Dongle`, `wl*`, `CFG80211-ERROR`, `CSIMON`, `WLCSM`, `Wowl`, `igs`, `emf`, `wl_pktfwd` | S8/S10 | `wl.ko`/`dhd.ko` same as retail apart from the build date; `rtecdc.bin` is the GPL copy (14 B build stamp vs retail). This log is retail's, so its `CFG80211-ERROR` lines are normal for this driver build, which Merlin ships too |
| `bcm_enet`, `SYSPORT`, `Archer`, `merlin28_*` / `MerlinSupport` (Broadcom Merlin28 SerDes, not Asuswrt-Merlin), `eth0`–`eth6`, `brcm-rgmii`, `brcm-mdio`, `tr_find_sf2_sw`, `logical_port` | S8/S9 | `init_switch` (1,815 insns) and `config_switch` compile to SAME-CODE; BCM53134 switch configuration identical; `init-broadcom.o` is the ASUS prebuilt |
| `fcache`, `FCACHE_*`, `BLOG`, `pktflow`, `Pathstats`, `[FHW]`, `bdmf`, `M2M`, `spu` | S8 | prebuilt/GPL modules, present, 0 unresolved |
| `usbcore`, `xhci`, `ehci`, `ohci`, `hub`, `sdhci`, `mmc0`, `cdc_acm` | S8/S9 | modules present; `start_usb` and `add_usb_*_modules` attributed (walk c) |
| netfilter, `ebt_*`, `xt_*`, `IMQ`, `PPP`, `l2tp`, `PPTP`, `gre`, `sit`, `8021q`, `IPv6`, `IGMP`, `br0` | S8/S10 | modules present; Merlin's PPP deflate/multilink deltas reviewed (S7) |
| `Tuxera`, `tfat`, `fuse` | S8 | prebuilt filesystem modules present |
| `VFS`, `Freeing`, `Run /sbin/init`, `devtmpfs` | S9 | `/sbin/init → rc` link matches stock; rootfs skeleton identical (walk b) |

No subsystem in the log is outside an existing cell.

### (b) Image file tree, by top-level directory (stock staging `fs/` vs v12e `fs/`)

Identical structure: `bin sbin lib usr rom www tmp var dev proc sys sysroot bootfs data jffs mmc
cifs1 cifs2 webs` are directories in both; `etc home mnt root debug` are the same symlinks into
`tmp`/`sys`.

| difference | cell |
|---|---|
| `opt`: stock directory (14 factory stress-test scripts), Merlin symlink to `tmp/opt` (Entware) | S9, section I of the README |
| `ftpclient/usr/lib/libstdc++.so.6`: Merlin only, from Merlin's `ftpclient-install` (cloud-sync FTP client), loaded only by `ftpclient` | S10 (loader check: 0 Merlin findings) |
| file counts: `bin` +3, `sbin` +3, `lib` +6, `www` +20, `rom` +1, `usr` −114 | S9/S10: symlink, loader and ABI checks; section I |

Every directory is owned by a cell.

### (c) `rc` init order (`sysinit`, `init_main` and everything they call)

[`init-path-compare.py`](../init-path-compare.py) compares sources (preprocessor-aware brace
matching): [`init-path-compare.txt`](init-path-compare.txt).
[`init-path-objcmp.py`](../init-path-objcmp.py) compares the compiled code of each function as built
for RT-AXE7800: [`init-path-objcmp.txt`](init-path-objcmp.txt). For the compiled comparison:

- relocations are limited to the function's own address range (binutils 2.32 prints the whole
  section's relocations with `--disassemble=<fn>`);
- branch targets and literal-pool PC-relative addends are normalised;
- `.LC`/`__func__` labels are resolved to their strings.

The first run lacked those normalisations and reported five functions as different that compile to
the same code.

Result over 98 functions: **52 SAME-CODE**, 25 not compiled for this model in either tree,
16 DIFFERENT-CODE, 4 Merlin-only, 1 stock-only. The hardware bring-up path is SAME-CODE or an
unchanged ASUS prebuilt:

- SAME-CODE: `init_switch`, `config_switch`, `init_syspara`, `init_gpio`, `init_wl`, `start_wl`,
  `init_pass_nvram`, `sync_boot_state`, `chk_same_boot_policy`, the scheduler v1→v2 converters.
- ASUS prebuilts: `reset_psr_hwaddr`, `init_enc_nvram`, `start_gpy211_monitor`.

How each DIFFERENT-CODE function is explained:

| function | cause |
|---|---|
| `init_nvram` | RT-AXE7800 block: Merlin features only (`AllLED`, MSSID prelink, psta BSS disable, `noconsole`, `/etc/shadow`); no interface or port assignment changed |
| `init_nvram2` | Merlin: `webs_state_*` reset, AiMesh `cp_restart` unset, `ovpn_defaults()`; patch 0002 guard around `init_asus_pp_eula()`; stock's `ftp_tls=1` not forced |
| `init_main` | 3 hunks: Merlin's `init-start` user script, `setup_passwd()`, the `fstab` custom-config hooks; `stop_logger()` moved later in the shutdown sequence |
| `handle_notifications` | 43 Merlin hunks. The only platform-conditional one is VPN Director `restart_vpnrouting` calling `amvpn_refresh_wg_bypass_rules()` on 6756. That writes WireGuard client subnets to `/proc/blog/skip_wireguard_network`, stock ASUS's own mechanism (stock `rc/wireguard.c`, present in the v12e kernel), and only for enabled `wgcN` clients |
| `start_lan` | 3 hunks: `set_hostname()`, LAN `udhcpc -H <hostname>`, and the STP condition (walk d: STP stays off on this model) |
| `console_init` | 6756: reads `/proc/environment/noconsole` (the U-Boot env) before applying the NVRAM `noconsole` |
| `setup_conntrack` | larger buffers, trailing-newline trim |
| `restart_wireless` | AiMesh repeater `last_pap` bookkeeping (`re_mode=1` only) |
| `force_free_caches` | Merlin also writes `1` to `/proc/sys/vm/drop_caches` |
| `config_format_compatibility_handler` | calls `adjust_merlin_config()` (Merlin's versioned stock→Merlin migration, S9) |
| `check_services` | Merlin dropped the crond restart check (since 380.68, 2017; every Merlin model) |
| `lanaccess_wl` | Merlin calls `setup_leds()` |
| `start_usb` | Merlin commented out `modprobe ledtrig-usbdev/leds-usb` (commit `489ac3eb2e`); neither module exists in stock or Merlin |
| `add_usb_modem_modules`, `add_usb_host_modules` | identical source; GCC split/inlining differs with the larger translation unit. Function plus `.part` clone call the same targets with the same strings |
| `stop_usb` | one extra `add`: a `.rodata` offset beyond one immediate. Layout only |

Merlin-only functions: `adjust_merlin_config` (S9), `run_custom_script`, `use_custom_config` and
`run_postconf`. The last three are Merlin's user-script hooks and run only the files a user has put
in `/jffs/scripts` and `/jffs/configs`. Stock-only: `adjust_vpnc_config` (Merlin replaces it).

### (d) Platform layer: every function in the Broadcom-specific objects

Walk (c) found a model-relevant difference in a helper outside the init path (`start_lan` STP, via
`ext_switch_exist()`). So every function defined in the platform objects was compared as compiled:
`shared/broadcom.o` (from `shared/sysdeps/broadcom/broadcom.c`), `shared/bcm_stamon.o`, and
`rc/{broadcom,init-broadcom,ate-broadcom,wps-broadcom,agg_brcm,tcode_brcm,obd-broadcom,roamast-broadcom,conn_diag-broadcom,amas-ssd-broadcom,amas-ssd-cd-broadcom}.o`.
Results: [`platform-objcmp.txt`](platform-objcmp.txt). **442 functions: 435 SAME-CODE, 7
DIFFERENT-CODE**, all attributed:

| function | cause | effect on this router |
|---|---|---|
| `get_phy_port_mapping` | inlines `swap_wanlan()`, which gained an ASUS 388_25373 guard: no WAN/LAN label swap while `x_Setting=0` | the RT-AXE7800 port table is **identical** (W0 2.5G `eth0`, L1–L4 1G, U1). The guard matters only before the setup wizard; the router has `x_Setting=1` |
| `add_sw_wan_cap` (inline) | ASUS 388_20566 code: when IPTV is configured, the primary-WAN capability flag goes to the WAN-capable port even if the WAN ifname doesn't match a port | active here (`switch_wantag=manual`). The flag only feeds port-status reporting. Its one `rc` user (`wan.c` Starlink check) reads it only for 2.5G ports without an ifname, and W0 has `eth0` |
| `get_wlan_service_status` | newer ASUS code: returns -1 when `hapd_enable=1` and `hostapd_cli -i <if> ping` gets no `PONG` | `hostapd_cli` is in v12e. Stock already returns -1 while Wi-Fi is not ready (`wlready=0`), so callers (`rc`, AiMesh `cfg_server`/`cfg_client`) handle it |
| `get_psta_status` | newer ASUS code: PSTA state from `wpa_cli-2.7 … status` instead of the `autho_sta_list` ioctl | media-bridge/repeater modes only (`sw_mode=1` here); `wpa_cli-2.7` is in v12e |
| `set_wlan_service_status` | same source and same call/string targets; inlining differs | none |
| `stop_wps_method`, `start_wps_method` | newer ASUS code: AiMesh VIF-onboarding WPS (`wps_via_vif`) and repeater (`re_mode`) paths | router mode without `wps_via_vif` takes stock's path |

Also checked: `start_lan` STP. Stock always runs `brctl stp br0 0` on HND. Merlin, with ASUS
388_25523 code, uses `lan_stp` when an external switch port exists (`ext_switch_exist()`). Every
RT-AXE7800 port has `ext_port_id = -1`, so STP stays **off** as in stock. The router has
`lan_stp=1` and STP is off today. `brctl setfd br0 0` and `hnd_set_hwstp` (SAME-CODE) are unchanged.

### Applicability to the final image

These object comparisons used the local `v12b` build tree. Its installed `sbin/rc` is
**byte-identical** to v12e's (`7cdaf3b1…`). Its `libshared.so` differs from v12e's in 4 bytes of
`.rodata`, the build timestamp only.

### Field history

None of the models Merlin 3004.388 lists as supported (`README-merlin.txt`) uses the BCM6756. The
newer ASUS code paths that Merlin carries have therefore not run on this SoC under Merlin. They come from
ASUS's own later 388 releases, but this remains a residual risk, not a verified cell.

**Walks (a), (b) and (d) produced no new cell. Walk (c) produced the platform-layer row, which was
checked in (d).**
