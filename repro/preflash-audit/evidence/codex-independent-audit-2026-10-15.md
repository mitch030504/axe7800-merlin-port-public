What this repo does: it combines Merlin 3004.388 userspace with ASUS GPL 388.25206 platform code and same-model proprietary components for the RT-AXE7800. This review assumes one router with existing stock settings, no UART, and ASUS rescue as its only independent recovery interface.

**Independent pre-flash audit, 15 October 2026 — NO-GO for the owner's router.**

I found concrete settings-loss, security, and flash-error-handling defects that the earlier audit did not close. I did not establish a deterministic hard-bricking defect in this exact image. Its container, checksums, board DTBs, and module symbol closure pass the independent checks below. Passing those checks does not establish safe first boot, preserved settings, or dependable recovery.

**Subject and evidence conventions**

Image: `RT-AXE7800_3004_388.13_alpha1_nand_squashfs.pkgtb`, 56,726,740 bytes, SHA-256 `1ec1b5d1b6b965bc684d1b667c1f1e0d743cbeae16e3e9e732c2b96ff32f0561`.

Paths used below:

- `P` = `/home/mitchell/gemini/axe7800`.
- `G` = `/home/mitchell/axe7800-work/pkg/gpl-25206/asuswrt/release`.
- `M` = `/home/mitchell/axe7800-work/merlin/v12b/release`.
- `S` = `/home/mitchell/axe7800-work/stock/asuswrt/release`.
- `A` = `/tmp/axe7800-independent-audit-20261015` — this report and all generated audit artifacts.
- `R` = `A/rootfs`, independently extracted from the exact image, rather than assumed to match the supplied extraction.

The inspected local `M` tree is not the remote v12e build tree. Its installed `/sbin/rc` is byte-identical to the exact image: SHA-256 `7cdaf3b17b41e786a3cfbc5d95d1fc6db7142ccf13681bd405c72b05c17d3a84`. The inspected local libovpn `.text`, `.rodata`, `.data`, and `.dynsym` also match the final image. Kernel claims below use the exact decompressed image and embedded configuration. Other source-to-final-build relationships are stated as limitations, not silently assumed.

No router access was used. No router state, repository file, GPL source, or existing work tree was changed; nothing was deleted, flashed, committed, or pushed. All audit-generated files are under `A`. Two independent scoped reviews covered kernel/modules and settings/rollback; their evidence is retained there. No private symbols were stubbed and no donor firmware was used.

**Must fix or explicitly resolve before flashing**

1. **High — the new slot is committed without a working-management or recovery test.**

   **Evidence:** `M/src/router/rc/init.c:20968–21001,21864–21884`; numbered extracts in `A/source-evidence.txt`. `sync_boot_state()` calls `setBootImageState(BOOT_SET_NEW_IMAGE)` based on partition policy. Its call follows `start_misc_services()` without testing that function's result, LAN reachability, successful web login, radio readiness, or sustained operation.

   **Failure case:** `rc` gets that far while `httpd`, a network service, or a radio fails asynchronously. Merlin is committed even though it is unusable. Power cycling then selects Merlin again. The earlier audit acknowledged a pre-commit window, but “services started” must not be read as “services verified healthy.” A surviving old slot also does not restore shared settings changed earlier in boot.

   **Required resolution:** obtain actual boot, management, reboot, rollback, and rescue evidence on a recoverable test unit with this exact image, or implement and test a commit policy that checks the necessary health conditions. For this owner, an untested rescue path cannot substitute for that evidence. This is a known design limitation made decisive by the no-UART constraint, rather than a newly discovered image-format defect.

