#!/bin/zsh
# Build Emi Key, sign it, install to ~/Library/Input Methods, and enable + select it.
#   ./build.sh                build + install (skipped when the installed copy is identical)
#   ./build.sh --force        reinstall + restart even when nothing changed
#   ./build.sh --no-install   only assemble build/Emi Key.app
# Restarting the input method breaks the connection of apps that are already open (Chrome, Electron apps,
# Ghostty): they type plain letters until relaunched. So an unchanged build never restarts it.
set -euo pipefail
cd "${0:A:h}"

NAME="Emi Key"
EXE=EmiKey
IDENTITY="Apple Development: emi2git@gmail.com (76UQD6DDM8)"
APP="build/$NAME.app"
DEST="$HOME/Library/Input Methods/$NAME.app"
MODE="${1:-}"

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

# Fingerprint of everything that changes behaviour (unsigned binary, plist, resources) — the signature itself
# differs on every signing, so it cannot be compared.
STAMP=$(cd "$APP/Contents" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum | shasum | cut -c1-40)
echo "$STAMP" > "$APP/Contents/Resources/BuildStamp"
# Build number = commit count (not part of the fingerprint: a docs-only commit needs no reinstall).
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "built $APP ($VERSION build $BUILD)"

[[ "$MODE" == "--no-install" ]] && exit 0

if [[ "$MODE" != "--force" && -f "$DEST/Contents/Resources/BuildStamp" ]] &&
   [[ "$(cat "$DEST/Contents/Resources/BuildStamp")" == "$STAMP" ]]; then
  echo "unchanged: $DEST is already this build — not restarting (open apps keep working)"
  exit 0
fi

pkill -x "$EXE" 2>/dev/null || true
mkdir -p "${DEST:h}"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "installed $DEST"

# Register + enable + select via Carbon TIS (no System Settings needed; persists across reboots).
"$DEST/Contents/MacOS/$EXE" --install
echo "note: Chrome / Electron apps and Ghostty that were already open keep talking to the old Emi Key process —"
echo "      quit and reopen them once."
