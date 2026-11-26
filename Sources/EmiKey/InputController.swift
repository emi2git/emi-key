import Cocoa
import InputMethodKit
import EmiKeyCore
import os

let log = Logger(subsystem: AppState.bundleID, category: "input")

/// Classic IMK composition in every app: the word being composed is underlined marked text; it becomes plain text
/// when it is committed (Space, punctuation, Enter, Tab, arrows, a click, a focus change).
@objc(EmiKeyInputController)
final class InputController: IMKInputController {
    private var state: AppState { .shared }
    private var composer: Composer { AppState.shared.composer }
    /// This controller has put marked text into the client.
    private var hasMarked = false
    /// A word committed by Chromium's deactivate/activate blip, to be taken back into the composition (see FocusBlip).
    private var resumable: Draft?
    /// The client text the next edit replaces instead of inserting (the resumed word).
    private var replacing: NSRange?

    private static let none = NSRange(location: NSNotFound, length: 0)

    private func dbg(_ msg: @autoclosure () -> String) {
        if state.debug { let m = msg(); log.notice("dbg \(m, privacy: .public)") }
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    // MARK: keys

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard state.ready, let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        return process(event, client: client)
    }

    private func process(_ event: NSEvent, client: IMKTextInput) -> Bool {
        let typed = Self.keyInput(event)
        var key = typed
        let id = client.bundleIdentifier()
        dbg("key=\(String(describing: key)) app=\(id ?? "?") sel=\(client.selectedRange()) marked=\(client.markedRange()) has=\(hasMarked)")
        if let r = resumable { resumable = nil; resume(r, client: client) }
        // Terminals: Esc belongs to the program (vim leaves insert mode, readline's Meta prefix) — never a flip.
        if key == .escape, state.isTerminal(id) { key = .other }
        // Esc right after a committed word flips it — only when the app shows that word just before the cursor.
        if key == .escape, !hasMarked, let old = composer.flipText, !committedTextBeforeCursor(old, client: client) {
            key = .other
        }
        let out = composer.handle(key, precedingText: precedingText(client))
        if state.keyLog || state.debug {
            log.notice("key handled=\(out.handled, privacy: .public) delete=\(self.composer.lastDeleteUTF16Count, privacy: .public) marked=true")
        }
        return apply(out, client: client, typed: typed)
    }

    static func keyInput(_ e: NSEvent) -> KeyInput {
        if !e.modifierFlags.intersection([.command, .control, .option]).isEmpty { return .other }
        switch e.keyCode {
        case 53: return .escape
        case 51: return .backspace
        case 36, 76: return .enter
        case 49: return .space
        case 48: return .tab
        case 117, 115, 119, 116, 121, 123, 124, 125, 126: return .other   // fwd-delete, home/end, page, arrows
        default: break
        }
        guard let chars = e.characters, chars.count == 1, let c = chars.first else { return .other }
        if let u = c.unicodeScalars.first, (0xF700...0xF8FF).contains(u.value) || u.value < 0x20 || u.value == 0x7F { return .other }
        return .char(c)
    }

    /// Where the composition starts (or the cursor, when nothing is marked). nil = the app does not say.
    private func compositionStart(_ client: IMKTextInput) -> Int? {
        if let r = replacing { return r.location }
        let m = client.markedRange()
        if hasMarked, m.location != NSNotFound { return m.location }
        let s = client.selectedRange()
        return s.location == NSNotFound ? nil : s.location
    }

    /// Up to 200 characters before the composition. nil = unknown (the composer then uses its own word memory).
    private func precedingText(_ client: IMKTextInput) -> String? {
        guard state.readsContext(client.bundleIdentifier()), let start = compositionStart(client) else { return nil }
        if start == 0 { return "" }
        let from = max(0, start - 200)
        return client.attributedSubstring(from: NSRange(location: from, length: start - from))?.string
    }

    /// Is `text` (a committed word + its separator) exactly what the app shows just before the cursor?
    private func committedTextBeforeCursor(_ text: String, client: IMKTextInput) -> Bool {
        guard state.readsContext(client.bundleIdentifier()) else { return false }
        let sel = client.selectedRange(), n = text.utf16.count
        guard sel.location != NSNotFound, sel.length == 0, sel.location >= n else { return false }
        return client.attributedSubstring(from: NSRange(location: sel.location - n, length: n))?.string == text
    }

    // MARK: output

