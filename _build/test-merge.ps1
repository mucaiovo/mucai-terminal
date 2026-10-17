#Requires -Version 5.1
<#
.SYNOPSIS
    Install-MucaiTerminal.ps1 的回归测试。

.DESCRIPTION
    把 _build/fixtures 里的 Windows Terminal settings.json 复制到临时文件，
    对副本执行合并，然后断言结果符合预期。不会碰真实的 settings.json。

    两个 fixture：
      fresh-machine.json   —— 全新机器：没有 schemes / themes，defaults 是空的
      current-machine.json —— 已配置过的机器：已有别的配色方案、4 个 profile、自定义快捷键

.EXAMPLE
    pwsh -NoProfile -File .\test-merge.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path (Split-Path -Parent $here) 'Install-MucaiTerminal.ps1'
$fixtures = Join-Path $here 'fixtures'

$pass = 0
$fail = 0

# 安装脚本用 Write-Host 输出（颜色），无法被调用方捕获；
# 所以用当前宿主另起一个进程来跑，这样既能拿到输出，也不会被它的日志刷屏。
$psExe = (Get-Process -Id $PID).Path

function Assert-Equal {
    param($Actual, $Expected, [string]$What)
    if ("$Actual" -eq "$Expected") {
        Write-Host "    [OK] $What" -ForegroundColor Green
        $script:pass++
    }
    else {
        Write-Host "    [XX] $What —— 期望 [$Expected]，实际 [$Actual]" -ForegroundColor Red
        $script:fail++
    }
}

foreach ($name in @('fresh-machine', 'current-machine')) {
    Write-Host ''
    Write-Host "==> $name" -ForegroundColor Cyan

    $src = Join-Path $fixtures "$name.json"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "mucai-test-$name.json"
    Copy-Item $src $tmp -Force

    # 记录原始状态，用来验证「不该动的东西没被动」
    $orig = Get-Content $tmp -Raw | ConvertFrom-Json
    $origFace = $orig.profiles.defaults.font.face
    $origSchemes = @($orig.schemes).Count
    $origProfiles = @($orig.profiles.list).Count
    $origKeys = @($orig.keybindings).Count

    $null = & $psExe -NoProfile -File $installer -SkipTools -SkipFont -SkipLegacyProfile -ForceBaseConfig -TerminalSettingsPath $tmp -FontSize 11 2>&1

    $j = Get-Content $tmp -Raw | ConvertFrom-Json

    Assert-Equal ($j.themes.Count) 1 'themes 里只加了一个主题'
    Assert-Equal ($j.themes[0].name) 'Mucai' '主题名'
    Assert-Equal ($j.themes[0].tab.background) '#B5C4FF' '活动标签底色'
    Assert-Equal ($j.themes[0].tabRow.background) '#121318' '标签行底色'
    Assert-Equal ($j.themes[0].window.useMica) 'False' 'useMica 必须为 false（否则半透明会透出 Mica）'
    Assert-Equal ($j.theme) 'Mucai' '启用的主题'
    Assert-Equal ($j.useAcrylicInTabRow) 'False' '标签行不用亚克力'
    Assert-Equal ($j.tabWidthMode) 'titleLength' '标签宽度模式'
    Assert-Equal ($j.defaultProfile) '{574e775e-4f2a-5b96-ac1e-a2962a402336}' '默认 profile 指向 PowerShell 7'

    $scheme = $j.schemes | Where-Object { $_.name -eq 'Mucai' }
    Assert-Equal ($scheme.background) '#121318' '配色方案背景'
    Assert-Equal ($scheme.foreground) '#E3E2E9' '配色方案前景'
    Assert-Equal ($scheme.cursorColor) '#B5C4FF' '光标颜色'
    Assert-Equal ($scheme.selectionBackground) '#C1C5DD' '选中背景'

    $d = $j.profiles.defaults
    Assert-Equal ($d.colorScheme) 'Mucai' 'defaults.colorScheme'
    Assert-Equal ($d.padding) '5, 5, 5, 5' 'defaults.padding'
    Assert-Equal ($d.opacity) '80' 'defaults.opacity'
    # 无模糊透明只在 Win11 生效；非 Win11 上脚本会退回亚克力，断言跟着系统走
    $buildNumber = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber).CurrentBuildNumber
    $expectAcrylic = if ($buildNumber -lt 22000) { 'True' } else { 'False' }
    Assert-Equal ($d.useAcrylic) $expectAcrylic "defaults.useAcrylic（build $buildNumber 下应为 $expectAcrylic）"
    Assert-Equal ($d.cursorShape) 'filledBox' 'defaults.cursorShape'
    Assert-Equal ($d.intenseTextStyle) 'bold' 'defaults.intenseTextStyle'
    Assert-Equal ($d.font.size) '11' 'defaults.font.size（跟随 -FontSize）'
    Assert-Equal ($d.font.builtinGlyphs) 'True' 'defaults.font.builtinGlyphs'
    Assert-Equal ($d.unfocusedAppearance.opacity) '80' '失焦时保持透明'

    # -SkipFont 时不应该改动字体族，但字号 / builtinGlyphs 仍然要设
    Assert-Equal ($d.font.face) $origFace 'defaults.font.face 在 -SkipFont 下保持原样'

    foreach ($p in $j.profiles.list) {
        if ($p.commandline -match '(?i)powershell\.exe|pwsh') {
            Assert-Equal ($p.commandline -match '(?i)-nologo') 'True' "profile '$($p.name)' 带 -NoLogo"
        }
    }

    # 原有内容不能被弄丢；同时旧名（DankMaterialShell）应该已被迁移清掉
    $origOthers = @($orig.schemes | Where-Object { $_.name -ne 'Mucai' -and $_.name -ne 'DankMaterialShell' }).Count
    $newOthers = @($j.schemes | Where-Object { $_.name -ne 'Mucai' -and $_.name -ne 'DankMaterialShell' }).Count
    Assert-Equal (@($j.schemes | Where-Object { $_.name -eq 'Mucai' }).Count) 1 '配色方案里只有一个 Mucai'
    Assert-Equal (@($j.schemes | Where-Object { $_.name -eq 'DankMaterialShell' }).Count) 0 '旧名 DankMaterialShell 已被迁移清掉'
    Assert-Equal (@($j.themes | Where-Object { $_.name -eq 'DankMaterialShell' }).Count) 0 '旧主题也清掉了'
    Assert-Equal $newOthers $origOthers '原有配色方案被保留'
    Assert-Equal (@($j.keybindings).Count) $origKeys '原有快捷键被保留'
    Assert-Equal (@($j.profiles.list).Count) $origProfiles '原有 profile 一个都没丢'

    # 幂等：再跑一次不应该有任何改动
    $again = & $psExe -NoProfile -File $installer -SkipTools -SkipFont -SkipLegacyProfile -ForceBaseConfig -TerminalSettingsPath $tmp -FontSize 11 2>&1
    Assert-Equal ([bool](@($again) -match '无需修改').Count) 'True' '重复执行是空操作（幂等）'

    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host "全部通过：$pass 项断言" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "失败 $fail 项，通过 $pass 项" -ForegroundColor Red
    exit 1
}
