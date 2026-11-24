import XCTest
@testable import EmiKeyCore

final class ContextTests: XCTestCase {
    let d = ContextDetector(english: FakeEnglish())

    func testBasics() {
        XCTAssertNil(d.detect(""))
        XCTAssertNil(d.detect("   \n "))
        XCTAssertEqual(d.detect("Mẹ đưa cho con "), .vi)
        XCTAssertEqual(d.detect("I take the "), .en)
        XCTAssertEqual(d.detect("我爱你 "), .zh)
        XCTAssertEqual(d.detect("tôi đi "), .vi)
        XCTAssertEqual(d.detect("hello my "), .en)
    }

    func testRecentWordsWeighMost() {
        XCTAssertEqual(d.detect("tôi đi học. I take the test so "), .en)
        XCTAssertEqual(d.detect("I take the test, rồi tôi đi "), .vi)
    }

    func testOnlyLastWordsCount() {
        let long = String(repeating: "hello my test ", count: 50) + "hôm nay tôi đi chợ với mẹ "
        XCTAssertEqual(d.detect(long), .vi)
    }

    func testEarlierLineCountsWhenCurrentEmpty() {
        XCTAssertEqual(d.detect("tôi đi học\n"), .vi)
        XCTAssertEqual(d.detect("tôi đi học\nhello my "), .en)
    }
}
