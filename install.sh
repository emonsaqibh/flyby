#!/bin/bash
# Installs Flyby into /Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/emonsaqibh/flyby/main/install.sh | bash
#   … | bash -s -- --beta       the newest release, betas included
#   … | bash -s -- 0.3.0        a specific version
#
# Why a script rather than a download link: until releases are notarized, macOS
# refuses to open an app downloaded in a browser. Files fetched with curl aren't
# marked as downloads, so the app opens normally. After this, Flyby tells you
# when there's an update and hands you this same command.
set -euo pipefail

REPO="emonsaqibh/flyby"
APP_NAME="Flyby"
BUNDLE_ID="com.fringecore.flyby"

say()  { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "Flyby is a Mac app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$major" -ge 14 ]] || fail "Flyby needs macOS 14 or later (you have $(sw_vers -productVersion))."

WANT="${1:-}"
BETA=0
case "$WANT" in
  --beta) BETA=1; WANT="" ;;
  -*)     fail "unknown option $WANT (use --beta or a version like 0.3.0)" ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -n "$WANT" ]]; then
  API="https://api.github.com/repos/$REPO/releases/tags/v${WANT#v}"
else
  API="https://api.github.com/repos/$REPO/releases?per_page=30"
fi
curl -fsSL -H 'Accept: application/vnd.github+json' "$API" -o "$TMP/releases.json" \
  || fail "couldn't reach GitHub ($API)"

# Pick the release with JavaScript for Automation, which every Mac has, rather
# than assuming python or jq. Only real version tags count — the legacy
# "Golden" and "beta" releases are skipped — and only releases carrying
# Flyby.zip. Prints "<tag> <zip url>".
PICK="$(osascript -l JavaScript - "$TMP/releases.json" "$BETA" <<'JXA'
ObjC.import('Foundation');
function run(argv) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
  let releases = JSON.parse(text);
  if (!Array.isArray(releases)) releases = [releases];
  const allowBeta = argv[1] === '1';
  const re = /^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$/;
  const parse = tag => {
    const m = re.exec(tag || '');
    return m ? { core: [+m[1], +m[2], +m[3]], pre: m[4] ? m[4].split('.') : [] } : null;
  };
  const cmp = (a, b) => {
    for (let i = 0; i < 3; i++) if (a.core[i] !== b.core[i]) return a.core[i] - b.core[i];
    if (!a.pre.length || !b.pre.length) return b.pre.length - a.pre.length;
    for (let i = 0; i < Math.min(a.pre.length, b.pre.length); i++) {
      const x = a.pre[i], y = b.pre[i];
      if (x === y) continue;
      const nx = /^\d+$/.test(x), ny = /^\d+$/.test(y);
      if (nx && ny) return (+x) - (+y);
      if (nx !== ny) return nx ? -1 : 1;
      return x < y ? -1 : 1;
    }
    return a.pre.length - b.pre.length;
  };
  const candidates = releases
    .filter(r => !r.draft)
    .map(r => ({ r, v: parse(r.tag_name) }))
    .filter(c => c.v && (allowBeta || c.v.pre.length === 0 || releases.length === 1))
    .map(c => ({ ...c, zip: (c.r.assets || []).find(a => a.name === 'Flyby.zip') }))
    .filter(c => c.zip)
    .sort((a, b) => cmp(b.v, a.v));
  return candidates.length ? candidates[0].r.tag_name + ' ' + candidates[0].zip.browser_download_url : '';
}
JXA
)" || PICK=""
[[ -n "$PICK" ]] || fail "no installable Flyby release found${WANT:+ for $WANT}"
TAG="${PICK%% *}"
URL="${PICK#* }"

say "Downloading $APP_NAME ${TAG#v}…"
curl -fL --progress-bar "$URL" -o "$TMP/Flyby.zip" || fail "couldn't download $URL"
ditto -x -k "$TMP/Flyby.zip" "$TMP/unzipped"
APP="$TMP/unzipped/$APP_NAME.app"
[[ -d "$APP" ]] || fail "the download didn't contain $APP_NAME.app"
codesign --verify --deep --strict "$APP" 2>/dev/null || fail "the downloaded app failed its signature check"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" == "$BUNDLE_ID" ]] \
  || fail "the download isn't Flyby ($BUNDLE_ID)"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# /Applications is where permissions and open-at-login expect it; fall back to
# ~/Applications for a standard (non-admin) account that can't write there.
DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi
TARGET="$DEST/$APP_NAME.app"

if [[ -e "$TARGET" ]]; then
  existing="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$existing" == "$BUNDLE_ID" ]] || fail "$TARGET exists and isn't Flyby — move it aside first"
fi
if pgrep -f "$TARGET/Contents/MacOS/" >/dev/null; then
  say "Quitting the running copy…"
  pkill -f "$TARGET/Contents/MacOS/" 2>/dev/null || true
  for _ in $(seq 1 25); do pgrep -f "$TARGET/Contents/MacOS/" >/dev/null || break; sleep 0.2; done
fi

say "Installing to ${DEST}…"
rm -rf "$TARGET"
ditto "$APP" "$TARGET"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TARGET/Contents/Info.plist")"

[[ "${NO_OPEN:-}" == 1 ]] || open "$TARGET"
say "Installed $APP_NAME $version. Look for it in the menu bar — it'll tell you when there's an update."
