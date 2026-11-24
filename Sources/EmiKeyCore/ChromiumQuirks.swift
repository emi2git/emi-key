import Foundation

/// Chromium deactivates the input method right after the first key in a newly focused field and re-activates it
/// at once — often on a **new** input controller (a new client proxy for the same field). The word typed so far is
/// already plain text in the document, so it must survive that blip: the deactivating controller stashes its
/// per-word state here, and whichever controller activates next for the same app adopts it.
public struct FocusBlip<State> {
    /// How long a stashed word waits for the re-activation (the blip takes a few milliseconds).
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

    /// First key after adopting a word: is it still the text just before the cursor? `before` = the text the app
    /// reports before the cursor (nil = unreadable). Only a clear mismatch says no: text that is shorter than the
    /// word (Chromium's text can lag behind our last insert) or unreadable keeps the word.
    public static func wordStillThere(before: String?, shown: String) -> Bool {
        guard let before, before.count >= shown.count else { return true }
        return before.hasSuffix(shown)
    }
}

/// Chromium updates the selection it reports asynchronously: the key right after an edit may still see the cursor
/// where it was *before* that edit (`wo3` → 我 moves it from 3 to 1, the next key reports 3). Read as a cursor move,
/// that would end the word being typed. A cursor reported exactly at the previous key's location, when our edit
/// should have moved it, is that lag — trust our own record, once: a second time in a row it is an app whose
/// reported cursor never moves (see `markUntracked`).
public enum SelectionLag {
    public static func isLag(reported: Int?, expected: Int?, previous: Int?, lastWasLag: Bool) -> Bool {
        guard !lastWasLag, let r = reported, let e = expected, let p = previous else { return false }
        return r != e && r == p && p != e
    }
}
