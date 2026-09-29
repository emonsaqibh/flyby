#!/bin/bash
# The certificate releases are signed with, so people keep Flyby's Screen
# Recording, Accessibility and Input Monitoring grants from one update to the
# next — without a Developer ID. build.sh uses it for release builds, and
# release.sh won't release without it (or a Developer ID).
#
#   ./scripts/release-signing.sh           create it, on the Mac releases are
#                                          made on
#   ./scripts/release-signing.sh --remove  delete it
#
# It's what makes every future Flyby the same app to macOS: keep it, and back
# it up — Keychain Access › login › My Certificates › "Flyby Release Signing"
# › File › Export Items…, as a .p12 with a password. Lose it and the next
# release is a new app to macOS again, and everyone grants its permissions
# once more. To release from another Mac, import that .p12 there.
set -euo pipefail
# Twenty years: a signature that isn't timestamped is checked against today.
DAYS=7300 "$(dirname "$0")/signing-cert.sh" "Flyby Release Signing" "$@"
if [[ "${1:-}" != "--remove" ]]; then
  echo "  Back it up: Keychain Access › login › My Certificates › \"Flyby Release Signing\" › File › Export Items… (.p12)"
fi
