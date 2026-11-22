// Pure helpers for the Spotify and YouTube bar widget. Kept out of Panel.qml
// so the QML stays declarative and these stay trivially testable.

// Spotify's own MPRIS bus is org.mpris.MediaPlayer2.spotify, but the same
// widget should also drive the headless clients people run instead of the
// desktop app, so match on bus name, desktop entry, and identity.
function isSpotify(player) {
  if (!player) return false

  var dbusName = String(player.dbusName || "").toLowerCase()
  var desktopEntry = String(player.desktopEntry || "").toLowerCase()
  var identity = String(player.identity || "").toLowerCase()

  if (dbusName.indexOf("mediaplayer2.spotify") !== -1) return true
  if (desktopEntry === "spotify" || desktopEntry === "spotifyd" || desktopEntry === "spotify-player") return true
  return identity === "spotify" || identity === "spotifyd"
}

function metadataString(player, key) {
  if (!player || !player.metadata) return ""
  var value = player.metadata[key]
  return value === undefined || value === null ? "" : String(value)
}

function urlHost(value) {
  var url = String(value || "")
  if (url.indexOf("https://") !== 0 || artUnprintable(url)) return ""

  var authority = url.substring(8).split(/[/?#]/)[0]
  if (!authority || authority.indexOf("@") !== -1 || authority.indexOf(":") !== -1) return ""
  return authority.toLowerCase()
}

function isYoutubePageUrl(value) {
  var host = urlHost(value)
  return host === "youtube.com" || host === "www.youtube.com"
}

function youtubeWindowTitleMatches(player, windowTitle) {
  // Match canonically equivalent accents from browser titles and MPRIS metadata.
  var title = String(player && player.trackTitle || "").trim().normalize("NFC")
  var toplevelTitle = String(windowTitle || "").trim().normalize("NFC")
  return title !== "" && toplevelTitle === title + " - YouTube"
}

// Vivaldi does not currently publish xesam:url for the dedicated web app. If
// it appears in a future release, use it; otherwise require the MPRIS title to
// match the exact YouTube toplevel title supplied by Panel.qml. The panel only
// supplies that title after it finds the dedicated app ID.
function isYoutube(player, youtubeWindowTitle, browserName) {
  if (!player) return false
  var dbusName = String(player.dbusName || "").toLowerCase()
  var prefix = "org.mpris.mediaplayer2." + String(browserName || "vivaldi").toLowerCase()
  if (dbusName !== prefix && dbusName.indexOf(prefix + ".") !== 0) return false
  var pageUrl = metadataString(player, "xesam:url")
  if (pageUrl !== "") return isYoutubePageUrl(pageUrl)
  return youtubeWindowTitleMatches(player, youtubeWindowTitle)
}

function sourceKind(player, youtubeWindowTitle, browserName) {
  if (isSpotify(player)) return "spotify"
  if (isYoutube(player, youtubeWindowTitle, browserName)) return "youtube"
  return ""
}

function findSource(players, kind, youtubeWindowTitle, stoppedState, browserName) {
  var list = players && players.length !== undefined ? players : []
  var idle = null
  var idleWithTrack = null

  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (sourceKind(p, youtubeWindowTitle, browserName) !== kind) continue
    if (p.isPlaying) return p
    if (!idleWithTrack && hasDisplayableTrack(p, stoppedState)) idleWithTrack = p
    if (!idle) idle = p
  }

  return idleWithTrack || idle
}

// A playing client wins over an idle one. Among idle clients, keep the paused
// track ahead of an empty instance so it remains visible in the bar.
function findSpotify(players, stoppedState) {
  return findSource(players, "spotify", "", stoppedState)
}

function findYoutube(players, youtubeWindowTitle, stoppedState, browserName) {
  return findSource(players, "youtube", youtubeWindowTitle, stoppedState, browserName)
}

function barLabel(player, showArtist) {
  if (!player) return ""

  var title = String(player.trackTitle || "")
  var artist = String(player.trackArtist || "")

  if (!title) return artist
  if (!showArtist || !artist) return title
  return title + "  ·  " + artist
}

// ------------------------------------------------------------------ tooltip
//
// The hover tooltip is the one place the widget hands track metadata to a
// sink it does not own: the host bar's tooltip Text. Omarchy 4.5 draws it as
// plain text, but the plugin API only promises "text", and a Text left on
// AutoText would read a title like `<img src=…>` as markup. So the tooltip is
// built here, bounded and made literal for both readings.

// Code points per field, ellipsis included. YouTube titles stop at 100, so a
// title is only cut when a player publishes something no store would; a long
// list of featured artists gives way first. The whole tooltip stays narrower
// than a 1366-pixel screen.
var tooltipTitleLimit = 100
var tooltipArtistLimit = 60
// The whole line, prefix included: the kit's FoamyText.TOOLTIP_CHARS. The
// line is cut here, never between a letter and its marks or inside an emoji
// sequence or a flag (continuesCluster, splitsFlag), so the kit's code-point
// cap that Panel applies after it never has to cut.
var tooltipLineLimit = 100

// Every combining mark (Unicode 16, general category M) outside the blocks
// that continuesCluster names, as pairs of first and last code point: the
// points, vowel signs and viramas of the Cyrillic, Hebrew, Arabic, Indic,
// Southeast Asian, Tibetan and other scripts, the kana voiced sound marks,
// and the marks past U+FFFF. Qt's JavaScript has no Unicode property
// escapes, so the ranges are listed here.
var scriptMarks = [
  0x0483, 0x0489,
  0x0591, 0x05bd, 0x05bf, 0x05bf, 0x05c1, 0x05c2, 0x05c4, 0x05c5, 0x05c7, 0x05c7, 0x0610, 0x061a,
  0x064b, 0x065f, 0x0670, 0x0670, 0x06d6, 0x06dc, 0x06df, 0x06e4, 0x06e7, 0x06e8, 0x06ea, 0x06ed,
  0x0711, 0x0711, 0x0730, 0x074a, 0x07a6, 0x07b0, 0x07eb, 0x07f3, 0x07fd, 0x07fd, 0x0816, 0x0819,
  0x081b, 0x0823, 0x0825, 0x0827, 0x0829, 0x082d, 0x0859, 0x085b, 0x0897, 0x089f, 0x08ca, 0x08e1,
  0x08e3, 0x0903, 0x093a, 0x093c, 0x093e, 0x094f, 0x0951, 0x0957, 0x0962, 0x0963, 0x0981, 0x0983,
  0x09bc, 0x09bc, 0x09be, 0x09c4, 0x09c7, 0x09c8, 0x09cb, 0x09cd, 0x09d7, 0x09d7, 0x09e2, 0x09e3,
  0x09fe, 0x09fe, 0x0a01, 0x0a03, 0x0a3c, 0x0a3c, 0x0a3e, 0x0a42, 0x0a47, 0x0a48, 0x0a4b, 0x0a4d,
  0x0a51, 0x0a51, 0x0a70, 0x0a71, 0x0a75, 0x0a75, 0x0a81, 0x0a83, 0x0abc, 0x0abc, 0x0abe, 0x0ac5,
  0x0ac7, 0x0ac9, 0x0acb, 0x0acd, 0x0ae2, 0x0ae3, 0x0afa, 0x0aff, 0x0b01, 0x0b03, 0x0b3c, 0x0b3c,
  0x0b3e, 0x0b44, 0x0b47, 0x0b48, 0x0b4b, 0x0b4d, 0x0b55, 0x0b57, 0x0b62, 0x0b63, 0x0b82, 0x0b82,
  0x0bbe, 0x0bc2, 0x0bc6, 0x0bc8, 0x0bca, 0x0bcd, 0x0bd7, 0x0bd7, 0x0c00, 0x0c04, 0x0c3c, 0x0c3c,
  0x0c3e, 0x0c44, 0x0c46, 0x0c48, 0x0c4a, 0x0c4d, 0x0c55, 0x0c56, 0x0c62, 0x0c63, 0x0c81, 0x0c83,
  0x0cbc, 0x0cbc, 0x0cbe, 0x0cc4, 0x0cc6, 0x0cc8, 0x0cca, 0x0ccd, 0x0cd5, 0x0cd6, 0x0ce2, 0x0ce3,
  0x0cf3, 0x0cf3, 0x0d00, 0x0d03, 0x0d3b, 0x0d3c, 0x0d3e, 0x0d44, 0x0d46, 0x0d48, 0x0d4a, 0x0d4d,
  0x0d57, 0x0d57, 0x0d62, 0x0d63, 0x0d81, 0x0d83, 0x0dca, 0x0dca, 0x0dcf, 0x0dd4, 0x0dd6, 0x0dd6,
  0x0dd8, 0x0ddf, 0x0df2, 0x0df3, 0x0e31, 0x0e31, 0x0e34, 0x0e3a, 0x0e47, 0x0e4e, 0x0eb1, 0x0eb1,
  0x0eb4, 0x0ebc, 0x0ec8, 0x0ece, 0x0f18, 0x0f19, 0x0f35, 0x0f35, 0x0f37, 0x0f37, 0x0f39, 0x0f39,
  0x0f3e, 0x0f3f, 0x0f71, 0x0f84, 0x0f86, 0x0f87, 0x0f8d, 0x0f97, 0x0f99, 0x0fbc, 0x0fc6, 0x0fc6,
  0x102b, 0x103e, 0x1056, 0x1059, 0x105e, 0x1060, 0x1062, 0x1064, 0x1067, 0x106d, 0x1071, 0x1074,
  0x1082, 0x108d, 0x108f, 0x108f, 0x109a, 0x109d, 0x135d, 0x135f, 0x1712, 0x1715, 0x1732, 0x1734,
  0x1752, 0x1753, 0x1772, 0x1773, 0x17b4, 0x17d3, 0x17dd, 0x17dd, 0x180b, 0x180d, 0x180f, 0x180f,
  0x1885, 0x1886, 0x18a9, 0x18a9, 0x1920, 0x192b, 0x1930, 0x193b, 0x1a17, 0x1a1b, 0x1a55, 0x1a5e,
  0x1a60, 0x1a7c, 0x1a7f, 0x1a7f, 0x1b00, 0x1b04, 0x1b34, 0x1b44, 0x1b6b, 0x1b73, 0x1b80, 0x1b82,
  0x1ba1, 0x1bad, 0x1be6, 0x1bf3, 0x1c24, 0x1c37, 0x1cd0, 0x1cd2, 0x1cd4, 0x1ce8, 0x1ced, 0x1ced,
  0x1cf4, 0x1cf4, 0x1cf7, 0x1cf9, 0x2cef, 0x2cf1, 0x2d7f, 0x2d7f, 0x2de0, 0x2dff, 0x302a, 0x302f,
  0x3099, 0x309a, 0xa66f, 0xa672, 0xa674, 0xa67d, 0xa69e, 0xa69f, 0xa6f0, 0xa6f1, 0xa802, 0xa802,
  0xa806, 0xa806, 0xa80b, 0xa80b, 0xa823, 0xa827, 0xa82c, 0xa82c, 0xa880, 0xa881, 0xa8b4, 0xa8c5,
  0xa8e0, 0xa8f1, 0xa8ff, 0xa8ff, 0xa926, 0xa92d, 0xa947, 0xa953, 0xa980, 0xa983, 0xa9b3, 0xa9c0,
  0xa9e5, 0xa9e5, 0xaa29, 0xaa36, 0xaa43, 0xaa43, 0xaa4c, 0xaa4d, 0xaa7b, 0xaa7d, 0xaab0, 0xaab0,
  0xaab2, 0xaab4, 0xaab7, 0xaab8, 0xaabe, 0xaabf, 0xaac1, 0xaac1, 0xaaeb, 0xaaef, 0xaaf5, 0xaaf6,
  0xabe3, 0xabea, 0xabec, 0xabed, 0xfb1e, 0xfb1e, 0x101fd, 0x101fd, 0x102e0, 0x102e0, 0x10376, 0x1037a,
  0x10a01, 0x10a03, 0x10a05, 0x10a06, 0x10a0c, 0x10a0f, 0x10a38, 0x10a3a, 0x10a3f, 0x10a3f, 0x10ae5, 0x10ae6,
  0x10d24, 0x10d27, 0x10d69, 0x10d6d, 0x10eab, 0x10eac, 0x10efc, 0x10eff, 0x10f46, 0x10f50, 0x10f82, 0x10f85,
  0x11000, 0x11002, 0x11038, 0x11046, 0x11070, 0x11070, 0x11073, 0x11074, 0x1107f, 0x11082, 0x110b0, 0x110ba,
  0x110c2, 0x110c2, 0x11100, 0x11102, 0x11127, 0x11134, 0x11145, 0x11146, 0x11173, 0x11173, 0x11180, 0x11182,
  0x111b3, 0x111c0, 0x111c9, 0x111cc, 0x111ce, 0x111cf, 0x1122c, 0x11237, 0x1123e, 0x1123e, 0x11241, 0x11241,
  0x112df, 0x112ea, 0x11300, 0x11303, 0x1133b, 0x1133c, 0x1133e, 0x11344, 0x11347, 0x11348, 0x1134b, 0x1134d,
  0x11357, 0x11357, 0x11362, 0x11363, 0x11366, 0x1136c, 0x11370, 0x11374, 0x113b8, 0x113c0, 0x113c2, 0x113c2,
  0x113c5, 0x113c5, 0x113c7, 0x113ca, 0x113cc, 0x113d0, 0x113d2, 0x113d2, 0x113e1, 0x113e2, 0x11435, 0x11446,
  0x1145e, 0x1145e, 0x114b0, 0x114c3, 0x115af, 0x115b5, 0x115b8, 0x115c0, 0x115dc, 0x115dd, 0x11630, 0x11640,
  0x116ab, 0x116b7, 0x1171d, 0x1172b, 0x1182c, 0x1183a, 0x11930, 0x11935, 0x11937, 0x11938, 0x1193b, 0x1193e,
  0x11940, 0x11940, 0x11942, 0x11943, 0x119d1, 0x119d7, 0x119da, 0x119e0, 0x119e4, 0x119e4, 0x11a01, 0x11a0a,
  0x11a33, 0x11a39, 0x11a3b, 0x11a3e, 0x11a47, 0x11a47, 0x11a51, 0x11a5b, 0x11a8a, 0x11a99, 0x11c2f, 0x11c36,
  0x11c38, 0x11c3f, 0x11c92, 0x11ca7, 0x11ca9, 0x11cb6, 0x11d31, 0x11d36, 0x11d3a, 0x11d3a, 0x11d3c, 0x11d3d,
  0x11d3f, 0x11d45, 0x11d47, 0x11d47, 0x11d8a, 0x11d8e, 0x11d90, 0x11d91, 0x11d93, 0x11d97, 0x11ef3, 0x11ef6,
  0x11f00, 0x11f01, 0x11f03, 0x11f03, 0x11f34, 0x11f3a, 0x11f3e, 0x11f42, 0x11f5a, 0x11f5a, 0x13440, 0x13440,
  0x13447, 0x13455, 0x1611e, 0x1612f, 0x16af0, 0x16af4, 0x16b30, 0x16b36, 0x16f4f, 0x16f4f, 0x16f51, 0x16f87,
  0x16f8f, 0x16f92, 0x16fe4, 0x16fe4, 0x16ff0, 0x16ff1, 0x1bc9d, 0x1bc9e, 0x1cf00, 0x1cf2d, 0x1cf30, 0x1cf46,
  0x1d165, 0x1d169, 0x1d16d, 0x1d172, 0x1d17b, 0x1d182, 0x1d185, 0x1d18b, 0x1d1aa, 0x1d1ad, 0x1d242, 0x1d244,
  0x1da00, 0x1da36, 0x1da3b, 0x1da6c, 0x1da75, 0x1da75, 0x1da84, 0x1da84, 0x1da9b, 0x1da9f, 0x1daa1, 0x1daaf,
  0x1e000, 0x1e006, 0x1e008, 0x1e018, 0x1e01b, 0x1e021, 0x1e023, 0x1e024, 0x1e026, 0x1e02a, 0x1e08f, 0x1e08f,
  0x1e130, 0x1e136, 0x1e2ae, 0x1e2ae, 0x1e2ec, 0x1e2ef, 0x1e4ec, 0x1e4ef, 0x1e5ee, 0x1e5ef, 0x1e8d0, 0x1e8d6,
  0x1e944, 0x1e94a
]

function isScriptMark(code) {
  if (code < scriptMarks[0] || code > scriptMarks[scriptMarks.length - 1]) return false
  for (var i = 0; i < scriptMarks.length; i += 2) {
    if (code <= scriptMarks[i + 1]) return code >= scriptMarks[i]
  }
  return false
}

// Characters that continue the one before them: combining marks (the table
// above and the blocks below), the vowel and final jamo of a Hangul syllable
// written in jamo, the Thai and Lao vowel sign AM and the halfwidth kana
// voiced sound marks (letters by category, but part of the syllable before
// them), joiners, variation selectors, emoji skin tones and tag sequences. A
// cut never lands in front of one, so a letter keeps its marks and an emoji
// its modifier. Unicode's other grapheme cluster rules (a conjunct across a
// virama, a prepended sign) are not followed here.
function continuesCluster(code) {
  return isScriptMark(code)
    || (code >= 0x0300 && code <= 0x036f) || (code >= 0x1ab0 && code <= 0x1aff)
    || (code >= 0x1dc0 && code <= 0x1dff) || (code >= 0x20d0 && code <= 0x20ff)
    || (code >= 0xfe00 && code <= 0xfe0f) || (code >= 0xfe20 && code <= 0xfe2f)
    || (code >= 0x1160 && code <= 0x11ff) || (code >= 0xd7b0 && code <= 0xd7ff)
    || code === 0x0e33 || code === 0x0eb3 || code === 0xff9e || code === 0xff9f
    || code === 0x200c || code === 0x200d
    || (code >= 0x1f3fb && code <= 0x1f3ff) || (code >= 0xe0020 && code <= 0xe007f)
    || (code >= 0xe0100 && code <= 0xe01ef)
}

// A flag is two regional indicators, paired from the start of a run, so a
// cut in front of `points[cut]` splits one when an odd number of them comes
// right before it.
function splitsFlag(points, cut) {
  var isIndicator = function (code) { return code >= 0x1f1e6 && code <= 0x1f1ff }
  if (!isIndicator(points[cut])) return false
  var run = 0
  while (cut - run > 0 && isIndicator(points[cut - run - 1])) run++
  return run % 2 === 1
}

// One untrusted metadata field for the tooltip: line breaks and other control
// characters become a space (a title cannot grow the tooltip into a column),
// and anything longer than `limit` code points ends in an ellipsis within it.
function tooltipField(value, limit) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ")
  var max = limit > 1 ? Math.floor(limit) : tooltipTitleLimit
  var points = []
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      var low = text.charCodeAt(i + 1)
      if (low >= 0xdc00 && low <= 0xdfff) {
        points.push((code - 0xd800) * 0x400 + (low - 0xdc00) + 0x10000)
        i++
        continue
      }
    }
    points.push(code)
  }
  if (points.length <= max) return text

  var cut = max - 1
  while (cut > 0 && (continuesCluster(points[cut]) || points[cut - 1] === 0x200d || splitsFlag(points, cut))) cut--
  var kept = ""
  for (var j = 0; j < cut; j++) kept += String.fromCodePoint(points[j])
  return kept + "\u2026"
}

