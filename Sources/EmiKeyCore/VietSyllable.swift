import Foundation

/// Vowel/consonant modifier used by Telex: â ê ô (hat), ă (breve), ơ ư (horn), đ (stroke).
enum VMark: Sendable { case none, hat, breve, horn, stroke }

/// Vietnamese syllable tables + validator (no word list).
public enum VietSyllable {
    /// Each row: marked vowel followed by its sắc, huyền, hỏi, ngã, nặng forms. Tone index 1…5.
    static let rows = ["aáàảãạ", "ăắằẳẵặ", "âấầẩẫậ", "eéèẻẽẹ", "êếềểễệ", "iíìỉĩị",
                       "oóòỏõọ", "ôốồổỗộ", "ơớờởỡợ", "uúùủũụ", "ưứừửữự", "yýỳỷỹỵ"]

    /// lowercase char → (marked vowel without tone, tone 0…5)
    static let decomp: [Character: (Character, Int)] = {
        var d: [Character: (Character, Int)] = [:]
        for row in rows {
            let cs = Array(row)
            for (t, c) in cs.enumerated() { d[c] = (cs[0], t) }
        }
        return d
    }()

    static let vowels: Set<Character> = Set(rows.map { Array($0)[0] })

    /// (base ascii letter, mark) → lowercase Vietnamese letter.
    static func compose(_ base: Character, _ mark: VMark) -> Character {
        switch (base, mark) {
        case ("a", .hat): return "â"
        case ("a", .breve): return "ă"
        case ("e", .hat): return "ê"
        case ("o", .hat): return "ô"
        case ("o", .horn): return "ơ"
        case ("u", .horn): return "ư"
        case ("d", .stroke): return "đ"
        default: return base
        }
    }

    /// Put tone (1…5) on a lowercase marked vowel.
    static func toned(_ v: Character, _ tone: Int) -> Character {
        guard tone > 0, let row = rows.first(where: { $0.first == v }) else { return v }
        return Array(row)[tone]
    }

    static let initials: Set<String> = ["", "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n",
                                        "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x"]
    static let finals: Set<String> = ["c", "ch", "m", "n", "ng", "nh", "p", "t"]
    static let openOnly: Set<String> = ["ai", "ao", "au", "âu", "ay", "ây", "eo", "êu", "ia", "iu", "oi", "ôi", "ơi",
                                        "ui", "ưi", "ưu", "ưa", "ua", "oai", "oay", "oao", "oeo", "uôi", "ươi", "ươu",
                                        "uây", "uyu", "iêu", "yêu", "uya", "uơ", "y"]
    static let needFinal: Set<String> = ["ă", "â", "iê", "yê", "uô", "ươ", "uâ", "oă", "uyê", "oo"]
    static let either: Set<String> = ["a", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "oa", "oe", "uê", "uy"]
    static let chNhNuclei: Set<String> = ["a", "ê", "i", "oa", "uê", "uy"]

    struct Parts: Equatable { var initial: String; var nucleus: String; var final: String; var tone: Int }

    /// Split a (possibly toned) word into initial / nucleus / final / tone. nil if not shaped like one syllable.
    static func parse(_ word: String) -> Parts? {
        var tone = 0
        var plain: [Character] = []
        for ch in word.lowercased() {
            if let (v, t) = decomp[ch] {
                if t != 0 { if tone != 0 { return nil }; tone = t }
                plain.append(v)
            } else if ch == "đ" || (ch.isASCII && ch.isLetter) {
                plain.append(ch)
            } else { return nil }
        }
        guard let fv = plain.firstIndex(where: { vowels.contains($0) }) else { return nil }
        var end = fv
        while end < plain.count, vowels.contains(plain[end]) { end += 1 }
        guard !plain[end...].contains(where: { vowels.contains($0) }) else { return nil }
        var initial = String(plain[..<fv])
        var start = fv
        if initial == "q" {
            guard plain[fv] == "u", end - fv >= 2 else { return nil }
            initial = "qu"; start += 1
        } else if initial == "g", plain[fv] == "i", end - fv >= 2 {
            initial = "gi"; start += 1
        }
        return Parts(initial: initial, nucleus: String(plain[start..<end]), final: String(plain[end...]), tone: tone)
    }

    /// True when `word` (e.g. "việt", "cho", "người") is a valid Vietnamese syllable.
    public static func isValid(_ word: String) -> Bool {
        guard let p = parse(word), initials.contains(p.initial) else { return false }
        let n = p.nucleus, f = p.final
        guard let first = n.first else { return false }
        guard f.isEmpty || finals.contains(f) else { return false }
        if openOnly.contains(n) { guard f.isEmpty else { return false } }
        else if needFinal.contains(n) { guard !f.isEmpty else { return false } }
        else if !either.contains(n) { return false }
        if n == "oo", !(f == "ng" || f == "c") { return false }
        if f == "ch" || f == "nh" { guard chNhNuclei.contains(n) else { return false } }
        if ["c", "ch", "p", "t"].contains(f) { guard p.tone == 1 || p.tone == 5 else { return false } }
        // Spelling: c/k, g/gh, ng/ngh.
        let front = "ieêy".contains(first)
        switch p.initial {
        case "c": if front { return false }
        case "k": if !front { return false }
        case "gh", "ngh": if !"ieê".contains(first) { return false }
        case "g": if "eê".contains(first) { return false }
        case "ng": if "ieê".contains(first) { return false }
        default: break
        }
        return true
    }

    /// True when the word carries Vietnamese-only letters (tone marks, ă â ê ô ơ ư đ).
    public static func hasVietnameseMarks(_ word: String) -> Bool {
        word.lowercased().contains { ch in
            if ch == "đ" { return true }
            if let (v, t) = decomp[ch] { return t != 0 || !"aeiouy".contains(v) }
            return false
        }
    }
}
