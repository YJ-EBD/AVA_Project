#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flutter_dir="$(cd "$script_dir/.." && pwd)"
backend_dir="${BACKEND_DIR:-$(cd "$flutter_dir/../NodeBackend" && pwd)}"
api_base_url="${AVA_API_BASE_URL:-http://112.166.136.198:8080}"
ws_url="${AVA_WS_URL:-ws://112.166.136.198:8080/ws}"

cd "$flutter_dir"

pubspec_version="$(awk '/^version:/{print $2; exit}' pubspec.yaml)"
if [[ -z "$pubspec_version" ]]; then
  echo "pubspec.yaml version was not found." >&2
  exit 1
fi

app_version="${pubspec_version%%+*}"
build_number="${pubspec_version##*+}"
if [[ "$build_number" == "$pubspec_version" ]]; then
  build_number="1"
fi

flutter pub get
flutter build macos --release \
  --dart-define=AVA_API_BASE_URL="$api_base_url" \
  --dart-define=AVA_WS_URL="$ws_url" \
  --dart-define=AVA_APP_VERSION="$app_version" \
  --dart-define=AVA_BUILD_NUMBER="$build_number"

release_dir="$flutter_dir/build/macos/Build/Products/Release"
app_path="$(find "$release_dir" -maxdepth 1 -name '*.app' -print | head -n 1)"
if [[ -z "$app_path" ]]; then
  echo "macOS .app was not found under $release_dir." >&2
  exit 1
fi

dmg_name="AVA_Project_${app_version}_${build_number}_macOS.dmg"
installer_dir="$flutter_dir/build/macos/installer"
dmg_root="$installer_dir/dmgroot"
dmg_path="$installer_dir/$dmg_name"
updates_dir="$backend_dir/AppUpdates"

rm -rf "$dmg_root"
mkdir -p "$dmg_root" "$installer_dir" "$updates_dir"
ditto "$app_path" "$dmg_root/$(basename "$app_path")"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -volname "AVA Project" -srcfolder "$dmg_root" -ov -format UDZO "$dmg_path"
cp "$dmg_path" "$updates_dir/$dmg_name"

echo "Created macOS update package:"
echo "  $dmg_path"
echo "Copied to:"
echo "  $updates_dir/$dmg_name"
echo ""
echo "Server config:"
echo "  AVA_APP_MACOS_LATEST_VERSION=$app_version"
echo "  AVA_APP_MACOS_BUILD_NUMBER=$build_number"
echo "  AVA_APP_MACOS_FILE_NAME=$dmg_name"
