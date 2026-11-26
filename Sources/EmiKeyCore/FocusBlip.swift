import Foundation

/// Chromium deactivates the input method right after the first key in a newly focused field and re-activates it
/// at once — often on a **new** input controller. Deactivation commits the word being composed (that is the right
/// thing for a real focus change), so the deactivating controller parks the composer's draft here, and whichever
/// controller activates next for the same app within `window` resumes it — if the committed word is still the text
/// just before the cursor (then it becomes marked text again).
public struct FocusBlip<State> {
    /// How long a parked word waits for the re-activation (the blip takes a few milliseconds).
    public static var window: TimeInterval { 0.5 }

    private var stash: (bundle: String?, time: Date, state: State)?

    public init() {}

    public mutating func park(_ state: State, bundle: String?, at time: Date = Date()) {
        stash = (bundle, time, state)
    }

    /// The parked state when this activation is the blip's second half (same app, within `window`); always clears.
    public mutating func take(bundle: String?, at time: Date = Date()) -> State? {
        defer { stash = nil }
        guard let s = stash, s.bundle == bundle, time.timeIntervalSince(s.time) >= 0,
              time.timeIntervalSince(s.time) < Self.window else { return nil }
        return s.state
    }

    public mutating func clear() { stash = nil }

    /// May the committed `word` be taken back into the composition? Only when the app shows it just before the
    /// cursor (`before`, nil = unreadable): anything else leaves the committed text alone.
    public static func wordStillThere(before: String?, word: String) -> Bool {
        guard let before, !word.isEmpty else { return false }
        return before.hasSuffix(word)
    }
}
