# Porting redwood to XNU 8020 (iOS 15.3)

`patches/hackios-8020.patch` is the redwood work rebased from `xnu-8796.121.2` (iOS 16.5) onto
`xnu-8020.140.41` (iOS 15.3). It applies to a pristine tag with **no fuzz and no rejects**
(`patch -F0`, 77 files, 194 hunks).

The redwood work is two halves, exactly as in `hackios/xnu/apply.sh`:

| | what | where |
|---|---|---|
| changes to Apple's files | 194 hunks in 77 files | `patches/hackios-8020.patch` |
| files Apple's tree does not have | 104 files | `hackios/xnu/files/` (copied by `scripts/fetch-xnu.sh`) |

The patch does **not** carry the 104 new files. `scripts/fetch-xnu.sh` copies them from the
hackios checkout and then checks that the ten that matter are there. Without that step the build
dies at the first `bsd/dev/redwood_*.c` in `bsd/conf/files`.

## What 8020 already does by itself (things 8796 needed the patch for)

8020's `config/MASTER.arm64.bcm2837` is a much more portable configuration than 8796's was:

```
#  ARM_EXTRAS_BASE = [ nos_arm_pmap nos_arm_asm ]
#  KERNEL_BASE =    [ arm64 xsmall msgb_small config_embedded config_requires_u32_munging ARM_EXTRAS_BASE ]
```

* `nos_arm_pmap` and `nos_arm_asm` are **already** in `KERNEL_BASE` — the portable pmap and the
  generic arm64 support are the default for bcm2837. The redwood patch's biggest change
  (`config_pmap_ppl` out of `KERNEL_BASE`) is unnecessary: `config_pmap_ppl` no longer exists in
  8020 at all.
* `osfmk/conf/files.arm64` already splits the pmap the way `nos_arm_pmap` wants
  (`osfmk/arm/pmap.c` plus `osfmk/arm/pmap/pmap_*.c`), so the pmap file move is only a path fix
  in the patch (see below).
* `config/MASTER.arm64.bcm2837` is now a *fragment*: the `# NAME = [ ... ]` block is still parsed
  by `SETUP/config/doconf` (it is how options are selected), and the real `options` lines at the
  bottom are board-specific additions only.

## The ten hunks that did not apply, and what was done with each

