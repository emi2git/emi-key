import XCTest
@testable import EmiKeyCore

/// Composer wired to the real bundled data — the same setup the app uses.
final class RealEngineTests: XCTestCase {
    static let res = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources")
    static let pinyin = PinyinEngine(resources: res)
    static let english = EnglishWords(resources: res)

    func type(_ s: String, preceding: String? = nil) -> String {
        let c = Composer(telex: TelexEngine(), pinyin: Self.pinyin, english: Self.english, settings: .init(), learnedFile: nil)
        var field = preceding ?? ""
        for ch in s {
            let key: KeyInput = ch == " " ? .space : ch == "\n" ? .enter : ch == "⎋" ? .escape : ch == "⌫" ? .backspace : .char(ch)
            let out = c.handle(key, precedingText: preceding == nil ? nil : field)
            field.removeLast(min(c.lastDeleteCount, field.count))
            field += out.commit
            if !out.handled { if key == .enter { field += "\n" } else if key == .space { field += " " } else if case .char(let x) = key { field += String(x) } }
        }
        return field
    }

    func testCases() {
        let cases: [(String, String?, String)] = [
            ("hello world ", nil, "hello world "),
            ("I take the bus ", nil, "I take the bus "),
            ("cho con bus ", "", "cho con bú "),
            ("tooi ddi hocj ", nil, "tôi đi học "),
            ("Vieetj Nam ", nil, "Việt Nam "),
            ("nguowif ", nil, "người "),
            ("dduowngf ", nil, "đường "),
            ("class test git ", nil, "class test git "),
            ("ma ", nil, "ma "),
            ("ma31", nil, "马"),
            ("ma5 ", nil, "吗"),
            ("ni3hao ", nil, "你好"),
            ("nihao3 ", nil, "你好"),
            ("wo3 shi4 ", nil, "我是"),
            ("xiao4yang2shangshan ", nil, "小羊上山"),
            ("mp3 iphone15 2026 ", nil, "mp3 iphone15 2026 "),
            ("vieetj⎋ ", nil, "vieetj "),
            ("the bus ⎋", nil, "the bú "),
            ("has ", "I ", "I has "),
        ]
        var fails: [String] = []
        for (input, pre, want) in cases {
            let got = type(input, preceding: pre)
            let full = (pre ?? "")
            let expect = want.hasPrefix(full) ? want : full + want
            if got != expect { fails.append("\(input) → \(got) (want \(expect))") }
        }
        XCTAssert(fails.isEmpty, "\n" + fails.joined(separator: "\n"))
    }
}
