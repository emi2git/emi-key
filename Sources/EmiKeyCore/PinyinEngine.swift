import Foundation

/// Pinyin dictionary + parser over `pinyin.tsv` (simplified \t traditional \t "ni3 hao3" \t freq).
/// The syllable set is derived from the dictionary itself.  Texts stay as UTF-8 byte ranges into the
/// loaded file and are decoded only for returned candidates; lookups use flat hash tables, which
/// keeps loading fast even in debug builds.
public final class PinyinEngine: PinyinLookup, @unchecked Sendable {
    struct Entry {
        var simp: Int32, simpLen: UInt8
        var trad: Int32, tradLen: UInt8
        var syl: Int32, n: UInt8
    }
    struct QSyl { let id: UInt16; let tone: UInt8; let end: Int }   // tone 0 = any; end = input chars consumed
    struct Match { let entry: Int32; let score: Double; let wrong: Int }

    private var buf: [UInt8] = []
    private var entries: [Entry] = []
    private var syls: [UInt16] = []
    private var tones: [UInt8] = []
    private var weight: [Float] = []        // frequency, split between the readings of one character
    // Entry index: chained hash table keyed by the toneless syllable sequence.
    private var keys: [UInt64] = []
    private var next: [Int32] = []
    private var head = [Int32](repeating: -1, count: 1 << 18)
    // Syllable table: packed letters (5 bits each) → id.
    private var sylCode = [UInt64](repeating: 0, count: 2048)
    private var sylSlot = [Int32](repeating: -1, count: 2048)
    private var typeable: [Bool] = []       // syllable has a vowel ("m", "ng", "hng", "r" don't count)
    private var maxLen = 1
    private var lnTotal = 0.0
    public private(set) var loadMillis = 0.0

    static let wrongTonePenalty = 2.0
    static let lengthBonus = 3.0            // per extra syllable of a dictionary word
    static let spanTop = 6, beam = 8

    public var entryCount: Int { entries.count }
    public var syllableCount: Int { typeable.filter { $0 }.count }

    public init(resources: URL) {
        let t0 = Date()
        if let data = try? Data(contentsOf: resources.appendingPathComponent("pinyin.tsv")) {
            buf = [UInt8](data)
            parse()
            splitReadings()
        }
        loadMillis = Date().timeIntervalSince(t0) * 1000
    }

    // MARK: - Loading

    private static let fnvSeed: UInt64 = 1469598103934665603
    @inline(__always) private static func fnv(_ k: UInt64, _ id: UInt16) -> UInt64 { (k ^ UInt64(id &+ 1)) &* 1099511628211 }
    @inline(__always) private static func slot(_ code: UInt64) -> Int { Int((code &* 0x9E3779B97F4A7C15) >> 53) }

    private func findSyllable(_ code: UInt64) -> Int32 {
        var s = PinyinEngine.slot(code)
        while sylSlot[s] >= 0 { if sylCode[s] == code { return sylSlot[s] }; s = (s + 1) & 2047 }
        return -1
    }

    private func syllableID(code: UInt64, len: Int) -> UInt16 {
        var s = PinyinEngine.slot(code)
        while sylSlot[s] >= 0 { if sylCode[s] == code { return UInt16(sylSlot[s]) }; s = (s + 1) & 2047 }
        let id = typeable.count
        sylCode[s] = code; sylSlot[s] = Int32(id)
        var c = code, vowel = false, letters: [UInt8] = []
        for _ in 0..<len { letters.append(UInt8(c & 31) + 96); c >>= 5 }
        for l in letters where "aeiouv".utf8.contains(l) { vowel = true }
        typeable.append(vowel && letters != [120, 120])   // "xx" is a placeholder
        return UInt16(id)
    }

