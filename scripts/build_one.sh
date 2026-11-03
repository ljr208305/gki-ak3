#!/usr/bin/env bash
# ============================================================================
#  F:\GKI  本地 AK3 内核构建引擎（单设备）
#  固定组合：BakaSU 35257 + SUSFS 2.2.0 + 内核后缀「念想」
#  用法：bash build_one.sh --file oneplus_ace6_b [--suffix 念想] [--dry-run]
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GKI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ------------------------- 默认参数 -------------------------
FILE="${FILE:-}"
SUFFIX="${SUFFIX:-念想}"
KPM_MODE="${KPM_MODE:-N/A}"                  # N/A | KPM | KPN
FEATURE_PROFILE="${FEATURE_PROFILE:-core}"   # core | full
FEATURE_FILE="${FEATURE_FILE:-}"
DRY_RUN="${DRY_RUN:-0}"
SAVE_SOURCE="${SAVE_SOURCE:-0}"
CCACHE_ON="${CCACHE_ON:-1}"
JOBS="${JOBS:-}"
WORK_ROOT="${WORK_ROOT:-$HOME/gki-build}"
SRC_ROOT="${SRC_ROOT:-$WORK_ROOT/src}"
OUT_DIR="${OUT_DIR:-$GKI_ROOT/out}"
LOG_DIR="${LOG_DIR:-$GKI_ROOT/logs}"
PATCH_DIR="${PATCH_DIR:-$GKI_ROOT/patches}"
BAKASU_REPO="${BAKASU_REPO:-https://github.com/Baka-SU/BakaSU}"
BAKASU_COMMIT="${BAKASU_COMMIT:-516d3e87fbc986ccefdde2c2765f1700612441a9}"
SUSFS_VERSION="${SUSFS_VERSION:-2.2.0}"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
AK3_REPO="${AK3_REPO:-https://github.com/Numbersf/AnyKernel3}"
REPO_URL="${REPO_URL:-}"
MANIFEST_OWNERS="${MANIFEST_OWNERS:-OnePlusOSS/kernel_manifest Numbersf/kernel_manifest Numbersf/Kernel_Manifest_Appendix}"

# ------------------------- 日志 -------------------------
mkdir -p "$LOG_DIR" "$OUT_DIR"
LOGFILE="$LOG_DIR/build-${FILE:-init}-$(date +%Y%m%d-%H%M%S).log"
C_INFO=$'\033[1;36m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_STEP=$'\033[1;35m'; C_END=$'\033[0m'

log()  { local m="[$(date +%H:%M:%S)] $*"; printf '%s%s%s\n' "$C_INFO" "$m" "$C_END"; printf '%s\n' "$m" >>"$LOGFILE"; }
ok()   { local m="[$(date +%H:%M:%S)] OK $*"; printf '%s%s%s\n' "$C_OK" "$m" "$C_END"; printf '%s\n' "$m" >>"$LOGFILE"; }
warn() { local m="[$(date +%H:%M:%S)] !  $*"; printf '%s%s%s\n' "$C_WARN" "$m" "$C_END" >&2; printf '%s\n' "$m" >>"$LOGFILE"; }
die()  { local m="[$(date +%H:%M:%S)] XX $*"; printf '%s%s%s\n' "$C_ERR" "$m" "$C_END" >&2; printf '%s\n' "$m" >>"$LOGFILE"; exit 1; }
step() { printf '\n%s===== %s =====%s\n' "$C_STEP" "$*" "$C_END"; printf '===== %s =====\n' "$*" >>"$LOGFILE"; }
dry()  { [ "$DRY_RUN" = "1" ]; }
trap 'rc=$?; if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then printf "\n[EXIT %s] 见日志 %s\n" "$rc" "$LOGFILE" >&2; fi' EXIT

# ------------------------- 参数解析 -------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --file|-f)          FILE="$2"; shift 2 ;;
    --suffix|-s)        SUFFIX="$2"; shift 2 ;;
    --kpm)              KPM_MODE="$2"; shift 2 ;;
    --profile)          FEATURE_PROFILE="$2"; shift 2 ;;
    --feature-file)     FEATURE_FILE="$2"; shift 2 ;;
    --jobs|-j)          JOBS="$2"; shift 2 ;;
    --dry-run)          DRY_RUN=1; shift ;;
    --save-source)      SAVE_SOURCE=1; shift ;;
    --no-ccache)        CCACHE_ON=0; shift ;;
    --no-sync)          RESYNC=0; shift ;;
    --no-share-src)     SHARE_SRC=0; shift ;;
    -h|--help)          sed -n '2,7p' "$0"; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
done
[ -n "$FILE" ] || die "缺少 --file（机型 id 见 config/devices.json）"
LOGFILE="$LOG_DIR/build-${FILE}-$(date +%Y%m%d-%H%M%S).log"

