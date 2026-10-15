# RT-AXE7800 / BCM6756 Asuswrt-Merlin porting research

> ## ⚠️ NOT FLASH-READY — DO NOT FLASH ANYTHING BUILT FROM THIS RESEARCH
>
> This is **experimental RT-AXE7800 / BCM6756 porting research**.
> - **No image produced by this work is flash-ready.** Do **not** flash generated images.
> - **No ASUS firmware binaries are redistributed here.** No stock/extracted firmware, no
>   `.o` / `.ko` / `.so` / ELF objects, no dongle firmware, no donor binaries, no images.
> - **Runtime ABI compatibility and flash safety are NOT established.**
> - This repository documents **research and reproducibility. It is not a firmware release.**
> - No router flash, NVRAM, MTD, bootloader or partition operation is part of this workflow.

**Public v4 — matching ASUS GPL 388.25206 received; stock and Merlin RT-AXE7800 images build. Still not flash-ready.**

A reproducibility lab for porting Asuswrt-Merlin to the **ASUS RT-AXE7800**
(Broadcom **BCM6756**, profile **96756GW**, 32-bit ARM).

Merlin baseline: **`asuswrt-merlin.ng`, branch `3006.102-wifi6`, commit
`ccd139a31d94de15d2da744083dbafbcfe97dcdf`**. That pinned lineage is *our* reproducibility
baseline; it is **not** claimed to be the source tree ASUS used for any retail firmware.

## Public v4 — GPL 388.25206 (current)

ASUS supplied `GPL_RT-AXE7800_3.0.0.4.388.25206-gcaa73b5.tgz` through its open-source request
channel. Its tree identifies itself as `EXTENDNO=25206-gcaa73b5`, the shipping firmware.

| | status | where |
|---|---|---|
| package intake | identity established; all three generation gaps **PASS** via authentic same-model prebuilts (`spwenc.o` → `invalid_*`, `priv_webapi.o` → 34/34 libwebapi contract, `s46comm.o`) | [`repro/intake/INTAKE-388_25206.md`](repro/intake/INTAKE-388_25206.md) |
| stock build | unmodified package builds a complete image; `rc`, `httpd`, `libwebapi.so`, `libnvram.so` are **byte-identical to retail 388_25206** | [`repro/stock-build-25206`](repro/stock-build-25206/README.md) |
| Merlin baseline | measured: `3004.388` matches the 25206 ABI (2 vs 15 type mismatches) | [`repro/baseline-analysis`](repro/baseline-analysis/BASELINE-DECISION.md) |
| Merlin port | **complete image** `RT-AXE7800_3004_388.13_alpha1_nand_squashfs.pkgtb`, independent builds on two hosts agree, runtime ABI closure identical to stock | [`repro/clean-replay-v12`](repro/clean-replay-v12/README.md) |

The port uses only same-model ASUS inputs: 1,098 GPL files staged by a committed sha256
manifest, plus eight small patches. Each patch either removes a call that ASUS's own 25206 source
does not make (functions Merlin picked up from later GPLs), aligns a Merlin header with the
supplied objects' ABI, fixes a Merlin build bug, or brings in ASUS 25206 hardware fixes that
Merlin's platform sources lack (MXIC NAND workarounds in U-Boot, UBI and the flash driver). No
stubs, no donor binaries.

A [pre-flash audit](repro/preflash-audit/README.md) checked the image against stock offline: bootloader untouched, accepted by the stock upload check, same DTB, modules and blobs, and the radio firmware corrected to the stock-build copy. It also lists what must be checked on the device first. Its [coverage matrix](repro/preflash-audit/COVERAGE.md) crosses every stage of the flash and boot with every property class. Each cell is marked verified, not verifiable offline (with the reason), or not applicable.

**Not established:** behaviour on hardware. Nothing has been flashed, and nothing here says it
is safe to flash. The warning above still applies in full.

Build environment: [`tools/build-env/Dockerfile`](tools/build-env/Dockerfile). The package's ARM
toolchain lacks `cc1`/`cc1plus`/`lto1`/`libgcc.a`; RMerlin's `am-toolchains` copy is
byte-identical on every shared file and supplies them (see the stock-build notes).

