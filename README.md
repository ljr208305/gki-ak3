# F:\GKI — 本地 AK3 内核构建台

Windows 上一条命令编出**一加 / OPPO / realme 全机型**可刷的 root 内核（AnyKernel3）。
固定组合：**BakaSU 35257 + SUSFS 2.2.0 + 内核后缀「念想」**。

编译跑在 WSL2（Ubuntu-24.04-SukiSU）里，源码落 WSL 的 ext4（快），产物 AK3 直接丢 `out\`。

---

## 快速开始

1. 双击 **`gki.cmd`**（绕过执行策略，直接开菜单）
2. 菜单按 `1` 选设备（可多选）→ 按 `3` 开始构建
3. 编完去 **`out\`** 拿 `AK3_BakaSU35257_SUSFS2.2.0_NianXiang_<机型>_<内核版本>_<时间>.zip`

命令行同样能跑：

```powershell
.\gki.cmd -Action build -Devices oneplus_ace_6
.\gki.cmd -Action build -Devices oneplus_ace_6,oneplus_13_b -Kpm KPM -Jobs 6
.\gki.cmd -Action build -Devices oneplus_ace_6 -DryRun     # 只走流程不编译
.\gki.cmd -Action list -Brand oneplus -Android 16
.\gki.cmd -Action env                                      # 环境自检
.\gki.cmd -Action products                                 # 看产物
.\gki.cmd -Action refresh                                  # 重拉设备清单
```

---

## 菜单

```
1) 选择设备      一行输入：关键字 / 序号 / 回车看列表
2) 构建参数      后缀 / KPM / 配置档 / 并发 / ccache / 是否留源码
3) 开始构建      回车直接编已选设备，日志同时落 logs\
4) 查看产物      out\ 里的 AK3 列表
5) 环境自检      依赖、磁盘、DNS、内存
6) 刷新设备清单  重拉上游 FILE.md 重新生成 198 台表
7) 查看日志      挑一份看尾部
```

### 选设备怎么最快

进 `1` 之后直接敲，一行解决：

| 输入 | 结果 |
|---|---|
| `ace6` | 模糊搜，3 台（Ace 6 / 6T / 6 Ultra）列出来带序号，再敲个号就选上 |
| `一加 13` | 中文品牌照样认，出 13 / 13r / 13t / 13s 全系 |
| `nord 3` | 空格当「并且」，一步步缩范围 |
| `42` | 直接按序号选（序号跟列表里印的一致，198 台固定不变） |
| `42,45,50-55` | 多选，逗号连字符都行 |
| `oneplus_ace_6` | 完整 id 直接命中 |
| `all` | 当前全部 198 台一次选中 |
| `#` | 调回上次构建那批 |
| `c` | 清空已选 |
| 回车 | 看全部列表，列表里输序号能一边选一边取消 |
| `q` | 选完返回 |

只命中一台时直接选上，不用再敲确认。选完回主菜单按 `3`，回车就开编。

参数子菜单里的项：

| 项 | 默认 | 说明 |
|---|---|---|
| 内核后缀 | `念想` | `uname -r` 会显示 `6.6.xx-android15-念想` |
| KPM 模式 | `N/A` | `KPM` 打 `patch_linux` 进 Image / `KPN` 走 kptools |
| 配置档 | `core` | core 只开 KSU+SUSFS 系列；full 再并入 `patches/features/*.config` |
| 并发 | 自动 | 按 WSL 内存算，每并发约 1.9G |
| ccache | 开 | 二次编译快一半以上 |
| 保留源码 | 关 | 编完删源码省磁盘；连续编同机型就打开 |

---

## 构建引擎（scripts/build_one.sh）

```bash
bash scripts/build_one.sh --file <机型id> [选项]
```

| 选项 | 作用 |
|---|---|
| `--file` | 机型 id，见 `config/devices.json` |
| `--suffix` | 内核后缀，默认 `念想`；`-1` 表示不加 |
| `--kpm` | `N/A` / `KPM` / `KPN` |
| `--profile` | `core` / `full` |
| `--jobs` | 并发数，不给就按内存自动算 |
| `--dry-run` | 只打印每步命令，不真跑 |
| `--save-source` | 编完不删源码 |
| `--no-sync` | 已有源码时跳过 repo sync |
| `--no-ccache` | 关缓存 |

进度速查（另开一个窗口）：

```bash
wsl -d Ubuntu-24.04-SukiSU -u root -- bash /mnt/f/GKI/scripts/status.sh
```

流程与上游 Action-Build 一致，九步：

```
0 预检（工具/ccache/repo/内存并发）
1 探测清单仓库分支（OnePlusOSS → Numbersf → Appendix）
2 repo init + repo sync
3 剥 ABI 保护、check_defconfig
4 识别 KMI（android15-6.6 这种）和内核版本
5 接 BakaSU（固定 commit 516d3e87，版本号由 git 历史算出 35257）
6 打 SUSFS 2.2.0 补丁（本地补丁优先，缺了就回退上游对应分支）
7 写 gki_defconfig（KSU + SUSFS 全开 + KSU_FULL_NAME_FORMAT）
8 注入内核后缀「念想」
9 make 编译 → 找 Image → 包 AnyKernel3 → 落 out\
```

