import XCTest
@testable import EmiKeyCore

final class FocusBlipTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testBlipHandsTheWordToTheNextActivation() {
        // Chromium: first key "a", deactivate, activate (often a new controller) 1 ms later.
        var b = FocusBlip<String>()
        b.park("a", bundle: "com.google.Chrome", at: t0)
        XCTAssertEqual(b.take(bundle: "com.google.Chrome", at: t0.addingTimeInterval(0.001)), "a")
        XCTAssertNil(b.take(bundle: "com.google.Chrome", at: t0.addingTimeInterval(0.002)), "taken only once")
    }

    func testOtherAppOrLateActivationStartsOver() {
        var b = FocusBlip<String>()
        b.park("a", bundle: "com.google.Chrome", at: t0)
        XCTAssertNil(b.take(bundle: "com.apple.TextEdit", at: t0.addingTimeInterval(0.01)))
        b.park("a", bundle: "com.google.Chrome", at: t0)
        XCTAssertNil(b.take(bundle: "com.google.Chrome", at: t0.addingTimeInterval(2)))
        b.park("a", bundle: "com.google.Chrome", at: t0)
        b.clear()
        XCTAssertNil(b.take(bundle: "com.google.Chrome", at: t0))
    }

    func testWordStillThere() {
        XCTAssertTrue(FocusBlip<String>.wordStillThere(before: "a", word: "a"))
        XCTAssertTrue(FocusBlip<String>.wordStillThere(before: "the ư", word: "ư"))
        XCTAssertFalse(FocusBlip<String>.wordStillThere(before: nil, word: "a"), "unreadable: leave it committed")
        XCTAssertFalse(FocusBlip<String>.wordStillThere(before: "", word: "ư"), "not there (yet): leave it")
        XCTAssertFalse(FocusBlip<String>.wordStillThere(before: "x", word: "a"), "another field / text")
        XCTAssertFalse(FocusBlip<String>.wordStillThere(before: "abc", word: ""))
    }
}
