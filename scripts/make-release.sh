#!/bin/zsh
# Builds a Release version of iContainer.app and packages it as a zip
# ready to attach to a GitHub release.
#
# The app is ad-hoc signed: release builds are not notarized (see the
# README's first-launch note). When a Developer ID certificate becomes
# available, set SIGN_IDENTITY to its name and add a notarytool step.
set -euo pipefail

cd "$(dirname "$0")/.."

# Use the full Xcode toolchain even when xcode-select points at the
# Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SIGN_IDENTITY="${SIGN_IDENTITY:--}" # "-" = ad-hoc
VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' iContainer.xcodeproj/project.pbxproj | head -1)
DERIVED=$(mktemp -d /tmp/icontainer-release.XXXXXX)
DIST="dist"

echo "Building iContainer ${VERSION} (Release)..."
xcodebuild -project iContainer.xcodeproj \
  -scheme iContainer \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build | grep -E "error:|warning: [^M]|BUILD" || true

APP="$DERIVED/Build/Products/Release/iContainer.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }

echo "Re-signing (deep, ${SIGN_IDENTITY})..."
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

mkdir -p "$DIST"
ZIP="$DIST/iContainer-v${VERSION}.zip"
rm -f "$ZIP"
echo "Packaging $ZIP..."
ditto -c -k --keepParent "$APP" "$ZIP"

rm -rf "$DERIVED"
echo "Done: $ZIP"
echo "Attach it to the GitHub release for tag v${VERSION}."
