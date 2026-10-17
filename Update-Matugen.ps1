#Requires -Version 5.1
<#
.SYNOPSIS
    更新 matugen.exe —— 默认从 GitHub Release 直接下载，不用编译、不用 Rust。

.DESCRIPTION
    两条路径：

      GitHub（默认）  从 https://github.com/<Repo>/releases 下载现成的 matugen.exe，
                      校验 SHA256 后装到 ~/.local/bin。几十秒完成，不需要任何工具链。
      -Build          从 crates.io 拉源码自己编（临时装 Rust 工具链，约 9 分钟）。
                      只在"这个版本还没发布到 GitHub"或者想自己验一遍源码时才用。

    为什么默认走 GitHub：上游 matugen 从不发 Windows 二进制，所以我们在自己的仓库里
    用 CI 编好并发布（见 mucai-terminal\_build\github\）。这个脚本只是去那儿拿。

.PARAMETER Repo
    GitHub 仓库，默认 mucaiovo/matugen-win。
    也可以设环境变量 MATUGEN_WIN_REPO。

.PARAMETER Version
    指定版本（如 4.2.0）。默认取最新 Release。

.PARAMETER Build
    强制从源码编译（原来的路径，需要 Rust 工具链）。

.PARAMETER KeepToolchain
    配合 -Build：编译完保留 Rust 工具链（下次更快，多占约 2 GB）。

.PARAMETER Force
    即使本机版本已经等于目标版本，也重新下载/编译安装。

.PARAMETER Token
    私有仓库时才需要。默认会读 GH_TOKEN / GITHUB_TOKEN 环境变量。

.PARAMETER DryRun
    只打印计划，不下载、不装。

.EXAMPLE
    matugen-update -DryRun
    看本机版本 vs GitHub 上最新版本，什么都不做。

.EXAMPLE
    matugen-update
    从 GitHub 下载最新版并安装。

.EXAMPLE
    matugen-update -Build
    自己编译（GitHub 上还没发布的版本用这个）。
