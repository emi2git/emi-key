#!/bin/zsh
# Build Emi Key, sign it, install to ~/Library/Input Methods, restart it, and enable + select it.
#   ./build.sh            build + install + enable
#   ./build.sh --no-install   only assemble build/Emi Key.app
set -euo pipefail
cd "${0:A:h}"

NAME="Emi Key"
EXE=EmiKey
IDENTITY="Apple Development: emi2git@gmail.com (76UQD6DDM8)"
APP="build/$NAME.app"
DEST="$HOME/Library/Input Methods/$NAME.app"

swift build -c release --product "$EXE"
BIN="$(swift build -c release --show-bin-path)/$EXE"

[[ -f Resources/AppIcon.icns && -f Resources/MenuIconTemplate.tiff ]] || swift scripts/make-icons.swift

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp Resources/AppIcon.icns Resources/MenuIconTemplate.tiff "$APP/Contents/Resources/"
for f in pinyin.tsv english.txt vietnamese.txt; do
  [[ -f "Resources/$f" ]] && cp "Resources/$f" "$APP/Contents/Resources/"
done

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "built $APP"

[[ "${1:-}" == "--no-install" ]] && exit 0

pkill -x "$EXE" 2>/dev/null || true
mkdir -p "${DEST:h}"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "installed $DEST"

# Register + enable + select via Carbon TIS (no System Settings needed; persists across reboots).
"$DEST/Contents/MacOS/$EXE" --install
echo "note: Chrome / Electron apps that were open keep talking to the old Emi Key process — quit and reopen them."
echo "note: Chrome / Electron apps and Ghostty that were open keep talking to the old Emi Key process — quit and reopen them."
