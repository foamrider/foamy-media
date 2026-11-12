// Tests for everything the widget knows that is not painting. Model.js has no
// Qt in it, so player matching, the label, and the whole album-colour pipeline
// run here: `node tests/model-test.js`.

const assert = require("assert")
const M = require("../Model.js")

// ------------------------------------------------------------ player matching
{
  const desktop = { dbusName: "org.mpris.MediaPlayer2.spotify", identity: "Spotify" }
  const daemon = { dbusName: "org.mpris.MediaPlayer2.spotifyd.instance7", identity: "spotifyd" }
  const tui = { dbusName: "org.mpris.MediaPlayer2.spotify_player", desktopEntry: "spotify-player" }
  const firefox = { dbusName: "org.mpris.MediaPlayer2.firefox.instance_1_2", identity: "Mozilla Firefox" }
  // Not Spotify, but its bus name contains the word.
  const decoy = { dbusName: "org.mpris.MediaPlayer2.notspotifyatall", identity: "Rhythmbox" }

  assert.ok(M.isSpotify(desktop))
  assert.ok(M.isSpotify(daemon))
  assert.ok(M.isSpotify(tui))
  assert.ok(!M.isSpotify(firefox))
  assert.ok(!M.isSpotify(decoy))
  assert.ok(!M.isSpotify(null))

  // A player that is actually making sound wins over one that is merely open,
  // so a forgotten paused instance never hides the live one.
  const paused = Object.assign({ isPlaying: false }, desktop)
  const playing = Object.assign({ isPlaying: true }, daemon)
  assert.strictEqual(M.findSpotify([paused, playing]), playing)
  assert.strictEqual(M.findSpotify([playing, paused]), playing)
  assert.strictEqual(M.findSpotify([paused]), paused)
  const emptyIdle = Object.assign({ isPlaying: false, trackTitle: "", trackArtist: "" }, desktop)
  const pausedTrack = Object.assign({ isPlaying: false, playbackState: 2, trackTitle: "Instant Crush" }, daemon)
  const stoppedTrack = Object.assign({ isPlaying: false, playbackState: 0, trackTitle: "Old track" }, desktop)
  assert.strictEqual(M.findSpotify([emptyIdle, pausedTrack], 0), pausedTrack)
  assert.strictEqual(M.findSpotify([pausedTrack, emptyIdle], 0), pausedTrack)
  assert.strictEqual(M.findSpotify([stoppedTrack, pausedTrack], 0), pausedTrack)
  assert.strictEqual(M.findSpotify([firefox]), null)
  assert.strictEqual(M.findSpotify([]), null)
  assert.strictEqual(M.findSpotify(undefined), null)

  const youtube = {
    dbusName: "org.mpris.MediaPlayer2.vivaldi.instance4510",
    identity: "Vivaldi",
    metadata: { "xesam:url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ" },
    trackTitle: "A YouTube video",
    isPlaying: true,
  }
  const youtubePaused = Object.assign({}, youtube, { isPlaying: false })
  const normalVivaldiMedia = Object.assign({}, youtube, {
    metadata: { "xesam:url": "https://vimeo.com/123" },
  })
  const youtubeInFirefox = Object.assign({}, youtube, {
    dbusName: "org.mpris.MediaPlayer2.firefox.instance_1_2",
  })

  assert.ok(M.isYoutube(youtube))
  assert.ok(M.isYoutube(Object.assign({}, youtube, {
    metadata: { "xesam:url": "https://youtube.com/watch?v=dQw4w9WgXcQ" },
  })))
  assert.ok(!M.isYoutube(normalVivaldiMedia))
  assert.ok(!M.isYoutube(youtubeInFirefox))
  assert.ok(!M.isYoutube(Object.assign({}, youtube, {
    metadata: { "xesam:url": "https://music.youtube.com/watch?v=test" },
  })))
  assert.ok(!M.isYoutube(Object.assign({}, youtube, {
    metadata: { "xesam:url": "https://youtube.com.evil.test/watch?v=test" },
  })))
  assert.ok(!M.isYoutube(Object.assign({}, youtube, {
    metadata: { "xesam:url": "https://youtube.com@evil.test/watch?v=test" },
  })))
  assert.ok(!M.isYoutube(Object.assign({}, youtube, { metadata: {} })))

  const youtubeWithoutUrl = Object.assign({}, youtube, { metadata: {} })
  assert.ok(M.isYoutube(youtubeWithoutUrl, "A YouTube video - YouTube"))
  assert.ok(!M.isYoutube(youtubeWithoutUrl, "A different video - YouTube"))
  assert.ok(!M.isYoutube(youtubeWithoutUrl, "A YouTube video - Vimeo"))
  assert.ok(!M.isYoutube(normalVivaldiMedia, "A YouTube video - YouTube"))

  // Browser window titles and MPRIS metadata can encode the same accent differently.
  const composedTitle = "ROS\u00c9 & Bruno Mars - APT. (Official Music Video)"
  const decomposedTitle = "ROSE\u0301 & Bruno Mars - APT. (Official Music Video)"
  const accentedYoutube = Object.assign({}, youtubeWithoutUrl, { trackTitle: composedTitle })
  assert.strictEqual(M.findYoutube([accentedYoutube], decomposedTitle + " - YouTube"), accentedYoutube)
  assert.ok(M.isYoutube(Object.assign({}, accentedYoutube, { trackTitle: decomposedTitle }), composedTitle + " - YouTube"))
  assert.ok(!M.isYoutube(accentedYoutube, "ROSE & Bruno Mars - APT. (Official Music Video) - YouTube"))
  assert.ok(!M.isYoutube(accentedYoutube, decomposedTitle + " - Vimeo"))
  assert.ok(!M.isYoutube(Object.assign({}, accentedYoutube, { metadata: normalVivaldiMedia.metadata }), decomposedTitle + " - YouTube"))

  assert.strictEqual(M.sourceKind(desktop), "spotify")
  assert.strictEqual(M.sourceKind(youtube), "youtube")
  assert.strictEqual(M.sourceKind(normalVivaldiMedia), "")
  assert.strictEqual(M.findYoutube([normalVivaldiMedia, youtubePaused, youtube]), youtube)
  assert.strictEqual(M.findYoutube([youtubePaused]), youtubePaused)
  assert.strictEqual(M.findYoutube([youtubeWithoutUrl], "A YouTube video - YouTube"), youtubeWithoutUrl)
  assert.strictEqual(M.findYoutube([youtubeWithoutUrl], "A different video - YouTube"), null)
  assert.strictEqual(M.findYoutube([normalVivaldiMedia]), null)
}

