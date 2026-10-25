@echo off
rem ============================================================
rem  tools\build.bat - extract the Workshop upload set into build\
rem ------------------------------------------------------------
rem  源：empire_validity_bypass\          （mod 本体，即工坊上传内容）
rem  出：build\empire_validity_bypass\    （只含需要上传的文件）
rem
rem  被排除、不进 build\ 的东西：
rem    .git\ .github\ .vscode\ .idea\ ...          VCS 与编辑器
rem    tools\ dist\ build\ steamcmd\ tmp\          开发脚本与构建产物
rem    README.md CHANGELOG.md LICENSE               仓库文档
rem    Thumbs.db desktop.ini *.swp *.bak *.log ...  系统垃圾与临时文件
rem    *.psd *.xcf *.zip *.7z ...                   美术源文件与压缩包
rem    empire_validity_bypass.mod                    含 path= 的本地描述文件
rem
rem  规则与 tools/build.sh 完全一致，两个脚本产出同一套文件。
rem  用法：tools\build.bat [-o DIR] [-n] [-h]
rem  退出码：0 成功 / 2 源不合规 / 3 参数或路径不安全 / 4 构建后校验失败
rem ============================================================
setlocal
for /f "tokens=2 delims=:" %%C in ('chcp') do set "_OLDCP=%%C"
set "_OLDCP=%_OLDCP: =%"
chcp 65001 >nul 2>nul
setlocal enabledelayedexpansion

set "MOD_ID=empire_validity_bypass"
set "MOD_FILE=%MOD_ID%.mod"
set "SCRIPT_REL=common\governments\civics\zzz_empire_validity_bypass_origins.txt"
set "JUNK_FILES=Thumbs.db desktop.ini *.swp *.swo *~ *.bak *.tmp *.log *.orig *.rej *.pyc *.zip *.7z *.rar *.psd *.xcf"
set "WARN="
set "PIC_DIMS="
set "WANT_VDF=1"
set "WS_ID_ARG="

for %%I in ("%~dp0..") do set "REPO_ROOT=%%~fI"
set "SRC=%REPO_ROOT%\%MOD_ID%"
set "OUT_ROOT=%REPO_ROOT%\build"
set "DRY_RUN=0"

rem ---------------------------------------------------------- 参数
:parse
if "%~1"=="" goto parsed
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
if /i "%~1"=="-n" set "DRY_RUN=1" & shift & goto parse
if /i "%~1"=="--dry-run" set "DRY_RUN=1" & shift & goto parse
if /i "%~1"=="--no-vdf" set "WANT_VDF=0" & shift & goto parse
if /i "%~1"=="-o" goto arg_out
if /i "%~1"=="--out" goto arg_out
if /i "%~1"=="--workshop-id" goto arg_wsid
set "_a=%~1"
if /i "!_a:~0,14!"=="--workshop-id=" set "WS_ID_ARG=!_a:~14!" & shift & goto parse
echo 错误：未知参数 %~1
echo 用 tools\build.bat -h 查看用法。
set "EC=3" & goto finish

:arg_wsid
if "%~2"=="" (
    echo 错误：%~1 需要一个物品 ID
    set "EC=3" & goto finish
)
set "WS_ID_ARG=%~2"
shift & shift
goto parse

:arg_out
if "%~2"=="" (
    echo 错误：%~1 需要一个目录参数
    set "EC=3" & goto finish
)
set "OUT_ROOT=%~2"
shift & shift
goto parse

:parsed
for %%I in ("%OUT_ROOT%") do set "OUT_ROOT=%%~fI"
set "DEST=%OUT_ROOT%\%MOD_ID%"

