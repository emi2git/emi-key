import XCTest
@testable import EmiKeyCore

struct FakeEnglish: EnglishLexicon {
    static let words: Set<String> = ["bus", "has", "ban", "man", "the", "i", "take", "test", "class", "git", "ma", "an",
                                     "he", "men", "change", "my", "hello", "so", "to", "do", "as", "less", "dad"]
    func isWord(_ w: String) -> Bool { Self.words.contains(w.lowercased()) }
}

struct FakePinyin: PinyinLookup {
    static let syllables: Set<String> = ["ma", "ni", "hao", "xiao", "yang", "shang", "shan", "wo", "ai", "zhong", "guo",
                                         "ren", "a", "de", "shi", "hen"]
    static let simp: [String: [String]] = [
        "ma3": ["马", "码", "蚂"], "ma5": ["吗"], "ma0": ["吗"], "ma1": ["妈", "吗"],
        "nihao3": ["你好"], "ni3hao3": ["你好"], "ni3hao": ["你好"],
        "xiao4": ["小", "笑"], "xiao4yang": ["小羊"], "xiao4yang2": ["小羊"],
        "xiao4yang2shang": ["小羊上"], "xiao4yang2shangshan": ["小羊上山"],
        "ren2": ["人", "仁"], "wo3ai4ni3": ["我爱你"],
    ]
    static let trad: [String: [String]] = ["ma3": ["馬", "碼", "螞"]]

    func segmentsAsPinyin(_ letters: String) -> Bool {
        let s = Array(letters.lowercased())
        guard !s.isEmpty else { return false }
        var ok = [Bool](repeating: false, count: s.count + 1); ok[0] = true
        for i in 0..<s.count where ok[i] {
            for j in (i + 1)...s.count where Self.syllables.contains(String(s[i..<j])) { ok[j] = true }
        }
        return ok[s.count]
    }

    func candidates(for input: String, traditional: Bool, limit: Int) -> [PinyinCandidate] {
        if input.hasPrefix("zhong1guo2") {   // only a prefix phrase exists
            return input == "zhong1guo2" ? [PinyinCandidate(text: "中国", consumed: 10)]
                : [PinyinCandidate(text: "中国", consumed: 10), PinyinCandidate(text: "中", consumed: 6)]
        }
        let list = (traditional ? Self.trad[input] : nil) ?? Self.simp[input] ?? []
        return list.prefix(limit).map { PinyinCandidate(text: $0, consumed: input.count) }
    }
}

final class ComposerTests: XCTestCase {
    var learnedURL: URL!

