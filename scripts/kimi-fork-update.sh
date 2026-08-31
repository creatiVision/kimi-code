#!/usr/bin/env bash
# kimi-fork-update.sh — Host-aware Kimi Code CLI update & build orchestrator.
#
# Capabilities:
# 1. Fast Deploy: Copies prebuilt binary from shared xchg directory (< 1 second)
# 2. Full Build: Syncs upstream + 4 PR branches, builds native SEA binary,
#    publishes to shared xchg directory, and notifies other hosts via shared board.
#
# Flags:
#   --fast        Force fast deploy from shared xchg prebuilt binary without rebuilding
#   --build       Force full rebuild from source, publish to xchg, and deploy
#   --sync-only   Only fetch and sync git branches on GitHub
#   --doctor      Verify current installation and configs

set -euo pipefail

HOST=$(hostname)
MODE="${1:---auto}"
LOG_FILE="${KIMI_LOG_FILE:-$HOME/.kimi-code/logs/fork-update.log}"
XCHG_BIN_DIR="${KIMI_XCHG_BIN_DIR:-/media/xchg/ai-tools-data/bin/kimi-builds/linux-x64}"
BOARD_FILE="${KIMI_BOARD_FILE:-/media/xchg/ai-knowledge-base/shared-kimi-chat-laptop+debian1.md}"

# ---- Host Path Resolution ----------------------------------------------------
case "$HOST" in
  debian1)
    FORK_REPO="${KIMI_FORK_REPO:-/media/sdc2-2tb-work-privat-xchg/00_Work/002_cv-projects/cv_ai_kimi-code-cli-fork}"
    KIMI_BIN="${KIMI_KIMI_BIN:-$HOME/.kimi-code/bin/kimi}"
    export PATH="$HOME/.local/node-v24.15.0/bin:$HOME/.local/bin:$PATH"
    ;;
  *laptop*|kimi-*)
    FORK_REPO="${KIMI_FORK_REPO:-/media/work-data/002_cv-projects/cv_ai_kimi-code-cli-fork}"
    KIMI_BIN="${KIMI_KIMI_BIN:-$HOME/.kimi-code/bin/kimi}"
    export PATH="$HOME/.local/bin:$PATH"
    ;;
  *)
    FORK_REPO="${KIMI_FORK_REPO:?Unbekannter Host $HOST: Bitte KIMI_FORK_REPO setzen}"
    KIMI_BIN="${KIMI_KIMI_BIN:-$HOME/.kimi-code/bin/kimi}"
    ;;
esac

UPSTREAM="${KIMI_UPSTREAM:-origin}"
FORK_REMOTE="${KIMI_FORK:-creatiVision}"
BIN_DIR="$(dirname "$KIMI_BIN")"

mkdir -p "$(dirname "$LOG_FILE")" "$BIN_DIR"

log() {
  local msg="[$(date +"%Y-%m-%d %H:%M:%S")] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

notify_board() {
  local msg="$*"
  if [ -f "$BOARD_FILE" ] || [ -d "$(dirname "$BOARD_FILE")" ]; then
    {
      echo ""
      echo "## [$(date +"%Y-%m-%d %H:%M")] @$HOST"
      echo ""
      echo "$msg"
      echo ""
      echo "---"
    } >> "$BOARD_FILE" 2>/dev/null || true
    log "Shared board benachrichtigt: $msg"
  fi
}

fast_deploy() {
  local src="$XCHG_BIN_DIR/kimi"
  local meta="$XCHG_BIN_DIR/build-meta.json"
  if [ ! -f "$src" ]; then
    log "Kein prebuilt Binary in $XCHG_BIN_DIR gefunden."
    return 1
  fi

  log "==> Fast Deploy: Kopiere prebuilt Binary aus xchg..."
  cp -p "$src" "$KIMI_BIN.new"
  chmod +x "$KIMI_BIN.new"
  mv -f "$KIMI_BIN.new" "$KIMI_BIN"
  log "✅ $KIMI_BIN aktualisiert."

  if [ -f "$meta" ]; then
    log "Build-Metadata: $(cat "$meta" | tr -d "\n")"
  fi

  log "Version: $("$KIMI_BIN" --version 2>&1)"
  "$KIMI_BIN" doctor || true
  return 0
}

# ------------------------------------------------------------------------------
# Doctor Mode
# ------------------------------------------------------------------------------
if [ "$MODE" = "--doctor" ]; then
  log "=== Kimi Doctor Check ($HOST) ==="
  if [ -x "$KIMI_BIN" ]; then
    "$KIMI_BIN" --version
    "$KIMI_BIN" doctor
  else
    log "FEHLER: $KIMI_BIN nicht ausführbar."
    exit 1
  fi
  exit 0
fi

# ------------------------------------------------------------------------------
# Fast Mode
# ------------------------------------------------------------------------------
if [ "$MODE" = "--fast" ]; then
  log "=== Fast Deploy Modus aufgerufen ==="
  if fast_deploy; then
    log "=== Fast Deploy erfolgreich beendet ==="
    exit 0
  else
    log "Fast Deploy nicht möglich. Wechsle zu Full Build."
    MODE="--build"
  fi
fi

# ------------------------------------------------------------------------------
# Auto Mode: Check if xchg has newer prebuilt binary before doing full build
# ------------------------------------------------------------------------------
if [ "$MODE" = "--auto" ]; then
  if [ -f "$XCHG_BIN_DIR/kimi" ] && [ -f "$KIMI_BIN" ]; then
    XCHG_TIME=$(stat -c %Y "$XCHG_BIN_DIR/kimi" 2>/dev/null || echo 0)
    LOCAL_TIME=$(stat -c %Y "$KIMI_BIN" 2>/dev/null || echo 0)
    if [ "$XCHG_TIME" -gt "$LOCAL_TIME" ]; then
      log "Prebuilt Binary im xchg ist neuer als lokales Binary ($XCHG_TIME > $LOCAL_TIME). Führe Fast Deploy aus."
      fast_deploy
      exit 0
    fi
  fi
fi

# ------------------------------------------------------------------------------
# Full Build / Sync Mode
# ------------------------------------------------------------------------------
log "=== Full Sync & Build ($HOST) in $FORK_REPO gestartet ==="

if [ ! -d "$FORK_REPO" ]; then
  log "FEHLER: Fork Repository $FORK_REPO nicht gefunden."
  exit 1
fi

cd "$FORK_REPO"

# 1. Fetch Remotes
log "Fetch $UPSTREAM and $FORK_REMOTE..."
git fetch "$UPSTREAM" main
git fetch "$FORK_REMOTE"

# 2. Reconcile with Upstream
LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "none")
git checkout main
git merge "$UPSTREAM/main" -m "Merge $UPSTREAM/main into main" || {
  log "Merge von $UPSTREAM/main erfordert manuelle Konfliktlösung."
  exit 1
}