SHARE_SRC="${SHARE_SRC:-1}"
CHIP_HINT="$(awk -F'\t' -v f="$FILE" '$1==f{print $3; exit}' "$GKI_ROOT/config/manifest-map.tsv" 2>/dev/null | sed 's|.*/||' || true)"
if [ "$SHARE_SRC" = "1" ] && [ -n "$CHIP_HINT" ]; then
  # 同芯片机型共用一份源码，编第二台不用重拉几十 G
  SRC="$SRC_ROOT/$CHIP_HINT"
else
  SRC="$SRC_ROOT/$FILE"
fi
KP="$SRC/kernel_platform"
AK3_WORK="$WORK_ROOT/AnyKernel3"
BAKASU_DIR="$WORK_ROOT/bakasu"
SUSFS_DIR="$WORK_ROOT/susfs4ksu"
REPO_BIN=""
KSU_CODE=0; KSU_TAG="unknown"; KSU_SHORT="unknown"
KERNEL_REPOS=""; KMI=""; KVER="0.0.0"

repo_sync_with_retry() {
  local tries="${1:-3}" n=1
  while [ "$n" -le "$tries" ]; do
    log "repo sync 第 $n/$tries 次"
    if "$REPO_BIN" sync -c -j"$JOBS" --no-clone-bundle --no-tags --force-sync; then
      return 0
    fi
    warn "第 $n 次 sync 没走完"
    n=$((n + 1))
    if [ "$n" -le "$tries" ]; then
      log "30 秒后重试（已下载的不会重下）"
      sleep 30
    fi
  done
  return 1
}

# ============================================================================
step "0/9 预检  FILE=$FILE  SUFFIX=$SUFFIX  KPM=$KPM_MODE  DRY_RUN=$DRY_RUN"
log "工程根 : $GKI_ROOT"
log "源码区 : $SRC"
log "产物区 : $OUT_DIR"
log "日志   : $LOGFILE"

if [ -z "$JOBS" ]; then
  MEM_MB="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 8192)"
  BY_MEM="$(( MEM_MB / 1900 ))"
  if [ "$BY_MEM" -lt 1 ]; then BY_MEM=1; fi
  JOBS="$(nproc --all 2>/dev/null || echo 4)"
  if [ "$JOBS" -gt "$BY_MEM" ]; then JOBS="$BY_MEM"; fi
  log "内存 ${MEM_MB}MB，自动并发 $JOBS（想硬来就 --jobs N）"
fi

for c in git curl unzip zip python3 make patch awk find sed; do
  command -v "$c" >/dev/null 2>&1 || die "缺少命令: $c（跑 scripts/env_check.sh 看安装清单）"
done
if ! command -v ccache >/dev/null 2>&1; then
  if [ "$CCACHE_ON" = "1" ]; then
    warn "没有 ccache，这次不带缓存编译"
    CCACHE_ON=0
  fi
fi

if command -v repo >/dev/null 2>&1; then
  REPO_BIN="$(command -v repo)"
else
  mkdir -p "$WORK_ROOT/bin"
  if [ -x "$WORK_ROOT/bin/repo" ]; then
    REPO_BIN="$WORK_ROOT/bin/repo"
  else
    log "没有 repo 工具，先试 storage.googleapis.com"
    if ! dry; then
      if curl -fsSL --max-time 20 https://storage.googleapis.com/git-repo-downloads/repo -o "$WORK_ROOT/bin/repo" 2>/dev/null; then
        chmod +x "$WORK_ROOT/bin/repo"
        ok "repo 已下载到 $WORK_ROOT/bin/repo"
      else
        warn "storage.googleapis.com 不通"
        log "改用 GitHub 上的 repo launcher"
        curl -fsSL --max-time 30 https://raw.githubusercontent.com/GerritCodeReview/git-repo/main/repo -o "$WORK_ROOT/bin/repo" \
          || die "repo 工具取不到：先在 WSL 里跑 sudo apt-get install -y repo"
        chmod +x "$WORK_ROOT/bin/repo"
        ok "repo launcher 已就位"
      fi
    fi
    REPO_BIN="$WORK_ROOT/bin/repo"
  fi
fi
export PATH="$HOME/.local/bin:$WORK_ROOT/bin:$PATH"

if [ -z "$REPO_URL" ] && ! dry; then
  if ! curl -sfI --max-time 6 https://gerrit.googlesource.com/git-repo >/dev/null 2>&1; then
    REPO_URL="https://github.com/GerritCodeReview/git-repo"
    warn "gerrit.googlesource.com 不通，repo 工具改走 GitHub 镜像"
  fi
fi

if ! git config --global user.name >/dev/null 2>&1; then
  git config --global user.name "gki-builder"
fi
if ! git config --global user.email >/dev/null 2>&1; then
  git config --global user.email "gki-builder@localhost"
fi
# 弱网保护：低速连接 60 秒自动断掉重连，避免 repo sync 无限挂起
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60
git config --global http.postBuffer 524288000

