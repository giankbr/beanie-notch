#!/bin/bash
# Builds dist/Beanie.app (universal, ad-hoc signed) and dist/Beanotch.dmg.
set -euo pipefail
cd "$(dirname "$0")"
version="${VERSION:-1.0.0}"
dist="dist"
app="$dist/Beanie.app"

swift build -c release --arch arm64 --arch x86_64 -Xswiftc -Osize -Xlinker -dead_strip

rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp .build/apple/Products/Release/Beanie "$app/Contents/MacOS/Beanie"
strip -x "$app/Contents/MacOS/Beanie"

# The Now Playing helper: plain clang against Xcode's SDK (the Command Line Tools one may lag the OS).
dev="$(xcode-select -p)"
env -u SDKROOT DEVELOPER_DIR="$dev" xcrun clang -isysroot "$(DEVELOPER_DIR="$dev" xcrun --sdk macosx --show-sdk-path)" \
  -dynamiclib -fobjc-arc -Os -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -framework Foundation -framework AppKit Helper/NowPlaying.m -o "$app/Contents/Frameworks/libNowPlaying.dylib"
strip -x "$app/Contents/Frameworks/libNowPlaying.dylib"
sed "s/@VERSION@/$version/g" Resources/Info.plist > "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
cp -R Resources/Fonts "$app/Contents/Resources/Fonts"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# The icon is drawn in docs/landing-page.pen (App Icon frame) and exported to Resources/AppIcon.png.
cp Resources/AppIcon.png "$work/icon.png"
mkdir "$work/Beanie.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$work/icon.png" --out "$work/Beanie.iconset/icon_${s}x${s}.png" > /dev/null
  sips -z $((s * 2)) $((s * 2)) "$work/icon.png" --out "$work/Beanie.iconset/icon_${s}x${s}@2x.png" > /dev/null
done
iconutil -c icns "$work/Beanie.iconset" -o "$app/Contents/Resources/Beanie.icns"

codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"

# A laid-out DMG (background, icon spots) through dmgbuild, kept in a local venv; a plain one without it.
venv=".build/dmgvenv"
if [ ! -x "$venv/bin/dmgbuild" ]; then
  python3 -m venv "$venv" > /dev/null 2>&1 && "$venv/bin/pip" install -q dmgbuild > /dev/null 2>&1 || true
fi
if [ -x "$venv/bin/dmgbuild" ]; then
  swift tools/make_dmg_background.swift "$work/background.png"
  "$venv/bin/dmgbuild" -s tools/dmg_settings.py -D app="$app" -D background="$work/background.png" \
    "Beanotch $version" "$dist/Beanotch.dmg" > /dev/null
else
  mkdir "$work/dmg"
  cp -R "$app" "$work/dmg/"
  ln -s /Applications "$work/dmg/Applications"
  hdiutil create -volname "Beanotch $version" -srcfolder "$work/dmg" -ov -format UDZO "$dist/Beanotch.dmg" > /dev/null
fi
echo "built $app and $dist/Beanotch.dmg"
