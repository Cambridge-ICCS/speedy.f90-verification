#!/bin/bash
# Build and run SPEEDY, then compare the outputs with a golden reference.
#
# Usage: scripts/check_golden.sh [--lean] [--golden name] [--no-build] [compare_golden.py options]
#
#   --lean      build with the Lean kernels and the shadow check (build.sh --lean --shadow):
#               each Lean kernel call is checked against the original Fortran, bitwise in
#               double precision, which catches differences too small to survive the float32
#               output.
#   --golden    name of the reference under golden/ (default: reference)
#   --no-build  use the existing bin/speedy
#
# Any remaining options (e.g. --rtol 1e-6, -v) are passed to compare_golden.py.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=reference
BUILD=1
BUILD_ARGS=()
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --golden)   NAME=$2; shift 2 ;;
        --no-build) BUILD=0; shift ;;
        --lean)     BUILD_ARGS+=(--lean --shadow); shift ;;
        *)          ARGS+=("$1"); shift ;;
    esac
done

GOLDEN=$ROOT/golden/$NAME
if [ ! -d "$GOLDEN" ]; then
    echo "No golden reference at $GOLDEN; run scripts/make_golden.sh first"
    exit 1
fi

PY=$ROOT/.venv/bin/python
[ -x "$PY" ] || PY=python3

cd "$ROOT"
[ $BUILD = 1 ] && ./build.sh ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
./run.sh > /dev/null

# Shadow check of Lean kernels against the Fortran (only active in --lean --shadow builds)
if grep -q "MISMATCH" rundir/output.txt; then
    echo "FAIL: Lean kernel differs from Fortran"
    grep -A2 "MISMATCH" rundir/output.txt
    exit 1
fi
if grep -q "shadow-checking" rundir/output.txt; then
    echo "Shadow check: every Lean kernel call bit-identical to Fortran"
fi

# Fast path: a byte-identical match against the manifest needs no NetCDF reading.
if (cd rundir && shasum -a 256 --status -c "$GOLDEN/MANIFEST.sha256" 2>/dev/null); then
    echo "PASS: all $(wc -l < "$GOLDEN/MANIFEST.sha256" | tr -d ' ') output files are byte-identical to golden/$NAME"
    exit 0
fi

"$PY" scripts/compare_golden.py "$GOLDEN" rundir ${ARGS[@]+"${ARGS[@]}"}