rem ---------------------------------------------------------- 路径安全
rem 目标目录随后会被 rd /s /q，所以它不能等于、不能包住、也不能落在源码/仓库里。
rem %%~fI 已经把 . 和 .. 折掉了，这里只判包含关系。
if "%OUT_ROOT:~2%"=="" goto err_root
if "%OUT_ROOT:~3%"=="" goto err_root
if /i "%DEST%"=="%SRC%" goto err_same
if /i "%DEST%"=="%REPO_ROOT%" goto err_ancestor
rem 包含关系用「把 前缀\ 替换掉」判断：cmd 的 %var:old=new% 不能嵌套变量，
rem 所以外层走延迟展开、内层走普通展开。
set "_needle=%DEST%\"
set "_d=%REPO_ROOT%"
set "_r=!_d:%_needle%=!"
if not "!_d!"=="!_r!" goto err_ancestor
set "_needle=%SRC%\"
set "_d=%DEST%"
set "_r=!_d:%_needle%=!"
if not "!_d!"=="!_r!" goto err_inside

rem ---------------------------------------------------------- 源校验
if not exist "%SRC%\" goto err_no_src
set "DESC=%SRC%\descriptor.mod"
if not exist "%DESC%" goto err_no_desc

set "VER="
set "MOD_NAME="
set "SUPV="
set "PIC="
for /f "usebackq tokens=1,2 delims==" %%A in ("%DESC%") do (
    set "_k=%%~A"
    set "_k=!_k: =!"
    if /i "!_k!"=="version" if not defined VER set "VER=%%~B"
    if /i "!_k!"=="name" if not defined MOD_NAME set "MOD_NAME=%%~B"
    if /i "!_k!"=="supported_version" if not defined SUPV set "SUPV=%%~B"
    if /i "!_k!"=="picture" if not defined PIC set "PIC=%%~B"
)
if not defined VER goto err_no_ver
if not defined MOD_NAME set "MOD_NAME=(未声明)"
if not defined SUPV set "SUPV=(未声明)"

findstr /i /r /c:"^ *path *= *" "%DESC%" >nul 2>nul
if not errorlevel 1 goto err_has_path

if not defined PIC goto after_pic
if not exist "%SRC%\%PIC%" goto err_no_pic
call :png_size "%SRC%\%PIC%"

:after_pic
if not exist "%SRC%\%SCRIPT_REL%" goto err_no_script

set "ROOT_MOD=%REPO_ROOT%\%MOD_FILE%"
if not exist "%ROOT_MOD%" (
    call :addwarn "仓库根缺少 %MOD_FILE%（只影响本地安装，不影响工坊上传）"
    goto after_root_ver
)
set "ROOT_VER="
for /f "usebackq tokens=1,2 delims==" %%A in ("%ROOT_MOD%") do (
    set "_k=%%~A"
    set "_k=!_k: =!"
    if /i "!_k!"=="version" if not defined ROOT_VER set "ROOT_VER=%%~B"
)
if /i "%ROOT_VER%"=="%VER%" goto after_root_ver
call :addwarn "版本号不同步：descriptor.mod=%VER%，%MOD_FILE%=%ROOT_VER%"

:after_root_ver
rem ---------------------------------------------------------- 目标目录
if "%DRY_RUN%"=="1" goto dry_target
set "TARGET=%DEST%"
if exist "%TARGET%\" rd /s /q "%TARGET%"
rem 清完目标目录后立刻确认源码还在：护栏万一漏了，这里要吼出来
if not exist "%SRC%\descriptor.mod" goto err_lost
mkdir "%TARGET%" 2>nul
if not exist "%TARGET%\" goto err_mkdir
goto do_copy

:dry_target
set "TARGET=%TEMP%\evb-dryrun-%RANDOM%%RANDOM%"
if exist "%TARGET%\" rd /s /q "%TARGET%"
mkdir "%TARGET%" 2>nul
if not exist "%TARGET%\" goto err_mkdir

rem ---------------------------------------------------------- 复制
:do_copy
rem robocopy 退出码 < 8 都算成功（1=有复制，2=有多余，3=两者都有）
robocopy "%SRC%" "%TARGET%" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD .git .github .vs .idea .vscode .settings .svn .cache __pycache__ node_modules tools dist build steamcmd tmp temp >nul 2>nul
if errorlevel 8 goto err_copy

rem ---------------------------------------------------------- 剔除
for /r "%TARGET%" %%F in (%JUNK_FILES%) do if exist "%%F" del /f /q "%%F" >nul 2>nul

