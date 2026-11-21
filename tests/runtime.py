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


# Stands in for Omarchy's omarchy-webapp-window-class. Each call logs its
# arguments and answers the next case of Runtime.qml's hintSteps: the class,
# the class with a failing exit, a hang, two lines, 1 MB of junk, the class
# again. The junk is more than a pipe holds, so it is written completely
# (and the marker file made) only when the reader takes more than the
# widget's 512-byte bound; with the bound, `tr` loses its reader and fails.
WINDOW_CLASS = r"""#!/bin/bash
printf '%s\n' "$*" >>"$FOAMY_OUT/window-class-calls"
case $(wc -l <"$FOAMY_OUT/window-class-calls") in
  2) printf 'chrome-youtube.com__-Default\n'; exit 1 ;;
  3) exec sleep 30 ;;
  4) printf 'chrome-youtube.com__-Default\nsecond line\n' ;;
  5) head -c 1000000 /dev/zero | tr '\0' x && : >"$FOAMY_OUT/window-class-flood-complete" ;;
  *) printf 'chrome-youtube.com__-Default\n' ;;
esac
"""


def instance(run):
    """The shell's IPC instance id once its checks are done (FOAMY READY)."""
    if not run.wait_for_log("FOAMY READY", 120):
        return None
    by_id = Path(run.env["XDG_RUNTIME_DIR"]) / "quickshell/by-id"
    ids = harness.wait_for(lambda: [p.name for p in by_id.iterdir()] if by_id.is_dir() else None, 10)
    return ids[0] if ids else None


def ipc(run, instance_id, *args):
    """What `qs ipc -i <id> <args>` printed, or None when it failed."""
    if instance_id is None:
        return None
    result = subprocess.run(
        ["qs", "ipc", "-i", instance_id, *args],
        env=run.env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.stdout.strip() if result.returncode == 0 else None


# The IPC functions scripts and keybindings call, with what they return:
# the transport calls answer "ok" or "unhandled".
IPC_FUNCTIONS = {
    "open(): void",
    "close(): void",
    "toggle(): void",
    "settings(): void",
    "launch(): void",
    "playPause(): string",
    "next(): string",
    "previous(): string",
    "shuffle(): string",
    "loop(): string",
    "status(): string",
}


def ipc_functions(shown, target):
    """The functions `qs ipc show` lists for `target`."""
    functions, current = set(), None
    for line in (shown or "").splitlines():
        if line.startswith("target "):
            current = line.split(" ", 1)[1].strip()
        elif current == target and line.strip().startswith("function "):
            functions.add(line.strip().split(" ", 1)[1])
    return functions


def run(host, lang):
    shell = (PLUGIN / "tests/qml/Runtime.qml").read_text()
    r = harness.Run(
        host,
        shell,
        plugin=PLUGIN,
        language=lang,
        prefix=f"foamy-media-runtime-{host}-{lang}-",
        fakebin={"omarchy-webapp-window-class": WINDOW_CLASS},
    )
    # The harness gives each run a private session bus: no live MPRIS player.
    # The shell holds after its checks until the IPC call is made; stop() ends it.
    r.env.update(FOAMY_LANG=lang, FOAMY_HOLD_MS="120000")
    # The window-picker hint steps do not depend on the language (and one
    # of them waits out a 3 s deadline): they run in the English run only.
    hint = lang == "en"
    if hint:
        r.env["FOAMY_HINT"] = "1"
    r.start()
    try:
        instance_id = instance(r)
        status = ipc(r, instance_id, "call", "foamy.media", "status")
        shown = ipc(r, instance_id, "show") if hint else None
        answer = ipc(r, instance_id, "call", "foamy.media", "next") if hint else None
    finally:
        r.stop()
    log = r.log
    result = next(
        (line.split("FOAMY RESULT ", 1)[1] for line in log.splitlines() if "FOAMY RESULT" in line), "no result"
    )
    failures = r.failures() + [f"FOAMY FAIL host command: {line}" for line in r.host_commands()]
    calls_log = r.out / "window-class-calls"
    calls = calls_log.read_text().splitlines() if calls_log.exists() else []
    if calls != (["https://youtube.com/"] * 6 if hint else []):
        failures.append(f"FOAMY FAIL omarchy-webapp-window-class calls: {calls}")
    if (r.out / "window-class-flood-complete").exists():
        failures.append("FOAMY FAIL the window-class output was read past its 512-byte bound")
    if hint:
        functions = ipc_functions(shown, "foamy.media")
        if functions != IPC_FUNCTIONS:
            failures.append(
                "FOAMY FAIL the foamy.media IPC functions differ:"
                f" missing {sorted(IPC_FUNCTIONS - functions)}, extra {sorted(functions - IPC_FUNCTIONS)}"
            )
        if answer != "unhandled":
            failures.append(f"FOAMY FAIL `next` with no player answered {answer!r}, expected 'unhandled'")
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
