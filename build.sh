#!/bin/sh
# Builds and signs HerdrMenu.app into ~/Applications, where Spotlight finds it
# and where the "Launch at login" item points.
set -e
cd "$(dirname "$0")"
bundle="$HOME/Applications/HerdrMenu.app"
app="$bundle/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
swiftc HerdrMenu.swift -o "$app/MacOS/HerdrMenu"
cp sheep.png "$app/Resources/"
# App icon from herdr's logo (logo.png, 512px): an iconset of every size up to 512, packed into AppIcon.icns
iconset=$(mktemp -d)/AppIcon.iconset
mkdir "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s logo.png --out "$iconset/icon_${s}x${s}.png" >/dev/null
  [ $((s * 2)) -le 512 ] && sips -z $((s * 2)) $((s * 2)) logo.png --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Resources/AppIcon.icns"
rm -r "$(dirname "$iconset")"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.pierre-charles.herdr-menu</string>
  <key>CFBundleName</key><string>HerdrMenu</string>
  <key>CFBundleExecutable</key><string>HerdrMenu</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Ad-hoc signature over the whole bundle (no developer account needed); macOS login items check it
codesign --force --sign - "$bundle"
echo "Built $bundle"
# If the old build is running, swap it for the new one (waiting for it to quit, or open would just refocus it)
if pkill -x HerdrMenu; then
  while pgrep -qx HerdrMenu; do sleep 0.1; done
  open "$bundle"
  echo "Restarted HerdrMenu"
fi