# ============================================================================
step "1/9 解析源码清单"
MANIFEST_REPO=""; MANIFEST_BRANCH=""
MAP_FILE="$GKI_ROOT/config/manifest-map.tsv"
if [ -f "$MAP_FILE" ]; then
  MAPLINE="$(awk -F'\t' -v f="$FILE" '$1==f{print $2 "\t" $3; exit}' "$MAP_FILE" 2>/dev/null || true)"
  if [ -n "$MAPLINE" ]; then
    MANIFEST_REPO="$(printf '%s\n' "$MAPLINE" | cut -f1)"
    MANIFEST_BRANCH="$(printf '%s\n' "$MAPLINE" | cut -f2)"
  fi
fi
if [ -n "$MANIFEST_REPO" ]; then
  ok "清单映射命中: $MANIFEST_REPO @ $MANIFEST_BRANCH ($FILE.xml)"
else
  warn "映射表里没有 $FILE，走在线探测（慢）"
  CACHE_FILE="$GKI_ROOT/config/manifest-cache.tsv"
  if [ -f "$CACHE_FILE" ]; then
    CACHED="$(awk -F'\t' -v f="$FILE" '$1==f{print $2 " " $3; exit}' "$CACHE_FILE" 2>/dev/null || true)"
    if [ -n "$CACHED" ]; then
      C_REPO="${CACHED%% *}"; C_BRANCH="${CACHED#* }"
      if curl -sfI --max-time 8 "https://raw.githubusercontent.com/$C_REPO/$C_BRANCH/$FILE.xml" >/dev/null 2>&1; then
        MANIFEST_REPO="$C_REPO"; MANIFEST_BRANCH="$C_BRANCH"
        ok "清单缓存命中: $MANIFEST_REPO @ $MANIFEST_BRANCH"
      fi
    fi
  fi
  if [ -z "$MANIFEST_REPO" ]; then
    for r in $MANIFEST_OWNERS; do
      for b in $(timeout 40 git ls-remote --heads "https://github.com/$r.git" 2>/dev/null | sed 's|.*refs/heads/||'); do
        if curl -sfI --max-time 10 "https://raw.githubusercontent.com/$r/$b/$FILE.xml" >/dev/null 2>&1; then
          MANIFEST_REPO="$r"; MANIFEST_BRANCH="$b"; break 2
        fi
      done
    done
    if [ -n "$MANIFEST_REPO" ]; then
      printf '%s\t%s\t%s\n' "$FILE" "$MANIFEST_REPO" "$MANIFEST_BRANCH" >> "$CACHE_FILE"
    fi
  fi
fi
[ -n "$MANIFEST_REPO" ] || die "映射表和三个清单仓库里都没有 $FILE.xml，核对机型 id"
ok "清单: $MANIFEST_REPO @ $MANIFEST_BRANCH ($FILE.xml)"

# ============================================================================
step "2/9 同步内核源码"
if [ -d "$SRC/.repo" ] && [ -f "$KP/common/Makefile" ]; then
  if [ "${RESYNC:-1}" = "0" ]; then
    log "已有源码，跳过 sync（--no-sync）"
  else
    log "已有源码，增量 repo sync 补全缺失项目"
    cd "$SRC"
    if ! dry; then
      # 共用源码时可能是别的机型的清单，先切过来
      CUR_XML="$(basename "$(readlink -f "$SRC/.repo/manifest.xml" 2>/dev/null)" 2>/dev/null || true)"
      if [ -n "$CUR_XML" ] && [ "$CUR_XML" != "$FILE.xml" ]; then
        log "切换清单 $CUR_XML -> $FILE.xml"
        INIT_ARGS2=(-u "https://github.com/$MANIFEST_REPO.git" -b "$MANIFEST_BRANCH" -m "$FILE.xml" --depth=1 --no-clone-bundle --no-tags)
        if [ -n "$REPO_URL" ]; then INIT_ARGS2+=("--repo-url=$REPO_URL"); fi
        ( cd "$SRC" && "$REPO_BIN" init "${INIT_ARGS2[@]}" ) || die "切换清单失败，删掉 $SRC 重来"
      fi
      # 清掉上一轮打的补丁，保证这次从干净源码起
      if [ -d "$KP/common/.git" ]; then
        ( cd "$KP/common" && git reset --hard -q HEAD && git clean -fdq ) >/dev/null 2>&1 || true
      fi
      repo_sync_with_retry 5 || die "repo sync 五次都没完成，检查网络后重跑（增量续传）"
    fi
    ok "增量同步完成"
  fi