#>
[CmdletBinding()]
param(
    [string]$Repo = $(if ($env:MATUGEN_WIN_REPO) { $env:MATUGEN_WIN_REPO } else { 'mucaiovo/matugen-win' }),
    [string]$Version,
    [switch]$Build,
    [switch]$KeepToolchain,
    [switch]$Force,
    [switch]$DryRun,
    [string]$Token = $(if ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { '' })
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

function Write-Step { param([string]$m) Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok { param([string]$m) Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Skip { param([string]$m) Write-Host "    [  ] $m" -ForegroundColor DarkGray }
function Write-Warn { param([string]$m) Write-Host "    [!!] $m" -ForegroundColor Yellow }

$localBin = Join-Path $HOME '.local\bin'
$target = Join-Path $localBin 'matugen.exe'
$cargoBin = Join-Path $HOME '.cargo\bin'
$rustup = Join-Path $cargoBin 'rustup.exe'
$cargo = Join-Path $cargoBin 'cargo.exe'
$toolchain = 'stable-x86_64-pc-windows-gnu'

Write-Host ''
Write-Host 'Update-Matugen —— 更新 matugen.exe' -ForegroundColor White

# ---------------------------------------------------------------------------
Write-Step '1/5 检查当前版本'
$current = $null
if (Test-Path $target) {
    try { $current = (& $target --version 2>&1 | Select-Object -First 1) -replace '^matugen\s+', '' } catch { }
}
if ($current) { Write-Ok "本机：$current  ($target)" } else { Write-Skip '本机还没有 matugen.exe' }

if ($Build) {
    # =======================================================================
    # 路径 B：从源码编译
    # =======================================================================
    $latest = $null
    try {
        $meta = Invoke-RestMethod -Uri 'https://crates.io/api/v1/crates/matugen' -TimeoutSec 20 `
            -Headers @{ 'User-Agent' = 'mucai-terminal' }
        $latest = $meta.crate.max_stable_version
        Write-Ok "crates.io 最新：$latest"
    }
    catch { Write-Warn "查不到 crates.io 版本（$($_.Exception.Message.Split([char]10)[0])）" }

    $goal = if ($Version) { $Version } elseif ($latest) { $latest } else { $null }
    if (-not $goal) { throw '既没有 -Version，也查不到最新版本，无法继续' }
    if ($current -eq $goal -and -not $Force) {
        Write-Host ''
        Write-Ok "已经是最新（$goal），不用更新。想强制重装加 -Force。"
        exit 0
    }

    Write-Step '2/5 计划（源码编译）'
    Write-Host "    目标版本：$goal" -ForegroundColor DarkGray
    Write-Host "    工具链：  $toolchain（临时安装，不需要 MSVC）" -ForegroundColor DarkGray
    Write-Host "    结束处理：$(if ($KeepToolchain) { '保留工具链' } else { '卸掉整个 Rust 工具链（回收约 2 GB）' })" -ForegroundColor DarkGray
    Write-Host '    预计耗时：10–20 分钟' -ForegroundColor DarkGray
    if ($DryRun) { Write-Host ''; Write-Host '这是 -DryRun，什么都没有装。' -ForegroundColor Yellow; exit 0 }

    Write-Step '3/5 准备 Rust 工具链'
    if (Test-Path $rustup) { Write-Skip 'rustup 已存在' }
    else {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw '没有 winget，装不了 rustup。请手动安装 Rust 后重跑。'
        }
        Write-Host '    -> winget install Rustlang.Rustup' -ForegroundColor DarkGray
        winget install --id Rustlang.Rustup -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
        Get-Process -Name rustup-init -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Skip "清掉卡住的 rustup-init（pid $($_.Id)）"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $rustup)) { throw "rustup 没装上：$rustup" }
        Write-Ok 'rustup 就位'
    }
    $hasToolchain = (& $rustup toolchain list 2>&1) -match [regex]::Escape($toolchain)
    if ($hasToolchain) { Write-Skip "$toolchain 已安装" }
    else {
        Write-Host "    -> rustup toolchain install $toolchain（走 USTC 镜像）" -ForegroundColor DarkGray
        $env:RUSTUP_DIST_SERVER = 'https://mirrors.ustc.edu.cn/rust-static'
        $env:RUSTUP_UPDATE_ROOT = 'https://mirrors.ustc.edu.cn/rust-static/rustup'
        & $rustup toolchain install $toolchain 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "工具链安装失败（退出码 $LASTEXITCODE）" }
        Write-Ok "$toolchain 装好了"
    }

    Write-Step '4/5 编译 matugen（约 9 分钟）'
    $installArgs = @('+stable-x86_64-pc-windows-gnu', 'install', 'matugen', '--force')
    if ($Version) { $installArgs += @('--version', $Version) } else { $installArgs += '--locked' }
    Write-Host "    -> cargo $($installArgs -join ' ')" -ForegroundColor DarkGray
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $cargo @installArgs 2>&1 | Select-String -Pattern 'Compiling matugen|Installing|Installed|error' | ForEach-Object { "      $($_.Line.Trim())" }
    $sw.Stop()
    if ($LASTEXITCODE -ne 0) { throw "编译失败（退出码 $LASTEXITCODE）" }
    Write-Ok ("编译完成，耗时 {0:N1} 分钟" -f $sw.Elapsed.TotalMinutes)

    $built = Join-Path $cargoBin 'matugen.exe'
    if (-not (Test-Path $built)) { throw "没找到编译产物：$built" }
    if (Test-Path $target) { Copy-Item -LiteralPath $target -Destination "$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force }
    New-Item -ItemType Directory -Force -Path $localBin | Out-Null
    Copy-Item -LiteralPath $built -Destination $target -Force
    Write-Ok "已安装：$(& $target --version)"

    Write-Step '5/5 收尾'
    if ($KeepToolchain) { Write-Skip '-KeepToolchain：保留 Rust 工具链' }
    else {
        Write-Host '    -> rustup self uninstall -y' -ForegroundColor DarkGray
        & $rustup self uninstall -y 2>&1 | Select-String -Pattern 'removing|uninstalled' | ForEach-Object { "      $($_.Line.Trim())" }
        if (-not (Test-Path (Join-Path $HOME '.rustup'))) { Write-Ok 'Rust 工具链已卸载（约 2 GB）' } else { Write-Warn '工具链可能没卸干净' }
    }

    Write-Host ''
    Write-Host "更新完成：$current -> $goal" -ForegroundColor Green
    Write-Host '版本变化可能改变配色，建议先：mucai-regen -DryRun' -ForegroundColor Yellow
    exit 0
}

# =======================================================================
# 路径 A：从 GitHub Release 下载（默认）
# =======================================================================
Write-Step '2/5 查询 GitHub Release'
$wantVer = if ($Version) { $Version -replace '^v', '' } else { $null }
$headers = @{ 'User-Agent' = 'mucai-terminal'; 'Accept' = 'application/vnd.github+json' }
if ($Token) { $headers['Authorization'] = "Bearer $Token" }
$uri = if ($wantVer) { "https://api.github.com/repos/$Repo/releases/tags/v$wantVer" }
       else { "https://api.github.com/repos/$Repo/releases/latest" }
Write-Host "    仓库：$Repo$(if ($wantVer) { "  版本：$wantVer" } else { '  版本：latest' })" -ForegroundColor DarkGray

try {
    $rel = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30 -ErrorAction Stop
}
catch {
    $code = $null
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code -eq 404) {
        $what = if ($wantVer) { "版本 $wantVer" } else { '任何 Release' }
        Write-Warn "$Repo 上没有$what"
        Write-Host '    想自己编这个版本：' -ForegroundColor DarkGray
        Write-Host "      matugen-update -Build$(if ($Version) { " -Version $Version" })" -ForegroundColor DarkGray
        exit 1
    }
    throw "查询 GitHub Release 失败（HTTP $code）：$($_.Exception.Message)"
}

$goal = ($rel.tag_name -replace '^v', '')
Write-Ok "GitHub 最新：$goal  (tag $($rel.tag_name)，发布于 $($rel.published_at))"

if ($current -eq $goal -and -not $Force) {
    Write-Host ''
    Write-Ok "已经是最新（$goal），不用更新。想强制重装加 -Force。"
    exit 0
}

$exeAsset = $rel.assets | Where-Object { $_.name -eq 'matugen.exe' } | Select-Object -First 1
$sumAsset = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
if (-not $exeAsset) {
    throw "这个 Release 里没有 matugen.exe（只有：$(($rel.assets.name) -join ', ')）"
}

Write-Step '3/5 下载并校验'
if ($DryRun) {
    Write-Host "    会下载 matugen.exe（$([math]::Round($exeAsset.size/1MB,1)) MB）并校验 SHA256" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '这是 -DryRun，什么都没有下载。' -ForegroundColor Yellow
    exit 0
}

$tmp = Join-Path $env:TEMP ("matugen-dl-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $exeTmp = Join-Path $tmp 'matugen.exe'
    Write-Host "    -> $($exeAsset.name)  ($([math]::Round($exeAsset.size/1MB,1)) MB)" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $exeAsset.browser_download_url -OutFile $exeTmp -UseBasicParsing -TimeoutSec 180
    $actual = (Get-FileHash $exeTmp -Algorithm SHA256).Hash

    if ($sumAsset) {
        $sumTmp = Join-Path $tmp 'SHA256SUMS.txt'
        Invoke-WebRequest -Uri $sumAsset.browser_download_url -OutFile $sumTmp -UseBasicParsing -TimeoutSec 60
        $expected = $null
        foreach ($line in (Get-Content $sumTmp)) {
            if ($line -match 'matugen\.exe') { $expected = ($line -split '\s+')[0]; break }
        }
        if (-not $expected) { $expected = ((Get-Content $sumTmp -Raw) -split '\s+')[0] }
        if ($actual -ne $expected) {
            throw "SHA256 校验失败！`n      期望 $expected`n      实际 $actual"
        }
        Write-Ok "SHA256 校验通过：$actual"
    }
    else {
        Write-Warn "这个 Release 没带 SHA256SUMS.txt，跳过校验（实际 SHA256：$actual）"
    }

    # 先做一次冒烟测试，确认它真能跑，再覆盖线上那份。
    # 注意：不要紧跟着用 `| Select-Object -First 1` —— 它会在拿到第一行后提前掐断管道，
    # 进程可能被中止，$LASTEXITCODE 就不可靠了（会误报"跑不起来"）。
    $rawOut = & $exeTmp --version 2>&1
    $exeCode = $LASTEXITCODE
    $verOut = (@($rawOut) | Select-Object -First 1)
    if ($exeCode -ne 0 -or "$verOut" -notmatch 'matugen') { throw "下载的 exe 跑不起来（退出码 $exeCode）：$verOut" }
    Write-Ok "试跑通过：$verOut"

    Write-Step '4/5 安装'
    if (Test-Path $target) {
        $bak = "$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $target -Destination $bak -Force
        Write-Ok "旧版本已备份 -> $bak"
    }
    New-Item -ItemType Directory -Force -Path $localBin | Out-Null
    Copy-Item -LiteralPath $exeTmp -Destination $target -Force
    Write-Ok "已安装：$(& $target --version)"
    Write-Ok "SHA256：$actual"
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step '5/5 完成'
Write-Host "    $current -> $goal" -ForegroundColor Green
Write-Host ''
Write-Host '版本变化可能改变生成的配色，建议先看一眼再应用：' -ForegroundColor Yellow
Write-Host '    mucai-regen -DryRun      # 只看颜色' -ForegroundColor DarkGray
Write-Host '    mucai-regen              # 确认后应用' -ForegroundColor DarkGray
