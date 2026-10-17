#Requires -Version 5.1
<#
.SYNOPSIS
    把慕彩的终端美化方案（Arch + kitty + fish 那一套设计）落到 Windows 上。

.DESCRIPTION
    分四步，可重复执行，每一步都可以单独跳过：

      1. 用 winget 装齐依赖
         PowerShell 7 / Windows Terminal / starship / zoxide / eza / bat / yazi /
         fastfetch / JetBrainsMono Nerd Font
      2. 写配置文件
         ~/.config/starship.toml、~/.config/fastfetch/config.jsonc
      3. 写 PowerShell profile（提示符 / 别名 / 函数 / 启动画面）
      4. 合并 Windows Terminal 的 settings.json
         配色方案 Mucai、主题（标签行配色）、字体、内边距、
         透明度、光标形状、-NoLogo

    规则：
      * 任何被覆盖的文件都会先备份成 <原名>.bak-yyyyMMdd-HHmmss
      * 内容没变化的文件不会重写、也不会产生备份
      * 不会覆盖你没被本脚本管理的设置（defaultProfile 除外，见下）

.PARAMETER FontSize
    Windows Terminal 字号，默认 11。Linux 端用的是 10.0，想要严格一致就传 -FontSize 10。

.PARAMETER SkipTools
    跳过第 1 步（不装任何东西），只写配置。

.PARAMETER SkipFont
    跳过字体检测与安装。此时不会改动 settings.json 里的 font.face。

.PARAMETER NoBanner
    不要在开新终端时显示 fastfetch 信息面板。

.PARAMETER SkipLegacyProfile
    只写 PowerShell 7 的 profile，不动 Windows PowerShell 5.1 的。

.PARAMETER TerminalSettingsPath
    手动指定 Windows Terminal 的 settings.json 路径（便携版 / 非默认安装时用）。

.PARAMETER DryRun
    只打印将要做什么，不写任何文件。

.EXAMPLE
    pwsh -NoProfile -File .\Install-MucaiTerminal.ps1
    在全新机器上装齐依赖并套用配置。

.EXAMPLE
    pwsh -NoProfile -File .\Install-MucaiTerminal.ps1 -SkipTools -FontSize 10 -DryRun
    先看看在已经装好工具的机器上会改哪些东西。

.NOTES
    本文件由 _build/inject.py 从模板生成，配置文件内容是从真实文件注入的，
    请勿手工编辑 payload 区；要改逻辑请改 _build/Install-MucaiTerminal.template.ps1 后重新注入。
#>
[CmdletBinding()]
param(
    [int]$FontSize = 11,
    [switch]$SkipTools,
    [switch]$SkipFont,
    [switch]$NoBanner,
    [switch]$SkipLegacyProfile,
    [switch]$ForceBaseConfig,
    [string]$TerminalSettingsPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# ===========================================================================
# 输出小工具
# ===========================================================================
function Write-Step { param([string]$m) Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Skip { param([string]$m) Write-Host "    [  ] $m" -ForegroundColor DarkGray }
function Write-Warn { param([string]$m) Write-Host "    [!!] $m" -ForegroundColor Yellow }

$script:Changed = @()

function Update-SessionPath {
    $m = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = (@($m, $u) | Where-Object { $_ }) -join ';'
}

# 写文件：内容相同则跳过；不同则先备份再写
function Save-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$Bom
    )

    $same = $false
    if (Test-Path -LiteralPath $Path) {
        $old = [System.IO.File]::ReadAllText($Path)
        if ($old.Length -gt 0 -and $old[0] -eq [char]0xFEFF) { $old = $old.Substring(1) }
        if ($old.Replace("`r`n", "`n") -eq $Content.Replace("`r`n", "`n")) { $same = $true }
    }

    if ($same) { Write-Skip "$Path 已是最新，跳过"; return }
    if ($DryRun) { Write-Ok "[DryRun] 会写 $Path"; $script:Changed += $Path; return }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    if (Test-Path -LiteralPath $Path) {
        $bak = "$Path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $Path -Destination $bak -Force
        Write-Ok "已备份 -> $bak"
    }

    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($Bom.IsPresent)))
    Write-Ok "已写入 $Path"
    $script:Changed += $Path
}