| # | file | 8796 → 8020 | action |
|---|---|---|---|
| 1, 2 | `osfmk/arm/pmap/pmap.c`, `pmap.h` | the file moved up a level | **path renamed** in the patch; the hunks then apply clean. Content still matters for cactus: `flush_dcache((vm_offset_t) pp << PAGE_SHIFT, …)` (ppnum is 32-bit, DRAM runs to `0xFFFFF000`), the empty no-PPL `pmap_cs_lockdown_pages`, and the `pmap_page_protect` panic format. |
| 3 | `bsd/kern/kern_exec.c` #7 | `spawn_validate_persona` | **rewritten**. Redwood drops the `persona == NULL → ESRCH` return; 8020's `persona_lookup` has the same contract, so the same intent applies, but redwood's version leaves the `verify` block dereferencing NULL. Here the block became `if (verify && persona != NULL)`; the `out:` label stays (still used). |
| 4 | `bsd/vm/vm_unix.c` | **the code is not in 8020** — `PREBOOT_CRYPTEX_PATH` / cryptex grafting arrived in iOS 16 | **dropped**. There is nothing to relax: 8020's `shared_region_map_and_slide` has no preboot check. |
| 5 | `config/MASTER.arm64.bcm2837` #1 | option-group comment block rewritten upstream | **rewritten**: `FILESYS_BASE` gains `mockfs ramfs apfs`; `pgo` out of `BSD_DEV`/`BSD_DEBUG` (no profile data for a new config); nothing else needed (`nos_arm_pmap nos_arm_asm` already there, `config_pmap_ppl` gone). |
| 6 | `config/MASTER.arm64.bcm2837` #2 | `sched_hygiene_debug` does not exist in 8020, and 8020 added `interrupt_masked_debug sched_preemption_disable_debug` | **dropped** — the hunk has no target. |
| 7 | `makedefs/MakeInc.cmd` | identical text | **applied** by hand: `XCRUN = /usr/bin/xcrun` → `xcrun` (there is no `/usr/bin/xcrun` on Linux; `xnu-deps/host/bin/xcrun` is on `PATH`). |
| 8 | `osfmk/conf/files.arm64` | 8796 had `amcc_rorgn_ppl.c` + `amcc_rorgn_common.c`; 8020 has **no `amcc_rorgn.c` at all** (only the header) | **rewritten** to comment out 8020's `osfmk/arm64/amcc_rorgn.c optional nos_arm_asm`. Left in, `config`/`make` fails on a target that does not exist. Safe to drop: the header only declares `rorgn_stash_range`/`rorgn_lockdown` under `KERNEL_INTEGRITY_KTRR`/`CTRR`, which this config does not define. |
| 9 | `osfmk/kern/kalloc.h` | 8020 writes `__typeof__(*ptr)` (no parens) | **rewritten** around `#if XNU_NO_TYPE_BUILTINS` → `KALLOC_TYPE_IS_COMPATIBLE_PTR(ptr, type) (1)`. `XNU_NO_TYPE_BUILTINS` is what `xnu-deps/hostinc/xnu_clang_compat.h` defines when the compiler has no `__builtin_xnu_types_compatible` (stock clang does not). |
| 10 | `osfmk/kern/percpu.h` | 8020 already computes the iterator with `__next_` and integer casts | **narrowed**: the bounds test became `(vm_address_t)__base <= (vm_address_t)__end` in both `percpu_foreach` and `percpu_foreach_secondary`. As pointers, with one CPU, the two ends belong to no object and the comparison is undefined; the loop must not run. |
| — | `bsd/kern/sys_generic.c` #3, #4 | `dofilewrite` already fixed by the patch; **`write_internal` does not exist in 8020** (added in iOS 16 for `guardid`) | **dropped** #4; #3 was already satisfied. |

## What the compiler said (8020 vs 8796 drift in the copied files)

The 104 files were written against 8796's headers. Everything below was found by building, in the
order it appeared. All of `bsd/dev/redwood_*.c`, `bsd/miscfs/apfs/*`, `bsd/miscfs/ramfs`,
`bsd/pthread/pthread_kext_static.c`, `osfmk/arm64/{generic_arm64_support,loader_return,psci_smp}.c`
and `libkern/amfi/miniamfi.c` now compile.

| file | 8796 → 8020 | fix |
|---|---|---|
| `libkern/amfi/miniamfi.c` | `amfi_t` lost `TrustCache`, `*WithProc`, `write_internal`, gained `CoreEntitlements`; libTrustCache types (`TCReturn_t`, `TrustCacheRuntime_t`) do not exist | **whole file rewritten** in `overrides/` against the 9-member `amfi_t`; `CoreEntitlements` stays zeroed (only the PPL pmap would call it, and this config has no PPL) |
| `osfmk/arm64/machine_routines.c` | `ml_cpu_idle_time()` read `processor_t::pr_recount` / `struct recount_usage` (iOS 16 `recount`) | returns `false` with a comment — no recount in 8020 |
| `osfmk/arm64/user_exception_trace.c` | `#include <kern/recount.h>` + `recount_task_times()` | `task_info(TASK_ABSOLUTETIME_INFO)` instead; in `patches/redwood-8020.patch` because the file is copied *after* the main patch |
| `osfmk/ipc/mach_kernelrpc.c` | `goto done` jumps over `typeof(...) info[max_count]`, a variably modified array — C forbids it | `return rv;` at that one site (`rv` is already `MACH_SEND_INVALID_DEST`); Apple's own file, so it is in the main patch |
| `iokit/Kernel/IOBufferMemoryDescriptor.cpp` | `return NULL;` in a `bool` function; xnu's C++ `stddef.h` defines `NULL` as `nullptr`, which does not convert | `return false;` |
| `libkern/libkern/crypto/Makefile` | 8020's `EXPORT_MI_LIST` does not carry `crypto.h`, so `<libkern/crypto/crypto.h>` is not in `EXPORT_HDRS` and every kernel compile that reaches `rand.h` from there dies | `crypto.h` added to `PRIVATE_DATAFILES` (which feeds both the install and the export list) |
| `osfmk/minicrypto/mc_provider.c` | `crypto_digest_alg_t`, `crypto_random_ctx_t`, `CRYPTO_DIGEST_ALG_*`, `CCKPRNG_ENTROPY_SIZE` do not exist in 8020 — iOS 16 added them to `libkern/crypto/{crypto,rand,register_crypto}.h` and to corecrypto | the three headers are **restored from 8796** in `overrides/libkern/libkern/crypto/`; `CCKPRNG_ENTROPY_SIZE` (64) is defined locally in `mc_provider.c` |

