#!/usr/bin/env python3
"""Load Foamy Media offscreen on Omarchy 4.5
with the foamy-kit harness: isolated HOME/XDG/runtime dirs, no Wayland or
Hyprland, a private session bus (so no live MPRIS player). Checks tests/qml/Runtime.qml plus
`qs ipc call foamy.media status` answered by the leader.

FOAMY_KIT (default ~/GitHub/Personal/foamy-kit) provides the harness.
The host is Omarchy 4.5: FOAMY_HOST_45, else $OMARCHY_TEST_ROOT/shell, else
the installed /usr/share/omarchy/shell."""

import json
import os
from pathlib import Path
import subprocess
import sys

PLUGIN = Path(__file__).resolve().parents[1]
KIT = Path(os.environ.get("FOAMY_KIT", Path.home() / "GitHub/Personal/foamy-kit"))
if not (KIT / "preview/harness.py").exists():
    print(f"SKIP: foamy-kit harness not found at {KIT} (set FOAMY_KIT)")
    raise SystemExit(0)
# Omarchy 4.5 only by default; set before the harness reads its hosts.
if not os.environ.get("FOAMY_HOST_45"):
    _root = os.environ.get("OMARCHY_TEST_ROOT")
    os.environ["FOAMY_HOST_45"] = str(Path(_root) / "shell") if _root else "/usr/share/omarchy/shell"
sys.path.insert(0, str(KIT / "preview"))
import harness  # noqa: E402


def ipc_status(run):
    """`qs ipc call foamy.media status` once the checks are done (FOAMY READY)."""
    if not run.wait_for_log("FOAMY READY", 120):
        return None
    by_id = Path(run.env["XDG_RUNTIME_DIR"]) / "quickshell/by-id"
    ids = harness.wait_for(lambda: [p.name for p in by_id.iterdir()] if by_id.is_dir() else None, 10)
    if not ids:
        return None
    result = subprocess.run(
        ["qs", "ipc", "-i", ids[0], "call", "foamy.media", "status"],
        env=run.env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def run(host, lang):
    shell = (PLUGIN / "tests/qml/Runtime.qml").read_text()
    r = harness.Run(host, shell, plugin=PLUGIN, language=lang, prefix=f"foamy-media-runtime-{host}-{lang}-")
    # The harness gives each run a private session bus: no live MPRIS player.
    # The shell holds after its checks until the IPC call is made; stop() ends it.
    r.env.update(FOAMY_LANG=lang, FOAMY_HOLD_MS="120000")
    r.start()
    try:
        status = ipc_status(r)
    finally:
        r.stop()
    log = r.log
    result = next(
        (line.split("FOAMY RESULT ", 1)[1] for line in log.splitlines() if "FOAMY RESULT" in line), "no result"
    )
    failures = r.failures() + [f"FOAMY FAIL host command: {line}" for line in r.host_commands()]
    try:
        leader = status is not None and json.loads(status).get("leader") is True
    except ValueError:
        leader = False
    ok = "FOAMY READY" in log and not failures and leader
    print(f"{'PASS' if ok else 'FAIL'} runtime {host} {lang}: {result}; ipc status from leader: {leader}")
    if not ok:
        print("\n".join("    " + line for line in (failures or log.splitlines()[-40:])))
        print(f"    logs kept in {r.base}")
    else:
        r.cleanup()
    return ok


if __name__ == "__main__":
    cases = [("4.5", "en"), ("4.5", "no"), ("4.5", "ar")]
    results = [run(host, lang) for host, lang in cases]
    raise SystemExit(0 if all(results) else 1)
