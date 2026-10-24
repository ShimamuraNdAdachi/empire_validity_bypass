#Requires -Version 5.1
<#
.SYNOPSIS
    打包发布 zip：dist/<modid>-v<版本>.zip

.DESCRIPTION
    产出包结构（解压到 Paradox 用户数据目录即可，不要多套一层）：
        README.md
        mod/empire_validity_bypass.mod
        mod/empire_validity_bypass/descriptor.mod
        mod/empire_validity_bypass/common/governments/civics/zzz_....txt

    打包后会校验包内文件清单与源码一致，并输出 SHA256，便于发布时贴出来。

.PARAMETER OutDir
    输出目录，默认 <仓库>\dist

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModId = 'empire_validity_bypass'
$SrcModFile = Join-Path $RepoRoot ($ModId + '.mod')
$SrcModDir = Join-Path $RepoRoot $ModId
$SrcDescriptor = Join-Path $SrcModDir 'descriptor.mod'
$ScriptRel = 'common/governments/civics/zzz_empire_validity_bypass_origins.txt'

foreach ($p in @($SrcModFile, $SrcDescriptor)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "缺少文件：$p" }
}
if (-not (Test-Path -LiteralPath $SrcModDir)) { throw "缺少目录：$SrcModDir" }
if (-not (Test-Path -LiteralPath (Join-Path $SrcModDir $ScriptRel))) { throw "缺少起源覆盖脚本：$ScriptRel" }

# ---------------------------------------------------------------- 版本与输出路径
$descText = Read-TextFileUtf8 $SrcDescriptor
if ($descText -notmatch '(?m)^[ \t]*version[ \t]*=[ \t]*"([^"]+)"') { throw 'descriptor.mod 中没有 version 字段' }
$version = $Matches[1]
if ($descText -notmatch '(?m)^[ \t]*name[ \t]*=[ \t]*"([^"]*)"') { throw 'descriptor.mod 中没有 name 字段' }
$modName = $Matches[1]

if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'dist' }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$zipPath = Join-Path $OutDir ("{0}-v{1}.zip" -f $ModId, $version)
$stageRoot = Join-Path $OutDir ('.stage-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

# ---------------------------------------------------------------- 暂存目录
try {
    New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

    $stageModRoot = Join-Path $stageRoot 'mod'
    New-Item -ItemType Directory -Path $stageModRoot -Force | Out-Null

    Copy-Item -LiteralPath $SrcModFile -Destination (Join-Path $stageModRoot ($ModId + '.mod')) -Force
    Copy-Item -LiteralPath $SrcModDir -Destination (Join-Path $stageModRoot $ModId) -Recurse -Force

    $readme = Join-Path $RepoRoot 'README.md'
    if (Test-Path -LiteralPath $readme) { Copy-Item -LiteralPath $readme -Destination (Join-Path $stageRoot 'README.md') -Force }

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    # 手工建条目：.NET Framework 的 CreateFromDirectory 会写成反斜杠分隔
    # （Windows 能开，但不符合 zip 规范，其它平台/工具会把它当成一个长文件名）。
    $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in (Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Sort-Object FullName)) {
            $rel = $f.FullName.Substring($stageRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $archive.Dispose()
    }

    # ------------------------------------------------------------ 包内容校验
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    } finally {
        $zip.Dispose()
    }

    $fail = @()
    $expected = @()
    $expected += ('mod/' + $ModId + '.mod')
    $expected += ('mod/' + $ModId + '/descriptor.mod')
    $expected += ('mod/' + $ModId + '/' + $ScriptRel)
    foreach ($e in $expected) {
        if ($entries -notcontains $e) { $fail += "缺少 $e" }
    }

    $stagedFiles = @(Get-ChildItem -LiteralPath $stageModRoot -Recurse -File).Count
    $zipModFiles = @($entries | Where-Object { $_ -like 'mod/*' }).Count
    if ($stagedFiles -ne $zipModFiles) {
        $fail += ("包内 mod 文件数 {0} 与暂存 {1} 不一致" -f $zipModFiles, $stagedFiles)
    }

    if ($fail.Count -gt 0) { throw ('包内容校验失败：' + ($fail -join '; ')) }

    # ------------------------------------------------------------ 报告
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    $size = (Get-Item -LiteralPath $zipPath).Length

    Write-Host ''
    Write-Host '=== 打包完成 ===' -ForegroundColor Green
    Write-Host ("mod     ：{0}" -f $modName)
    Write-Host ("版本    ：{0}" -f $version)
    Write-Host ("输出    ：{0}" -f $zipPath)
    Write-Host ("大小    ：{0:N0} 字节" -f $size)
    Write-Host ("SHA256  ：{0}" -f $hash)
    Write-Host ''
    Write-Host '包内文件：'
    foreach ($e in ($entries | Sort-Object)) { Write-Host ("  {0}" -f $e) }
    Write-Host ''
    Write-Host '安装：解压到 Documents\Paradox Interactive\Stellaris，与已有 mod 文件夹合并（不要多套一层目录）。'
} finally {
    # 清理暂存目录：先确认它确实在 OutDir 之下
    if (Test-Path -LiteralPath $stageRoot) {
        $resolvedStage = [System.IO.Path]::GetFullPath($stageRoot)
        if ($resolvedStage.StartsWith($OutDir, [System.StringComparison]::OrdinalIgnoreCase) -and
            $resolvedStage.Length -gt $OutDir.Length -and
            (Split-Path -Leaf $resolvedStage) -like '.stage-*') {
            Remove-Item -LiteralPath $resolvedStage -Recurse -Force
        } else {
            Write-Warning "暂存目录不在预期位置，未删除：$resolvedStage"
        }
    }
}
