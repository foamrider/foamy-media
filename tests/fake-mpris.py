#!/usr/bin/env python3
"""A scripted Spotify on the session bus, for tests/tooltip-runtime.py.

Owns org.mpris.MediaPlayer2.spotify and plays the tracks in the JSON file
named by argv[1] ([{"title", "artist", "status"}…]), one at a time: the
player's own Next() moves to the next one, so the widget drives the script
through MPRIS exactly as it would drive Spotify. Prints "FAKE MPRIS UP" once
the name is owned. Needs PyGObject (Gio)."""

import json
import signal
import sys

from gi.repository import Gio, GLib

PATH = "/org/mpris/MediaPlayer2"
ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
XML = f"""<node>
  <interface name="{ROOT}">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="{PLAYER}">
    <method name="Next"/><method name="Previous"/><method name="Pause"/><method name="PlayPause"/>
    <method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
    <method name="SetPosition"><arg name="TrackId" type="o" direction="in"/><arg name="Position" type="x" direction="in"/></method>
    <method name="OpenUri"><arg name="Uri" type="s" direction="in"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="read"/>
    <property name="Metadata" type="a{{sv}}" access="read"/>
    <property name="Volume" type="d" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>"""

tracks = json.loads(open(sys.argv[1], encoding="utf-8").read())
state = {"index": 0, "connection": None}


def track():
    return tracks[min(state["index"], len(tracks) - 1)]


def metadata():
    t = track()
    return GLib.Variant(
        "a{sv}",
        {
            "mpris:trackid": GLib.Variant("o", f"/org/foamy/track/{state['index']}"),
            "mpris:length": GLib.Variant("x", 200_000_000),
            "xesam:title": GLib.Variant("s", t["title"]),
            "xesam:artist": GLib.Variant("as", [t["artist"]] if t["artist"] else []),
        },
    )


def properties(interface):
    if interface == ROOT:
        return {
            "CanQuit": GLib.Variant("b", False),
            "CanRaise": GLib.Variant("b", False),
            "HasTrackList": GLib.Variant("b", False),
            "Identity": GLib.Variant("s", "Spotify"),
            "DesktopEntry": GLib.Variant("s", "spotify"),
            "SupportedUriSchemes": GLib.Variant("as", []),
            "SupportedMimeTypes": GLib.Variant("as", []),
        }
    return {
        "PlaybackStatus": GLib.Variant("s", track().get("status", "Playing")),
        "Rate": GLib.Variant("d", 1.0),
        "Metadata": metadata(),
        "Volume": GLib.Variant("d", 0.5),
        "Position": GLib.Variant("x", 0),
        "MinimumRate": GLib.Variant("d", 1.0),
        "MaximumRate": GLib.Variant("d", 1.0),
        "CanGoNext": GLib.Variant("b", True),
        "CanGoPrevious": GLib.Variant("b", True),
        "CanPlay": GLib.Variant("b", True),
        "CanPause": GLib.Variant("b", True),
        "CanSeek": GLib.Variant("b", False),
        "CanControl": GLib.Variant("b", True),
    }


def on_call(connection, _sender, path, interface, method, _params, invocation):
    if interface == PLAYER and method == "Next" and state["index"] < len(tracks) - 1:
        state["index"] += 1
        changed = {k: v for k, v in properties(PLAYER).items() if k in ("Metadata", "PlaybackStatus")}
        connection.emit_signal(
            None,
            PATH,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (PLAYER, changed, [])),
        )
        print(f"FAKE MPRIS TRACK {state['index']}", flush=True)
    invocation.return_value(None)


def on_get(connection, _sender, path, interface, name):
    return properties(interface)[name]


def on_bus(connection, name):
    state["connection"] = connection
    for info in Gio.DBusNodeInfo.new_for_xml(XML).interfaces:
        connection.register_object(PATH, info, on_call, on_get, None)


loop = GLib.MainLoop()
Gio.bus_own_name(
    Gio.BusType.SESSION,
    "org.mpris.MediaPlayer2.spotify",
    Gio.BusNameOwnerFlags.NONE,
    on_bus,
    lambda _c, _n: print("FAKE MPRIS UP", flush=True),
    lambda _c, _n: loop.quit(),
)
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, loop.quit)
loop.run()
