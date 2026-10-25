# Porting redwood to XNU 8020 (iOS 15.3)

`patches/hackios-8020.patch` is the redwood work rebased from `xnu-8796.121.2` (iOS 16.5) onto
`xnu-8020.140.41` (iOS 15.3). It applies to a pristine tag with **no fuzz and no rejects**
(`patch -F0`, 72 files, 185 hunks).

The redwood work is two halves, exactly as in `hackios/xnu/apply.sh`:

| | what | where |
|---|---|---|
| changes to Apple's files | 185 hunks in 72 files | `patches/hackios-8020.patch` |
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

## Build plumbing that had to change (not part of the patch)

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

The patch now applies; the compiler has not spoken. The 104 new files were written against
8796's headers, so the first build is expected to fail on API drift — `kalloc_type`/`zalloc`
flags, `vnode`/`VFS` KPI, IOKit (`IOPlatformExpert`, `IOMobileFramebuffer`), `pthread_kext`.
Iterate with `build=true`; `build.log` and `deps.log` come back as the `build-log` artifact and
the first errors are in the run summary.

Open items after the kernel links:

1. `-lpthread_kext` is libpthread **514** (iOS 16.5) from `xnu-deps`; 8020's own is 454. It is
   compiled against 8020's exported headers, so this may just work — if it does not, pin
   `xnu-deps/setup.sh` to the libpthread release that shipped with 8020.
2. UEFI side: MSDC/eMMC (see `D:/redmi6A-uefi/HANDOFF.md`) — still the only way past the 64 MB
   boot partition.
3. SMP: bounded inside `arm_init_cpu`; 8020 has `osfmk/arm64/psci_smp.c` in `files/`, so PSCI may
   replace the MTK spin-table path entirely.
