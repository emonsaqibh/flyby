#!/bin/bash
# Builds Flyby. There are two builds, with different bundle identifiers, so they
# keep separate settings, Keychain entries, Google session, login item and
# Screen Recording grant, and can run side by side:
#
#   ./build.sh               → build/Flyby Dev.app   com.fringecore.flyby.dev
#                              and a copy kept in dev-builds/<version>/
#   ./run.sh                   (the same, then launch it)
#   CONF=debug ./build.sh      unoptimized, for lldb
#
#   FLAVOR=release VERSION=0.3.0 ./build.sh
#                            → build/Flyby.app       com.fringecore.flyby
#                              (what ./release.sh runs; use that instead)
#
# All development happens in the dev build. It takes its version from git
# ("0.3.0-dev.14 · pill": 14 commits past v0.3.0, on branch feature/pill), wears
# an amber icon and a DEV badge, and never checks for updates. A release build is
# made once per version by release.sh, and frozen. Both are Apple silicon only:
# Flyby needs macOS 27, which doesn't run on Intel Macs.
#
# Needs Xcode 27. macOS 27's SwiftUI implements @State and friends as macros,
# and their compiler plugin ships with Xcode, not the Command Line Tools — so
# when xcode-select points at the CLT, Xcode is used for this build anyway.
#
# Signing: macOS keys Flyby's privacy grants (Screen Recording, Full Disk
# Access) to its signature, and an ad-hoc signature changes with every
# build — so a build signed that way loses them all, on every rebuild and every
# update. So each flavor is signed with this Mac's certificate for it when there
# is one: "Flyby Dev Local Signing" (scripts/dev-signing.sh) and "Flyby Release
# Signing" (scripts/release-signing.sh). Otherwise ad-hoc — CI has neither.
# SIGN_IDENTITY overrides; a Developer ID also turns on the hardened runtime and
# a secure timestamp (both required for notarization, which release.sh does).
set -euo pipefail
cd "$(dirname "$0")"

# MARK: - Toolchain

# An Xcode, not the CLT (which lack the macro plugin), with the macOS 27 SDK.
builds_flyby() {
  [[ -f "$1/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]] || return 1
  local sdk
  sdk="$(DEVELOPER_DIR="$1" xcrun --sdk macosx --show-sdk-version 2>/dev/null)" || return 1
  [[ "${sdk%%.*}" -ge 27 ]]
}
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! builds_flyby "$(xcode-select -p)"; then
  while IFS= read -r xcode; do
    if builds_flyby "$xcode/Contents/Developer"; then
      export DEVELOPER_DIR="$xcode/Contents/Developer"
      break
    fi
  done < <(echo /Applications/Xcode.app; mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null)
  [[ -n "${DEVELOPER_DIR:-}" ]] \
    || { echo "✗ Flyby needs Xcode 27 — the Command Line Tools can't build macOS 27 SwiftUI" >&2; exit 1; }
  echo "› Using $(dirname "$(dirname "$DEVELOPER_DIR")") (xcode-select points at a toolchain that can't build Flyby)"
fi

FLAVOR="${FLAVOR:-dev}"
BASE_ID="com.fringecore.flyby"
REQUESTED_IDENTITY="${SIGN_IDENTITY:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEV_IDENTITY="Flyby Dev Local Signing"
RELEASE_IDENTITY="Flyby Release Signing"

# This Mac's certificate for the flavor, unless SIGN_IDENTITY picked one.
use_local_identity() {
  if [[ -z "$REQUESTED_IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$1\""; then
    SIGN_IDENTITY="$1"
  fi
}
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)

case "$FLAVOR" in
  dev)
    # Optimized by default: an unoptimized SwiftUI build is laggier than what
    # ships, which makes the dev app useless for judging how the pill feels.
    CONF="${CONF:-release}"
    APP_NAME="Flyby Dev"
    BUNDLE_ID="$BASE_ID.dev"
    ICON=Resources/AppIcon-Dev.icns
    ARCHS="${ARCHS:-arm64}"
    # A readable version from git: v0.3.0-14-g6160965 → "0.3.0-dev.14", plus
    # " · pill" on feature/pill. Before the first v-tag, the plist's version.
    if [[ -z "${VERSION:-}" ]]; then
      if DESCRIBE="$(git describe --tags --match 'v[0-9]*' --long 2>/dev/null)"; then
        REST="${DESCRIBE#v}"; REST="${REST%-g*}"            # 0.3.0-14
        VERSION="${REST%-*}-dev.${REST##*-}"
      else
        VERSION="$PLIST_VERSION-dev"
      fi
      BRANCH="$(git symbolic-ref --short -q HEAD || true)"
      case "$BRANCH" in ""|dev|main) ;; *) VERSION="$VERSION · ${BRANCH##*/}" ;; esac
    fi
    BUILD_NUMBER="$(date +%Y%m%d%H%M)"
    use_local_identity "$DEV_IDENTITY"
    ;;
  release)
    CONF="${CONF:-release}"
    APP_NAME="Flyby"
    BUNDLE_ID="$BASE_ID"
    ICON=Resources/AppIcon.icns
    ARCHS="${ARCHS:-arm64}"
    : "${VERSION:?FLAVOR=release needs VERSION — use ./release.sh <version>}"
    # Monotonic across releases, which is all CFBundleVersion has to be.
    BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
    use_local_identity "$RELEASE_IDENTITY"
    ;;
  *) echo "✗ unknown FLAVOR '$FLAVOR' (dev|release)" >&2; exit 2 ;;
