# Foamy Media

Spotify and YouTube playback controls. Also supports spotifyd and spotify-player.

![Foamy Media screenshot](preview.png)

## Install

Requires Omarchy Quattro with MPRIS support and a supported media player.
Artwork processing uses `curl` and ImageMagick (`magick`); browser integration
uses Hyprland and the configured browser.

```sh
omarchy plugin add https://github.com/foamrider/foamy-media.git --enable
```

## Use

- Start playback, then left-click the widget to open the player.
- Right-click to play/pause; middle-click to skip to the next track.
- Use the panel for seeking, volume, shuffle, repeat, and source selection.
- Open the cog to change controls, appearance, language, and browser settings.

For YouTube, open **Browser settings → Use an open window** and select your
YouTube web app. Start a video first if it is not detected. Check the browser
and profile; ordinary browser tabs are not automatically detected.
The widget hides when no supported player has a track by default.

## Remove

```sh
omarchy plugin remove foamy.media
```

Removal stops the widget and its helpers. Spotify, browser profiles, YouTube
web apps, playback, and cached artwork remain available.

Omarchy manages the plugin entry in `shell.json`. Packages and data outside
the plugin directory are retained unless you remove them separately.

## License

Licensed under [MIT](LICENSE). Based on [Spotmarchy](LICENSE-SPOTMARCHY), with
[Omarchy](LICENSE-OMARCHY) and [Lucide](LICENSE-LUCIDE) components.

Provided **as is**, without warranty or guaranteed support. Use at your own risk.
