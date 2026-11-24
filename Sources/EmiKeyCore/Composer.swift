import Foundation

/// Key-by-key state machine: raw keys → marked text / commits / Chinese candidates.
///
/// One Composer per text field (call `flush()` on focus change).
public final class Composer {
    public var settings: ComposerSettings

    /// **Delete contract.** After every `handle(_:precedingText:)`, `pick(_:)` and `flush()` call, the app must
    /// first delete `lastDeleteCount` characters (Swift `Character`s / grapheme clusters) immediately before the
    /// cursor, and only then insert `commit`. It is 0 for every call except Esc right after a committed word,
    /// which flips that word: it deletes "word + separator" and `commit` holds the flipped word + the same separator.
    /// Same amount in UTF-16 units: `lastDeleteUTF16Count` (for NSRange-based replacement).
    public private(set) var lastDeleteCount = 0
    public private(set) var lastDeleteUTF16Count = 0

    private let telex: TelexTransforming
    private let pinyin: PinyinLookup
    private let english: EnglishLexicon
    private let detector: ContextDetector
    private let learnedFile: URL?

    private var buffer = ""            // raw keys of the word being composed
    private var chinese = false        // word has a tone digit
    private var override: Lang?        // Esc flip while composing (.vi / .en)
    private var cands: [PinyinCandidate] = []
    private var memory: [String] = []  // last committed words in this field (context fallback)
    private var preceding: String?
    /// Last committed word that Esc may flip (only valid for the very next key).
    private var flippable: (shown: String, other: String, raw: String, sep: String)?
    /// raw word (lowercased) → ["vi": n, "en": n] flip counts.
    private var learned: [String: [String: Int]] = [:]

    public init(telex: TelexTransforming, pinyin: PinyinLookup, english: EnglishLexicon, settings: ComposerSettings, learnedFile: URL?) {
        self.telex = telex; self.pinyin = pinyin; self.english = english
        self.settings = settings; self.learnedFile = learnedFile
        self.detector = ContextDetector(english: english)
        if let url = learnedFile, let data = try? Data(contentsOf: url),
           let d = try? JSONDecoder().decode([String: [String: Int]].self, from: data) { learned = d }
    }

    /// precedingText: text before the cursor in the client, excluding the marked text (nil if the app hides it).
    public func handle(_ key: KeyInput, precedingText: String?) -> ComposerOutput {
        lastDeleteCount = 0; lastDeleteUTF16Count = 0
        preceding = precedingText
        let flip = flippable
        flippable = nil

        switch key {
        case .char(let c):
            if c.isASCII && c.isLetter {
                buffer.append(c)
                return composing()
            }
            if let d = c.wholeNumberValue, c.isASCII { return digit(c, d) }
            if buffer.isEmpty { return ComposerOutput(commit: String(c)) }
            if chinese { return commitChinese(suffix: String(c)) }
            return commitLatin(sep: String(c))

        case .space:
            if buffer.isEmpty { return ComposerOutput(handled: false) }
            if chinese {
                if !cands.isEmpty { return pickCandidate(0) }
                return finish(commit: buffer + " ")
            }
            return commitLatin(sep: " ")

        case .enter:
            if buffer.isEmpty { return ComposerOutput(handled: false) }
            if chinese { return finish(commit: buffer) }
            var o = commitLatin(sep: "")
            flippable = nil
            o.handled = false
            return o

        case .escape:
            if buffer.isEmpty {
                guard let f = flip else { return ComposerOutput(handled: false) }
                let old = f.shown + f.sep
                lastDeleteCount = old.count; lastDeleteUTF16Count = old.utf16.count
                record(f.raw, toVietnamese: f.other != f.raw)
                if !memory.isEmpty { memory[memory.count - 1] = f.other }
                flippable = (f.other, f.shown, f.raw, f.sep)
                return ComposerOutput(commit: f.other + f.sep)
            }
            if chinese { return finish(commit: buffer) }
            guard telex.transform(buffer, style: settings.toneStyle) != nil else {
                var o = finish(commit: buffer); o.handled = false; return o
            }
            let nowVi = decide(buffer).isVi
            override = nowVi ? .en : .vi
            record(buffer, toVietnamese: !nowVi)
            return composing()

        case .backspace:
            if buffer.isEmpty { return ComposerOutput(handled: false) }
            buffer.removeLast()
            if buffer.isEmpty { return finish(commit: "") }
            if chinese && !buffer.contains(where: { $0.isNumber }) { chinese = false }
            return composing()

        case .tab, .other:
            if buffer.isEmpty { return ComposerOutput(handled: false) }
            var o = chinese ? finish(commit: buffer) : commitLatin(sep: "")
            flippable = nil
            o.handled = false
            return o
        }
    }

    /// Pick candidate index (0-based) by mouse click in the candidate bar.
    public func pick(_ index: Int) -> ComposerOutput {
        lastDeleteCount = 0; lastDeleteUTF16Count = 0
        flippable = nil
        guard chinese else { return composing() }
        return pickCandidate(index)
    }