    private func parse() {
        var total = 0.0
        buf.withUnsafeBufferPointer { p in
            let n = p.count
            guard let base = p.baseAddress, n > 0 else { return }
            // Upper bounds: a line has at least 8 bytes, a syllable at least 2 (uninitialised, so cheap).
            let lines = n / 8 + 1, seps = n / 2 + 1
            func find(_ c: Int32, _ from: Int) -> Int {
                guard from < n, let r = memchr(base + from, c, n - from) else { return n }
                return base.distance(to: r.assumingMemoryBound(to: UInt8.self))
            }
            // Raw buffers (no bounds checks / CoW in debug builds); copied into arrays at the end.
            let E = UnsafeMutablePointer<Entry>.allocate(capacity: lines)
            let W = UnsafeMutablePointer<Float>.allocate(capacity: lines)
            let K = UnsafeMutablePointer<UInt64>.allocate(capacity: lines)
            let X = UnsafeMutablePointer<Int32>.allocate(capacity: lines)
            let S = UnsafeMutablePointer<UInt16>.allocate(capacity: seps)
            let T = UnsafeMutablePointer<UInt8>.allocate(capacity: seps)
            defer { E.deallocate(); W.deallocate(); K.deallocate(); X.deallocate(); S.deallocate(); T.deallocate() }
            var ne = 0, ns = 0
            head.withUnsafeMutableBufferPointer { H in
                var i = 0
                while i < n {
                    let s0 = i, s1 = find(9, i); i = s1 + 1
                    let t0 = i, t1 = find(9, i); i = t1 + 1
                    let sylStart = ns
                    var code: UInt64 = 0, len = 0, tone: UInt8 = 5, key = PinyinEngine.fnvSeed
                    while i < n {
                        var c = p[i]
                        if c >= 65 && c <= 90 { c += 32 }
                        if c >= 97 && c <= 122 { if len < 12 { code |= UInt64(c - 96) << (5 * UInt64(len)) }; len += 1 }
                        else if c >= 48 && c <= 53 { tone = c == 48 ? 5 : c - 48 }
                        else if c == 32 || c == 9 || c == 10 {
                            if len > 0 && ns < seps {
                                let id = syllableID(code: code, len: min(len, 12))
                                S[ns] = id; T[ns] = tone; ns += 1; key = PinyinEngine.fnv(key, id)
                            }
                            code = 0; len = 0; tone = 5
                            if c != 32 { break }
                        }
                        i += 1
                    }
                    let atTab = i < n && p[i] == 9
                    i += 1
                    var f = 0
                    if atTab { while i < n && p[i] != 10 { if p[i] >= 48 && p[i] <= 57 { f = f * 10 + Int(p[i] - 48) }; i += 1 }; i += 1 }
                    let cnt = ns - sylStart
                    guard cnt > 0, s1 > s0, ne < lines else { ns = sylStart; continue }
                    E[ne] = Entry(simp: Int32(s0), simpLen: UInt8(min(s1 - s0, 255)),
                                  trad: Int32(t0), tradLen: UInt8(min(t1 - t0, 255)),
                                  syl: Int32(sylStart), n: UInt8(min(cnt, 255)))
                    W[ne] = Float(f)
                    total += Double(f) + 0.5
                    if cnt > maxLen { maxLen = cnt }
                    let h = Int(key >> 46)
                    K[ne] = key; X[ne] = H[h]; H[h] = Int32(ne)
                    ne += 1
                }
            }
            entries = Array(UnsafeBufferPointer(start: E, count: ne))
            weight = Array(UnsafeBufferPointer(start: W, count: ne))
            keys = Array(UnsafeBufferPointer(start: K, count: ne))
            next = Array(UnsafeBufferPointer(start: X, count: ne))
            syls = Array(UnsafeBufferPointer(start: S, count: ns))
            tones = Array(UnsafeBufferPointer(start: T, count: ns))
        }
        lnTotal = log(max(total, 1))
    }

    /// Decodes one UTF-8 scalar at `i`; returns (scalar, byte length).
    @inline(__always) private static func scalar(_ p: UnsafeBufferPointer<UInt8>, _ i: Int) -> (Int, Int) {
        let b = Int(p[i])
        if b < 0x80 { return (b, 1) }
        if b < 0xE0 { return ((b & 0x1F) << 6 | Int(p[i+1] & 0x3F), 2) }
        if b < 0xF0 { return ((b & 0x0F) << 12 | Int(p[i+1] & 0x3F) << 6 | Int(p[i+2] & 0x3F), 3) }
        return ((b & 0x07) << 18 | Int(p[i+1] & 0x3F) << 12 | Int(p[i+2] & 0x3F) << 6 | Int(p[i+3] & 0x3F), 4)
    }

