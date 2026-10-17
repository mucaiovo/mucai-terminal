#Requires -Version 5.1
<#
.SYNOPSIS
    用 matugen 从当前 Windows 壁纸重新生成整套终端配色。

.DESCRIPTION
    一条命令把三样东西一起刷新，保证它们同源同值：

      1. ~/.config/starship.toml              （提示符）
      2. ~/.config/fastfetch/config.jsonc     （启动信息面板）
      3. Windows Terminal settings.json 里的 Mucai 配色方案 + 主题

    模板与 Linux 端那份逐字节相同、matugen 版本也是 4.2.0，所以两端生成结果一致。

    配色来源分两块：
      * 背景 / 前景 / 光标 / 选中 / 标签栏  -> Material You token（colors.surface 等）
      * 16 个 ANSI 槽                        -> 见 -Ansi 参数

    执行顺序：快照 -> matugen 输出到暂存目录 -> 校验 -> 落到线上文件。
    任何一步失败都不会动你现在的配置；每次成功生成之前都会先快照到
    ~/.cache/mucai-terminal/last/，随时可以用 -Rollback 退回去。

.PARAMETER Wallpaper
    壁纸文件路径。不指定则从注册表读当前桌面壁纸。

.PARAMETER Prefer
    一张图里能提出多个候选种子色时用哪个。默认 saturation —— 在你这台机器上它选中的
    #1b63fd 正好等于现在这套主题的种子，所以切到动态管线后观感不变。

.PARAMETER Ansi
    16 个 ANSI 槽（ls / git diff / 语法高亮的颜色）从哪来：
      base16  —— matugen 自带的 base16（wal 后端），完全随壁纸走（默认）
      classic —— 固定成你现在这套 pastel 配色（粉/绿/黄/蓝），只让窗口外观跟随壁纸

    提醒：base16 是"从图里取色"，一张蓝调壁纸可能提不出黄色和青色，yellow/cyan 槽的
    色相未必符合终端惯用语义；classic 模式则始终保住色相语义。

.PARAMETER Rollback
    不做生成，直接恢复到上一次成功生成之前的状态。

.PARAMETER DryRun
    完整跑一遍生成并打印结果，但不写任何线上文件。

.PARAMETER SettingsPath
    手动指定 Windows Terminal 的 settings.json（便携版 / 非默认安装，或用于测试）。

.EXAMPLE
    mucai-regen
    用当前壁纸刷新整套配色。

.EXAMPLE
    mucai-regen -Ansi classic
    保留现在这套 ANSI 配色，只让窗口外观跟随壁纸。

.EXAMPLE
    mucai-regen -Rollback
    退回上一次生成之前的样子。
