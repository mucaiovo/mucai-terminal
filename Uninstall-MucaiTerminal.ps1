#Requires -Version 5.1
<#
.SYNOPSIS
    回滚 / 卸载 Install-MucaiTerminal.ps1 与 mucai-regen 造成的改动。

.DESCRIPTION
    默认动作是"安全回滚"，不会碰你装的命令行工具，也不会碰你自己的终端设置：

      1. 从 Windows Terminal settings.json 里移除 Mucai 配色方案与主题，
         并把 theme / colorScheme 复位（你的其他配色方案、快捷键、profile 一律不动）
      2. 去掉 PowerShell profile 上的 -NoLogo（恢复启动横幅）
      3. 删除 ~/.config/matugen/（matugen 的模板与配置）
      4. 删除 ~/.local/bin/mucai-regen.ps1
      5. 删除 ~/.cache/mucai-terminal/（快照与暂存产物）
      6. 从 PowerShell profile 里移除 mucai-regen 函数（只删标记块，其余内容不动）

    可选参数可以把回滚做得更彻底，见下面。

.PARAMETER RestoreSettings
    不用"精准移除"，而是整份恢复 Windows Terminal 的 settings.json。
    默认挑**最旧**的那份 *.bak-*（也就是这套配置第一次改动之前的原始状态）。
    会先把所有备份列出来。

.PARAMETER RestoreFrom
    指定要恢复的某一份备份（配合 -RestoreSettings 使用）。

.PARAMETER RemoveTools
    额外用 winget 卸载 starship / zoxide / eza / bat / yazi / fastfetch。
    （默认不卸 —— 这些工具你自己也可能在用。）

.PARAMETER RemoveMatugen
    额外删除 ~/.local/bin/matugen.exe。

.PARAMETER DryRun
    只打印会做什么，不写任何文件、不删任何东西。

.EXAMPLE
    pwsh -NoProfile -File .\Uninstall-MucaiTerminal.ps1 -DryRun
    先看看会删什么、改什么。

.EXAMPLE
    pwsh -NoProfile -File .\Uninstall-MucaiTerminal.ps1
    安全回滚：移除配色方案与主题，删掉 matugen 那套，保留工具。

.EXAMPLE
    pwsh -NoProfile -File .\Uninstall-MucaiTerminal.ps1 -RestoreSettings -RemoveTools -RemoveMatugen
    最彻底的回滚。