    override func setUp() {
        learnedURL = FileManager.default.temporaryDirectory.appendingPathComponent("emikey-\(UUID().uuidString)/learned.json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: learnedURL.deletingLastPathComponent()) }

    func make(_ s: ComposerSettings = .init(), learned: Bool = false) -> Composer {
        Composer(telex: TelexEngine(), pinyin: FakePinyin(), english: FakeEnglish(), settings: s,
                 learnedFile: learned ? learnedURL : nil)
    }

    /// Feeds keys to a simulated text field. " " space, "\n" enter, "⎋" escape, "⌫" backspace, "⇥" tab.
    /// `preceding` non-nil → the app reports the text before the cursor; nil → app hides it.
    @discardableResult
    func type(_ s: String, preceding: String? = nil, composer: Composer? = nil, last: UnsafeMutablePointer<ComposerOutput>? = nil) -> String {
        let c = composer ?? make()
        var field = preceding ?? ""
        for ch in s {
            let key: KeyInput
            switch ch {
            case " ": key = .space
            case "\n": key = .enter
            case "⎋": key = .escape
            case "⌫": key = .backspace
            case "⇥": key = .tab
            default: key = .char(ch)
            }
            let out = c.handle(key, precedingText: preceding == nil ? nil : field)
            field.removeLast(min(c.lastDeleteCount, field.count))
            field += out.commit
            if !out.handled {
                switch key {
                case .enter: field += "\n"
                case .space: field += " "
                case .tab: field += "\t"
                case .char(let x): field += String(x)
                case .backspace: if !field.isEmpty { field.removeLast() }
                default: break
                }
            }
            last?.pointee = out
        }
        return field
    }

    func out(_ s: String, composer: Composer? = nil) -> ComposerOutput {
        var o = ComposerOutput()
        type(s, composer: composer, last: &o)
        return o
    }

    // MARK: Vietnamese / English

    func testSpecExamples() {
        XCTAssertEqual(type("cho con bus ", preceding: "Mẹ đưa "), "Mẹ đưa cho con bú ")
        XCTAssertEqual(type("I take the bus "), "I take the bus ")
        XCTAssertEqual(type("I take the bus ", preceding: ""), "I take the bus ")
        XCTAssertEqual(type("tooi ddi bus "), "tôi đi bú ")
        XCTAssertEqual(type("tooi has "), "tôi há ")
        XCTAssertEqual(type("bus "), "bus ")
        XCTAssertEqual(type("class test git went wow aws the "), "class test git went wow aws the ")
        XCTAssertEqual(type("Vieetj Nam "), "Việt Nam ")
        XCTAssertEqual(type("nguowif Vieetj "), "người Việt ")
    }

    func testPunctuationAndEnter() {
        XCTAssertEqual(type("tooi, ddi."), "tôi, đi.")
        XCTAssertEqual(type("vieetj\nhello\n"), "việt\nhello\n")
        XCTAssertEqual(type("ass "), "as ")           // Telex undo
        XCTAssertEqual(type("less "), "less ")       // English word, only an undo → raw
        XCTAssertEqual(type("aaa "), "aa ")
        XCTAssertEqual(type("ddd "), "dd ")
    }

    func testMarkedText() {
        XCTAssertEqual(out("vieetj").marked, "việt")
        XCTAssertEqual(out("bu").marked, "bu")
        XCTAssertEqual(out("hello").marked, "hello")
        XCTAssertEqual(out("tooi vieet").marked, "viêt")   // preview in Vietnamese context
        XCTAssertEqual(out("vieetj").commit, "")
    }

    func testEscFlipAfterCommit() {
        XCTAssertEqual(type("I take the bus ⎋"), "I take the bú ")
        XCTAssertEqual(type("cho con bus ⎋", preceding: "Mẹ đưa "), "Mẹ đưa cho con bus ")
        XCTAssertEqual(type("tooi ⎋"), "tooi ")
        XCTAssertEqual(type("tooi ⎋⎋"), "tôi ")
        XCTAssertEqual(type("bus,⎋"), "bú,")
        let c = make()
        type("bus ", composer: c)
        _ = c.handle(.escape, precedingText: nil)
        XCTAssertEqual(c.lastDeleteCount, 4)
        XCTAssertEqual(c.lastDeleteUTF16Count, 4)
        // Esc not right after the word → passed on.
        XCTAssertEqual(type("bus x⌫⎋"), "bus ")
        XCTAssertFalse(out("hello ⎋").handled)
        XCTAssertFalse(out("⎋").handled)
        XCTAssertFalse(out("tooi\n⎋").handled)
    }

    func testEscFlipWhileComposing() {
        XCTAssertEqual(out("bus⎋").marked, "bú")
        XCTAssertEqual(type("bus⎋ "), "bú ")
        XCTAssertEqual(type("tooi⎋ "), "tooi ")
        XCTAssertEqual(type("tooi⎋⎋ "), "tôi ")
        // No transform: commit raw, Esc goes to the app.
        let o = out("hello⎋")
        XCTAssertFalse(o.handled)
        XCTAssertEqual(type("hello⎋"), "hello")
    }

    func testLearnedOnlyWhenNoContext() {
        for _ in 0..<2 { let c = make(learned: true); type("bus ⎋", composer: c) }
        XCTAssertEqual(type("bus ", composer: make(learned: true)), "bú ")
        XCTAssertEqual(type("the bus ", composer: make(learned: true)), "the bus ")   // context wins
        XCTAssertEqual(type("bus ", composer: make(learned: false)), "bus ")
        XCTAssertTrue(FileManager.default.fileExists(atPath: learnedURL.path))
    }

    func testBackspaceAndOther() {
        XCTAssertEqual(type("tooij⌫ "), "tôi ")
        XCTAssertEqual(type("ab⌫⌫⌫"), "")
        XCTAssertFalse(out("⌫").handled)
        let o = out("tooi⇥")
        XCTAssertFalse(o.handled)
        XCTAssertEqual(type("tooi⇥"), "tôi\t")
        let c = make()
        _ = type("vieetj", composer: c)
        let r = c.handle(.other, precedingText: nil)
        XCTAssertEqual(r.commit, "việt"); XCTAssertFalse(r.handled)
    }

    func testFlushAndMemoryReset() {
        let c = make()
        type("tooi vieetj", composer: c)
        XCTAssertEqual(c.flush(), "việt")
        XCTAssertEqual(type("bus ", composer: c), "bus ")   // memory cleared
    }

    func testToneStyleSetting() {
        var s = ComposerSettings(); s.toneStyle = .old
        XCTAssertEqual(type("hoaf thuys ", composer: make(s)), "hòa thúy ")
        XCTAssertEqual(type("hoaf thuys "), "hoà thuý ")
    }

    // MARK: Chinese

    func testChineseBasics() {
        let o = out("ma3")
        XCTAssertEqual(o.marked, "ma3")
        XCTAssertEqual(o.candidates, ["马", "码", "蚂"])
        XCTAssertEqual(type("ma31"), "马")
        XCTAssertEqual(type("ma32"), "码")
        XCTAssertEqual(type("ma3 "), "马")
        XCTAssertEqual(type("ma5 "), "吗")
        XCTAssertEqual(type("nihao3 "), "你好")
        XCTAssertEqual(type("ni3hao3 "), "你好")
        XCTAssertEqual(type("ni3hao "), "你好")
        XCTAssertEqual(type("ma3\n"), "ma3")
        XCTAssertEqual(type("ma3⎋"), "ma3")
        XCTAssertEqual(type("ma "), "ma ")
        XCTAssertEqual(type("ma3,"), "马,")
        XCTAssertEqual(type("ma39"), "")              // no 9th candidate: ignored, still composing
        XCTAssertEqual(out("ma39").marked, "ma3")
    }

    func testChineseKeepsUpdating() {
        XCTAssertEqual(out("xiao4").candidates, ["小", "笑"])
        XCTAssertEqual(out("xiao4yang2shang").candidates, ["小羊上"])
        XCTAssertEqual(type("xiao4yang2shangshan "), "小羊上山")
        XCTAssertEqual(out("xiao4yang2⌫").candidates, ["小羊"])
        XCTAssertEqual(type("ma3⌫ "), "ma ")             // tone removed → back to Latin
    }

    func testChinesePartialConsume() {
        var o = ComposerOutput()
        let field = type("zhong1guo2ren2 ", composer: make(), last: &o)
        XCTAssertEqual(field, "中国")
        XCTAssertEqual(o.marked, "ren2")
        XCTAssertEqual(o.candidates, ["人", "仁"])
        XCTAssertEqual(type("zhong1guo2ren2  "), "中国人")
        XCTAssertEqual(type("zhong1guo2ren2 1"), "中国人")
        XCTAssertEqual(type("zhong1guo2ren2 2"), "中国仁")
        XCTAssertEqual(type("zhong1guo2ren22"), "中")   // picks 中 (6 chars), "guo2ren2" keeps composing
    }

    func testChinesePick() {
        let c = make()
        type("ma3", composer: c)
        let o = c.pick(1)
        XCTAssertEqual(o.commit, "码")
        XCTAssertEqual(o.candidates, [])
    }

    func testTraditional() {
        var s = ComposerSettings(); s.traditional = true
        XCTAssertEqual(out("ma3", composer: make(s)).candidates, ["馬", "碼", "螞"])
        XCTAssertEqual(type("ma3 ", composer: make(s)), "馬")
    }

    func testDigitsNotTones() {
        XCTAssertEqual(type("mp3 "), "mp3 ")
        XCTAssertEqual(type("iphone15 "), "iphone15 ")
        XCTAssertEqual(type("2026 "), "2026 ")
        XCTAssertEqual(type("abc6 "), "abc6 ")
        XCTAssertEqual(type("a9 "), "a9 ")
        XCTAssertEqual(type("ma6 "), "ma6 ")
        XCTAssertEqual(out("mp3").candidates, [])
        XCTAssertEqual(type("42"), "42")
    }

    func testChineseContextMemory() {
        XCTAssertEqual(type("ma3 bus "), "马bus ")
    }

    func testUppercase() {
        XCTAssertEqual(type("Hello VIEETJ Bus "), "Hello VIỆT Bú ")
        XCTAssertEqual(type("TOOI DDI BUS "), "TÔI ĐI BÚ ")
    }
}