#>
[CmdletBinding()]
param(
    [string]$Wallpaper,
    [ValidateSet('saturation', 'value', 'less-saturation', 'lightness')]
    [string]$Prefer = 'saturation',
    [ValidateSet('base16', 'classic')]
    [string]$Ansi = 'base16',
    [switch]$Rollback,
    [switch]$DryRun,
    [string]$SettingsPath,
    [string]$MatugenPath
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# matugen 的查找顺序：~/.local/bin（推荐 —— 卸掉 Rust 工具链后仍然可用）-> ~/.cargo/bin -> PATH
if (-not $MatugenPath) {
    $MatugenPath = @(
        (Join-Path $HOME '.local\bin\matugen.exe'),
        (Join-Path $HOME '.cargo\bin\matugen.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $MatugenPath) {
        $cmd = Get-Command matugen -ErrorAction SilentlyContinue
        if ($cmd) { $MatugenPath = $cmd.Source }
    }
}

function Write-Step { param([string]$m) Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok { param([string]$m) Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Skip { param([string]$m) Write-Host "    [  ] $m" -ForegroundColor DarkGray }
function Write-Warn { param([string]$m) Write-Host "    [!!] $m" -ForegroundColor Yellow }

# --- 路径 -------------------------------------------------------------------
$templateDir = Join-Path $HOME '.config\matugen\templates'
$cacheDir = Join-Path $HOME '.cache\mucai-terminal'
$stageDir = Join-Path $cacheDir 'stage'
$snapDir = Join-Path $cacheDir 'last'

$starshipFile = Join-Path $HOME '.config\starship.toml'
$fastfetchFile = Join-Path $HOME '.config\fastfetch\config.jsonc'

# classic 模式用的 ANSI 16 色 = Linux 端 dms-colors.json 里的 dank16（dark）
$ClassicAnsi = [ordered]@{
    black        = '#121318'
    red          = '#FF7297'
    green        = '#7FFF94'
    yellow       = '#FFF972'
    blue         = '#9DAEF2'
    purple       = '#334479'
    cyan         = '#B5C4FF'
    white        = '#EFF3FF'
    brightBlack  = '#404248'
    brightRed    = '#FF9FB8'
    brightGreen  = '#A5FFB4'
    brightYellow = '#FFFBA5'
    brightBlue   = '#C0CCFF'
    brightPurple = '#CBD5FF'
    brightCyan   = '#DDE4FF'
    brightWhite  = '#F8FAFF'
}

# ---------------------------------------------------------------------------
# 找 Windows Terminal 的 settings.json
# ---------------------------------------------------------------------------
function Get-TerminalSettingsPaths {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    return @($cands | Where-Object { Test-Path -LiteralPath $_ })
}

$settingsTargets = if ($SettingsPath) { @($SettingsPath) } else { Get-TerminalSettingsPaths }
if ($settingsTargets.Count -eq 0) { throw '没有找到 Windows Terminal 的 settings.json（可用 -SettingsPath 指定）' }

# ---------------------------------------------------------------------------
# 壁纸
# ---------------------------------------------------------------------------
function Get-CurrentWallpaperText {
    try {
        $w = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -ErrorAction Stop).Wallpaper
        if ($w) { return $w }
    }
    catch { }
    $transcoded = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
    if (Test-Path $transcoded) { return $transcoded }
    return ''
}

function Resolve-Wallpaper {
    if ($Wallpaper) {
        if (-not (Test-Path -LiteralPath $Wallpaper)) { throw "壁纸不存在：$Wallpaper" }
        return (Resolve-Path -LiteralPath $Wallpaper).Path
    }
    $w = Get-CurrentWallpaperText
    if (-not $w) { throw '读不到当前壁纸，请用 -Wallpaper 显式指定' }
    if (-not (Test-Path -LiteralPath $w)) { throw "注册表里的壁纸路径不存在：$w（用 -Wallpaper 指定）" }
    return (Resolve-Path -LiteralPath $w).Path
}

# ---------------------------------------------------------------------------
# 快照 / 回滚
# ---------------------------------------------------------------------------
function Get-SnapshotItems {
    $items = @(
        @{ Name = 'starship.toml'; Path = $starshipFile },
        @{ Name = 'fastfetch-config.jsonc'; Path = $fastfetchFile }
    )
    $i = 0
    foreach ($s in $settingsTargets) { $items += @{ Name = "settings-$i.json"; Path = $s }; $i++ }
    return $items
}

function Save-Snapshot {
    Remove-Item $snapDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $snapDir | Out-Null
    foreach ($it in Get-SnapshotItems) {
        if (Test-Path -LiteralPath $it.Path) {
            Copy-Item -LiteralPath $it.Path -Destination (Join-Path $snapDir $it.Name) -Force
        }
    }
    Set-Content -Path (Join-Path $snapDir 'wallpaper.txt') -Value (Get-CurrentWallpaperText) -Encoding utf8
    Write-Ok "已快照当前状态 -> $snapDir"
}

function Restore-Snapshot {
    if (-not (Test-Path $snapDir)) {
        Write-Warn "没有找到快照（$snapDir），无法回滚"
        Write-Host '    想恢复到"安装脚本刚装完"的样子，请重跑 Install-MucaiTerminal.ps1。' -ForegroundColor DarkGray
        return $false
    }
    Write-Step '回滚到上一次生成之前'
    $n = 0
    foreach ($it in Get-SnapshotItems) {
        $src = Join-Path $snapDir $it.Name
        if (Test-Path -LiteralPath $src) {
            if ($DryRun) { Write-Ok "[DryRun] 会恢复 $($it.Path)"; continue }
            $dir = Split-Path -Parent $it.Path
            if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            Copy-Item -LiteralPath $src -Destination $it.Path -Force
            Write-Ok "已恢复 $($it.Path)"
            $n++
        }
    }
    if (-not $DryRun) {
        $w = Join-Path $snapDir 'wallpaper.txt'
        if (Test-Path $w) { Write-Host "    （快照对应的壁纸：$((Get-Content $w -Raw).Trim())）" -ForegroundColor DarkGray }
    }
    if ($n -eq 0 -and -not $DryRun) { Write-Warn '快照里没有可恢复的文件' }
    return $true
}

# ---------------------------------------------------------------------------
# 生成：写一份"输出到暂存目录"的 matugen 配置，避免半途写坏线上文件
# ---------------------------------------------------------------------------
function New-StageConfigM3 {
    $slash = { param($p) $p -replace '\\', '/' }
    $cfg = @"
[config]
caching = false

[templates.starship]
input_path = '$(& $slash (Join-Path $templateDir 'starship-colors.toml'))'
output_path = '$(& $slash (Join-Path $stageDir 'starship.toml'))'

[templates.fastfetch]
input_path = '$(& $slash (Join-Path $templateDir 'fastfetch-config.jsonc'))'
output_path = '$(& $slash (Join-Path $stageDir 'fastfetch-config.jsonc'))'

[templates.wt-colors]
input_path = '$(& $slash (Join-Path $templateDir 'windows-terminal-colors.txt'))'
output_path = '$(& $slash (Join-Path $stageDir 'wt-colors.txt'))'

[templates.source-color]
input_path = '$(& $slash (Join-Path $templateDir 'source-color.txt'))'
output_path = '$(& $slash (Join-Path $stageDir 'source-color.txt'))'
"@

    # opencode 主题（只在装了 opencode 且模板存在时才生成）
    if ((Test-Path (Join-Path $templateDir 'opencode-theme.json')) -and (Test-Path (Join-Path $HOME '.config\opencode'))) {
        $cfg += @"

[templates.opencode]
input_path = '$(& $slash (Join-Path $templateDir 'opencode-theme.json'))'
output_path = '$(& $slash (Join-Path $stageDir 'opencode-theme.json'))'
"@
    }

    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    $path = Join-Path $stageDir 'config-m3.toml'
    Set-Content -Path $path -Value $cfg -Encoding utf8
    return $path
}

# 第二趟：base16 必须用 `color hex <源色>` 生成。
# 实测 matugen 的 base16（wal 后端）在 image 模式下会去用图片自身的取色集，
# 产出近黑的垃圾值（base08 = #000004），不能用于 image 模式。
function New-StageConfigAnsi {
    $slash = { param($p) $p -replace '\\', '/' }
    $cfg = @"
[config]
caching = false

[templates.wt-ansi]
input_path = '$(& $slash (Join-Path $templateDir 'windows-terminal-ansi.txt'))'
output_path = '$(& $slash (Join-Path $stageDir 'wt-ansi.txt'))'
"@
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    $path = Join-Path $stageDir 'config-ansi.toml'
    Set-Content -Path $path -Value $cfg -Encoding utf8
    return $path
}

function Read-ColorFile {
    param([string]$Path)
    $h = @{}
    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^\s*([A-Za-z]+)\s*=\s*(#[0-9A-Fa-f]{6})\s*$') { $h[$Matches[1]] = $Matches[2] }
    }
    return $h
}

# ---------------------------------------------------------------------------
# 合并进 Windows Terminal settings.json（与 Install-MucaiTerminal 同一套逻辑）
# ---------------------------------------------------------------------------
function ConvertFrom-JsoncText {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    $inStr = $false; $esc = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inStr) {
            [void]$sb.Append($c)
            if ($esc) { $esc = $false }
            elseif ($c -eq '\') { $esc = $true }
            elseif ($c -eq '"') { $inStr = $false }
            continue
        }
        if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c); continue }
        if ($c -eq '/' -and ($i + 1) -lt $Text.Length) {
            $n = $Text[$i + 1]
            if ($n -eq '/') { while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }; [void]$sb.Append("`n"); continue }
            if ($n -eq '*') {
                $i += 2
                while (($i + 1) -lt $Text.Length -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
                $i++; continue
            }
        }
        [void]$sb.Append($c)
    }
    return [regex]::Replace($sb.ToString(), ',(\s*[}\]])', '$1')
}

