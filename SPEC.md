# Emi Key — spec

One macOS input method for English, Vietnamese and Mandarin with no switching.

## System integration
- Real macOS input method (InputMethodKit), installed to `~/Library/Input Methods/Emi Key.app`.
- Enabled once in System Settings → Keyboard → Input Sources; macOS starts it at login automatically.
- Lives in the top-right input menu with the C2 icon (three brush strokes, template image).
- Menu: two checkmark items only — Traditional Chinese, Old tone style (hòa). No windows; super light (no timers or polling, dictionaries load once).
- Classic marked text in every app: the word being composed is underlined; it becomes plain text when committed.
  No per-app editing modes (direct insertion was dropped: it needed per-app hacks and still broke — see CLAUDE.md).
  - Space / punctuation commit the word (+ the key). Enter, Tab, arrows and ⌘/⌃/⌥ shortcuts commit the word exactly
    as shown and the app gets the key on the same, first press. Backspace edits the composition (empty = gone).
  - Clicking elsewhere, focus change, app switch: the composition is committed as shown.
  - Terminals (Terminal.app, Ghostty, `PtyApps`): they drop a key that ends a composition, so Enter/Tab/Esc are sent
    together with the committed word (`word\r`). An arrow key that ends a word may need a second press there.
  - Chromium deactivates and re-activates the input method right after the first key in a newly focused field (often
    on a new controller): that commits the word; on the next key (same app, < 0.5 s) it is taken back into the
    composition if it is still just before the cursor (`FocusBlip`), else it stays committed.
  - Context comes from the text before the composition, except in terminals (screen grid) and WeChat 4 (reports its
    placeholder): there Emi Key's own memory of the last words in the field is used.
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
- Transform only when the result is a valid Vietnamese syllable; otherwise keep the raw letters (`class`, `git` stay).
- `uow` gives ươ (người, được); with nothing after the o it is uơ (`thuowr` → thuở, `huow` → huơ), since open ươ does not exist.
- A common English word (top 5000) with a tone key before a consonant (`test` tét, `rest` rét, `best`, `corn`) stays
  English in any context — Telex typists put the tone last (`tets` → tét). Esc still flips it.
- Ambiguous words (valid English AND valid Vietnamese once transformed, e.g. `bus` → bú, `has` → há):
  decided by **context** = language of the last few words before the cursor
  (read via IMK client text; fall back to Emi Key's own record of recent words in this field).
  - Previous words Vietnamese (have diacritics / are Vietnamese-only) → Vietnamese.
  - Previous words English, or start of field → English.
- Esc while composing a word that Telex can transform toggles it: Vietnamese → raw letters, raw letters →
  Vietnamese (still composing; Space commits). Other words: Esc commits the raw letters and reaches the app.
- Esc right after a committed word (`the bus ⎋` → the bú) flips it — only when the app shows that word just before the
  cursor (it is replaced via its range). Otherwise (WeChat, text not readable, cursor moved, Chromium's lagging
  selection) Esc simply goes to the app. In terminals Esc always belongs to the program (vim, readline): the word is
  committed as shown and Esc is passed on.

## Chinese (pinyin with tone numbers)
- Chinese is triggered only by a digit 0–5 right after a valid pinyin syllable (`ma3`, `nihao3`, `ni3hao`).
  - 1–4 = tones, 5 or 0 = neutral tone.
- Once a word has a tone digit, the whole word is Chinese until Space / punctuation / Enter.
  Untoned syllables match any tone (`xiao4yang2shangshan` keeps updating).
- Candidate bar: horizontal, numbered 1–9. Ranking = exact tone match first, then by frequency; closest matches (wrong tone) listed lower so typos still find 你好.
  A syllable that also splits into a common word (`xian` = xi'an → 西安, `qu4xian` → 去西安) offers that word in the
  last whole-input slot.
- A digit right after a tone digit picks that candidate (`ma3` then `1` → 马). Space picks the first candidate. Enter is always passed to the app; raw letters stay. Esc cancels to the raw letters.
- Digit not after a valid pinyin syllable, or > 5 → typed normally (`mp3`, `iphone15`, `2026`).
- Simplified by default; Traditional option in the menu.
- While composing, the raw pinyin (`ni3hao`) is the underlined marked text; the candidate bar sits under its first letter; picking replaces it.

## Keys
- Enter is always the user's own Enter: the word stays as shown and the app gets Enter on the first press.
- Space never selects Chinese when there is no tone digit (plain `ma` stays English).

## Data (bundled, offline)
- Pinyin dictionary: CC-CEDICT (tones + traditional) with word frequency (jieba dict) — built by `scripts/build-data.py` into `Resources/pinyin.tsv`.
- English word list with frequency (for "is this a real English word") — `Resources/english.txt`.
- Vietnamese: syllable validator in code (no word list needed) + `Resources/vietnamese.txt` common words for context scoring (optional).

## Code layout
- `Sources/EmiKeyCore/` — pure Swift library, no AppKit: TelexEngine, VietSyllable, PinyinEngine, Dictionary, ContextDetector, Composer (the state machine taking key events → in-progress text / commit / candidates).
- `Sources/EmiKey/` — IMK app: InputController (marked text), CandidateWindow, menu, icon.
- `Tests/EmiKeyCoreTests/` — unit tests (`swift test`).
- `Tests/e2e/` — types real keystrokes into TextEdit, Chrome (page + address bar), Safari, Notes, Terminal, Ghostty,
  Pages, Numbers, Keynote, Xcode, Spotlight and WeChat's search field with Emi Key selected and checks the text
  (`--app`, `--field`); leaves no windows, notes, files, settings or Open Recent entries behind. See CLAUDE.md.
- `build.sh` — build, sign, install to `~/Library/Input Methods`, restart the input method (skipped when the installed
  build is identical: a restart breaks already-open Chrome/Electron/Ghostty until relaunched).
- `scripts/uninstall.sh [--purge]` — disable, remove app + settings (+ learned words).
- Resilience: missing dictionaries → pure pass-through; unreadable learned.json → ignored and rewritten (atomic, ≤ 1000 words).
- Privacy: no network; nothing typed is logged unless `DebugLog` is set.
