#!/usr/bin/env bash
# Layer I — CLAUDE_ENV_FILE: sourced before every Bash tool execution.
# Re-exports critical environment variables in case the shell env is stale.
# This is for Bash tool env, not API auth (see get-api-key.sh for that).

SUPERVISOR_DIR="${HOME}/.claude/supervisor"
CONFIG="${SUPERVISOR_DIR}/config.json"

# Re-export ANTHROPIC_API_KEY from credential chain if missing
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  _key=$(bash "${SUPERVISOR_DIR}/get-api-key.sh" 2>/dev/null || echo "")
  if [ -n "$_key" ]; then
    export ANTHROPIC_API_KEY="$_key"
  fi
fi

# Load completion token from config
if command -v python3 &>/dev/null && [ -f "$CONFIG" ]; then
  _token=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('completion_token',''))" 2>/dev/null || echo "")
  if [ -n "$_token" ]; then
    export CLAUDE_COMPLETION_TOKEN="$_token"
  fi
fi

# Disable telemetry
export DISABLE_TELEMETRY="${DISABLE_TELEMETRY:-1}"
export DISABLE_ERROR_REPORTING="${DISABLE_ERROR_REPORTING:-1}"
