#!/bin/zsh
# Creates a self-signed "Nova Local" code-signing identity in your login
# keychain, once. Builds signed with it keep the same identity across
# rebuilds, so macOS stops asking for Keychain access after every build.
#
# It adds exactly one certificate + private key to the login keychain and
# touches nothing else. Run it again any time: it does nothing if the
# identity already exists. Remove it in Keychain Access (search "Nova Local").
set -euo pipefail

NAME="Nova Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
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

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" >/dev/null 2>&1
PASS=$(openssl rand -hex 16)
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/nova.p12" -passout "pass:$PASS" >/dev/null 2>&1 \
  || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/nova.p12" -passout "pass:$PASS" >/dev/null 2>&1

# Only codesign may use the private key without asking.
security import "$WORK/nova.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\". Builds from scripts/build_app.sh now sign with it."
