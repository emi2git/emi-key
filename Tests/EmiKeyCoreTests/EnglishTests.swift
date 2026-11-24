import XCTest
@testable import EmiKeyCore

final class EnglishTests: XCTestCase {
    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")

    func testWords() {
        let en = EnglishWords(resources: Self.resources)
        XCTAssertGreaterThan(en.count, 10_000)
        XCTAssertTrue(en.isWord("hello"))
        XCTAssertTrue(en.isWord("Hello"))
        XCTAssertTrue(en.isWord("CLASS"))
        XCTAssertFalse(en.isWord("qzxv"))
        XCTAssertFalse(en.isWord(""))
    }
}
