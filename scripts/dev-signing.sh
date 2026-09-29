#!/bin/bash
# Makes a local code-signing certificate for Flyby Dev, once per Mac.
#
# An ad-hoc signature changes with every build, and macOS keys the privacy
# grants Flyby Dev needs — Screen Recording, Accessibility, Full Disk Access —
# to the signature, so every rebuild used to lose them all. Signed with this
# certificate instead, each build is the same app to macOS and the grants
# stay. build.sh uses it for dev builds whenever it's in the keychain; release
# builds and CI never see it.
#
#   ./scripts/dev-signing.sh           create it (asks for your password once,
#                                      to trust it for code signing)
#   ./scripts/dev-signing.sh --remove  delete it again
#
# It's self-signed and trusted only for code signing, only in your login
# keychain. Nothing outside this Mac trusts it.
set -euo pipefail

NAME="Flyby Dev Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [[ "${1:-}" == "--remove" ]]; then
  while security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; do
    security delete-identity -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1 \
      || security delete-certificate -c "$NAME" "$KEYCHAIN"
  done
  echo "✓ Removed \"$NAME\""
  exit 0
fi

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ \"$NAME\" is already in the login keychain"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# The system LibreSSL writes a PKCS#12 the keychain can import as is.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -config "$WORK/cert.conf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" -out "$WORK/identity.p12"

# codesign may use the key without asking each time.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "› Imported \"$NAME\". macOS will ask for your password to trust it for code signing…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

security find-identity -v -p codesigning | grep -q "$NAME" \
  || { echo "✗ \"$NAME\" isn't a valid code-signing identity" >&2; exit 1; }
echo "✓ \"$NAME\" is ready; ./build.sh signs Flyby Dev with it from now on"
