#!/bin/zsh
set -euo pipefail
PROJECT_DIR=${0:A:h:h}
if pgrep -x Snap >/dev/null; then
    print -u2 'Quit Snap before installing an update.'
    exit 1
fi
"$PROJECT_DIR/scripts/build.sh"
if [[ -e /Applications/Snap.app ]]; then
    BACKUP_DIR="$HOME/Library/Application Support/Snap/Backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    mv /Applications/Snap.app "$BACKUP_DIR/Snap.app"
    print "Previous app saved to $BACKUP_DIR"
fi
ditto "$PROJECT_DIR/build/Snap.app" /Applications/Snap.app
codesign --verify --strict /Applications/Snap.app
print 'Installed /Applications/Snap.app'