# ===========================================================================
# 要落盘的配置内容（由 _build/inject.py 从真实文件注入）
# ===========================================================================
$StarshipToml = @'
#__PAYLOAD_STARSHIP_TOML__
'@

$FastfetchConfig = @'
#__PAYLOAD_FASTFETCH_CONFIG__
'@

$ProfileHead = @'
#__PAYLOAD_PROFILE_HEAD__
'@

$ProfileBanner = @'
#__PAYLOAD_PROFILE_BANNER__
'@

# --- matugen 那一套：刷配色用的命令、matugen 配置与全部模板、以及回滚脚本 ---
$MucaiRegenScript = @'
#__PAYLOAD_MUCAI_REGEN__
'@

$UninstallScript = @'
#__PAYLOAD_UNINSTALL__
'@

$UpdateMatugenScript = @'
#__PAYLOAD_UPDATE_MATUGEN__
'@

$MatugenConfigToml = @'
#__PAYLOAD_MATUGEN_CONFIG__
'@

$TplStarship = @'
#__PAYLOAD_TPL_STARSHIP__
'@

$TplFastfetch = @'
#__PAYLOAD_TPL_FASTFETCH__
'@

$TplWtColors = @'
#__PAYLOAD_TPL_WTCOLORS__
'@

$TplWtAnsi = @'
#__PAYLOAD_TPL_WTANSI__
'@

$TplSourceColor = @'
#__PAYLOAD_TPL_SOURCECOLOR__
'@

$TplOpencode = @'
#__PAYLOAD_TPL_OPENCODE__
'@

# 内置的 matugen.exe（gzip + base64）。没有这块就跳过，不影响其他部署。
$MatugenBlob = @'
#__PAYLOAD_MATUGEN_BLOB__
'@

# 单引号 here-string 的取值 = 两个标记行之间的原文，结尾那个换行符不计入。
# 所以这里直接拼接就能逐字节还原源文件，不需要额外补换行。
$ProfileText = $ProfileHead + $ProfileBanner
if ($NoBanner) { $ProfileText = $ProfileHead }

# ===========================================================================
# 1. 依赖
# ===========================================================================
Write-Step '1/4 检查并安装依赖工具'

$tools = @(
    @{ Id = 'Microsoft.PowerShell';      Name = 'PowerShell 7';      Cmd = 'pwsh' }
    @{ Id = 'Microsoft.WindowsTerminal'; Name = 'Windows Terminal';  Cmd = 'wt' }
    @{ Id = 'Starship.Starship';         Name = 'starship';          Cmd = 'starship' }
    @{ Id = 'ajeetdsouza.zoxide';        Name = 'zoxide';            Cmd = 'zoxide' }
    @{ Id = 'eza-community.eza';         Name = 'eza';               Cmd = 'eza' }
    @{ Id = 'sharkdp.bat';               Name = 'bat';               Cmd = 'bat' }
    @{ Id = 'sxyazi.yazi';               Name = 'yazi';              Cmd = 'yazi' }
    @{ Id = 'Fastfetch-cli.Fastfetch';   Name = 'fastfetch';         Cmd = 'fastfetch' }
)

if ($SkipTools) {
    Write-Skip '-SkipTools：跳过依赖安装'
}
else {
    Update-SessionPath
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warn '找不到 winget（应用安装程序未安装），跳过依赖安装；配置文件照常写入。'
    }
    else {
        foreach ($t in $tools) {
            if (Get-Command $t.Cmd -ErrorAction SilentlyContinue) { Write-Skip "$($t.Name) 已安装"; continue }
            if ($DryRun) { Write-Ok "[DryRun] 会安装 $($t.Name)  ($($t.Id))"; continue }

            Write-Host "    -> winget install --id $($t.Id)" -ForegroundColor DarkGray
            winget install --id $t.Id -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -eq 0) { Write-Ok "$($t.Name) 安装完成" }
            else { Write-Warn "$($t.Name) 安装失败（winget 退出码 $LASTEXITCODE），继续" }
            Update-SessionPath
        }
    }
}

