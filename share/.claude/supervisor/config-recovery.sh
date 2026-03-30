#!/usr/bin/env bash
# Layer R — Git-based config recovery.
# Runs via cron every 10 minutes. Restores deleted/corrupted hook files
# from the last committed state of the p6df-claude repo.
# Does NOT clobber intentionally modified files.

set -euo pipefail

REPO="${HOME}/.p6/p6m7g8-dotfiles/p6df-claude"
SUPERVISOR_DIR="${HOME}/.claude/supervisor"
LOG="${SUPERVISOR_DIR}/interventions.log"

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")
  echo "{\"ts\":\"${ts}\",\"event\":\"$1\",\"layer\":\"R-git-recovery\",\"detail\":\"$2\"}" >> "$LOG" 2>/dev/null || true
}

[ -d "$REPO" ] || exit 0

# Fetch from remote in background (non-blocking, non-critical)
git -C "$REPO" fetch --quiet --depth=1 2>/dev/null &

# Check for missing or empty tracked files in share/.claude/
MISSING=()
while IFS= read -r tracked_file; do
  full_path="${REPO}/${tracked_file}"
  if [ ! -f "$full_path" ] || [ ! -s "$full_path" ]; then
    MISSING+=("$tracked_file")
  fi
done < <(git -C "$REPO" ls-files "share/.claude/" 2>/dev/null)

if [ ${#MISSING[@]} -gt 0 ]; then
  # Check for intentional staged changes before restoring
  STAGED=$(git -C "$REPO" diff --name-only HEAD -- "share/.claude/" 2>/dev/null)
  for f in "${MISSING[@]}"; do
    if echo "$STAGED" | grep -q "^${f}$"; then
      continue  # Intentionally modified — skip
    fi
    git -C "$REPO" checkout HEAD -- "$f" 2>/dev/null && log "file_restored" "$f" || true
  done
  # Re-establish symlinks after restore
  bash "${SUPERVISOR_DIR}/reinstall-symlinks.sh" 2>/dev/null || true
  log "symlinks_reinstalled" "after_recovery"
fi
