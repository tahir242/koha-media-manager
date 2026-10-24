#!/bin/sh
# Build MediaManager.kpz in the repository root (Linux/macOS). Runs build_kpz.py,
# which needs Python 3.8+ and only its standard library.
# Usage: scripts/build_kpz.sh
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for python in python3 python; do
    if command -v "$python" >/dev/null 2>&1 \
        && "$python" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
        exec "$python" "$here/build_kpz.py" "$@"
    fi
done
echo "build_kpz.sh: Python 3.8+ is required (python3 not found)." >&2
exit 1
