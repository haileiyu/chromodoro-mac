#!/bin/zsh
# Builds build/Macodoro.app: a release binary, icons, Info.plist, and an ad-hoc signature.
# Needs only the Xcode Command Line Tools. Pass --install to copy it to /Applications.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=1.0.0
BUNDLE_ID=io.github.haileiyu.macodoro
APP=build/Macodoro.app

swift build -c release --product Macodoro
BIN="$(swift build -c release --show-bin-path)/Macodoro"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Macodoro"
cp Resources/icon16.png Resources/icon32.png Resources/idle16.png Resources/idle32.png "$APP/Contents/Resources/"

# App icon from the 1254 px transparent logo.
ICONSET="$(mktemp -d)/Macodoro.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/logo.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/logo.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Macodoro.icns"
rm -rf "${ICONSET:h}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Macodoro</string>
  <key>CFBundleDisplayName</key><string>Macodoro</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Macodoro</string>
  <key>CFBundleIconFile</key><string>Macodoro</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Pomodoro timer for the macOS menu bar.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for notifications and login items on this Mac.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
  # Quit a running copy so the new one replaces it.
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
  rm -rf /Applications/Macodoro.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Macodoro.app"
  open /Applications/Macodoro.app
fi
