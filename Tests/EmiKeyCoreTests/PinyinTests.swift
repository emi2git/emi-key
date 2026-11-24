import XCTest
@testable import EmiKeyCore

final class PinyinTests: XCTestCase {
    static let engine = PinyinEngine(resources: EnglishTests.resources)
    var p: PinyinEngine { Self.engine }

    func texts(_ s: String, trad: Bool = false, limit: Int = 9) -> [String] {
        p.candidates(for: s, traditional: trad, limit: limit).map(\.text)
    }

    func testLoad() {
        let e = PinyinEngine(resources: EnglishTests.resources)
        print("pinyin load: \(String(format: "%.1f", e.loadMillis)) ms, \(e.entryCount) entries, \(e.syllableCount) syllables")
        XCTAssertGreaterThan(e.entryCount, 100_000)
        XCTAssertLessThan(e.loadMillis, 300)
    }

    func testSegments() {
        for s in ["nihao", "xian", "ma", "shangshan", "xiaoyang", "lv"] { XCTAssertTrue(p.segmentsAsPinyin(s), s) }
        for s in ["mp", "iphone", "class", "", "m", "ng", "r", "test"] { XCTAssertFalse(p.segmentsAsPinyin(s), s) }
    }

    func testSingleSyllables() {
        let ma3 = texts("ma3")
        XCTAssertEqual(ma3.first, "马")
        XCTAssertEqual(ma3.dropFirst().first, "码")
        XCTAssertEqual(texts("ma5").first, "吗")
        XCTAssertEqual(texts("ma0").first, "吗")
        XCTAssertEqual(texts("wo3").first, "我")
        XCTAssertEqual(texts("shi4").first, "是")
    }

    func testPhrases() {
        for s in ["nihao3", "ni3hao3", "ni3hao", "nihao"] { XCTAssertEqual(texts(s).first, "你好", s) }
        XCTAssertTrue(texts("nihao4").contains("你好"))
        let c = p.candidates(for: "ni3hao3", traditional: false, limit: 9)
        XCTAssertEqual(c.first?.consumed, 7)
    }

    func testComposition() {
        let t = texts("xiao4yang2shangshan")
        XCTAssertTrue(t.prefix(5).contains("小羊上山"), "\(t)")
        XCTAssertTrue(texts("xiao3yang2shang4shan1").prefix(2).contains("小羊上山"))
    }

    func testPrefixCandidates() {
        let input = "xiao4yang2shangshan"
        let c = p.candidates(for: input, traditional: false, limit: 12)
        let partial = c.filter { $0.consumed < input.count }
        XCTAssertFalse(partial.isEmpty)
        XCTAssertTrue(partial.contains { $0.consumed == 5 }, "first-syllable candidates")   // "xiao4"
        XCTAssertEqual(Set(c.map(\.text)).count, c.count, "deduplicated")
        XCTAssertLessThanOrEqual(p.candidates(for: input, traditional: false, limit: 3).count, 3)
    }

    func testAmbiguousSegmentation() {
        XCTAssertTrue(texts("xian1", limit: 20).contains("先"))
        XCTAssertTrue(texts("xian", limit: 20).contains("西安"))
        XCTAssertEqual(texts("xi1an1").first, "西安")
    }

    func testTraditional() {
        XCTAssertEqual(texts("ma3", trad: true).first, "馬")
        XCTAssertEqual(texts("ma5", trad: true).first, "嗎")
    }

    func testRejects() {
        XCTAssertTrue(texts("mp3").isEmpty)
        XCTAssertTrue(texts("2026").isEmpty)
        XCTAssertTrue(p.candidates(for: "ma3", traditional: false, limit: 0).isEmpty)
    }

    func testSpeed() {
        let inputs = ["xiao4yang2shangshan", "wo3ai4bei3jing1tian1an1men2", "zhong1hua2ren2min2gong4he2guo2", "nihaoshijie"]
        for s in inputs { _ = p.candidates(for: s, traditional: false, limit: 9) }
        let t0 = Date()
        let rounds = 20
        for _ in 0..<rounds { for s in inputs { _ = p.candidates(for: s, traditional: false, limit: 9) } }
        let ms = Date().timeIntervalSince(t0) * 1000 / Double(rounds * inputs.count)
        print("pinyin candidates: \(String(format: "%.2f", ms)) ms per call (6-7 syllables)")
        XCTAssertLessThan(ms, 20)
    }
}
