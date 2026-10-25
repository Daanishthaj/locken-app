#!/bin/bash
# Builds Locken for release and packages it as web/public/Locken.dmg, ready for release-signing.swift.
# Stages in ~/LockenStage (not the iCloud Desktop, which adds Finder tags that break the signature check).
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="$HOME/Library/Developer/Xcode/DerivedData/LockenRelease"
STAGE="$HOME/LockenStage"
APP="$DERIVED/Build/Products/Release/LockenTestApp.app"

echo "1/4 Building Locken (Release)..."
# Universal: runs on Apple silicon and Intel Macs (macOS 15 or later).
xcodebuild -project LockenTestApp.xcodeproj -scheme LockenTestApp -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet

echo "2/4 Staging in $STAGE..."
rm -rf "$STAGE"
mkdir "$STAGE"
ditto --norsrc --noextattr --noacl "$APP" "$STAGE/Locken.app"
ln -s /Applications "$STAGE/Applications"

echo "3/4 Checking the app..."
codesign --verify --deep --strict "$STAGE/Locken.app"
SIGNATURE=$(codesign -dvv "$STAGE/Locken.app" 2>&1)
[[ "$SIGNATURE" == *"TeamIdentifier=P36B98NRT2"* ]] \
  || { echo "Not signed with the Apple Development certificate (team P36B98NRT2). Stopping."; exit 1; }
ARCHS_BUILT=$(lipo -archs "$STAGE/Locken.app/Contents/MacOS/LockenTestApp")
[[ "$ARCHS_BUILT" == *x86_64* && "$ARCHS_BUILT" == *arm64* ]] \
  || { echo "Expected a universal app (arm64 and x86_64), got: $ARCHS_BUILT. Stopping."; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$STAGE/Locken.app/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$STAGE/Locken.app/Contents/Info.plist")

echo "4/4 Making web/public/Locken.dmg..."
hdiutil create -volname Locken -srcfolder "$STAGE" -ov -format UDZO web/public/Locken.dmg -quiet

echo
echo "Done: Locken $VERSION (build $BUILD). Next, sign it:"
echo "  swift scripts/release-signing.swift sign web/public/Locken.dmg $VERSION $BUILD \"What's new\""
