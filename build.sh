#!/bin/sh
# Builds and signs Remora.app into ~/Applications, where Spotlight finds it
# and where the "Launch at login" item points.
set -e
cd "$(dirname "$0")"
bundle="$HOME/Applications/Remora.app"
app="$bundle/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
swiftc -swift-version 5 *.swift -o "$app/MacOS/Remora"
cp icon/menubar.png "$app/Resources/"
# App icon from icon/remora.png (1024px, drawn by icon/make.py): an iconset of every size, packed into AppIcon.icns
iconset=$(mktemp -d)/AppIcon.iconset
mkdir "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s icon/remora.png --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) icon/remora.png --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Resources/AppIcon.icns"
rm -r "$(dirname "$iconset")"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.pierre-charles.remora</string>
  <key>CFBundleName</key><string>Remora</string>
  <key>CFBundleExecutable</key><string>Remora</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <!-- App Nap would hold back the island's mouse-moved events, so hovering the notch did nothing -->
  <key>NSAppSleepDisabled</key><true/>
</dict></plist>
PLIST
# Ad-hoc signature over the whole bundle (no developer account needed); macOS login items check it
codesign --force --sign - "$bundle"
echo "Built $bundle"
# If a build is running (or HerdrMenu, Remora's old name), swap it for the new one, waiting for it to quit,
# or open would just refocus it. Remora copies HerdrMenu's settings on its first launch, so the old app goes.
running=false
for old in Remora HerdrMenu; do
  if pkill -x $old; then
    running=true
    while pgrep -qx $old; do sleep 0.1; done
  fi
done
if [ -d "$HOME/Applications/HerdrMenu.app" ]; then
  rm -r "$HOME/Applications/HerdrMenu.app"
  echo "Removed HerdrMenu.app (Remora takes over its settings)"
  running=true
fi
if $running; then
  open "$bundle"
  echo "Started Remora"
fi
