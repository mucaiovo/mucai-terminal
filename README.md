# mucai-terminal

这是我（慕彩）自己攒的一套终端美化方案，一条命令装到任意 Windows 机器上。

同一套设计在两端落地：Linux 端是 **kitty + fish**，Windows 端是 **Windows Terminal + PowerShell 7 + starship**。
配色、提示符、字号、透明度、补全手感都指向同一个目标 —— 换台机器、换个系统，终端还是同一套东西。

配色由 [matugen](https://github.com/InioX/matugen) 跟随壁纸自动生成（Material You），
所以换张壁纸，整套终端配色（WT 16 色 + 标签栏 + 提示符 + 信息面板 + opencode 主题）一起变。

## 从 GitHub 用

```powershell
git clone https://github.com/mucaiovo/mucai-terminal
cd mucai-terminal
pwsh -NoProfile -File .\Install-MucaiTerminal.ps1
```

> 也可以只下载 `Install-MucaiTerminal.ps1` 单个文件 —— 它把 starship.toml、fastfetch 配置、
> matugen 模板、`mucai-regen` / `Uninstall-MucaiTerminal` / `Update-Matugen` 三个脚本，
> 以及 **matugen.exe 本体**（4.7 MB，gzip+base64）全都内置了，不依赖网络。

装完日常就两条命令：

```powershell
mucai-regen -DryRun    # 看当前壁纸会生成什么颜色，不写文件
mucai-regen            # 应用
```

## 一条命令

```powershell
# 全新机器：装齐依赖 + 套用配置（不需要管理员权限）
pwsh -NoProfile -File .\Install-MucaiTerminal.ps1

# 先看看会改什么，不写任何文件
pwsh -NoProfile -File .\Install-MucaiTerminal.ps1 -DryRun

# 已经装好工具，只想套配置；字号和 Linux 端完全一致（10pt）
pwsh -NoProfile -File .\Install-MucaiTerminal.ps1 -SkipTools -FontSize 10
```

Windows PowerShell 5.1 也能跑这个脚本（用来自举安装 PowerShell 7）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-MucaiTerminal.ps1
```

> 执行策略如果拦住了：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`，
> 或者用上面的 `-ExecutionPolicy Bypass`。

## 脚本做了什么

| 步骤 | 内容 |
| --- | --- |
| 1 | 用 winget 装：PowerShell 7、Windows Terminal、starship、zoxide、eza、bat、yazi、fastfetch、JetBrainsMono Nerd Font |
| 2 | 检测系统里实际的 Nerd Font 族名（`JetBrainsMono NF` 和 `JetBrainsMono Nerd Font` 两种命名都认） |
| 3 | 写 `~/.config/starship.toml`、`~/.config/fastfetch/config.jsonc`、PowerShell profile |
| 4 | 合并 Windows Terminal 的 `settings.json`：配色方案、主题、字体、内边距、透明度、光标、`-NoLogo` |

关于透明度：微软文档明确写了「无模糊透明只在 Windows 11 生效」。
脚本会读注册表判断系统版本——Windows 11 上用无模糊纯透明（和 kitty 的 `background_opacity` 一致），
Windows 10 上自动退回亚克力模糊并提示，否则窗口会变成完全不透明。

同一套设计在两端的落点：

| Linux 端（kitty + fish） | Windows 端（WT + pwsh7 + starship） |
| --- | --- |
| kitty 的调色板（`dank-theme.conf` 那份） | WT 配色方案 `Mucai` |
| kitty 标签栏（`dank-tabs.conf`） | WT 主题 `Mucai`（标签行 / 活动标签底色） |
| `kitty.conf` 里的字体/字号/`padding 5`/`opacity 80`/`cursorShape filledBox`/`narrow_symbols` | WT 的 `font.face`、字号、`padding`、`opacity`、`cursorShape`、`builtinGlyphs` |
| fish `config.fish` 的 starship/zoxide 初始化 + 别名 | PowerShell profile：`cat`→bat、`ls`/`lt`→eza、`fa`→fastfetch、`y`（yazi 退出切换目录）、`滚`/`安装`/`卸载`（dnf 版翻成 winget）、`reboot` |
| fish 的补全与提示手感 | PSReadLine：灰色自动建议、Tab 补全菜单、上下键前缀搜索、Emacs 键位 |
| 开终端时的 `fastfetch` | 同样在开新终端时显示 |

## 参数

| 参数 | 说明 |
| --- | --- |
| `-FontSize <int>` | Windows Terminal 字号，默认 `11`（Linux 端用的是 10.0，想要严格一致传 `10`） |
| `-SkipTools` | 不装任何东西，只写配置 |
| `-SkipFont` | 跳过字体检测与安装；**不会**改动 `font.face`（字号和 `builtinGlyphs` 仍会设置） |
| `-NoBanner` | 开新终端时不显示 fastfetch 信息面板 |
| `-SkipLegacyProfile` | 只写 PowerShell 7 的 profile，不动 Windows PowerShell 5.1 的 |
| `-TerminalSettingsPath <path>` | 手动指定 WT 的 `settings.json`（便携版/非默认安装） |
| `-DryRun` | 只打印将要做什么，不写任何文件 |
| `-ForceBaseConfig` | 即使用 matugen 接管了，也用固定配色覆盖 starship.toml / fastfetch 配置 |

## 让配色跟随壁纸（matugen）

可选的一层：装好之后，终端配色由**当前壁纸**生成 —— 两端跑的是同一套 matugen 流程、同一份模板、
同一个 matugen 版本（4.2.0），所以同一张壁纸在两端会生成完全相同的配色。

### 它刷新哪些东西

| 产物 | 颜色来源 |
| --- | --- |
| `~/.config/starship.toml` | matugen 模板（与 Linux 端逐字节相同） |
| `~/.config/fastfetch/config.jsonc` | 同上 |
| `~/.config/opencode/themes/matugen.json` | 同上（只在装了 opencode 时生成） |
| Windows Terminal 的 `Mucai` 方案 + 主题 | Material You token（窗口外观）+ base16（16 个 ANSI 槽） |

#### opencode 的额外一步：选中

主题文件由 matugen 生成，但**光有文件不够** —— opencode 的主题选中状态存在它自己的状态文件
`~/.local/state/opencode/kv.json` 的 `"theme":"matugen"` 里。那不是配置项，`opencode.jsonc`
里也没有 `theme` 这一项（schema 的 `additionalProperties: false` 反而会判它非法）。

两种做法：

* **退出 opencode 后跑 `mucai-regen`** —— 它会顺手把 `kv.json` 里的 `theme` 设成 `matugen`（会备份）。
* **在 opencode 里用 `/theme` 选一次 matugen**。opencode 正在运行时只能这么做：它退出时会把内存里的
  状态写回 `kv.json`，盖掉外部的修改，所以此时 `mucai-regen` 只更新主题文件并提醒你。

改完主题要**重启 opencode** 才生效（它在启动时读一次）。

### 一次性准备

> **大多数情况下你不需要做这一步** —— `Install-MucaiTerminal.ps1` 里已经内置了 matugen 4.2.0
> （gzip+base64，10.9 MB），装的时候直接释放成 `~/.local/bin/matugen.exe`，不需要 Rust、不需要编译。
> 只有想自己从源码构建、或者要升级版本时，才需要下面这一套。

装 Rust 的 **GNU** 工具链（不要用默认的 MSVC —— 没有 MSVC 会在链接阶段失败）：

```powershell
winget install Rustlang.Rustup
rustup toolchain install stable-x86_64-pc-windows-gnu
cargo +stable-x86_64-pc-windows-gnu install matugen --locked
```

实测：编译约 **9 分钟**，产出 matugen 4.2.0。模板和配置由 `Install-MucaiTerminal.ps1` 铺到 `~/.config/matugen/`。

**装完可以把整个 Rust 工具链卸掉省空间** —— matugen.exe 是静态的独立程序：

```powershell
# 1) 把 matugen.exe 挪到 ~/.local/bin（profile 已经在维护这个 PATH，mucai-regen 也优先找这里）
Copy-Item "$env:USERPROFILE\.cargo\bin\matugen.exe" "$env:USERPROFILE\.local\bin\" -Force

# 2) 卸掉 Rust（实测回收约 2.2 GB；matugen.exe 留在 ~/.local/bin 不受影响）
rustup self uninstall -y
```

> `rustup self uninstall` 会删掉整个 `~/.cargo` 和 `~/.rustup`（包括 `~/.cargo\bin\matugen.exe`），
> 所以**先复制再卸载**。卸载后 `mucai-regen` 会自动从 `~/.local/bin` 找到 matugen。

> **国内网络**：`static.rust-lang.org` 会卡（实测停滞十分钟），换 USTC 镜像快约 15 倍：
> ```powershell
> $env:RUSTUP_DIST_SERVER = 'https://mirrors.ustc.edu.cn/rust-static'
> rustup toolchain install stable-x86_64-pc-windows-gnu
> ```
> 另外 `winget install Rustlang.Rustup` 会**卡在 rustup-init 的交互确认**上，
> 需要手动结束（`Stop-Process -Name rustup-init -Force`）—— rustup 本身其实已经装好了。

### 日常使用

```powershell
mucai-regen                                # 用当前壁纸刷新整套
mucai-regen -DryRun                        # 只看会变成什么色，不写任何文件
mucai-regen -Ansi classic                  # ANSI 16 色保持现在这套 pastel
mucai-regen -Wallpaper "D:\pics\x.png"     # 换一张图试试
mucai-regen -Rollback                      # 退回上一次生成之前
```

跑完 Windows Terminal 会**热重载**，开个新标签页即可，不用重启。

### 两种 ANSI 模式的实际差别

以你当前壁纸为例（`--prefer saturation` 选中源色 `#1b63fd`）：

| 槽位 | `-Ansi classic`（= 你现在这套） | `base16`（默认，随壁纸） |
| --- | --- | --- |
| 背景 / 前景 / 光标 / 选中 | `#121318` `#E3E2E9` `#B5C4FF` `#C1C5DD` | **完全相同** |
| 红 | `#FF7297` | `#FF6699` |
| 绿 | `#7FFF94` | `#00B447` |
| 黄 | `#FFF972` | `#8699DC`（是蓝的） |
| 蓝 | `#9DAEF2` | `#7597FF` |
| 紫 | `#334479` | `#EE62ED` |
| 青 | `#B5C4FF` | `#C687BF`（是品红） |

原因：`classic` 保留的是这套方案最早那组**固定色相**（粉/绿/黄/蓝）+ 随方案调明度算出来的结果，
所以永远有语义正确的黄和青；而 matugen 的 base16 是**从图里取色**，一张蓝调壁纸里根本没有黄和青。
`ls`、`git diff` 的语义色会因此改变 —— 喜欢现在这套就用 `-Ansi classic`。

### 回滚（三级 + 一键卸载）

| 想退到哪 | 怎么做 |
| --- | --- |
| 上一次生成之前 | `mucai-regen -Rollback`（快照在 `~/.cache/mucai-terminal/last/`） |
| 安装脚本刚装完的固定配色 | `pwsh -File .\Install-MucaiTerminal.ps1 -ForceBaseConfig` |
| 手工改坏之前 | Windows Terminal 自己留的 `settings.json.bak-<时间戳>` |
| 不想要这套配置了 | `pwsh -File .\Uninstall-MucaiTerminal.ps1`（见下） |

三层互不干扰：`mucai-regen` 每次成功生成前都会先快照；安装脚本**不会**用固定配色覆盖 matugen 的产物，
除非你显式加 `-ForceBaseConfig`。

## 更新 matugen

上游 matugen **从来不发 Windows 二进制**（26 个 release 全部只有 Linux 的 ELF），
winget / scoop / Chocolatey / cargo-binstall 也都没有。所以我们在自己的仓库
[`mucaiovo/matugen-win`](https://github.com/mucaiovo/matugen-win/releases) 里用 GitHub Actions
编好并发布 —— **本机永远不需要 Rust 工具链**。

日常只有一条命令：

```powershell
matugen-update -DryRun           # 看本机版本 vs GitHub 最新版本，什么都不下载
matugen-update                   # 从 GitHub 下载并安装（约 20 秒）
matugen-update -Version 4.3.0    # 指定版本
matugen-update -Force            # 版本相同也重装
```

它做的事：查该仓库的 Release → 下载 `matugen.exe` → 用 `SHA256SUMS.txt` 校验 →
试跑一次确认能启动 → 备份旧版本 → 装到 `~/.local/bin`。**全程不编译。**

> 仓库名可以用 `-Repo owner/name` 或环境变量 `MATUGEN_WIN_REPO` 换；私有仓库需要 `-Token`。

### 万一 GitHub 上没有你要的版本

```powershell
matugen-update -Build                    # 从 crates.io 拉源码编译（约 9 分钟，临时装 Rust）
matugen-update -Build -KeepToolchain     # 编译完保留工具链（多占约 2 GB，下次更快）
matugen-update -Build -Version 4.3.0
```

编译路径会自动：装 rustup（顺带清掉卡住的 `rustup-init`）→ 装 GNU 工具链（走 USTC 镜像）
→ `cargo install matugen --force` → 拷到 `~/.local/bin` → 卸掉工具链（回收约 2 GB）。

### 这个仓库是怎么来的

把 [`_build\github\build-matugen.yml`](_build/github/build-matugen.yml) 放进一个**空仓库**即可
（不用 fork 上游 —— 源码从 crates.io 拉）。它每周一自动检查 crates.io：
有新版本就编译并发布 Release，没有就跳过（约 20 秒）。配置步骤见
[`_build/github/README.md`](_build/github/README.md)。

已验证：CI 用 MSVC 编出来的 exe，**生成的配色与本地 GNU 编的逐字节一致**
（exe 是 8.7 MB vs 23.9 MB，差别只在链接方式，不影响输出）。

### ⚠️ 升级不一定是好事

**版本变化可能改变生成的配色** —— 调色算法、模板引擎在不同版本间会动。所以：

* 升级完先 `mucai-regen -DryRun` 看颜色，确认再 `mucai-regen`；
* 想保住"两端逐字节一致"这个性质，**两边的 matugen 版本要同步**
  （Linux 端是 `pacman -S matugen`）。

### 让安装脚本也带上新版本

安装脚本内置的是 4.2.0（现在只有 **4.7 MB**，来自 Release 里的 `.gzb64`）。升级后要重新分发，把内置的也换掉：

```powershell
# 1) 从 Releases 下载 matugen-<版本>.gzb64，放进 _build\matugen\（同名文件直接覆盖）
python .\_build\inject.py                        # 重新注入（会自检全部载荷）
pwsh -NoProfile -File .\_build\test-merge.ps1    # 回归测试
```

`inject.py` 会取 `_build\matugen\matugen-*.gzb64` 里最新的那个；如果没有这个文件，
它会生成一个**不带内置 exe** 的安装脚本（其余功能照常，装完靠 `mucai-regen` 前的 `matugen-update` 补）。

> 本地已经装好新版时，也可以用 `_build\make-matugen-blob.ps1` 从 `~/.local/bin\matugen.exe`
> 现场生成 `.gzb64` —— 效果和下载 Release 里那份一样，只是多花一步。

> **也可以完全不重新生成脚本**：把新的 `matugen.exe` 直接放在安装脚本**同一个目录**里，
> 安装脚本会优先用它（按 SHA256 判断是否一致），内置的那份只作为兜底。

### 关于"杀软可能报毒"

内置 exe 用的是 gzip + base64（**4.7 MB**，解压后 8.7 MB，SHA256 与 Release 一致，耗时约 0.2 秒）。
**"一个脚本解出二进制再落盘"是恶意软件常用的形态**，个别杀软/EDR 可能会拦。
实测你这台机器上 Defender 没有告警；如果换台机器被拦，用同目录放 `matugen.exe` 的方式绕开即可。

## 彻底卸载

`Uninstall-MucaiTerminal.ps1` 会把这套配置留下的东西清干净（也会被安装脚本一起铺到 `~/.local/bin`）：

```powershell
pwsh -NoProfile -File .\Uninstall-MucaiTerminal.ps1 -DryRun   # 先看会做什么
pwsh -NoProfile -File .\Uninstall-MucaiTerminal.ps1           # 安全回滚
```

默认动作（**不碰你装的命令行工具，也不碰你自己的设置**）：

1. 从 `settings.json` 移除 `Mucai` 配色方案与主题，`theme` 复位为 `system`，
   `defaults.colorScheme` 移除（你原有的其它配色方案、快捷键、profile 一律不动）
2. 去掉 PowerShell profile 上的 `-NoLogo`（恢复启动横幅）
3. 删除 `~/.config/matugen/`
4. 删除 `~/.local/bin/mucai-regen.ps1`（`matugen.exe` 默认保留）
5. 删除 `~/.cache/mucai-terminal/`
6. 从 PowerShell profile 里移除 `mucai-regen` 函数（只删 `# >>> mucai-terminal` 标记块，其余内容不动）

更彻底的选项：

| 参数 | 作用 |
| --- | --- |
| `-RestoreSettings` | 不用"精准移除"，整份恢复 `settings.json`（默认挑**最旧**那份备份，也就是第一次改动之前的原始状态；会先把所有备份列出来） |
| `-RestoreFrom <文件>` | 指定恢复某一份备份 |
| `-RemoveTools` | 额外用 winget 卸载 starship / zoxide / eza / bat / yazi / fastfetch |
| `-RemoveMatugen` | 额外删除 `~/.local/bin/matugen.exe` |
| `-DryRun` | 只打印，不动任何东西 |

> 注意：默认回滚**不**清理 `profiles.defaults` 里的外观键（字体、字号、内边距、透明度、光标等）——
> 它们不影响你使用，留着也就是这套主题的样子。想连外观一起还原，用 `-RestoreSettings` 整份恢复。


### 已知的坑（都是实测撞到的）

* **base16 在 image 模式下是坏的**：`matugen image <壁纸> -b wal` 会产出近黑的垃圾值（`base08 = #000004`）。
  所以 `mucai-regen` 跑**两趟**：第一趟从壁纸出 M3 配色并导出被选中的源色，第二趟用 `color hex <源色>` 生成 base16。
* **`--prefer` 必须显式给**：图里有多个候选种子色时 matugen 会弹交互选择器，脚本环境里会直接报错。
  默认 `saturation`，可用 `-Prefer value|lightness|less-saturation`。
* **`--json` 不是导出路径**，是输出颜色格式（hex/rgb/hsl），帮助文案有误导。
* 模板关键字要带 `.default` 层级：`{{colors.surface.default.hex}}`、`{{base16.base00.default.hex}}`；
  base16 的名字里字母是**小写**（`base0a` 而非 `base0A`）。

## 安全性

* **幂等**：重复执行不会重复写入，内容没变的文件会打印「已是最新，跳过」。
* **先备份**：任何被覆盖的文件都会生成 `<原名>.bak-yyyyMMdd-HHmmss`。
* **不碰无关设置**：只增删自己管理的键，你原有的配色方案、快捷键、profile 列表都会保留，
  同时把 `defaultProfile` 指向 PowerShell 7。
* 只改当前用户的配置，不需要管理员权限。

恢复原状：把 `*.bak-*` 改回原名即可（WT 的 `settings.json` 在
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`）。

## 两端不完全一样的地方（取舍）

这些是两端能力差异，不是实现偷懒：

* `cursor_trail`（光标拖尾动画）、`cursor_text_color`：WT 没有对应设置。
* `tab_bar_style powerline` + `slanted`：WT 的标签不支持斜切能量条，只能用底色近似；
  标签文字颜色由 WT 自动对比度决定，锁不了 kitty 里的 `#1b2d61`。
* `tab_bar_min_tabs 2`：WT 只有一个标签时也会显示标签行。
* `tab_title_template`（`{title[:30]} [{index}]` + 活动/铃声符号）：WT 没有标题模板。
* `fallback_fonts ... Sarasa UI SC`：WT 不支持字体回退列表，中文回退交给系统。
* `confirm_os_window_close 0`：WT 的等价项是 `"warning.confirmOnClose": "never"`，
  脚本默认没设（保留关闭确认，避免误关正在跑的任务），需要的话自己加。
* fish 的 `abbr` 是「边打字边展开」，PowerShell 没有这个机制，脚本用函数/别名代替（回车后生效）。
* `sl | lolcat`、`grub`、`lsfg` 是 Linux 专属，Windows 端没做。

## 目录结构

```
Install-MucaiTerminal.ps1        安装脚本（可分发的单个文件，自带全部配置内容；
                                会把 mucai-regen、matugen 模板与配置、卸载脚本一起铺好）
Uninstall-MucaiTerminal.ps1      回滚 / 卸载脚本
mucai-regen.ps1                  用壁纸刷新整套配色（装到 ~/.local/bin/，profile 里有同名函数）
README.md
_build/
  Install-MucaiTerminal.template.ps1   脚本模板（逻辑写在这里，payload 用标记占位）
  inject.py                           把真实文件注入模板，生成上面的脚本（附自检）
  test-merge.ps1                      回归测试：对 fixture 跑合并并断言结果
  fixtures/                           回归测试用的两份 settings.json（全新机器 / 已配置过的机器）
  matugen/                            matugen 的 Windows 配置、模板、以及安装用的 fastfetch 载荷
  matugen-verify/                     跨平台同源验收脚本（verify.ps1，比对两端的产物）
  reference/                          同一套 matugen 模板与"标准答案"，用于逐字节比对
```

### 改了配置之后怎么重新生成

`Install-MucaiTerminal.ps1` 里的配置内容是**注入**进去的，不要手工编辑：

1. 改 `_build/Install-MucaiTerminal.template.ps1`（只有这一步是改逻辑）；
2. 如果改的是 starship.toml / fastfetch 配置 / PowerShell profile，
   更新 `_build/inject.py` 顶部的 `STARSHIP` / `FASTFETCH` / `LIVE_PROFILE` 指向的文件；
3. 重新生成并验证：

```powershell
python .\_build\inject.py
pwsh -NoProfile -File .\_build\test-merge.ps1
```

`inject.py` 会拒绝注入含 `'@` 行首的内容（会截断 here-string），
并且注入的是文件原文，避免手抄 Nerd Font 图标出错。

## 两端一致（验收）

`_build/matugen-verify/verify.ps1` 用来验证「同一张壁纸 + 同一份模板 + 同一个 matugen 版本，
两端生成的文件逐字节相同」：它用固定种子跑一遍 matugen，把结果与 `_build/reference/expected/`
里的标准答案逐字节比对。改了模板之后跑一次，就知道两端有没有跑偏。


## 许可

* 本仓库自己的脚本：[MIT](LICENSE)
* 安装脚本内置的 matugen.exe：GPL-2.0-or-later（第三方软件，见 [THIRD-PARTY-LICENSES.txt](THIRD-PARTY-LICENSES.txt)）

安装脚本内置的 matugen 由本仓库 CI 从 crates.io 的源码构建，未做修改，
按 GPL 要求附带了完整许可文本与源码出处。