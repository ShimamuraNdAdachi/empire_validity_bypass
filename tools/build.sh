#!/usr/bin/env bash
# ============================================================
# tools/build.sh — 提取「创意工坊上传集合」到 build/
# ------------------------------------------------------------
# 源：empire_validity_bypass/          （mod 本体，即工坊上传内容）
# 出：build/empire_validity_bypass/    （只含需要上传的文件）
#     build/workshop_build_item.vdf    （steamcmd 上传参数，引号已转义、换行为真实换行）
#
# 被排除、不进 build/ 的东西：
#   .git/ .github/ .vscode/ .idea/ ...           VCS 与编辑器
#   tools/ dist/ build/ steamcmd/ tmp/           开发脚本与构建产物
#   README.md CHANGELOG.md LICENSE               仓库文档（工坊简介另存 bbcode）
#   Thumbs.db desktop.ini *.swp *.bak *.log ...  系统垃圾与临时文件
#   *.psd *.xcf *.zip *.7z ...                   美术源文件与压缩包
#   empire_validity_bypass.mod                   含 path= 的本地描述文件
#
# VDF 的 title/description/changenote/visibility/appId 来自
# tools/workshop/publish.json 与 CHANGELOG.md；物品 ID 取自
# tools/workshop/publishedfileid.txt（首次为 0）。
#
# 规则与 tools/build.bat 完全一致，两个脚本产出同一套文件。
#
# 用法：tools/build.sh [-o DIR] [-n] [--no-vdf] [--workshop-id ID] [-h]
# 退出码：0 成功 / 2 源不合规 / 3 参数或路径不安全 / 4 构建后校验失败
# ============================================================

[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -euo pipefail

MOD_ID='empire_validity_bypass'
MOD_FILE="${MOD_ID}.mod"
SCRIPT_REL='common/governments/civics/zzz_empire_validity_bypass_origins.txt'

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SRC="$REPO_ROOT/$MOD_ID"

WARNINGS=()

usage() {
    cat <<'EOF'
用法: tools/build.sh [-o DIR] [-n] [--no-vdf] [--workshop-id ID] [-h]

把本 mod 需要上传到 Steam 创意工坊的文件提取到 build/empire_validity_bypass/，
并在 build/workshop_build_item.vdf 渲染出 steamcmd 上传用的 VDF（描述与
changenote 的引号已转义、换行写成真实换行）。
.git、tools/、dist/、README.md、根目录 .mod、系统垃圾等一律不进 build。

选项:
  -o, --out DIR       构建输出根目录，默认 <仓库>/build
  -n, --dry-run       演练：产物写到临时目录，列出清单后删除，不动 build/
      --no-vdf        只做内容构建，不渲染 workshop_build_item.vdf
      --workshop-id   物品 ID，覆盖 tools/workshop/publishedfileid.txt
  -h, --help          显示本帮助

VDF 配置来自 tools/workshop/publish.json（appId / title / visibility /
descriptionFile / previewFile），缺失时用内置默认值。

退出码:
  0  成功
  2  源文件缺失或描述文件字段不合规
  3  参数错误，或输出路径不安全（会覆盖源码）
  4  构建后校验失败（含 VDF 校验）
EOF
}

die() {
    local code=$1; shift
    printf '错误：%s\n' "$*" >&2
    exit "$code"
}

warn() { WARNINGS+=("$*"); }

# ---------------------------------------------------------------- 排除规则
# 目录名命中即整棵子树跳过；文件名按“末段”匹配。
EXCLUDE_DIRS='.git .github .vs .idea .vscode .settings .svn .cache __pycache__ node_modules tools dist build steamcmd tmp temp'
EXCLUDE_REPO_FILES='README.md CHANGELOG.md LICENSE'
EXCLUDE_JUNK_NAMES='Thumbs.db desktop.ini'
EXCLUDE_JUNK_GLOBS='*.swp *.swo *~ *.bak *.tmp *.log *.orig *.rej *.pyc *.zip *.7z *.rar *.psd *.xcf'

# 返回排除原因（stdout），未命中返回 1。
path_reason() {
    local rel=$1 rest seg base
    base=${rel##*/}

    rest=$rel
    while [ -n "$rest" ]; do
        seg=${rest%%/*}
        if [ "$seg" = "$rest" ]; then rest=''; else rest=${rest#*/}; fi
        case " $EXCLUDE_DIRS " in
            *" $seg "*) printf '开发/构建/VCS 目录'; return 0 ;;
        esac
    done

    case $base in
        .gitignore|.gitattributes|.gitmodules|.editorconfig) printf '仓库配置'; return 0 ;;
        .*)                                                  printf '隐藏文件（VCS / 编辑器缓存）'; return 0 ;;
    esac
    case " $EXCLUDE_REPO_FILES " in
        *" $base "*) printf '仓库文档'; return 0 ;;
    esac
    case " $EXCLUDE_JUNK_NAMES " in
        *" $base "*) printf '系统垃圾'; return 0 ;;
    esac
    # shellcheck disable=SC2254
    case $base in
        *.swp|*.swo|*~|*.bak|*.tmp|*.log|*.orig|*.rej|*.pyc) printf '临时/备份文件'; return 0 ;;
        *.zip|*.7z|*.rar)                                     printf '压缩包'; return 0 ;;
        *.psd|*.xcf)                                          printf '美术源文件'; return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------- 描述文件