else
  mkdir -p "$SRC"
  cd "$SRC"
  if dry; then
    log "[dry] repo init -u https://github.com/$MANIFEST_REPO.git -b $MANIFEST_BRANCH -m $FILE.xml ${REPO_URL:+(--repo-url=$REPO_URL)}"
    log "[dry] repo sync -c -j$JOBS"
  else
    INIT_ARGS=(-u "https://github.com/$MANIFEST_REPO.git" -b "$MANIFEST_BRANCH" -m "$FILE.xml"
               --depth=1 --no-clone-bundle --no-tags)
    if [ -n "$REPO_URL" ]; then INIT_ARGS+=("--repo-url=$REPO_URL"); fi
    "$REPO_BIN" init "${INIT_ARGS[@]}"
    sed -i -e '/prebuilts\/asuite"/{/ks-kernel\.lnx\.5\.0\.r3-rel/d}' \
           -e '/tools\/tradefederation\/prebuilts"/{/ks-kernel\.lnx\.5\.0\.r3-rel/d}' \
           ".repo/manifests/$FILE.xml"
    log "repo sync 开始（几十 G，卡住会自动重连）"
    repo_sync_with_retry 5 || die "repo sync 五次都没完成，检查网络后重跑（增量续传）"
  fi
  ok "源码同步完成"
fi

# ============================================================================
step "3/9 剥 ABI 保护与构建审查"
if [ -d "$KP" ]; then
  KERNEL_REPOS="$(find "$SRC" -name build.config.msm.common -printf '%h\n' 2>/dev/null | head -1 | sed "s|^$SRC/||" | cut -d/ -f2 || true)"
fi
log "KERNEL_REPOS=${KERNEL_REPOS:-none}"
if ! dry; then
  for d in "$KP/common" "$KP/$KERNEL_REPOS"; do
    if [ -d "$d" ]; then
      if [ -f "$d/BUILD.bazel" ]; then
        sed -i '/"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",$/d' "$d/BUILD.bazel" || true
      fi
      rm -f "$d"/android/abi_gki_protected_exports_* 2>/dev/null || true
    fi
  done
  if [ -f "$KP/common/build.config.gki" ] && grep -q 'check_defconfig' "$KP/common/build.config.gki"; then
    sed -i 's/check_defconfig//' "$KP/common/build.config.gki"
  fi
  if [ -f "$KP/build/kernel/kleaf/common_kernels.bzl" ]; then
    sed -i 's/check_defconfig = None,/check_defconfig = "disabled",/' "$KP/build/kernel/kleaf/common_kernels.bzl" 2>/dev/null || true
  fi
fi

# ============================================================================
step "4/9 识别 KMI / 内核版本"
for f in "$KP/common/build.config.constants" "$KP/common/build.config.common"; do
  if [ -f "$f" ]; then
    KMI="$(grep -m1 '^BRANCH=' "$f" | cut -d= -f2 || true)"
    if [ -n "$KMI" ]; then break; fi
  fi
done
if [ -z "$KMI" ] && [ -n "$KERNEL_REPOS" ] && [ -f "$KP/$KERNEL_REPOS/android/ACK_SHA" ]; then
  KMI="$(grep -m1 '^android' "$KP/$KERNEL_REPOS/android/ACK_SHA" | cut -d- -f1,2 || true)"
fi
if [ -z "$KMI" ]; then
  if dry; then
    KMI="android15-6.6"
    log "[dry] 没源码，KMI 假设 $KMI"
  else
    die "识别不出 KMI（build.config.* 没有 BRANCH=）"
  fi
fi
KANDROID_VERSION="${KMI%-*}"
KERNEL_VERSION="${KMI#*-}"
KVER="$(awk '/^VERSION =/{v=$3}/^PATCHLEVEL =/{p=$3}/^SUBLEVEL =/{s=$3}END{print v"."p"."s}' "$KP/common/Makefile" 2>/dev/null || true)"
[ -n "$KVER" ] || KVER="0.0.0"
ok "KMI=$KMI  内核=$KVER  后缀=$SUFFIX"

# ============================================================================
step "5/9 接入 BakaSU（固定 commit）"
if [ ! -d "$BAKASU_DIR/.git" ]; then
  if dry; then
    log "[dry] git clone $BAKASU_REPO $BAKASU_DIR"
  else
    git clone "$BAKASU_REPO" "$BAKASU_DIR"
  fi
fi
if dry; then
  KSU_CODE=35257; KSU_TAG="v4.2.0-rc3"; KSU_SHORT="516d3e87"
  log "[dry] checkout $BAKASU_COMMIT（版本号按 35257 假设）"
else
  git -C "$BAKASU_DIR" fetch --all --tags --prune
  git -C "$BAKASU_DIR" checkout -f "$BAKASU_COMMIT"
  KSU_COMMITS="$(git -C "$BAKASU_DIR" rev-list --count HEAD)"
  KSU_CODE="$((30000 + KSU_COMMITS + 700))"
  KSU_TAG="$(git -C "$BAKASU_DIR" describe --abbrev=0 --tags 2>/dev/null || echo unknown)"
  KSU_SHORT="$(git -C "$BAKASU_DIR" rev-parse --short=8 HEAD)"
  log "BakaSU 提交 $KSU_SHORT  版本号 $KSU_CODE  标签 $KSU_TAG"
  if [ "$KSU_CODE" != "35257" ]; then
    warn "BakaSU 版本号是 $KSU_CODE，不是 35257（commit 或历史被改过）"
  fi
  mkdir -p "$KP/common/drivers"
  ln -sfn "$BAKASU_DIR/kernel" "$KP/common/drivers/kernelsu"
  if ! grep -q 'kernelsu' "$KP/common/drivers/Makefile"; then
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KP/common/drivers/Makefile"
  fi
  if ! grep -q 'drivers/kernelsu/Kconfig' "$KP/common/drivers/Kconfig"; then
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KP/common/drivers/Kconfig"
  fi
  ok "BakaSU 已挂到 common/drivers/kernelsu"