// -------------------------------------------------------------- the bar label
{
  const player = { trackTitle: "Instant Crush", trackArtist: "Daft Punk", isPlaying: true }
  assert.strictEqual(M.barLabel(player, true), "Instant Crush  ·  Daft Punk")
  assert.strictEqual(M.barLabel(player, false), "Instant Crush")
  assert.strictEqual(M.barLabel({ trackTitle: "", trackArtist: "Daft Punk" }, true), "Daft Punk")
  assert.strictEqual(M.barLabel({ trackTitle: "Solo", trackArtist: "" }, true), "Solo")
  assert.strictEqual(M.barLabel(null, true), "")

  assert.ok(M.hasTrackInformation(player))
  assert.ok(M.hasTrackInformation({ trackTitle: "", trackArtist: "Daft Punk" }))
  assert.ok(!M.hasTrackInformation({ trackTitle: "", trackArtist: "" }))
  assert.ok(!M.hasTrackInformation(null))

  const pausedTrack = Object.assign({}, player, { isPlaying: false, playbackState: 2 })
  const stoppedTrack = Object.assign({}, player, { isPlaying: false, playbackState: 0 })
  const emptyPlayer = { trackTitle: "", trackArtist: "", isPlaying: false, playbackState: 2 }
  assert.ok(M.hasDisplayableTrack(pausedTrack, 0))
  assert.ok(!M.hasDisplayableTrack(stoppedTrack, 0))
  assert.ok(M.shouldShowWidget(pausedTrack, null, true, 0))
  assert.ok(M.shouldShowWidget(null, pausedTrack, true, 0))
  assert.ok(!M.shouldShowWidget(stoppedTrack, null, true, 0))
  assert.ok(!M.shouldShowWidget(null, stoppedTrack, true, 0))
  assert.ok(!M.shouldShowWidget(emptyPlayer, null, true, 0))
  assert.ok(!M.shouldShowWidget(null, emptyPlayer, true, 0))
  assert.ok(M.shouldShowWidget(null, null, false, 0))

}

