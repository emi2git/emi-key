import XCTest
@testable import EmiKeyCore

final class ChromiumQuirksTests: XCTestCase {
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
        XCTAssertTrue(FocusBlip<String>.wordStillThere(before: "a", shown: "a"))
        XCTAssertTrue(FocusBlip<String>.wordStillThere(before: "ư", shown: "ư"))
        XCTAssertTrue(FocusBlip<String>.wordStillThere(before: nil, shown: "a"), "unreadable: trust our record")
        XCTAssertTrue(FocusBlip<String>.wordStillThere(before: "", shown: "ư"), "lagging text: trust our record")
        XCTAssertFalse(FocusBlip<String>.wordStillThere(before: "x", shown: "a"), "another field / text: forget")
    }


    func testSelectionLagAfterShrinkingReplacement() {
        // `wo3 ` → 我: we expect the cursor at 1, Chromium still reports 3 (where it was before the edit).
        XCTAssertTrue(SelectionLag.isLag(reported: 3, expected: 1, previous: 3, lastWasLag: false))
        // Only once in a row: an app whose cursor never moves keeps reporting the same place.
        XCTAssertFalse(SelectionLag.isLag(reported: 3, expected: 1, previous: 3, lastWasLag: true))
    }

    func testRealCursorMovesAreNoLag() {
        XCTAssertFalse(SelectionLag.isLag(reported: 7, expected: 4, previous: 3, lastWasLag: false), "click elsewhere")
        XCTAssertFalse(SelectionLag.isLag(reported: 4, expected: 4, previous: 3, lastWasLag: false), "in step")
        XCTAssertFalse(SelectionLag.isLag(reported: 3, expected: 3, previous: 3, lastWasLag: false))
        XCTAssertFalse(SelectionLag.isLag(reported: nil, expected: 1, previous: 3, lastWasLag: false))
        XCTAssertFalse(SelectionLag.isLag(reported: 3, expected: nil, previous: 3, lastWasLag: false), "nothing expected")
    }
}