    /// A character with several readings carries the same frequency on each (吗 ma2/ma3/ma5).
    /// Split it by how often each reading occurs inside longer words, plus a share for neutral-tone
    /// readings (standalone particles such as 吗 ma5 / 了 le5 rarely occur inside compounds).
    private func splitReadings() {
        let maxScalar = 0x40000, count = entries.count
        var group = [Int32](repeating: -1, count: maxScalar)   // scalar → latest single-char entry
        var single = [Int32](repeating: -1, count: count)      // chain of readings of one scalar
        var multi = [Bool](repeating: false, count: maxScalar)
        var support = [Double](repeating: 0, count: count)     // per single-char entry
        var multiList: [Int] = []
        buf.withUnsafeBufferPointer { p in entries.withUnsafeBufferPointer { E in
        syls.withUnsafeBufferPointer { S in tones.withUnsafeBufferPointer { T in weight.withUnsafeBufferPointer { W in
        group.withUnsafeMutableBufferPointer { G in single.withUnsafeMutableBufferPointer { N in
        multi.withUnsafeMutableBufferPointer { M in support.withUnsafeMutableBufferPointer { U in
            for i in 0..<count where E[i].n == 1 {
                let (s, l) = PinyinEngine.scalar(p, Int(E[i].simp))
                guard l == Int(E[i].simpLen), s < maxScalar else { continue }
                if G[s] >= 0 && !M[s] { M[s] = true; multiList.append(s) }
                N[i] = G[s]; G[s] = Int32(i)
            }
            for i in 0..<count where E[i].n > 1 {
                var at = Int(E[i].simp), k = 0
                let end = at + Int(E[i].simpLen), n = Int(E[i].n), base = Int(E[i].syl)
                while at < end && k < n {
                    let (s, l) = PinyinEngine.scalar(p, at)
                    if s < maxScalar && M[s] {
                        let sy = S[base + k], tn = T[base + k]
                        var r = Int(G[s])
                        while r >= 0 {
                            let ri = Int(E[r].syl)
                            if S[ri] == sy && T[ri] == tn { U[r] += Double(W[i]); break }
                            r = Int(N[r])
                        }
                    }
                    at += l; k += 1
                }
            }
        } } } } } } } } }
        for s in multiList {
            var list: [Int] = []
            var r = group[s]; while r >= 0 { list.append(Int(r)); r = single[Int(r)] }
            let f = Double(list.map { weight[$0] }.max() ?? 0)
            let neutral = list.filter { tones[Int(entries[$0].syl)] == 5 }.count
            let sup = list.map { support[$0] + (tones[Int(entries[$0].syl)] == 5 ? 0.5 * f / Double(neutral) : 0) }
            let k = 0.02 * f + 1
            let sum = sup.reduce(0, +) + Double(list.count) * k
            for (j, e) in list.enumerated() { weight[e] = Float(Double(weight[e]) * (sup[j] + k) / sum) }
        }
    }

    // MARK: - Segmentation

    /// Syllable id for letters[a..<b] when it is a typeable syllable.
    private func syllable(_ l: [UInt8], _ a: Int, _ b: Int) -> UInt16? {
        guard b - a <= 6 else { return nil }
        var code: UInt64 = 0
        for (k, i) in (a..<b).enumerated() {
            guard l[i] >= 97 && l[i] <= 122 else { return nil }
            code |= UInt64(l[i] - 96) << (5 * UInt64(k))
        }
        let id = findSyllable(code)
        return id >= 0 && typeable[Int(id)] ? UInt16(id) : nil
    }

    /// All complete segmentations of `l` (up to `cap`), longest first syllables first.
    private func segmentations(_ l: [UInt8], cap: Int) -> [[(UInt16, Int)]] {
        let n = l.count
        var ok = [Bool](repeating: false, count: n + 1); ok[n] = true
        if n > 0 { for a in stride(from: n - 1, through: 0, by: -1) {
            for b in (a + 1)...min(n, a + 6) where ok[b] && syllable(l, a, b) != nil { ok[a] = true; break }
        } }
        guard n > 0, ok[0] else { return [] }
        var out: [[(UInt16, Int)]] = [], cur: [(UInt16, Int)] = []
        func dfs(_ a: Int) {
            if out.count >= cap { return }
            if a == n { out.append(cur); return }
            for b in stride(from: min(n, a + 6), to: a, by: -1) where ok[b] {
                if let id = syllable(l, a, b) { cur.append((id, b)); dfs(b); cur.removeLast() }
            }
        }
        dfs(0)
        return out
    }

    public func segmentsAsPinyin(_ letters: String) -> Bool {
        let l = Array(letters.lowercased().utf8)
        return !l.isEmpty && !segmentations(l, cap: 1).isEmpty
    }