for /d /r "%TARGET%" %%D in (*) do (
    set "_n=%%~nxD"
    if "!_n:~0,1!"=="." rd /s /q "%%D" >nul 2>nul
)
for /r "%TARGET%" %%F in (*) do (
    set "_n=%%~nxF"
    if "!_n:~0,1!"=="." del /f /q "%%F" >nul 2>nul
)
rem 顺带清掉因剔除变空的目录（只删空的，不会误删内容）
for /f "delims=" %%D in ('dir /a:d /b /s "%TARGET%" 2^>nul ^| sort /r') do rd "%%D" >nul 2>nul

rem ---------------------------------------------------------- 构建后校验
if not exist "%TARGET%\descriptor.mod" goto err_post_desc
if not exist "%TARGET%\%SCRIPT_REL%" goto err_post_script
if defined PIC if not exist "%TARGET%\%PIC%" goto err_post_pic
findstr /i /r /c:"^ *path *= *" "%TARGET%\descriptor.mod" >nul 2>nul
if not errorlevel 1 goto err_post_path

set "JUNK="
for /r "%TARGET%" %%F in (%JUNK_FILES%) do if exist "%%F" (
    set "JUNK=1"
    echo   [残留] %%F
)
for /d /r "%TARGET%" %%D in (*) do (
    set "_n=%%~nxD"
    if "!_n:~0,1!"=="." (
        set "JUNK=1"
        echo   [残留] %%D\
    )
)
if defined JUNK goto err_post_junk

set /a COUNT=0
set /a BYTES=0
for /f "delims=" %%F in ('dir /b /s /a-d "%TARGET%\*" 2^>nul') do (
    set /a COUNT+=1
    set /a BYTES+=%%~zF
)
if "%COUNT%"=="0" goto err_post_empty

rem ---------------------------------------------------------- 创意工坊 VDF
rem steamcmd 的上传参数只能写在 VDF 里（appid / contentfolder / previewfile /
rem title / description / changenote / visibility），这里直接渲染一份出来。
rem publish.json 只做最小的扁平键值提取，不是通用 JSON 解析。
if "%WANT_VDF%"=="0" goto after_vdf

set "VDF_WRITTEN=0"
set "PUB_JSON=%REPO_ROOT%\tools\workshop\publish.json"
for %%I in ("%TARGET%\..") do set "VDF_DIR=%%~fI"
set "VDF_OUT=%VDF_DIR%\workshop_build_item.vdf"

call :json_get "%PUB_JSON%" appId
set "APP_ID=%JSON_V%"
if not defined APP_ID set "APP_ID=281990"

call :json_get "%PUB_JSON%" visibility
set "VIS=3"
if /i "%JSON_V%"=="0" set "VIS=0"
if /i "%JSON_V%"=="public" set "VIS=0"
if /i "%JSON_V%"=="1" set "VIS=1"
if /i "%JSON_V%"=="friends" set "VIS=1"
if /i "%JSON_V%"=="2" set "VIS=2"
if /i "%JSON_V%"=="private" set "VIS=2"

call :json_get "%PUB_JSON%" title
set "TITLE_V=%JSON_V%"
if not defined TITLE_V set "TITLE_V=%MOD_NAME%"
call :escape_var TITLE_V

call :json_get "%PUB_JSON%" previewFile
set "PREVIEW_REL=%JSON_V%"
if not defined PREVIEW_REL set "PREVIEW_REL=%PIC%"
set "PREVIEW_REL=%PREVIEW_REL:/=\%"

call :json_get "%PUB_JSON%" descriptionFile
set "DESC_FILE=%JSON_V%"
if not defined DESC_FILE set "DESC_FILE=tools\workshop\description.bbcode"
set "DESC_FILE=%DESC_FILE:/=\%"
if not "%DESC_FILE:~1,1%"==":" if not "%DESC_FILE:~0,1%"=="\" set "DESC_FILE=%REPO_ROOT%\%DESC_FILE%"
if not exist "%DESC_FILE%" goto err_no_descfile