2. **High, inherited ASUS behavior — a JFFS mount failure can erase persistent data without a format request.**

   **Evidence:** `M/src/router/rc/ubifs.c:60–120,238–255`. If `mount(...,"ubifs",...)` fails, `start_ubifs()` calls `ubifs_erase()`, which calls `ubifs_unlock()`. That routine erases LEBs and invokes `mkfs.ubifs`. The compiled `ubifs.o` retains the mount → unlock → mount path (`A/start-ubifs-disasm.txt`, calls at offsets `0x330`, `0x34c`, `0x36c`). The installed `rc` matches the image.

   **Failure case:** a filesystem compatibility, corruption, or transient mount failure enters destructive recovery. `/jffs` includes persisted NVRAM files, VPN material, SSH keys, and other settings. Neither switching firmware slots nor reflashing stock reconstructs erased files.

   **Required resolution:** preserve an independently restorable backup and make the first-boot path fail safely on an unexplained mount failure. This predates the port; it is not evidence that v12e will trigger it. It directly disproves E14's claim that formatting happens only for a missing volume or `ubifs_format=1`.

3. **High, conditional — the DHCP migration can corrupt reservations and save the damaged result.**

   **Evidence:** `M/src/router/rc/format.c:250–314`; `_vstrsep()` at `M/src/router/shared/shutils.c:2039`. The splitter replaces `>` delimiters with NULs. For an already-complete four-field reservation, the migration then copies `entry`, which now contains only the MAC address. If another three-field row sets `converted`, it saves the entire damaged list and removes `dhcp_hostnames`.

   **Reproduction:** `python3 A/check_migrations.py` compiles the actual extracted parsing loop and actual `_vstrsep()` against synthetic, non-secret input. `A/dhcp-migration-result.txt` records:

   ```text
   input:  <02:00:00:00:00:01>192.0.2.2>>kept<02:00:00:00:00:02>192.0.2.3>
   result: 02:00:00:00:00:01<02:00:00:00:00:02>192.0.2.3>>migrated
   converted=1
   ```

   The first reservation loses its address and hostname. This requires a nonempty `/jffs/nvram/dhcp_hostnames` file and mixed reservation formats; their presence on this owner’s unit was not checked.

   **Smallest fix:** reconstruct complete rows from the split fields, retain separators, and add this mixed-format regression case. Until then, rule out the trigger using a protected settings inventory or fix the migration before flashing.

4. **High, conditional — OpenVPN migration deletes its source even when replacement storage fails.**

   **Evidence:** `M/src/router/rc/format.c:97–126,136–165`; `M/src/router/libovpn/openvpn_config.c:410–438`. `set_ovpn_custom()` returns `-1` when its JFFS write fails. The migration ignores that return and unsets the old NVRAM keys anyway; some `custom2` branches unset them before attempting the write. `format.c:374–375` commits if any `need_commit` branch fires.

   **Failure case:** `/jffs` is full, unwritable, or unavailable. The replacement directives are absent or incomplete while the original is removed. A nonempty server `rgw` key, another migration, or a later ordinary commit can persist the loss. There is no failure propagated to prevent boot-slot commitment.

   **Smallest fix:** check a complete successful write before deleting any original; abort migration on failure. Preserve source settings until successful migration and rollback have been demonstrated. `A/rollback-review/final-libovpn-disassembly.txt` confirms the final-image writer and return behavior; no filesystem failure was induced on hardware.

5. **High when existing VPN settings matter — falling back to stock does not roll configuration back.**

   **Evidence:** the same `format.c` migrates `vpn_{server,client}N_custom` into `/jffs/openvpn/vpn_{server,client}N_custom3` and removes the originals. Lines `171–193` translate and remove server `rgw`/`plan`. Lines `339–370` remove OpenVPN and WireGuard rows from `vpnc_clientlist`. These paths are compiled for this target. Stock’s UI/defaults and libvpn use the old settings, and its library has no `custom3` string. Stock getter disassemblies and numbered source evidence are in `A/rollback-review/`.

   **Failure case:** migration succeeds, then a later boot failure sends the router back to the old stock slot. Stock now sees altered shared NVRAM/JFFS: custom directives and original profile/policy records are gone from the locations it reads. This can break VPN access or routing policy even though the firmware fallback itself works.

   **Required resolution:** keep a protected stock settings/JFFS backup and demonstrate restoration, or make migrations reversible and retain originals. Deliberately replacing VPN Fusion with Merlin behavior is not itself a port bug; treating the resulting rollback as settings-preserving is wrong. I did not inspect this owner’s VPN configuration or claim an actual traffic leak.

