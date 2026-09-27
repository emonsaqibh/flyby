#!/bin/bash
# Publishes a release made by ./release.sh:
#
#   ./publish.sh 0.3.0 notes.md
#
# - checks the release was built from the commit you're on,
# - tags it v<version> and pushes the tag,
# - creates the GitHub release with Flyby.zip attached (and the DMG, if
#   release.sh made one): a pre-release for x.y.z-suffix versions, the repo's
#   Latest release for a plain x.y.z.
#
# install.sh and the in-app updater both pick releases up from here. Needs the
# GitHub CLI (`brew install gh`, then `gh auth login`).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./publish.sh <version> <notes.md>}"
VERSION="${VERSION#v}"
NOTES="${2:?usage: ./publish.sh <version> <notes.md>}"
TAG="v$VERSION"
DEST="releases/$VERSION"
ZIP="$DEST/Flyby.zip"

command -v gh >/dev/null || { echo "✗ needs the GitHub CLI: brew install gh && gh auth login" >&2; exit 1; }
[[ -f "$ZIP" ]] || { echo "✗ no $ZIP — run ./release.sh $VERSION first" >&2; exit 1; }
[[ -f "$NOTES" ]] || { echo "✗ no notes file at $NOTES" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "✗ commit your changes first — the tag must match the release" >&2; exit 1; }
if [[ "$(cat "$DEST/COMMIT")" != "$(git rev-parse HEAD)" ]]; then
  echo "✗ $VERSION was built from $(cut -c1-7 "$DEST/COMMIT"), but HEAD is $(git rev-parse --short HEAD)" >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "✗ tag $TAG already exists — versions are never reused" >&2
  exit 1
fi

ASSETS=("$ZIP")
for dmg in "$DEST"/*.dmg; do
  if [[ -f "$dmg" ]]; then ASSETS+=("$dmg"); fi
done

echo "› Tagging $TAG"
git tag -a "$TAG" -m "Flyby $VERSION"
git push -q origin HEAD "$TAG"

# x.y.z-anything is a pre-release; a plain x.y.z becomes the repo's Latest.
case "$VERSION" in
  *-*) KIND=(--prerelease) ;;
  *)   KIND=(--latest) ;;
esac
echo "› Creating the GitHub release (${KIND[0]#--})"
gh release create "$TAG" "${ASSETS[@]}" --verify-tag "${KIND[@]}" \
  --title "Flyby $VERSION" --notes-file "$NOTES"

# A release without its zip breaks install.sh and the updater, and gh has been
# seen returning success with an asset missing — so look. Ask the assets
# endpoint: the list embedded in the release object can lag for minutes.
echo "› Checking Flyby.zip is attached"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
RID="$(gh api "repos/$REPO/releases/tags/$TAG" --jq .id)"
has_zip() { gh api "repos/$REPO/releases/$RID/assets" --jq '.[] | select(.state == "uploaded") | .name' | grep -qx 'Flyby.zip'; }
for _ in $(seq 1 12); do has_zip && break; sleep 5; done
if ! has_zip; then
  echo "› Flyby.zip missing — uploading it again"
  gh release upload "$TAG" "$ZIP" --clobber
  has_zip || { echo "✗ $TAG still has no Flyby.zip — fix it before announcing" >&2; exit 1; }
fi
echo "✓ Published Flyby $VERSION — https://github.com/$REPO/releases/tag/$TAG"