esac
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)"
APP="${OUT_DIR:-build}/$APP_NAME.app"

ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

# MARK: - Compile

echo "› Compiling $APP_NAME $VERSION ($CONF, $ARCHS)…"
swift build -c "$CONF" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONF" "${ARCH_FLAGS[@]}" --show-bin-path)/Flyby"

# MARK: - Bundle

echo "› Assembling the app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Flyby"

# SwiftPM's default build system (from Xcode 27) stamps the binary with the
# deployment target as its SDK version too, so a 27.0 target built with a
# newer SDK claims the older one. macOS picks which generation of its design
# an app gets from that number, so write the SDK that was actually used back in.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
read -r MIN_OS STAMPED_SDK < <(otool -l "$APP/Contents/MacOS/Flyby" \
  | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "minos" { minos = $2 } found && $1 == "sdk" { print minos, $2; exit }')
if [[ -n "$MIN_OS" && "$STAMPED_SDK" != "$SDK_VERSION" ]]; then
  echo "› Stamping the macOS $SDK_VERSION SDK (the build recorded $STAMPED_SDK)…"
  vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
    -output "$APP/Contents/MacOS/Flyby" "$APP/Contents/MacOS/Flyby"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleIdentifier $BUNDLE_ID" \
    -c "Set :CFBundleName $APP_NAME" \
    -c "Set :CFBundleDisplayName $APP_NAME" \
    -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $BUILD_NUMBER" \
    "$APP/Contents/Info.plist"
if [[ -n "$COMMIT" ]]; then
  # Shown in Settings › General next to the version.
  $PB -c "Add :FlybyCommit string $COMMIT" "$APP/Contents/Info.plist" 2>/dev/null \
    || $PB -c "Set :FlybyCommit $COMMIT" "$APP/Contents/Info.plist"
fi
# Ancient, still expected: Launch Services reads it before the plist.
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The icons are generated art; draw whichever is missing (see
# Resources/IconGenerator/README.md to swap in real artwork).
if [[ ! -f "$ICON" ]]; then
  echo "› Drawing $(basename "$ICON")…"
  if [[ "$FLAVOR" == dev ]]; then
    swift Resources/IconGenerator/generate.swift --dev
  else
    swift Resources/IconGenerator/generate.swift
  fi
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# MARK: - Sign

echo "› Signing ($SIGN_IDENTITY)…"
sign_args=(--force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID")
# Only a Developer ID is notarized; the local certificates aren't, and
# Apple's timestamp service has no business with them.
if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
  sign_args+=(--options runtime --timestamp)
fi
codesign "${sign_args[@]}" "$APP"
codesign --verify --strict "$APP"

echo "✓ Built $APP ($BUNDLE_ID $VERSION, build $BUILD_NUMBER)"

# Keep every dev build by version, alongside the frozen releases in releases/.
# Rebuilding the same commit replaces that version's copy.
if [[ "$FLAVOR" == dev && -z "${OUT_DIR:-}" ]]; then
  KEEP="dev-builds/$VERSION"
  rm -rf "$KEEP"
  mkdir -p "$KEEP"
  ditto "$APP" "$KEEP/$APP_NAME.app"
  echo "  kept a copy in ${KEEP}/"
fi
