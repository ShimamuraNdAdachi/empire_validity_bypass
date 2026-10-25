#!/usr/bin/env bash
# ============================================================
# tools/build.sh — 提取「创意工坊上传集合」到 build/
# ------------------------------------------------------------
# 源：empire_validity_bypass/          （mod 本体，即工坊上传内容）
# 出：build/empire_validity_bypass/    （只含需要上传的文件）
#
# 被排除、不进 build/ 的东西：
#   .git/ .github/ .vscode/ .idea/ ...           VCS 与编辑器
#   tools/ dist/ build/ steamcmd/ tmp/           开发脚本与构建产物
#   README.md CHANGELOG.md LICENSE               仓库文档（工坊简介另存 bbcode）
#   Thumbs.db desktop.ini *.swp *.bak *.log ...  系统垃圾与临时文件
#   *.psd *.xcf *.zip *.7z ...                   美术源文件与压缩包
#   empire_validity_bypass.mod                   含 path= 的本地描述文件
#
# 规则与 tools/build.bat 完全一致，两个脚本产出同一套文件。
#
# 用法：tools/build.sh [-o DIR] [-n] [-h]
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
用法: tools/build.sh [-o DIR] [-n] [-h]

把本 mod 需要上传到 Steam 创意工坊的文件提取到 build/empire_validity_bypass/。
.git、tools/、dist/、README.md、根目录 .mod、系统垃圾等一律不进 build。

选项:
  -o, --out DIR   构建输出根目录，默认 <仓库>/build
  -n, --dry-run   演练：产物写到临时目录，列出清单后删除，不动 build/
  -h, --help      显示本帮助

退出码:
  0  成功
  2  源文件缺失或描述文件字段不合规
  3  参数错误，或输出路径不安全（会覆盖源码）
  4  构建后校验失败
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
while [ $# -gt 0 ]; do
    case $1 in
        -o|--out)
            [ $# -ge 2 ] || die 3 "$1 需要一个目录参数"
            OUT_ARG=$2; shift 2 ;;
        --out=*)
            OUT_ARG=${1#*=}; shift ;;
        -n|--dry-run)
            DRY_RUN=1; shift ;;
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