#>
[CmdletBinding()]
param(
    [switch]$RestoreSettings,
    [string]$RestoreFrom,
    [switch]$RemoveTools,
    [switch]$RemoveMatugen,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

function Write-Step { param([string]$m) Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok { param([string]$m) Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Skip { param([string]$m) Write-Host "    [  ] $m" -ForegroundColor DarkGray }
function Write-Warn { param([string]$m) Write-Host "    [!!] $m" -ForegroundColor Yellow }

$markerBegin = '# >>> mucai-terminal'
$markerEnd = '# <<< mucai-terminal'

function Remove-PathSafely {
    param([string]$Path, [string]$What)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Skip "$What 不存在，跳过"; return }
    if ($DryRun) { Write-Ok "[DryRun] 会删除 $Path"; return }
    Remove-Item -LiteralPath $Path -Recurse -Force
    Write-Ok "已删除 $Path"
}

function Get-TerminalSettingsPaths {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    return @($cands | Where-Object { Test-Path -LiteralPath $_ })
}

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

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Uninstall-MucaiTerminal —— 回滚这套终端配置' -ForegroundColor White

$settingsTargets = Get-TerminalSettingsPaths

# ===========================================================================
# 1. Windows Terminal settings.json
# ===========================================================================
Write-Step '1/6 Windows Terminal 设置'

if ($settingsTargets.Count -eq 0) {
    Write-Warn '没有找到 Windows Terminal 的 settings.json'
}
elseif ($RestoreSettings) {
    foreach ($t in $settingsTargets) {
        $backups = @(Get-ChildItem (Split-Path -Parent $t) -Filter ((Split-Path -Leaf $t) + '.bak-*') -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime)
        if ($backups.Count -eq 0) { Write-Warn "$t 没有备份可恢复"; continue }
        Write-Host '    可用的备份：' -ForegroundColor DarkGray
        foreach ($b in $backups) { Write-Host ("      {0}  {1}" -f $b.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $b.Name) -ForegroundColor DarkGray }

        $pick = if ($RestoreFrom) { $backups | Where-Object { $_.FullName -eq $RestoreFrom -or $_.Name -eq $RestoreFrom } | Select-Object -First 1 }
        else { $backups | Select-Object -First 1 }   # 最旧的一份 = 这套配置动手之前的状态
        if (-not $pick) { Write-Warn "找不到指定的备份：$RestoreFrom"; continue }

        if ($DryRun) { Write-Ok "[DryRun] 会用 $($pick.Name) 恢复 $t"; continue }
        Copy-Item -LiteralPath $t -Destination "$t.bak-uninstall-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
        Copy-Item -LiteralPath $pick.FullName -Destination $t -Force
        Write-Ok "已用 $($pick.Name) 恢复 $t"
    }
}
else {
    foreach ($t in $settingsTargets) {
        $raw = [System.IO.File]::ReadAllText($t)
        $hasBom = ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF)
        if ($hasBom) { $raw = $raw.Substring(1) }
        try { $s = $raw | ConvertFrom-Json } catch { $s = (ConvertFrom-JsoncText $raw) | ConvertFrom-Json }

        $before = $s | ConvertTo-Json -Depth 32
        $notes = @()

        # 把新名和旧名都清掉 —— 旧名 DankMaterialShell 是改名之前用的
        $drop = @('Mucai', 'DankMaterialShell')

        $schemes = @($s.schemes | Where-Object { $_ -and $drop -notcontains $_.name })
        if (@($s.schemes).Count -ne $schemes.Count) { Set-JsonProp $s 'schemes' $schemes; $notes += '移除配色方案 Mucai（含旧名）' }

        $themes = @($s.themes | Where-Object { $_ -and $drop -notcontains $_.name })
        if (@($s.themes).Count -ne $themes.Count) { Set-JsonProp $s 'themes' $themes; $notes += '移除主题 Mucai（含旧名）' }

        if ($drop -contains $s.theme) { Set-JsonProp $s 'theme' 'system'; $notes += 'theme 复位为 system' }

        if ($s.profiles -and $s.profiles.defaults -and ($drop -contains $s.profiles.defaults.colorScheme)) {
            $s.profiles.defaults.PSObject.Properties.Remove('colorScheme')
            $notes += 'defaults.colorScheme 已移除（回到 WT 默认配色）'
        }

        $hasPwshProfile = $false
        foreach ($p in @($s.profiles.list)) {
            if (-not $p -or -not $p.commandline) { continue }
            if ($p.commandline -match '(?i)-nologo') {
                $new = ($p.commandline -replace '(?i)\s*-nologo\b', '').Trim()
                Set-JsonProp $p 'commandline' $new
                $notes += "profile '$($p.name)' 去掉 -NoLogo"
            }
            if ($p.guid -eq '{574e775e-4f2a-5b96-ac1e-a2962a402336}' -or $p.source -eq 'Windows.Terminal.PowershellCore') { $hasPwshProfile = $true }
        }
        if ($hasPwshProfile -and $s.defaultProfile -eq '{574e775e-4f2a-5b96-ac1e-a2962a402336}') {
            $notes += '（defaultProfile 仍指向 PowerShell 7，未改动）'
        }

        $after = $s | ConvertTo-Json -Depth 32
        if ($before -eq $after) { Write-Skip "$t 没有本脚本留下的东西"; continue }

        if ($DryRun) {
            Write-Ok "[DryRun] 会更新 $t"
            foreach ($n in $notes) { Write-Host "        - $n" -ForegroundColor DarkGray }
            continue
        }
        $bak = "$t.bak-uninstall-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $t -Destination $bak -Force
        [System.IO.File]::WriteAllText($t, $after, (New-Object System.Text.UTF8Encoding($hasBom)))
        Write-Ok "已更新 $t"
        Write-Ok "  备份 -> $bak"
        foreach ($n in $notes) { Write-Host "        - $n" -ForegroundColor DarkGray }
    }
}

# ===========================================================================
# 2-6. 文件与 profile
# ===========================================================================
Write-Step '2/6 matugen 模板与配置'
Remove-PathSafely (Join-Path $HOME '.config\matugen') '~/.config/matugen'

# opencode 的主题文件（如果当初由 mucai-regen 生成过）
$ocTheme = Join-Path $HOME '.config\opencode\themes\matugen.json'
if (Test-Path $ocTheme) {
    Remove-PathSafely $ocTheme 'opencode 的 matugen 主题'
    Write-Skip '  （opencode 里如果还在用 matugen 主题，进去用 /theme 换回默认即可）'
}
else { Write-Skip 'opencode 主题文件不存在，跳过' }

Write-Step '3/6 mucai-regen 命令'
Remove-PathSafely (Join-Path $HOME '.local\bin\mucai-regen.ps1') 'mucai-regen.ps1'
if ($RemoveMatugen) { Remove-PathSafely (Join-Path $HOME '.local\bin\matugen.exe') 'matugen.exe' }
else { Write-Skip 'matugen.exe 保留（要删加 -RemoveMatugen）' }

Write-Step '4/6 配色快照与暂存'
Remove-PathSafely (Join-Path $HOME '.cache\mucai-terminal') '~/.cache/mucai-terminal'

Write-Step '5/6 PowerShell profile 里的 mucai-regen 函数'
$docs = [Environment]::GetFolderPath('MyDocuments')
$profilePaths = @(
    (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
)
foreach ($p in $profilePaths) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Skip "$p 不存在"; continue }
    $text = [System.IO.File]::ReadAllText($p)
    if ($text -notmatch [regex]::Escape($markerBegin)) { Write-Skip "$p 里没有本脚本的标记块"; continue }

    $lines = $text -split "`r`n|`n"
    $out = New-Object System.Collections.Generic.List[string]
    $skipping = $false
    $removed = 0
    foreach ($line in $lines) {
        if ($line.Trim() -eq $markerBegin) { $skipping = $true; $removed++; continue }
        if ($line.Trim() -eq $markerEnd) { $skipping = $false; continue }
        if (-not $skipping) { $out.Add($line) }
    }
    if ($DryRun) { Write-Ok "[DryRun] 会从 $p 移除标记块（$removed 行起）"; continue }
    $bak = "$p.bak-uninstall-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $p -Destination $bak -Force
    [System.IO.File]::WriteAllText($p, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    Write-Ok "已从 $p 移除（备份 -> $bak）"
}

Write-Step '6/6 命令行工具'
if (-not $RemoveTools) {
    Write-Skip 'starship / zoxide / eza / bat / yazi / fastfetch 保留（要卸加 -RemoveTools）'
}
else {
    $tools = @('Starship.Starship', 'ajeetdsouza.zoxide', 'eza-community.eza', 'sharkdp.bat', 'sxyazi.yazi', 'Fastfetch-cli.Fastfetch')
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Warn '找不到 winget，跳过' }
    else {
        foreach ($id in $tools) {
            if ($DryRun) { Write-Ok "[DryRun] 会卸载 $id"; continue }
            winget uninstall --id $id -e --disable-interactivity --accept-source-agreements | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Ok "已卸载 $id" } else { Write-Warn "$id 卸载返回 $LASTEXITCODE（可能本来就没装）" }
        }
    }
}

Write-Host ''
if ($DryRun) { Write-Host '这是 -DryRun，什么都没有改动。' -ForegroundColor Yellow }
else {
    Write-Host '回滚完成。Windows Terminal 里开个新标签页即可看到效果。' -ForegroundColor Green
    Write-Host '想连外观设置（字体/字号/透明度等）一起恢复，用 -RestoreSettings 整份还原 settings.json。' -ForegroundColor DarkGray
}