// ------------------------------------------------------------ the hover tooltip
{
  const WJ = "\u2060"
  const shown = (text) => text.split(WJ).join("") // what a reader sees
  const tip = (title, artist, prefix) => M.tooltipLabel({ trackTitle: title, trackArtist: artist }, prefix)

  // Normal text passes through untouched, prefix first.
  assert.strictEqual(tip("Instant Crush", "Daft Punk", ""), "Instant Crush  ·  Daft Punk")
  assert.strictEqual(tip("Instant Crush", "Daft Punk", "Paused — "), "Paused — Instant Crush  ·  Daft Punk")
  assert.strictEqual(tip("", "Daft Punk", ""), "Daft Punk")
  assert.strictEqual(tip("Solo", "", ""), "Solo")
  assert.strictEqual(tip("أغنية", "فنان", ""), "أغنية  ·  فنان")
  assert.strictEqual(M.tooltipLabel(null, "Paused — "), "")
  // The tooltip is the one place the artist always shows, whatever showArtist says.
  assert.strictEqual(tip("Title", "Artist", ""), M.barLabel({ trackTitle: "Title", trackArtist: "Artist" }, true))

  // Markup and entities stay literal: every `<` and `&` is followed by a word
  // joiner (so Qt's AutoText test cannot take it for markup), and nothing
  // else changes, so a plain-text sink draws exactly the original.
  const hostile = [
    ["<b>bold</b>", "<i>artist</i>"],
    ['<img src="file:///tmp/probe.png">', '<img src="https://example.com/x.png" width=4000>'],
    ["Tom & Jerry", "Simon & Garfunkel"],
    ["a < b > c", "&amp;"],
    ["&lt;b&gt;hi&lt;/b&gt;", "<!DOCTYPE html><p>x"],
    ["  <font color=red>x</font>", "<?xml version='1.0'?><b>y</b>"],
  ]
  for (const [title, artist] of hostile) {
    const out = tip(title, artist, "")
    assert.strictEqual(shown(out), title + "  ·  " + artist)
    for (let i = 0; i < out.length; i++) {
      if (out[i] === "<" || out[i] === "&") assert.strictEqual(out[i + 1], WJ, JSON.stringify(out))
    }
  }
  assert.strictEqual(M.literalTooltip("Spotify is not running"), "Spotify is not running")
  assert.strictEqual(M.literalTooltip("<b>"), "<" + WJ + "b>")
  assert.strictEqual(M.literalTooltip(undefined), "")

  // The kit's host-tooltip cap (FoamyText.tooltip, as Panel passes it) bounds
  // the whole line, prefix included, before the markup guard: a long title
  // and artist end in "…" within 100 code points, and the joiners after `<`
  // and `&` are added afterwards, so they neither count nor get cut off.
  const FoamyText = require("../kit/node-loader.cjs").load("FoamyText")
  const capped = (title, artist, prefix) =>
    M.tooltipLabel({ trackTitle: title, trackArtist: artist }, prefix, FoamyText.tooltip)
  assert.strictEqual(capped("Instant Crush", "Daft Punk", "Paused — "), "Paused — Instant Crush  ·  Daft Punk")
  const longLine = capped("t".repeat(80), "a".repeat(50), "Paused — ")
  assert.strictEqual(longLine, ("Paused — " + "t".repeat(80) + "  ·  " + "a".repeat(50)).slice(0, 99) + "\u2026")
  assert.strictEqual([...longLine].length, FoamyText.TOOLTIP_CHARS)
  const guarded = capped("<".repeat(99) + "x", "", "")
  assert.strictEqual(shown(guarded), "<".repeat(99) + "x")
  assert.strictEqual(guarded, ("<" + WJ).repeat(99) + "x")

  // Control characters cannot stack the tooltip into lines.
  assert.strictEqual(tip("one\ntwo\r\nthree\u2028four\tfive", "", ""), "one two three four five")
  assert.strictEqual(tip("a\u0000\u001b[31mb\u0085c", "", ""), "a [31mb c")

  // Each field is bounded, ellipsis included: the title to 100 code points
  // (YouTube's own maximum, so a real one is never cut), the artist to 60.
  const limit = M.tooltipTitleLimit
  const artistLimit = M.tooltipArtistLimit
  assert.strictEqual(limit, 100)
  assert.strictEqual(artistLimit, 60)
  assert.strictEqual(tip("t".repeat(100), "a".repeat(60), ""), "t".repeat(100) + "  ·  " + "a".repeat(60))
  const exact = "x".repeat(limit)
  assert.strictEqual(M.tooltipField(exact, limit), exact)
  const long = "y".repeat(5000)
  assert.strictEqual(M.tooltipField(long, limit), "y".repeat(limit - 1) + "\u2026")
  const both = tip(long, "z".repeat(5000), "Paused — ")
  assert.strictEqual(both, "Paused — " + "y".repeat(limit - 1) + "\u2026  ·  " + "z".repeat(artistLimit - 1) + "\u2026")
  // The bound counts what is shown, before the joiners go in.
  const angles = tip("<".repeat(500), "", "")
  assert.strictEqual(shown(angles), "<".repeat(limit - 1) + "\u2026")
  // Astral characters are counted and cut whole, never split into a lone surrogate.
  const emoji = M.tooltipField("\u{1F600}".repeat(200), limit)
  assert.strictEqual(emoji, "\u{1F600}".repeat(limit - 1) + "\u2026")
  assert.strictEqual(Array.from(emoji).length, limit)
  // A cut never strands a base letter from its combining mark or a ZWJ sequence half-built.
  const accents = "e\u0301".repeat(100) // 200 code points
  const cutAccents = M.tooltipField(accents, limit)
  assert.ok(/^(e\u0301)+\u2026$/.test(cutAccents), JSON.stringify(cutAccents))
  const family = "\u{1F468}\u200d\u{1F469}\u200d\u{1F467}"
  const cutFamily = M.tooltipField("a".repeat(limit - 3) + family, limit)
  assert.ok(!cutFamily.endsWith("\u200d\u2026") && !cutFamily.slice(0, -1).endsWith("\u200d"), JSON.stringify(cutFamily))
  assert.ok(Array.from(cutFamily).length <= limit)
  // A long RTL title keeps its characters in logical order.
  const rtl = "مرحبا ".repeat(60)
  assert.strictEqual(M.tooltipField(rtl, limit), rtl.slice(0, limit - 1) + "\u2026")
}

