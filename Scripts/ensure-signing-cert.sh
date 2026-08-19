#!/bin/bash
# Ensure a stable local code-signing identity exists. Ad-hoc signatures have
# no persistent identity, so macOS re-prompts the Keychain grant for the
# Claude Code credentials item after every rebuild. A local self-signed cert
# gives Pace.app a stable identity: grant once, survives rebuilds.
# Nothing here enters the repo; the cert lives only in the login keychain.
set -euo pipefail

CERT_NAME="Pace Local Signing"

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "$CERT_NAME"
  exit 0
fi

echo "Creating local signing certificate '$CERT_NAME' (one-time)..." >&2
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/cert.conf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = codesign_ext
prompt = no
[ dn ]
CN = Pace Local Signing
[ codesign_ext ]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" \
  -config "$TMP_DIR/cert.conf" >/dev/null 2>&1
# SHA1 MAC + 3DES PBE explicitly: OpenSSL 3's default p12 encoding
# (AES/PBKDF2) fails macOS `security import` with "MAC verification failed".
openssl pkcs12 -export -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
  -out "$TMP_DIR/cert.p12" -passout pass:pace >/dev/null 2>&1
security import "$TMP_DIR/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P pace -T /usr/bin/codesign >/dev/null

# codesign refuses an identity whose chain reaches no trusted root, so a bare
# import is not enough — without trust settings the ad-hoc fallback would
# silently take over and the task's entire purpose (grant survives rebuilds)
# would be defeated while looking done. User-domain trust (no -d) so no admin
# password is needed; macOS may still show one interactive confirmation.
if ! security add-trusted-cert -r trustRoot -p codeSign \
     -k "$HOME/Library/Keychains/login.keychain-db" "$TMP_DIR/cert.pem" >/dev/null 2>&1; then
  echo "warning: could not set trust for '$CERT_NAME' (interactive confirmation declined or unavailable);" >&2
  echo "         codesign will fall back to ad-hoc — run 'make app' interactively once to fix." >&2
fi

echo "$CERT_NAME"
