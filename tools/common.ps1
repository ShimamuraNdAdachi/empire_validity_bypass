#Requires -Version 5.1
<#
    tools/common.ps1
    ---------------------------------------------------------------
    公共辅助函数。被 install.ps1 / package.ps1 点源引入：
        . (Join-Path $PSScriptRoot 'common.ps1')

    只做三件事：找路径、读 UTF-8 文本、写无 BOM 的 UTF-8 文本。
#>

function Read-TextFileUtf8 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-TextFileUtf8 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $enc = New-Object System.Text.UTF8Encoding($false)   # 不写 BOM
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Get-StellarisUserDataPath {
    <#  Paradox 用户数据目录（存档 / mod / dlc_load.json 所在处）  #>
    [CmdletBinding()]
    param([string]$Path)

    if ($Path) { return [System.IO.Path]::GetFullPath($Path) }
    if ($env:STELLARIS_USER_DATA) { return [System.IO.Path]::GetFullPath($env:STELLARIS_USER_DATA) }

    $docs = [Environment]::GetFolderPath('MyDocuments')
    return (Join-Path $docs 'Paradox Interactive\Stellaris')
}

function Test-StellarisGameRoot {
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return ((Test-Path -LiteralPath (Join-Path $Path 'launcher-settings.json')) -and
            (Test-Path -LiteralPath (Join-Path $Path 'common\governments\civics')))
}

function Get-SteamRootCandidates {
    [CmdletBinding()]
    param()

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKCU:\Software\Valve\Steam',
                       'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
                       'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $item = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($name in @('SteamPath', 'InstallPath')) {
                $val = $item.$name
                if ($val) { $out.Add(($val -replace '/', '\')) }
            }
        } catch { }
    }
    foreach ($guess in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam',
                         'D:\Steam', 'E:\Steam', 'F:\Steam',
                         'D:\SteamLibrary', 'E:\SteamLibrary', 'F:\SteamLibrary')) {
        if (Test-Path -LiteralPath $guess) { $out.Add($guess) }
    }

    $seen = @{}
    $uniq = @()
    foreach ($p in $out) {
        $k = $p.ToLowerInvariant()
        if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $uniq += $p }
    }
    return $uniq
}

function Get-StellarisGamePath {
    <#  返回 Stellaris 安装目录；找不到返回 $null  #>
    [CmdletBinding()]
    param([string]$Path)

    if ($Path -and (Test-StellarisGameRoot $Path)) { return [System.IO.Path]::GetFullPath($Path) }
    if ($env:STELLARIS_GAME_PATH -and (Test-StellarisGameRoot $env:STELLARIS_GAME_PATH)) {
        return [System.IO.Path]::GetFullPath($env:STELLARIS_GAME_PATH)
    }

    foreach ($root in (Get-SteamRootCandidates)) {
        $libs = New-Object System.Collections.Generic.List[string]
        $libs.Add($root)

        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = Read-TextFileUtf8 $vdf
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"]+)"')) {
                $libs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
            }
        }

        foreach ($lib in $libs) {
            $cand = Join-Path $lib 'steamapps\common\Stellaris'
            if (Test-StellarisGameRoot $cand) { return $cand }
        }
    }
    return $null
}
