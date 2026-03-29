#!/usr/bin/env bash
# Cross-platform notification wrapper.
# Usage: notify.sh "Title" "Message"

TITLE="${1:-Claude Code}"
MESSAGE="${2:-}"

case "$(uname -s)" in
  Darwin)
    osascript -e "display notification \"${MESSAGE}\" with title \"${TITLE}\"" 2>/dev/null || \
      tput bel 2>/dev/null || true
    ;;
  Linux)
    if command -v notify-send &>/dev/null; then
      notify-send "${TITLE}" "${MESSAGE}" 2>/dev/null || true
    else
      echo "[${TITLE}] ${MESSAGE}" >&2
      tput bel 2>/dev/null || true
    fi
    ;;
  *)
    echo "[${TITLE}] ${MESSAGE}" >&2
    ;;
esac