function Set-JsonProp {
    param($Object, [string]$Name, $Value)
    if (@($Object.PSObject.Properties.Name) -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Get-WtSchemeJson {
    param([hashtable]$Colors)
    return [ordered]@{
        name                = 'Mucai'
        background          = $Colors['background']
        foreground          = $Colors['foreground']
        cursorColor         = $Colors['cursorColor']
        selectionBackground = $Colors['selectionBackground']
        black               = $Colors['black']
        red                 = $Colors['red']
        green               = $Colors['green']
        yellow              = $Colors['yellow']
        blue                = $Colors['blue']
        purple              = $Colors['purple']
        cyan                = $Colors['cyan']
        white               = $Colors['white']
        brightBlack         = $Colors['brightBlack']
        brightRed           = $Colors['brightRed']
        brightGreen         = $Colors['brightGreen']
        brightYellow        = $Colors['brightYellow']
        brightBlue          = $Colors['brightBlue']
        brightPurple        = $Colors['brightPurple']
        brightCyan          = $Colors['brightCyan']
        brightWhite         = $Colors['brightWhite']
    }
}

function Merge-WtColors {
    param([string]$Path, [hashtable]$Colors)

    $raw = [System.IO.File]::ReadAllText($Path)
    $hasBom = ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF)
    if ($hasBom) { $raw = $raw.Substring(1) }
    try { $s = $raw | ConvertFrom-Json } catch { $s = (ConvertFrom-JsoncText $raw) | ConvertFrom-Json }

    $before = $s | ConvertTo-Json -Depth 32

    # 旧名字（改名前叫 DankMaterialShell）的方案一并清掉，否则设置界面里会残留一个孤儿
    $legacyNames = @('DankMaterialShell')
    $others = @($s.schemes | Where-Object { $_ -and $_.name -ne 'Mucai' -and $legacyNames -notcontains $_.name })
    Set-JsonProp $s 'schemes' (@((Get-WtSchemeJson -Colors $Colors)) + $others)

    $theme = [ordered]@{
        name   = 'Mucai'
        tab    = [ordered]@{ background = $Colors['tabActive']; unfocusedBackground = $Colors['tabRow'] }
        tabRow = [ordered]@{ background = $Colors['tabRow']; unfocusedBackground = $Colors['tabRow'] }
        window = [ordered]@{ applicationTheme = 'dark'; useMica = $false }
    }
    $otherThemes = @($s.themes | Where-Object { $_ -and $_.name -ne 'Mucai' -and $legacyNames -notcontains $_.name })
    Set-JsonProp $s 'themes' (@($theme) + $otherThemes)
    Set-JsonProp $s 'theme' 'Mucai'

    $after = $s | ConvertTo-Json -Depth 32
    if ($before -eq $after) { Write-Skip "$Path 无需修改"; return }

    if ($DryRun) { Write-Ok "[DryRun] 会更新 $Path"; return }

    $bak = "$Path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    [System.IO.File]::WriteAllText($Path, $after, (New-Object System.Text.UTF8Encoding($hasBom)))
    Write-Ok "已更新 $Path"
    Write-Ok "  备份 -> $bak"
}

# ===========================================================================
# 主流程
# ===========================================================================
Write-Host ''
Write-Host 'mucai-regen —— 用壁纸刷新整套终端配色' -ForegroundColor White

if ($Rollback) {
    if (-not (Restore-Snapshot)) { exit 1 }
    Write-Host ''
    Write-Host '回滚完成。Windows Terminal 里开个新标签页即可看到效果。' -ForegroundColor Green
    exit 0
}

Write-Step '1/5 环境检查'
if (-not (Test-Path -LiteralPath $MatugenPath)) {
    throw "找不到 matugen：$MatugenPath`n    装法见 README（Rust GNU 工具链 + cargo install matugen）"
}
foreach ($t in @('starship-colors.toml', 'fastfetch-config.jsonc', 'windows-terminal-colors.txt')) {
    $p = Join-Path $templateDir $t
    if (-not (Test-Path -LiteralPath $p)) { throw "缺模板：$p`n    重跑 Install-MucaiTerminal.ps1 即可铺好" }
}
Write-Ok "matugen：$(& $MatugenPath --version)"
Write-Ok "模板目录：$templateDir"

Write-Step '2/5 确定壁纸'
$wall = Resolve-Wallpaper
Write-Ok "壁纸：$wall"
Write-Host "    种子策略：--prefer $Prefer" -ForegroundColor DarkGray

Write-Step '3/5 第一趟：从壁纸生成（提示符 / 面板 / 窗口外观 / 源色）'
$stageM3 = New-StageConfigM3
foreach ($f in @('starship.toml', 'fastfetch-config.jsonc', 'wt-colors.txt', 'source-color.txt')) {
    Remove-Item (Join-Path $stageDir $f) -Force -ErrorAction SilentlyContinue
}
$out1 = & $MatugenPath --config $stageM3 image $wall --prefer $Prefer 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'matugen 执行失败：'
    $out1 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    throw 'matugen 失败，已中止（你的配置没有被改动）'
}
foreach ($f in @('starship.toml', 'fastfetch-config.jsonc', 'wt-colors.txt', 'source-color.txt')) {
    if (-not (Test-Path (Join-Path $stageDir $f))) { throw "matugen 没有生成 $f，已中止" }
}
Write-Ok '提示符 / 信息面板 / 窗口外观 已生成'