    /// Turns a composer output into client edits. Returns whether the key was consumed.
    @discardableResult
    private func apply(_ out: ComposerOutput, client: IMKTextInput, typed: KeyInput? = nil) -> Bool {
        defer { updateCandidates(out.candidates, client: client) }
        let target = replacing ?? Self.none
        replacing = nil
        // Terminals treat a key that ends a composition as part of it and drop it (or send the committed text in its
        // place): Enter would be lost. Send the key's own character together with the committed word instead.
        if !out.handled, !out.commit.isEmpty, state.isTerminal(client.bundleIdentifier()),
           let k = typed, let ch = k == .enter ? "\r" : k == .tab ? "\t" : k == .escape ? "\u{1b}" : nil {
            client.insertText(out.commit + ch, replacementRange: target)
            hasMarked = false
            return true
        }
        let nU16 = composer.lastDeleteUTF16Count
        if nU16 > 0 {
            // Esc flip of the committed word just before the cursor (checked in `process`).
            let sel = client.selectedRange()
            guard sel.location != NSNotFound, sel.location >= nU16 else { return out.handled }
            client.insertText(out.commit, replacementRange: NSRange(location: sel.location - nU16, length: nU16))
            hasMarked = false
        } else if !out.commit.isEmpty || target.location != NSNotFound && out.marked.isEmpty {
            // Committing replaces the marked text (or the resumed word); an empty commit just clears it.
            client.insertText(out.commit, replacementRange: target)
            hasMarked = false
        }
        if !out.marked.isEmpty || hasMarked {
            let a = NSAttributedString(string: out.marked, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue, .markedClauseSegment: 0])
            client.setMarkedText(a, selectionRange: NSRange(location: (out.marked as NSString).length, length: 0),
                                 replacementRange: out.commit.isEmpty ? target : Self.none)
            hasMarked = !out.marked.isEmpty
        }
        // Enter, Tab, arrows, shortcuts: the word is committed as shown and the app gets the key on this same press.
        return out.handled
    }

    private func updateCandidates(_ cands: [String], client: IMKTextInput) {
        guard !cands.isEmpty else { CandidateWindow.shared.hide(); return }
        // Bar sits under the first character of the composition (caret line rect for a reliable height).
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        let m = client.markedRange()
        if m.location != NSNotFound, m.length > 0 {
            var actual = NSRange()
            let first = client.firstRect(forCharacterRange: NSRange(location: m.location, length: 1), actualRange: &actual)
            if first != .zero, first.minX <= rect.minX, rect.minX - first.minX < 2000 { rect.origin.x = first.minX }
        }
        CandidateWindow.shared.onPick = { [weak self] i in self?.pick(i) }
        CandidateWindow.shared.show(cands, under: rect)
    }

    private func pick(_ i: Int) {
        guard let client = client() else { return }
        apply(composer.pick(i), client: client)
    }

    // MARK: lifecycle

    /// Commit the word being composed as it stands (click elsewhere, focus change, app switch).
    /// Returns what was committed.
    @discardableResult
    private func reset(_ sender: Any? = nil) -> String {
        let text = composer.flush()
        if hasMarked, let client = (sender as? IMKTextInput) ?? client() {
            client.insertText(text, replacementRange: Self.none)
        }
        hasMarked = false
        resumable = nil
        replacing = nil
        CandidateWindow.shared.hide()
        return text
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        state.debug = state.defaults.bool(forKey: "DebugLog")
        state.keyLog = state.defaults.bool(forKey: "KeyLog")
        let id = (sender as? IMKTextInput)?.bundleIdentifier()
        dbg("activate \(id ?? "?") ctl=\(ObjectIdentifier(self).hashValue)")
        reset()
        // Chromium deactivates and re-activates the input method right after the first key in a newly focused field,
        // often on a new controller: the word deactivation committed may be resumed on the next key.
        resumable = Self.blip.take(bundle: id)
    }

    /// The word committed on deactivation (`committed`) and the composer's draft of it.
    private struct Draft { var committed: String; var draft: Composer.Draft }
    private static var blip = FocusBlip<Draft>()

    /// Next key after the blip: the committed word becomes the composition again if it is still just before the cursor.
    private func resume(_ r: Draft, client: IMKTextInput) {
        let sel = client.selectedRange(), n = r.committed.utf16.count
        guard state.readsContext(client.bundleIdentifier()), sel.location != NSNotFound, sel.length == 0, sel.location >= n,
              FocusBlip<Draft>.wordStillThere(before: client.attributedSubstring(from: NSRange(location: sel.location - n, length: n))?.string,
                                              word: r.committed) else {
            dbg("blip word not resumed")
            return
        }
        composer.resume(r.draft)
        replacing = NSRange(location: sel.location - n, length: n)
        dbg("blip word resumed")
    }

    override func deactivateServer(_ sender: Any!) {
        let id = (sender as? IMKTextInput)?.bundleIdentifier()
        dbg("deactivate \(id ?? "?") ctl=\(ObjectIdentifier(self).hashValue)")
        let draft = hasMarked ? composer.draft : nil
        let committed = reset(sender)
        if let draft, !committed.isEmpty { Self.blip.park(Draft(committed: committed, draft: draft), bundle: id) } else { Self.blip.clear() }
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        dbg("commitComposition ctl=\(ObjectIdentifier(self).hashValue)")
        reset(sender)
    }

    // MARK: menu

    override func menu() -> NSMenu! {
        let m = NSMenu(title: "Emi Key")
        func add(_ title: String, _ sel: Selector, on: Bool) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            it.state = on ? .on : .off
            m.addItem(it)
        }
        add("Traditional Chinese", #selector(toggleTraditional(_:)), on: state.traditional)
        add("Old tone style (hòa)", #selector(toggleOldTone(_:)), on: state.toneStyle == .old)
        return m
    }

    @objc func toggleTraditional(_ sender: Any?) { state.traditional.toggle() }
    @objc func toggleOldTone(_ sender: Any?) { state.toneStyle = state.toneStyle == .old ? .new : .old }
}
