#Requires -Version 5.1
<#
.SYNOPSIS
    提取创意工坊上传集合到 build\，并渲染 steamcmd 用的 workshop_build_item.vdf。

.DESCRIPTION
    1. 校验源码：descriptor.mod 字段、path= 字段、预览图、版本号同步
    2. 清空 build\<modid>\ 后重建，只复制需要上传的文件
    3. 剔除 VCS / 开发脚本 / 构建产物 / 系统垃圾 / 美术源文件
    4. 渲染 build\workshop_build_item.vdf（转义引号，换行写真实换行）
    5. 构建后校验文件清单，并把 VDF 按 KeyValues 读回来逐字比对 description

    用法（一般通过 tools\build.bat 调用，参数原样转发）：
        tools\build.bat [-o DIR] [-n] [--no-vdf] [--workshop-id ID] [-h]

    退出码：0 成功 / 2 源不合规 / 3 参数或路径不安全 / 4 构建后校验失败

.NOTES
    这个脚本是 UTF-8 带 BOM + CRLF（PowerShell 5.1 读无 BOM 的 UTF-8 会把中文当 ANSI）。
    对应的 build.bat 必须保持纯 ASCII：cmd 解析含中文的 UTF-8 批处理会错位。
#>

$ErrorActionPreference = 'Stop'

$ModId = 'empire_validity_bypass'
$ModFile = $ModId + '.mod'
$ScriptRel = 'common/governments/civics/zzz_empire_validity_bypass_origins.txt'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $RepoRoot $ModId

$Warnings = New-Object System.Collections.Generic.List[string]

function Warn([string]$Message) { $script:Warnings.Add($Message) }

function Fail([int]$Code, [string]$Message) {
    Write-Host ("错误：{0}" -f $Message) -ForegroundColor Red
    exit $Code
}

function Show-Usage {
    $text = @'
用法: tools\build.bat [-o DIR] [-n] [--no-vdf] [--workshop-id ID] [-h]

  把本 mod 需要上传到 Steam 创意工坊的文件提取到 build\empire_validity_bypass\，
  并在 build\workshop_build_item.vdf 渲染出 steamcmd 上传用的 VDF。
  .git、tools\、dist\、README.md、根目录 .mod、系统垃圾等一律不进 build。

  -o, --out DIR      构建输出根目录，默认 <仓库>\build
  -n, --dry-run      演练：产物写到临时目录，列出清单后删除，不动 build\
      --no-vdf       只做内容构建，不渲染 workshop_build_item.vdf
      --workshop-id  物品 ID，覆盖 tools\workshop\publishedfileid.txt
  -h, --help         显示本帮助

VDF 配置来自 tools\workshop\publish.json（appId / title / visibility /
descriptionFile / previewFile），缺失时用内置默认值；
物品 ID 取自 tools\workshop\publishedfileid.txt。

退出码: 0 成功 / 2 源不合规 / 3 参数或路径不安全 / 4 构建后校验失败
'@
    Write-Host $text
}

# ---------------------------------------------------------------- 参数
$OutArg = $null
$DryRun = $false
$WantVdf = $true
$WorkshopIdArg = $null

