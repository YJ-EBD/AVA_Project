#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flutter_dir="$(cd "$script_dir/.." && pwd)"
pubspec_path="$flutter_dir/pubspec.yaml"
app_version_path="$flutter_dir/lib/src/config/app_version.dart"

requested_version="${1:-}"
requested_build="${2:-}"

current_full="$(awk '/^version:/{print $2; exit}' "$pubspec_path")"
if [[ -z "$current_full" ]]; then
  echo "pubspec.yaml version was not found." >&2
  exit 1
fi

current_version="${current_full%%+*}"
current_build="${current_full##*+}"
if [[ "$current_build" == "$current_full" ]]; then
  current_build="0"
fi

if [[ -z "$requested_version" ]]; then
  IFS='.' read -r major minor patch <<< "$current_version"
  requested_version="${major}.${minor}.$((patch + 1))"
fi

if [[ ! "$requested_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must use semantic version format like 0.1.298." >&2
  exit 1
fi

if [[ -z "$requested_build" ]]; then
  requested_build="$((current_build + 1))"
fi

if [[ ! "$requested_build" =~ ^[0-9]+$ ]] || [[ "$requested_build" -le 0 ]]; then
  echo "Build number must be a positive integer." >&2
  exit 1
fi

VERSION="$requested_version" BUILD="$requested_build" perl -0pi -e \
  's/^version:\s*.*$/version: $ENV{VERSION}+$ENV{BUILD}/m' \
  "$pubspec_path"

VERSION="$requested_version" BUILD="$requested_build" perl -0pi -e '
  s/(static const name = String\.fromEnvironment\(\s*'\''AVA_APP_VERSION'\'',\s*defaultValue:\s*'\'')[^'\'']+('\'',)/$1$ENV{VERSION}$2/s;
  s/(static const buildNumber = int\.fromEnvironment\(\s*'\''AVA_BUILD_NUMBER'\'',\s*defaultValue:\s*)\d+(,)/$1$ENV{BUILD}$2/s;
' "$app_version_path"

echo "AVA Flutter version bumped to ${requested_version}+${requested_build}"