Write-Step '4/5 第二趟：生成 16 个 ANSI 槽'
$ansiColors = @{}
if ($Ansi -eq 'classic') {
    Write-Skip 'classic 模式：用固定配色，不需要第二趟'
    foreach ($k in $ClassicAnsi.Keys) { $ansiColors[$k] = $ClassicAnsi[$k] }
}
else {
    $srcRaw = Get-Content -LiteralPath (Join-Path $stageDir 'source-color.txt') -Raw
    if ($srcRaw -notmatch '(#[0-9A-Fa-f]{6})') { throw "拿不到源色，已中止（source-color.txt 内容：$srcRaw）" }
    $srcColor = $Matches[1]
    Write-Ok "被选中的源色：$srcColor"
    $stageAnsi = New-StageConfigAnsi
    Remove-Item (Join-Path $stageDir 'wt-ansi.txt') -Force -ErrorAction SilentlyContinue
    $out2 = & $MatugenPath -b wal --config $stageAnsi color hex $srcColor 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'matugen（base16 那一趟）执行失败：'
        $out2 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
        throw 'matugen 失败，已中止（你的配置没有被改动）'
    }
    $ansiColors = Read-ColorFile (Join-Path $stageDir 'wt-ansi.txt')
    Write-Ok 'ANSI 16 色：base16（随壁纸走）'
}