// ------------------------------------------------------------------- run time
{
  assert.strictEqual(M.formatTime(0), "0:00")
  assert.strictEqual(M.formatTime(9), "0:09")
  assert.strictEqual(M.formatTime(274.52), "4:34")
  assert.strictEqual(M.formatTime(3600), "1:00:00")
  assert.strictEqual(M.formatTime(3725), "1:02:05")
  // Never a negative clock, whatever the player reports.
  assert.strictEqual(M.formatTime(-5), "0:00")
  assert.strictEqual(M.formatTime(undefined), "0:00")
}

// ------------------------------------------------- what may be handed to sh(1)
{
  const art = "https://i.scdn.co/image/ab67616d0000b273d1ec82bc061a90006584aa9b"
  assert.strictEqual(M.artProbeTarget(art), art)
  assert.strictEqual(M.artProbeTarget("https://scdn.co/image/abc"), "https://scdn.co/image/abc")
  assert.strictEqual(M.artProbeTarget("https://open.scdn.co/image/abc"), "https://open.scdn.co/image/abc")
  assert.strictEqual(M.artProbeTarget("https://i.ytimg.com/vi/abc/hqdefault.jpg"), "https://i.ytimg.com/vi/abc/hqdefault.jpg")
  // Case in the host is not a bypass and not a rejection.
  assert.ok(M.artProbeTarget("https://I.SCDN.CO/image/abc"))
  assert.strictEqual(M.artProbeTarget("file:///home/example/cover.png"), "/home/example/cover.png")
  // A file on disk may legitimately have a space in its name.
  assert.strictEqual(M.artProbeTarget("file:///home/example/My%20Art.png"), "/home/example/My Art.png")

  // The host is matched on a label boundary. An earlier version used a bare
  // prefix pattern, which let anyone who registered "evilscdn.co" point the
  // probe at their own server.
  assert.ok(M.artHostAllowed("scdn.co"))
  assert.ok(M.artHostAllowed("i.scdn.co"))
  assert.ok(M.artHostAllowed("ytimg.com"))
  assert.ok(M.artHostAllowed("i.ytimg.com"))
  assert.ok(!M.artHostAllowed("evilscdn.co"))
  assert.ok(!M.artHostAllowed("evilytimg.com"))
  assert.ok(!M.artHostAllowed("scdn.co.evil.test"))
  assert.ok(!M.artHostAllowed("ytimg.com.evil.test"))
  assert.ok(!M.artHostAllowed(".scdn.co"))

  // Art URLs are metadata from another process, so everything that is not
  // plainly one of the two shapes a player publishes is refused, not probed.
  const refused = [
    "https://evilscdn.co/image/x",            // lookalike, no label boundary
    "https://myscdn.co/image/x",              // same
    "https://i.scdn.co.attacker.test/x",      // the real host as a prefix
    "https://i.ytimg.com.attacker.test/x",    // same for YouTube artwork
    "https://i.scdn.co@evil.test/x",          // userinfo, not a host
    "https://i.scdn.co:8443/x",               // a port is never part of one
    "https://evil.test/#https://i.scdn.co/",  // the allowed host in a fragment
    "https://evil.test/?u=https://i.scdn.co", // and in a query
    "http://i.scdn.co/image/x",               // plaintext
    "HTTPS://i.scdn.co/image/x",              // scheme must be exact
    "https:///image/x",                       // no host at all
    "file://remote/share/art.png",            // names another machine
    "file://../../etc/passwd",                // not an absolute local path
    "https://i.scdn.co/image/a b",            // a raw space in a URL
    "file:///home/example/a%00b.png",            // a control character in a path
    "$(rm -rf ~)",
    "; rm -rf ~",
    "`id`",
    "|| curl evil.test",
    "", null, undefined
  ]
  refused.forEach(function (value) {
    assert.strictEqual(M.artProbeTarget(value), null, JSON.stringify(value))
  })
}