---

The sections below describe the **v3 state before the package arrived**. They are superseded
and kept for the record.

## Current state model

```
Published ASUS GPL 388.34458
    -> standalone buildable and internally coherent
    -> an older / different userspace generation than the shipping firmware

Pinned Merlin + RT-AXE7800 integration
    -> deterministic clean replay established (repro/clean-replay-v11)
    -> first clean blocker:
           invalid_nvram_get_program
           invalid_program_check
       at the write_smb_conf / libdisk link boundary
    -> downstream known gaps (NOT the current first blocker):
           libwebapi private contract
           s46comm-generation S46
    -> waiting for a matching current-generation ASUS source package
```

## Where the port actually stands

| | status |
|---|---|
| Standalone GPL 388.34458 build | **established** — builds from ASUS's own published package |
| Merlin-port clean replay | **established** — one script, zero manual steps, from the pinned commit |
| Current clean first blocker | `invalid_nvram_get_program`, `invalid_program_check` |
| Downstream known gaps | `libwebapi` private contract · `s46comm`-generation S46 |
| Merlin-side cross-product adaptations | resolved (see below) |
| Technical work | **intentionally frozen** pending authentic current-generation source/supply |

### The clean replay

[`repro/clean-replay-v11`](repro/clean-replay-v11/README.md) reconstructs the whole legitimate
integration state from the pinned commit in a single pass, with no manual mutable-worktree
state: model/config integration, authentic same-model GPL 388.34458 supply staged **only**
after per-file SHA-256 verification against a committed manifest, the accepted source
adaptations, and assertions that abort on any synthetic artifact reaching a supply directory.

Determinism was demonstrated across two independent fresh lineages: identical adapted-source
hashes, and the same first blocker both times.

**No synthetic, stub, or donor object is part of the clean port.** The replay refuses to
proceed if one is present.

### Current first blocker

    make[5]: *** [Makefile:77: write_smb_conf] Error 1     (libdisk)

    undefined reference to `invalid_nvram_get_program'
    undefined reference to `invalid_program_check'

Two symbols, at the `write_smb_conf` link. They have no open-source caller, are required by a
prebuilt `libnvram`, and the shipping firmware exercises the corresponding behaviour. Their
names indicate validation semantics, so **they are deliberately not stubbed, guessed, or
bypassed** — a permissive replacement could silently weaken input validation.

`libwebapi`/`priv_webapi` and `rc`/`s46comm` are demonstrated **downstream** gaps behind this
boundary. Earlier public snapshots described `priv_webapi.o` as the current Merlin-side
blocker; that is **superseded** — it was only reachable in earlier runs that had crossed the
`invalid_*` boundary using diagnostic objects, which are excluded from the clean port.

## Generation, not omission

An audit of published GPL 388.34458 versus the shipping 388_25206 firmware found the
difference between them is **narrow and localized**, not systemic. Across roughly twenty
shared libraries present in both, exported-ABI deltas are single-digit symbol counts, and
several are ABI-identical. Three areas account for essentially all of the divergence:

| area | published 388.34458 | shipping 388_25206 |
|---|---|---|
| `shared` provider surface | older surface | 44 exports our build does not have |
| `libwebapi` | component not present in the package | ships and is actively used |
| `rc` / S46 | `s46map_rptd` generation | `s46comm` generation |

Notably, `libnvram` itself is **ABI-identical** between the two — the current blocker is about
which component *provides* those two symbols, not about `nvram` differing.

Pinned Merlin generally tracks the **shipping** 388_25206 generation rather than the published
388.34458 one.

> **GPL 388.34458 is not described here as incomplete.** It is internally coherent and
> standalone-buildable for its own generation. It simply is not the same generation as the
> currently shipping firmware. Nothing in this repository asserts that ASUS withheld anything.

## The external dependency

The key remaining input is a source/GPL package matching RT-AXE7800 firmware
`3.0.0.4.388_25206`, or the current `388_25xxx` generation.

