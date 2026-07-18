#!/bin/zsh
# Builds a Release iContainer.app, signs it, notarizes + staples it, and
# packages it as a DMG ready to attach to a GitHub release.
#
# Why a DMG (not a bare .zip): the app embeds Sparkle.framework. When a bare
# .zip is downloaded via a browser, Safari's "Open safe files after
# downloading" auto-extracts it with Archive Utility, which mangles the
# framework's versioned symlink layout and breaks its code-signature seal
# ("unsealed contents present in the root directory of an embedded
# framework") — Gatekeeper then blocks the app even though it's notarized. A
# DMG is mounted, not extracted, so the bundle reaches disk byte-for-byte.
# Sparkle updates from the DMG too (it handles .dmg natively).
#
# Signing is done INSIDE-OUT (never `--deep`): Sparkle's nested helpers
# (XPCServices, Autoupdate, Updater.app) are signed first, then the
# framework, then the app. `--deep` mis-seals versioned frameworks.
#
# Signing behaviour:
#   - Developer ID Application identity present (or SIGN_IDENTITY set):
#     full signed + notarized + stapled DMG.
#   - Otherwise: ad-hoc signed .zip fallback (unnotarized, dev only).
#
# Notarization uses a stored notarytool keychain profile (default name
# "icontainer-notary"; see the app's notarization setup).
# Env overrides: SIGN_IDENTITY, NOTARY_PROFILE, NOTARIZE=0, APPCAST=0.
set -euo pipefail

cd "$(dirname "$0")/.."

# Use the full Xcode toolchain even when xcode-select points at the CLT.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Resolve the signing identity: explicit override wins; else the first
# "Developer ID Application" cert in the keychain; else ad-hoc ("-").
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$SIGN_IDENTITY"
else
  IDENTITY=$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+"(.*)"$/\1/')
  IDENTITY="${IDENTITY:--}"
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-icontainer-notary}"
NOTARIZE="${NOTARIZE:-1}"

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' iContainer.xcodeproj/project.pbxproj | head -1)
DERIVED=$(mktemp -d /tmp/icontainer-release.XXXXXX)
DIST="dist"

echo "Building iContainer ${VERSION} (Release)..."
xcodebuild -project iContainer.xcodeproj \
  -scheme iContainer \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build | grep -E "error:|warning: [^M]|BUILD" || true

APP="$DERIVED/Build/Products/Release/iContainer.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }

mkdir -p "$DIST"

# ---------------------------------------------------------------------------
# Ad-hoc fallback (no Developer ID identity): zip only, unnotarized.
# ---------------------------------------------------------------------------
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signing ad-hoc (no Developer ID identity — NOT notarized)..."
  codesign --force --deep --sign "-" "$APP"
  codesign --verify --deep --strict "$APP"
  ZIP="$DIST/iContainer-v${VERSION}.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  rm -rf "$DERIVED"
  echo "Done (ad-hoc, unnotarized): $ZIP"
  exit 0
fi

# ---------------------------------------------------------------------------
# Developer ID: inside-out signing.
# ---------------------------------------------------------------------------
FLAGS=(--force --options runtime --timestamp --sign "$IDENTITY")
echo "Signing with: $IDENTITY (inside-out, hardened runtime + timestamp)..."

SPK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPK" ]]; then
  V="$SPK/Versions/Current"
  for xpc in "$V"/XPCServices/*.xpc(N); do codesign "${FLAGS[@]}" "$xpc"; done
  [[ -e "$V/Autoupdate" ]] && codesign "${FLAGS[@]}" "$V/Autoupdate"
  [[ -e "$V/Updater.app" ]] && codesign "${FLAGS[@]}" "$V/Updater.app"
  codesign "${FLAGS[@]}" "$SPK"
fi
# Any other embedded frameworks (belt-and-suspenders; never --deep).
for fw in "$APP"/Contents/Frameworks/*.framework(N); do
  [[ "$fw" == "$SPK" ]] && continue
  codesign "${FLAGS[@]}" "$fw"
done
# Finally the app.
codesign "${FLAGS[@]}" "$APP"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
# Launch assessment (this is what Gatekeeper enforces — must be "accepted").
spctl -a -vvv -t exec "$APP" 2>&1 | head -3 || true

# ---------------------------------------------------------------------------
# Notarize the app, then staple it (so the app itself passes offline).
# ---------------------------------------------------------------------------
if [[ "$NOTARIZE" == "1" ]]; then
  APPZIP=$(mktemp -d)/icontainer-app.zip
  ditto -c -k --keepParent "$APP" "$APPZIP"
  echo "Notarizing the app (profile: $NOTARY_PROFILE) — a few minutes..."
  xcrun notarytool submit "$APPZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling the app..."
  xcrun stapler staple "$APP"
  rm -f "$APPZIP"
fi

# ---------------------------------------------------------------------------
# Build the DMG from the (stapled) app, then sign + notarize + staple it.
# ---------------------------------------------------------------------------
DMG="$DIST/iContainer-v${VERSION}.dmg"
rm -f "$DMG"
STAGE=$(mktemp -d /tmp/icontainer-dmg.XXXXXX)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
echo "Creating DMG..."
hdiutil create -volname "iContainer ${VERSION}" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

echo "Signing the DMG..."
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [[ "$NOTARIZE" == "1" ]]; then
  echo "Notarizing the DMG — a few minutes..."
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling the DMG..."
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

# Verify the app *as it will arrive on the user's disk*: mount the DMG and
# assess the app inside (this is the check that would have caught the broken
# Sparkle seal before shipping).
echo "Verifying the app inside the DMG..."
MNT=$(mktemp -d /tmp/icontainer-mnt.XXXXXX)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MNT" >/dev/null
spctl -a -vvv -t exec "$MNT/iContainer.app" 2>&1 | head -3 || true
codesign --verify --deep --strict "$MNT/iContainer.app" && echo "  DMG app signature OK"
hdiutil detach "$MNT" >/dev/null || true
rm -rf "$MNT"

# ---------------------------------------------------------------------------
# Sparkle appcast — single-item, enclosure points at the DMG on the GitHub
# release, EdDSA-signed with the keychain key. Commit + push appcast.xml.
# ---------------------------------------------------------------------------
if [[ "${APPCAST:-1}" == "1" ]]; then
  SPARKLE_BIN=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)
  if [[ -n "$SPARKLE_BIN" && -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "Generating Sparkle appcast..."
    APPCAST_DIR=$(mktemp -d /tmp/icontainer-appcast.XXXXXX)
    cp "$DMG" "$APPCAST_DIR/"
    "$SPARKLE_BIN/generate_appcast" \
      --download-url-prefix "https://github.com/nico81/iContainer/releases/download/v${VERSION}/" \
      --link "https://github.com/nico81/iContainer" \
      -o appcast.xml \
      "$APPCAST_DIR"
    rm -rf "$APPCAST_DIR"
    echo "Wrote appcast.xml — commit + push it so the update feed serves v${VERSION}."
  else
    echo "WARNING: Sparkle tools not found under DerivedData; skipping appcast." >&2
  fi
fi

rm -rf "$DERIVED"
echo "Done: $DMG"
echo "Attach it to the GitHub release for tag v${VERSION}."
