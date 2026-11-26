#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prefix="${SHAREX_PREFIX:-$HOME/.local}"
app_dir="$prefix/lib/sharex-linux"
bin_dir="$prefix/bin"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
desktop_dir="$data_dir/applications"
autostart_dir="$config_dir/autostart"
enable_autostart=false

usage() {
    printf '%s\n' 'Usage: packaging/linux/install.sh [--enable-autostart]'
    printf '%s\n' 'Set SHAREX_PREFIX to choose a different user-local prefix.'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --enable-autostart) enable_autostart=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ -x "$source_dir/ShareXLinux" ]] || { printf 'Missing Linux binary in %s\n' "$source_dir" >&2; exit 1; }
[[ -d "$source_dir/ShareXLinux_ShareXLinux.resources/Desktop" ]] || {
    printf 'Missing desktop resources in %s\n' "$source_dir" >&2
    exit 1
}

mkdir -p "$app_dir" "$bin_dir" "$desktop_dir"
rm -rf "$app_dir/ShareXLinux_ShareXLinux.resources"
cp "$source_dir/ShareXLinux" "$app_dir/ShareXLinux"
cp -R "$source_dir/ShareXLinux_ShareXLinux.resources" "$app_dir/"
chmod 0755 "$app_dir/ShareXLinux"
ln -sfn "$app_dir/ShareXLinux" "$bin_dir/sharex-linux"

desktop_exec="\"$bin_dir/sharex-linux\""
escaped_exec="${desktop_exec//\\/\\\\}"
escaped_exec="${escaped_exec//&/\\&}"
escaped_exec="${escaped_exec//|/\\|}"
sed "s|@EXEC@|$escaped_exec|g" "$source_dir/packaging/sharex.desktop" > "$desktop_dir/io.github.PDGamerSG.ShareXLinux.desktop"

if $enable_autostart; then
    mkdir -p "$autostart_dir"
    sed "s|@EXEC@|$escaped_exec|g" "$source_dir/packaging/sharex-autostart.desktop" > "$autostart_dir/io.github.PDGamerSG.ShareXLinux.desktop"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
fi

printf 'Installed ShareX Linux at %s\n' "$app_dir"
printf 'Launcher: %s\n' "$bin_dir/sharex-linux"
if $enable_autostart; then
    printf 'Autostart: %s\n' "$autostart_dir/io.github.PDGamerSG.ShareXLinux.desktop"
fi
