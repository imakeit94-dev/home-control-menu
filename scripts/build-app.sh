#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swift build -c release
swift scripts/generate-icon.swift "$PWD"
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
APP="$PWD/dist/空调控制.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Assets/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
cp .build/release/AirControl "$APP/Contents/MacOS/AirControl.next"
mv -f "$APP/Contents/MacOS/AirControl.next" "$APP/Contents/MacOS/AirControl"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>AirControl</string>
  <key>CFBundleIdentifier</key><string>local.ivan.AirControl</string>
  <key>CFBundleName</key><string>空调控制</string>
  <key>CFBundleDisplayName</key><string>空调控制</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.3</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>连接家中的 Home Assistant，读取并控制智能家居设备。</string>
  <key>NSAppTransportSecurity</key><dict>
    <key>NSAllowsLocalNetworking</key><true/>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "已生成：$APP"