// Qt's AutoText test (Qt::mightBeRichText) looks only at the first `<` (and an
// earlier `&lt;`). A WORD JOINER after every `<` and `&` fails that test, so
// AutoText falls back to plain text, while a PlainText sink (4.5) draws the
// joiner as nothing: the string reads the same either way. Escaping would not:
// plain text would show `&amp;` and AutoText would still guess per string.
function literalTooltip(text) {
  return String(text === undefined || text === null ? "" : text).replace(/[<&]/g, "$&\u2060")
}

// The hover text for a live player: `prefix` (the translated "Paused — ")
// then title and artist, each bounded, the whole line bounded to
// `tooltipLineLimit`, made literal as a whole. `bound` (Panel passes the
// kit's FoamyText.tooltip, the cap every plugin applies to app text it hands
// the host tooltip) caps the line again before the guard is added, so the
// word joiners never count against it or get cut off.
function tooltipLabel(player, prefix, bound) {
  if (!player) return ""

  var title = tooltipField(player.trackTitle, tooltipTitleLimit)
  var artist = tooltipField(player.trackArtist, tooltipArtistLimit)
  var label = tooltipField(String(prefix || "") + (!title ? artist : !artist ? title : title + "  ·  " + artist), tooltipLineLimit)
  return literalTooltip(typeof bound === "function" ? bound(label) : label)
}