fi

# ============================================================================
step "6/9 接入 SUSFS"
LOCAL_SUSFS="$PATCH_DIR/susfs/$KMI"
SUSFS_PATCH=""
# 兼容旧的按版本命名的目录
if [ ! -f "$LOCAL_SUSFS/50_add_susfs_in_gki-$KMI.patch" ] && [ -f "$PATCH_DIR/susfs-v$SUSFS_VERSION/$KMI/50_add_susfs_in_gki-$KMI.patch" ]; then
  LOCAL_SUSFS="$PATCH_DIR/susfs-v$SUSFS_VERSION/$KMI"
fi
if [ -f "$LOCAL_SUSFS/50_add_susfs_in_gki-$KMI.patch" ]; then
  SUSFS_PATCH="$LOCAL_SUSFS/50_add_susfs_in_gki-$KMI.patch"
  log "用本地补丁: $SUSFS_PATCH"
  if ! dry; then
    cp "$SUSFS_PATCH" "$KP/common/"
    cp "$LOCAL_SUSFS"/fs/* "$KP/common/fs/"
    cp "$LOCAL_SUSFS"/include/linux/* "$KP/common/include/linux/"
  fi
else
  warn "本地没有 $KMI 的 $SUSFS_VERSION 补丁，回退上游 gki-$KMI 分支"
  if [ ! -d "$SUSFS_DIR/.git" ]; then
    if dry; then log "[dry] git clone $SUSFS_REPO"; else git clone "$SUSFS_REPO" "$SUSFS_DIR"; fi
  fi
  if ! dry; then
    git -C "$SUSFS_DIR" fetch --all --tags --prune 2>/dev/null || true
    git -C "$SUSFS_DIR" checkout -f "origin/gki-$KMI" 2>/dev/null || die "上游没有分支 gki-$KMI"
    SUSFS_PATCH="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-$KMI.patch"
    [ -f "$SUSFS_PATCH" ] || die "上游 gki-$KMI 里没有 $KMI 补丁"
    cp "$SUSFS_PATCH" "$KP/common/"
    cp "$SUSFS_DIR"/kernel_patches/fs/* "$KP/common/fs/" 2>/dev/null || true
    cp "$SUSFS_DIR"/kernel_patches/include/linux/* "$KP/common/include/linux/" 2>/dev/null || true
    log "上游 SUSFS 版本: $(grep -m1 '^#define SUSFS_VERSION' "$KP/common/include/linux/susfs.h" 2>/dev/null | sed 's/.*"\(.*\)"/\1/' || echo unknown)"
  fi
fi

if ! dry; then
  cd "$KP/common"
  PB_NAME="$(basename "$SUSFS_PATCH")"
  APPLIED=0
  # depth=1 克隆没有 blob 历史，3-way merge 用不了；先补全 common 的 git 历史
  if [ -d .git ] && [ -f .git/shallow ]; then
    log "补全 common 的 git 历史（3-way merge 需要历史 blob）"
    git fetch --unshallow 2>/dev/null || true
    [ -f .git/shallow ] && git fetch --unshallow --filter=blob:none 2>/dev/null || true
  fi
  # 优先 3-way merge，它能自动处理上下文行号偏移
  APPLY_LOG="/tmp/susfs-apply.log"
  if [ -d .git ]; then
    if git apply --3way --whitespace=nowarn "$PB_NAME" >"$APPLY_LOG" 2>&1; then
      APPLIED=1
      log "git apply --3way 成功"
    else
      log "3-way 失败，末尾输出："
      tail -8 "$APPLY_LOG" 2>/dev/null || true
    fi
  fi
  if [ "$APPLIED" = "0" ]; then
    if patch -p1 --forward --dry-run < "$PB_NAME" >/dev/null 2>&1; then
      patch -p1 --forward < "$PB_NAME" && APPLIED=1
    fi
  fi
  if [ "$APPLIED" = "0" ]; then
    log "严格匹配失败，用 fuzz=3 模糊匹配（厂商源码和 GKI 有偏移）"
    if patch -p1 --forward --fuzz=3 --dry-run < "$PB_NAME" >/dev/null 2>&1; then
      patch -p1 --forward --fuzz=3 < "$PB_NAME" && APPLIED=1
    fi
  fi
  if [ "$APPLIED" = "0" ]; then
    log "fuzz 也不行，试 git apply --3way"
    git apply --3way --whitespace=nowarn "$PB_NAME" && APPLIED=1
  fi
  REJS="$(find . -name '*.rej' -newermt '-10 minutes' 2>/dev/null | head -10)"
  if [ -n "$REJS" ]; then
    warn "有打不进去的补丁块："
    printf '%s\n' "$REJS" | while read -r r; do warn "  $r"; done
  fi
  if [ "$APPLIED" = "0" ]; then
    die "SUSFS 补丁打不进去，看 $LOGFILE 和上面的 .rej"
  fi
  ok "SUSFS 补丁已应用（有 .rej 的块会被列出）"
fi

# ============================================================================
step "7/9 写 defconfig（BakaSU + SUSFS + 念想）"
if ! dry; then
  cd "$KP/common"
  CFG=./arch/arm64/configs/gki_defconfig
  [ -f "$CFG" ] || die "找不到 $CFG"

  set_config() {
    local val="$1"
    local key="${val%%=*}"
    if grep -qF "${key}=" "$CFG" || grep -qF "# ${key} is not set" "$CFG"; then
      VAL="$val" awk -v k="$key" '$0=="# "k" is not set" || index($0,k"=")==1 {print ENVIRON["VAL"]; next} {print}' \
        "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
    else
      printf '%s\n' "$val" >> "$CFG"
    fi
  }

  set_config "CONFIG_KSU=y"
  set_config "CONFIG_KSU_MULTI_MANAGER_SUPPORT=y"
  set_config "CONFIG_KSU_FULL_NAME_FORMAT=\"%TAG_NAME%-${SUFFIX}.\""
  set_config "CONFIG_KSU_SUSFS=y"
  # 按补丁里真正实现的开关来开，避免开了补丁没实现的项导致链接报未定义符号
  if [ -f "$SUSFS_PATCH" ]; then
    SUSFS_OPTS="$(grep -o 'CONFIG_KSU_SUSFS_[A-Z_0-9]*' "$SUSFS_PATCH" | sort -u)"
    for opt in $SUSFS_OPTS; do
      set_config "${opt}=y"
    done
    log "按补丁开 SUSFS 开关: $(echo "$SUSFS_OPTS" | tr '\n' ' ')"
  else
    for k in SUS_PATH SUS_MOUNT SUS_KSTAT SPOOF_UNAME ENABLE_LOG \
             HIDE_KSU_SUSFS_SYMBOLS SPOOF_CMDLINE_OR_BOOTCONFIG OPEN_REDIRECT; do
      set_config "CONFIG_KSU_SUSFS_${k}=y"
    done
  fi
  case "$KPM_MODE" in
    KPM) set_config "CONFIG_KPM=y" ;;
    KPN) set_config "CONFIG_KPM=n" ;;
    *)   : ;;
  esac
  ok "核心配置写入（KSU_FULL_NAME_FORMAT=\"%TAG_NAME%-${SUFFIX}.\"）"

  if [ "$FEATURE_PROFILE" = "full" ]; then
    FF="$FEATURE_FILE"
    if [ -z "$FF" ]; then
      FF="$PATCH_DIR/features/features-$KVER.config"
      if [ ! -f "$FF" ]; then
        FF="$(ls "$PATCH_DIR"/features/features-*.config 2>/dev/null | head -1 || true)"
      fi
    fi
    if [ -n "$FF" ] && [ -f "$FF" ]; then
      log "合并完整 features: $FF"
      while IFS= read -r line; do
        case "$line" in
          CONFIG_*=*) set_config "$line" ;;
          "# CONFIG_"*" is not set") set_config "$line" ;;
        esac
      done < "$FF"
      ok "features 已并入"
    else
      warn "没有 features 文件，跳过 full 附加项"
    fi
  fi
fi

# ============================================================================
step "8/9 注入内核后缀「$SUFFIX」"
if ! dry && [ -n "$SUFFIX" ] && [ "$SUFFIX" != "-1" ]; then
  cd "$KP"
  for f in ./common/scripts/setlocalversion "./$KERNEL_REPOS/scripts/setlocalversion" ./external/dtc/scripts/setlocalversion; do
    if [ -f "$f" ]; then
      log "改后缀: $f"
      sed -i 's/ -dirty//g' "$f"
      sed -i '$i res=$(echo "$res" | sed '"'"'s/-dirty//g'"'"')' "$f"
      if grep -q 'KERNELVERSION.*scm_version' "$f"; then
        sed -i "s|echo \"\${KERNELVERSION}.*scm_version}\"|echo \"\${KERNELVERSION}-${KANDROID_VERSION}-${SUFFIX}\"|" "$f"
      elif grep -q 'echo "\$res"' "$f"; then
        sed -i "s/^res=.*/res=\"-${KANDROID_VERSION}-${SUFFIX}\"/" "$f"
      else
        echo "echo \"\$res-${SUFFIX}\"" >> "$f"
      fi
      chmod +x "$f"
    fi
  done
  ok "setlocalversion 已改"
