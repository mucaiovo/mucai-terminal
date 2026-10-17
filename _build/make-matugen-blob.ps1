#Requires -Version 5.1
<#
.SYNOPSIS
    把 matugen.exe 压成 gzip+base64 的数据块，供安装脚本内置。

.DESCRIPTION
    安装脚本 `Install-MucaiTerminal.ps1` 里嵌的那一大段就是用它生成的。
    升级 matugen 之后，如果要让重新分发的安装脚本也带上新版本，跑一次这个 + inject.py 即可：

        pwsh -NoProfile -File .\_build\make-matugen-blob.ps1
        python .\_build\inject.py
        pwsh -NoProfile -File .\_build\test-merge.ps1

.PARAMETER ExePath
    要打包的 matugen.exe，默认取 ~/.local/bin/matugen.exe。

.PARAMETER OutPath
    输出的数据块路径，默认 _build\matugen\matugen-<版本>.gzb64
    （inject.py 读的是 `matugen-*.gzb64` 里最新的那个）
#>
[CmdletBinding()]
param(
    [string]$ExePath = (Join-Path $HOME '.local\bin\matugen.exe'),
    [string]$OutPath
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

if (-not (Test-Path -LiteralPath $ExePath)) { throw "找不到 $ExePath" }

$ver = ((& $ExePath --version 2>&1 | Select-Object -First 1) -replace '^matugen\s+', '').Trim()
if (-not $ver) { throw "拿不到版本号：$ExePath" }

$dir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'matugen'
if (-not $OutPath) { $OutPath = Join-Path $dir "matugen-$ver.gzb64" }

$raw = [System.IO.File]::ReadAllBytes($ExePath)
$ms = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
$gz.Write($raw, 0, $raw.Length)
$gz.Close()
$comp = $ms.ToArray()

[System.IO.File]::WriteAllText($OutPath, [Convert]::ToBase64String($comp), (New-Object System.Text.UTF8Encoding($false)))

# 顺手把旧版本的数据块清掉，避免 inject.py 拿错
Get-ChildItem $dir -Filter 'matugen-*.gzb64' | Where-Object { $_.FullName -ne $OutPath } | ForEach-Object {
    Write-Host "  删除旧数据块: $($_.Name)" -ForegroundColor DarkGray
    Remove-Item $_.FullName -Force
}

Write-Host ''
Write-Host "版本: $ver" -ForegroundColor Green
Write-Host ("原始: {0:N1} MB -> gzip {1:N1} MB -> base64 {2:N1} MB" -f ($raw.Length / 1MB), ($comp.Length / 1MB), ((Get-Item $OutPath).Length / 1MB))
Write-Host "输出: $OutPath"
Write-Host "exe 的 SHA256: $((Get-FileHash $ExePath -Algorithm SHA256).Hash)"
Write-Host ''
Write-Host '接下来跑：python .\_build\inject.py   （把数据块注入安装脚本，并自检）' -ForegroundColor DarkGray
