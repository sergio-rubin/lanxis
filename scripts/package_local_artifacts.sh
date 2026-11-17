#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p dist
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk dist/lanxis-android-armeabi-v7a-0.1.0.apk
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk dist/lanxis-android-arm64-v8a-0.1.0.apk
cp build/app/outputs/flutter-apk/app-x86_64-release.apk dist/lanxis-android-x86_64-0.1.0.apk
tar -C build/linux/x64/release/bundle -czf dist/lanxis-linux-x64-0.1.0.tar.gz .
rm -f dist/lanxis-windows-x64-0.1.0.zip
if [[ -n "${LANXIS_WINDOWS_ARTIFACT:-}" ]]; then
  cp "$LANXIS_WINDOWS_ARTIFACT" dist/lanxis-windows-x64-0.1.0.zip
fi
(
  cd dist
  artifacts=(lanxis-android-*-0.1.0.apk lanxis-linux-x64-0.1.0.tar.gz)
  if [[ -f lanxis-windows-x64-0.1.0.zip ]]; then
    artifacts+=(lanxis-windows-x64-0.1.0.zip)
  fi
  sha256sum "${artifacts[@]}" > SHA256SUMS
)
