#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plist="$project_root/Resources/Info.plist"

if [[ -x /usr/libexec/PlistBuddy ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist"
    exit 0
fi

command -v python3 >/dev/null 2>&1 || {
    printf '%s\n' 'Cannot read the release version: PlistBuddy or python3 is required.' >&2
    exit 1
}

python3 - "$plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    value = plistlib.load(stream)["CFBundleShortVersionString"]
print(value)
PY