fi

# ============================================================================
step "9/9 编译内核"
if ! dry; then
  cd "$KP"
  CLANG_BIN=""
  if [ -f ./common/build.config.common ]; then
    CLANG_BIN="$(grep -m1 '^CLANG_PREBUILT_BIN=' ./common/build.config.common | cut -d= -f2- || true)"
    CLANG_VER="$(grep -m1 '^CLANG_VERSION=' ./common/build.config.constants 2>/dev/null | cut -d= -f2 || true)"
    if [ -n "$CLANG_VER" ]; then
      CLANG_BIN="${CLANG_BIN//'${CLANG_VERSION}'/$CLANG_VER}"
    fi
  fi
  if [ -z "$CLANG_BIN" ] || [ ! -d "$KP/$CLANG_BIN" ]; then
    CLANG_BIN="$(ls -d "$KP"/prebuilts/clang/host/linux-x86/clang-*/bin 2>/dev/null | head -1 | sed "s|^$KP/||" || true)"
  fi
  [ -n "$CLANG_BIN" ] && [ -d "$KP/$CLANG_BIN" ] || die "找不到 prebuilts clang"
  export PATH="$KP/$CLANG_BIN:$PATH"
  LIBCLANG_DIR="$(dirname "$KP/$CLANG_BIN")/lib"
  if [ -d "$LIBCLANG_DIR" ]; then export LIBCLANG_PATH="$LIBCLANG_DIR"; fi
  log "clang: $CLANG_BIN"

  USE_LLVM_IAS=false
  if grep -q '^LLVM_IAS=1' ./common/build.config.arm 2>/dev/null; then USE_LLVM_IAS=true; fi

  PAHOLE=""
  PB="$(ls -d "$KP"/prebuilts*/kernel-build-tools 2>/dev/null | head -1 || true)"
  if [ -n "$PB" ] && [ -x "$PB/linux-x86/bin/pahole" ]; then PAHOLE="$PB/linux-x86/bin/pahole"; fi

  ENABLE_RUST=false; RUSTC_BIN=""; BINDGEN_BIN=""
  RUSTC_VER="$(grep -m1 '^RUSTC_VERSION=' ./common/build.config.constants 2>/dev/null | cut -d= -f2 || true)"
  if [ -n "$RUSTC_VER" ]; then
    RD_VER="$(echo "$RUSTC_VER" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || true)"
    [ -n "$RD_VER" ] || RD_VER="$RUSTC_VER"
    RT="$(ls -d "$KP"/prebuilts*/rust 2>/dev/null | head -1 || true)"
    if [ -n "$RT" ] && [ -x "$RT/linux-x86/$RD_VER/bin/rustc" ]; then
      RUSTC_BIN="$RT/linux-x86/$RD_VER/bin/rustc"
      CDIR="$(dirname "$(dirname "$KP/$CLANG_BIN")")"
      if [ -x "$CDIR/clang-tools/linux-x86/bin/bindgen" ]; then
        BINDGEN_BIN="$CDIR/clang-tools/linux-x86/bin/bindgen"
        ENABLE_RUST=true
      fi
    fi
  fi
  if [ "$ENABLE_RUST" = true ]; then
    log "Rust 支持已启用"
  else
    log "无 Rust 工具链，按非 Rust 编译"
  fi

  CC_WRAPPER="$(command -v clang)"
  if [ "$CCACHE_ON" = "1" ]; then
    printf '#!/bin/bash\nexec ccache "%s" "$@"\n' "$(command -v clang)" > "$WORK_ROOT/cc-wrapper"
    chmod +x "$WORK_ROOT/cc-wrapper"
    CC_WRAPPER="$WORK_ROOT/cc-wrapper"
    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache_${KMI:-$FILE}}"
    export CCACHE_COMPILERCHECK="none"
    export CCACHE_NOHASHDIR=1
    export CCACHE_IS_KERNEL_COMPILING=1
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
    mkdir -p "$CCACHE_DIR"
    ccache -M "$CCACHE_MAXSIZE" >/dev/null 2>&1 || true
  fi

  COMMON_REAL="$(realpath "$KP/common")"
  ROOT_REAL="$(dirname "$(dirname "$COMMON_REAL")")"
  KCFLAGS="-fdebug-prefix-map=$ROOT_REAL=. -ffile-prefix-map=$ROOT_REAL=. -no-canonical-prefixes -O2 -pipe -Wno-error -fno-stack-protector -D__ANDROID_COMMON_KERNEL__"
  KCPPFLAGS="-fmacro-prefix-map=$ROOT_REAL=."

  MAKE_ARGS=(
    O=out LLVM=1 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
    CC="$CC_WRAPPER" HOSTCC="$CC_WRAPPER" LD=ld.lld
    KCFLAGS="$KCFLAGS" KCPPFLAGS="$KCPPFLAGS"
  )
  if [ -n "$PAHOLE" ]; then MAKE_ARGS+=(PAHOLE="$PAHOLE"); fi
  if [ "$USE_LLVM_IAS" = true ]; then MAKE_ARGS+=(LLVM_IAS=1); fi
  if [ "$ENABLE_RUST" = true ]; then MAKE_ARGS+=(RUSTC="$RUSTC_BIN" BINDGEN="$BINDGEN_BIN"); fi

  export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(TZ=UTC date +'%a %b %d %T %Z %Y')}"
  export KBUILD_BUILD_VERSION=1

  cd "$KP/common"
  log "make gki_defconfig"
  make "${MAKE_ARGS[@]}" gki_defconfig --no-print-directory | tail -3
  if [ "${KVER%%.*}" = "5" ]; then
    log "5.x 内核强制 thin LTO"
    scripts/config --file out/.config -e LTO_CLANG -e LTO_CLANG_THIN -d LTO_CLANG_NONE -d LTO_CLANG_FULL
  fi
  make "${MAKE_ARGS[@]}" olddefconfig --no-print-directory | tail -3
  log "关键配置检查:"
  grep -E '^CONFIG_KSU(_SUSFS|_FULL_NAME_FORMAT|=)' out/.config | head -20 || true

  log "开始编译 -j$JOBS（第一次很久）"
  T0=$(date +%s)
  make -j"$JOBS" "${MAKE_ARGS[@]}"
  ok "编译完成，耗时 $(( $(date +%s) - T0 ))s"
  if [ "$CCACHE_ON" = "1" ]; then ccache -s | head -5 || true; fi
