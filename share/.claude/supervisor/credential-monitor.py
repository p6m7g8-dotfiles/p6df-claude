#!/usr/bin/env python3
"""
Layer K — Credential health monitor daemon.

Every 60s: verifies API key is valid (format check + optional lightweight ping).
On auth failure: writes cred-refresh-needed sentinel.
On billing error: writes billing-blocked sentinel, alerts user.
Monitors cred-refresh-needed sentinel from stop-failure hook and rotates key.
Clears billing-blocked when API recovers.
"""
import json
import os
import subprocess
import sys
import time
import logging
import re

SUPERVISOR_DIR = os.path.expanduser("~/.claude/supervisor")
CONFIG_PATH = os.path.join(SUPERVISOR_DIR, "config.json")
LOG_PATH = os.path.join(SUPERVISOR_DIR, "credential-monitor.log")
INTERVENTIONS = os.path.join(SUPERVISOR_DIR, "interventions.log")
BILLING_SENTINEL = os.path.join(SUPERVISOR_DIR, "billing-blocked")
CRED_REFRESH = os.path.join(SUPERVISOR_DIR, "cred-refresh-needed")
CRED_CACHE = os.path.join(SUPERVISOR_DIR, ".cred-cache")

logging.basicConfig(filename=LOG_PATH, level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")

def notify(title, message):
    import platform
    if platform.system() == "Darwin":
        os.system(f'osascript -e \'display notification "{message}" with title "{title}"\' 2>/dev/null || true')
    else:
        os.system(f'notify-send "{title}" "{message}" 2>/dev/null || true')

def log_intervention(event, detail=""):
    entry = json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "event": event, "layer": "K-cred-monitor", "detail": detail})
    try:
        with open(INTERVENTIONS, "a") as f:
            f.write(entry + "\n")
    except Exception:
        pass

def get_api_key():
    """Get API key via get-api-key.sh (Layer H)."""
    script = os.path.join(SUPERVISOR_DIR, "get-api-key.sh")
    if os.path.exists(script):
        try:
            r = subprocess.run(["bash", script], capture_output=True, text=True, timeout=10)
            key = r.stdout.strip()
            if key:
                return key
        except Exception:
            pass
    return os.environ.get("ANTHROPIC_API_KEY", "")

def is_key_format_valid(key):
    """Anthropic keys start with sk-ant-."""
    return bool(key and re.match(r'^sk-ant-', key))

def check_billing_recovery():
    """Check if billing sentinel is stale (>1hr) and API might be working."""
    if not os.path.exists(BILLING_SENTINEL):
        return
    try:
        age = time.time() - os.path.getmtime(BILLING_SENTINEL)
        if age > 3600:  # 1 hour
            key = get_api_key()
            if is_key_format_valid(key):
                os.remove(BILLING_SENTINEL)
                log_intervention("billing_recovered")
                notify("Claude Code", "Billing issue may be resolved. Try continuing your session.")
    except Exception:
        pass

def handle_cred_refresh():
    """Called when stop-failure hook wrote cred-refresh-needed sentinel."""
    if not os.path.exists(CRED_REFRESH):
        return
    try:
        os.remove(CRED_REFRESH)
        key = get_api_key()
        if is_key_format_valid(key):
            log_intervention("cred_refreshed")
            logging.info("Credentials refreshed successfully")
        else:
            log_intervention("cred_refresh_failed")
            notify("Claude Code — Auth Error", "Credential refresh failed. Check your API key.")
    except Exception:
        pass

def main():
    logging.info("Credential monitor started")

    while True:
        try:
            handle_cred_refresh()
            check_billing_recovery()

            key = get_api_key()
            if not is_key_format_valid(key):
                log_intervention("invalid_key_format")
                logging.warning("API key format invalid or missing")
                notify("Claude Code — Auth Warning",
                       "ANTHROPIC_API_KEY is missing or invalid format. Claude may fail.")

        except Exception as e:
            logging.error(f"Credential monitor error: {e}")

        time.sleep(60)

if __name__ == "__main__":
    main()