    /// Parses "xiao4yang2shangshan" into candidate syllable sequences.  A digit ends a syllable.
    /// When the tail cannot be segmented (still typing), the longest segmentable prefix is used.
    func parseInput(_ input: String) -> [[QSyl]] {
        var chunks: [([UInt8], UInt8, Int)] = []   // letters, tone, input offset of first letter
        var cur: [UInt8] = [], start = 0, pos = 0
        for c in input.lowercased().utf8 {
            if c >= 97 && c <= 122 { if cur.isEmpty { start = pos }; cur.append(c) }
            else if c >= 48 && c <= 53, !cur.isEmpty { chunks.append((cur, c == 48 ? 5 : c - 48, start)); cur = [] }
            else { break }
            pos += 1
        }
        if !cur.isEmpty { chunks.append((cur, 0, start)) }
        var result: [[QSyl]] = [[]]
        for (letters, tone, base) in chunks {
            var segs = segmentations(letters, cap: 6)
            var complete = true
            if segs.isEmpty {   // longest prefix that segments
                complete = false
                var p = letters.count - 1
                while p > 0 && segs.isEmpty { segs = segmentations(Array(letters[0..<p]), cap: 3); p -= 1 }
                if segs.isEmpty { break }
            }
            var next: [[QSyl]] = []
            for r in result { for s in segs where next.count < 12 {
                var q = r
                for (k, (id, end)) in s.enumerated() {
                    let last = k == s.count - 1 && complete
                    q.append(QSyl(id: id, tone: last ? tone : 0, end: base + end + (last && tone > 0 ? 1 : 0)))
                }
                next.append(q)
            } }
            result = next
            if !complete { break }
        }
        return result.filter { !$0.isEmpty }
    }

    // MARK: - Candidates

    private func matches(_ q: ArraySlice<QSyl>) -> [Match] {
        var key = PinyinEngine.fnvSeed
        for x in q { key = PinyinEngine.fnv(key, x.id) }
        var out: [Match] = []
        var e = head[Int(key >> 46)]
        while e >= 0 { defer { e = next[Int(e)] }
            guard keys[Int(e)] == key else { continue }
            let en = entries[Int(e)]
            guard Int(en.n) == q.count else { continue }
            var wrong = 0, same = true
            for (k, s) in q.enumerated() {
                let at = Int(en.syl) + k
                if syls[at] != s.id { same = false; break }
                if s.tone != 0 && tones[at] != s.tone { wrong += 1 }
            }
            guard same else { continue }
            let sc = log(Double(weight[Int(e)]) + 0.5) - lnTotal - PinyinEngine.wrongTonePenalty * Double(wrong)
                + PinyinEngine.lengthBonus * Double(q.count - 1)
            out.append(Match(entry: e, score: sc, wrong: wrong))
        }
        return out.sorted { $0.wrong != $1.wrong ? $0.wrong < $1.wrong : $0.score > $1.score }
    }

