#!/bin/sh
# Runs the real probe, the built helper (bin/<arch>/foamy-media-helper
# art-probe), against real fixtures, because asserting that the code contains
# a check is not the same as showing what it does. Everything here is local:
# no network, and nothing that needs a Spotify. The fetch's bounds (no
# redirects, the size cap on received bytes, the deadline) and the refusal of
# special files are cargo tests in native/src/, against a loopback server.
#
#   sh tests/probe-test.sh
#
# A missing helper binary is a failure: bin/<arch>/ is committed. Without
# ImageMagick only the cases that end before a decode run (the decode cases
# are skipped and say so), which is what CI runs.

set -eu

cd "$(dirname "$0")/.."

if ! command -v node >/dev/null 2>&1; then
  echo "skip — node not installed"
  exit 0
fi

# FOAMY_MEDIA_ARCH=aarch64 runs the other build (through binfmt and qemu).
arch=${FOAMY_MEDIA_ARCH:-$(uname -m)}
helper="$PWD/bin/$arch/foamy-media-helper"
if [ ! -x "$helper" ]; then
  echo "FAIL     no helper for $arch at $helper (build it with kit/native/build-native.sh .)"
  exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export XDG_CACHE_HOME="$work/cache"

failures=0
status=0

fail() {
  echo "FAIL     $1"
  failures=$((failures + 1))
}

# One field of the helper's JSON reply ("mean", "file").
field() {
  sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"
}

# Runs a command with a deadline, so a helper that blocks fails instead of
# hanging the suite. The exit status is left in $status, stdout in
# $work/out and stderr in $work/err. Returns 1 (after counting a failure)
# when the deadline ended it.
run_helper() {
  status=0
  timeout 30 "$@" >"$work/out" 2>"$work/err" || status=$?
  if [ "$status" -eq 124 ]; then
    fail "$label — the helper hung past 30 s"
    return 1
  fi
}

# The reply of `art-probe <target>`, within the same deadline.
reply_of() {
  timeout 30 "$helper" art-probe "$1" || :
}

# expect_ok <target> <label>: exit 0, nothing on stderr, and a reply that
# names a cover file that exists.
expect_ok() {
  label=$2
  run_helper "$helper" art-probe "$1" || return 0
  reply=$(cat "$work/out")
  file=$(field file <"$work/out")
  if [ "$status" -ne 0 ]; then
    fail "$label — exit $status, expected the probe to read this ($reply)"
  elif [ -s "$work/err" ]; then
    fail "$label — the helper wrote to stderr: $(head -c 200 "$work/err")"
  elif [ "${reply#*\"ok\":true}" = "$reply" ]; then
    fail "$label — replied $reply"
  elif [ -z "$file" ] || [ ! -f "$file" ]; then
    fail "$label — the reply names no written cover ($reply)"
  else
    echo "ok       $label"
  fi
}

# expect_code <CODE> <label> <command…>: the refusal the helper documents
# (native/src/main.rs): exit 2 for INVALID_ARGUMENT, 1 for every other code,
# nothing on stderr, and exactly one JSON line with that code.
expect_code() {
  code=$1 label=$2
  shift 2
  want=1
  if [ "$code" = INVALID_ARGUMENT ]; then
    want=2
  fi
  run_helper "$@" || return 0
  reply=$(cat "$work/out")
  if [ "$status" -ne "$want" ]; then
    fail "$label — exit $status, expected $want with $code ($reply)"
  elif [ -s "$work/err" ]; then
    fail "$label — the helper wrote to stderr: $(head -c 200 "$work/err")"
  elif [ "$(wc -l <"$work/out")" -ne 1 ]; then
    fail "$label — the reply is not one line: $reply"
  else
    case "$reply" in
      "{\"code\":\"$code\","*'"ok":false}') echo "ok       $label ($code)" ;;
      *) fail "$label — replied $reply, expected $code" ;;
    esac
  fi
}

# ---------------------------------------- cases that end before a decode

expect_code INVALID_ARGUMENT "a relative path" "$helper" art-probe relative.png
# A WHATWG URL parser reads this host as evil.test; the helper refuses it
# before any URL parser sees it.
expect_code INVALID_ARGUMENT "a backslash in the URL's host" "$helper" art-probe 'https://evil.test\.scdn.co/x'

# Formats that reach an ImageMagick delegate or coder rather than a raster
# decoder. The magic-byte check is what keeps these out, and every outcome
# is one JSON line, a refusal included.
printf 'not an image at all\n' >"$work/text.txt"
expect_code UNSUPPORTED_FORMAT "a plain text file" "$helper" art-probe "$work/text.txt"

printf '%s' '<svg xmlns="http://www.w3.org/2000/svg"><image href="/etc/passwd"/></svg>' >"$work/evil.svg"
expect_code UNSUPPORTED_FORMAT "an SVG referencing a local file" "$helper" art-probe "$work/evil.svg"

