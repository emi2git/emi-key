# Emi Key — maintainer notes

macOS input method (InputMethodKit): English + Vietnamese Telex + pinyin with tone digits, no switching. Direct
insertion (the word in progress is real text, no underline). Behaviour spec: [SPEC.md](SPEC.md). User docs:
[README.md](README.md). Open work: [TASKS.md](TASKS.md).

## Architecture
- `Sources/EmiKeyCore/` — pure Swift, no AppKit, fully unit-tested. Keys in → text out.
  - `Composer` — the per-key state machine (`handle(KeyInput, precedingText:)` → `ComposerOutput` commit/marked/
    candidates/handled + `lastDeleteCount` for the Esc flip). Decides English vs Vietnamese (`decide`) and Chinese.
  - `TelexEngine` + `VietSyllable` — Telex transform, only when the result is a valid syllable.
  - `ContextDetector` + `EnglishWords` — language of the words before the cursor; English word list with rank.
  - `PinyinEngine` — loads `Resources/pinyin.tsv` (~55 ms), segmentation + ranked candidates.
  - `ChromiumQuirks` — pure helpers for Chromium's focus blip / lagging selection (tested without an app).
- `Sources/EmiKey/` — the IMK app: `InputController` turns composer output into the smallest edit of the client
  text (`insertText(_:replacementRange:)`), falls back to marked text for apps that hide their text; per-app
  handling lives in `AppState` (`BlindApps`, `PtyApps`, `UntrackedApps`, `MarkedApps`). `InputSources` = `--install/--select/--disable`.
- Per-app quirks (Chromium, Terminal, Ghostty, WeChat, …) are documented in SPEC.md → System integration. Keep
  that list current when adding one. Known app behaviour that is not Emi Key: Notes autocorrects (đi → dì,
  viêt → việt) and capitalises — the user's Notes settings are left alone, so those 2 cases fail there.

## Data
`python3 -I scripts/build-data.py [download_dir]` rebuilds `Resources/pinyin.tsv` (CC-CEDICT + jieba frequencies)
and `Resources/english.txt` (frequency-ranked; the line number is the rank used by `EnglishLexicon.rank`).
Both are committed; the app runs offline.

## Build / test / install
```sh
swift test                 # unit tests (+ latency benchmark); must stay green
./build.sh                 # build, sign, install to ~/Library/Input Methods, enable + select (skips identical builds)
./build.sh --force         # reinstall even if unchanged
./build.sh --no-install    # only assemble build/Emi Key.app
scripts/uninstall.sh [--purge]
```
- Signing: `Apple Development: emi2git@gmail.com (76UQD6DDM8)`, bundle id `com.emi2git.inputmethod.EmiKey`.
- **Every reinstall disconnects already-open Chrome/Electron apps and Ghostty** (WeChat 4 and AppKit apps reconnect): they keep
  talking to the dead process and type plain letters until relaunched. Batch fixes; reinstall as rarely as
  possible; tell the user which apps to relaunch. `build.sh` never restarts the IME for an unchanged build.

## End-to-end tests
`swift Tests/e2e/e2e.swift --app <app> Tests/e2e/cases-full.txt` types real keys with Emi Key selected and checks
the text. Apps: textedit, chrome (isolated throw-away profile), safari, notes, terminal, ghostty (separate
instance), pages, numbers, keynote, xcode, spotlight, wechat; `chrome-user`/`ghostty-user` use the user's own
instance (avoid). `gdocs` is always skipped (Google Docs.app only opens docs.google.com; any doc is a Drive file).
Safety rules (built into the harness — keep them when changing it):
- Never type into the user's own windows. Keys go to the target pid only, and before every key the test window
  (WeChat: its search field) must be focused and no real key/click may have happened; otherwise it stops.
- A case starts only after 3 s without keyboard/mouse use (`--idle-timeout`, default 600 s, then it gives up).
- Leave no trail: only documents/windows the test created, closed without saving; temp files deleted; app
  settings (`defaults`), Open Recent lists, clipboard and input source restored. Pages/Numbers/Keynote/Xcode must
  not be running (the harness launches its own session and quits it). Keynote is driven without AppleScript
  (Automation access to it may be denied): ⌘N, Create, Tab/Return, read via ⌘A ⌘C (clipboard restored).
- Another agent or the user may be using the GUI: the harness waits and retries; never fight for focus.
- WeChat: only the main-window search field; never Enter, never a chat; cleared + Esc after each case; never
  launched or quit. If WeChat predates the installed Emi Key it may still talk to the old process (keys arrive
  untransformed): report it, do not quit the user's WeChat.
- The harness sets `KeyLog` (content-free per-key lines) and restores Emi Key's settings (it learns
  `UntrackedApps` while tested); after an aborted run check `defaults read com.emi2git.inputmethod.EmiKey`,
  Open Recent lists and iCloud `Untitled` documents by hand.
- When waiting for a background run, wait on its PID — never `pgrep -f` a pattern that is in your own command line.

## Privacy
No network code. Logs (`/usr/bin/log show --predicate 'subsystem == "com.emi2git.inputmethod.EmiKey"'`) never
contain typed text: per-key lines only with `KeyLog` and content-free; text only with `DebugLog` (debugging,
off by default — never leave it on). Learned flips: `~/Documents/Emi Key/learned.json`.