6. **High, conditional security regression — LAN-only SSH can become WAN-reachable when the firewall is disabled.**

   **Evidence:** stock `G/src/router/rc/ssh.c:88–91` binds Dropbear to `lan_ipaddr` when routing with LAN-only SSH. Merlin `M/src/router/rc/ssh.c:70–73` comments out that binding and supplies only a port. Merlin `rc/firewall.c:3559` initializes INPUT ACCEPT; lines `3853–4263` add the filtering and final drop only when `fw_enable_x=1`. Numbered evidence is in `A/rollback-review/source-evidence.txt`.

   **Failure case:** preserve stock `sshd_enable=2` and a disabled firewall in router mode. The old firmware restricts the listening address; Merlin listens on WAN too. SSH authentication still applies. With the normal enabled firewall, the explicit WAN SSH allow remains restricted to `sshd_enable==1`; actual owner exposure was not established.

   **Smallest fix:** retain the stock LAN binding for LAN-only mode, or otherwise enforce that restriction independently of the optional firewall. Inventory the actual setting combination before treating this condition as absent.

7. **High, inherited ASUS defect — a failed flash writer child can be accepted as success.**

   **Evidence:** `G/src-rt-5.04axhnd.675x/router-sysdep/bcm_flashutil/bcm_imgif_pkgtb.c:1704–1733` uses `wait(&child_ret)`, applies `WEXITSTATUS` without checking `WIFEXITED`, ignores `wait()` failure/PID identity, and decrements its outstanding-writer count regardless. `httpd/httpd.c:2446` installs `chld_reap`; `shared/misc.c:2994` implements it as `waitpid(-1,NULL,WNOHANG)` until no child remains. The flash library has no signal-mask/handler imports to protect that wait. The exact library is byte-identical to the stock build, SHA-256 `f8353f6be8fdf6a1c3f4dbaa8c490e66b4217265825b341c3d3d3c5e9686318d`.

   **Binary confirmation:** `llvm-objdump -d --disassemble-symbols=imgif_pkgtb_close R/lib/libbcm_flashutil.so` (`A/flashutil-disasm.txt`) shows `wait@plt` at `0x1a944`, immediately followed by loading the exit-status byte at `0x1a948`, with no termination/error check.

   **Controlled host checks:** `A/wait-status.c` demonstrates SIGKILL status `9` becomes `WEXITSTATUS=0`. `A/reaped-child.c` reproduces the HTTP handler reaping an `_exit(1)` child before the library-style wait:

   ```text
   failed child reaped by SIGCHLD handler: wait=-1 errno=10 interpreted_exit=0 write_fails=0
   ```

   **Consequence:** an OOM-killed, failed, or already-reaped writer can escape the completion-error check and allow an incomplete slot to be marked valid. This does not prove the old committed slot is destroyed, or that every upgrade hits the race. It invalidates a blanket claim that failed uploads/writes are correctly reported.

   **Smallest fix:** track the actual writer PIDs, prevent competing reaping, retry interrupted waits, and require successful normal exit. The initial stock-UI flash uses the running stock writer, so fixing only the candidate image cannot repair that first upload path.

8. **Medium, inherited ASUS defect — metadata write failures are discarded.**

   **Evidence:** `G/.../router-sysdep/bcm_flashutil/bcm_flashutil.c:1246–1289` overwrites the first metadata-copy result with the second. `commit()`, `setImgValidStatus()` (`1380–1397`), and `setImgSeqNum()` (`1418–1433`) discard `set_metadata_val()`’s result and return success after a successful read. The image finalizer also ignores their returns.

   **Binary confirmation:** `A/flashutil-disasm.txt` shows `setImgValidStatus` calling the metadata writer at `0xb6a4`, then returning the earlier read result from `r4` at `0xb6a8`. `A/metadata-writer-disasm.txt` shows the two-copy writer. These are instructions from the actual image library, not just source speculation.

   **Failure case:** a metadata `ubiupdatevol` operation fails but upload/commit code reports success. One copy can retain an older, valid-CRC state; subsequent slot selection can differ from the UI’s apparent result. Redundancy helps with interrupted writes but does not make ignored errors harmless.

   **Smallest fix:** propagate failures through every layer and verify the selected persistent state. This is another running-stock first-flash limitation; no NAND fault injection was performed and no specific unavoidable bricking outcome is claimed.

