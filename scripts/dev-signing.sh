#!/bin/bash
# The certificate dev builds are signed with, once per Mac, so Flyby Dev keeps
# its Screen Recording, Accessibility and Input Monitoring grants across
# rebuilds. build.sh uses it for dev builds whenever it's in the keychain.
#
#   ./scripts/dev-signing.sh           create it
#   ./scripts/dev-signing.sh --remove  delete it
set -euo pipefail
exec "$(dirname "$0")/signing-cert.sh" "Flyby Dev Local Signing" "$@"
