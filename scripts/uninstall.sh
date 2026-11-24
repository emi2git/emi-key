#!/bin/zsh
# Uninstall Emi Key.
#   scripts/uninstall.sh           switch to a normal keyboard, disable Emi Key, remove the app and its settings
#   scripts/uninstall.sh --purge   also delete learned words (~/Documents/Emi Key)
set -uo pipefail

NAME="Emi Key"
EXE=EmiKey
ID=com.emi2git.inputmethod.EmiKey
DEST="$HOME/Library/Input Methods/$NAME.app"
DATA="$HOME/Documents/$NAME"

if [[ -x "$DEST/Contents/MacOS/$EXE" ]]; then
  "$DEST/Contents/MacOS/$EXE" --disable || true
fi
pkill -x "$EXE" 2>/dev/null || true
rm -rf "$DEST" && echo "removed $DEST"
defaults delete "$ID" 2>/dev/null && echo "removed settings ($ID)"
if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "$DATA" && echo "removed $DATA"
else
  [[ -d "$DATA" ]] && echo "kept learned words in $DATA (--purge deletes them)"
fi
echo "done. Emi Key may stay listed in System Settings → Keyboard → Input Sources until you log out."