9. **Medium — stock OpenVPN server autostart is not migrated.**

   **Evidence:** stock `G/src/router/shared/defaults.c:3554` and `www/Advanced_VPN_OpenVPN.asp:176,711,1614` use `vpn_serverx_eas`. Merlin `M/src/router/libovpn/openvpn_control.c:727–741` starts servers using only `vpn_serverx_start`, whose default at `shared/defaults.c:3561` is empty. A recursive search of Merlin `rc`, `libovpn`, `shared`, and `httpd` found no conversion/read of `vpn_serverx_eas`. Final libovpn executable sections match the inspected source build.

   **Failure case:** an enabled stock OpenVPN server does not start automatically under Merlin until configured through Merlin’s mechanism. That can remove an existing remote-management path while LAN and web startup still succeed and the image commits.

   **Smallest fix:** migrate the enabled-server list once, preserving the original, and verify the result. This owner’s enabled-server state was not inspected.

10. **Medium assurance defect — the earlier compiled-code comparator can hide real behavior changes.**

    **Evidence:** `P/repro/preflash-audit/init-path-objcmp.py`, `disasm()`, replaces every matching three-or-more-digit hexadecimal-looking token with `ADDR`, replaces all branch destinations with `ADDR`, and discards some literal-pool words as layout. It also limits local string comparisons to 80 bytes. This is not an equivalence proof for control flow, numeric constants, or referenced data.

    **Reproduction:** `A/comparator-counterexamples.txt`, using the script’s normalization expressions:

    ```text
    cmp r0, #100 == cmp r0, #999 => cmp r0, #ADDR
    beq 100 <good> == beq 200 <bad> => beq ADDR
    mov r0, #100 == mov r0, #999 => mov r0, #ADDR
    ```

    **Consequence:** the reported 52/435 “SAME-CODE” counts are screening results, not verified semantic equality. I did not demonstrate a specific dangerous platform function hidden by this normalization.

    **Smallest fix:** preserve numeric operands and compare branch destinations within the function’s control-flow graph; resolve literal data precisely. Calibrate with deliberately changed constants, branch targets, and referenced data. The new migration findings also disprove the audit’s broader assertion that every remaining offline-checkable issue had been exhausted.

11. **Medium assurance/resource issue — the upgrade stages payloads in RAM, and the stated flash budget omits reservation overhead.**

    **Evidence:** `G/.../bcm_flashutil/bcm_imgif_pkgtb.c:73–74` sets `PKGTB_FORKED_WRITES=1` and `PKGTB_USE_TMP_FILES_ALL=1`, explicitly downloading entire segments into `/var`. `init_storage_dev():874–882` opens `/var/{bootfs,rootfs}.tmp`; hashing precedes volume recreation and writing. Incremental HTTP buffering is only one layer of the path.

    **Measured image:** bootfs `10,121,512` bytes plus rootfs `46,604,288` bytes, about `54.10 MiB` of payload potentially resident in tmpfs while writes overlap, plus process/buffer overhead. At a 126,976-byte usable LEB, the default extra 1 MiB per segment requires `88+376=464` LEBs, rather than approximately 447. Environment overrides can change the extra reservation.

    **Consequence and bound:** using the prior audit’s unrefreshed snapshot of 455 inactive-slot LEBs plus 416 free LEBs, 464 still fits and leaves approximately 407 free. I found no actual image-size or RAM-capacity blocker. The defects are the “no RAM staging” claim and using the smaller payload-only budget as proof. Low-memory behavior matters particularly because of finding 7.

    **Required resolution:** correct the audit, use the real peak-memory/volume accounting, and verify sufficient free resources immediately before any future upgrade. The snapshot is prior evidence, not a measurement I made on the router.

**Lower-severity compatibility and integration findings**