**No matching public package has been located.** ASUS's published RT-AXE7800 GPL package is
388.34458; searches of the support pages and the CDN naming convention did not locate a
package for the `388_25xxx` line. This is reported as *not located* — it is **not** a claim
that such a package does or does not exist.

A request for the complete matching source package has been submitted through ASUS's normal
open-source channel. Correspondence itself is not published here.

## If a package arrives

[`repro/intake`](repro/intake/ACCEPTANCE-MATRIX.md) contains the read-only plan for evaluating
one objectively:

- [`ACCEPTANCE-MATRIX.md`](repro/intake/ACCEPTANCE-MATRIX.md) — per-gap PASS / FAIL /
  INCONCLUSIVE criteria. File absence alone is never FAIL.
- [`PACKAGE-PROVENANCE-CHECKLIST.md`](repro/intake/PACKAGE-PROVENANCE-CHECKLIST.md) —
  identity and provenance fields. Filenames and version numbers are treated as unreliable:
  388.34458 carries a *higher* build number than 388_25206 while being older and a different
  generation.
- [`GENERATION-DELTA-AUDIT.md`](repro/intake/GENERATION-DELTA-AUDIT.md) — the measured
  three-way comparison.
- [`CROSS-PRODUCT-DEPENDENCY-MAP.md`](repro/intake/CROSS-PRODUCT-DEPENDENCY-MAP.md) — which
  dependencies a matching package would *not* fix, because Merlin inherited them from other
  ASUS product lines.
- [`PRE-ASUS-CLOSURE.md`](repro/intake/PRE-ASUS-CLOSURE.md) — final classifications.
- [`tools/inspect-gpl-generation-gaps.sh`](tools/inspect-gpl-generation-gaps.sh) — read-only
  generation-gap inspector. Complements
  [`tools/verify-asus-gpl-drop.sh`](tools/verify-asus-gpl-drop.sh), which covers package
  identity. Neither writes to, extracts into, or modifies a supplied package.

## Merlin-side adaptations (independent of ASUS)

Two dependencies that pinned Merlin inherited from *other* ASUS product lines were resolved
with model-correct source guards — **not** stubs:

| symbol | inherited from | resolution |
|---|---|---|
| `get_fh_if_prefix_by_unit` | RT-BE86U lineage | guarded on `RTCONFIG_MULTILAN_CFG`, which this model does not set |
| `hnd_boardid_cmp` | RT-BE96U lineage | its branch scoped to the model it is written for; the branch was link-live but runtime-dead here |

Both patches are published in
[`repro/clean-replay-v11/patches`](repro/clean-replay-v11/patches). No currently demonstrated
blocker is of a kind that a matching ASUS package could not address.

## Why the freeze

Every remaining unknown — whether a matching package supplies the two `invalid_*` symbols,
ships `libwebapi`, or is the `s46comm` generation — is decidable only by examining such a
package. The intake tooling to decide it already exists. Continuing to build or adapt would
mean guessing at private validation semantics, which this project does not do.

## Layout

    repro/clean-replay-v12/   CURRENT: Merlin 3004.388 + GPL 25206 replay, manifest, patches, evidence
    repro/stock-build-25206/  unmodified ASUS package build and retail comparison
    repro/baseline-analysis/  measured Merlin baseline choice
    repro/clean-replay-v11/   v3 replay on 3006.102 + GPL 388.34458 (superseded)
    tools/build-env/          build container
    repro/clean-replay-v2/    earlier milestone (historical)
    repro/intake/             acceptance matrix, provenance checklist, audits
    tools/                    read-only package verification and inspection
    research/public-oracle/   public-source lineage analysis
    prep/, docs/              earlier notes; see each file's header for status

## Scope and conduct

- Stock firmware is used **only** as a read-only ABI/runtime oracle, by observation of
  exported and imported symbol names. No proprietary implementation is reverse engineered,
  reconstructed, or republished.
- Embedded credential and API-key symbols are recorded by existence and size only. Their
  values are never read or published.
- No donor binaries from other models are used as build inputs. Other models' objects appear
  only as read-only symbol oracles in analysis.
- No feature is disabled merely to make a build progress.