fi

# ============================================================================
step "打包 AnyKernel3"
if dry; then
  log "[dry] find Image / clone $AK3_REPO / 写 anykernel.sh / zip 到 $OUT_DIR"
else
  IMG="$(find "$KP/common/out" -name Image -type f 2>/dev/null | head -1 || true)"
  if [ -z "$IMG" ]; then
    IMG="$(find "$KP/out" -name Image -type f 2>/dev/null | head -1 || true)"
  fi
  [ -n "$IMG" ] || die "没找到 Image，编译挂了（看 $LOGFILE）"
  KSIZE="$(stat -c %s "$IMG")"
  [ "$KSIZE" -gt 1000000 ] || die "Image 只有 $KSIZE 字节，构建没走完"
  ok "Image: $IMG ($(( KSIZE / 1024 )) KB)"
  log "内核串: $(strings "$IMG" 2>/dev/null | grep -m1 '^Linux version ' || echo '<取不到>')"

  if [ ! -d "$AK3_WORK/.git" ]; then
    rm -rf "$AK3_WORK"
    git clone --depth=1 "$AK3_REPO" "$AK3_WORK"
  else
    git -C "$AK3_WORK" fetch --depth=1 origin >/dev/null 2>&1 || true
    git -C "$AK3_WORK" reset --hard FETCH_HEAD >/dev/null 2>&1 || true
  fi
  rm -rf "$AK3_WORK/.git"
  cp "$IMG" "$AK3_WORK/Image"

  KSU_VER_STR="$(echo "$KSU_TAG" | sed 's/^v//')-${SUFFIX}"
  cat > "$AK3_WORK/anykernel.sh" <<AK3EOF
