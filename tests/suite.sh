#!/bin/bash
# foamy-media's own tests; tests/validate.sh runs this after the linters.
#   --ci    no Quickshell, no Omarchy host: node, the helper on local
#           fixtures (probe-test.sh skips without ImageMagick) and the
#           clipboard producer tests
#   --fast  skip the offscreen runtime tests
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1
ci=0 fast=0
for arg in "$@"; do
  case $arg in
    --ci) ci=1 ;;
    --fast) fast=1 ;;
    *)
      echo "suite.sh: unknown argument $arg" >&2
      exit 2
      ;;
  esac
done
status=0
run() {
  echo "== $*"
  "$@" || status=1
}
skip() { echo "SKIP $*"; }
kit=${FOAMY_KIT:-$HOME/GitHub/Personal/foamy-kit}
for test in tests/*-test.js tests/i18n.test.cjs; do
  run node "$test"
done
run sh tests/probe-test.sh
# The aarch64 build runs through binfmt; a core dump under qemu is not wanted.
if [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
  (
    ulimit -c 0
    FOAMY_MEDIA_ARCH=aarch64 run sh tests/probe-test.sh
    exit $status
  ) || status=1
else
  skip "the aarch64 helper: no qemu-aarch64 binfmt"
fi
if ((ci)); then
  FOAMY_SUITE_CI=1 run python3 -I tests/test_clipboard.py
else
  run python3 -I tests/test_clipboard.py
fi
if ((ci || fast)); then
  skip "i18n_runtime.py, runtime.py, tooltip-runtime.py: offscreen Quickshell"
elif [ ! -f "$kit/preview/harness.py" ]; then
  echo "FAIL the runtime tests need foamy-kit (set FOAMY_KIT)"
  status=1
else
  run python3 "$kit/preview/i18n_runtime.py" .
  run python3 -I tests/runtime.py
  run python3 -I tests/tooltip-runtime.py
fi
exit $status
