#!/usr/bin/env python3
"""Layer AJ: Machine resource governor — blocks new agent spawns when RAM/CPU/disk critical."""
import json
import os
import sys
import time
from pathlib import Path

SUPERVISOR_DIR = Path.home() / ".claude" / "supervisor"
SPAWN_BLOCKED = SUPERVISOR_DIR / "spawn-blocked"
RESOURCE_STATE = SUPERVISOR_DIR / "resource-state.json"

def load_config():
    cfg_path = SUPERVISOR_DIR / "config.json"
    try:
        return json.loads(cfg_path.read_text())
    except Exception:
        return {}

def get_resource_usage():
    """Get current resource usage without psutil dependency."""
    result = {}

    # CPU via /proc/loadavg or sysctl
    try:
        import subprocess
        # macOS: sysctl
        r = subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True, text=True, timeout=2)
        if r.returncode == 0:
            # format: { 1.23 2.34 3.45 }
            parts = r.stdout.strip().strip("{}").split()
            if parts:
                result["load_1m"] = float(parts[0])
    except Exception:
        pass

    # Memory via vm_stat (macOS)
    try:
        import subprocess
        r = subprocess.run(["vm_stat"], capture_output=True, text=True, timeout=2)
        if r.returncode == 0:
            lines = r.stdout.splitlines()
            page_size = 4096
            pages_free = 0
            pages_inactive = 0
            pages_wired = 0
            pages_active = 0
            for line in lines:
                if "page size of" in line:
                    try:
                        page_size = int(line.split("page size of")[1].split()[0])
                    except Exception:
                        pass
                elif "Pages free" in line:
                    pages_free = int(line.split(":")[1].strip().rstrip("."))
                elif "Pages inactive" in line:
                    pages_inactive = int(line.split(":")[1].strip().rstrip("."))
                elif "Pages wired" in line:
                    pages_wired = int(line.split(":")[1].strip().rstrip("."))
                elif "Pages active" in line:
                    pages_active = int(line.split(":")[1].strip().rstrip("."))
            total_pages = pages_free + pages_inactive + pages_wired + pages_active
            if total_pages > 0:
                used_pages = pages_wired + pages_active
                result["memory_pct"] = (used_pages / total_pages) * 100
                result["memory_free_mb"] = (pages_free * page_size) / (1024 * 1024)
    except Exception:
        pass

    # Disk via df
    try:
        import subprocess
        r = subprocess.run(["df", "-k", str(Path.home())], capture_output=True, text=True, timeout=2)
        if r.returncode == 0:
            lines = r.stdout.splitlines()
            if len(lines) >= 2:
                parts = lines[1].split()
                if len(parts) >= 5:
                    pct_str = parts[4].rstrip("%")
                    result["disk_pct"] = float(pct_str)
    except Exception:
        pass

    return result

def check_resources(cfg):
    usage = get_resource_usage()

    cpu_threshold = cfg.get("resource_cpu_load_threshold", 4.0)
    mem_threshold = cfg.get("resource_memory_pct_threshold", 90.0)
    disk_threshold = cfg.get("resource_disk_pct_threshold", 95.0)
    mem_free_min_mb = cfg.get("resource_memory_free_min_mb", 512)

    reasons = []

    load = usage.get("load_1m")
    if load is not None and load > cpu_threshold:
        reasons.append(f"CPU load {load:.1f} > threshold {cpu_threshold}")

    mem_pct = usage.get("memory_pct")
    if mem_pct is not None and mem_pct > mem_threshold:
        reasons.append(f"Memory {mem_pct:.0f}% > threshold {mem_threshold}%")

    mem_free = usage.get("memory_free_mb")
    if mem_free is not None and mem_free < mem_free_min_mb:
        reasons.append(f"Free memory {mem_free:.0f}MB < minimum {mem_free_min_mb}MB")

    disk_pct = usage.get("disk_pct")
    if disk_pct is not None and disk_pct > disk_threshold:
        reasons.append(f"Disk {disk_pct:.0f}% > threshold {disk_threshold}%")

    return reasons, usage

def write_state(usage, blocked, reasons):
    state = {
        "timestamp": time.time(),
        "blocked": blocked,
        "reasons": reasons,
        "usage": usage,
    }
    tmp = str(RESOURCE_STATE) + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, RESOURCE_STATE)

def main():
    SUPERVISOR_DIR.mkdir(parents=True, exist_ok=True)
    cfg = load_config()
    interval = cfg.get("resource_check_interval_seconds", 15)

    while True:
        reasons, usage = check_resources(cfg)
        blocked = len(reasons) > 0

        write_state(usage, blocked, reasons)

        if blocked:
            if not SPAWN_BLOCKED.exists():
                SPAWN_BLOCKED.write_text(
                    f"Resource limits exceeded at {time.strftime('%Y-%m-%dT%H:%M:%S')}: "
                    + "; ".join(reasons)
                )
                # notify
                try:
                    import subprocess
                    msg = "Claude spawn blocked: " + "; ".join(reasons)
                    subprocess.run(
                        ["osascript", "-e", f'display notification "{msg}" with title "Claude Resource Governor"'],
                        capture_output=True, timeout=5
                    )
                except Exception:
                    pass
        else:
            # Only clear if it was a resource block (not a billing block)
            if SPAWN_BLOCKED.exists():
                content = SPAWN_BLOCKED.read_text()
                if "Resource limits" in content:
                    SPAWN_BLOCKED.unlink(missing_ok=True)

        time.sleep(interval)

if __name__ == "__main__":
    main()