// ------------------------------------------ and how the helper is launched
{
  // The probe is the native helper now: no shell script, no awk, no curl.
  // tests/probe-test.sh runs the real binary against real fixtures, and
  // `cargo test` in native/ covers its bounds one by one.
  assert.strictEqual(M.artProbeScript, undefined)
  assert.deepStrictEqual(M.artProbeArgs("/home/example/a b.png"), ["art-probe", "/home/example/a b.png"])
  assert.deepStrictEqual(M.artProbeArgs("https://i.scdn.co/image/x"), ["art-probe", "https://i.scdn.co/image/x"])

  const fs = require("fs")
  const path = require("path")
  const service = fs.readFileSync(path.join(__dirname, "..", "MediaService.qml"), "utf8")
  // The target is an argument of the bundled binary, never spliced into code.
  // The only shell in the file is the window-class hint's fixed script (a
  // `head -c` bound, REVIEW section 5): a literal with no outside values.
  const shells = service.split("\n").filter(line => /\/bin\/sh|"sh", *"-c"|bash", *"-c"/.test(line)).map(line => line.trim())
  assert.deepStrictEqual(shells, ['command: ["bash", "-c", "set -o pipefail; timeout --kill-after=1s 3s omarchy-webapp-window-class https://youtube.com/ | head -c 512"]'],
    "the art probe must not run through a shell script")
  assert.ok(/FoamyNative\.command\(root\.pluginDir, "foamy-media-helper", Model\.artProbeArgs\(target\)\)/.test(service))
  // And its exits are read the way DESIGN.md asks: 126/127 mean there is no
  // helper for this CPU, which is said once and never retried.
  assert.ok(/FoamyNative\.unavailable\(exitCode\)/.test(service))
  assert.ok(/root\.artHelperUnavailable = true/.test(service))
  assert.ok(/!target \|\| root\.artHelperUnavailable/.test(service), "an unavailable helper is not launched again")
  assert.ok(/failure === "TLS_UNSUPPORTED"/.test(service), "a CPU without HTTPS support is not retried")
  const settings = fs.readFileSync(path.join(__dirname, "..", "MediaSettings.qml"), "utf8")
  assert.ok(settings.indexOf("This plugin's helper isn't available for this CPU.") !== -1)
  const native = require("../kit/node-loader.cjs").load("FoamyNative")
  assert.strictEqual(native.UNAVAILABLE_TEXT, "This plugin's helper isn't available for this CPU.")

  // The helper checks the host again: its list is this one.
  const main = fs.readFileSync(path.join(__dirname, "..", "native", "src", "main.rs"), "utf8")
  const hosts = /const HOSTS: \[&str; \d+\] = \[([^\]]*)\]/.exec(main)
  assert.ok(hosts, "native/src/main.rs HOSTS")
  ;["scdn.co", "ytimg.com"].forEach(function (host) { assert.ok(M.artHostAllowed(host)) })
  assert.deepStrictEqual(JSON.parse("[" + hosts[1] + "]"), ["scdn.co", "ytimg.com"])
}