# 取 "key = "value"" 里的 value（第一个匹配）。
desc_get() {
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" | head -n 1
}

# 打印 PNG 的 "宽x高"；不是 PNG 或读不出来返回 1。
png_size() {
    local bytes w h
    bytes=$(od -An -tu1 -N24 -- "$1" 2>/dev/null) || return 1
    # shellcheck disable=SC2086
    set -- $bytes
    [ $# -ge 24 ] || return 1
    [ "${1}/${2}/${3}/${4}" = '137/80/78/71' ] || return 1   # PNG 魔数
    w=$(( ${17} * 16777216 + ${18} * 65536 + ${19} * 256 + ${20} ))
    h=$(( ${21} * 16777216 + ${22} * 65536 + ${23} * 256 + ${24} ))
    printf '%sx%s' "$w" "$h"
}

# ---------------------------------------------------------------- 参数
OUT_ARG=''
DRY_RUN=0
WANT_VDF=1
WORKSHOP_ID_ARG=''
while [ $# -gt 0 ]; do
    case $1 in
        -o|--out)
            [ $# -ge 2 ] || die 3 "$1 需要一个目录参数"
            OUT_ARG=$2; shift 2 ;;
        --out=*)
            OUT_ARG=${1#*=}; shift ;;
        -n|--dry-run)
            DRY_RUN=1; shift ;;
        --no-vdf)
            WANT_VDF=0; shift ;;
        --workshop-id)
            [ $# -ge 2 ] || die 3 "$1 需要一个 ID"
            WORKSHOP_ID_ARG=$2; shift 2 ;;
        --workshop-id=*)
            WORKSHOP_ID_ARG=${1#*=}; shift ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift; break ;;
        *)
            usage >&2
            die 3 "未知参数：$1" ;;
    esac
done

# ---------------------------------------------------------------- 路径
# 折成物理绝对路径（不创建任何东西）：路径里的 . 与 .. 会绕过纯字符串比较，
# 而目标目录随后要被 rm -rf，这一步不能省。
canon() {
    local p=$1 tail=''
    while [ ! -d "$p" ]; do
        tail="/$(basename -- "$p")$tail"
        p=$(dirname -- "$p")
        [ "$p" = '/' ] && break
    done
    printf '%s%s\n' "$(cd -- "$p" && pwd -P)" "$tail"
}