---

## 固定组合怎么保证

| 件 | 值 | 落点 |
|---|---|---|
| BakaSU | commit `516d3e87fbc986ccefdde2c2765f1700612441a9` | `$HOME/gki-build/bakasu`，`KSU_VERSION = 30000 + rev-list --count + 700 = 35257` |
| SUSFS | 2.2.0（`50_add_susfs_in_gki-android15-6.6.patch` + `fs/susfs.c` + `include/linux/susfs*.h`） | `patches/susfs-v2.2.0/` |
| 后缀 | `念想` | `setlocalversion` 注入 + `CONFIG_KSU_FULL_NAME_FORMAT="%TAG_NAME%-念想."` |
| 打包 | Numbersf/AnyKernel3 | 每次现克隆，写好 `anykernel.sh` 塞 Image 打 zip |

编完在日志里能核对：

```
BakaSU 提交 516d3e87  版本号 35257  标签 v4.2.0-rc3
内核串: Linux version 6.6.66-android15-8-gxxxxxxxx-念想
关键配置检查: CONFIG_KSU=y CONFIG_KSU_SUSFS=y ...
```

---

## 能编哪些机型

`config/devices.json` 共 **198 台**：一加 105 / OPPO 74 / realme 19，来自上游 `FILE.md`。

机型 id 最后的字母是**你手机当前安卓大版本**，选错开不了机：

| 后缀 | 安卓 |
|---|---|
| `_s` | 12 |
| `_t` | 13 |
| `_u` | 14 |
| `_v` | 15 |
| `_b` | 16 |
| 无后缀 | 出厂版本（如 `oneplus_ace_6` = Ace6 出厂 Android 16） |

举例：Ace6 跑 ColorOS 16 就是 `oneplus_ace_6`；一加 13 跑 Android 15 是 `oneplus_13`，升到 16 换 `oneplus_13_b`。

### SUSFS 2.2.0 的覆盖边界

本地 `patches/susfs-v2.2.0` 只有 **android15-6.6** 这一份补丁，正好是你那台 Ace6 三代内核（6.6.66 / 6.6.89 / 6.6.118）用的。

选 6.6 系机型 → 精确 2.2.0。
选 5.10 / 5.15 / 6.1 / 6.12 机型 → 自动回退 `susfs4ksu` 的 `gki-<KMI>` 分支，版本随上游，日志会打出实际版本号。

要让某个 KMI 也吃 2.2.0，把那套文件丢进去：

```
patches/susfs-v2.2.0/kernel_patches/
├── 50_add_susfs_in_gki-<KMI>.patch      # KMI 例如 android16-6.12
├── fs/susfs.c
└── include/linux/susfs.h susfs_def.h
```

引擎按 `50_add_susfs_in_gki-<KMI>.patch` 是否存在来选本地/上游。

---

## 刷入

1. 产物是 AnyKernel3，`recovery` 或管理器里刷：
   - BakaSU / SukiSU 管理器 → 安装 → 选本地 zip
   - 或 Horizon Kernel Flasher / TWRP `adb sideload`
2. 刷前把原 boot 备份一份
3. 开机进系统装 **BakaSU 管理器 APK**，打开确认版本 `35257`
4. 验三项：
   ```bash
   uname -r                       # 结尾带 -念想
   cat /proc/version
   zcat /proc/config.gz | grep SUSFS   # 没有 config.gz 就看管理器里的状态
   ```

---

## 环境

已就绪：

- WSL `Ubuntu-24.04-SukiSU`（Ubuntu 24.04.5，12 核，7.7G 内存）
- 源码区 `~/gki-build/src/<机型>`（ext4，快）
- 产物直接写 `/mnt/f/GKI/out`
- DNS 已修（`scripts/wsl_fixnet.sh`：systemd-resolved 上游写 223.5.5.5 / 119.29.29.29）

16G 物理内存的机器编 6.6 内核会吃紧，把 WSL 内存抬上来：

```ini
# C:\Users\念想\.wslconfig
[wsl2]
memory=10GB
swap=16GB
processors=12
```

改完 `wsl --shutdown` 再生效。

---

## 常见问题

**DNS 挂了 / 拉不到清单** → `bash scripts/wsl_fixnet.sh`（Windows 侧也能 `.\\gki.cmd -Action env` 看网络那一段）

**`storage.googleapis.com` 不通** → 不影响，repo 工具改从 GitHub 取；再不行 `sudo apt-get install -y repo`

**编译中途 `Killed`** → 内存爆了，降并发：`--jobs 4`，或按上面抬 WSL 内存

**`repo sync` 卡住** → 中断重跑，或 `repo sync -j4 --retry-fetcher`；清单探测那步超过 15 分钟也重跑一次

