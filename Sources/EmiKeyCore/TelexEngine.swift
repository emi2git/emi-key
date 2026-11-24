import Foundation

/// Standard Telex. Marks (aa ee oo aw ow uw w dd) and tones (s f r x j, z clears) may come anywhere
/// after the vowel; pressing the same key again undoes it and types the letter (`ass` → "as").
public struct TelexEngine: TelexTransforming {
    public init() {}

    public func transform(_ raw: String, style: ToneStyle) -> String? {
        guard let r = Self.process(raw, style: style) else { return nil }
        if r.undone { return r.plausibleBeforeUndo ? r.text : nil }
        return r.action && VietSyllable.isValid(r.text) ? r.text : nil
    }

    /// Rendering without the validity check (for live display while a syllable is still incomplete).
    public func preview(_ raw: String, style: ToneStyle) -> String? {
        guard let r = Self.process(raw, style: style), r.action || r.undone else { return nil }
        return r.text
    }

    struct L { var base: Character; var mark: VMark = .none; var upper: Bool; var fromW = false }
    struct Result { var text: String; var action: Bool; var undone: Bool; var plausibleBeforeUndo: Bool }

    static let toneKeys: [Character: Int] = ["s": 1, "f": 2, "r": 3, "x": 4, "j": 5]
    static func isV(_ l: L) -> Bool { "aeiouy".contains(l.base) }

    static func process(_ raw: String, style: ToneStyle) -> Result? {
        var ls: [L] = []
        var tone = 0, action = false, undone = false, plausible = false
        for ch in raw {
            guard ch.isASCII, ch.isLetter else { return nil }
            let k = Character(ch.lowercased()), up = ch.isUppercase
            let literal = L(base: k, upper: up)
            if undone { ls.append(literal); continue }

            if let t = toneKeys[k], ls.contains(where: isV) {
                if tone == t {
                    plausible = plausiblePrefix(ls); tone = 0; ls.append(literal); undone = true
                } else { tone = t; action = true }
                continue
            }
            if k == "z", tone != 0 { tone = 0; action = true; continue }
            if k == "d", let f = ls.first, f.base == "d" {
                if f.mark == .none { ls[0].mark = .stroke; action = true; continue }
                plausible = plausiblePrefix(ls); ls[0].mark = .none; ls.append(literal); undone = true
                continue
            }
            if k == "a" || k == "e" || k == "o", let i = lastRun(ls).last(where: { ls[$0].base == k }) {
                if ls[i].mark == .hat {
                    plausible = plausiblePrefix(ls); ls[i].mark = .none; ls.append(literal); undone = true
                } else { ls[i].mark = .hat; action = true }
                continue
            }
            if k == "w" {
                let run = lastRun(ls).filter { !(ls[$0].base == "u" && $0 > 0 && ls[$0 - 1].base == "q") }
                var targets: [Int] = [], mark = VMark.horn
                for j in run where targets.isEmpty && ls[j].base == "u" && run.contains(j + 1) && ls[j + 1].base == "o" {
                    targets = [j, j + 1]
                }
                if targets.isEmpty {
                    for j in run where targets.isEmpty && ls[j].base == "o" && run.contains(j + 1) && ls[j + 1].base == "a" {
                        targets = [j + 1]; mark = .breve
                    }
                }
                if targets.isEmpty, let j = run.last(where: { ls[$0].base == "o" }) { targets = [j] }
                if targets.isEmpty, let j = run.last(where: { ls[$0].base == "u" }) { targets = [j] }
                if targets.isEmpty, let j = run.last(where: { ls[$0].base == "a" }) { targets = [j]; mark = .breve }
                if targets.isEmpty {
                    ls.append(L(base: "u", mark: .horn, upper: up, fromW: true)); action = true
                } else if targets.allSatisfy({ ls[$0].mark == mark }) {
                    plausible = plausiblePrefix(ls)
                    for j in targets {
                        ls[j].mark = .none
                        if ls[j].fromW { ls[j].base = "w" }   // standalone ư typed as w: give the w back
                    }
                    ls.append(literal); undone = true
                } else {
                    for j in targets { ls[j].mark = mark }
                    action = true
                }
                continue
            }
            ls.append(literal)
        }
        return Result(text: render(ls, tone: tone, style: style), action: action, undone: undone,
                      plausibleBeforeUndo: plausible)
    }

    /// Indices of the last contiguous vowel run.
    static func lastRun(_ ls: [L]) -> [Int] {
        var i = ls.count - 1
        while i >= 0, !isV(ls[i]) { i -= 1 }
        var run: [Int] = []
        while i >= 0, isV(ls[i]) { run.insert(i, at: 0); i -= 1 }
        return run
    }

    /// Before an undo: initial consonants valid and at most one vowel run (so `class` → nil, `ass` → "as").
    static func plausiblePrefix(_ ls: [L]) -> Bool {
        let fv = ls.firstIndex(where: isV) ?? ls.count
        let initial = String(ls[..<fv].map { VietSyllable.compose($0.base, $0.mark) })
        guard VietSyllable.initials.contains(initial) || initial == "q" else { return false }
        var i = fv
        while i < ls.count, isV(ls[i]) { i += 1 }
        return !ls[i...].contains(where: isV)
    }

    static func tonePosition(_ ls: [L], style: ToneStyle) -> Int? {
        guard let first = ls.firstIndex(where: isV) else { return nil }
        var run = [first]
        while run.last! + 1 < ls.count, isV(ls[run.last! + 1]) { run.append(run.last! + 1) }
        if run.count >= 2, first > 0,
           (ls[first - 1].base == "q" && ls[first].base == "u") ||
           (first == 1 && ls[0].base == "g" && ls[first].base == "i" && ls[first].mark == .none) {
            run.removeFirst()
        }
        if let m = run.last(where: { [.hat, .breve, .horn].contains(ls[$0].mark) }) { return m }
        if run.count == 1 { return run[0] }
        if run.last! + 1 < ls.count { return run.last! }
        if run.count >= 3 { return run[1] }
        let pair = String(run.map { ls[$0].base })
        if ["oa", "oe", "uy"].contains(pair) { return style == .new ? run[1] : run[0] }
        return run[0]
    }

    static func render(_ ls: [L], tone: Int, style: ToneStyle) -> String {
        var chars = ls.map { VietSyllable.compose($0.base, $0.mark) }
        if tone != 0, let p = tonePosition(ls, style: style) { chars[p] = VietSyllable.toned(chars[p], tone) }
        return String(zip(chars, ls).map { $1.upper ? String($0).uppercased() : String($0) }.joined())
    }
}