# Past the byte bound, with a JPEG signature so only the size can catch it.
printf '\377\330\377' >"$work/big.jpg"
head -c 9000000 /dev/zero >>"$work/big.jpg"
expect_code TOO_LARGE "a 9MB file past the size bound" "$helper" art-probe "$work/big.jpg"

expect_code UNREADABLE "a path that is not there" "$helper" art-probe "$work/does-not-exist.png"

# A valid cover with no ImageMagick on PATH: the plugin does without a
# backdrop, and says why.
node tests/make-text-bomb.js "$work/tiny.png" 0 1
expect_code MAGICK_MISSING "a cover without ImageMagick installed" \
  env PATH=/var/empty "$helper" art-probe "$work/tiny.png"

# ---------------------------------------------- cases that need a decode

decode_cases() {
  # A cover, and a cover whose name has a space in it.
  magick -size 200x200 xc:'#1db954' "$work/cover.png"
  expect_ok "$work/cover.png" "a PNG cover"
  cp "$work/cover.png" "$work/My Cover.png"
  expect_ok "$work/My Cover.png" "a cover with a space in its name"

  magick -size 200x200 xc:'#b2313a' "$work/cover.jpg"
  expect_ok "$work/cover.jpg" "a JPEG cover"

  # 410KB on disk, 144 megapixels decoded — roughly 430MB of pixels if nothing
  # stops it. This is the case the byte bounds cannot catch, so it is the one
  # that shows the area limit doing the work.
  node tests/make-bomb.js "$work/bomb.png" 12000
  expect_code DECODE_FAILED "a 12000x12000 decompression bomb" "$helper" art-probe "$work/bomb.png"

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
subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
print(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024)
' "$helper" art-probe "$work/text-bomb.png")
    if [ "$peak" -lt 64 ]; then
      echo "ok       the zTXt bomb peaked at ${peak}MiB"
    else
      fail "the zTXt bomb peaked at ${peak}MiB: its text reached the decoder"
    fi
  else
    echo "skip     the zTXt bomb's peak memory — python3 not installed"
  fi

  # Ordinary text (ImageMagick itself writes tEXt dates) is dropped without
  # changing the cover: the same pixels give the same colour.
  magick -size 64x64 gradient:'#1db954-#b2313a' -set comment 'a cover' "$work/texted.png"
  magick "$work/texted.png" -strip "$work/plain.png"
  with=$(reply_of "$work/texted.png" | field mean)
  without=$(reply_of "$work/plain.png" | field mean)
  if [ -n "$with" ] && [ "$with" = "$without" ]; then
    echo "ok       a PNG with text chunks reads as the same cover ($with)"
  else
    fail "a PNG with text chunks read as '$with', the same cover without them as '$without'"
  fi

  # The cover the panel is allowed to display: written here, not fetched by Qt,
  # and capped so that decoding it is bounded too.
  oversized="$work/oversized.png"
  magick -size 3000x2000 gradient:'#204080-#c0f0ff' "$oversized"
  art=$(reply_of "$oversized" | field file)
  if [ -z "$art" ] || [ ! -f "$art" ]; then
    fail "the probe did not write a cover for the panel to show"
  else
    kind=$(od -An -v -tx1 -N8 "$art" | tr -d " \n")
    case "$kind" in
      89504e470d0a1a0a*) echo "ok       the written cover is a PNG" ;;
      *) fail "the written cover is not a PNG" ;;
    esac

    width=$(magick identify -format '%w' "$art")
    height=$(magick identify -format '%h' "$art")
    if [ "$width" -le 640 ] && [ "$height" -le 640 ]; then
      echo "ok       3000x2000 was capped to ${width}x${height}"
    else
      fail "the written cover is ${width}x${height}, past the 640 cap"
    fi
  fi

  # The cache is keyed by the cover's bytes, not its URL: a player that writes
  # every track's cover to one file:// path still gets the new cover.
  same="$work/same-path.png"
  magick -size 64x64 xc:'#1db954' "$same"
  first=$(reply_of "$same" | field file)
  magick -size 64x64 xc:'#b2313a' "$same"
  second=$(reply_of "$same" | field file)
  again=$(reply_of "$same" | field file)
  if [ -n "$first" ] && [ -n "$second" ] && [ "$first" != "$second" ] && [ "$second" = "$again" ]; then
    echo "ok       a rewritten cover at the same path is a new cached cover"
  else
    fail "the cover cache reused a stale cover for a rewritten path ($first, $second, $again)"
  fi
}

if command -v magick >/dev/null 2>&1; then
  decode_cases
else
  echo "SKIP decode cases: ImageMagick not installed"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures probe test(s) failed"
  exit 1
fi

echo "ok — probe tests passed"
