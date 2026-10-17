#Requires -Version 5.1
<#
.SYNOPSIS
    matugen 在 Windows 上的"同源"验收测试。

.DESCRIPTION
    用同一份 matugen 模板 + 同一个种子色，在 Windows 上渲染，
    然后与 Linux 端的线上文件逐字节比对。

    种子色 #1b63fd 取自 Linux 端的 ~/.cache/DankMaterialShell/dms-colors.json
    里的 source_color 读出来的 —— 也就是说，这个种子能确切复现他当前那套配色
    （已在 Linux 上验证：starship.toml 逐字节一致）。

    已知的有意差异：fastfetch 配置在 Windows 上必须把 logo 的 9 个颜色槽位都填满
    （Windows 默认 logo 用到多个槽位，只填 1、2 会导致"双拼色"），所以这份与 Linux 端
    的线上文件不同；对它的比对验证的是"确定性"，而不是跨平台逐字节相同。
    starship.toml 仍然是逐字节相同的。

    同时实测 matugen 的耗时与峰值内存。

.EXAMPLE
    pwsh -NoProfile -File .\verify.ps1
#>
[CmdletBinding()]
param(
    [string]$Seed = '#1b63fd',
    [string]$MatugenPath
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# matugen 的查找顺序：~/.local/bin（卸掉 Rust 工具链后的位置）-> ~/.cargo/bin -> PATH
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

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ref = Join-Path (Split-Path -Parent $here) 'reference'
$templates = Join-Path $ref 'templates'
$expected = Join-Path $ref 'expected'
$out = Join-Path $here 'out'

if (-not (Test-Path $MatugenPath)) { throw "找不到 matugen: $MatugenPath" }
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $out | Out-Null

# --- 生成 Windows 版 matugen 配置（绝对路径 + 正斜杠，避免 TOML 转义问题）---
$slash = { param($p) $p -replace '\\', '/' }
$cfgPath = Join-Path $here 'config.windows.toml'
$cfg = @"
[config]

[templates.starship]
input_path = '$(& $slash (Join-Path $templates 'starship-colors.toml'))'
output_path = '$(& $slash (Join-Path $out 'starship.toml'))'

[templates.fastfetch]
input_path = '$(& $slash (Join-Path $templates 'fastfetch-config.jsonc'))'
output_path = '$(& $slash (Join-Path $out 'fastfetch-config.jsonc'))'
"@
Set-Content -Path $cfgPath -Value $cfg -Encoding utf8

Write-Host "=== matugen 版本 ===" -ForegroundColor Cyan
& $MatugenPath --version

Write-Host ""
Write-Host "=== 运行（种子 $Seed，含内存采样）===" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath $MatugenPath `
    -ArgumentList @('--config', $cfgPath, 'color', 'hex', $Seed) `
    -PassThru -NoNewWindow
$peak = 0
while (-not $proc.HasExited) {
    try { $proc.Refresh(); if ($proc.WorkingSet64 -gt $peak) { $peak = $proc.WorkingSet64 } } catch { }
    Start-Sleep -Milliseconds 10
}
$sw.Stop()
$proc.WaitForExit()

Write-Host ("  耗时      : {0:N0} ms" -f $sw.Elapsed.TotalMilliseconds)
Write-Host ("  峰值内存  : {0:N1} MB" -f ($peak / 1MB))
Write-Host ("  退出码    : {0}" -f $proc.ExitCode)

# --- 逐字节比对 ---
Write-Host ""
Write-Host "=== 与 Linux 端线上文件比对 ===" -ForegroundColor Cyan
$fail = 0
$pairs = @(
    @{ Name = 'starship.toml';          Got = (Join-Path $out 'starship.toml');          Want = (Join-Path $expected 'starship.toml') },
    @{ Name = 'fastfetch-config.jsonc'; Got = (Join-Path $out 'fastfetch-config.jsonc'); Want = (Join-Path $expected 'fastfetch-config.jsonc') }
)
foreach ($p in $pairs) {
    if (-not (Test-Path $p.Got)) { Write-Host "  [XX] $($p.Name) 没有生成" -ForegroundColor Red; $fail++; continue }
    $a = [System.IO.File]::ReadAllBytes($p.Got)
    $b = [System.IO.File]::ReadAllBytes($p.Want)
    $same = ($a.Length -eq $b.Length) -and (@(Compare-Object $a $b -SyncWindow 0).Count -eq 0)
    if ($same) {
        Write-Host ("  [OK] {0} 逐字节一致（{1:N0} bytes）" -f $p.Name, $a.Length) -ForegroundColor Green
    }
    else {
        $ta = ([System.IO.File]::ReadAllText($p.Got)).Replace("`r`n", "`n")
        $tb = ([System.IO.File]::ReadAllText($p.Want)).Replace("`r`n", "`n")
        if ($ta -eq $tb) {
            Write-Host ("  [~~] {0} 仅换行符不同（内容一致，{1:N0} vs {2:N0} bytes）" -f $p.Name, $a.Length, $b.Length) -ForegroundColor Yellow
        }
        else {
            Write-Host ("  [XX] {0} 内容不同（{1:N0} vs {2:N0} bytes）" -f $p.Name, $a.Length, $b.Length) -ForegroundColor Red
            $n = [Math]::Min($ta.Length, $tb.Length)
            for ($i = 0; $i -lt $n; $i++) {
                if ($ta[$i] -ne $tb[$i]) {
                    Write-Host ("       首个差异 @ {0}: Windows=[{1}]  Linux=[{2}]" -f $i, $ta.Substring([Math]::Max(0, $i - 20), 40), $tb.Substring([Math]::Max(0, $i - 20), 40))
                    break
                }
            }
            $fail++
        }
    }
}

Write-Host ""
if ($fail -eq 0) { Write-Host "验收通过：两端同源同值" -ForegroundColor Green; exit 0 }
else { Write-Host "验收失败：$fail 个文件不一致" -ForegroundColor Red; exit 1 }
