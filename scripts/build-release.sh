#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="$project_root/dist"
signing_identity="-"
notary_profile=""
dry_run=false
run_tests=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --skip-tests) run_tests=false; shift ;;
        --sign) signing_identity="${2:?Missing signing identity}"; shift 2 ;;
        --notarize) notary_profile="${2:?Missing keychain profile}"; shift 2 ;;
        --output) output_dir="${2:?Missing output directory}"; shift 2 ;;
        --help) printf '%s\n' 'Usage: scripts/build-release.sh [--dry-run] [--skip-tests] [--output DIR] [--sign IDENTITY] [--notarize KEYCHAIN_PROFILE]'; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
done
if [[ -n "$notary_profile" && "$signing_identity" == "-" ]]; then
    printf '%s\n' 'Notarization requires --sign with a Developer ID Application identity.' >&2
    exit 1
fi
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
cd "$project_root"
build_root="$project_root/.build/universal-release"
bundle="$output_dir/ShareX Mac.app"
archive="$output_dir/ShareXMac-universal.zip"

run() {
    if $dry_run; then printf '%q ' "$@"; printf '\n'; else "$@"; fi
}

if $run_tests; then run swift test --build-system native; fi
for architecture in arm64 x86_64; do
    run swift build --build-system native -c release --triple "${architecture}-apple-macosx13.0" \
        --scratch-path "$build_root/$architecture" --product ShareXMac
done

# Stage a complete bundle before replacing any prior build in the output folder.
staging="$output_dir/.ShareXMac-staging-$$.app"
trap 'rm -rf "$staging"' EXIT
run mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
run cp Resources/Info.plist "$staging/Contents/Info.plist"
run cp LICENSE NOTICE "$staging/Contents/Resources/"
if $dry_run; then
    arm_binary="$build_root/arm64/arm64-apple-macosx/release/ShareXMac"
    intel_binary="$build_root/x86_64/x86_64-apple-macosx/release/ShareXMac"
else
    arm_bin_dir="$(swift build --build-system native -c release --triple arm64-apple-macosx13.0 --scratch-path "$build_root/arm64" --show-bin-path)"
    intel_bin_dir="$(swift build --build-system native -c release --triple x86_64-apple-macosx13.0 --scratch-path "$build_root/x86_64" --show-bin-path)"
    arm_binary="$arm_bin_dir/ShareXMac"
    intel_binary="$intel_bin_dir/ShareXMac"
fi
run xcrun lipo -create "$arm_binary" "$intel_binary" -output "$staging/Contents/MacOS/ShareXMac"
run xcrun swift scripts/make-icon.swift "$build_root/ShareXMac.iconset"
run xcrun iconutil -c icns "$build_root/ShareXMac.iconset" -o "$staging/Contents/Resources/ShareXMac.icns"
run /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$staging/Contents/Info.plist"

if [[ "$signing_identity" == "-" ]]; then
    run codesign --force --sign - --entitlements Resources/ShareXMac.entitlements "$staging"
else
    run codesign --force --options runtime --timestamp --sign "$signing_identity" \
        --entitlements Resources/ShareXMac.entitlements "$staging"
fi
run codesign --verify --strict --verbose=2 "$staging"
run xcrun lipo "$staging/Contents/MacOS/ShareXMac" -verify_arch arm64
run xcrun lipo "$staging/Contents/MacOS/ShareXMac" -verify_arch x86_64
if ! $dry_run; then
    if [[ -e "$bundle" ]]; then
        # Only replace a bundle created for this application.
        existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")"
        [[ "$existing_id" == "io.github.pdgamersg.ShareXMac" ]] || { printf '%s\n' 'Refusing to replace an unrelated app.' >&2; exit 1; }
        rm -rf "$bundle"
    fi
fi
run mv "$staging" "$bundle"
run ditto -c -k --sequesterRsrc --keepParent "$bundle" "$archive"
if [[ -n "$notary_profile" ]]; then
    run xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" --wait
    run xcrun stapler staple "$bundle"
    run xcrun stapler validate "$bundle"
    run ditto -c -k --sequesterRsrc --keepParent "$bundle" "$archive"
fi
printf 'App: %s\nArchive: %s\n' "$bundle" "$archive"