if [ -n "$OUT_ARG" ]; then
    case $OUT_ARG in
        /*) : ;;
        *)  OUT_ARG=$PWD/$OUT_ARG ;;
    esac
    OUT_ROOT=$(canon "$OUT_ARG")
else
    OUT_ROOT=$(canon "$REPO_ROOT/build")
fi
DEST=$OUT_ROOT/$MOD_ID

# ---------------------------------------------------------------- 路径安全
case $OUT_ROOT in
    /) die 3 '输出根目录不能是 /' ;;
esac

# 源码目录：既不能等于、不能在里面、也不能当它的上级
guard=$(canon "$SRC")
[ "$DEST" != "$guard" ] || die 3 "输出目录与源码目录相同：$DEST（换一个 -o）"
case $DEST in
    "$guard"/*) die 3 "输出目录位于源码目录内部：$DEST" ;;
esac
case $guard in
    "$DEST"/*) die 3 "输出目录是源码目录的上级：$DEST" ;;
esac

# 仓库根：不能等于、也不能当它的上级（放在仓库里，例如 build/，是正常的）
guard=$(canon "$REPO_ROOT")
[ "$DEST" != "$guard" ] || die 3 "输出目录与仓库根相同：$DEST（换一个 -o）"
case $guard in
    "$DEST"/*) die 3 "输出目录是仓库根的上级：$DEST" ;;
esac

# ---------------------------------------------------------------- 源校验
[ -d "$SRC" ] || die 2 "缺少 mod 目录：$SRC"
DESC="$SRC/descriptor.mod"
[ -f "$DESC" ] || die 2 "缺少描述文件：$DESC"

VER=$(desc_get version "$DESC")
MOD_NAME=$(desc_get name "$DESC")
SUPV=$(desc_get supported_version "$DESC")
PIC=$(desc_get picture "$DESC")

[ -n "$VER" ] || die 2 'descriptor.mod 里没有 version 字段'
[ -n "$MOD_NAME" ] || warn 'descriptor.mod 里没有 name 字段（工坊标题会用文件名）'
[ -n "$SUPV" ] || warn 'descriptor.mod 里没有 supported_version 字段'
[ -n "$PIC" ] || warn 'descriptor.mod 里没有 picture 字段（工坊会用默认缩略图）'

# 工坊内容里的 descriptor.mod 不能带 path=（那是本地安装专用的）
if grep -qiE '^[[:space:]]*path[[:space:]]*=' "$DESC"; then
    die 2 "descriptor.mod 含有 path= 字段：工坊上传的内容里不能有它（删掉再构建）"
fi

if [ -n "$PIC" ]; then
    if [ -f "$SRC/$PIC" ]; then
        if dims=$(png_size "$SRC/$PIC"); then
            PIC_DIMS=$dims
            [ "$dims" = '512x512' ] || warn "预览图尺寸 $dims，惯例是 512x512（正方形）"
        else
            PIC_DIMS='非 PNG 或无法解析'
        fi
    else
        die 2 "descriptor.mod 指向的预览图不存在：$SRC/$PIC"
    fi
fi

[ -f "$SRC/$SCRIPT_REL" ] || die 2 "缺少起源覆盖脚本：$SCRIPT_REL"

# 根目录 .mod 只是本地安装用，不进 build；版本号不同步时提醒
if [ -f "$REPO_ROOT/$MOD_FILE" ]; then
    ROOT_VER=$(desc_get version "$REPO_ROOT/$MOD_FILE")
    [ "$ROOT_VER" = "$VER" ] || warn "版本号不同步：descriptor.mod=$VER，$MOD_FILE=$ROOT_VER"
else
    warn "仓库根缺少 $MOD_FILE（只影响本地安装，不影响工坊上传）"
fi

# ---------------------------------------------------------------- 收集清单
WORK=$(mktemp -d "${TMPDIR:-/tmp}/evb-build.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

KEEP="$WORK/keep.txt"
SKIP="$WORK/skip.tsv"
: > "$KEEP"
: > "$SKIP"

while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if reason=$(path_reason "$rel"); then
        printf '%s\t%s\n' "$rel" "$reason" >> "$SKIP"
    elif [ -f "$SRC/$rel" ]; then
        printf '%s\n' "$rel" >> "$KEEP"
    fi
done < <(cd -- "$SRC" && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort)

[ -s "$KEEP" ] || die 2 "mod 目录里没有任何可上传的文件：$SRC"

# ---------------------------------------------------------------- 落地
if [ "$DRY_RUN" -eq 1 ]; then
    TARGET="$WORK/out"
    mkdir -p -- "$TARGET"
else
    TARGET="$DEST"
    if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
        rm -rf -- "$TARGET"
    fi
    # 清完目标目录后立刻确认源码还在：万一护栏漏了，这里要吼出来
    [ -d "$SRC" ] && [ -f "$DESC" ] || die 3 "清空目标目录后发现源码不见了：$SRC"
    mkdir -p -- "$TARGET"
fi

while IFS= read -r rel; do
    mkdir -p -- "$TARGET/$(dirname -- "$rel")"
    cp -p -- "$SRC/$rel" "$TARGET/$rel"
done < "$KEEP"

# ---------------------------------------------------------------- 构建后校验
FAILS=()

[ -f "$TARGET/descriptor.mod" ] || FAILS+=('descriptor.mod 没有进 build')
[ -f "$TARGET/$SCRIPT_REL" ]    || FAILS+=("缺少 $SCRIPT_REL")

if [ -n "$PIC" ] && [ ! -f "$TARGET/$PIC" ]; then
    FAILS+=("缺少预览图 $PIC")
fi

if grep -qiE '^[[:space:]]*path[[:space:]]*=' "$TARGET/descriptor.mod"; then
    FAILS+=('build 里的 descriptor.mod 含 path= 字段')
fi

# 根目录只允许 descriptor.mod 一个 .mod 文件
while IFS= read -r m; do
    [ -n "$m" ] || continue
    [ "${m##*/}" = 'descriptor.mod' ] || FAILS+=("build 里混入了 .mod 文件：$m")