$chrome = Read-ColorFile (Join-Path $stageDir 'wt-colors.txt')
$colors = [ordered]@{}
foreach ($k in $chrome.Keys) { $colors[$k] = $chrome[$k] }
foreach ($k in $ansiColors.Keys) { $colors[$k] = $ansiColors[$k] }
if ($colors.Count -lt 22) { throw "配色解析不完整，只拿到 $($colors.Count) 个（应为 22 个）" }

Write-Host ''
Write-Host '    新配色预览：' -ForegroundColor DarkGray
Write-Host ("      背景 {0}   前景 {1}   光标 {2}   选中 {3}" -f $colors['background'], $colors['foreground'], $colors['cursorColor'], $colors['selectionBackground']) -ForegroundColor DarkGray
Write-Host ("      黑 {0}  红 {1}  绿 {2}  黄 {3}" -f $colors['black'], $colors['red'], $colors['green'], $colors['yellow']) -ForegroundColor DarkGray
Write-Host ("      蓝 {0}  紫 {1}  青 {2}  白 {3}" -f $colors['blue'], $colors['purple'], $colors['cyan'], $colors['white']) -ForegroundColor DarkGray
Write-Host ("      亮黑 {0}   活动标签 {1}" -f $colors['brightBlack'], $colors['tabActive']) -ForegroundColor DarkGray