**产物 Image 找到但没有 AK3** → 看 `logs\` 里对应日志尾部，多半是 zip 那步路径问题

**换机型要重下几十 G** → 正常，每个机型独立源码目录。留着源码 + ccache，二次编同机型只要十几分钟

**编译要多久** → 16G 内存机器：6.6 内核首发约 2.5~4 小时，带 ccache 二次 40~90 分钟。机器越强越快，纯看 CPU

---

## 目录

```
F:\GKI\
├── gki.cmd                 Windows 启动器（双击开菜单）
├── gki.ps1                 主工具（菜单 + 命令行）
├── config\
│   ├── devices.json        198 台设备表
│   ├── FILE.md             上游原始清单
│   └── tool-state.json     工具记住的选择和参数
├── scripts\
│   ├── build_one.sh        单设备构建引擎
│   ├── env_check.sh        环境自检/装依赖
│   ├── status.sh           构建进度速查
│   └── wsl_fixnet.sh       WSL DNS 修复
├── patches\
│   ├── susfs-v2.2.0\       本地 SUSFS 2.2.0 补丁
│   ├── features\           从你旧包提的 features.config（6.6.66/89/118）
│   ├── bakasu-35257\       BakaSU 驱动源码选摘（版本核对用）
│   └── integration-reference\  Ace6 兼容补丁参考
├── out\                    产物 AK3
├── logs\                   构建日志
├── work\                   预留
└── _ref\                   你给的补丁源码包原始内容（核对用，删了不影响构建）
```

---

## 和你旧包的关系

`_ref\` 是 `Ace6_6.6.66_6.6.89_6.6.118_NianXiang_BakaSU35257_SUSFS2.2.0_PATCH_SOURCE.zip` 解出来的，里面 `features.config` 和 `common.patch` 印证了这套组合：

- `CONFIG_KSU_FULL_NAME_FORMAT="%TAG_NAME%-念想."` → 就是 `v4.2.0-rc3-念想.`
- 三份 `features.config` 已提取到 `patches\features\`，`--profile full` 时按内核版本匹配并入
- 22 项 SUSFS 相关配置在构建时全部写入 defconfig

旧包是「三合一 payload 选择器」AK3（一个 zip 里塞三个 Image，靠 Go 选择器按模块匹配挑一个）。本地构建是**一机型一 zip 单 Image**，刷之前不会选错版本，也不用塞几百 MB 的多余 Image。

---

# 云端构建（GitHub Actions）

本地网络到 github/codelinaro 抽风时，用云上跑。runner 是微软机房，拉源码几分钟，几十 G 不走你的宽带。

## 1. 建一个空仓库

GitHub 上新建 `gki-ak3`（public 免费跑 Actions；private 每月 2000 分钟，编一台约 60 分钟）。

## 2. 推上去

```powershell
cd F:\GKI
git remote remove origin 2>$null
git remote add origin https://github.com/<你的用户名>/gki-ak3.git
git push -u origin main
```

首次推可能要 Personal Access Token 当密码（Settings → Developer settings → Tokens，勾 `repo` 权限）。

## 3. 跑

仓库页 → `Actions` → 左边 `Build AK3` → `Run workflow`：

| 输入 | 填什么 |
|---|---|
| devices | 机型 id，逗号分隔：`oneplus_ace_6,oneplus_13_b` |
| suffix | `念想`（默认） |
| kpm | `N/A` / `KPM` / `KPN` |
| profile | `core` / `full` |
| jobs | 留空自动，runner 是 4 核 |
| keep_source | 编多台同芯片时打开，第二台省一半时间 |

跑完在 run 页面底部下 `AK3-<run号>`，解开就是刷包。日志在 `logs-<run号>`。

## 云端同样带你这套配置

- BakaSU 固定 commit `516d3e87` → 版本号 35257
- SUSFS 2.2.0 补丁走 `patches/susfs-v2.2.0/`（本地补丁优先，缺 KMI 才回退上游）
- 内核后缀 `念想`：`setlocalversion` + `CONFIG_KSU_FULL_NAME_FORMAT="%TAG_NAME%-念想."`
- 198 台机型映射表 `config/manifest-map.tsv` 已内置，云端不用探测清单

## 云端能撑住吗

runner 默认可用 30G 左右，`scripts/ci_free_space.sh` 会清掉 dotnet / Android SDK / CodeQL 等腾到 70G+，一台 6.x 内核够编。编完源码默认删掉；编第二台同芯片就把 `keep_source` 打开。

---

# 本地提速清单

| 手段 | 效果 |
|---|---|
| 同芯片共用源码目录（已开） | ace6 编完再编 13_b / ace5 同芯片，不重拉 60G，直接增量编译 |
| ccache 按 KMI 共享（已开） | 换机型但内核版本相同，命中大部分编译缓存 |
| 并发按内存自动 | 10G 内存自动 -j5，想硬上 `--jobs 6` |
| `--no-sync` | 源码已经完整时跳过同步检查 |
| `--no-share-src` | 关掉共用，回到按机型独立目录 |

同芯片分组例子：

- `oneplus/sm8750`：ace_6、13_b、13、15、15r …
- `oneplus/sm8650`：ace5、ace3_pro …
- 分组表在 `config/manifest-map.tsv` 第三列