12. **Low, conditional — multilink PPP support is removed.** Exact embedded stock configuration enables `CONFIG_PPP_MULTILINK`; v12e disables it. The conditional implementations in `kernel/linux-4.19/drivers/net/ppp/ppp_generic.c` therefore disappear. A connection requiring multilink PPP loses that support; ordinary single-link PPPoE is not thereby shown broken. Restore the option if required, or explicitly exclude that use case. Other deliberate Merlin feature losses, including the Japanese S46 stack, VPN Fusion, and WebDAV, also need an owner-specific compatibility inventory; retaining their old NVRAM keys does not retain the features.

13. **Low — patch 0002 leaves a callable update hook with no applet.** `M/src/router/rc/rc.c:2380` excludes the `firmware_webs_update` applet for RTAXE7800, but `rc/Makefile:1486–1487` installs its symlink and `rc/services.c:18978–18983,22625–22637` retains the service handler/launcher. The actual image contains `/sbin/firmware_webs_update -> rc`; `rc.c:3908–3909` reports an unknown applet and returns success. Thus a `start_firmware_webs_update` service request cannot perform that update operation and can fail silently to its caller. The watchdog’s automatic caller is feature-guarded; I found no active normal first-boot trigger and do not claim manual firmware upload is broken. Scope out the corresponding install/dispatch paths too, matching the intentionally omitted feature.

**What passed, and exactly what that establishes**

- **Exact artifact and both FIT layers:** `python3 A/inspect_image.py <subject> <stock-pkgtb>` independently parsed bounded FDT structures, extracted payloads, and asserted every image-node SHA-256 in the outer and nested FIT against actual bytes. `A/image-integrity.txt` records offsets, lengths, hashes, and configurations. The outer header is 937 bytes; its selected configuration contains only `description`, `bootfs`, `rootfs`, and `compatible`, with no loader property. Therefore this package does not request a loader-partition replacement.
- **Stock upload's fixed-offset model gate:** checked actual bytes at offsets 82 and 92 against the stock code's checks (`0003`, `RT-AXE7800\0`). The image matches that model gate. This was not an HTTP upload or an execution of the stock private validation routine.
- **Root filesystem:** built a native audit-only unsquashfs from existing Merlin sources into `A`, then extracted the exact rootfs. It produced 2,656 files and 541 symlinks. File bytes, symlink targets, and file/directory modes match the supplied v12e extraction; that extraction has one additional empty `bootfs/` directory. Logs: `rootfs-extract.txt`, `rootfs-comparison.txt`. No regular files with setuid/setgid or world-write mode were found. This is not an exhaustive security review of their contents.
- **U-Boot and DTBs:** U-Boot payload is 2,645,152 bytes; only five bytes differ from the local stock GPL build, all in its banner timestamp at offsets 893581–893587. Board DTB SHA-256 is `b8fba56a66f3526b3452d52bece67747852ba88eb6c67f97d1a123f2edb1c857`; U-Boot DTB is `4a5f70559564fa55bfeb707c9014691eded43d91ed40a546e44bed857fbe07dd`; both match stock. This review did not independently obtain retail bootfs bytes or exercise rescue.
- **Kernel:** decompressed all 45 LZO blocks with size/checksum checks. v12e Image is 11,761,836 bytes, SHA-256 `552226096618e746d32ebd8cfb9314479544398bc5314480a19d19f294a7f3de`. Its embedded configuration equals the supplied `.config`. This is an ARM32/ARMv7 kernel and userspace, despite the prompt's ARM64 description. Do not use AArch64 userspace ABI assumptions for this image.
- **Module closure against actual kernel bytes:** 150 regular ARM32 modules plus three `.ko` symlinks; one vermagic, `4.19.183 SMP preempt mod_unload ARMv7 p2v8`. Checked 7,385 export records, their actual name/value pointers in the exact Image, and 1,797 module exports: zero missing strong imports. Compared stock: 127 module implementations byte-identical, WireGuard changed, 22 added, none missing. `A/kernel-review/check_exact_exports.py` and `exact-export-check.json` retain the check.
- **Depmod calibration:** the unmodified exact-rootfs run emits no unresolved-symbol warnings. Removing both `printk` and `__ksymtab_printk` from a scratch map yields 90 warnings. Removing just `printk` does not test sensitivity, because depmod also reads the export record. Depmod returns zero even with warnings; stderr was checked. Correct calibration is in `A/kernel-review/depmod-sensitivity-stderr.txt`; the parent's earlier zero-warning sensitivity attempt is retained and is not counted as successful calibration.
- **Hardware fixes:** both complete patches 0007/0008 were reviewed. Exact Image contains the added UBI and NAND retry messages. The U-Boot comparison supports its NAND fix matching stock. The TPL BBT change concerns loader-side code; this package does not replace that partition. This is evidence the repairs were incorporated, not a NAND fault test.
- **Radio blob:** extracted `rtecdc.bin` SHA-256 is `d5b3b559fc1b20be2da3b91b67a0e47e302145fe3587e0e418ac355e1e6d045f`, matching the manifested GPL input. The previous wrong-radio-blob defect is not reopened.
- **Supply and toolchain:** independently verified all 1,098 supply-manifest source hashes/sizes/link targets and uniqueness of destinations (`A/manifest-verification.txt`). All 5,923 ARM and 6,128 AArch64 shared regular toolchain files match both am-toolchains and the working completed toolchains. ARM adds the four documented compiler/libgcc files; AArch64 also has Python bytecode cache additions. `A/toolchain-check.txt` records this. This does not prove the remote build used these exact inputs or establish compiler trust cryptographically.
- **Userspace closure:** reran `P/tools/rootfs-abi-closure.py` on the fresh extraction: 619 dynamic ELFs; the same five under-linked-library symbol findings and missing `lld2d -> libbcm_crc.so` already recorded for stock. No new static closure finding. This checker excludes dlopen-only interfaces, strips symbol versions, and is not a substitute for the dynamic loader.
- **Resources:** the proprietary `bcm_bpm.ko` is identical to stock and retains 15/3 percentage defaults in its code, despite config entries of 25/5. Its NVRAM-dependent behavior was not measured. Neither config values nor a daemon's executable size establish peak RAM use.