rem cmd 单行上限 8191 字符：转义会把文本撑大，所以直接看源文件字节数
for %%A in ("%DESC_FILE%") do set "_fsz=%%~zA"
if defined _fsz if %_fsz% GTR 6000 goto err_vdf_long

rem 物品 ID：参数 > tools\workshop\publishedfileid.txt > 0（首次上传）
set "PUB_ID=%WS_ID_ARG%"
if not defined PUB_ID if exist "%REPO_ROOT%\tools\workshop\publishedfileid.txt" set /p PUB_ID=<"%REPO_ROOT%\tools\workshop\publishedfileid.txt"
set "_badid="
if defined PUB_ID for /f "delims=0123456789" %%X in ("%PUB_ID%") do set "_badid=1"
if defined _badid set "PUB_ID="
if not defined PUB_ID set "PUB_ID=0"

findstr /c:"!" "%DESC_FILE%" >nul 2>nul
if not errorlevel 1 call :addwarn "简介里有 ! ，cmd 会吞掉；需要的话用 build.sh 渲染 VDF"

call :vdf_value "%DESC_FILE%" 1
set "DESC_V=%VDF_V%"

call :json_get "%PUB_JSON%" changenote
if defined JSON_V (
    set "NOTE_V=!JSON_V!"
    call :escape_var NOTE_V
) else (
    call :changenote_file
    rem 块内必须用 !延迟展开!：%VAR% 在这块被解析时还是旧值
    for %%A in ("!NOTE_TMP!") do set "_nsz=%%~zA"
    if !_nsz! GTR 6000 goto err_vdf_long
    call :vdf_value "!NOTE_TMP!" 0
    set "NOTE_V=!VDF_V!"
    del "!NOTE_TMP!" >nul 2>nul
    if not defined NOTE_V call :addwarn "CHANGELOG 里没有 %VER% 的条目，changenote 为空"
)

set "CONTENT_V=%TARGET%"
set "CONTENT_V=%CONTENT_V:\=/%"
set "PREVIEW_V=%TARGET%\%PREVIEW_REL%"
set "PREVIEW_V=%PREVIEW_V:\=/%"

break>"%VDF_OUT%"
>>"%VDF_OUT%" echo "workshopitem"
>>"%VDF_OUT%" echo {
>>"%VDF_OUT%" echo 	"appid"		"%APP_ID%"
>>"%VDF_OUT%" echo 	"publishedfileid"		"%PUB_ID%"
>>"%VDF_OUT%" echo 	"contentfolder"		"%CONTENT_V%"
>>"%VDF_OUT%" echo 	"previewfile"		"%PREVIEW_V%"
>>"%VDF_OUT%" echo 	"title"		"%TITLE_V%"
>>"%VDF_OUT%" echo 	"description"		"%DESC_V%"
>>"%VDF_OUT%" echo 	"changenote"		"%NOTE_V%"
>>"%VDF_OUT%" echo 	"visibility"		"%VIS%"
>>"%VDF_OUT%" echo }

rem 校验：行数必须是 11（有裸换行就会变多）
set "VDF_LINES="
for /f %%A in ('find /c /v "" ^<"%VDF_OUT%"') do set "VDF_LINES=%%A"
if not "%VDF_LINES%"=="11" goto err_vdf_lines
findstr /b /c:"\"workshopitem\"" "%VDF_OUT%" >nul 2>nul
if errorlevel 1 goto err_vdf_head
set "VDF_WRITTEN=1"

:after_vdf
rem ---------------------------------------------------------- 报告
echo.
if "%DRY_RUN%"=="1" (
    echo === 演练完成（未写入 build\） ===
) else (
    echo === 构建完成 ===
)
echo mod       ：%MOD_NAME%
echo 版本      ：%VER%
echo 游戏版本  ：%SUPV%
if defined PIC_DIMS echo 预览图    ：%PIC% ^(%PIC_DIMS%^)
echo 源目录    ：%SRC%
echo 输出目录  ：%TARGET%
echo 文件数    ：%COUNT%
set /a SIZE_KB=BYTES/1024
echo 大小      ：%BYTES% 字节（%SIZE_KB% KB）
echo.
echo 文件清单：
for /f "delims=" %%F in ('dir /b /s /a-d "%TARGET%\*" 2^>nul') do call :echo_rel "%%F" "%TARGET%"

