#!/bin/bash
# Build and run SPEEDY, then snapshot the run directory as a golden reference.
#
# Usage: scripts/make_golden.sh [name]      (default name: reference)
#
# The snapshot goes to golden/<name>/ and contains every NetCDF output file,
# the stdout diagnostics (output.txt), a SHA-256 manifest of the outputs and
# a BUILD_INFO file recording how the binary was produced. Results under
# -Ofast depend on compiler version and flags, so compare like with like.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:-reference}
DEST=$ROOT/golden/$NAME

cd "$ROOT"
./build.sh
./run.sh > /dev/null

rm -rf "$DEST"
mkdir -p "$DEST"
cp rundir/[0-9]*.nc rundir/output.txt "$DEST"/
cp namelist.nml "$DEST"/

(cd "$DEST" && shasum -a 256 [0-9]*.nc > MANIFEST.sha256)

FC=${FC:-$(command -v brew >/dev/null && echo "$(brew --prefix)/bin/gfortran" || echo gfortran)}
{
    echo "date:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "git:       $(git rev-parse HEAD)$(git diff --quiet -- source || echo ' (source modified)')"
    echo "compiler:  $($FC --version | head -1)"
    echo "flags:     $(grep -E '^(BASE|OPT|STRICT)=' source/gfortran.makefile | tr '\n' ' ')"
    echo "host:      $(uname -sm)"
    echo "files:     $(ls "$DEST"/[0-9]*.nc | wc -l | tr -d ' ')"
} > "$DEST/BUILD_INFO"

cat "$DEST/BUILD_INFO"
echo "Golden outputs saved to $DEST"
