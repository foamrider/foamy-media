#!/bin/sh
# Runs the real probe script against real fixtures, because asserting that the
# script contains a flag is not the same as showing what it does. Everything
# here is local: no network, and nothing that needs a Spotify.
#
#   sh tests/probe-test.sh
#
# Skips if ImageMagick is missing, which is also the case where the plugin
# quietly does without a cover backdrop.

set -eu

cd "$(dirname "$0")/.."

if ! command -v magick >/dev/null 2>&1; then
  echo "skip — ImageMagick not installed"
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then
  echo "skip — node not installed"
  exit 0
fi

script=$(node -e 'process.stdout.write(require("./Model.js").artProbeScript())')
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export XDG_CACHE_HOME="$work/cache"

failures=0

probe() {
  sh -c "$script" sh "$1" >/dev/null 2>&1
}

expect_ok() {
  if probe "$1"; then
    echo "ok       $2"
  else
    echo "FAIL     $2 — expected the probe to read this"
    failures=$((failures + 1))
  fi
}

expect_refused() {
  if probe "$1"; then
    echo "FAIL     $2 — expected the probe to refuse this"
    failures=$((failures + 1))
  else
    echo "refused  $2"
  fi
}

# A cover, and a cover whose name has a space in it.
magick -size 200x200 xc:'#1db954' "$work/cover.png"
expect_ok "$work/cover.png" "a PNG cover"
cp "$work/cover.png" "$work/My Cover.png"
expect_ok "$work/My Cover.png" "a cover with a space in its name"

magick -size 200x200 xc:'#b2313a' "$work/cover.jpg"
expect_ok "$work/cover.jpg" "a JPEG cover"

# Formats that reach an ImageMagick delegate or coder rather than a raster
# decoder. The magic-byte check is what keeps these out.
printf 'not an image at all\n' > "$work/text.txt"
expect_refused "$work/text.txt" "a plain text file"

printf '%s' '<svg xmlns="http://www.w3.org/2000/svg"><image href="/etc/passwd"/></svg>' > "$work/evil.svg"
expect_refused "$work/evil.svg" "an SVG referencing a local file"

printf '%s' 'push graphic-context image over 0,0 0,0 "msl:/etc/passwd" pop graphic-context' > "$work/evil.mvg"
expect_refused "$work/evil.mvg" "an MVG vector script"

# Past the byte bound, with a JPEG signature so only the size can catch it.
printf '\377\330\377' > "$work/big.jpg"
head -c 9000000 /dev/zero >> "$work/big.jpg"
expect_refused "$work/big.jpg" "a 9MB file past the size bound"

# 410KB on disk, 144 megapixels decoded — roughly 430MB of pixels if nothing
# stops it. This is the case the byte bounds cannot catch, so it is the one
# that shows the area limit doing the work.
node tests/make-bomb.js "$work/bomb.png" 12000
expect_refused "$work/bomb.png" "a 12000x12000 decompression bomb"

expect_refused "$work/does-not-exist.png" "a path that is not there"

# 100KB on disk, a valid 1x1 image, and 96MiB of zTXt text that libpng would
# inflate and keep outside every ImageMagick limit (half of it after the image
# data). Unstripped, the probe peaks near 300MB here; the real attack scales
# the same chunks to gigabytes. Stripped, it costs what a plain cover costs,
# and the cover still shows: the text never reaches the decoder.
node tests/make-text-bomb.js "$work/text-bomb.png" 96 1024
expect_ok "$work/text-bomb.png" "a 1x1 PNG carrying 96MiB of zTXt text"
if command -v python3 >/dev/null 2>&1; then
  peak=$(python3 -I -c '
import resource, subprocess, sys
subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024)
' sh -c "$script" sh "$work/text-bomb.png")
  if [ "$peak" -lt 64 ]; then
    echo "ok       the zTXt bomb peaked at ${peak}MiB"
  else
    echo "FAIL     the zTXt bomb peaked at ${peak}MiB: its text reached the decoder"
    failures=$((failures + 1))
  fi
else
  echo "skip     the zTXt bomb's peak memory — python3 not installed"
fi

