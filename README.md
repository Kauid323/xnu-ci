# xnu-ci — 在 GitHub Actions 上编 XNU（本地只用 Windows）

本地不装 Linux：这个仓库只放"怎么编"，内核在 ubuntu runner 上编，产物当 artifact 下载。

目标：**iOS 15.3 / `xnu-8020.140.41`**，iPhone10,3 身份，hackios 的平台层（不是 edk2）。

## 两个 job

- **rebase**（push 就自动跑，约 2 分钟）：拉目标 XNU、打 `patches/hackios-8020.patch`，
  把打不上的 hunk 列进 job summary，`.rej` 当 artifact 带回来。**不需要工具链**。
- **build**（手动触发，`build=true`）：装 theos（Linux cctools + `iPhoneOS16.5.sdk`）、
  跑 hackios 的 `xnu-deps/setup.sh`、`xnu-build.sh`，`out/` 里的 `mach.*` 当 artifact；
  `build.log` / `deps.log` 无论如何都会带回来，job summary 里先列前 120 条错误。

## 现状（2026-10-25 下午）

**内核编出来了。** CI run 40180421049 全绿，artifact `mach-kernel`：

| 文件 | 大小 | 说明 |
|---|---|---|
| `mach.development.bcm2837` | 14,967,816 B | 剥过符号，给 `mkxnuimg.py` 用 |
| `mach.development.bcm2837.unstripped` | 18,651,360 B | 带符号，调 panic/栈回溯用 |

`feedfacf` / arm64 / `MH_EXECUTE` / 25 条 load command。`build.log` 里能看到
`LD mach.development.bcm2837.unstripped` → `DSYMUTIL` → `LIBTOOL` → `STRIP` →
`built kernel at .../mach.development.bcm2837`。

从"能编译"到"能链接"补了 7 个未定义符号（`cc_load32_be` 一族、`ml_io_map_unmappable`、
两个 `pmap_cs_*`、`pmap_pending_preemption`、`recount_current_thread_time_mach`），
每一个的原因和做法都记在 [`PORTING.md`](PORTING.md) 的两张"编译器说 / 链接器说"表里。

下一步不在这个仓库里：把内核打成 boot.img 刷上 cactus（见 `D:/redmi6A-uefi/HANDOFF.md`）。

`patches/hackios-8020.patch` 已经把 hackios 给 `xnu-8796.121.2`（iOS 16.5）的 185 个 hunk
移植到 `xnu-8020.140.41`，**在纯净 tag 上 `patch -F0` 零 fuzz、零 `.rej` 通过**（77 个文件、
194 hunk）。移植记录逐 hunk 写在 [`PORTING.md`](PORTING.md)。

redwood 的工作是两半，缺一半就编不过：

| | 内容 | 位置 |
|---|---|---|
| 改 Apple 的文件 | 194 hunk / 77 文件 | `patches/hackios-8020.patch` |
| Apple 树里没有的新文件 | 104 个 | `hackios/xnu/files/`，由 `scripts/fetch-xnu.sh` 拷进去 |

补丁**不带**那 104 个新文件（`bsd/dev/redwood_*.c`、`bsd/miscfs/apfs/*`、
`iokit/Kernel/Mini*.cpp`、`osfmk/arm64/psci_smp.c` …）。`fetch-xnu.sh` 拷完会检查十个关键
文件在不在，缺了就直接失败，而不是等编译器在 `bsd/conf/files` 上炸。

一个好消息：8020 的 bcm2837 配置本身已经是"可移植"的那一套——
`ARM_EXTRAS_BASE = [ nos_arm_pmap nos_arm_asm ]` 默认就在 `KERNEL_BASE` 里，
`config_pmap_ppl` 在 8020 里根本不存在。8796 时代最大的一块改动因此不需要了。

## 用法

```bash
cd D:/redmi6A-uefi/xnu-ci
git add -A && git commit -m "8020: rebased patch + files/ + build log"
git push
```

推上去后：Actions → `xnu` → Run workflow → 勾 `build=true`。
第一次大概率在编译期失败（104 个新文件是按 8796 的头文件写的），拿 `build-log` artifact
里的 `build.log` 逐条改。

## 已知风险

- `setup-theos.sh` 里 toolchain 的下载地址是"猜"的（theos 的 Linux 工具链发布资产名可能不同）；
  脚本先试官方 installer，失败再试 clone + release，最后会 `ls` 出来让人看。
- `xnu-deps/setup.sh` 会拉 Apple 的几个开源包和 `MacOSX13.3.sdk`（几百 MB），第一次跑慢。
- SDK 锁在 **16.5**：`xnu-deps/setup.sh` 和 `xnu-env.sh` 都硬编码 16.5，且后者会覆盖我们
  传的 `XNU_SDK_PATH`。对 8020 的源码没有影响（它只用 `__IPHONE_OS_VERSION_MIN_REQUIRED`
  跟 iOS 5/6/7/10 比）。
- `-lpthread_kext` 来自 libpthread **514**（iOS 16.5），8020 自带的是 454。它是拿 8020 自己
  导出的头文件编的，可能没事；真链不上就把 `xnu-deps/setup.sh` 钉到 454。
- 编出来的内核是 **iOS 15.3 的 XNU + hackios 平台层**，`mach.development.bcm2837`；
  能不能直接喂给现在的 loader 要等 artifact 下来再验（版本/ABI 变了，`loader_return.c`、
  `psci_smp.c` 这些符号偏移可能变，探针偏移要重算）。