echo.
echo 已排除（源目录里有、但没进 build）：
set "SKIPPED="
for /f "delims=" %%F in ('dir /b /s /a-d "%SRC%\*" 2^>nul') do (
    set "_p=%%F"
    set "_p=!_p:%SRC%\=!"
    if not exist "%TARGET%\!_p!" (
        echo   !_p!
        set "SKIPPED=1"
    )
)
if not defined SKIPPED echo   （mod 目录里没有需要剔除的文件）
for %%X in (.git .github tools dist README.md CHANGELOG.md LICENSE %MOD_FILE%) do (
    if exist "%REPO_ROOT%\%%X" echo   %%X	（在仓库根，不参与上传）
)

if defined WARN (
    echo.
    echo 提醒：
    echo   - %WARN%
)

if "%DRY_RUN%"=="1" (
    echo.
    echo 演练结束：%TARGET% 已丢弃。
) else (
    echo.
    echo 上传根目录（contentfolder）：%TARGET%
    echo 启动器：Mods → 选中本 mod → Upload Mod；或把上面的目录当作 steamcmd 的 contentfolder。
)
if "%VDF_WRITTEN%"=="1" (
    echo.
    echo 创意工坊 VDF：%VDF_OUT%
    echo   物品 ID %PUB_ID% / visibility %VIS% / 简介 %DESC_FILE%
    if "%PUB_ID%"=="0" echo   首次上传（publishedfileid=0）；上传成功后把物品 ID 写进 tools\workshop\publishedfileid.txt。
    echo   steamcmd +login 账号 +workshop_build_item "%VDF_OUT%" +quit
)
if exist "%TARGET%\" if "%DRY_RUN%"=="1" rd /s /q "%TARGET%"
if exist "%VDF_OUT%" if "%DRY_RUN%"=="1" del /f /q "%VDF_OUT%" >nul 2>nul
set "EC=0" & goto finish

rem ---------------------------------------------------------- 收尾
:finish
if defined _OLDCP chcp %_OLDCP% >nul 2>nul
exit /b %EC%

rem ---------------------------------------------------------- 子程序
:addwarn
set "WARN=!WARN! %~1"
exit /b 0

:escape_var
rem %1=变量名；原地把值里的 \ 与 " 转义成 VDF 能吃的形式
setlocal enabledelayedexpansion
set "_v=!%~1!"
if defined _v set "_v=!_v:\=\\!"
if defined _v set "_v=!_v:"=\"!"
endlocal & set "%~1=%_v%"
exit /b 0

:json_get
rem %1=json 文件 %2=键 → JSON_V（扁平键值，找不到时为空）
set "JSON_V="
if not exist "%~1" exit /b 0
for /f "usebackq tokens=1,* delims=:" %%A in (`findstr /i /c:"\"%~2\"" "%~1"`) do (
    if not defined JSON_V (
        set "_jraw=%%B"
        call :json_clean
    )
)
exit /b 0

:json_clean
rem 去逗号、去引号、去首尾空白，结果放 JSON_V
setlocal enabledelayedexpansion
set "_v=!_jraw!"
if "!_v:~-1!"=="," set "_v=!_v:~0,-1!"
if defined _v set "_v=!_v:"=!"
for /f "tokens=*" %%X in ("!_v!") do set "_v=%%X"
endlocal & set "JSON_V=%_v%"
exit /b 0

:vdf_value
rem %1=文本文件 %2=1 时替换 {{VERSION}}/{{SUPPORTED_VERSION}} → VDF_V（单行，\n 分隔）
set "VDF_V="
set "_vfirst=1"
if not exist "%~1" exit /b 0
for /f "usebackq delims=" %%L in (`findstr /n /r "^" "%~1"`) do (
    set "_vl=%%L"
    call :vdf_line %~2
)
exit /b 0

