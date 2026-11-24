# Emi Key — spec

One macOS input method for English, Vietnamese and Mandarin with no switching.

## System integration
- Real macOS input method (InputMethodKit), installed to `~/Library/Input Methods/Emi Key.app`.
- Enabled once in System Settings → Keyboard → Input Sources; macOS starts it at login automatically.
- Lives in the top-right input menu with the C2 icon (three brush strokes, template image).
- Menu: two checkmark items only — Traditional Chinese, Old tone style (hòa). No windows; super light (no timers or polling, dictionaries load once).
- Direct insertion (like EVKey/OpenKey): the word being typed is real text, never underlined marked text. Each key becomes the smallest edit (replace only the changed tail); unchanged plain letters pass straight to the app. Apps that hide their text from input methods (cannot be edited in place) fall back to classic underlined marked text. Moving the cursor / clicking / switching app mid-word just forgets the word (the text stays).
- Works in every app (Terminal and code editors included). Secure fields are skipped by macOS.
  - Chromium/Electron: the first key after focusing a field may report no cursor (stay direct); a consumed Backspace still
    reaches the page (so Backspace edits are passed on, leaving one character for it); an inline-autocomplete selection
    after the cursor (address bar) does not end the word.
  - Terminal.app: its reported cursor/text drift from the screen → edits use Emi Key's own record of the cursor and of
    what it typed; Backspace/Esc go straight to the shell, a backward cursor jump ends the word.
  - Ghostty: ignores replacement ranges → an edit is sent as DEL × n + the new text (like typing it).
  - Apps whose cursor never moves (auto-detected, `UntrackedApps`) → marked text.
  - Marked text in terminals (`PtyApps`, Ghostty): Enter/Tab are sent together with the committed word (terminals drop a
    key that ends a composition).
  - After reinstalling Emi Key, Chrome/Electron apps and Ghostty that were already open must be relaunched once
    (they keep the dead connection to the old process).
- Offline. No network. Learned data in `~/Documents/Emi Key/` (learned.json).
- Signed with `Apple Development: emi2git@gmail.com (76UQD6DDM8)`. Bundle id `com.emi2git.inputmethod.EmiKey`.

## English
- Letters pass through as typed when no rule below applies.

## Vietnamese (Telex)
- Standard Telex: aa â, aw ă, ee ê, oo ô, ow ơ, uw/w ư, dd đ; s f r x j = sắc huyền hỏi ngã nặng; z removes tone; double tone key undoes it (`ass` → as).
- Tone placement: new style by default (`hoà`, `thuý`); old style (`hòa`, `thúy`) as a menu option.
- Tone/mark keys may come anywhere after the vowel (`vieetj`, `vietje`, `tieengs` all work).
- Transform only when the result is a valid Vietnamese syllable; otherwise keep the raw letters (`class`, `test`, `git` stay).
- Ambiguous words (valid English AND valid Vietnamese once transformed, e.g. `bus` → bú, `has` → há):
  decided by **context** = language of the last few words before the cursor
  (read via IMK client text; fall back to Emi Key's own record of recent words in this field).
  - Previous words Vietnamese (have diacritics / are Vietnamese-only) → Vietnamese.
  - Previous words English, or start of field → English.
- Esc right after a word flips it between the raw letters and the transformed version.

## Chinese (pinyin with tone numbers)
- Chinese is triggered only by a digit 0–5 right after a valid pinyin syllable (`ma3`, `nihao3`, `ni3hao`).
  - 1–4 = tones, 5 or 0 = neutral tone.
- Once a word has a tone digit, the whole word is Chinese until Space / punctuation / Enter.
  Untoned syllables match any tone (`xiao4yang2shangshan` keeps updating).
- Candidate bar: horizontal, numbered 1–9. Ranking = exact tone match first, then by frequency; closest matches (wrong tone) listed lower so typos still find 你好.
- A digit right after a tone digit picks that candidate (`ma3` then `1` → 马). Space picks the first candidate. Enter is always passed to the app; raw letters stay. Esc cancels to the raw letters.
- Digit not after a valid pinyin syllable, or > 5 → typed normally (`mp3`, `iphone15`, `2026`).
- Simplified by default; Traditional option in the menu.
- While composing, the raw pinyin (`ni3hao`) is plain text in the document; the candidate bar sits under its first letter; picking replaces it.

## Keys
- Enter is always the user's own Enter: the word stays as shown and the app gets Enter on the first press.
- Space never selects Chinese when there is no tone digit (plain `ma` stays English).

## Data (bundled, offline)
- Pinyin dictionary: CC-CEDICT (tones + traditional) with word frequency (jieba dict) — built by `scripts/build-data.py` into `Resources/pinyin.tsv`.
- English word list with frequency (for "is this a real English word") — `Resources/english.txt`.
- Vietnamese: syllable validator in code (no word list needed) + `Resources/vietnamese.txt` common words for context scoring (optional).

## Code layout
- `Sources/EmiKeyCore/` — pure Swift library, no AppKit: TelexEngine, VietSyllable, PinyinEngine, Dictionary, ContextDetector, Composer (the state machine taking key events → in-progress text / commit / candidates).
- `Sources/EmiKey/` — IMK app: InputController, CandidateWindow, menu, icon.
- `Tests/EmiKeyCoreTests/` — unit tests (`swift test`).
- `Tests/e2e/` — types real keystrokes into TextEdit, Chrome (page + address bar), Safari, Notes, Terminal, Ghostty with
  Emi Key selected and checks the text (`--app`, `--field`); leaves no windows, notes, files or settings behind.
- `build.sh` — build, sign, install to `~/Library/Input Methods`, restart the input method (skipped when the installed
  build is identical: a restart breaks already-open Chrome/Electron/Ghostty until relaunched).
- `scripts/uninstall.sh [--purge]` — disable, remove app + settings (+ learned words).
- Resilience: missing dictionaries → pure pass-through; unreadable learned.json → ignored and rewritten (atomic, ≤ 1000 words).
- Privacy: no network; nothing typed is logged unless `DebugLog` is set.
