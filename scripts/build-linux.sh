#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="$project_root/dist/sharex-linux"
release=false
check_dependencies=false
skip_tests=false

usage() {
    cat <<'EOF'
Usage: scripts/build-linux.sh [--check-dependencies] [--release] [--output DIR] [--skip-tests]

  --check-dependencies  Check build and runtime packages, then exit.
  --release              Build ShareXLinux and stage an installable bundle.
  --output DIR           Write the staged bundle below DIR.
  --skip-tests           Skip Swift and Python tests during --release.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-dependencies) check_dependencies=true; shift ;;
        --release) release=true; shift ;;
        --output) output_dir="${2:?Missing output directory}"; shift 2 ;;
        --skip-tests) skip_tests=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if ! $check_dependencies && ! $release; then
    usage >&2
    exit 2
fi

missing=()
for command in swift python3 pkg-config; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done
command -v dpkg-deb >/dev/null 2>&1 || missing+=("dpkg-deb")

if command -v python3 >/dev/null 2>&1; then
    if ! python3 - <<'PY' >/dev/null 2>&1
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk
PY
    then
        missing+=("python3-gi/gir1.2-gtk-3.0")
    fi
fi

if command -v pkg-config >/dev/null 2>&1 && ! pkg-config --exists sqlite3; then
    missing+=("libsqlite3-dev")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing required Linux build/runtime dependencies: %s\n' "${missing[*]}" >&2
    printf '%s\n' 'Ubuntu: sudo apt install swift pkg-config dpkg-dev libsqlite3-dev python3-gi gir1.2-gtk-3.0' >&2
    printf '%s\n' 'Fedora: sudo dnf install swift pkgconf-pkg-config sqlite-devel python3-gobject gtk3' >&2
    exit 1
fi

if $check_dependencies; then
    optional=()
    for command in tesseract wl-copy xclip grim slurp maim gnome-screenshot import xdotool; do
        command -v "$command" >/dev/null 2>&1 || optional+=("$command")
    done
    if ! python3 - <<'PY' >/dev/null 2>&1
import gi
gi.require_version("Keybinder", "3.0")
from gi.repository import Keybinder
PY
    then
        optional+=("gir1.2-keybinder-3.0")
    fi
    if [[ ${#optional[@]} -gt 0 ]]; then
        printf 'Optional desktop helpers not found: %s\n' "${optional[*]}"
        printf '%s\n' 'Install the helpers for the desktop sessions and features you use.'
    else
        printf '%s\n' 'All recommended desktop helpers are installed.'
    fi
    exit 0
fi

cd "$project_root"
if ! $skip_tests; then
    swift test --disable-sandbox
    python3 -m unittest discover -s Tests/ShareXLinuxDesktopTests -p 'test_*.py'
fi

swift build -c release --static-swift-stdlib --product ShareXLinux
bin_dir="$(swift build -c release --static-swift-stdlib --product ShareXLinux --show-bin-path)"
binary="$bin_dir/ShareXLinux"
resource_bundle="$bin_dir/ShareXLinux_ShareXLinux.resources"
[[ -x "$binary" ]] || { printf 'Release binary was not produced: %s\n' "$binary" >&2; exit 1; }
[[ -d "$resource_bundle/Desktop" ]] || { printf 'Desktop resources were not produced: %s\n' "$resource_bundle/Desktop" >&2; exit 1; }

rm -rf "$output_dir"
mkdir -p "$output_dir/ShareXLinux_ShareXLinux.resources" "$output_dir/packaging"
cp "$binary" "$output_dir/ShareXLinux"
cp -R "$resource_bundle/Desktop" "$output_dir/ShareXLinux_ShareXLinux.resources/"
cp packaging/linux/sharex.desktop packaging/linux/sharex-autostart.desktop packaging/linux/install.sh "$output_dir/packaging/"
chmod 0755 "$output_dir/ShareXLinux" "$output_dir/packaging/install.sh"
tar -C "$(dirname "$output_dir")" -czf "$(dirname "$output_dir")/sharex-linux.tar.gz" "$(basename "$output_dir")"
deb="$output_dir/ShareXLinux.deb"
"$project_root/scripts/package-linux-deb.sh" --source "$output_dir" --output "$deb"
printf 'Linux bundle: %s\nDEB: %s\nArchive: %s\n' "$output_dir" "$deb" "$(dirname "$output_dir")/sharex-linux.tar.gz"
