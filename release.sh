#!/bin/bash
# Freezes the current commit as a versioned release of Flyby.
#
#   ./release.sh 0.3.0              a stable release
#   ./release.sh 0.4.0-beta.1       a beta (publish.sh makes it a GitHub pre-release)
#   INSTALL=0 ./release.sh 0.3.0    leave /Applications alone
#
# Builds the release flavor — Flyby.app, com.fringecore.flyby — and writes
# releases/<version>/ with the app, Flyby.zip (what install.sh and the in-app
# updater download), a snapshot of the exact source, and the commit it came from.
# A release is never rebuilt or overwritten: later changes only ever reach the dev
# build (./build.sh). Publish it with ./publish.sh <version> <notes.md>.
#
# Signing is ad-hoc unless SIGN_IDENTITY names a Developer ID. With NOTARY_PROFILE
# set as well, the app is notarized and stapled, and a DMG is made and notarized
# too — a DMG is pointless before then, since Gatekeeper blocks an un-notarized one
# downloaded in a browser. (DMG=1 forces one anyway.)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>   e.g. 0.3.0 or 0.4.0-beta.1}"
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]]; then
  echo "✗ '$VERSION' isn't a version — use x.y.z or x.y.z-beta.n" >&2
  exit 2
fi

APP_NAME="Flyby"
BUNDLE_ID="com.fringecore.flyby"
DEST="releases/$VERSION"
[[ -e "$DEST" ]] && { echo "✗ $DEST already exists — releases are immutable, pick a new version" >&2; exit 1; }

# The release has to be reproducible from its tag, so it's built from a clean tree.
if [[ -n "$(git status --porcelain)" && "${ALLOW_DIRTY:-0}" != 1 ]]; then
  echo "✗ uncommitted changes — commit first (or ALLOW_DIRTY=1 for a throwaway local build)" >&2
  exit 1
fi

# Every release signed the same way, or it's a new app to macOS and everyone
# grants Screen Recording (and Full Disk Access) all over again:
# with the release certificate (scripts/release-signing.sh, or its backup
# imported), or a Developer ID. ALLOW_ADHOC=1 for a throwaway local build.
if [[ -z "${SIGN_IDENTITY:-}" && "${ALLOW_ADHOC:-0}" != 1 ]] \
   && ! security find-identity -v -p codesigning 2>/dev/null | grep -qF '"Flyby Release Signing"'; then
  echo "✗ no \"Flyby Release Signing\" certificate on this Mac — run ./scripts/release-signing.sh (or import its .p12 backup), or set SIGN_IDENTITY" >&2
  exit 1
fi

NOTARIZE=false
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ "${SIGN_IDENTITY:--}" != "-" ]] || { echo "✗ notarizing needs a Developer ID — set SIGN_IDENTITY" >&2; exit 1; }
  NOTARIZE=true
fi
MAKE_DMG="${DMG:-$($NOTARIZE && echo 1 || echo 0)}"

# Build outside $DEST, so a failed build leaves no half-made release behind.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
FLAVOR=release VERSION="$VERSION" OUT_DIR="$STAGE" ./build.sh
APP="$STAGE/$APP_NAME.app"

notarize() {
  echo "› Notarizing $(basename "$1") (this takes a few minutes)…"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if $NOTARIZE; then
  # notarytool takes a zip, not a bundle; the ticket is then stapled to the
  # app itself so it passes Gatekeeper offline, wherever it's copied.
  ditto -c -k --keepParent "$APP" "$STAGE/notarize.zip"
  notarize "$STAGE/notarize.zip"
  xcrun stapler staple "$APP"
fi

mkdir -p "$DEST"
echo "› Packaging…"
ditto -c -k --keepParent "$APP" "$DEST/$APP_NAME.zip"
if [[ "$MAKE_DMG" == 1 ]]; then
  DMG_OUT="$DEST/$APP_NAME-$VERSION.dmg"
  scripts/package-dmg.sh "$APP" "$DMG_OUT"
  if $NOTARIZE; then
    notarize "$DMG_OUT"
    xcrun stapler staple "$DMG_OUT"
  fi
fi

echo "› Archiving source…"
git archive --format=tar.gz --prefix="flyby-$VERSION/" -o "$DEST/source.tar.gz" HEAD
git rev-parse HEAD > "$DEST/COMMIT"
mv "$APP" "$DEST/"

INSTALLED="/Applications/$APP_NAME.app"
if [[ "${INSTALL:-1}" == 0 ]]; then
  echo "› Not installing (INSTALL=0)"
elif [[ -e "$INSTALLED" ]] && [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$INSTALLED/Contents/Info.plist" 2>/dev/null)" != "$BUNDLE_ID" ]]; then
  echo "› $INSTALLED isn't Flyby — leaving it alone"
elif pgrep -f "$INSTALLED/Contents/MacOS/" >/dev/null; then
  echo "› $INSTALLED is running — quit it, then: ditto \"$DEST/$APP_NAME.app\" \"$INSTALLED\""
else
  echo "› Installing to $INSTALLED"
  rm -rf "$INSTALLED"
  ditto "$DEST/$APP_NAME.app" "$INSTALLED"
fi

echo "✓ Released $VERSION → $DEST"
echo "  Next: ./publish.sh $VERSION notes.md"
