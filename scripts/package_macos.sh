#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
if [[ "${1:-}" != "--skip-build" ]]; then
  flutter build macos --release
fi
app="$project_dir/build/macos/Build/Products/Release/QuotaMate.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
artifact="QuotaMate-$version-macos-universal"
mkdir -p "$project_dir/dist"
helper_build_dir="$(mktemp -d "$project_dir/build/claude-helper.XXXXXX")"
stage_dir=""
cleanup() {
  if [[ -n "$stage_dir" ]]; then rm -rf "$stage_dir"; fi
  rm -rf "$helper_build_dir"
}
trap cleanup EXIT
for architecture in arm64 x86_64; do
  xcrun swiftc -O -target "$architecture-apple-macos11.0" "$project_dir/scripts/claude_statusline.swift" -o "$helper_build_dir/$architecture"
done
xcrun lipo -create "$helper_build_dir/arm64" "$helper_build_dir/x86_64" -output "$app/Contents/Resources/quotamate-claude-statusline"
chmod 755 "$app/Contents/Resources/quotamate-claude-statusline"
codesign --force --sign - --timestamp=none "$app/Contents/Resources/quotamate-claude-statusline"
# Local development signature only; this is not Developer ID signing or notarization.
codesign --force --deep --sign - --preserve-metadata=entitlements --timestamp=none "$app"
codesign --verify --deep --strict "$app"
stage_dir="$(mktemp -d "$project_dir/dist/stage.XXXXXX")"
ditto "$app" "$stage_dir/QuotaMate.app"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname "QuotaMate" -srcfolder "$stage_dir" -ov -format UDZO "$project_dir/dist/$artifact.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$project_dir/dist/$artifact.zip"
cd "$project_dir/dist"
shasum -a 256 "$artifact.dmg" "$artifact.zip" > SHA256SUMS
python3 "$project_dir/scripts/clean_old_packages.py" "$project_dir/dist" "$version"
