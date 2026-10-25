# xnu-ci — 在 GitHub Actions 上编 XNU（本地只用 Windows）

本地不装 Linux：这个仓库只放"怎么编"，内核在 ubuntu runner 上编，产物当 artifact 下载。

目标：**iOS 15.3 / `xnu-8020.140.41`**，iPhone10,3 身份，hackios 的平台层（不是 edk2）。

## 两个 job

- **rebase**（push 就自动跑，约 2 分钟）：拉目标 XNU、用 `patch -F3` 打 hackios 的补丁，
  把还打不上的 hunk 列进 job summary，`.rej` 当 artifact 带回来。**不需要工具链**。
- **build**（手动触发，`build=true`）：装 theos（Linux cctools + `iPhoneOS15.6.sdk`）、
  跑 hackios 的 `xnu-deps/setup.sh`、`xnu-build.sh`，`out/` 里的 `mach.*` 当 artifact。

## 本地测过的现状（2026-10-25，Windows + MSYS2 git/patch）

`patches/hackios-8796.patch` 是 hackios 给 `xnu-8796.121.2`（iOS 16.5）写的 73 个文件的补丁。
对 `xnu-8020.140.41`：

| 打补丁的方式 | 失败 hunk |
|---|---|
| `git apply`（零 fuzz） | 34 个 hunk，22 个文件 |
| `patch -p1 -F3`（3 行 fuzz） | **9 个 hunk** |

所以剩下要手工移植的是这 9 个 hunk（`patch -F3` 之后还会留 `.rej`），文件名是按补丁里的
`@@ -行号` 对出来的：

| 文件 | hunk | 作用（都是挂平台层用的钩子） |
|---|---|---|
| `bsd/kern/kern_exec.c` | #7 @3171 | exec 里的钩子（`exectrace` 就加在这附近） |
| `bsd/kern/sys_generic.c` | @631、@678 | read/write 的钩子 |
| `bsd/vm/vm_unix.c` | @2538 | `after_root_check` 附近 |
| `config/MASTER.arm64.bcm2837` | @16、@50 | 机器配置项（8020 的 config 目录结构变了） |
| `makedefs/MakeInc.cmd` | @100 | 编译命令（`VERBOSE` 那一段） |
| `osfmk/conf/files.arm64` | @25 | 新文件登记 |
| `osfmk/kern/kalloc.h` | @821 | `kt_granule_t` 附近 |
| `osfmk/kern/percpu.h` | @236 | `other_percpu_base` 附近 |

逐个对照 8796 的写法移植即可；移植完把结果做成 `patches/hackios-8020.patch`。

## 用法

```bash
cd D:/redmi6A-uefi/xnu-ci
git init -q . && git add -A && git commit -m "xnu ci: rebase report + build"
git remote add origin git@github.com:<你>/xnu-ci.git     # 或 https + token
git push -u origin main
```

推上去后：
1. Actions 里 `xnu` 会跑 **rebase**，看 summary 里的失败列表和 `rebase-report` artifact；
2. 把 9 处移植完（在 `patches/` 里生成一份 `hackios-8020.patch`，脚本默认读 `patches/hackios-8796.patch`，
   改一下 `PATCH` 变量或直接替换文件名）；
3. 手动 Run workflow，勾 `build=true`，拿 `mach-kernel` artifact。

## 已知风险（第一次跑 build 时大概率先撞这些）

- `setup-theos.sh` 里 toolchain 的下载地址是"猜"的（theos 的 Linux 工具链发布资产名可能不同）；
  脚本先试官方 installer，失败再试 clone + release，最后会 `ls` 出来让人看。
- `xnu-deps/setup.sh` 会拉 Apple 的几个开源包和 `MacOSX13.3.sdk`（几百 MB），第一次跑慢。
- `xnu-build.sh` 里 `MACHINE=BCM2837`（hackios 的机器配置）；8020 的 `config/` 里得有这个配置，
  这也是上面 `config/MASTER.arm64.bcm2837` 那两处 hunk 要移植的原因。
- 编出来的内核是 **iOS 15.3 的 XNU + hackios 平台层**，`mach.development.bcm2837`；
  它能不能直接喂给现在的 loader，要等第一次 artifact 下来再验（版本/ABI 变了，`loader_return.c`、
  `psci_smp.c` 这些符号偏移可能变，探针偏移要重算）。