// An open web-app window is not itself a track. YouTube clears these fields
// after playback ends, which lets the panel keep its tab without leaving an
// empty source in charge of the bar.
function hasTrackInformation(player) {
  return barLabel(player, true) !== ""
}

function hasDisplayableTrack(player, stoppedState) {
  if (!hasTrackInformation(player)) return false
  return stoppedState === undefined || player.playbackState !== stoppedState
}

// Paused tracks still belong in the bar. A player is empty once it has no
// track metadata or explicitly reports that playback is stopped.
function shouldShowWidget(spotifyPlayer, youtubePlayer, hideWhenStopped, stoppedState) {
  return !hideWhenStopped
    || hasDisplayableTrack(spotifyPlayer, stoppedState)
    || hasDisplayableTrack(youtubePlayer, stoppedState)
}

function formatTime(seconds) {
  var total = Math.floor(Number(seconds) || 0)
  if (total < 0) total = 0

  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var secs = total % 60

  if (hours > 0) return hours + ":" + pad(minutes) + ":" + pad(secs)
  return minutes + ":" + pad(secs)
}

function pad(value) {
  return value < 10 ? "0" + value : String(value)
}

// ---------------------------------------------------------------- album art
//
// The panel wears the current cover as its background. Two numbers drive
// that: the cover's mean luminance, which sets how heavily the scrim has to
// cover it for text to stay readable, and its dominant colour, which tints
// the scrim so the panel reads as part of the artwork rather than a window
// sitting on top of it. Both come from one probe — the native helper, which
// runs ImageMagick (see `artProbeArgs`) — and everything below is the parsing
// and the maths.