    private func text(_ es: [Int32], traditional: Bool) -> String {
        var bytes: [UInt8] = []
        for e in es {
            let en = entries[Int(e)]
            let off = Int(traditional ? en.trad : en.simp), len = Int(traditional ? en.tradLen : en.simpLen)
            bytes.append(contentsOf: buf[off..<off + len])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// k-best word segmentations over the syllables by log frequency (wrong tones penalised).
    private func compose(_ q: [QSyl], cache: inout [Int: [Match]]) -> [(Double, [Int32])] {
        let n = q.count
        var best = [[(Double, [Int32])]](repeating: [], count: n + 1)
        best[0] = [(0, [])]
        for i in 0..<n where !best[i].isEmpty {
            for j in (i + 1)...min(n, i + maxLen) {
                let key = i * 64 + j
                let ms = cache[key] ?? { let m = matches(q[i..<j]); cache[key] = m; return m }()
                let top = ms.sorted { $0.score > $1.score }.prefix(PinyinEngine.spanTop)
                for p in best[i] { for m in top {
                    let s = p.0 + m.score
                    if best[j].count >= PinyinEngine.beam, let worst = best[j].last, worst.0 >= s { continue }
                    let at = best[j].firstIndex { $0.0 < s } ?? best[j].count
                    best[j].insert((s, p.1 + [m.entry]), at: at)
                    if best[j].count > PinyinEngine.beam { best[j].removeLast() }
                } }
            }
        }
        return best[n]
    }

    static let splitWordMinWeight: Float = 1000

    /// Does this reading (dictionary words over syllables `q`) contain a common word with the typed tones that covers
    /// exactly one syllable of the `primary` reading (西安 = xi an where the primary reading has the one syllable xian)?
    private func splitsIntoWord(_ es: [Int32], _ q: [QSyl], primary: [QSyl]) -> Bool {
        let spans = Set(primary.indices.map { (($0 == 0 ? 0 : primary[$0 - 1].end) << 16) | primary[$0].end })
        var k = 0
        for e in es {
            let en = entries[Int(e)], n = Int(en.n)
            defer { k += n }
            guard n > 1, k + n <= q.count, weight[Int(e)] >= Self.splitWordMinWeight else { continue }
            let exact = (0..<n).allSatisfy { q[k + $0].tone == 0 || tones[Int(en.syl) + $0] == q[k + $0].tone }
            let span = ((k == 0 ? 0 : q[k - 1].end) << 16) | q[k + n - 1].end
            if exact, spans.contains(span) { return true }
        }
        return false
    }

    public func candidates(for input: String, traditional: Bool, limit: Int) -> [PinyinCandidate] {
        guard limit > 0 else { return [] }
        let segs = parseInput(input)
        guard !segs.isEmpty else { return [] }
        // Whole-input items: (class 0 = dictionary word with exact tones, 1 = the rest), score.
        var whole: [(cls: Int, score: Double, entries: [Int32], seg: Int)] = []
        var caches = [[Int: [Match]]](repeating: [:], count: segs.count)
        for (si, q) in segs.enumerated() {
            // Compare segmentations on plain frequency (the length bonus only ranks words against
            // compositions of the same syllables), and prefer fewer, longer syllables (xian > xi an).
            let segCost = (PinyinEngine.lengthBonus + 0.5) * Double(q.count - 1)
            let direct = matches(q[...])
            caches[si][q.count] = direct
            for m in direct { whole.append((m.wrong == 0 ? 0 : 1, m.score - segCost, [m.entry], si)) }
            if q.count > 1 {
                for (s, es) in compose(q, cache: &caches[si]) where es.count > 1 { whole.append((1, s - segCost, es, si)) }
            }
        }
        whole.sort { $0.cls != $1.cls ? $0.cls < $1.cls : $0.score > $1.score }
        let primary = whole.first?.seg ?? 0
        let q = segs[primary]

        var seen = Set<String>()
        var wholeOut: [PinyinCandidate] = []
        for w in whole {
            let t = text(w.entries, traditional: traditional)
            if seen.insert(t).inserted { wholeOut.append(PinyinCandidate(text: t, consumed: segs[w.seg].last!.end)) }
            if wholeOut.count >= limit { break }
        }
        var prefixOut: [PinyinCandidate] = []
        if q.count > 1 {
            for j in stride(from: q.count - 1, through: 1, by: -1) {
                let ms = caches[primary][j] ?? matches(q[0..<j])
                var added = 0
                for m in ms where added < (j == 1 ? 5 : 2) {
                    let t = text([m.entry], traditional: traditional)
                    if seen.insert(t).inserted { prefixOut.append(PinyinCandidate(text: t, consumed: q[j - 1].end)); added += 1 }
                }
            }
        }
        let wholeCap = max(1, limit - min(prefixOut.count, max(limit / 3, 1)))
        var out = Array(wholeOut.prefix(wholeCap))
        // Another way to split the syllables (xian → xi an) loses on frequency against common single characters,
        // but when that split spells a common word (西安, 去西安) it is offered too, in the last whole-input slot.
        if segs.count > 1, out.count >= 2,
           let a = whole.first(where: { $0.seg != primary && splitsIntoWord($0.entries, segs[$0.seg], primary: q) }),
           case let t = text(a.entries, traditional: traditional), !out.contains(where: { $0.text == t }) {
            let c = PinyinCandidate(text: t, consumed: segs[a.seg].last!.end)
            if out.count >= wholeCap { out[out.count - 1] = c } else { out.append(c) }
            seen.insert(t)
        }
        out += prefixOut.prefix(limit - out.count)
        if out.count < limit { out += wholeOut.dropFirst(wholeCap).prefix(limit - out.count) }
        return out
    }
}