# 3. Verify / Merge our 4 PR Branches
PR_BRANCHES=(
  "feat/skill-group-selector"
  "fix/prompt-cache-key-clean"
  "fix/session-workdir-resume"
  "fix/mcp-schema-limits"
  "feat/fork-native-updater"
)

for BRANCH in "${PR_BRANCHES[@]}"; do
  log "Prüfe Branch $BRANCH..."
  if git rev-parse --verify "$FORK_REMOTE/$BRANCH" >/dev/null 2>&1; then
    if ! git merge-base --is-ancestor "$FORK_REMOTE/$BRANCH" HEAD; then
      log "Merge $FORK_REMOTE/$BRANCH in main..."
      git merge "$FORK_REMOTE/$BRANCH" -m "Merge branch '$BRANCH' into main" || {
        log "WARNUNG: Merge-Konflikt bei $BRANCH. Breche Branch-Merge ab."
        git merge --abort 2>/dev/null || true
      }
    else
      log "Branch $BRANCH ist bereits in main enthalten."
    fi
  fi
done

# Push updated main to Fork
log "Push aktualisiertes main nach $FORK_REMOTE..."
git push "$FORK_REMOTE" main

if [ "$MODE" = "--sync-only" ]; then
  log "Sync-only abgeschlossen."
  exit 0
fi

# 4. Install & Build
log "Installiere Dependencies..."
pnpm install

log "Baue Packages..."
pnpm run build

log "Baue Standalone SEA Native Binary..."
pnpm --filter @moonshot-ai/kimi-code run build:native:sea

BUILT_BIN="$FORK_REPO/apps/kimi-code/dist-native/bin/linux-x64/kimi"
if [ ! -f "$BUILT_BIN" ]; then
  log "FEHLER: Gebautes Binary $BUILT_BIN nicht gefunden."
  exit 1
fi

# 5. Publish to Shared xchg Hub
mkdir -p "$XCHG_BIN_DIR"
cp -p "$BUILT_BIN" "$XCHG_BIN_DIR/kimi"
chmod +x "$XCHG_BIN_DIR/kimi"

VERSION=$("$BUILT_BIN" --version 2>&1 || echo "0.38.0")
COMMIT=$(git rev-parse HEAD)

echo "{\"version\":\"$VERSION\",\"commit\":\"$COMMIT\",\"built_at\":\"$(date --iso-8601=seconds)\",\"built_by\":\"$HOST\",\"target\":\"linux-x64\",\"pr_branches\":[\"feat/skill-group-selector\",\"fix/prompt-cache-key-clean\",\"fix/session-workdir-resume\",\"fix/mcp-schema-limits\",\"feat/fork-native-updater\"]}" > "$XCHG_BIN_DIR/build-meta.json"

log "Published nach $XCHG_BIN_DIR/kimi (Version $VERSION, Commit ${COMMIT:0:9})"

# 6. Deploy locally (Configs remain untouched)
cp -p "$BUILT_BIN" "$KIMI_BIN"
chmod +x "$KIMI_BIN"
log "Lokal deployed nach $KIMI_BIN"

# 7. Notify Shared Message Board
notify_board "🚀 **Kimi Code CLI Update** (v$VERSION, Commit \`${COMMIT:0:9}\`) erfolgreich gebaut auf @$HOST und im xchg bereitgestellt. Andere Hosts können das Update via \`update-kimi-code --fast\` in < 1s übernehmen."

# 8. Doctor Verification
log "Verifiziere Installation..."
"$KIMI_BIN" --version
"$KIMI_BIN" doctor

log "=== Update auf $HOST erfolgreich abgeschlossen ==="
