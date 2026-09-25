# Foamy Media

Spotify and a dedicated YouTube web app in the Omarchy Quattro bar. Includes
track information, artwork, progress, seeking, volume, shuffle, repeat, and
source switching. Playback uses Quickshell's MPRIS service rather than polling
`playerctl`.

## Install

```sh
omarchy plugin add https://github.com/foamrider/foamy-media.git --enable
```

Requires Omarchy Quattro. Spotify, spotifyd, and spotify-player are supported.
Artwork additionally requires `curl` and ImageMagick (`magick`). Without these,
playback still works but artwork is unavailable. No account credentials or
Spotify API keys are needed.

## Controls

By default, left-click opens the popup and right-click plays/pauses. Enable
**Left-click plays/pauses** to exchange those actions. Middle-click skips to the
next track. The wheel changes tracks, adjusts volume, or does nothing, according
to the selected setting. A touchpad swipe skips one track per gesture.

When both sources play, the most recently started source takes control. The
footer also lets you choose a source. Switching sources never pauses the other
player. Paused tracks remain visible; stopped or empty players are hidden by
default. The bar's Add/Edit Widgets interface remains available when hidden.

## Settings

Open the popup and select its gear button. Changes are saved through Omarchy's
shell API to this widget's entry in `~/.config/omarchy/shell.json`. No separate
preferences file is created. Tab navigates controls; Escape returns from settings
or closes the player. Dropdowns support arrow keys and Enter. Invalid values
show an error and are not saved.

| Key | Default | Meaning |
| --- | --- | --- |
| `language` | `system` | System language, `nb` (Norsk bokmål), or `en` (English) |
| `leftClick` | `Open panel` | The switch selects `Play/pause`; right-click always takes the other action |
| `scrollAction` | `Previous/next track` | Also accepts `Volume` or `Nothing` |
| `volumeStep` | `5` | Volume change per wheel step, 1–20 percent |
| `hideWhenClosed` | `true` | Hide when players are stopped, empty, or closed; paused tracks remain visible |
| `maxLabelWidth` | `200` | Track label width, 60–600 logical pixels |
| `showArtist` | `true` | Artist alongside the title |
| `showProgress` | `true` | Progress underline in the bar |
| `animateTitle` | `true` | Scroll overflowing track text |
| `showEqualizer` | `true` | Animated playback indicator in the bar and source tabs |
| `accent` | `Source color` | Also accepts `Album art`, `Theme accent`, or `Bar foreground` |
| `artBackground` | `true` | Blur the artwork behind the popup header |
| `artIntensity` | `55` | Artwork intensity, 0–100; brightness also adapts to the cover |
| `youtubeEnabled` | `true` | Enable dedicated YouTube web-app integration |
| `youtubeBrowser` | `vivaldi` | Browser executable name on PATH |
| `youtubeProfile` | `Default` | Browser profile used when launching the web app |
| `youtubeAppId` | `vivaldi-youtube.com__-Default` | Exact Wayland app ID of the dedicated YouTube window |
| `youtubeMprisName` | `vivaldi` | Browser part of `org.mpris.MediaPlayer2.<name>[.instance]` |

System language selects Norwegian for `nb`, `nn`, or `no` locales and English
otherwise. Language changes update the plugin's own settings and player labels;
track metadata and Omarchy's generic widget editor are not translated by it.

The YouTube defaults match Vivaldi's Default profile. Other Chromium-family
browsers require matching executable, profile, Wayland app ID, and MPRIS name;
the defaults do not claim automatic browser discovery. Use `hyprctl clients -j`
to inspect window IDs and `busctl --user list` to inspect MPRIS bus names.
Detection requires the exact configured window plus a YouTube URL or an exact
`<track title> - YouTube` window-title match. Ordinary browser media, YouTube
Music, and lookalike domains are excluded. A shared browser MPRIS service can
still be ambiguous across profiles or identical titles. Disable integration if
that restriction does not fit your browser setup.

Example widget entry (inside a bar layout section):

```json
{
  "id": "foamy.media",
  "leftClick": "Play/pause",
  "language": "system",
  "maxLabelWidth": 300
}
```

## Artwork and privacy

Artwork URLs arrive from local MPRIS players. Remote artwork is fetched only
from HTTPS hosts under `scdn.co` or `ytimg.com`, without redirects. Downloads,
decoded dimensions, resource use, and formats are bounded. Local file artwork
is also accepted. Only a re-encoded, metadata-stripped raster image is loaded
into QML. The last eight covers live under
`$XDG_CACHE_HOME/foamy-media/covers` (default `~/.cache/foamy-media/covers`).

There is no telemetry, account configuration, or listening-history database.
Artwork requests go to the media provider. Diagnostic IPC returns current track
metadata and, for `artDebug`, local artwork paths; review that output before
sharing it. No runtime cache or desktop configuration belongs in this repository.

## IPC

```sh
omarchy-shell foamy.media toggle
omarchy-shell foamy.media settings
omarchy-shell foamy.media playPause
omarchy-shell foamy.media next
omarchy-shell foamy.media previous
omarchy-shell foamy.media shuffle
omarchy-shell foamy.media loop
omarchy-shell foamy.media launch
omarchy-shell foamy.media status
```

Also available: `open`, `close`, `artDebug`, `reprobeArt`, and `wheelDebug`.

```sh
omarchy bar move foamy.media --section right
omarchy plugin remove foamy.media
```

## Development

```sh
node test/model-test.js
node test/preferences-test.js
sh test/probe-test.sh
omarchy plugin validate .
```

The probe tests use generated local fixtures and a disposable cache; they do not
need network access or a running player. After editing QML, run
`omarchy restart shell` before testing. Validate artwork on a live GPU: offscreen
QML rendering can omit shader blur. Validate settings in both languages,
keyboard navigation, persistence after restart, click mapping, and missing-player
behavior. Browser matching tests use synthetic metadata; test a configured browser
live before claiming support for it.

## License and attribution

MIT. Foamy Media builds on [Spotmarchy](https://github.com/mich-nduka/spotmarchy)
by Mich Nduka. Its copyright and permission notice are preserved in
[LICENSE-SPOTMARCHY](LICENSE-SPOTMARCHY). The popup lifecycle and dropdown derive
from Omarchy, whose notice is in [LICENSE-OMARCHY](LICENSE-OMARCHY).
Foamy changes are covered by [LICENSE](LICENSE).
