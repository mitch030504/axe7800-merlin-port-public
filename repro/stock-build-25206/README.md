# Stock build — ASUS GPL 3.0.0.4.388.25206-gcaa73b5, unmodified

The ASUS package, built as shipped (no source changes) for `rt-axe7800`, in the container from
[`tools/build-env`](../../tools/build-env/Dockerfile). **Nothing built here is flashed.**

    docker build --build-arg STOCK_AUTOCONF=1 -t axe7800-build-stock tools/build-env
    docker run --rm -v <stock>:/work -v <toolchains>:/opt/toolchains axe7800-build-stock \
        bash -c 'cd /work/asuswrt/release/src-rt-5.04axhnd.675x && make rt-axe7800'

## Result: complete image, and byte-identical to retail where it can be checked

`exit=0`, final pass 22m40s. Outputs in `src-rt-5.04axhnd.675x/targets/96756GW/`:

| file | sha256 |
|---|---|
| `RT-AXE7800_3.0.0.4_388_25206-gcaa73b5_nand_squashfs.pkgtb` (55,449,252 B) | `cf982e48f62968d7d039d088b9908b5df14cd4ff403044c9e9d0f17493eecc86` |
| `RT-AXE7800_3.0.0.4_388_25206-gcaa73b5_nand_squashfs_loader.pkgtb` | `9f9bf44af3984d140568ae3487738db4fd4f611bcc4f2042cb3e1e454992392a` |
| `rootfs.img` (2,572 files) | `c91f4318fec64625c2db1db5030eb1be10c8db2b7ee606de8b868da94d978943` |
| `vmlinux` | `4b0ae79bf3d686cac811f3bd61cd7ff4be63e9afd46c6f22d2d6d4889c95243d` |

Build timestamps are embedded, so the image hash itself is not expected to be reproducible.
The per-binary comparison below is the meaningful one.

### Comparison with the shipping 388_25206 firmware

The intake documents recorded the sha256 of four binaries from the verified stock firmware
(`repro/intake/ACCEPTANCE-MATRIX.md`, `libwebapi-shipping-contract.txt`). This GPL build
reproduces all four **byte for byte**:

| rootfs path | GPL build | retail 388_25206 |
|---|---|---|
| `/lib/libnvram.so` (31,740 B) | `3c1c4e83032a79fc…` | `3c1c4e83…` |
| `/usr/lib/libwebapi.so` (91 exports) | `2a236d64f8971a73…` | `2a236d64…` |
| `/usr/sbin/httpd` | `766beb1619352889…` | `766beb16…` |
| `/sbin/rc` | `d4135c8614e18f4b…` | `d4135c86…` |

This is direct evidence that the package is the corresponding source for the retail
firmware's `rc`, `httpd`, `libwebapi` and `libnvram`, not just a nearby generation. The
open `libshared.so` also defines `invalid_nvram_get_program` and `invalid_program_check`, which
the prebuilt `libnvram.so` imports.

## What it took (build host only — the package itself was not changed)

| attempt | stop | fix (host side) |
|---|---|---|
| 1 | `roldconf`: `sudo: No such file or directory` | passwordless `sudo` in the container (the ASUS Makefile runs `sudo mkdir /projects/bca/...`) |
| 2 | `ln: ... /opt/toolchains/...: Read-only file system` | `/opt/toolchains` must be writable (the Makefile adds symlinks there) |
| 3 | `prebuild_checks`: `xxd is required` | add `xxd`, `openssl` CLI, python3 yaml/crypto/elftools |
| 4 | kernel `olddefconfig`: `cannot execute 'cc1'` | **the package's toolchain lacks the compiler proper.** The RMerlin `am-toolchains` copy of the same `crosstools-arm-gcc-9.2-linux-4.19-glibc-2.30-binutils-2.32` is byte-identical on all 5,923 shared files and adds exactly `cc1`, `cc1plus`, `lto1`, `libgcc.a` (aarch64: 6,128/6,128 identical) |
| 5 | `cc1: libisl.so.15: cannot open shared object` | `LD_LIBRARY_PATH` to the toolchain's own `usr/lib` (cc1 RPATH points at the vendor's build path) |
| 6 | `iperf3/configure`: `ac_fn_c_try_cpp: command not found` (after 2h20m) | `iperf3/bootstrap.sh` regenerates `configure`; autoconf 2.71 breaks its `AC_EGREP_CPP` checks. Stock image uses Ubuntu's `autoconf2.69` (`STOCK_AUTOCONF=1`). Merlin has its own source fix (`011d359e77`) |
| 7 | — | **complete** |

The missing `cc1`/`cc1plus`/`lto1`/`libgcc.a` mean the package does not build with only what
it ships. It is recorded here as a fact about the package; the files used to complete the
toolchain are the matching upstream Broadcom toolchain, verified by overlap.