done < <(find "$TARGET" -maxdepth 1 -name '*.mod' -print 2>/dev/null | LC_ALL=C sort)

# 不能有漏网的排除项
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    reason=$(path_reason "$rel") || continue
    FAILS+=("build 里残留 $rel（$reason）")
done < <(cd -- "$TARGET" && find . -mindepth 1 | sed 's|^\./||' | LC_ALL=C sort)

EXPECTED_COUNT=$(wc -l < "$KEEP" | tr -d ' ')
ACTUAL_COUNT=$(find "$TARGET" -type f | wc -l | tr -d ' ')
[ "$EXPECTED_COUNT" = "$ACTUAL_COUNT" ] ||
    FAILS+=("文件数不一致：源 $EXPECTED_COUNT 个，build $ACTUAL_COUNT 个")

if [ ${#FAILS[@]} -gt 0 ]; then
    printf '构建后校验失败：\n' >&2
    for f in "${FAILS[@]}"; do printf '  - %s\n' "$f" >&2; done
    exit 4
fi

# ---------------------------------------------------------------- 创意工坊 VDF
# steamcmd 的上传参数只能写在 VDF 里（appid / contentfolder / previewfile /
# title / description / changenote / visibility），所以这里直接渲染一份出来。
# publish.json 是扁平键值，下面只做最小提取，不是通用 JSON 解析。
json_get() {
    local raw
    [ -f "$1" ] || return 0
    raw=$(grep -m 1 "\"$2\"" "$1" 2>/dev/null | sed 's/^[^:]*:[[:space:]]*//') || return 0
    [ -n "$raw" ] || return 0
    raw=${raw%,}
    raw=$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case $raw in
        \"*\") raw=${raw#\"}; raw=${raw%\"} ;;
    esac
    printf '%s' "$raw"
}

# 单行转义：\ → \\， " → \"（不动换行）
vdf_escape_text() {
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
# 换行处理：raw（默认）保留真实换行；escape 折成字面量 \n。
# steamcmd 不还原字面量 \n，写进去的 "\n" 会原样印在工坊页面上
# （1.2.0 那次上传就是这么坏的），所以默认 raw。
vdf_fold_newlines() {
    if [ "$NEWLINE_MODE" = 'escape' ]; then
        awk 'BEGIN { ORS = "" } NR > 1 { printf "\\n" } { printf "%s", $0 }'
    else
        cat
    fi
}
# 占位符替换 → 转义 → 换行处理
vdf_escape_file() {
    sed -e 's/\r$//' \
        -e "s|{{SUPPORTED_VERSION}}|$SUPV|g" -e "s|{{VERSION}}|$VER|g" "$1" \
        | vdf_escape_text | vdf_fold_newlines
}

VDF_OUT="$(dirname -- "$TARGET")/workshop_build_item.vdf"
VDF_WRITTEN=0
if [ "$WANT_VDF" -eq 0 ]; then
    :
else
    PUB_JSON="$REPO_ROOT/tools/workshop/publish.json"

    APP_ID=$(json_get "$PUB_JSON" appId)
    [ -n "$APP_ID" ] || APP_ID=281990

    case $(json_get "$PUB_JSON" visibility) in
        0|public)   VIS=0 ;;
        1|friends)  VIS=1 ;;
        2|private)  VIS=2 ;;
        *)          VIS=3 ;;   # 默认 unlisted，自测阶段最稳
    esac

    TITLE=$(json_get "$PUB_JSON" title)
    [ -n "$TITLE" ] || TITLE=$MOD_NAME

    PREVIEW_REL=$(json_get "$PUB_JSON" previewFile)
    [ -n "$PREVIEW_REL" ] || PREVIEW_REL=$PIC

    DESC_FILE=$(json_get "$PUB_JSON" descriptionFile)
    [ -n "$DESC_FILE" ] || DESC_FILE=tools/workshop/description.bbcode
    case $DESC_FILE in
        /*) : ;;
        *)  DESC_FILE="$REPO_ROOT/$DESC_FILE" ;;
    esac
    [ -f "$DESC_FILE" ] || die 2 "找不到工坊简介文件：$DESC_FILE"

    # 物品 ID：命令行 > tools/workshop/publishedfileid.txt > 0（首次上传）
    PUB_ID=$WORKSHOP_ID_ARG
    if [ -z "$PUB_ID" ] && [ -f "$REPO_ROOT/tools/workshop/publishedfileid.txt" ]; then
        PUB_ID=$(tr -dc '0-9' < "$REPO_ROOT/tools/workshop/publishedfileid.txt")
    fi
    [ -n "$PUB_ID" ] || PUB_ID=0

    # 换行写法：raw（默认，写真实换行）/ escape（写字面量 \n）
    NEWLINE_MODE=$(json_get "$PUB_JSON" newlineMode)
    [ "$NEWLINE_MODE" = 'escape' ] || NEWLINE_MODE=raw

    TITLE_ESC=$(printf '%s' "$TITLE" | vdf_escape_text)
    DESC_ESC=$(vdf_escape_file "$DESC_FILE")

    CFG_NOTE=$(json_get "$PUB_JSON" changenote)
    if [ -n "$CFG_NOTE" ]; then
        NOTE_ESC=$(printf '%s' "$CFG_NOTE" | sed 's/\\n/\n/g' | vdf_escape_text | vdf_fold_newlines)
    else
        # 从 CHANGELOG 取当前版本那一节的项目符号；缩进的续行接回上一条
        NOTE_ESC=$(awk -v want="$VER" '
            function emit() { for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? "\n" : ""), item[i] }
            /^## / {
                if (state == 1) { emit(); state = 2 }
                else if (state == 0 && index($0, "## " want) == 1) { state = 1 }
                next
            }
            state == 1 && /^- / { n++; item[n] = substr($0, 3); next }
            state == 1 && /^[ \t]+[^ \t]/ { s = $0; sub(/^[ \t]+/, "", s); if (n > 0) item[n] = item[n] " " s; next }
            END { if (state == 1) emit() }
        ' "$REPO_ROOT/CHANGELOG.md" | vdf_escape_text | vdf_fold_newlines)
        [ -n "$NOTE_ESC" ] || warn "CHANGELOG 里没有 $VER 的条目，changenote 为空"
    fi

    CONTENT_ESC=$(printf '%s' "$TARGET" | vdf_escape_text)
    PREVIEW_ESC=$(printf '%s' "$TARGET/$PREVIEW_REL" | vdf_escape_text)

    {
        printf '"workshopitem"\n{\n'
        printf '\t"appid"\t\t"%s"\n' "$APP_ID"
        printf '\t"publishedfileid"\t\t"%s"\n' "$PUB_ID"
        printf '\t"contentfolder"\t\t"%s"\n' "$CONTENT_ESC"
        printf '\t"previewfile"\t\t"%s"\n' "$PREVIEW_ESC"
        printf '\t"title"\t\t"%s"\n' "$TITLE_ESC"
        printf '\t"description"\t\t"%s"\n' "$DESC_ESC"
        printf '\t"changenote"\t\t"%s"\n' "$NOTE_ESC"
        printf '\t"visibility"\t\t"%s"\n' "$VIS"
        printf '}\n'
    } > "$VDF_OUT"
    VDF_WRITTEN=1

    # 校验：8 个字段都在、花括号收尾、未转义引号 34 个；
    # raw 模式下不允许再出现字面量 \n（那正是简介显示成一行 "\n" 的原因）
    head -n 1 "$VDF_OUT" | grep -q '^"workshopitem"$' ||
        die 4 'VDF 第一行不是 "workshopitem"'
    for k in appid publishedfileid contentfolder previewfile title description changenote visibility; do
        grep -q "\"$k\"" "$VDF_OUT" || die 4 "VDF 缺少字段：$k"
    done
    [ "$(tail -n 1 "$VDF_OUT")" = '}' ] || die 4 'VDF 最后一行不是 }'
    Q_TOTAL=$(grep -oF '"' "$VDF_OUT" 2>/dev/null | wc -l | tr -d ' ' || true)
    Q_ESC=$(grep -oF '\"' "$VDF_OUT" 2>/dev/null | wc -l | tr -d ' ' || true)
    if [ $((Q_TOTAL - Q_ESC)) -ne 34 ]; then
        die 4 "VDF 引号未配对（未转义引号 $((Q_TOTAL - Q_ESC)) 个，应为 34）"
    fi
    if [ "$NEWLINE_MODE" != 'escape' ]; then
        DESC_BLOCK=$(awk '
            index($0, "\t\"description\"") == 1 { f = 1 }
            index($0, "\t\"changenote\"") == 1 { f = 0 }
            f
        ' "$VDF_OUT")
        if printf '%s\n' "$DESC_BLOCK" | grep -q '\\n'; then
            die 4 '简介里还有字面量 \n：换行没有写成真实换行'
        fi
    fi
fi

# ---------------------------------------------------------------- 报告
SIZE_KB=$(du -sk "$TARGET" | awk '{print $1}')
SIZE_HUMAN=$(awk -v k="$SIZE_KB" 'BEGIN { if (k >= 1024) printf "%.1f MB", k / 1024; else printf "%d KB", k }')

# 仓库根这一层没上传的东西，只用于说明
ROOT_SKIP=''
for e in "$REPO_ROOT"/* "$REPO_ROOT"/.[!.]*; do
    [ -e "$e" ] || continue
    n=${e##*/}
    [ "$n" = "$MOD_ID" ] && continue
    [ "$n" = 'build' ] && continue
    ROOT_SKIP="$ROOT_SKIP$n, "
