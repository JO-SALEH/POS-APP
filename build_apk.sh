#!/usr/bin/env bash
# JO POS - build APK on Linux / macOS
set -e
cd "$(dirname "$0")"
command -v flutter >/dev/null || { echo "Flutter not found in PATH"; exit 1; }
if [ ! -d android ]; then
  cp pubspec.yaml pubspec.yaml.bak
  flutter create --platforms=android --project-name jo_pos_mobile --org com.joroyalty .
  mv pubspec.yaml.bak pubspec.yaml
  rm -rf test
fi
python3 tools/patch_android.py
flutter pub get
flutter build apk --release
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/JO_POS.apk
echo "DONE: dist/JO_POS.apk"
