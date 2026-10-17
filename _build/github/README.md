# 用 GitHub Actions 构建 matugen（Windows）

目的：**上游不发 Windows 二进制，所以自己用 CI 编一次，之后更新只是"下载"**，本地永远不需要 Rust 工具链。

## 一次性配置（约 5 分钟）

1. 在 GitHub 上新建一个仓库，名字随意（比如 `matugen-win`）。**public / private 都行** ——
   GitHub Free 每月有 2000 分钟 Actions 额度，这个 workflow 每次约 9 分钟，每周跑一次也就 36 分钟/月。
2. 把 `build-matugen.yml` 放到仓库里的 `.github/workflows/build-matugen.yml`。
3. 打开仓库的 **Actions** 页面 → 左边选 `build-matugen-windows` → 右边 **Run workflow**。

跑完（约 10 分钟）在 **Releases** 页面就能看到 `v4.2.0`，里面有三个文件：

| 文件 | 用途 |
| --- | --- |
| `matugen.exe` | 直接可用的 Windows 程序 |
| `matugen-4.2.0.gzb64` | 给安装脚本内嵌用的（gzip+base64） |
| `SHA256SUMS.txt` | 校验和 |

之后**每周一 03:17 会自动检查** crates.io 有没有新版本：有就自动构建并发布一个 Release，没有就跳过（不会重复构建 —— 它先查这个 tag 的 Release 存不存在）。

也可以手动指定版本：Run workflow 时在 `version` 里填 `4.3.0`。

## 之后怎么"更新"

### 方式 A：只换本机（最省事）

1. 从 Release 下载 `matugen.exe`
2. 放到 `mucai-terminal\` **同一个目录**（和 `Install-MucaiTerminal.ps1` 并排）
3. 跑 `Install-MucaiTerminal.ps1` —— 它会优先用同目录那份（按 SHA256 判断），装到 `~/.local/bin`

或者直接手动覆盖：`Copy-Item matugen.exe "$env:USERPROFILE\.local\bin\" -Force`

### 方式 B：连安装脚本的内置版本一起换（重新分发时用）

1. 下载 `matugen-<版本>.gzb64`，放进 `mucai-terminal\_build\matugen\`
   （`make-matugen-blob.ps1` 会删掉旧版本的，所以不用手动清理）
2. `python .\_build\inject.py` —— 重新注入并自检
3. `pwsh .\_build\test-merge.ps1` —— 回归测试

### 更新完一定要做的一步

**版本变化可能改变生成的配色**（调色算法/模板引擎会动）：

```powershell
mucai-regen -DryRun    # 先看颜色有没有变
mucai-regen            # 确认后再应用
```

不满意：`mucai-regen -Rollback` 退回上一次。

## 几个已知点

* **构建环境用 MSVC**（`windows-latest` 自带），和我们本地用的 GNU 工具链不同。**生成的配色应该完全一致**
  （算法相同、Rust 的浮点行为是确定的），但 exe 的字节不同。介意的话可以在 workflow 里换成 GNU 目标，
  不过没必要 —— 真正要对齐的是**输出**，不是 exe 的哈希。
* **matugen 是 GPL-2.0-or-later**：自己构建、自己分发（哪怕 public 仓库）都是允许的，
  保留许可声明即可。如果设成 public 仓库，等于你在分发二进制，作者不负任何责任（GPL 本来就无担保）。
* Release 里的产物是**永久**的；artifact 只有 90 天。所以把文件放进 Release，别只靠 artifact。
* 如果哪天 workflow 跑失败，多半是上游依赖变动（比如 lockfile 里某个 crate 被 yank）。把 `--locked` 去掉重试，
  或者指定一个能编过的版本。