done
ROOT_SKIP=${ROOT_SKIP%, }

printf '\n'
if [ "$DRY_RUN" -eq 1 ]; then
    printf '=== 演练完成（未写入 build/） ===\n'
else
    printf '=== 构建完成 ===\n'
fi
printf 'mod       ：%s\n' "$MOD_NAME"
printf '版本      ：%s\n' "$VER"
printf '游戏版本  ：%s\n' "${SUPV:-（未声明）}"
[ -n "${PIC_DIMS:-}" ] && printf '预览图    ：%s（%s）\n' "$PIC" "$PIC_DIMS"
printf '源目录    ：%s\n' "$SRC"
printf '输出目录  ：%s\n' "$TARGET"
printf '文件数    ：%s\n' "$ACTUAL_COUNT"
printf '大小      ：%s\n' "$SIZE_HUMAN"

printf '\n文件清单：\n'
while IFS= read -r rel; do
    printf '  %s\n' "$rel"
done < <(cd -- "$TARGET" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)

printf '\n已排除：\n'
if [ -s "$SKIP" ]; then
    while IFS=$'\t' read -r rel reason; do
        printf '  %-48s %s\n' "$rel" "$reason"
    done < "$SKIP"
else
    printf '  （mod 目录里没有需要剔除的文件）\n'