// ------------------------------------- nothing else may load the art URL
{
  // The reported defect: the probe was hardened while the two QML Image
  // elements still took the raw MPRIS URL, so the displayed cover skipped
  // every check the probe made. Qt would have fetched any origin, followed
  // redirects, and decoded whatever its image plugins handle -- an Omarchy
  // install ships the SVG and PDF ones -- inside the shell process.
  //
  // Everything shown now comes from the file the probe wrote, so this asserts
  // the property directly against the QML rather than trusting it to stay so.
  const fs = require("fs")
  const path = require("path")
  const read = (name) => fs.readFileSync(path.join(__dirname, "..", name), "utf8")
  const sources = (name) => read(name)
    .split("\n")
    .map(function (line, index) { return { line: line.trim(), number: index + 1, file: name } })
    .filter(function (entry) { return /^source\s*:/.test(entry.line) })

  const loaders = [].concat(sources("Panel.qml"), sources("MediaView.qml"), sources("BarContent.qml"))
  assert.ok(loaders.length >= 2, "expected the popup to have image sources to check")

  // No source of any kind may name the raw URL. This is the invariant that
  // was broken; `source: artBlurSource` naming a sibling item is fine, an
  // art URL is not.
  loaders.forEach(function (entry) {
    assert.ok(!/\bartUrl\b/.test(entry.line), entry.file + ":" + entry.number + " loads the raw art URL: " + entry.line)
  })

  // The covers that are displayed come from the probed file, both of them:
  // the thumbnail and the blurred backdrop. `artSource` is the Panel's URL of
  // the file the probe wrote (MediaService.artFile), and only while it
  // belongs to the current track.
  const probed = loaders.filter(function (entry) { return /media\.artSource\b/.test(entry.line) })
  assert.strictEqual(probed.length, 2, "expected exactly two loads of the probed cover")
  assert.ok(/readonly property string artSource: artShown && imagesActive \? Model\.fileUrl\(MediaService\.artFile\) : ""/
    .test(read("Panel.qml")), "Panel.artSource must come from the probed file of the current track")
}

// ------------------------------------------------------ the file it hands over
{
  const probe = M.parseArtProbe(JSON.stringify({
    ok: true,
    mean: "#102030",
    file: "/home/example/.cache/foamy-media/covers/abc123.png",
    swatches: [{ count: 2581, hex: "#102030" }]
  }))
  assert.strictEqual(probe.file, "/home/example/.cache/foamy-media/covers/abc123.png")

  // A reply without a usable file still parses; there is simply nothing to show.
  const colourOnly = M.parseArtProbe('{"ok":true,"mean":"#102030","swatches":[{"count":10,"hex":"#102030"}]}')
  assert.strictEqual(colourOnly.file, "")
  ;["relative/x.png", "/a\nb.png", 7, null].forEach(function (file) {
    const reply = M.parseArtProbe(JSON.stringify({ ok: true, mean: "#102030", file: file, swatches: [] }))
    assert.strictEqual(reply.file, "", JSON.stringify(file))
  })

  // A path becomes a URL with every segment encoded, so a space or a "#" in it
  // cannot end the path early.
  assert.strictEqual(M.fileUrl("/home/example/cover.png"), "file:///home/example/cover.png")
  assert.strictEqual(M.fileUrl("/home/my art/a b.png"), "file:///home/my%20art/a%20b.png")
  assert.strictEqual(M.fileUrl("/home/a#b/c.png"), "file:///home/a%23b/c.png")
  assert.strictEqual(M.fileUrl(""), "")
  assert.strictEqual(M.fileUrl(null), "")
}

