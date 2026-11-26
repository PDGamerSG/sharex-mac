#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir=""
output=""
version="$("$project_root/scripts/release-version.sh")"

usage() {
    cat <<'EOF'
Usage: scripts/package-linux-deb.sh --source DIR --output FILE [--version VERSION]

  --source DIR       Staged output from scripts/build-linux.sh.
  --output FILE      The single Debian package to write.
  --version VERSION  Debian package version. Defaults to the app bundle version.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) source_dir="${2:?Missing source directory}"; shift 2 ;;
        --output) output="${2:?Missing output file}"; shift 2 ;;
        --version) version="${2:?Missing version}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n "$source_dir" && -n "$output" ]] || { usage >&2; exit 2; }
command -v dpkg-deb >/dev/null 2>&1 || {
    printf '%s\n' 'dpkg-deb is required to build the Linux release package.' >&2
    exit 1
}

source_dir="$(cd "$source_dir" && pwd)"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
binary="$source_dir/ShareXLinux"
resources="$source_dir/ShareXLinux_ShareXLinux.resources"
desktop_template="$source_dir/packaging/sharex.desktop"

[[ -x "$binary" ]] || { printf 'Missing Linux binary in %s\n' "$source_dir" >&2; exit 1; }
[[ -d "$resources/Desktop" ]] || { printf 'Missing desktop resources in %s\n' "$source_dir" >&2; exit 1; }
[[ -f "$desktop_template" ]] || { printf 'Missing desktop entry in %s\n' "$source_dir" >&2; exit 1; }
[[ "$version" =~ ^[0-9]+([.][0-9]+)*([+~-][0-9A-Za-z.+~_-]+)?$ ]] || {
    printf 'Invalid Debian package version: %s\n' "$version" >&2
    exit 1
}

architecture="$(dpkg --print-architecture)"
package_root="$(mktemp -d "${TMPDIR:-/tmp}/sharex-linux-deb.XXXXXX")"
trap 'rm -rf "$package_root"' EXIT
chmod 0755 "$package_root"

install -d "$package_root/usr/lib/sharex-linux" "$package_root/usr/share/applications" "$package_root/DEBIAN"
install -m 0755 "$binary" "$package_root/usr/lib/sharex-linux/ShareXLinux"
cp -R "$resources" "$package_root/usr/lib/sharex-linux/"

cat > "$package_root/DEBIAN/control" <<EOF
Package: sharex-linux
Version: $version
Section: graphics
Priority: optional
Architecture: $architecture
Maintainer: ShareX contributors <sharex@pdgamersg.github.io>
Depends: python3, python3-gi, gir1.2-gtk-3.0, gir1.2-keybinder-3.0, libsqlite3-0, libstdc++6, tesseract-ocr
Description: ShareX Linux screenshot and OCR utility
 ShareX Linux captures screenshots, stores local history, and recognizes text offline.
EOF

sed 's|@EXEC@|/usr/lib/sharex-linux/ShareXLinux|g' "$desktop_template" \
    > "$package_root/usr/share/applications/io.github.PDGamerSG.ShareXLinux.desktop"

mkdir -p "$(dirname "$output")"
rm -f "$output"
dpkg-deb --build --root-owner-group "$package_root" "$output" >/dev/null
printf 'Debian package: %s\n' "$output"