if ($DryRun) {
    Write-Step '5/5 应用（-DryRun 跳过）'
    Write-Skip '暂存目录里的产物保留着，可以去 %USERPROFILE%\.cache\mucai-terminal\stage\ 看'
    Write-Host ''
    Write-Host '这是 -DryRun，线上文件一个都没动。' -ForegroundColor Yellow
    exit 0
}

Write-Step '5/5 快照当前状态，然后落盘'
Save-Snapshot
Copy-Item -LiteralPath (Join-Path $stageDir 'starship.toml') -Destination $starshipFile -Force
Write-Ok "已更新 $starshipFile"
$ffDir = Split-Path -Parent $fastfetchFile
if (-not (Test-Path $ffDir)) { New-Item -ItemType Directory -Force -Path $ffDir | Out-Null }
Copy-Item -LiteralPath (Join-Path $stageDir 'fastfetch-config.jsonc') -Destination $fastfetchFile -Force
Write-Ok "已更新 $fastfetchFile"

# --- opencode 主题 ---
$ocTheme = Join-Path $stageDir 'opencode-theme.json'
if (Test-Path $ocTheme) {
    $ocThemesDir = Join-Path $HOME '.config\opencode\themes'
    New-Item -ItemType Directory -Force -Path $ocThemesDir | Out-Null
    $ocTarget = Join-Path $ocThemesDir 'matugen.json'
    Copy-Item -LiteralPath $ocTheme -Destination $ocTarget -Force
    Write-Ok "已更新 $ocTarget"

    # 选中状态在 opencode 自己的 kv.json 里；opencode 正在运行时写了会被它退出时覆盖
    $kvPath = Join-Path $HOME '.local\state\opencode\kv.json'
    if (Get-Process -Name opencode -ErrorAction SilentlyContinue) {
        Write-Warn 'opencode 正在运行 —— 主题文件已更新，但选中状态要退出它之后再设'
        Write-Warn '  （或在 opencode 里用 /theme 选 matugen）'
    }
    else {
        $kvObj = [ordered]@{}
        if (Test-Path $kvPath) {
            try {
                $existing = Get-Content $kvPath -Raw | ConvertFrom-Json
                foreach ($p in $existing.PSObject.Properties) { $kvObj[$p.Name] = $p.Value }
                Copy-Item -LiteralPath $kvPath -Destination "$kvPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
            }
            catch { Write-Warn 'kv.json 解析失败，跳过主题选中设置（在 opencode 里 /theme 选一次即可）' }
        }
        if ($kvObj['theme'] -ne 'matugen') {
            $kvObj['theme'] = 'matugen'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $kvPath) | Out-Null
            [System.IO.File]::WriteAllText($kvPath, ($kvObj | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
            Write-Ok "已把 opencode 主题设为 matugen（重启 opencode 生效）"
        }
        else { Write-Skip 'opencode 主题已经是 matugen' }
    }
}
else { Write-Skip '没装 opencode（或不需要），跳过它的主题' }

foreach ($t in $settingsTargets) { Merge-WtColors -Path $t -Colors $colors }

Write-Host ''
Write-Host '完成。Windows Terminal 会热重载，开个新标签页就是新配色。' -ForegroundColor Green
Write-Host '想退回上一次：mucai-regen -Rollback' -ForegroundColor DarkGray
