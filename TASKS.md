# Emi Key — tasks

1. [x] Data + Pinyin engine (agent "pinyin"): scripts/build-data.py, Resources/pinyin.tsv, Resources/english.txt, PinyinEngine + EnglishWords, tests.
2. [x] Telex + context + Composer (agent "telex"): TelexEngine, VietSyllable, ContextDetector, Composer state machine, tests.
3. [x] IMK app shell (agent "app"): InputController, candidate window, menu, Settings, C2 icon, build.sh, install to ~/Library/Input Methods, e2e harness.
4. [x] Integrate, run all unit tests, e2e in TextEdit, Terminal, browser.
5. [x] Push to GitHub emi2git/emi-key (private), memory note.

## Round 2 — every app (2026-11-24, owner: Claude)
6. [x] e2e in Pages, Numbers, Keynote (blank doc, close without saving), Xcode (scratch file), Spotlight, Google Docs app (only if no Drive file is created). Fix bugs.
7. [x] WeChat: test only in its search box (never a chat), clear it after. Fix bugs.
8. [x] Known weaknesses: `test` → tét in Vietnamese context; `thuowr` → thưở; untoned `xian` misses 西安; Esc flip in terminals.
9. [x] Project CLAUDE.md for maintainers (architecture, build/test/install, app quirks, rules); README current.
10. [x] One final reinstall, all unit + e2e green, push; tell the user which apps to relaunch.
