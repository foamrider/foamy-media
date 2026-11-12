#!/usr/bin/env python3
"""The hover tooltip on the installed Omarchy 4.5 shell, offscreen.

A scripted Spotify (tests/fake-mpris.py) on the harness's private session bus
publishes hostile titles and artists. tests/qml/Tooltip.qml hovers the real
widget for each one and draws what it hands the bar in the host's own tooltip
Text, lifted verbatim from plugins/bar/Bar.qml, so a host that changes that
Text is tested as it ships. It checks the text reads literally there (and in
an AutoText Text, for hosts that leave the format unset), and inotify confirms
that no image named by an `<img src>` title is opened, while a control Text
fed the raw markup does open its own probe image.

FOAMY_KIT (default ~/GitHub/Personal/foamy-kit) provides the harness;
FOAMY_HOST_45 picks another 4.5 shell. Needs PyGObject and dbus-daemon."""
import ctypes
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
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
import harness  # noqa: E402

TITLE_LIMIT, ARTIST_LIMIT = 100, 60  # Model.tooltipTitleLimit, tooltipArtistLimit
IN_OPEN = 0x20


def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00\xff")) + chunk(b"IEND", b""))


def host_tooltip(host):
    """The host's tooltip Text, verbatim, in an Item that supplies the two
    names it reads from the bar (tooltipText, fontFamily)."""
    source = (Path(host) / "plugins/bar/Bar.qml").read_text()
    at = source.find("id: tooltipLabel")
    start = source.rfind("Text {", 0, at)
    if at < 0 or start < 0:
        raise SystemExit("FAIL: no tooltipLabel Text in the host Bar.qml")
    depth, end = 0, start
    for end in range(start, len(source)):
        depth += {"{": 1, "}": -1}.get(source[end], 0)
        if depth == 0 and source[end] == "}":
            break
    block = source[start:end + 1]
    if "text: root.tooltipText" not in block:
        raise SystemExit("FAIL: the host tooltip Text no longer reads root.tooltipText")
    fmt = next((line.strip() for line in block.splitlines() if "textFormat" in line), "textFormat unset (AutoText)")
    qml = ("import QtQuick\nimport qs.Commons\nimport qs.Commons as Commons\nimport qs.Ui\n\n"
           "Item {\n  id: root\n  property string tooltipText: \"\"\n  property string fontFamily: \"\"\n"
           "  readonly property alias label: tooltipLabel\n  width: tooltipLabel.implicitWidth\n"
           "  height: tooltipLabel.implicitHeight\n\n  " + block + "\n}\n")
    return qml, fmt


class Inotify:
    def __init__(self, directory):
        self.libc = ctypes.CDLL(None, use_errno=True)
        self.fd = self.libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0 or self.libc.inotify_add_watch(self.fd, str(directory).encode(), IN_OPEN) < 0:
            raise SystemExit("FAIL: inotify unavailable")

    def opened(self):
        names = []
        while True:
            try:
                data = os.read(self.fd, 65536)
            except BlockingIOError:
                return names
            offset = 0
            while offset < len(data):
                _, mask, _, size = struct.unpack_from("iIII", data, offset)
                name = data[offset + 16:offset + 16 + size].rstrip(b"\0").decode()
                if mask & IN_OPEN and name:
                    names.append(name)
                offset += 16 + size


def cases(probe):
    target = (probe / "tooltip-probe.png").as_uri()
    long_title = "<b>long</b> " * 400
    # (title, artist, status, whether Qt's AutoText would read it as markup)
    rows = [
        ("Instant Crush", "Daft Punk", "Playing", False),
        ("<b>bold</b>", "<i>italic</i>", "Playing", True),
        (f'<img src="{target}">', f"<img src='{target}' width=900>", "Playing", True),
        (f'  <img src="{target}">', "<!DOCTYPE html><p>artist", "Paused", True),
        ("Tom & Jerry", "Simon & Garfunkel", "Paused", False),
        ("a < b > c", "&amp;", "Playing", False),
        ("&lt;b&gt;escaped&lt;/b&gt;", "x<br>y", "Playing", True),
        ("مرحبا بالعالم", "فيروز", "Playing", False),
        ("first line\nsecond line", "", "Playing", False),
        (long_title, "z" * 3000, "Playing", True),
    ]

    def bounded(text, limit):
        text = text.replace("\n", " ")
        return text if len(text) <= limit else text[:limit - 1] + "\u2026"

    out = []
    for title, artist, status, rich in rows:
        title_shown, artist_shown = bounded(title, TITLE_LIMIT), bounded(artist, ARTIST_LIMIT)
        label = title_shown + ("  ·  " + artist_shown if artist_shown else "")
        out.append({"title": title, "artist": artist, "status": status, "label": label, "rich": rich})
    return out


def main():
    qml, fmt = host_tooltip(os.environ["FOAMY_HOST_45"])
    print(f"host tooltip Text: {fmt}")
    shell = (PLUGIN / "tests/qml/Tooltip.qml").read_text()
    r = harness.Run("4.5", shell, plugin=PLUGIN, language="en", prefix="foamy-media-tooltip-",
                    extra={"HostTooltip.qml": qml})
    probe = r.base / "probe"
    probe.mkdir()
    for name in ("tooltip-probe.png", "control-probe.png"):
        (probe / name).write_bytes(png())
    tracks = cases(probe)
    (r.base / "tracks.json").write_text(json.dumps(tracks, ensure_ascii=False))
    r.env["FOAMY_TRACKS"] = str(r.base / "tracks.json")
    watch = Inotify(probe)
    fake = None
    ok = False
    try:
        r.start()
        r.wait_for_log("FOAMY WAITING FOR PLAYER", 60)
        fake = subprocess.Popen([sys.executable, "-I", str(PLUGIN / "tests/fake-mpris.py"), str(r.base / "tracks.json")],
                                env=r.env, stdout=(r.base / "fake.log").open("w"), stderr=subprocess.STDOUT)
        r.wait(180)
    finally:
        if fake and fake.poll() is None:
            fake.terminate()
            fake.wait(5)
        r.stop()
    opened = watch.opened()
    log = r.log
    result = next((line.split("FOAMY RESULT ", 1)[1] for line in log.splitlines() if "FOAMY RESULT" in line), "no result")
    failures = r.failures()
    if "tooltip-probe.png" in opened:
        failures.append("FOAMY FAIL an <img> in track metadata made Qt open tooltip-probe.png")
    if "control-probe.png" not in opened:
        failures.append("FOAMY FAIL control: raw <img> markup in an AutoText Text did not open its probe; the image check proves nothing")
    failures += ["FOAMY FAIL Qt tried to load an image: " + line for line in log.splitlines() if "Cannot open" in line]
    ok = "FOAMY DONE" in log and not failures
    print(f"{'PASS' if ok else 'FAIL'} tooltip 4.5: {result}; files opened in the probe dir: {sorted(set(opened))}")
    if not ok:
        print("\n".join("    " + line for line in (failures or log.splitlines()[-40:])))
        print(f"    logs kept in {r.base}")
    else:
        r.cleanup()
    return ok


if __name__ == "__main__":
    raise SystemExit(0 if main() else 1)