    /// Focus lost / app switched: returns text to commit, clears state and the field's word memory.
    public func flush() -> String {
        lastDeleteCount = 0; lastDeleteUTF16Count = 0
        let text: String
        if buffer.isEmpty { text = "" }
        else if chinese { text = buffer }
        else { text = decide(buffer).text }
        reset()
        memory.removeAll(); flippable = nil; preceding = nil
        return text
    }

    // MARK: - Digits / Chinese

    private func digit(_ c: Character, _ d: Int) -> ComposerOutput {
        if buffer.isEmpty { return ComposerOutput(commit: String(c)) }
        let prevIsDigit = buffer.last!.isNumber
        if chinese {
            if prevIsDigit {
                if d >= 1, d - 1 < cands.count { return pickCandidate(d - 1) }
                return composing()   // no such candidate: ignore
            }
            if d <= 5 { buffer.append(c) }
            return composing()
        }
        // Latin word: a tone digit only right after a letter run that is valid pinyin (whole word, no digits yet).
        if d <= 5, !prevIsDigit, !buffer.contains(where: { $0.isNumber }),
           pinyin.segmentsAsPinyin(buffer.lowercased()) {
            chinese = true
            override = nil
            buffer.append(c)
            return composing()
        }
        buffer.append(c)
        return composing()
    }

    private func refreshCandidates() {
        cands = chinese ? pinyin.candidates(for: buffer.lowercased(), traditional: settings.traditional, limit: 9) : []
    }

    private func pickCandidate(_ i: Int) -> ComposerOutput {
        guard i >= 0, i < cands.count else { return composing() }
        let c = cands[i]
        remember(c.text)
        if c.consumed <= 0 || c.consumed >= buffer.count { return finish(commit: c.text) }
        buffer = String(buffer.dropFirst(c.consumed))
        var o = composing()
        o.commit = c.text
        return o
    }

    private func commitChinese(suffix: String) -> ComposerOutput {
        guard let c = cands.first else { return finish(commit: buffer + suffix) }
        remember(c.text)
        let rest = c.consumed > 0 && c.consumed < buffer.count ? String(buffer.dropFirst(c.consumed)) : ""
        return finish(commit: c.text + rest + suffix)
    }

    // MARK: - Latin / Vietnamese

    private func commitLatin(sep: String) -> ComposerOutput {
        let raw = buffer
        let d = decide(raw)
        remember(d.text)
        if let v = d.viet, v != raw { flippable = (d.text, d.isVi ? raw : v, raw, sep) }
        let o = finish(commit: d.text + sep)
        return o
    }

    /// Final choice for a Latin word. `viet` = valid Telex transform (nil if none).
    private func decide(_ raw: String) -> (text: String, viet: String?, isVi: Bool) {
        guard let t = telex.transform(raw, style: settings.toneStyle) else { return (raw, nil, false) }
        if let o = override { return o == .vi ? (t, t, true) : (raw, t, false) }
        if english.isWord(raw) {
            if t.allSatisfy({ $0.isASCII }) { return (raw, t, false) }   // only an undo happened (`less` → les)
            switch context() {
            case .vi?: return (t, t, true)
            case .en?, .zh?: return (raw, t, false)
            case nil: return learnedPrefersVi(raw) ? (t, t, true) : (raw, t, false)
            }
        }
        return (t, t, true)
    }

    private func context() -> Lang? {
        if let p = preceding, let l = detector.detect(p) { return l }
        return detector.detect(memory.joined(separator: " "))
    }

    private func composing() -> ComposerOutput {
        refreshCandidates()
        if buffer.isEmpty { return ComposerOutput() }
        if chinese { return ComposerOutput(marked: buffer, candidates: cands.map(\.text)) }
        let d = decide(buffer)
        var shown = d.text
        // Incomplete Vietnamese syllable (e.g. "vieet" before its tone) in a Vietnamese context: show the preview.
        if d.viet == nil, override != .en, !english.isWord(buffer), context() == .vi,
           let engine = telex as? TelexEngine, let p = engine.preview(buffer, style: settings.toneStyle) {
            shown = p
        }
        return ComposerOutput(marked: shown)
    }

    private func finish(commit: String) -> ComposerOutput {
        reset()
        return ComposerOutput(commit: commit)
    }

    private func reset() { buffer = ""; chinese = false; override = nil; cands = [] }

    private func remember(_ w: String) {
        memory.append(w)
        if memory.count > 10 { memory.removeFirst(memory.count - 10) }
    }

    // MARK: - Learned flips (used only when context is unknown)

    private func learnedPrefersVi(_ raw: String) -> Bool {
        let c = learned[raw.lowercased()] ?? [:]
        return (c["vi"] ?? 0) - (c["en"] ?? 0) >= 2
    }

    private func record(_ raw: String, toVietnamese: Bool) {
        let k = raw.lowercased()
        learned[k, default: [:]][toVietnamese ? "vi" : "en", default: 0] += 1
        guard let url = learnedFile, let data = try? JSONEncoder().encode(learned) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
