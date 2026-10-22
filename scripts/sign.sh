#!/bin/zsh
set -euo pipefail
umask 077

SNAP_APP=${1:?Usage: scripts/sign.sh path/to/Snap.app}
SNAP_SIGNING_DIR="$HOME/Library/Application Support/Snap/Signing"
SNAP_IDENTITY_FILE="$SNAP_SIGNING_DIR/identity.sha1"

if [[ -n ${SNAP_SIGNING_IDENTITY:-} ]]; then
    if [[ "$SNAP_SIGNING_IDENTITY" == - ]]; then
        print -u2 'Ad hoc signing resets Screen Recording approval. Choose a certificate identity.'
        exit 1
    fi
    codesign --force --sign "$SNAP_SIGNING_IDENTITY" --identifier dev.matthew.snap "$SNAP_APP"
else
    if [[ ! -f "$SNAP_IDENTITY_FILE" ]]; then
        SNAP_SIGNING_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/snap-signing.XXXXXX")
        trap 'rm -rf -- "$SNAP_SIGNING_TEMP"' EXIT
        cat > "$SNAP_SIGNING_TEMP/openssl.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = codesign
[subject]
CN = Snap Local Development (dev.matthew.snap)
[codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
CONFIG
        if ! /usr/bin/openssl req -new -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
            -config "$SNAP_SIGNING_TEMP/openssl.cnf" -keyout "$SNAP_SIGNING_TEMP/key.pem" \
            -out "$SNAP_SIGNING_TEMP/cert.pem" 2> "$SNAP_SIGNING_TEMP/openssl.log"; then
            cat "$SNAP_SIGNING_TEMP/openssl.log" >&2
            exit 1
        fi
        /usr/bin/openssl rand -hex 24 > "$SNAP_SIGNING_TEMP/password"
        # Use the PKCS#12 encoding supported by the macOS Keychain importer.
        /usr/bin/openssl pkcs12 -export -inkey "$SNAP_SIGNING_TEMP/key.pem" \
            -in "$SNAP_SIGNING_TEMP/cert.pem" -name 'Snap Local Development (dev.matthew.snap)' \
            -out "$SNAP_SIGNING_TEMP/identity.p12" -macalg sha1 \
            -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES \
            -passout "file:$SNAP_SIGNING_TEMP/password"
        /usr/bin/security import "$SNAP_SIGNING_TEMP/identity.p12" \
            -k "$HOME/Library/Keychains/login.keychain-db" \
            -P "$(<"$SNAP_SIGNING_TEMP/password")" -x -T /usr/bin/codesign
        SNAP_FINGERPRINT=$(/usr/bin/openssl x509 -in "$SNAP_SIGNING_TEMP/cert.pem" \
            -noout -fingerprint -sha1)
        SNAP_FINGERPRINT=${SNAP_FINGERPRINT#*=}
        SNAP_FINGERPRINT=${SNAP_FINGERPRINT//:/}
        mkdir -p "$SNAP_SIGNING_DIR"
        print -r -- "$SNAP_FINGERPRINT" > "$SNAP_IDENTITY_FILE"
        print 'Created Snap’s persistent local signing identity in the login Keychain.'
    fi

    SNAP_FINGERPRINT=$(<"$SNAP_IDENTITY_FILE")
    if [[ ${#SNAP_FINGERPRINT} != 40 || "$SNAP_FINGERPRINT" == *[^[:xdigit:]]* ]]; then
        print -u2 "Invalid signing fingerprint in $SNAP_IDENTITY_FILE"
        exit 1
    fi
    # Pin both the app identifier and certificate, never a mutable build hash.
    # Reuse the original key; a missing key must fail rather than silently change identity.
    codesign --force --sign "$SNAP_FINGERPRINT" --identifier dev.matthew.snap \
        --requirements "=designated => identifier \"dev.matthew.snap\" and certificate leaf = H\"$SNAP_FINGERPRINT\"" \
        --timestamp=none "$SNAP_APP"
fi

codesign --verify --strict "$SNAP_APP"