:vdf_line
rem 处理 _vl 里的一行：去行号 → 占位符 → 转义 → 用 \n 接到 VDF_V 后面
rem 注意：变量为空时 %var:old=new% 不替换而是原样吐出 "old=new"，所以每步都判空
setlocal enabledelayedexpansion
set "_t=!_vl:*:=!"
if "%~1"=="1" (
    if defined _t set "_t=!_t:{{VERSION}}=%VER%!"
    if defined _t set "_t=!_t:{{SUPPORTED_VERSION}}=%SUPV%!"
)
if defined _t set "_t=!_t:\=\\!"
if defined _t set "_t=!_t:"=\"!"
if "!_vfirst!"=="1" (
    endlocal & set "_vfirst=0" & set "VDF_V=%_t%" & exit /b 0
)
endlocal & set "VDF_V=%VDF_V%\n%_t%" & exit /b 0

:changenote_file
rem 把 CHANGELOG.md 里 "## %VER%" 那一节的 "- " 条目抽到 NOTE_TMP
set "NOTE_TMP=%TEMP%\evb-note-%RANDOM%%RANDOM%.txt"
break>"%NOTE_TMP%"
set "_in=0"
for /f "usebackq delims=" %%L in (`findstr /n /r "^" "%REPO_ROOT%\CHANGELOG.md"`) do (
    set "_cl=%%L"
    call :note_line
)
exit /b 0