### AnyKernel3 Ramdisk Mod Script
## Local build: BakaSU ${KSU_CODE} + SUSFS ${SUSFS_VERSION} + 念想
## osm0sis @ xda-developers

properties() { '
kernel.string=${KSU_VER_STR} | BakaSU ${KSU_CODE} | SUSFS ${SUSFS_VERSION} | ${FILE} | Linux ${KVER}
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot
IS_SLOT_DEVICE=auto
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto
NO_MAGISK_CHECK=1

. tools/ak3-core.sh

ui_print " "
ui_print "=================================="
ui_print " BakaSU ${KSU_CODE} + SUSFS ${SUSFS_VERSION}"
ui_print " 内核: Linux ${KVER} (念想)"
ui_print " 机型: ${FILE}"
ui_print "=================================="
ui_print " "

split_boot
if [ -f "split_img/ramdisk.cpio" ]; then
  unpack_ramdisk
  write_boot
else
  flash_boot
fi
AK3EOF
  chmod +x "$AK3_WORK/anykernel.sh"

  STAMP="$(date +%Y%m%d-%H%M)"
  AK3_NAME="AK3_BakaSU${KSU_CODE}_SUSFS${SUSFS_VERSION}_NianXiang_${FILE}_${KERNEL_VERSION}_${STAMP}.zip"
  rm -f "$OUT_DIR"/AK3_BakaSU*"_${FILE}_"*.zip 2>/dev/null || true
  ( cd "$AK3_WORK" && zip -r9 -q "$OUT_DIR/$AK3_NAME" . -x "*.git*" )
  ok "产物: $OUT_DIR/$AK3_NAME"
  ls -lh "$OUT_DIR/$AK3_NAME"
fi

# ============================================================================
step "收尾"
if [ "$SAVE_SOURCE" = "0" ] && ! dry; then
  log "删除源码 $SRC（省磁盘，想留加 --save-source）"
  rm -rf "$SRC"
else
  log "源码保留: $SRC"
fi
ok "全部完成  日志: $LOGFILE"
