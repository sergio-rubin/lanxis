#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p dist
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk dist/lanxis-android-armeabi-v7a-0.1.0.apk
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk dist/lanxis-android-arm64-v8a-0.1.0.apk
cp build/app/outputs/flutter-apk/app-x86_64-release.apk dist/lanxis-android-x86_64-0.1.0.apk
tar -C build/linux/x64/release/bundle -czf dist/lanxis-linux-x64-0.1.0.tar.gz .
(
  cd dist
  sha256sum lanxis-android-*-0.1.0.apk lanxis-linux-x64-0.1.0.tar.gz > SHA256SUMS
)