# Ordinary text (ImageMagick itself writes tEXt dates) is dropped without
# changing the cover: the same pixels give the same colour.
magick -size 64x64 gradient:'#1db954-#b2313a' -set comment 'a cover' "$work/texted.png"
magick "$work/texted.png" -strip "$work/plain.png"
with=$(sh -c "$script" sh "$work/texted.png" | sed -n 's/^MEAN //p')
without=$(sh -c "$script" sh "$work/plain.png" | sed -n 's/^MEAN //p')
if [ -n "$with" ] && [ "$with" = "$without" ]; then
  echo "ok       a PNG with text chunks reads as the same cover ($with)"
else
  echo "FAIL     a PNG with text chunks read as '$with', the same cover without them as '$without'"
  failures=$((failures + 1))
fi

# A text chunk that claims to run past the end of the file, and text between
# more chunks than any cover has (every gap it leaves is a copy to make).
node -e '
const fs = require("fs")
const { crc32 } = require("zlib")
const chunk = (type, body) => {
  const head = Buffer.alloc(4)
  head.writeUInt32BE(body.length)
  const typed = Buffer.concat([Buffer.from(type, "latin1"), body])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(typed))
  return Buffer.concat([head, typed, crc])
}
const png = fs.readFileSync(process.argv[1])
const head = png.subarray(0, 33)    // signature and IHDR
const rest = png.subarray(33)
const overrun = chunk("zTXt", Buffer.from("k\0\0x", "latin1"))
overrun.writeUInt32BE(0x100000)
fs.writeFileSync(process.argv[2], Buffer.concat([head, overrun, rest]))
const parts = [head]
for (let i = 0; i < 80; i++) parts.push(chunk("tEXt", Buffer.from("k\0v", "latin1")), chunk("gAMA", Buffer.from([0, 0, 0xb1, 0x8f])))
parts.push(rest)
fs.writeFileSync(process.argv[3], Buffer.concat(parts))
' "$work/plain.png" "$work/overrun.png" "$work/interleaved.png"
expect_refused "$work/overrun.png" "a PNG chunk that runs past the end of the file"
expect_refused "$work/interleaved.png" "a PNG with text between 80 other chunks"

# The cover the panel is allowed to display: written here, not fetched by Qt,
# and capped so that decoding it is bounded too.
oversized="$work/oversized.png"
magick -size 3000x2000 gradient:'#204080-#c0f0ff' "$oversized"
art=$(sh -c "$script" sh "$oversized" | sed -n 's/^ART //p')
if [ -z "$art" ] || [ ! -f "$art" ]; then
  echo "FAIL     the probe did not write a cover for the panel to show"
  failures=$((failures + 1))
else
  kind=$(od -An -v -tx1 -N8 "$art" | tr -d " \n")
  case "$kind" in
    89504e470d0a1a0a*) echo "ok       the written cover is a PNG" ;;
    *) echo "FAIL     the written cover is not a PNG"; failures=$((failures + 1)) ;;
  esac

  edge=$(magick identify -format '%w %h' "$art")
  set -- $edge
  if [ "$1" -le 640 ] && [ "$2" -le 640 ]; then
    echo "ok       3000x2000 was capped to ${1}x${2}"
  else
    echo "FAIL     the written cover is ${1}x${2}, past the 640 cap"
    failures=$((failures + 1))
  fi
fi

# The cache is keyed by the cover's bytes, not its URL: a player that writes
# every track's cover to one file:// path still gets the new cover.
same="$work/same-path.png"
magick -size 64x64 xc:'#1db954' "$same"
first=$(sh -c "$script" sh "$same" | sed -n 's/^ART //p')
magick -size 64x64 xc:'#b2313a' "$same"
second=$(sh -c "$script" sh "$same" | sed -n 's/^ART //p')
again=$(sh -c "$script" sh "$same" | sed -n 's/^ART //p')
if [ -n "$first" ] && [ -n "$second" ] && [ "$first" != "$second" ] && [ "$second" = "$again" ]; then
  echo "ok       a rewritten cover at the same path is a new cached cover"
else
  echo "FAIL     the cover cache reused a stale cover for a rewritten path ($first, $second, $again)"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures probe test(s) failed"
  exit 1
fi

echo "ok — probe tests passed"
