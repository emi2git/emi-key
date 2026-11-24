# Emi Key — spec

One macOS input method for English, Vietnamese and Mandarin with no switching.

## System integration
- Real macOS input method (InputMethodKit), installed to `~/Library/Input Methods/Emi Key.app`.
- Enabled once in System Settings → Keyboard → Input Sources; macOS starts it at login automatically.
- Lives in the top-right input menu with the C2 icon (three brush strokes, template image).
- Menu: Settings…, Traditional Chinese on/off, Help, About.
- Works in every app (Terminal and code editors included). Secure fields are skipped by macOS.
- Offline. No network. Learned data in `~/Documents/Emi Key/` (learned.json).
- Signed with `Apple Development: emi2git@gmail.com (76UQD6DDM8)`. Bundle id `com.emi2git.inputmethod.EmiKey`.

## English
- Letters pass through as typed when no rule below applies.

## Vietnamese (Telex)
- Standard Telex: aa â, aw ă, ee ê, oo ô, ow ơ, uw/w ư, dd đ; s f r x j = sắc huyền hỏi ngã nặng; z removes tone; double tone key undoes it (`ass` → as).
- Tone placement: new style by default (`hoà`, `thuý`); old style (`hòa`, `thúy`) as a Settings option.
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
- A digit right after a tone digit picks that candidate (`ma3` then `1` → 马). Space picks the first candidate. Enter commits the raw letters. Esc cancels to the raw letters.
- Digit not after a valid pinyin syllable, or > 5 → typed normally (`mp3`, `iphone15`, `2026`).
- Simplified by default; Traditional option in Settings/menu.
- Space never selects Chinese when there is no tone digit (plain `ma` stays English).

## Data (bundled, offline)
- Pinyin dictionary: CC-CEDICT (tones + traditional) with word frequency (jieba dict) — built by `scripts/build-data.py` into `Resources/pinyin.tsv`.
- English word list with frequency (for "is this a real English word") — `Resources/english.txt`.
- Vietnamese: syllable validator in code (no word list needed) + `Resources/vietnamese.txt` common words for context scoring (optional).

## Code layout
- `Sources/EmiKeyCore/` — pure Swift library, no AppKit: TelexEngine, VietSyllable, PinyinEngine, Dictionary, ContextDetector, Composer (the state machine taking key events → marked text / commit / candidates).
- `Sources/EmiKey/` — IMK app: InputController, CandidateWindow, Settings, menu, icon.
- `Tests/EmiKeyCoreTests/` — unit tests (`swift test`).
- `Tests/e2e/` — types real keystrokes into TextEdit with Emi Key selected and checks the text.
- `build.sh` — build, sign, install to `~/Library/Input Methods`, restart the input method.