The three restored crypto headers deserve a note of their own, because they also close a trap that
has nothing to do with crypto. In an **osfmk** compile the include path is
`-I. -I osfmk -I EXPORT_HDRS/osfmk … -I EXTERNAL_HEADERS -I osfmk/libsa`, and there is no
`osfmk/machine/types.h`. So a `<machine/types.h>` reached from `bsd/sys/types.h` resolves to
`osfmk/libsa/machine/types.h`, which maps `__arm64__` to the **32-bit** `libsa/arm/types.h`
(`dev_t` = `long`, `daddr_t` = `unsigned int`). Those collide with the `dev_t`/`daddr_t`/`clock_t`
that `osfmk/libsa/string.h` has already defined, and the compile dies on three typedef
redefinitions that point at Apple's own headers. 8796's `rand.h` avoids it by including
`libkern/crypto/crypto.h` (which is `<stddef.h>/<stdint.h>/<sys/cdefs.h>` only) instead of
`<sys/types.h>`, so restoring the iOS 16 headers fixes both problems at once.

Two small helpers in `scripts/` exist to answer this kind of question without a build:

* `inctrace.py <tree> <file.c> <target>` — replays the include graph with the kernel's `-I` order
  and prints the chain that reaches a header. It found the `mc_provider.c` chain above in one
  shot (`mc_provider.c -> libkern/crypto/rand.h -> bsd/sys/types.h`, and separately
  `-> osfmk/libsa/string.h -> osfmk/libsa/types.h`, which is the pair that collides).
* `hdrcheck.py <tree>` — every `#include` in the 104 copied files must resolve somewhere in the
  tree (or by basename); catches headers that 8796 had and 8020 does not.

Rule of thumb: whole-file rewrites go in `overrides/`, small edits to files that `files/` provides
go in `patches/redwood-8020.patch` (applied after the copy), everything else goes in the main
patch, which is regenerated from the working tree with
`git -c core.autocrlf=false diff > patches/hackios-8020.patch`.

## What the linker said (symbols 8020 does not define for a from-scratch arm64 build)

Compilation finishes; the kernel then failed to link with exactly seven undefined symbols. None
of them is redwood's mistake — they are all places where 8020's published source assumes a closed
piece of the platform (the PPL monitor, libcorecrypto) or where iOS 16 moved code into a header.