$i = 0
while ($i -lt $args.Count) {
    $a = [string]$args[$i]
    if ($a -eq '-o' -or $a -eq '--out') {
        $i++
        if ($i -ge $args.Count) { Fail 3 "$a 需要一个目录参数" }
        $OutArg = [string]$args[$i]
        $i++
    }
    elseif ($a -like '--out=*') { $OutArg = $a.Substring(6); $i++ }
    elseif ($a -eq '-n' -or $a -eq '--dry-run') { $DryRun = $true; $i++ }
    elseif ($a -eq '--no-vdf') { $WantVdf = $false; $i++ }
    elseif ($a -eq '--workshop-id') {
        $i++
        if ($i -ge $args.Count) { Fail 3 "$a 需要一个物品 ID" }
        $WorkshopIdArg = [string]$args[$i]
        $i++
    }
    elseif ($a -like '--workshop-id=*') { $WorkshopIdArg = $a.Substring(14); $i++ }
    elseif ($a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
    elseif ($a -eq '--') { $i++; break }
    else { Show-Usage; Fail 3 ("未知参数：" + $a) }
}

# ---------------------------------------------------------------- 路径
if (-not (Test-Path -LiteralPath $Src)) { Fail 2 "缺少 mod 目录：$Src" }
$SrcFull = (Get-Item -LiteralPath $Src).FullName

if ($OutArg) {
    $OutRoot = [System.IO.Path]::GetFullPath($OutArg)
} else {
    $OutRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot 'build'))
}
$OutRoot = $OutRoot.TrimEnd('\', '/')
$Dest = Join-Path $OutRoot $ModId
$RepoFull = (Get-Item -LiteralPath $RepoRoot).FullName.TrimEnd('\', '/')

# ---------------------------------------------------------------- 路径安全
# 目标目录随后会被整个删除，所以它不能等于、不能包住、也不能落在源码/仓库里。
if (-not $OutRoot -or $OutRoot -match '^[A-Za-z]:$') { Fail 3 '输出根目录不能是磁盘根目录' }
if ($Dest -eq $SrcFull) { Fail 3 "输出目录与源码目录相同：$Dest（换一个 -o）" }
if ($Dest.StartsWith($SrcFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Fail 3 "输出目录位于源码目录内部：$Dest"
}
if ($SrcFull.StartsWith($Dest + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Fail 3 "输出目录是源码目录的上级：$Dest"
}
if ($Dest -eq $RepoFull) { Fail 3 "输出目录与仓库根相同：$Dest（换一个 -o）" }
if ($RepoFull.StartsWith($Dest + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Fail 3 "输出目录是仓库根的上级：$Dest"
}

# ---------------------------------------------------------------- 排除规则
$ExcludeDirs = @('.git', '.github', '.vs', '.idea', '.vscode', '.settings', '.svn', '.cache',
                 '__pycache__', 'node_modules', 'tools', 'dist', 'build', 'steamcmd', 'tmp', 'temp')
$ExcludeRepoFiles = @('README.md', 'CHANGELOG.md', 'LICENSE')
$ExcludeJunkNames = @('Thumbs.db', 'desktop.ini')
$ExcludeTempGlobs = @('*.swp', '*.swo', '*~', '*.bak', '*.tmp', '*.log', '*.orig', '*.rej', '*.pyc')
$ExcludeArchives = @('*.zip', '*.7z', '*.rar')
$ExcludeArtGlobs = @('*.psd', '*.xcf')

function Get-ExcludeReason([string]$Rel) {
    $parts = $Rel -split '[\\/]'
    $baseName = $parts[$parts.Count - 1]

    foreach ($seg in $parts) {
        if ($ExcludeDirs -contains $seg) { return '开发/构建/VCS 目录' }
    }

    if ($baseName -like '.*') {
        if ($baseName -match '^\.(gitignore|gitattributes|gitmodules|editorconfig)$') { return '仓库配置' }
        return '隐藏文件（VCS / 编辑器缓存）'
    }
    if ($ExcludeRepoFiles -contains $baseName) { return '仓库文档' }
    if ($ExcludeJunkNames -contains $baseName) { return '系统垃圾' }
    foreach ($g in $ExcludeTempGlobs) { if ($baseName -like $g) { return '临时/备份文件' } }
    foreach ($g in $ExcludeArchives) { if ($baseName -like $g) { return '压缩包' } }
    foreach ($g in $ExcludeArtGlobs) { if ($baseName -like $g) { return '美术源文件' } }
    return $null
}

# ---------------------------------------------------------------- 描述文件
function Get-DescValue([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $line = Select-String -LiteralPath $Path -Pattern ('^\s*' + [regex]::Escape($Key) + '\s*=\s*"([^"]*)"') |
            Select-Object -First 1
    if (-not $line) { return $null }
    return [regex]::Match($line.Line, '"([^"]*)"').Groups[1].Value
}

$Desc = Join-Path $Src 'descriptor.mod'
if (-not (Test-Path -LiteralPath $Desc)) { Fail 2 "缺少描述文件：$Desc" }

$Version = Get-DescValue $Desc 'version'
$ModName = Get-DescValue $Desc 'name'
$SupportedVersion = Get-DescValue $Desc 'supported_version'
$Picture = Get-DescValue $Desc 'picture'

if (-not $Version) { Fail 2 'descriptor.mod 里没有 version 字段' }
if (-not $ModName) { Warn 'descriptor.mod 里没有 name 字段（工坊标题会用文件名）' }
if (-not $SupportedVersion) { Warn 'descriptor.mod 里没有 supported_version 字段' }
if (-not $Picture) { Warn 'descriptor.mod 里没有 picture 字段（工坊会用默认缩略图）' }

if (Select-String -LiteralPath $Desc -Pattern '^\s*path\s*=' -Quiet) {
    Fail 2 'descriptor.mod 含有 path= 字段：工坊上传的内容里不能有它（删掉再构建）'
}

$PictureDims = $null
if ($Picture) {
    $picPath = Join-Path $Src $Picture
    if (-not (Test-Path -LiteralPath $picPath)) { Fail 2 "descriptor.mod 指向的预览图不存在：$picPath" }
    $bytes = [System.IO.File]::ReadAllBytes($picPath)
    if ($bytes.Length -ge 24 -and
        $bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47) {
        $w = [uint32]$bytes[16] * 16777216 + [uint32]$bytes[17] * 65536 + [uint32]$bytes[18] * 256 + [uint32]$bytes[19]
        $h = [uint32]$bytes[20] * 16777216 + [uint32]$bytes[21] * 65536 + [uint32]$bytes[22] * 256 + [uint32]$bytes[23]
        $PictureDims = '{0}x{1}' -f $w, $h
        if ($PictureDims -ne '512x512') { Warn "预览图尺寸 $PictureDims，惯例是 512x512（正方形）" }
    } else {
        $PictureDims = '非 PNG 或无法解析'
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $Src $ScriptRel))) {
    Fail 2 "缺少起源覆盖脚本：$ScriptRel"
}

$RootMod = Join-Path $RepoRoot $ModFile
if (Test-Path -LiteralPath $RootMod) {
    $rootVersion = Get-DescValue $RootMod 'version'
    if ($rootVersion -ne $Version) {
        Warn "版本号不同步：descriptor.mod=$Version，$ModFile=$rootVersion"
    }
} else {
    Warn "仓库根缺少 $ModFile（只影响本地安装，不影响工坊上传）"
}

# ---------------------------------------------------------------- 收集清单
$Keep = New-Object System.Collections.Generic.List[object]
$Skips = New-Object System.Collections.Generic.List[object]

foreach ($entry in @(Get-ChildItem -LiteralPath $Src -Recurse -Force)) {
    $rel = $entry.FullName.Substring($SrcFull.Length).TrimStart('\', '/')
    if (-not $rel) { continue }
    $reason = Get-ExcludeReason $rel
    if ($reason) {
        $Skips.Add([pscustomobject]@{ Rel = $rel; Reason = $reason })
        continue
    }
    if (-not $entry.PSIsContainer) {
        $Keep.Add([pscustomobject]@{ Rel = $rel; Full = $entry.FullName })
    }
}

if ($Keep.Count -eq 0) { Fail 2 "mod 目录里没有任何可上传的文件：$Src" }

# ---------------------------------------------------------------- 落地
if ($DryRun) {
    $Target = Join-Path ([System.IO.Path]::GetTempPath()) ('evb-dryrun-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
} else {
    $Target = $Dest
}

if (Test-Path -LiteralPath $Target) {
    Remove-Item -LiteralPath $Target -Recurse -Force
}
# 清完目标目录后立刻确认源码还在：护栏万一漏了，这里要吼出来
if (-not (Test-Path -LiteralPath $Desc)) { Fail 3 "清空目标目录后发现源码不见了：$Src" }
New-Item -ItemType Directory -Path $Target -Force | Out-Null

foreach ($f in $Keep) {
    $dstPath = Join-Path $Target $f.Rel
    $dstDir = Split-Path -Parent $dstPath
    if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $f.Full -Destination $dstPath -Force
}

# ---------------------------------------------------------------- 构建后校验
$Fails = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath (Join-Path $Target 'descriptor.mod'))) { $Fails.Add('descriptor.mod 没有进 build') }
if (-not (Test-Path -LiteralPath (Join-Path $Target $ScriptRel))) { $Fails.Add("缺少 $ScriptRel") }
if ($Picture -and -not (Test-Path -LiteralPath (Join-Path $Target $Picture))) { $Fails.Add("缺少预览图 $Picture") }

if (Select-String -LiteralPath (Join-Path $Target 'descriptor.mod') -Pattern '^\s*path\s*=' -Quiet) {
    $Fails.Add('build 里的 descriptor.mod 含 path= 字段')
}

foreach ($m in @(Get-ChildItem -LiteralPath $Target -Filter '*.mod' -File -Force)) {
    if ($m.Name -ne 'descriptor.mod') { $Fails.Add("build 里混入了 .mod 文件：$($m.Name)") }
}

foreach ($entry in @(Get-ChildItem -LiteralPath $Target -Recurse -Force)) {
    $rel = $entry.FullName.Substring($Target.Length).TrimStart('\', '/')
    if (-not $rel) { continue }
    $reason = Get-ExcludeReason $rel
    if ($reason) { $Fails.Add("build 里残留 $rel（$reason）") }
}

$ExpectedCount = $Keep.Count
$ActualCount = @(Get-ChildItem -LiteralPath $Target -Recurse -File -Force).Count
if ($ExpectedCount -ne $ActualCount) {
    $Fails.Add("文件数不一致：源 $ExpectedCount 个，build $ActualCount 个")
}

if ($Fails.Count -gt 0) {
    Write-Host '构建后校验失败：' -ForegroundColor Red
    foreach ($f in $Fails) { Write-Host ('  - ' + $f) }
    exit 4
}

# ---------------------------------------------------------------- 创意工坊 VDF
# steamcmd 的上传参数只能写在 VDF 里（appid / contentfolder / previewfile /
# title / description / changenote / visibility），这里直接渲染一份出来。
# publish.json 是扁平键值，只做最小提取，不是通用 JSON 解析。
$VdfPath = Join-Path (Split-Path -Parent $Target) 'workshop_build_item.vdf'
$VdfWritten = $false
$AppId = '281990'
$Visibility = '3'
$PublishedId = '0'
$DescFile = Join-Path $RepoRoot 'tools\workshop\description.bbcode'

function Get-JsonValue([string]$Path, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $line = Select-String -LiteralPath $Path -Pattern ('"' + [regex]::Escape($Key) + '"\s*:\s*(.*)$') |
            Select-Object -First 1
    if (-not $line) { return $null }
    $raw = [regex]::Match($line.Line, '"' + [regex]::Escape($Key) + '"\s*:\s*(.*)$').Groups[1].Value
    $raw = $raw.Trim()
    $raw = $raw.TrimEnd(',')
    $raw = $raw.Trim()
    if ($raw.Length -ge 2 -and $raw.StartsWith('"') -and $raw.EndsWith('"')) {
        $raw = $raw.Substring(1, $raw.Length - 2)
    }
    return $raw
}

# 读文本 → 统一成 LF → 替换 {{VERSION}} / {{SUPPORTED_VERSION}}，不做转义
function Get-RenderedText([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $text = $text.Replace('{{VERSION}}', $Version).Replace('{{SUPPORTED_VERSION}}', $SupportedVersion)
    return $text.TrimEnd("`n")
}

# 单行 VDF 转义：\ → \\， " → \"
function ConvertTo-VdfEscaped([string]$Text) {
    return $Text.Replace('\', '\\').Replace('"', '\"')
}

# 换行处理。默认写真实换行（0x0A）：steamcmd 不还原字面量 \n，写进去的 "\n"
# 会原样印在工坊页面上（1.2.0 那次上传就是这么坏的）。若某个 steamcmd 版本
# 反而只认转义写法，把 publish.json 的 newlineMode 改成 "escape" 即可切回。
function ConvertTo-VdfBody([string]$Text, [string]$NewlineMode) {
    $body = ConvertTo-VdfEscaped $Text
    if ($NewlineMode -eq 'escape') { $body = $body.Replace("`n", '\n') }
    return $body
}

# 按 Valve KeyValues 的读法解析（引号字符串 + { }，转义 \\ \" \n \t），
# 返回 workshopitem 那一层的键值；结构不合法时返回 $null。
function Read-VdfDocument([string]$Text) {
    $tokens = New-Object System.Collections.Generic.List[object]
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '{' -or $c -eq '}') {
            $tokens.Add([pscustomobject]@{ Kind = 'brace'; Value = [string]$c })
            $i++
            continue
        }
        if ($c -ne '"') { return $null }
        $i++
        $sb = New-Object System.Text.StringBuilder
        $closed = $false
        while ($i -lt $n) {
            $ch = $Text[$i]
            if ($ch -eq '\') {
                if (($i + 1) -ge $n) { return $null }
                $nx = [string]$Text[$i + 1]
                switch -CaseSensitive ($nx) {
                    'n'     { [void]$sb.Append("`n") }
                    't'     { [void]$sb.Append("`t") }
                    '\'     { [void]$sb.Append('\') }
                    '"'     { [void]$sb.Append('"') }
                    default { [void]$sb.Append($nx) }
                }
                $i += 2
                continue
            }
            if ($ch -eq '"') { $closed = $true; $i++; break }
            [void]$sb.Append($ch)
            $i++
        }
        if (-not $closed) { return $null }
        $tokens.Add([pscustomobject]@{ Kind = 'string'; Value = $sb.ToString() })
    }

    if ($tokens.Count -lt 4) { return $null }
    if ($tokens[0].Kind -ne 'string' -or $tokens[0].Value -ne 'workshopitem') { return $null }
    if ($tokens[1].Kind -ne 'brace' -or $tokens[1].Value -ne '{') { return $null }
    $last = $tokens[$tokens.Count - 1]
    if ($last.Kind -ne 'brace' -or $last.Value -ne '}') { return $null }

    $pairs = [ordered]@{}
    $j = 2
    while ($j -lt ($tokens.Count - 1)) {
        if ($tokens[$j].Kind -ne 'string') { return $null }
        if (($j + 1) -ge ($tokens.Count - 1)) { return $null }
        if ($tokens[$j + 1].Kind -ne 'string') { return $null }
        $pairs[$tokens[$j].Value] = $tokens[$j + 1].Value
        $j += 2
    }
    return $pairs
}

if ($WantVdf) {
    $PubJson = Join-Path $RepoRoot 'tools\workshop\publish.json'

    $v = Get-JsonValue $PubJson 'appId'
    if ($v) { $AppId = $v }

    switch ((Get-JsonValue $PubJson 'visibility')) {
        '0'       { $Visibility = '0' }
        'public'  { $Visibility = '0' }
        '1'       { $Visibility = '1' }
        'friends' { $Visibility = '1' }
        '2'       { $Visibility = '2' }
        'private' { $Visibility = '2' }
        default   { $Visibility = '3' }
    }

    $Title = Get-JsonValue $PubJson 'title'
    if (-not $Title) { $Title = $ModName }

    $PreviewRel = Get-JsonValue $PubJson 'previewFile'
    if (-not $PreviewRel) { $PreviewRel = $Picture }
    $PreviewRel = $PreviewRel.Replace('/', '\')

    $descFromJson = Get-JsonValue $PubJson 'descriptionFile'
    if ($descFromJson) { $DescFile = $descFromJson.Replace('/', '\') }
    if (-not [System.IO.Path]::IsPathRooted($DescFile)) { $DescFile = Join-Path $RepoRoot $DescFile }
    if (-not (Test-Path -LiteralPath $DescFile)) { Fail 2 "找不到工坊简介文件：$DescFile" }

    # 物品 ID：参数 > tools\workshop\publishedfileid.txt > 0（首次上传）
    $idFile = Join-Path $RepoRoot 'tools\workshop\publishedfileid.txt'
    if ($WorkshopIdArg) {
        $PublishedId = $WorkshopIdArg
    } elseif (Test-Path -LiteralPath $idFile) {
        $PublishedId = ([System.IO.File]::ReadAllText($idFile) -replace '[^0-9]', '')
    }
    if (-not $PublishedId) { $PublishedId = '0' }
    if ($PublishedId -notmatch '^\d+$') {
        Warn "物品 ID 不是纯数字，按 0 处理：$PublishedId"
        $PublishedId = '0'
    }

    $descInfo = Get-Item -LiteralPath $DescFile
    if ($descInfo.Length -gt 6000) {
        Warn ("简介文件 {0} 字节，接近 steamcmd 的 8000 字符上限，上传前留意 VDF 是否被截断" -f $descInfo.Length)
    }

    # 换行写法：raw（默认，写真实换行）/ escape（写字面量 \n）
    $NewlineMode = 'raw'
    if ((Get-JsonValue $PubJson 'newlineMode') -eq 'escape') { $NewlineMode = 'escape' }

    $DescPlain = Get-RenderedText $DescFile
    $VdfTitle = ConvertTo-VdfEscaped $Title
    $VdfDesc = ConvertTo-VdfBody $DescPlain $NewlineMode
    # raw 模式下简介里出现字面量 \n，说明换行又被折成了转义写法（Steam 会原样打印）
    if ($NewlineMode -ne 'escape' -and $VdfDesc.Contains('\n')) {
        Fail 4 '简介里出现字面量 \n：确认 newlineMode，或把简介里的反斜杠去掉'
    }
    $ContentVdf = $Target.Replace('\', '/')
    $PreviewVdf = ([System.IO.Path]::Combine($Target, $PreviewRel)).Replace('\', '/')

    $noteRaw = Get-JsonValue $PubJson 'changenote'
    if ($noteRaw) {
        # publish.json 里用一行写时，\n 当作分行
        $NotePlain = $noteRaw.Replace('\n', "`n")
    } else {
        # CHANGELOG 里 "## <版本>" 那一节的 "- " 条目
        $noteLines = New-Object System.Collections.Generic.List[string]
        $changelog = Join-Path $RepoRoot 'CHANGELOG.md'
        if (Test-Path -LiteralPath $changelog) {
            $inSection = $false
            foreach ($line in [System.IO.File]::ReadAllLines($changelog, (New-Object System.Text.UTF8Encoding($false)))) {
                if ($line -match '^##\s') {
                    if ($inSection) { break }
                    if ($line.Trim() -eq ('## ' + $Version)) { $inSection = $true }
                    continue
                }
                if ($inSection -and $line.StartsWith('- ')) {
                    $noteLines.Add($line.Substring(2).TrimEnd())
                    continue
                }
                # CHANGELOG 里折行的条目（续行缩进）接回上一条，别把句子截断在工坊页面上
                if ($inSection -and $noteLines.Count -gt 0 -and $line -match '^\s+\S') {
                    $last = $noteLines.Count - 1
                    $noteLines[$last] = $noteLines[$last] + ' ' + $line.Trim()
                }
            }
        }
        if ($noteLines.Count -eq 0) { Warn "CHANGELOG 里没有 $Version 的条目，changenote 为空" }
        $NotePlain = ($noteLines -join "`n")
    }
    $VdfNote = ConvertTo-VdfBody $NotePlain $NewlineMode

    $vdfLines = @(
        '"workshopitem"'
        '{'
        ("`t`"appid`"`t`t`"$AppId`"")
        ("`t`"publishedfileid`"`t`t`"$PublishedId`"")
        ("`t`"contentfolder`"`t`t`"$ContentVdf`"")
        ("`t`"previewfile`"`t`t`"$PreviewVdf`"")
        ("`t`"title`"`t`t`"$VdfTitle`"")
        ("`t`"description`"`t`t`"$VdfDesc`"")
        ("`t`"changenote`"`t`t`"$VdfNote`"")
        ("`t`"visibility`"`t`t`"$Visibility`"")
        '}'
    )
    $vdfText = ($vdfLines -join "`r`n") + "`r`n"
    # 千万不要写 BOM：Valve 的 KeyValues 解析器会把 BOM 当成正文
    [System.IO.File]::WriteAllText($VdfPath, $vdfText, (New-Object System.Text.UTF8Encoding($false)))
    $VdfWritten = $true

    # 自检：按 KeyValues 的读法把 VDF 读回来，逐字比对字段。
    # 换行写错（字面量 \n、或是多出一个裸引号）在这里就会挂掉，
    # 不会等到传上工坊才发现简介变成一行 "\n"。
    $Doc = Read-VdfDocument $vdfText
    if (-not $Doc) {
        Fail 4 'VDF 解析失败：引号、转义或花括号没配对（description 里有落单的引号或反斜杠？）'
    }
    foreach ($key in @('appid', 'publishedfileid', 'contentfolder', 'previewfile', 'title',
                       'description', 'changenote', 'visibility')) {
        if (-not $Doc.Contains($key)) { Fail 4 ("VDF 缺少字段：{0}" -f $key) }
    }
    if ($Doc['description'] -cne $DescPlain) {
        Fail 4 'VDF 的 description 与 description.bbcode 渲染结果不一致'
    }
    if ($Doc['title'] -cne $Title) { Fail 4 'VDF 的 title 与源不一致' }
    if ($Doc['changenote'] -cne $NotePlain) { Fail 4 'VDF 的 changenote 与 CHANGELOG / publish.json 不一致' }
    if ($Doc['contentfolder'] -ne $ContentVdf) { Fail 4 'VDF 的 contentfolder 与构建目录不一致' }
    if ($Doc['previewfile'] -ne $PreviewVdf) { Fail 4 'VDF 的 previewfile 与构建目录不一致' }
    if ($Doc['visibility'] -ne $Visibility) { Fail 4 'VDF 的 visibility 与 publish.json 不一致' }
}

# ---------------------------------------------------------------- 报告
$sizeKb = [math]::Round((@(Get-ChildItem -LiteralPath $Target -Recurse -File -Force) |
                         Measure-Object -Property Length -Sum).Sum / 1024, 0)
$sizeHuman = if ($sizeKb -ge 1024) { '{0:N1} MB' -f ($sizeKb / 1024) } else { '{0} KB' -f $sizeKb }

$rootSkip = @()
foreach ($e in @(Get-ChildItem -LiteralPath $RepoRoot -Force)) {
    if ($e.Name -eq $ModId -or $e.Name -eq 'build') { continue }
    $rootSkip += $e.Name
}

Write-Host ''
if ($DryRun) {
    Write-Host '=== 演练完成（未写入 build\） ==='
} else {
    Write-Host '=== 构建完成 ==='
}
Write-Host ('mod       ：' + $ModName)
Write-Host ('版本      ：' + $Version)
Write-Host ('游戏版本  ：' + $(if ($SupportedVersion) { $SupportedVersion } else { '（未声明）' }))
if ($PictureDims) { Write-Host ('预览图    ：{0}（{1}）' -f $Picture, $PictureDims) }
Write-Host ('源目录    ：' + $SrcFull)
Write-Host ('输出目录  ：' + $Target)
Write-Host ('文件数    ：' + $ActualCount)
Write-Host ('大小      ：' + $sizeHuman)

Write-Host ''
Write-Host '文件清单：'
foreach ($f in @(Get-ChildItem -LiteralPath $Target -Recurse -File -Force | Sort-Object FullName)) {
    Write-Host ('  ' + $f.FullName.Substring($Target.Length).TrimStart('\', '/'))
}

Write-Host ''
Write-Host '已排除：'
if ($Skips.Count -gt 0) {
    foreach ($s in ($Skips | Sort-Object Rel)) {
        Write-Host ('  {0,-48} {1}' -f $s.Rel, $s.Reason)
    }
} else {
    Write-Host '  （mod 目录里没有需要剔除的文件）'
}
if ($rootSkip.Count -gt 0) {
    Write-Host ('  仓库根未上传：' + ($rootSkip -join ', '))
}

if ($Warnings.Count -gt 0) {
    Write-Host ''
    Write-Host '提醒：'
    foreach ($w in $Warnings) { Write-Host ('  - ' + $w) }
}

if ($DryRun) {
    Write-Host ''
    Write-Host ("演练结束：{0} 已丢弃。" -f $Target)
} else {
    Write-Host ''
    Write-Host ('上传根目录（contentfolder）：' + $Target)
    Write-Host '启动器：Mods → 选中本 mod → Upload Mod；或把上面的目录当作 steamcmd 的 contentfolder。'
}

if ($VdfWritten) {
    Write-Host ('创意工坊 VDF：' + $VdfPath)
    Write-Host ('  物品 ID {0} / visibility {1} / 简介 {2}' -f $PublishedId, $Visibility, $DescFile)
    if ($PublishedId -eq '0') {
        Write-Host '  首次上传（publishedfileid=0）；上传成功后把物品 ID 写进 tools\workshop\publishedfileid.txt。'
    }
    Write-Host ('  steamcmd +login 账号 +workshop_build_item "{0}" +quit' -f $VdfPath)
}

if ($DryRun -and (Test-Path -LiteralPath $Target)) {
    Remove-Item -LiteralPath $Target -Recurse -Force
}
if ($DryRun -and $VdfWritten -and (Test-Path -LiteralPath $VdfPath)) {
    Remove-Item -LiteralPath $VdfPath -Force
}

exit 0