**Previous-audit claims found wrong or too strong**

| Previous claim | Assessment |
|---|---|
| “Every check that can be made without booting … has passed”; “No open cell remains.” | Wrong as an assurance conclusion: findings 2–10 and 13 are inspectable offline. A finite matrix and four walks do not prove completeness. |
| Formatting happens only for missing volume or `ubifs_format=1`. | Wrong: failed UBIFS mount also enters erase/mkfs. |
| No RAM staging during the manual upload. | Wrong at the flash-library layer: complete segments use `/var` temporary files. |
| Approximately 447 LEBs proves fit inside the 455-LEB inactive slot. | Incomplete accounting: default reservations need 464. Prior free UBI space still makes it fit. |
| NVRAM/JFFS kept, therefore rollback preserves settings. | The flasher's payload write set is narrow, but first-boot migrations change/delete shared settings before fallback ends. |
| “Versioned” migration and no whole-volume format imply safe migration. | No general version transaction or rollback exists here; per-key presence tests can lose data, and write errors are ignored. |
| Compiled functions labeled SAME-CODE establish equivalence. | Too strong: normalization erases behavior-bearing operands and branch destinations. |
| Symbols, versions, structs, and semantics are effectively closed except hardware. | Symbol closure is well supported. Full proprietary struct/semantic agreement is not proven by identical header trees, configs, or names; the actual settings mismatches are counterexamples to semantic agreement. |
| A failed upload leaves the running slot untouched. | Normally true for bootfs/rootfs targeting, but not a complete failure guarantee: shared metadata is updated, service/NVRAM state changes, and writer/metadata errors can be suppressed. |
| Root README says “bootloader untouched.” | Misleading: loader partition is untouched; slot U-Boot proper and ATF are replaced. The later detailed audit correctly corrected this distinction. |
| Rescue code equals retail, so recovery behavior is verified. | Byte comparison supports code provenance only. Button entry, networking, actual stock-image acceptance, write success, and post-rescue settings were not demonstrated on this unit. The earlier checklist itself acknowledges this limitation. |

