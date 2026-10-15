# Codex findings: do their triggers apply to the owner's router? (read-only, 2026-10-15)

Commands are logged in `router-commands.txt`. Only counts, sizes and non-sensitive values were read.

| Codex finding | Trigger | Router state | Applies? |
|---|---|---|---|
| 3 DHCP migration corrupts rows | non-empty `/jffs/nvram/dhcp_hostnames` plus mixed-format `dhcp_staticlist` | file absent; `dhcp_staticlist` has 1 entry, 4 fields | no |
| 4/5 OpenVPN `custom` migration, VPN rollback | non-empty `vpn_server*_custom`/`vpn_client*_custom`, `vpnc_clientlist` rows | all custom keys empty; `vpnc_clientlist` empty; `/jffs/openvpn` absent | no |
| 6 LAN-only SSH reachable on WAN | `sshd_enable=2` with `fw_enable_x=0` | `sshd_enable=2`, `fw_enable_x=1` | no (firewall on) |
| 9 OpenVPN server autostart not migrated | configured server in `vpn_serverx_eas` | list is `1,` but server 1 has no proto/port/state/certs and no openvpn process | no (nothing configured) |
| 2 JFFS mount failure erases /jffs | UBIFS mount error | `/jffs` 5% used (2,284 of 45,528 kB); contents are stock logs and caches | inherited ASUS behaviour, not triggered by the image |

Not checked: Wi-Fi, WAN type and other settings the findings do not touch.

## Corrections to earlier claims (from the Codex audit, verified in source)
- "No RAM staging": wrong. `bcm_imgif_pkgtb.c:73-74` sets `PKGTB_USE_TMP_FILES_ALL=1`, so whole segments go to `/var` temp files. Payload is about 54 MiB against 254 MB tmpfs and `MemAvailable` 267 MB, so it still fits.
- "Formatting only when the volume is missing or `ubifs_format=1`": wrong. `rc/ubifs.c` also calls `ubifs_erase()` when the first mount fails (inherited from ASUS).