# ===========================================================================
# 2. 字体
# ===========================================================================
Write-Step '2/4 选择等宽 Nerd Font'

function Get-InstalledFontFamilies {
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        return @((New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name })
    }
    catch {
        # 退路：直接读字体注册表
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
            'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        )
        return @(foreach ($k in $keys) {
                (Get-ItemProperty $k -ErrorAction SilentlyContinue).PSObject.Properties |
                    Where-Object { $_.Name -notlike 'PS*' } |
                    ForEach-Object { $_.Name }
            })
    }
}

# 注意：Nerd Fonts v3 的族名是 "JetBrainsMono Nerd Font"，
# 而老版本/部分渠道装出来是 "JetBrainsMono NF"，所以两个都要认。
$fontCandidates = @(
    'JetBrainsMono NF', 'JetBrainsMono Nerd Font',
    'JetBrainsMono NFM', 'JetBrainsMono Nerd Font Mono',
    'CaskaydiaCove NF', 'CaskaydiaCove Nerd Font',
    'Hack NF', 'Hack Nerd Font',
    'FiraCode NF', 'FiraCode Nerd Font',
    'MesloLGS NF', 'MesloLGS Nerd Font'
)

$fontFace = $null
if ($SkipFont) {
    Write-Skip '-SkipFont：不改动字体设置'
}
else {
    $families = Get-InstalledFontFamilies
    foreach ($c in $fontCandidates) {
        if ($families -contains $c) { $fontFace = $c; break }
    }
    if (-not $fontFace) {
        $anyNerd = @($families | Where-Object { $_ -match 'Nerd ?Font' } | Sort-Object -Unique)
        if ($anyNerd.Count -gt 0) {
            $fontFace = $anyNerd[0]
            Write-Warn "没找到 JetBrainsMono Nerd Font，改用已装的 $fontFace"
        }
    }

    if ($fontFace) {
        Write-Ok "使用字体：$fontFace"
    }
    else {
        Write-Warn '系统里没有 Nerd Font，提示符的图标会变成方块。'
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget -and -not $DryRun) {
            winget install --id DEVCOM.JetBrainsMonoNerdFont -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -eq 0) {
                Write-Ok 'JetBrainsMono Nerd Font 安装完成'
                $families = Get-InstalledFontFamilies
                foreach ($c in $fontCandidates) { if ($families -contains $c) { $fontFace = $c; break } }
                if (-not $fontFace) { $fontFace = 'JetBrainsMono Nerd Font' }  # 该包提供的族名
                Write-Ok "使用字体：$fontFace"
            }
            else {
                Write-Warn "字体安装失败（winget 退出码 $LASTEXITCODE），保持原有字体设置"
            }
        }
        elseif ($DryRun) {
            Write-Ok '[DryRun] 会安装 JetBrainsMono Nerd Font (DEVCOM.JetBrainsMonoNerdFont)'
        }
        else {
            Write-Warn '没有 winget，跳过字体安装；保持原有字体设置'
        }
    }
}

# ===========================================================================
# 3. 配置文件
# ===========================================================================
Write-Step '3/4 写入 starship / fastfetch / PowerShell profile'

# 如果 matugen 已经接管这两个文件，就不要用固定配色覆盖它（否则"换了壁纸又被打回去"很难排查）
$matugenOwns = (Test-Path (Join-Path $HOME '.config\matugen\templates\starship-colors.toml')) -and (-not $ForceBaseConfig)
if ($matugenOwns) {
    Write-Skip 'matugen 已接管 starship.toml / fastfetch 配置，跳过不覆盖'
    Write-Skip '  （想强制恢复固定配色：重跑本脚本时加 -ForceBaseConfig）'
}
else {
    Save-TextFile -Path (Join-Path $HOME '.config\starship.toml') -Content $StarshipToml
    Save-TextFile -Path (Join-Path $HOME '.config\fastfetch\config.jsonc') -Content $FastfetchConfig
}

