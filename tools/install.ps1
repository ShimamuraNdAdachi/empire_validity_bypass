#Requires -Version 5.1
<#
.SYNOPSIS
    把本仓库的 empire_validity_bypass 安装到 Stellaris 用户数据目录。

.DESCRIPTION
    1. 校验源码文件是否齐全
    2. 检查游戏 / Paradox 启动器是否在运行（-Force 可跳过）
    3. 备份已安装的旧副本（改名 empire_validity_bypass.bak-<时间戳>）
    4. 复制 mod 目录，并写出带绝对路径的 .mod 描述文件
    5. -Enable 时把 mod 追加到 dlc_load.json 的 enabled_mods

.PARAMETER GameDataPath
    Paradox 用户数据目录。默认 Documents\Paradox Interactive\Stellaris；
    也可用环境变量 STELLARIS_USER_DATA 指定。

.PARAMETER Enable
    同时写入 dlc_load.json。注意：启动器 v2 以「播放集」为准，必要时仍需在 UI 里勾选。

.PARAMETER Force
    跳过"游戏 / 启动器正在运行"的检查，并且不提示确认。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install.ps1 -Enable
#>
[CmdletBinding()]
param(
    [string]$GameDataPath,
    [switch]$Enable,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModId = 'empire_validity_bypass'
$SrcModFile = Join-Path $RepoRoot ($ModId + '.mod')
$SrcModDir = Join-Path $RepoRoot $ModId
$SrcScript = Join-Path $SrcModDir 'common\governments\civics\zzz_empire_validity_bypass_origins.txt'

function Assert-PathExists {
    param([string]$Path, [string]$What)
    if (-not (Test-Path -LiteralPath $Path)) { throw "缺少$What：$Path" }
}

# ---------------------------------------------------------------- 1. 源码校验
Assert-PathExists $SrcModFile '.mod 描述文件'
Assert-PathExists $SrcModDir 'mod 目录'
Assert-PathExists (Join-Path $SrcModDir 'descriptor.mod') 'descriptor.mod'
Assert-PathExists $SrcScript '起源覆盖脚本'

# ---------------------------------------------------------------- 2. 进程检查
function Get-BlockingProcess {
    $hits = @()
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        $name = $p.ProcessName
        if ($name -match '^(?i)(stellaris|paradoxlauncher|bootstrapper)$') { $hits += $p; continue }
        if ($name -match '^(?i)launcher$') {
            $exePath = $null
            try { $exePath = $p.Path } catch { }
            if ($exePath -and ($exePath -match '(?i)paradox')) { $hits += $p }
        }
    }
    return $hits
}

$blocking = Get-BlockingProcess
if ($blocking.Count -gt 0) {
    $names = ($blocking | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', '
    if (-not $Force) {
        throw "游戏或启动器正在运行：$names。请完全退出后重试，或加 -Force 强制复制（启动器可能不会刷新 mod 列表）。"
    }
    Write-Warning "检测到正在运行的进程：$names（-Force，继续）"
}

# ---------------------------------------------------------------- 3. 目标目录
$UserData = Get-StellarisUserDataPath -Path $GameDataPath
if (-not (Test-Path -LiteralPath $UserData)) {
    throw "用户数据目录不存在：$UserData。请先在启动器里进一次游戏生成目录，或用 -GameDataPath 指定。"
}

$DestModRoot = Join-Path $UserData 'mod'
$DestModDir = Join-Path $DestModRoot $ModId
$DestModFile = Join-Path $DestModRoot ($ModId + '.mod')
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if (-not (Test-Path -LiteralPath $DestModRoot)) {
    New-Item -ItemType Directory -Path $DestModRoot -Force | Out-Null
}

Write-Host "源：$SrcModDir"
Write-Host "目标：$DestModDir"

# ---------------------------------------------------------------- 4. 备份 + 复制
if (Test-Path -LiteralPath $DestModDir) {
    $backupDir = Join-Path $DestModRoot ("$ModId.bak-$stamp")
    Move-Item -LiteralPath $DestModDir -Destination $backupDir
    Write-Host "旧副本已备份 → $backupDir"
}
if (Test-Path -LiteralPath $DestModFile) {
    Copy-Item -LiteralPath $DestModFile -Destination ($DestModFile + ".bak-$stamp") -Force
}

New-Item -ItemType Directory -Path $DestModDir -Force | Out-Null
Copy-Item -Path (Join-Path $SrcModDir '*') -Destination $DestModDir -Recurse -Force

$copied = Get-ChildItem -LiteralPath $DestModDir -Recurse -File
Write-Host ("已复制 {0} 个文件" -f $copied.Count)

# ---------------------------------------------------------------- 5. 写 .mod
$modText = Read-TextFileUtf8 $SrcModFile
$absPath = ($DestModDir -replace '\\', '/')
$pathLine = 'path="' + $absPath + '"'

if ($modText -match '(?m)^\s*path\s*=') {
    $modText = [regex]::Replace($modText, '(?m)^[ \t]*path[ \t]*=.*$', { param($m) $pathLine })
} else {
    $modText = $modText.TrimEnd() + "`n" + $pathLine + "`n"
}
Write-TextFileUtf8 -Path $DestModFile -Content $modText
Write-Host "已写出描述文件：$DestModFile"

# ---------------------------------------------------------------- 6. 启用
if ($Enable) {
    $dlcFile = Join-Path $UserData 'dlc_load.json'
    $entry = 'mod/' + $ModId + '.mod'
    if (-not (Test-Path -LiteralPath $dlcFile)) {
        Write-Warning "未找到 dlc_load.json，跳过自动启用；请在启动器里手动勾选。"
    } else {
        Copy-Item -LiteralPath $dlcFile -Destination ($dlcFile + ".bak-$stamp") -Force
        $raw = Read-TextFileUtf8 $dlcFile
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{"enabled_mods":[],"disabled_dlcs":[]}' }
        $json = $raw | ConvertFrom-Json

        $list = @()
        if ($json.PSObject.Properties.Name -contains 'enabled_mods') { $list = @($json.enabled_mods) }
        if ($list -notcontains $entry) {
            $list = @($list) + $entry
            if ($json.PSObject.Properties.Name -contains 'enabled_mods') {
                $json.enabled_mods = @($list)
            } else {
                $json | Add-Member -NotePropertyName enabled_mods -NotePropertyValue @($list) -Force
            }
            Write-TextFileUtf8 -Path $dlcFile -Content ($json | ConvertTo-Json -Depth 10 -Compress)
            Write-Host "已写入 dlc_load.json：$entry"
        } else {
            Write-Host "dlc_load.json 已包含该 mod，无需改动"
        }
    }
}

# ---------------------------------------------------------------- 7. 收尾
Write-Host ''
Write-Host '安装完成。后续步骤：'
Write-Host '  1) 启动游戏 →「Mods / 播放集」确认 empire_validity_bypass 已启用'
Write-Host '  2) 帝国选择界面检查带「游牧 + 虚境铸造」的设计（如 man）可开局'
Write-Host '  3) 联机时房主也需要启用同一份 mod，否则该设计在房主端仍可能被拒绝'