// --------------------------------------------------------- reading the artwork
{
  // Real output, from Random Access Memories (Drumless Edition) — a cover that
  // is almost entirely pale beige.
  // The helper parses ImageMagick's histogram lines into swatches
  // (native/src/magick.rs); this is the reply it gives for that cover.
  const beige = JSON.stringify({
    ok: true,
    mean: "#d2cfc8",
    file: "/home/example/.cache/foamy-media/covers/beige.png",
    swatches: [
      { count: 233, hex: "#b9b4a9" },
      { count: 2581, hex: "#d6d4ce" },
      { count: 2531, hex: "#d8d6d1" },
      { count: 167, hex: "#d9d6cf" }
    ]
  })

  const probe = M.parseArtProbe(beige)
  assert.strictEqual(probe.mean, "#d2cfc8")
  // Nothing on this cover is saturated, so area decides.
  assert.strictEqual(probe.dominant, "#d6d4ce")
  assert.ok(probe.luma > 0.8)

  assert.strictEqual(M.parseArtProbe(""), null)
  assert.strictEqual(M.parseArtProbe("magick: unable to open image"), null)
  assert.strictEqual(M.parseArtProbe(null), null)
  assert.strictEqual(M.parseArtProbe("[1,2]"), null)
  assert.strictEqual(M.parseArtProbe('{"ok":true}'), null)
  assert.strictEqual(M.parseArtProbe('{"ok":true,"mean":"D2CFC8","swatches":[{"count":1,"hex":"red"}]}'), null)
  // A failure reply is no cover, and its code is what decides a retry.
  const failed = '{"ok":false,"code":"TLS_UNSUPPORTED","error":"HTTPS isn\'t supported on this CPU"}'
  assert.strictEqual(M.parseArtProbe(failed), null)
  assert.strictEqual(M.artProbeFailure(failed), "TLS_UNSUPPORTED")
  assert.strictEqual(M.artProbeFailure(beige), "")
  assert.strictEqual(M.artProbeFailure("not json"), "")
  assert.strictEqual(M.artProbeFailure(""), "")
  // Only the mean: the colour falls back to it.
  const meanOnly = M.parseArtProbe('{"ok":true,"mean":"#204080","file":"/c/x.png","swatches":[]}')
  assert.strictEqual(meanOnly.dominant, "#204080")

  // A dark cover with one saturated area: the colour a person would name is
  // the green, not the near-black that covers most of the sleeve.
  const dark = M.pickDominant([
    { count: 4800, hex: "#0d0d12" },
    { count: 900, hex: "#1db954" },
    { count: 600, hex: "#141820" }
  ])
  assert.strictEqual(dark, "#1db954")

  // Mid-tones beat both ends, so neither the black bar nor the white text on
  // a sleeve is mistaken for its colour.
  assert.strictEqual(M.pickDominant([
    { count: 2000, hex: "#000000" },
    { count: 2000, hex: "#ffffff" },
    { count: 800, hex: "#b2313a" }
  ]), "#b2313a")

  assert.strictEqual(M.pickDominant([]), null)
  assert.strictEqual(M.pickDominant(null), null)
}

// ------------------------------------------------------------ the adaptive bit
{
  // The point of the whole feature: a brighter cover is covered more heavily,
  // so the panel's background lands in the same band whatever is playing.
  const dark = M.scrimAlpha(0.15, 55)
  const mid = M.scrimAlpha(0.47, 55)
  const bright = M.scrimAlpha(0.95, 55)
  assert.ok(dark < mid && mid < bright, [dark, mid, bright].join(" "))

  // More cover showing means less scrim, at every brightness.
  assert.ok(M.scrimAlpha(0.5, 90) < M.scrimAlpha(0.5, 55))
  assert.ok(M.scrimAlpha(0.5, 55) < M.scrimAlpha(0.5, 10))

  // Always a usable alpha, including from settings that make no sense.
  ;[0, 55, 100, -40, 900, NaN, undefined, "55"].forEach(function (intensity) {
    [0, 0.5, 1, -1, 2, NaN].forEach(function (luma) {
      const a = M.scrimAlpha(luma, intensity)
      assert.ok(a >= 0.18 && a <= 0.97, intensity + "/" + luma + " -> " + a)
    })
  })

  // Bright covers are also pulled down at the source; dark ones are left alone.
  assert.strictEqual(M.artBrightness(0.1), -0)
  assert.ok(M.artBrightness(0.9) < -0.3)
  assert.ok(M.artBrightness(1) >= -0.42)
}