$docs = [Environment]::GetFolderPath('MyDocuments')
$profilePaths = @((Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'))
if (-not $SkipLegacyProfile) {
    $profilePaths += (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
}
foreach ($p in $profilePaths) {
    # BOM：让 Windows PowerShell 5.1 也能正确读中文
    Save-TextFile -Path $p -Content $ProfileText -Bom
}

# --- matugen 那一套：模板、配置、mucai-regen 命令、回滚脚本 ---
Write-Host '    -- matugen / 换配色命令 --' -ForegroundColor DarkGray
$matugenDir = Join-Path $HOME '.config\matugen'
$matugenTplDir = Join-Path $matugenDir 'templates'
Save-TextFile -Path (Join-Path $matugenDir 'config.toml') -Content $MatugenConfigToml
Save-TextFile -Path (Join-Path $matugenTplDir 'starship-colors.toml') -Content $TplStarship
Save-TextFile -Path (Join-Path $matugenTplDir 'fastfetch-config.jsonc') -Content $TplFastfetch
Save-TextFile -Path (Join-Path $matugenTplDir 'windows-terminal-colors.txt') -Content $TplWtColors
Save-TextFile -Path (Join-Path $matugenTplDir 'windows-terminal-ansi.txt') -Content $TplWtAnsi
Save-TextFile -Path (Join-Path $matugenTplDir 'source-color.txt') -Content $TplSourceColor
Save-TextFile -Path (Join-Path $matugenTplDir 'opencode-theme.json') -Content $TplOpencode

$localBin = Join-Path $HOME '.local\bin'
Save-TextFile -Path (Join-Path $localBin 'mucai-regen.ps1') -Content $MucaiRegenScript
Save-TextFile -Path (Join-Path $localBin 'Uninstall-MucaiTerminal.ps1') -Content $UninstallScript
Save-TextFile -Path (Join-Path $localBin 'Update-Matugen.ps1') -Content $UpdateMatugenScript

# --- matugen.exe ---
# 优先用"脚本所在目录里的 matugen.exe"（升级时直接丢个新的在旁边，不用重新生成脚本），
# 没有的话就释放内置的那份（gzip+base64，装完这一步就不再需要 Rust 工具链了）。
$matugenTarget = Join-Path $localBin 'matugen.exe'
$embeddedVersion = '4.2.0'
$sidecar = $null
if ($PSScriptRoot) {
    $cand = Join-Path $PSScriptRoot 'matugen.exe'
    if (Test-Path $cand) { $sidecar = $cand }
}

if ($sidecar) {
    $same = $false
    if (Test-Path $matugenTarget) {
        $same = ((Get-FileHash $matugenTarget -Algorithm SHA256).Hash -eq (Get-FileHash $sidecar -Algorithm SHA256).Hash)
    }
    if ($same) { Write-Skip 'matugen.exe 与同目录那份一致，跳过' }
    elseif ($DryRun) { Write-Ok "[DryRun] 会用同目录的 matugen.exe 覆盖 $matugenTarget" }
    else {
        New-Item -ItemType Directory -Force -Path $localBin | Out-Null
        Copy-Item -LiteralPath $sidecar -Destination $matugenTarget -Force
        Write-Ok "已从同目录安装 matugen.exe（$(& $matugenTarget --version)）"
    }
}
elseif ($MatugenBlob -and $MatugenBlob.Length -gt 1000) {
    $current = $null
    if (Test-Path $matugenTarget) {
        try { $current = (& $matugenTarget --version 2>&1 | Select-Object -First 1) } catch { }
    }
    if ($current -match [regex]::Escape($embeddedVersion)) {
        Write-Skip "matugen.exe 已是 $embeddedVersion，跳过"
    }
    elseif ($DryRun) { Write-Ok "[DryRun] 会释放内置的 matugen $embeddedVersion 到 $matugenTarget" }
    else {
        New-Item -ItemType Directory -Force -Path $localBin | Out-Null
        $gzb = [Convert]::FromBase64String($MatugenBlob)
        $inMs = New-Object System.IO.MemoryStream(, $gzb)
        $outMs = New-Object System.IO.MemoryStream
        $dz = New-Object System.IO.Compression.GZipStream($inMs, [System.IO.Compression.CompressionMode]::Decompress)
        $dz.CopyTo($outMs)
        $dz.Close()
        [System.IO.File]::WriteAllBytes($matugenTarget, $outMs.ToArray())
        Write-Ok "已释放内置的 matugen $embeddedVersion -> $matugenTarget"
    }
}
else { Write-Skip '这个安装脚本没有内置 matugen.exe（构建时未包含），跳过' }

$matugenFound = [bool](Get-Command matugen -ErrorAction SilentlyContinue) -or
    (Test-Path (Join-Path $HOME '.local\bin\matugen.exe')) -or
    (Test-Path (Join-Path $HOME '.cargo\bin\matugen.exe'))
if ($matugenFound) {
    Write-Ok 'matugen 已就位，可以直接 mucai-regen 换配色'
}
else {
    Write-Warn 'matugen 还没装：按 README 的「让配色跟随壁纸」装好后，'
    Write-Warn '  把 matugen.exe 放到 ~/.local/bin 里，就可以把整个 Rust 工具链卸掉省空间'
}

# ===========================================================================
# 4. 合并 Windows Terminal settings.json
# ===========================================================================
Write-Step '4/4 合并 Windows Terminal 设置'

# Windows Terminal 的 settings.json 是 JSONC（允许注释和尾逗号）。
# PowerShell 7.4+ 的 ConvertFrom-Json 直接支持；更老的版本走这个清洗函数。
function ConvertFrom-JsoncText {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    $inStr = $false
    $esc = $false
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
            if ($n -eq '/') {                       # 行注释
                while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
                [void]$sb.Append("`n")
                continue
            }
            if ($n -eq '*') {                       # 块注释
                $i += 2
                while (($i + 1) -lt $Text.Length -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
                $i++
                continue
            }
        }
        [void]$sb.Append($c)
    }
    return [regex]::Replace($sb.ToString(), ',(\s*[}\]])', '$1')   # 去尾逗号
}

function Set-JsonProp {
    param($Object, [string]$Name, $Value)
    if (@($Object.PSObject.Properties.Name) -contains $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function Get-TerminalSettingsPaths {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    return @($cands | Where-Object { Test-Path -LiteralPath $_ })
}

function Update-TerminalSettingsFile {
    param([string]$Path, [string]$FontFace, [int]$FontSize, [bool]$UseAcrylic = $false, [switch]$SkipPalette)

    $raw = [System.IO.File]::ReadAllText($Path)
    $hasBom = ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF)
    if ($hasBom) { $raw = $raw.Substring(1) }

    try { $s = $raw | ConvertFrom-Json }
    catch { $s = (ConvertFrom-JsoncText $raw) | ConvertFrom-Json }

    $before = $s | ConvertTo-Json -Depth 32
    $notes = @()

    # --- 配色方案 + 主题：来自 kitty 的 dank-theme.conf / dank-tabs.conf ---
    # 如果 matugen 已经接管（mucai-regen 生成过配色），就不要用固定配色盖掉它；
    # 否则你换个壁纸、过阵子重跑安装脚本，配色又被打回去了。
    if ($SkipPalette) {
        $notes += '配色方案与主题交给 matugen 管理，未改动'
    }
    else {
        $scheme = [ordered]@{
        name                = 'Mucai'
        background          = '#121318'
        foreground          = '#E3E2E9'
        cursorColor         = '#B5C4FF'
        selectionBackground = '#C1C5DD'
        black               = '#121318'
        red                 = '#FF7297'
        green               = '#7FFF94'
        yellow              = '#FFF972'
        blue                = '#9DAEF2'
        purple              = '#334479'
        cyan                = '#B5C4FF'
        white               = '#EFF3FF'
        brightBlack         = '#404248'
        brightRed           = '#FF9FB8'
        brightGreen         = '#A5FFB4'
        brightYellow        = '#FFFBA5'
        brightBlue          = '#C0CCFF'
        brightPurple        = '#CBD5FF'
        brightCyan          = '#DDE4FF'
        brightWhite         = '#F8FAFF'
    }
    # 旧名字（改名前叫 DankMaterialShell）的方案一并清掉，否则设置界面里会残留一个孤儿
    $legacyNames = @('DankMaterialShell')
    $others = @($s.schemes | Where-Object { $_ -and $_.name -ne 'Mucai' -and $legacyNames -notcontains $_.name })
    Set-JsonProp $s 'schemes' (@($scheme) + $others)

    # --- 主题：来自 kitty 的 dank-tabs.conf（标签行/活动标签配色）---
    $theme = [ordered]@{
        name   = 'Mucai'
        tab    = [ordered]@{ background = '#B5C4FF'; unfocusedBackground = '#121318' }
        tabRow = [ordered]@{ background = '#121318'; unfocusedBackground = '#121318' }
        # useMica 必须为 false，否则半透明时底下会透出 Mica 材质
        window = [ordered]@{ applicationTheme = 'dark'; useMica = $false }
    }
    $otherThemes = @($s.themes | Where-Object { $_ -and $_.name -ne 'Mucai' -and $legacyNames -notcontains $_.name })
    Set-JsonProp $s 'themes' (@($theme) + $otherThemes)
    Set-JsonProp $s 'theme' 'Mucai'
    Set-JsonProp $s 'useAcrylicInTabRow' $false
    Set-JsonProp $s 'tabWidthMode' 'titleLength'   # 标签宽度跟随标题，接近 kitty
    }

    if (-not $s.profiles) { Write-Warn "$Path 里没有 profiles 段，跳过：$Path"; return }

    # --- profiles.defaults：来自 kitty.conf ---
    if (-not $s.profiles.defaults) { Set-JsonProp $s.profiles 'defaults' ([pscustomobject]@{}) }
    $d = $s.profiles.defaults

    # 字号 / builtinGlyphs 总是设置；-SkipFont 只表示「不动你已经选好的字体族」
    if (-not $d.font) { Set-JsonProp $d 'font' ([pscustomobject]@{}) }
    Set-JsonProp $d.font 'size' $FontSize
    Set-JsonProp $d.font 'builtinGlyphs' $true   # 让 WT 自己画 Powerline 符号（对应 kitty 的 narrow_symbols）
    if ($FontFace) { Set-JsonProp $d.font 'face' $FontFace }
    Set-JsonProp $d 'colorScheme' 'Mucai'
    Set-JsonProp $d 'padding' '5, 5, 5, 5'           # left, top, right, bottom（kitty window_padding_width 5）
    Set-JsonProp $d 'opacity' 80                        # kitty background_opacity 0.8
    # 无模糊的纯透明只在 Windows 11 生效（微软文档明确写了）；
    # Windows 10 上退回亚克力模糊，否则会变成完全不透明。
    Set-JsonProp $d 'useAcrylic' $UseAcrylic
    Set-JsonProp $d 'cursorShape' 'filledBox'           # kitty cursor_shape block
    Set-JsonProp $d 'cursorColor' '#B5C4FF'
    Set-JsonProp $d 'intenseTextStyle' 'bold'           # kitty 的粗体只换字形、不换亮色
    Set-JsonProp $d 'unfocusedAppearance' ([pscustomobject]@{ opacity = 80 })

    # --- 启动横幅：-NoLogo ---
    $pwshGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    $hasPwshProfile = $false
    foreach ($p in @($s.profiles.list)) {
        if (-not $p) { continue }
        $isPwsh = ($p.guid -eq $pwshGuid) -or ($p.source -eq 'Windows.Terminal.PowershellCore') -or ($p.commandline -match '(?i)\bpwsh(\.exe)?\b')
        $isWinPs = ($p.commandline -match '(?i)powershell\.exe')

        if ($isPwsh) {
            $hasPwshProfile = $true
            if ($p.commandline) {
                if ($p.commandline -notmatch '(?i)-nologo') {
                    Set-JsonProp $p 'commandline' ($p.commandline.Trim() + ' -NoLogo')
                    $notes += "profile '$($p.name)' 追加 -NoLogo"
                }
            }
            else {
                Set-JsonProp $p 'commandline' 'pwsh.exe -NoLogo'
                $notes += "profile '$($p.name)' 指定 pwsh.exe -NoLogo"
            }
        }
        elseif ($isWinPs -and $p.commandline -notmatch '(?i)-nologo') {
            Set-JsonProp $p 'commandline' ($p.commandline.Trim() + ' -NoLogo')
            $notes += "profile '$($p.name)' 追加 -NoLogo"
        }
    }

    # 默认启动 profile 指向 PowerShell 7
    if ($hasPwshProfile) { Set-JsonProp $s 'defaultProfile' $pwshGuid }

    $after = $s | ConvertTo-Json -Depth 32
    if ($before -eq $after) { Write-Skip "$Path 无需修改"; return }
    if ($DryRun) {
        Write-Ok "[DryRun] 会更新 $Path"
        foreach ($n in $notes) { Write-Ok "  - $n" }
        $script:Changed += $Path
        return
    }

    $bak = "$Path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    [System.IO.File]::WriteAllText($Path, $after, (New-Object System.Text.UTF8Encoding($hasBom)))
    Write-Ok "已更新 $Path"
    Write-Ok "  备份 -> $bak"
    foreach ($n in $notes) { Write-Ok "  - $n" }
    $script:Changed += $Path
}

$targets = @()
if ($TerminalSettingsPath) { $targets = @($TerminalSettingsPath) }
else { $targets = Get-TerminalSettingsPaths }

# 判断能不能用「无模糊透明」：Windows 11 = build 22000 以上
$buildNumber = 0
try {
    $buildNumber = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop).CurrentBuildNumber
}
catch { }
$useAcrylic = ($buildNumber -gt 0 -and $buildNumber -lt 22000)
if ($useAcrylic) {
    Write-Warn "系统是 Windows 10 (build $buildNumber)：无模糊透明不生效，改用亚克力模糊（仍是 80% 透明）"
}

if ($targets.Count -eq 0) {
    Write-Warn '没有找到 Windows Terminal 的 settings.json；装好 Windows Terminal 后重跑本脚本即可。'
}
else {
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t)) { Write-Warn "指定路径不存在：$t"; continue }
        Update-TerminalSettingsFile -Path $t -FontFace $fontFace -FontSize $FontSize -UseAcrylic $useAcrylic -SkipPalette:$matugenOwns
    }
}

# ===========================================================================
# 收尾
# ===========================================================================
Write-Step '完成'
if ($script:Changed.Count -gt 0) {
    foreach ($c in $script:Changed) { Write-Ok $c }
}
else {
    Write-Skip '没有任何文件需要改动'
}

Write-Host ''
Write-Host '接下来：' -ForegroundColor Cyan
Write-Host '  1. 关掉所有 Windows Terminal 窗口再打开（或在现有窗口里开一个新标签页）'
Write-Host '  2. 新装的命令行工具需要重开终端才能进 PATH'
Write-Host '  3. 提示符里的图标依赖 Nerd Font，请确认 Windows Terminal 用的是本脚本设置的字体'
if ($DryRun) { Write-Host ''; Write-Warn '这是 -DryRun，什么都没有写入。' }
