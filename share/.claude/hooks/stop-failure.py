#!/usr/bin/env python3
"""
Layer A — StopFailure hook: handles API errors gracefully by type.

Matchers (registered separately per error type in settings.json):
  rate_limit              → inform Claude to wait with productive work
  billing_error           → write sentinel, alert user
  authentication_failed   → trigger credential refresh
  max_output_tokens       → instruct continuation in next response
  server_error            → instruct retry
  unknown                 → generic retry guidance

StopFailure exit code is ignored per docs — use stdout for context only.
"""
import sys
import json
import os
import time

CONFIG_PATH = os.path.expanduser("~/.claude/supervisor/config.json")
BILLING_SENTINEL = os.path.expanduser("~/.claude/supervisor/billing-blocked")
CRED_REFRESH_SENTINEL = os.path.expanduser("~/.claude/supervisor/cred-refresh-needed")

def notify(title, message):
    """Cross-platform notification."""
    import platform
    if platform.system() == "Darwin":
        os.system(f'osascript -e \'display notification "{message}" with title "{title}"\' 2>/dev/null || true')
    else:
        os.system(f'notify-send "{title}" "{message}" 2>/dev/null || true')

def log_intervention(event, detail=""):
    log_path = os.path.expanduser("~/.claude/supervisor/interventions.log")
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "A-stop-failure", "detail": detail})
    try:
        with open(log_path, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

error_type = data.get("stop_failure_type", data.get("hook_event_name", "unknown"))
session_id = data.get("session_id", "unknown")
log_intervention(f"stop_failure_{error_type}", session_id)

MESSAGES = {
    "rate_limit": (
        "You hit a rate limit. Wait 30 seconds. Use this time to write a brief "
        "status update of what you've completed so far, without making any API calls."
    ),
    "billing_error": (
        "A billing error occurred. Your session has been paused. "
        "The user has been notified. Do not retry until notified it's resolved."
    ),
    "authentication_failed": (
        "Authentication failed. Credential refresh has been triggered. "
        "Retry your last action in a few seconds."
    ),
    "max_output_tokens": (
        "You hit the output token limit. Your response was truncated. "
        "Continue in your next response — start exactly where you left off."
    ),
    "server_error": (
        "The API returned a server error. Retry your last action immediately. "
        "This is a transient issue."
    ),
    "invalid_request": (
        "An invalid request was made. Check your tool inputs and retry with corrected parameters."
    ),
}

if error_type == "billing_error":
    try:
        with open(BILLING_SENTINEL, "w") as f:
            f.write(f"Billing error at {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}")
    except Exception:
        pass
    notify("Claude Code — Billing Error",
           "Claude session paused due to billing error. Check your Anthropic account.")

if error_type == "authentication_failed":
    try:
        with open(CRED_REFRESH_SENTINEL, "w") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    except Exception:
        pass

msg = MESSAGES.get(error_type, MESSAGES["server_error"])
# StopFailure output is for context only (exit code ignored)
print(json.dumps({"additionalContext": msg}))
sys.exit(0)