// ------------------------------------------------------------- accent contrast
{
  // A near-black cover still has to yield a visible accent.
  const lifted = M.ensureContrast("#101a12", 0.48)
  assert.ok(M.toHsl(lifted).l >= 0.48, lifted)

  // One that is already bright enough is left exactly as it is.
  assert.strictEqual(M.ensureContrast("#1DB954", 0.30), "#1db954")

  // Lifting keeps the hue — an accent taken from a red cover stays red.
  const red = M.ensureContrast("#2a0508", 0.48)
  const hue = M.toHsl(red).h
  assert.ok(hue < 0.05 || hue > 0.95, red + " hue " + hue)

  assert.strictEqual(M.normalizeHex("#ABCDEF"), "#abcdef")
  assert.strictEqual(M.normalizeHex("not a colour"), "#000000")
  assert.strictEqual(M.luminance("#000000"), 0)
  // The Rec. 709 weights are floats, so white lands a hair under one.
  assert.ok(Math.abs(M.luminance("#ffffff") - 1) < 1e-9)
  assert.ok(M.luminance("#00ff00") > M.luminance("#0000ff"))

  // hsl round trip, since the accent path leans on it.
  ;["#1db954", "#b2313a", "#7f7f7f", "#ffffff", "#000000"].forEach(function (hex) {
    const hsl = M.toHsl(hex)
    const back = M.fromHsl(hsl.h, hsl.s, hsl.l)
    const a = parseInt(hex.slice(1), 16)
    const b = parseInt(back.slice(1), 16)
    for (let shift = 0; shift <= 16; shift += 8) {
      assert.ok(Math.abs(((a >> shift) & 255) - ((b >> shift) & 255)) <= 1, hex + " -> " + back)
    }
  })
}

// ------------------------------------------------------- source selection
{
  // Startup: a playing source first (the focused YouTube window wins a tie).
  assert.strictEqual(M.initialSource(true, true, true, true, true, true, true), "youtube")
  assert.strictEqual(M.initialSource(true, false, true, true, true, true, true), "spotify")
  assert.strictEqual(M.initialSource(false, false, true, true, false, true, true), "youtube")
  assert.strictEqual(M.initialSource(false, false, false, false, true, true, true), "youtube")
  assert.strictEqual(M.initialSource(false, false, false, false, false, false, true), "youtube")
  assert.strictEqual(M.initialSource(false, false, false, false, false, false, false), "")

  const state = (o) => Object.assign({ spotifyPlaying: false, youtubePlaying: false, spotifyHasTrack: false,
    youtubeHasTrack: false, spotifyOpen: false, youtubeOpen: false }, o)
  assert.strictEqual(M.reconcileSource("spotify", state({ youtubePlaying: true })), "youtube")
  assert.strictEqual(M.reconcileSource("youtube", state({ spotifyPlaying: true })), "spotify")
  // Both playing: keep the user's choice.
  assert.strictEqual(M.reconcileSource("youtube", state({ spotifyPlaying: true, youtubePlaying: true, spotifyHasTrack: true, youtubeHasTrack: true, spotifyOpen: true, youtubeOpen: true })), "youtube")
  // A paused track beats an open but empty app.
  assert.strictEqual(M.reconcileSource("youtube", state({ spotifyHasTrack: true, youtubeOpen: true })), "spotify")
  assert.strictEqual(M.reconcileSource("youtube", state({ youtubeHasTrack: true, spotifyHasTrack: true, youtubeOpen: true, spotifyOpen: true })), "youtube")
  // The selected app closed: fall back to an open one.
  assert.strictEqual(M.reconcileSource("spotify", state({ youtubeOpen: true })), "youtube")
  assert.strictEqual(M.reconcileSource("youtube", state({})), "spotify")
}

// ------------------------------------------------------------ position tick
{
  // About one re-read per pixel the underline gains, between 1 s and 5 s.
  assert.strictEqual(M.progressTickInterval(240, 188), 1277)
  assert.strictEqual(M.progressTickInterval(60, 200), 1000)
  assert.strictEqual(M.progressTickInterval(3600, 200), 5000)
  assert.strictEqual(M.progressTickInterval(0, 200), 5000)
  assert.strictEqual(M.progressTickInterval(240, 0), 5000)
  assert.strictEqual(M.progressTickInterval(NaN, NaN), 5000)
}

console.log("ok — model tests passed")
