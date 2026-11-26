# Emi Key

One macOS input method for English, Vietnamese (Telex) and Chinese (pinyin + tone numbers). No switching:
just type. Version 1.0.0. Details: [SPEC.md](SPEC.md).

## Typing

| You type | You get | Rule |
|---|---|---|
| `hello world` | hello world | English stays as typed |
| `tooi ddi hocj` | tôi đi học | Telex: `aa` â, `aw` ă, `ee` ê, `oo` ô, `ow` ơ, `uw`/`w` ư, `dd` đ |
| `vieetj`, `vietje` | việt | tones `s f r x j` (sắc huyền hỏi ngã nặng) anywhere after the vowel, `z` removes |
| `ass`, `class`, `git` | as, class, git | double key undoes; not a Vietnamese syllable → left alone |
| `test`, `rest`, `best` | test, rest, best | common English words with the tone key before a consonant stay English (`tets` → tét) |
| `thuowr` | thuở | `uow` is ươ, or uơ when nothing follows |
| `I take the bus` / `cho con bus` | bus / bú | English-or-Vietnamese words follow the words before them |
| `ma3` | candidate bar `1 马 2 码 …` | a tone digit 1–4 (5/0 = neutral) after pinyin starts Chinese |
| `ma3` `2` | 码 | a digit right after the tone digit picks; Space picks the first |
| `ni3hao`, `xiao4yang2shangshan` | 你好, 小羊上山 | untoned syllables match any tone |
| `xian1`, `qu4xian` | … 西安, 去西安 | a syllable that also splits into a common word (xi'an) offers that word too |
| `mp3`, `iphone15`, `2026` | mp3, iphone15, 2026 | digits after non-pinyin stay digits |

- **Esc** while typing a word flips it between raw letters and Vietnamese; right after a word it flips that word
  (`the bus ⎋` → the bú) where the app shows its text (not in WeChat). While composing Chinese, Esc keeps the raw
  pinyin. In terminals (Terminal, Ghostty) Esc always goes to the program (vim, the shell) and never flips.
- **Enter**, Tab, arrows and ⌘/⌃/⌥ shortcuts keep the word exactly as shown and always reach the app on the first press.
- The word being typed is underlined (classic input-method style) in every app; clicking, moving the cursor or
  switching apps mid-word keeps it as shown.

## Menu (input menu, C2 icon)

- **Traditional Chinese** — 馬 instead of 马.
- **Old tone style (hòa)** — hòa / thúy instead of hoà / thuý.

## Install

```sh
./build.sh            # build, sign, install to ~/Library/Input Methods, enable + select
./build.sh --force    # reinstall even if nothing changed
```

If the installed copy is already this build, `build.sh` does nothing (it never restarts Emi Key needlessly).

## Uninstall

```sh
scripts/uninstall.sh           # switch to your keyboard layout, disable, remove the app and settings
scripts/uninstall.sh --purge   # also delete learned words (~/Documents/Emi Key)
```

## Troubleshooting

- **After installing an update, quit and reopen Chrome, Electron apps (VS Code, Slack, …) and Ghostty.**
  They keep a connection to the old Emi Key process and type plain letters until relaunched.
- Plain letters everywhere: check that Emi Key is selected in the input menu; reinstall with `./build.sh --force`.
- Password fields: macOS turns input methods off there, so you type plain letters — that is expected.
- A terminal that loses the Enter after a word: `defaults write com.emi2git.inputmethod.EmiKey PtyApps -array-add <bundle id>`.

## Privacy

Everything runs offline; Emi Key has no network code. Nothing you type is logged. The only file it writes is
`~/Documents/Emi Key/learned.json`: the words you flipped with Esc and how often (at most 1000 words), used only
when there is no text around to tell the language.
`defaults write com.emi2git.inputmethod.EmiKey DebugLog -bool YES` logs per-key details **including what you type**
to the system log — for debugging only, off by default; `defaults delete com.emi2git.inputmethod.EmiKey DebugLog` to undo.

## Development

```sh
swift test                                                    # unit tests (+ per-key latency benchmark)
swift Tests/e2e/e2e.swift --app textedit Tests/e2e/cases-full.txt   # real keystrokes; see CLAUDE.md for all --app values
```

The e2e harness only types into windows it creates, waits until nobody uses the keyboard or mouse, stops when you
type or focus leaves, and cleans up after itself (documents, settings, Open Recent entries). Maintainer notes: [CLAUDE.md](CLAUDE.md).
It needs Accessibility + Automation permission for the terminal running it. Icons: `swift scripts/make-icons.swift`.