// Album art is metadata published by another process, so the whole of the
// probe treats it as hostile input: this decides what may be fetched at all,
// and the helper bounds what happens to the bytes that come back.

// The only hosts whose images are fetched. Matched on a label boundary, so a
// registered lookalike like "evilscdn.co" is not taken for a subdomain. The
// helper checks the same list again (native/src/main.rs `HOSTS`).
var artHosts = ["scdn.co", "ytimg.com"]

function artHostAllowed(host) {
  for (var i = 0; i < artHosts.length; i++) {
    var allowed = artHosts[i]
    if (host === allowed) return true
    var suffix = "." + allowed
    if (host.length > suffix.length && host.slice(-suffix.length) === suffix) return true
  }
  return false
}

// A raw space or control character in a URL has no legitimate meaning and
// serves only to make one thing parse as another.
function artUnprintable(value) {
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code <= 0x20 || code === 0x7f) return true
  }
  return false
}

// A decoded path is held to the same rule minus the space, because a file on
// disk is perfectly entitled to one.
function artControlChars(value) {
  for (var i = 0; i < value.length; i++) {
    var code = value.charCodeAt(i)
    if (code < 0x20 || code === 0x7f) return true
  }
  return false
}

// What to hand the probe, or null when there is nothing worth probing.
function artProbeTarget(artUrl) {
  var url = String(artUrl || "")
  if (!url || artUnprintable(url)) return null

  if (url.indexOf("file://") === 0) {
    var path
    try {
      path = decodeURIComponent(url.substring(7))
    } catch (e) {
      return null
    }
    // A local absolute path only. file://host/path names another machine.
    if (path.indexOf("/") !== 0) return null
    if (artControlChars(path)) return null
    return path
  }

  if (url.indexOf("https://") !== 0) return null

  // The authority is everything before the first path, query or fragment.
  var authority = url.substring(8).split(/[/?#]/)[0]
  // A cover host is a plain ASCII name. Anything else (userinfo, a port, a
  // `\` or an encoded or fullwidth slash) can make another URL parser read
  // the URL as a host other than the one checked here.
  if (!/^[a-z0-9.-]+$/i.test(authority)) return null
  if (!artHostAllowed(authority.toLowerCase())) return null

  return url
}

// The probe itself is the plugin's native helper, `foamy-media-helper
// art-probe <target>` (native/src/main.rs has its contract), run with the
// target as an argument so no metadata ever reaches a command line as code.
//
// Clearing the host check is the start of the argument and not the end of it,
// because everything after it is still attacker-shaped: the response body, its
// size, and whatever ImageMagick decides the bytes are. So the helper checks
// the target again, does not follow redirects away from the host that was
// checked, bounds the download by the declared size and again by the bytes
// received, names the format from the magic bytes rather than letting the
// decoder guess, takes a PNG's text chunks out before the decoder sees them,
// and decodes under explicit resource limits with a deadline.
function artProbeArgs(target) {
  return ["art-probe", String(target)]
}

// The helper's one JSON line: { ok: true, mean, file, swatches } or
// { ok: false, code, error }. Null when it is neither.
function artProbeReply(text) {
  var reply
  try {
    reply = JSON.parse(String(text || "").trim())
  } catch (e) {
    return null
  }
  return reply !== null && typeof reply === "object" && !Array.isArray(reply) ? reply : null
}

// The failure code of a reply ("TLS_UNSUPPORTED", "TOO_LARGE", …), "" for a
// success or for output that is no reply at all.
function artProbeFailure(text) {
  var reply = artProbeReply(text)
  return reply && reply.ok === false && typeof reply.code === "string" ? reply.code : ""
}

// Turns the helper's reply into { mean, dominant, luma, file } or null.
function parseArtProbe(text) {
  var reply = artProbeReply(text)
  if (!reply || reply.ok !== true) return null

  var hex = /^#[0-9a-f]{6}$/
  var mean = typeof reply.mean === "string" && hex.test(reply.mean) ? reply.mean : null
  // The normalised copy the panel is allowed to display. Only ever a path
  // the helper just wrote, under the cache directory it just made.
  var file = typeof reply.file === "string" && reply.file.charAt(0) === "/"
    && !artControlChars(reply.file) ? reply.file : ""

  var swatches = []
  var list = Array.isArray(reply.swatches) ? reply.swatches : []
  for (var i = 0; i < list.length; i++) {
    var swatch = list[i]
    if (!swatch || typeof swatch.hex !== "string" || !hex.test(swatch.hex)) continue
    var count = Number(swatch.count)
    if (!isFinite(count) || count < 0) continue
    swatches.push({ count: count, hex: swatch.hex })
  }

  var dominant = pickDominant(swatches)
  if (!mean && !dominant) return null
  if (!mean) mean = dominant
  if (!dominant) dominant = mean

  return { mean: mean, dominant: dominant, luma: luminance(mean), file: file }
}

// A path turned into a URL a QML Image will accept, with every segment encoded
// so a space or a "#" in it cannot end the path early.
function fileUrl(path) {
  var value = String(path || "")
  if (!value) return ""
  return "file://" + value.split("/").map(encodeURIComponent).join("/")
}

// The colour a person would name if asked what colour the cover is: usually
// not the most common one, because backgrounds are grey and skies are large.
// Weight area sub-linearly, reward saturation hard, and prefer mid tones —
// then fall back to sheer area when the cover really is monochrome.
function pickDominant(swatches) {
  if (!swatches || !swatches.length) return null

  var best = null
  var bestScore = 0
  var biggest = null

  for (var i = 0; i < swatches.length; i++) {
    var swatch = swatches[i]
    if (!biggest || swatch.count > biggest.count) biggest = swatch

    var hsl = toHsl(swatch.hex)
    if (hsl.l < 0.10 || hsl.l > 0.94) continue

    // Peaks at l = 0.5 and falls off towards either end.
    var midness = 1 - Math.abs(hsl.l - 0.5) * 1.6
    if (midness < 0.1) midness = 0.1

    var score = Math.sqrt(swatch.count) * Math.pow(hsl.s, 1.4) * midness
    if (score > bestScore) {
      bestScore = score
      best = swatch
    }
  }

  // A washed-out cover scores near zero everywhere; area is the better answer.
  if (!best || bestScore < 0.35) return biggest ? biggest.hex : null
  return best.hex
}

// How opaque the scrim over the cover has to be. `intensity` is the user's
// 0-100 "how much cover shows through"; the luminance term is the adaptive
// half — a bright cover needs more covering than a dark one to hold the same
// contrast under light theme text.
function scrimAlpha(luma, intensity) {
  var showing = clamp(Number(intensity), 0, 100) / 100
  var base = 1 - 0.72 * showing
  var lift = Math.max(0, clamp(Number(luma), 0, 1) - 0.30) * 0.45
  return clamp(base + lift, 0.18, 0.97)
}

// Bright covers also get pulled down at the source, so the blur underneath
// the scrim is not a wall of white.
function artBrightness(luma) {
  return -clamp(Math.max(0, clamp(Number(luma), 0, 1) - 0.25) * 0.55, 0, 0.42)
}

// Nudge a colour's lightness until it clears `target` against the panel, so
// an accent taken from a near-black cover is still visible as an accent.
function ensureContrast(hex, target) {
  var hsl = toHsl(hex)
  var want = clamp(Number(target), 0, 1)
  if (hsl.l >= want) return normalizeHex(hex)

  // Saturated colours can afford to stay a little darker than grey ones.
  var lifted = want + hsl.s * 0.05
  return fromHsl(hsl.h, Math.max(hsl.s, 0.25), clamp(lifted, 0, 0.92))
}

// Rec. 709 luminance on gamma-encoded values. Close enough for deciding how
// dark to make a scrim, and far cheaper than linearising first.
function luminance(hex) {
  var rgb = toRgb(hex)
  if (!rgb) return 0
  return (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) / 255
}

function toRgb(hex) {
  var match = /^#?([0-9A-Fa-f]{6})$/.exec(String(hex || "").trim())
  if (!match) return null

  var value = parseInt(match[1], 16)
  return { r: (value >> 16) & 255, g: (value >> 8) & 255, b: value & 255 }
}

function normalizeHex(hex) {
  var rgb = toRgb(hex)
  if (!rgb) return "#000000" // foamy-lint: allow hex-colour — parse fallback for an invalid input, never drawn as a theme colour
  return "#" + hexPair(rgb.r) + hexPair(rgb.g) + hexPair(rgb.b)
}

function hexPair(value) {
  var out = Math.round(clamp(value, 0, 255)).toString(16)
  return out.length < 2 ? "0" + out : out
}

function toHsl(hex) {
  var rgb = toRgb(hex)
  if (!rgb) return { h: 0, s: 0, l: 0 }

  var r = rgb.r / 255
  var g = rgb.g / 255
  var b = rgb.b / 255
  var max = Math.max(r, g, b)
  var min = Math.min(r, g, b)
  var l = (max + min) / 2

  if (max === min) return { h: 0, s: 0, l: l }

  var d = max - min
  var s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  var h = 0

  if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6
  else if (max === g) h = ((b - r) / d + 2) / 6
  else h = ((r - g) / d + 4) / 6

  return { h: h, s: s, l: l }
}

function fromHsl(h, s, l) {
  if (s <= 0) {
    var grey = Math.round(clamp(l, 0, 1) * 255)
    return "#" + hexPair(grey) + hexPair(grey) + hexPair(grey)
  }

  var q = l < 0.5 ? l * (1 + s) : l + s - l * s
  var p = 2 * l - q

  return "#" + hexPair(hueToByte(p, q, h + 1 / 3))
    + hexPair(hueToByte(p, q, h))
    + hexPair(hueToByte(p, q, h - 1 / 3))
}

function hueToByte(p, q, t) {
  if (t < 0) t += 1
  if (t > 1) t -= 1

  var value = p
  if (t < 1 / 6) value = p + (q - p) * 6 * t
  else if (t < 1 / 2) value = q
  else if (t < 2 / 3) value = p + (q - p) * (2 / 3 - t) * 6

  return value * 255
}

function clamp(value, low, high) {
  var number = Number(value)
  if (!isFinite(number)) return low
  return number < low ? low : number > high ? high : number
}

// The source to show when the widget starts: a playing source first (the
// focused YouTube window wins a tie), then one holding a track, then an open
// one. "" keeps the current choice.
function initialSource(bothPlaying, youtubeActivated, youtubePlaying, spotifyHasTrack, youtubeHasTrack, spotifyOpen, youtubeOpen) {
  if (bothPlaying) return youtubeActivated ? "youtube" : "spotify"
  if (youtubePlaying) return "youtube"
  if (spotifyHasTrack) return "spotify"
  if (youtubeHasTrack) return "youtube"
  if (spotifyOpen) return "spotify"
  if (youtubeOpen) return "youtube"
  return ""
}

// The source to keep after a player appears, disappears or changes state.
// A single playing source wins; otherwise a paused track stays selected over
// an open-but-empty app, so the bar never falls back to a lonely launcher icon.
function reconcileSource(current, state) {
  if (state.youtubePlaying && !state.spotifyPlaying) return "youtube"
  if (state.spotifyPlaying && !state.youtubePlaying) return "spotify"
  var currentHasTrack = current === "youtube" ? state.youtubeHasTrack : state.spotifyHasTrack
  if (!currentHasTrack && state.spotifyHasTrack) return "spotify"
  if (!currentHasTrack && state.youtubeHasTrack) return "youtube"
  var currentOpen = current === "youtube" ? state.youtubeOpen : state.spotifyOpen
  if (currentOpen) return current
  return state.spotifyOpen ? "spotify" : state.youtubeOpen ? "youtube" : "spotify"
}

// How often (ms) the bar re-reads the playback position: about once per
// pixel the progress underline gains, at most once a second and at least
// every five seconds.
function progressTickInterval(lengthSeconds, widthPixels) {
  var length = Number(lengthSeconds), width = Number(widthPixels)
  if (!isFinite(length) || length <= 0 || !isFinite(width) || width <= 0) return 5000
  return Math.round(clamp(length * 1000 / width, 1000, 5000))
}

// Nothing here touches Qt, so the whole file also loads under node and the
// tests in tests/model-test.js exercise it directly. QML's .js import ignores
// this block.
if (typeof module !== "undefined") {
  module.exports = {
    isSpotify: isSpotify,
    metadataString: metadataString,
    urlHost: urlHost,
    isYoutubePageUrl: isYoutubePageUrl,
    youtubeWindowTitleMatches: youtubeWindowTitleMatches,
    isYoutube: isYoutube,
    sourceKind: sourceKind,
    findSource: findSource,
    findSpotify: findSpotify,
    findYoutube: findYoutube,
    barLabel: barLabel,
    tooltipTitleLimit: tooltipTitleLimit,
    tooltipArtistLimit: tooltipArtistLimit,
    tooltipLineLimit: tooltipLineLimit,
    tooltipField: tooltipField,
    literalTooltip: literalTooltip,
    tooltipLabel: tooltipLabel,
    hasTrackInformation: hasTrackInformation,
    hasDisplayableTrack: hasDisplayableTrack,
    shouldShowWidget: shouldShowWidget,
    formatTime: formatTime,
    artHostAllowed: artHostAllowed,
    artProbeTarget: artProbeTarget,
    artProbeArgs: artProbeArgs,
    artProbeFailure: artProbeFailure,
    parseArtProbe: parseArtProbe,
    fileUrl: fileUrl,
    pickDominant: pickDominant,
    scrimAlpha: scrimAlpha,
    artBrightness: artBrightness,
    ensureContrast: ensureContrast,
    luminance: luminance,
    toHsl: toHsl,
    fromHsl: fromHsl,
    normalizeHex: normalizeHex,
    initialSource: initialSource,
    reconcileSource: reconcileSource,
    progressTickInterval: progressTickInterval
  }
}