:note_line
setlocal enabledelayedexpansion
set "_t=!_cl:*:=!"
if "!_in!"=="2" (
    endlocal
    exit /b 0
)
if "!_in!"=="1" (
    if "!_t:~0,3!"=="## " (
        endlocal
        set "_in=2"
        exit /b 0
    )
    if "!_t:~0,2!"=="- " (
        set "_t=!_t:~2!"
        >>"%NOTE_TMP%" echo(!_t!
    )
    endlocal
    exit /b 0
)
if "!_t!"=="## %VER%" (
    endlocal
    set "_in=1"
    exit /b 0
)
endlocal
exit /b 0

:echo_rel
rem %1=绝对路径 %2=根目录，打印相对路径
set "_p=%~1"
set "_p=!_p:%~2\=!"
echo   !_p!
exit /b 0

:png_size
rem 转成十六进制后读 PNG 头：签名 + IHDR 里的宽高（失败时保持未定义）
if "%~1"=="" exit /b 0
for %%E in ("%~1") do set "_ext=%%~xE"
if /i not "!_ext!"==".png" exit /b 0
set "_hex=%TEMP%\evb-png-%RANDOM%%RANDOM%.txt"
rem 第四个参数 4 = 纯十六进制（1/7 是 base64）
certutil -encodehex -f "%~1" "%_hex%" 4 >nul 2>nul
if errorlevel 1 (
    del "%_hex%" >nul 2>nul
    exit /b 0
)
set "_sig="
for /f "usebackq tokens=1-4" %%a in ("%_hex%") do if not defined _sig set "_sig=%%a%%b%%c%%d"
set "_got="
for /f "usebackq skip=1 tokens=1-8" %%a in ("%_hex%") do (
    if not defined _got (
        set "_got=1"
        set /a "_w=0x%%a%%b%%c%%d" 2>nul
        set /a "_v=0x%%e%%f%%g%%h" 2>nul
    )
)
del "%_hex%" >nul 2>nul
if /i not "!_sig!"=="89504e47" exit /b 0
if not defined _w exit /b 0
if not defined _v exit /b 0
if not defined PNG_W set "PNG_W=!_w!"
if not defined PNG_H set "PNG_H=!_v!"
set "PIC_DIMS=!_w!x!_v!"
if not "!_w!x!_v!"=="512x512" call :addwarn "预览图尺寸 !_w!x!_v!，惯例是 512x512（正方形）"
exit /b 0

:usage
echo 用法: tools\build.bat [-o DIR] [-n] [--no-vdf] [--workshop-id ID] [-h]
echo.
echo   把本 mod 需要上传到 Steam 创意工坊的文件提取到 build\%MOD_ID%\，
echo   并在 build\workshop_build_item.vdf 渲染出 steamcmd 上传用的 VDF。
echo   .git、tools\、dist\、README.md、根目录 .mod、系统垃圾等一律不进 build。
echo.
echo   -o, --out DIR      构建输出根目录，默认 ^<仓库^>\build
echo   -n, --dry-run      演练：产物写到临时目录，列出清单后删除，不动 build\
echo       --no-vdf       只做内容构建，不渲染 workshop_build_item.vdf
echo       --workshop-id  物品 ID，覆盖 tools\workshop\publishedfileid.txt
echo   -h, --help         显示本帮助
echo.
echo VDF 配置来自 tools\workshop\publish.json（appId / title / visibility /
echo descriptionFile / previewFile），缺失时用内置默认值。
echo.
echo 退出码: 0 成功 / 2 源不合规 / 3 参数或路径不安全 / 4 构建后校验失败
set "EC=0" & goto finish

rem ---------------------------------------------------------- 错误出口
:err_root
echo 错误：输出根目录不能是磁盘根目录（用 -o 指定一个子目录）。
set "EC=3" & goto finish

:err_same
echo 错误：输出目录与源码目录相同：%DEST%
echo 换一个 -o；脚本会先清空目标目录，绝不能指向源码。
set "EC=3" & goto finish

:err_inside
echo 错误：输出目录位于源码目录内部：%DEST%
set "EC=3" & goto finish

:err_ancestor
echo 错误：输出目录与仓库根相同、或是它的上级：%DEST%
echo 换一个 -o；脚本会先清空目标目录。
set "EC=3" & goto finish

:err_lost
echo 错误：清空目标目录后发现源码不见了：%SRC%
set "EC=3" & goto finish

:err_no_src
echo 错误：缺少 mod 目录：%SRC%
set "EC=2" & goto finish

:err_no_desc
echo 错误：缺少描述文件：%DESC%
set "EC=2" & goto finish

:err_no_ver
echo 错误：descriptor.mod 里没有 version 字段。
set "EC=2" & goto finish

:err_has_path
echo 错误：descriptor.mod 含有 path= 字段；工坊上传的内容里不能有它（删掉再构建）。
set "EC=2" & goto finish

:err_no_pic
echo 错误：descriptor.mod 指向的预览图不存在：%SRC%\%PIC%
set "EC=2" & goto finish

:err_no_script
echo 错误：缺少起源覆盖脚本：%SRC%\%SCRIPT_REL%
set "EC=2" & goto finish

:err_copy
echo 错误：robocopy 复制失败（退出码 %ERRORLEVEL%）：%SRC% -^> %TARGET%
set "EC=4" & goto finish

:err_mkdir
echo 错误：创建不了输出目录（权限或路径问题）：%TARGET%
set "EC=3" & goto finish

:err_post_desc
echo 错误：构建后校验失败，descriptor.mod 没有进 build。
set "EC=4" & goto finish

:err_post_script
echo 错误：构建后校验失败，缺少 %SCRIPT_REL%。
set "EC=4" & goto finish

:err_post_pic
echo 错误：构建后校验失败，缺少预览图 %PIC%。
set "EC=4" & goto finish

:err_post_path
echo 错误：构建后校验失败，build 里的 descriptor.mod 含 path= 字段。
set "EC=4" & goto finish

:err_post_junk
echo 错误：构建后校验失败，build 里仍有被排除的文件或隐藏目录。
set "EC=4" & goto finish

:err_post_empty
echo 错误：构建后校验失败，build 里没有文件。
set "EC=4" & goto finish

:err_no_descfile
echo 错误：找不到工坊简介文件：%DESC_FILE%
set "EC=2" & goto finish

:err_vdf_long
echo 错误：简介或 changenote 超过 cmd 单行上限（约 8000 字符），VDF 渲染不了。
echo 改用 tools/build.sh 渲染，或把简介拆短。
set "EC=4" & goto finish

:err_vdf_lines
echo 错误：VDF 行数异常（%VDF_LINES%，应为 11）：有一次换行没转义成 \n。
set "EC=4" & goto finish

:err_vdf_head
echo 错误：VDF 第一行不是 "workshopitem"：%VDF_OUT%
set "EC=4" & goto finish
