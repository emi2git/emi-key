# Emi Key

One macOS input method for English, Vietnamese (Telex) and Chinese (pinyin + tone numbers) — no switching. See [SPEC.md](SPEC.md).

## Install

```sh
./build.sh
```

Builds a release, assembles `build/Emi Key.app`, signs it, installs it to `~/Library/Input Methods/Emi Key.app`,
restarts the old process and registers + enables + selects it (Carbon TIS, via `EmiKey --install`).
No System Settings visit needed; once enabled it stays in the input menu after a reboot.

`EmiKey --select` / `--disable` select or disable it from the command line.

## Use

- `ma3` → candidate bar `1 马 2 码 …`, `1`–`9` picks, Space takes the first, Enter keeps the letters (and is passed on), Esc cancels.
- `vieetj` → việt, `tooi ddi` → tôi đi; Esc right after a word flips raw ↔ Vietnamese.
- Everything else stays English.
- Typing is inserted directly (no underline while composing).
- Input menu: Traditional Chinese, Old tone style (hòa). That's all — no windows.
- Settings: defaults domain `com.emi2git.inputmethod.EmiKey`. Learned words: `~/Documents/Emi Key/learned.json`.

## Test

```sh
swift test                                   # engine unit tests
swift Tests/e2e/e2e.swift                    # real key events into TextEdit (pass-through cases)
swift Tests/e2e/e2e.swift Tests/e2e/cases-full.txt   # Telex / pinyin cases
```

The e2e harness needs Accessibility and Automation → TextEdit for the terminal running it.
`defaults write com.emi2git.inputmethod.EmiKey ForceHidden -bool YES` makes Emi Key treat every app as one that hides its
text (marked-text fallback) so the e2e cases cover that path too; `defaults delete … ForceHidden` to undo.

It waits until you stop typing, retries a case if you typed during it, and restores your input source.

## Icons

`swift scripts/make-icons.swift` regenerates `Resources/AppIcon.icns` and `Resources/MenuIconTemplate.tiff` (C2 brush strokes).
