#!/usr/bin/env python3
"""The cover service through its real Process, on the installed Omarchy 4.5
shell, offscreen.

tests/qml/Art.qml drives three bars with stand-in players. The plugin is a
copy whose bundled helper is a fake (hostenv.fake_helper_plugin): it logs
its arguments and answers as $FOAMY_OUT/helper-mode says (a cover, an HTTP
failure, TLS_UNSUPPORTED, exit 127 for no helper on this CPU, or a run
that lasts until the service stops it). Nothing
reaches the network: the helper is the fake, and the network state the
widget sees is the kit's fake NetworkManager on a private system bus.

FOAMY_KIT (default ~/GitHub/Personal/foamy-kit) provides the harness;
FOAMY_HOST_45 picks another 4.5 shell. Needs dbus-python and PyGObject."""

import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import zlib

PLUGIN = Path(__file__).resolve().parents[1]
KIT = Path(os.environ.get("FOAMY_KIT", Path.home() / "GitHub/Personal/foamy-kit"))
if not (KIT / "preview/harness.py").exists():
    print(f"SKIP: foamy-kit harness not found at {KIT} (set FOAMY_KIT)")
    raise SystemExit(0)
if not os.environ.get("FOAMY_HOST_45"):
    _root = os.environ.get("OMARCHY_TEST_ROOT")
    os.environ["FOAMY_HOST_45"] = str(Path(_root) / "shell") if _root else "/usr/share/omarchy/shell"
sys.path.insert(0, str(KIT / "preview"))
import fake_nm
import harness
import hostenv

# The helper's replies (native/src/main.rs): one JSON line, exit 0 for a
# cover and 1 for a failure. Exit 127 is what FoamyNative reports for a
# missing binary. "$#" shows that the target is one argument.
FAKE_HELPER = r"""#!/bin/bash
printf '%s %s\n' "$#" "$*" >>"$FOAMY_OUT/helper-calls"
read -r mode <"$FOAMY_OUT/helper-mode" || mode=ok
case $mode in
  ok) printf '{"ok":true,"mean":"#336699","file":"%s","swatches":[]}\n' "$FOAMY_OUT/probed.png" ;;
  http) printf '{"ok":false,"code":"HTTP","error":"404"}\n'; exit 1 ;;
  tls) printf '{"ok":false,"code":"TLS_UNSUPPORTED","error":"no HTTPS on this CPU"}\n'; exit 1 ;;
  missing) exit 127 ;;
  # Runs until the service stops it (a track change while it probes). It
  # sets the next probe's mode itself, so the scene never writes the mode
  # while this probe may not have read it yet.
  slow) printf 'ok\n' >"$FOAMY_OUT/helper-mode"; exec sleep 30 ;;
esac
"""

# What the scene's steps must have asked of the helper, in order: one probe
# for three bars, the last of a burst, a slow probe stopped by a track
# change and the next track's, an HTTPS cover once online and its
# three retries, once more after the network came back, one TLS failure
# with no retry, the next cover after the leading bar's monitor was
# unplugged, and one local cover before the helper went missing.
EXPECTED_CALLS = (
    ["2 art-probe /covers/My Cover.png", "2 art-probe /covers/c.png"]
    + ["2 art-probe /covers/slow.png", "2 art-probe /covers/next.png"]
    + ["2 art-probe https://i.scdn.co/image/x"] * 5
    + ["2 art-probe https://i.scdn.co/image/y", "2 art-probe /covers/u.png", "2 art-probe /covers/m.png"]
)


def png():
    """A valid 1x1 PNG: the cover the fake says it wrote."""

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff"))
        + chunk(b"IEND", b"")
    )


def main():
    work = Path(tempfile.mkdtemp(prefix=f"foamy-media-art-plugin-{os.getpid()}-"))
    try:
        plugin = hostenv.fake_helper_plugin(PLUGIN, work / "plugin", "foamy-media-helper", FAKE_HELPER)
        return run(plugin)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def run(plugin):
    shell = (PLUGIN / "tests/qml/Art.qml").read_text()
    r = harness.Run("4.5", shell, plugin=plugin, language="en", prefix="foamy-media-art-", system_bus="private")
    connectivity = r.base / "connectivity"
    fake_nm.set_connectivity(connectivity, fake_nm.NONE)
    (r.out / "helper-mode").write_text("ok\n")
    (r.out / "probed.png").write_bytes(png())
    r.env["FOAMY_CONNECTIVITY"] = str(connectivity)
    # The fake goes on the bus before qs: Quickshell looks for
    # NetworkManager only once, at start.
    r.start_buses()
    with fake_nm.start(r.system_bus_address, connectivity):
        r.run(timeout=120)
    log = r.log
    result = next(
        (line.split("FOAMY RESULT ", 1)[1] for line in log.splitlines() if "FOAMY RESULT" in line), "no result"
    )
    failures = r.failures() + [f"FOAMY FAIL host command: {line}" for line in r.host_commands()]
    calls_log = r.out / "helper-calls"
    calls = calls_log.read_text().splitlines() if calls_log.exists() else []
    if calls != EXPECTED_CALLS:
        failures.append(f"FOAMY FAIL helper calls: {calls}, expected {EXPECTED_CALLS}")
    # Every probe of the scene starts, the stopped one included: none may be
    # reported as one that could not start.
    failures += [
        "FOAMY FAIL a started probe was reported as not started: " + line
        for line in log.splitlines()
        if "could not start" in line
    ]
    # The raw cover URLs name files that do not exist: an Image handed one
    # logs that it cannot open it.
    failures += [
        "FOAMY FAIL an image loaded the raw cover URL: " + line
        for line in log.splitlines()
        if "Cannot open" in line and "/covers/" in line
    ]
    ok = "FOAMY DONE" in log and not failures
    print(f"{'PASS' if ok else 'FAIL'} art 4.5: {result}; helper calls: {len(calls)}")
    if not ok:
        print("\n".join("    " + line for line in (failures or log.splitlines()[-40:])))
        print(f"    logs kept in {r.base}")
    else:
        r.cleanup()
    return ok


if __name__ == "__main__":
    raise SystemExit(0 if main() else 1)