The earlier fixes for radio firmware, MXIC workarounds, and boot-once interpretation have supporting evidence. I am not treating their historical discovery as a new defect in v12e. The ATF rebuild and retail comparisons remain useful previous evidence, but I did not reproduce them in this review.

**What could not be verified, and why**

- No BCM6756 boot, radio calibration/function, switch/LAN/WAN connectivity, web authentication, USB behavior, hardware acceleration, watchdog behavior, sustained memory use, power-failure handling, or long-run stability was observed. No firmware execution on the router was authorized or performed.
- Rescue has not been demonstrated by this review: no button, TFTP, upload, reset, or stock restoration test. ASUS documents rescue as a distinct recovery mode requiring the reset-button/power sequence and a working wired restoration path; seeing its code or a blinking LED alone does not demonstrate a completed restore. [ASUS Firmware Restoration instructions](https://www.asus.com/us/support/faq/1000814/).
- Current owner settings, JFFS free space/health, mixed DHCP formats, VPN profiles, firewall state, and an independently restorable backup were not inspected. Conditional findings must not be represented as proof the owner currently meets their triggers. Prior resource/layout snapshots were not refreshed.
- Retail bootfs/rootfs/loader copies from the earlier scratch directory are unavailable; that directory is empty now. The prior evidence explicitly records lost intermediates, and parts of `router-commands.txt` are summaries or annotated commands rather than exact replayable shell inputs. I compared against the available local stock build and distinguished inherited retail claims from independent verification.
- I did not perform a fresh complete v12e build, inspect the remote build host, or reproduce the ATF rebuild. Docker socket access is denied in this session. The 32-bit x86 supplied objdump/unsquashfs programs terminate with SIGSYS here; native LLVM, Python ELF tooling, liblzo, and an audit-only native unsquashfs were used instead. QEMU is unavailable on the host, so the earlier 267-program real-loader/smoke results were not rerun. A REA signature-scan tool call was rejected because it requires approval under a never-approve policy; manual format-aware extraction provided the needed image inspection.
- I did not read every source line, recover all proprietary implementation semantics, prove every struct/ioctl ABI, test dlopen/plugin surfaces dynamically, or complete a CVE/attack-surface assessment of every bundled network service. No new generic hardening layer, donor object, private-symbol replacement, or firmware patch was introduced during this audit.

**Conditions for reconsidering NO-GO**

1. Fix or concretely rule out the applicable DHCP, OpenVPN, and SSH triggers. Retain original settings until replacements are successfully written and verified. Demonstrate that the stock configuration can be restored independently of slot selection.
2. Have protected stock settings and JFFS backups, credentials available outside the router, and a verified genuine stock recovery file. Reinstalling a firmware image alone does not reverse the migrations above.
3. Obtain evidence on a recoverable test device for this exact image: first boot with representative stock settings, working wired management, radios/WAN, reboot behavior, a failed-start/fallback case, Merlin-to-stock upload, and actual rescue restoration. A button-entry check is useful but narrower than a completed recovery test. This report does not authorize or perform tests on the owner's router.
4. Resolve or explicitly accept the inherited running-stock flash-error limitations. Candidate-image changes alone cannot repair code already running during the first stock-UI upload. Recheck real RAM/tmpfs/UBI headroom for that upload.
5. Replace the audit's equivalence/completeness claims with bounded checks that fail on deliberate behavioral changes, and bind future reports to the full image hash and retained evidence.

**Verdict:** do not flash v12e through the stock UI on this owner's no-UART router on the strength of the existing audit. The strongest new evidence concerns data preservation and falsely reported success, not a demonstrated inevitable hard brick. A first boot that reaches `rc`'s commit point is insufficient evidence that the router is safe or that stock recovery will preserve the owner's configuration.

Not checked: hardware operation, live owner settings, actual rescue/rollback, or a fresh final-image build.
Risk: this exact image can enter destructive or irreversible settings paths even while its FIT hashes, DTBs, and symbol checks all pass.
