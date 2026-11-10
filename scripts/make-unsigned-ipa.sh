#!/bin/bash
#
# Btt Music — unsigned device IPA builder
#
# Produces BttMusic-Unsigned.ipa: a real arm64 iOS-device build of the app
# (com.ahmed.btmu, with the Share Extension embedded) with code signing
# DISABLED (CODE_SIGNING_ALLOWED=NO). No Apple Developer account, team or
# certificates are involved.
#
# Requirements: a Mac with Xcode 16+ (for the iOS 18 SDK). Nothing else.
# Also runs on GitHub-hosted macOS runners (see .github/workflows/
# build-unsigned-ipa.yml).
#
# Usage:
#   ./scripts/make-unsigned-ipa.sh
#
# Output:
#   build/BttMusic-Unsigned.ipa          <- the deliverable
#   build/BttMusic.xcarchive             <- the archive, kept for reference
#
# The unsigned IPA is what tools like Sideloadly, AltStore, or TrollStore
# expect: they re-sign it with YOUR Apple ID and install it on your iPhone.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ_DIR="$REPO_ROOT/ios-btt-music"
BUILD_DIR="$REPO_ROOT/build"

command -v xcodebuild >/dev/null || {
  echo "ERROR: xcodebuild not found. Install Xcode from the Mac App Store," >&2
  echo "then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
}

mkdir -p "$BUILD_DIR"

echo "==> Archiving BttMusic for iOS devices (arm64), code signing disabled"
xcodebuild archive \
  -project "$PROJ_DIR/BttMusic.xcodeproj" \
  -scheme BttMusic \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$BUILD_DIR/BttMusic.xcarchive" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  | tail -n 8

APP_PATH="$BUILD_DIR/BttMusic.xcarchive/Products/Applications/BttMusic.app"
[ -d "$APP_PATH" ] || { echo "ERROR: BttMusic.app not found in archive" >&2; exit 1; }

# --- Verify this is a real iOS DEVICE binary, not a simulator one -----------
# Note: on Apple silicon, simulator slices are also arm64, so lipo alone is
# not enough. The Mach-O LC_BUILD_VERSION load command carries a numeric
# platform code: 2 = iOS device, 7 = iossimulator (vtool -show-build prints
# ` platform 2`, with a leading space).
echo "==> Verifying device slices (arm64 + platform iOS)"
BINARY="$APP_PATH/BttMusic"

lipo -info "$BINARY" | tee /dev/stderr | grep -q "arm64" || {
  echo "ERROR: binary does not contain an arm64 slice" >&2
  exit 1
}

PLATFORMS="$(vtool -show-build "$BINARY" | grep -E '^ *platform ' | sed 's/^ *//' | sort -u)" || true
echo "Build platforms found:"
echo "$PLATFORMS" | tee /dev/stderr

echo "$PLATFORMS" | grep -qE '^platform 2$' || {
  echo "ERROR: binary is not an iOS-device build (Mach-O platform must be 2 = iOS; got: $PLATFORMS)" >&2
  exit 1
}
if echo "$PLATFORMS" | grep -qE '^platform 7$'; then
  echo "ERROR: binary is a simulator build (platform 7 = iossimulator)" >&2
  exit 1
fi

# Sanity: bundle IDs and the embedded Share Extension must be intact.
plutil -extract CFBundleIdentifier raw "$APP_PATH/Info.plist" | grep -qx "com.ahmed.btmu" || {
  echo "ERROR: unexpected app bundle identifier" >&2
  exit 1
}
APP_EXTENSIONS_DIR="$APP_PATH/PlugIns"
[ -d "$APP_EXTENSIONS_DIR/ShareExtension.appex" ] || {
  echo "ERROR: ShareExtension.appex not embedded in the app" >&2
  exit 1
}
plutil -extract CFBundleIdentifier raw "$APP_EXTENSIONS_DIR/ShareExtension.appex/Info.plist" | grep -qx "com.ahmed.btmu.shareextension" || {
  echo "ERROR: unexpected Share Extension bundle identifier" >&2
  exit 1
}

echo "==> Packaging Payload into unsigned IPA"
rm -rf "$BUILD_DIR/Payload" "$BUILD_DIR/BttMusic-Unsigned.ipa"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/BttMusic.app"

(cd "$BUILD_DIR" && zip -qry BttMusic-Unsigned.ipa Payload)

echo
echo "✅ Done: $BUILD_DIR/BttMusic-Unsigned.ipa"
echo "   (arm64 device build, unsigned — sign with Sideloadly/AltStore/TrollStore)"
