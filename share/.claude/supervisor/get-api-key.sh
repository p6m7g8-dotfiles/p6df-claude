#!/usr/bin/env bash
# Layer H — Credential chain: apiKeyHelper script.
# Called by Claude Code before every API request. Must be fast (<1s).
# Falls through chain until a valid key is found.
#
# Chain: env var → cache → macOS Keychain → ~/.anthropic/credentials → 1Password CLI

set -euo pipefail

CACHE="${HOME}/.claude/supervisor/.cred-cache"
CACHE_TTL=3600  # 1 hour

# Helper: validate key format
valid_key() {
  [[ "$1" =~ ^sk-ant- ]]
}

# Check cache first (fastest path)
if [ -f "$CACHE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt "$CACHE_TTL" ]; then
    cached_key=$(cat "$CACHE" 2>/dev/null || echo "")
    if valid_key "$cached_key"; then
      echo "$cached_key"
      exit 0
    fi
  fi
fi

KEY=""

# 1. Environment variable
if [ -n "${ANTHROPIC_API_KEY:-}" ] && valid_key "${ANTHROPIC_API_KEY}"; then
  KEY="${ANTHROPIC_API_KEY}"

# 2. macOS Keychain
elif command -v security &>/dev/null; then
  KEY=$(security find-generic-password -a claude -s anthropic -w 2>/dev/null || echo "")

# 3. ~/.anthropic/credentials file
elif [ -f "${HOME}/.anthropic/credentials" ]; then
  KEY=$(grep -m1 'api_key' "${HOME}/.anthropic/credentials" 2>/dev/null | sed 's/.*=\s*//' | tr -d '[:space:]' || echo "")

# 4. 1Password CLI (with 2s timeout)
elif command -v op &>/dev/null; then
  KEY=$(timeout 2 op read "op://Private/Anthropic API Key/credential" 2>/dev/null || echo "")
fi

if valid_key "$KEY"; then
  # Write to cache
  echo "$KEY" > "$CACHE"
  chmod 600 "$CACHE"
  echo "$KEY"
  exit 0
fi

# All sources failed
exit 1