| symbol | referenced from | why 8020 has no definition | fix |
|---|---|---|---|
| `cc_load32_be`, `cc_load32_le`, `cc_load64_be`, `cc_store32_le`, `cc_store64_be` | `mc_digests.o` | 8796 put these helpers in `EXTERNAL_HEADERS/corecrypto/cc_priv.h` as `CC_INLINE`; 8020's copy has no load/store block at all, so the calls were implicit declarations and nothing was inlined | the block is **restored in `cc_priv.h`** (all sizes, both endiannesses, without 8796's `cc_sized_by` annotations that 8020's `cc_config.h` lacks) |
| `ml_io_map_unmappable` | `redwood_ufs.o`, `redwood_ufshc.o`, `redwood_camera.o`, `redwood_wifi.o`, … | iOS 16 added it to `osfmk/arm64/machine_routines.c` (and a fifth `unmappable` argument to `io_map()`); 8020 has neither | added next to `ml_io_map_wcomb()` as `io_map_with_prot(pa, size, flags, VM_PROT_DEFAULT)` — the block mapping it would skip does not exist here |
| `pmap_cs_allow_invalid`, `pmap_cs_fork_prepare` | `vm_map.o` | `osfmk/arm/pmap/pmap_cs.c` is a 33-line placeholder in the open source drop; the real code is the closed PPL pmap, or 8796's `PMAP_SUPPORT_PROTOTYPES` table in `pmap.c` | `overrides/osfmk/arm/pmap/pmap_cs.c` defines them the way `x86_64/pmap.c` does: unsupported, return `KERN_SUCCESS` |
| `pmap_pending_preemption` | `pmap.o` | only out-of-line when `SCHED_PREEMPTION_DISABLE_DEBUG && (DEBUG \|\| DEVELOPMENT)` — which `PERF_DBG_DEV` sets — and the body lives in the PPL | same override file: returns `_pmap_pending_preemption_real()` |
| `recount_current_thread_time_mach` | `thread.o` | the redwood-added `thread_runnable_and_run_self()` (for apfs lock statistics) called iOS 16's recount | `timer_grab(&thread->user_timer) + timer_grab(&thread->system_timer)`, the same sum `sched_prim.c` uses |

## Build plumbing that had to change (not part of the patch)

* `makedefs/MakeInc.kernel`: the `.dSYM` rule ran `$(DSYMUTIL) --minimize …`, and `DSYMUTIL` comes
  from `$(XCRUN) -sdk $(SDKROOT) -find dsymutil` (`MakeInc.cmd:220`). The `xcrun` shim in
  `xnu-deps/host/bin` does not answer `-find`, so it expanded to nothing and bash reported
  `--minimize: command not found`. There is no dsymutil on this toolchain at all, and the
  unstripped kernel has the same symbols, so the bundle is now assembled by hand
  (`mkdir` + `cp` + `touch`) instead of generated. This is the last thing that failed before the
  kernel existed.

* `scripts/fetch-xnu.sh` copies `hackios/xnu/files/.` after applying the patch and then verifies
  the tree is complete.
* `scripts/setup-theos.sh` / `build.sh` / `deps.sh` / workflow: the SDK is **iPhoneOS16.5**,
  because `hackios/xnu-deps/setup.sh` hardcodes `$THEOS/sdks/iPhoneOS16.5.sdk` and
  `xnu-env.sh` hardcodes `XNU_SDK_PATH=$XNUDEPS/sdk/iPhoneOS16.5.xnu.sdk` (and overrides ours).
  The target triple (`-target arm64-apple-ios16.5`) does not matter to 8020's own sources: they
  only ever test `__IPHONE_OS_VERSION_MIN_REQUIRED` against iOS 5/6/7/10.
* `XNU_NO_TYPE_BUILTINS` is never defined in-tree; it comes from the force-included
  `xnu_clang_compat.h` that `xnu-deps/host/bin/xnu-clang` passes with `-include`.

## Not yet done

Every directory that produces objects has now been through the compiler (`config`, `san`, `libsa`,
`osfmk`, `bsd`, `iokit`, `libkern`, `pexpert`, `security`), and `LDFILELIST bsd` runs. What is
left is the link: `build_all_bootstrap_DEVELOPMENT` is the target that has been failing, so the
next round of errors should be `undefined symbol` at `mach_kernelrpc`/kernel link time, not
compile errors.

Open items after the kernel links:

1. `-lpthread_kext` is libpthread **514** (iOS 16.5) from `xnu-deps`; 8020's own is 454. It is
   compiled against 8020's exported headers, so this may just work — if it does not, pin
   `xnu-deps/setup.sh` to the libpthread release that shipped with 8020.
2. UEFI side: MSDC/eMMC (see `D:/redmi6A-uefi/HANDOFF.md`) — still the only way past the 64 MB
   boot partition.
3. SMP: bounded inside `arm_init_cpu`; 8020 has `osfmk/arm64/psci_smp.c` in `files/`, so PSCI may
   replace the MTK spin-table path entirely.
