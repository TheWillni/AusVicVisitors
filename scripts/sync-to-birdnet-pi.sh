#!/usr/bin/env bash
# Keeps a local BirdNET-Pi/AvianVisitors install in sync with this
# repo's illustrations + masks/dims, so the collage always shows the
# latest AU-VIC asset set without any manual deploy step.
#
# Intended to run unattended via cron, invoked by its path INSIDE this
# cloned repo - since each cron firing re-reads the script file fresh,
# a `git pull` at the top of a run picks up the latest illustrations
# AND the latest version of this script itself for the NEXT run.
#
# One-time setup on the Pi:
#   git clone https://github.com/TheWillni/AusVicVisitors.git ~/AusVicVisitors
#   chmod +x ~/AusVicVisitors/scripts/sync-to-birdnet-pi.sh
#   ~/AusVicVisitors/scripts/sync-to-birdnet-pi.sh --dry-run   # sanity check first
#   crontab -e
#     # add a line like:
#     */30 * * * * /home/willni/AusVicVisitors/scripts/sync-to-birdnet-pi.sh
#
# Log output goes to ~/ausvicvisitors-sync.log (rotate/trim manually if
# it grows large - this script does not do that itself).
set -euo pipefail

REPO_DIR="${AUSVIC_REPO_DIR:-$HOME/AusVicVisitors}"
BIRDNET_DIR="${BIRDNET_DIR:-$HOME/BirdNET-Pi}"
ILLUSTRATIONS_DEST="$BIRDNET_DIR/avian/assets/illustrations"
FRONTEND_DEST="$BIRDNET_DIR/avian/frontend"
LOCKFILE="/tmp/ausvicvisitors-sync.lock"
LOGFILE="$HOME/ausvicvisitors-sync.log"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

log() { echo "$(date -Iseconds) $*" | tee -a "$LOGFILE"; }

# Prevent overlapping runs if a previous invocation is still going
# (e.g. a slow rsync on a big illustration set).
exec 200>"$LOCKFILE"
if ! flock -n 200; then
  log "sync already in progress, skipping this run"
  exit 0
fi

if [ ! -d "$REPO_DIR/.git" ]; then
  log "error: $REPO_DIR is not a git clone - run the one-time setup first"
  exit 1
fi
if [ ! -d "$BIRDNET_DIR" ]; then
  log "error: $BIRDNET_DIR not found - is BirdNET-Pi installed under this user?"
  exit 1
fi

log "sync starting (dry-run=$DRY_RUN)"

cd "$REPO_DIR"
BEFORE_SHA=$(git rev-parse HEAD)
if ! git pull --ff-only origin main >>"$LOGFILE" 2>&1; then
  log "git pull failed - leaving deployed assets untouched, will retry next run"
  exit 1
fi
AFTER_SHA=$(git rev-parse HEAD)

if [ "$BEFORE_SHA" = "$AFTER_SHA" ] && [ "$DRY_RUN" -eq 0 ]; then
  log "no new commits ($AFTER_SHA), nothing to sync"
  exit 0
fi

log "syncing $BEFORE_SHA -> $AFTER_SHA"

RSYNC_FLAGS=(-a --delete)
[ "$DRY_RUN" -eq 1 ] && RSYNC_FLAGS+=(--dry-run -v)

# Mirror illustrations exactly, including deletions - a species pruned
# or renamed in AusVicVisitors should disappear from the Pi too, not
# linger as a stale orphan file.
rsync "${RSYNC_FLAGS[@]}" "$REPO_DIR/illustrations/" "$ILLUSTRATIONS_DEST/" | tee -a "$LOGFILE"

# Only the two JSON files - never wholesale-replace frontend/, which
# also holds apt.js/index.html/styles.css/nest.webp that this repo
# does NOT track and would otherwise get deleted.
if [ "$DRY_RUN" -eq 1 ]; then
  log "[dry-run] would copy frontend/masks.json and frontend/dims.json"
else
  cp "$REPO_DIR/frontend/masks.json" "$FRONTEND_DEST/masks.json"
  cp "$REPO_DIR/frontend/dims.json" "$FRONTEND_DEST/dims.json"
fi

# A past bug: replacing a directory in place can leave it with
# restrictive permissions Caddy can't read. rsync updates contents
# in place rather than recreating the directory, but re-assert
# permissions every run anyway as a cheap safety net.
if [ "$DRY_RUN" -eq 0 ]; then
  chmod 755 "$ILLUSTRATIONS_DEST"
  find "$ILLUSTRATIONS_DEST" -type f -exec chmod 644 {} +
fi

# Cache-bust: apt.js isn't tracked in this repo, so its
# SKETCH_VERSION/IMG_VERSION constants can't be bumped by a commit
# here. Patch them directly on the Pi's deployed apt.js using the new
# commit's short SHA, so browsers and any CDN in front of /api/img
# actually pick up the refreshed images instead of serving a stale
# cached copy.
APT_JS="$FRONTEND_DEST/apt.js"
VERSION_TAG="auto-${AFTER_SHA:0:7}"
if [ -f "$APT_JS" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] would set SKETCH_VERSION/IMG_VERSION to '$VERSION_TAG' in $APT_JS"
  else
    sed -i "s/var SKETCH_VERSION = '[^']*'/var SKETCH_VERSION = '$VERSION_TAG'/" "$APT_JS"
    sed -i "s/var IMG_VERSION = '[^']*'/var IMG_VERSION = '$VERSION_TAG'/" "$APT_JS"
  fi
else
  log "warning: $APT_JS not found, skipped cache-bust version patch"
fi

log "sync complete, version tag $VERSION_TAG"
