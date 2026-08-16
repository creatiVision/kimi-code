#!/usr/bin/env bash
# kimi-fork-update.sh — SINGLE SOURCE für den update-kimi-code Workflow.
# Host-aware: erkennt den Host und wählt die Fork-/Deploy-Pfade selbst.
# Override via ENV: KIMI_FORK_REPO, KIMI_FORK_SYMLINK, KIMI_KIMI_BIN,
#   KIMI_UPSTREAM (default origin), KIMI_FORK (default creatiVision).
# Bei unbekanntem Host (z. B. debian1) bricht das Skript ab und verlangt,
# die Pfade per board/buzz bei debian1 zu erfragen und via ENV zu setzen.
#
# Logs: ~/.kimi-code/logs/fork-update.log
set -euo pipefail

HOST=$(hostname)
LOG_FILE="${KIMI_LOG_FILE:-$HOME/.kimi-code/logs/fork-update.log}"
DIST_ENTRY="${KIMI_DIST_ENTRY:-apps/kimi-code/dist/main.mjs}"

# ---- Host-Pfadauflösung ----------------------------------------------------
case "$HOST" in
  *laptop*|kimi-*)
    # kimi-laptop (Default)
    FORK_REPO="${KIMI_FORK_REPO:-/media/work-data/002_cv-projects/cv_ai_kimi-code-cli-fork}"
    REPO_DIR="${KIMI_FORK_SYMLINK:-/home/mb/.kimi-code-cli}"
    KIMI_BIN="${KIMI_KIMI_BIN:-$HOME/.kimi-code/bin/kimi}"
    ;;
  *)
    # Fremder Host (debian1, agy, hermes): Pfade müssen explizit gesetzt sein.
    FORK_REPO="${KIMI_FORK_REPO:?Unbekannter Host $HOST: Pfade per board/buzz bei debian1 erfragen und KIMI_FORK_REPO setzen}"
    REPO_DIR="${KIMI_FORK_SYMLINK:-$FORK_REPO}"
    KIMI_BIN="${KIMI_KIMI_BIN:?Unbekannter Host $HOST: KIMI_KIMI_BIN setzen}"
    ;;
esac
UPSTREAM="${KIMI_UPSTREAM:-origin}"
FORK_REMOTE="${KIMI_FORK:-creatiVision}"
BIN_DIR="$(dirname "$KIMI_BIN")"
KIMI_BAK="$KIMI_BIN.bak"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

exec 3>&1 1>>"$LOG_FILE" 2>&1

log "=== kimi-fork-update ($HOST) gestartet ==="
cd "$REPO_DIR"

# 1. Upstream fetchen
log "Fetch upstream ($UPSTREAM)..."
git fetch "$UPSTREAM" main

# 2. Neue Commits in Upstream?
UPSTREAM_NEW=$(git log --oneline main.."$UPSTREAM/main" || true)
if [ -z "$UPSTREAM_NEW" ]; then
  log "Keine neuen Upstream-Commits – kein Update nötig."
  log "=== kimi-fork-update beendet (keine Änderung) ==="
  exit 0
fi
log "Neue Upstream-Commits gefunden."

# 3. Fork main syncen (Achtung: hart reset!)
git checkout main
git reset --hard "$UPSTREAM/main"
git push "$FORK_REMOTE" main --force
log "Fork main gesynct."

# 4. Unsere 3 PR-Branches rebasen + pushen
for BRANCH in fix/latest-with-prompt-cache fix/mcp-schema-limits fix/session-workdir-resume; do
  log "Rebase $BRANCH..."
  if git checkout "$BRANCH" 2>/dev/null; then
    if git rebase "$UPSTREAM/main"; then
      git push "$FORK_REMOTE" "$BRANCH" --force
      log "$BRANCH rebased und gepusht."
    else
      log "WARNUNG: Rebase $BRANCH fehlgeschlagen – breche ab."
      git rebase --abort 2>/dev/null || true
      exit 1
    fi
  else
    log "Branch $BRANCH existiert nicht – überspringe."
  fi
done

# Sanity: echte Konflikt-Marker
if git grep -nE '^(<<<<<<<|>>>>>>>)' -- apps/kimi-code/src packages/agent-core-v2/src 2>/dev/null; then
  log "FEHLER: Ungelöste Konflikt-Marker. Breche ab."
  exit 1
fi

# 5. Merge der 3 in fork main
git checkout main
for BRANCH in fix/latest-with-prompt-cache fix/mcp-schema-limits fix/session-workdir-resume; do
  if git branch -a | grep -q "$BRANCH"; then
    git merge "$BRANCH" -m "chore: merge $BRANCH into fork main" || git merge --abort 2>/dev/null || true
  fi
done

# 6. Install + Build
pnpm install --no-frozen-lockfile || log "WARNUNG: pnpm install Warnungen."
pnpm run build:packages
pnpm --filter @moonshot-ai/kimi-code run build || { log "FEHLER: Build fehlgeschlagen."; exit 1; }

# 7. Deploy Wrapper (atomar)
mkdir -p "$BIN_DIR"
printf '#!/usr/bin/env node\nimport(%s)\n' "'$REPO_DIR/$DIST_ENTRY'" > /tmp/kimi.new
chmod +x /tmp/kimi.new
if [ -f "$KIMI_BIN" ] && [ ! -f "$KIMI_BAK" ]; then cp "$KIMI_BIN" "$KIMI_BAK" 2>/dev/null || true; fi
mv -f /tmp/kimi.new "$KIMI_BIN"
chmod +x "$KIMI_BIN"
log "Wrapper geschrieben: $KIMI_BIN"

# 8. Fork main pushen
git push "$FORK_REMOTE" main

log "=== kimi-fork-update ($HOST) erfolgreich abgeschlossen ==="