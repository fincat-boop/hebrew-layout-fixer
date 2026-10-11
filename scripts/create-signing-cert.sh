#!/bin/bash
# Creates a local self-signed code-signing identity in your login keychain.
#
# Why: build_app.sh otherwise signs ad-hoc, and an ad-hoc signature changes on
# every build — so macOS drops the Accessibility permission after each rebuild.
# With a stable identity the permission survives rebuilds. Run once; the
# identity never leaves this Mac. macOS will ask for your password to trust it.
set -euo pipefail

NAME="HebrewLayoutFixer Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl # LibreSSL: writes a .p12 that `security import` accepts

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "\"$NAME\" already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
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
CNF

echo "==> Creating certificate…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/identity.p12" -passout pass:temp

echo "==> Importing into the login keychain…"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P temp -T /usr/bin/codesign >/dev/null

echo "==> Trusting it for code signing (macOS will ask for your password)…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep "$NAME"
echo "Done. Run ./build_app.sh — from now on rebuilds keep the Accessibility permission."
