#!/bin/zsh
set -euo pipefail
SNAP_ROOT=${0:A:h:h}
SNAP_SOURCE_APP=${1:-"$SNAP_ROOT/build/Snap.app"}
SNAP_CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/snap-signing-check.XXXXXX")
trap 'rm -rf -- "$SNAP_CHECK_DIR"' EXIT

for SNAP_VARIANT in first second; do
    ditto "$SNAP_SOURCE_APP" "$SNAP_CHECK_DIR/$SNAP_VARIANT.app"
    mkdir -p "$SNAP_CHECK_DIR/$SNAP_VARIANT.app/Contents/Resources"
    print -r -- "$SNAP_VARIANT" > "$SNAP_CHECK_DIR/$SNAP_VARIANT.app/Contents/Resources/signing-check.txt"
    "$SNAP_ROOT/scripts/sign.sh" "$SNAP_CHECK_DIR/$SNAP_VARIANT.app"
done

SNAP_REQUIREMENT=$(codesign --display -r- "$SNAP_CHECK_DIR/first.app" 2>/dev/null)
SNAP_REQUIREMENT=${SNAP_REQUIREMENT#*designated => }
SNAP_FIRST_HASH=$(codesign --display -vvvv "$SNAP_CHECK_DIR/first.app" 2>&1 | sed -n 's/^CDHash=//p')
SNAP_SECOND_HASH=$(codesign --display -vvvv "$SNAP_CHECK_DIR/second.app" 2>&1 | sed -n 's/^CDHash=//p')
if [[ -z "$SNAP_FIRST_HASH" || "$SNAP_FIRST_HASH" == "$SNAP_SECOND_HASH" ]]; then
    print -u2 'Expected different code hashes for the two app payloads.'
    exit 1
fi
codesign --verify --strict --test-requirement "=$SNAP_REQUIREMENT" "$SNAP_CHECK_DIR/second.app"

ditto "$SNAP_CHECK_DIR/second.app" "$SNAP_CHECK_DIR/adhoc.app"
codesign --force --sign - --identifier dev.matthew.snap "$SNAP_CHECK_DIR/adhoc.app"
if codesign --verify --strict --test-requirement "=$SNAP_REQUIREMENT" "$SNAP_CHECK_DIR/adhoc.app" 2>/dev/null; then
    print -u2 'An app signed by another identity unexpectedly passed.'
    exit 1
fi

print 'tampered' > "$SNAP_CHECK_DIR/second.app/Contents/Resources/signing-check.txt"
if codesign --verify --strict "$SNAP_CHECK_DIR/second.app" 2>/dev/null; then
    print -u2 'A modified app unexpectedly passed signature validation.'
    exit 1
fi
print 'Verified: different builds share an identity; ad hoc and modified apps are rejected.'