fi
[ -n "$ROOT_SKIP" ] && printf '  %s\n' "仓库根未上传：$ROOT_SKIP"

if [ ${#WARNINGS[@]} -gt 0 ]; then
    printf '\n提醒：\n'
    for w in "${WARNINGS[@]}"; do printf '  - %s\n' "$w"; done
fi

if [ "$DRY_RUN" -eq 1 ]; then
    printf '\n演练结束：%s 已丢弃。\n' "$TARGET"
else
    printf '\n上传根目录（contentfolder）：%s\n' "$TARGET"
    printf '启动器：Mods → 选中本 mod → Upload Mod；或把上面的目录当作 steamcmd 的 contentfolder。\n'
fi

if [ "$VDF_WRITTEN" -eq 1 ]; then
    printf '创意工坊 VDF：%s\n' "$VDF_OUT"
    printf '  物品 ID %s / visibility %s / 描述来自 %s\n' \
        "$PUB_ID" "$VIS" "${DESC_FILE#"$REPO_ROOT"/}"
    if [ "$PUB_ID" = '0' ]; then
        printf '  首次上传（publishedfileid=0）；上传成功后把物品 ID 写进 tools/workshop/publishedfileid.txt。\n'
    fi
    printf 'steamcmd +login <账号> +workshop_build_item "%s" +quit\n' "$VDF_OUT"
fi

