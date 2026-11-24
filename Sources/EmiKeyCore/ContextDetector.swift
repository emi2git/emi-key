import Foundation

/// Language of the text just before the cursor: looks at the last ~6 words, most recent weighing most.
/// Words on earlier lines count half. Returns nil when there is nothing to judge.
public struct ContextDetector: Sendable {
    let english: EnglishLexicon?
    public var maxWords = 6

    public init(english: EnglishLexicon? = nil) { self.english = english }

    public func detect(_ text: String) -> Lang? {
        let tail = String(text.suffix(400))
        var lines = tail.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var words: [(String, Double)] = []   // newest first
        var factor = 1.0
        while words.count < maxWords, let line = lines.popLast() {
            for w in Self.words(line).reversed() where words.count < maxWords { words.append((w, factor)) }
            factor *= 0.5
        }
        var score: [Lang: Double] = [:]
        for (rank, (w, f)) in words.enumerated() {
            let weight = pow(0.6, Double(rank)) * f
            for (lang, s) in classify(w) { score[lang, default: 0] += s * weight }
        }
        guard let best = score.max(by: { a, b in
            a.value != b.value ? a.value < b.value : (a.key != .en)   // tie → .en
        }), best.value > 0 else { return nil }
        return best.key
    }

    static func words(_ line: String) -> [String] {
        line.split(whereSeparator: { $0.isWhitespace }).compactMap { tok in
            let w = String(tok).trimmingCharacters(in: .punctuationCharacters.union(.symbols))
            return w.isEmpty ? nil : w
        }
    }

    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            (0x3400...0x9FFF).contains(s.value) || (0xF900...0xFAFF).contains(s.value) ||
            (0x20000...0x2FFFF).contains(s.value) || (0x3040...0x30FF).contains(s.value)
        }
    }

    func classify(_ w: String) -> [Lang: Double] {
        if w.contains(where: Self.isCJK) { return [.zh: 1.5] }
        if VietSyllable.hasVietnameseMarks(w) { return [.vi: 1.5] }
        guard w.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [:] }
        let en = english?.isWord(w) ?? false
        let vi = VietSyllable.isValid(w)
        switch (en, vi) {
        case (true, true):
            // a rare English word that is a normal Vietnamese syllable (cho, con, ban) leans Vietnamese
            if let r = english?.rank(w), r > 3000 { return [.vi: 0.8, .en: 0.2] }
            return [.en: 0.5, .vi: 0.5]
        case (true, false): return [.en: 1]
        case (false, true): return [.vi: english == nil ? 0.5 : 0.8]
        case (false, false): return [.en: 0.4]
        }
    }
}
