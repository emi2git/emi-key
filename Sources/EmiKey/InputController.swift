import Cocoa
import InputMethodKit
import EmiKeyCore
import os

let log = Logger(subsystem: AppState.bundleID, category: "input")

/// Direct insertion (like EVKey/OpenKey): the word being composed is real text in the document, never marked
/// (underlined) text. Each composer output becomes the minimal edit from what is shown to the new text.
@objc(EmiKeyInputController)
final class InputController: IMKInputController {
    private var state: AppState { .shared }
    private var composer: Composer { AppState.shared.composer }
    /// The in-progress word as it currently stands in the document, just before the cursor.
    private var shown = ""
    /// Where the cursor should be after our last edit (nil = unknown, or the app hides its text).
    private var caret: Int?
    private var lastLoc: Int?
    /// Marked-text mode for the current word: the app hides its text, so we could not replace what we inserted.
    /// Then (and only then) the word is shown as classic marked text.
    private var markedMode = false
    private var hasMarked = false

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    // MARK: keys

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        return process(event, client: client)
    }

    private func process(_ event: NSEvent, client: IMKTextInput) -> Bool {
        let key = Self.keyInput(event)
        let sel = client.selectedRange()
        let loc: Int? = sel.location == NSNotFound ? nil : sel.location
        // Cursor moved / clicked elsewhere / selection: the shown text simply stays; forget the word.
        if let c = caret, loc != c || sel.length != 0 {
            // The app's cursor did not move although we typed into it (e.g. Ghostty, some terminals and
            // Electron apps report a fixed location). It can't be edited in place: use marked text there from now on.
            if let l = loc, l == lastLoc, sel.length == 0, !shown.isEmpty { state.markUntracked(client.bundleIdentifier()) }
            reset()
        }
        lastLoc = loc
        if shown.isEmpty && !hasMarked {
            markedMode = state.isUntracked(client.bundleIdentifier()) || readable(client, loc) == false
        }
        var start = loc.map { $0 - shown.utf16.count }
        if markedMode, hasMarked, case let m = client.markedRange(), m.location != NSNotFound { start = m.location }
        let out = composer.handle(key, precedingText: precedingText(client, start))
        log.notice("key handled=\(out.handled, privacy: .public) delete=\(self.composer.deleteCount, privacy: .public) marked=\(self.markedMode, privacy: .public)")
        return apply(out, client: client, event: event, key: key)
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

    /// Up to 200 characters before `start` (the start of the shown word). nil when the app does not expose its text.
    private func precedingText(_ client: IMKTextInput, _ start: Int?) -> String? {
        guard let start, start >= 0, !state.forceHidden else { return nil }
        if start == 0 { return "" }
        let from = max(0, start - 200)
        return client.attributedSubstring(from: NSRange(location: from, length: start - from))?.string
    }

    /// Does the app let us read its text around `loc`? (nil = cannot tell, e.g. at the very start.)
    private func readable(_ client: IMKTextInput, _ loc: Int?) -> Bool? {
        guard let loc, !state.forceHidden else { return false }
        if loc == 0 { return nil }
        return client.attributedSubstring(from: NSRange(location: loc - 1, length: 1)) != nil
    }

    // MARK: output

    /// Turns a composer output into an edit of the document. Returns whether the key was consumed.
    @discardableResult
    private func apply(_ out: ComposerOutput, client: IMKTextInput, event: NSEvent? = nil, key: KeyInput? = nil) -> Bool {
        defer { updateCandidates(out.candidates, client: client) }
        if markedMode { return applyMarked(out, client: client) }
        let sel = client.selectedRange()
        let loc: Int? = sel.location == NSNotFound ? nil : sel.location
        let canRead = readable(client, loc) == true
        let n = composer.lastDeleteCount, nU16 = composer.lastDeleteUTF16Count
        let target = out.commit + out.marked

        // Old text being replaced: `n` committed characters (Esc flip) + the shown word. nil = unknown.
        var old: String? = shown
        if n > 0 {
            old = nil
            if canRead, let loc, case let s = loc - shown.utf16.count - nU16, s >= 0,
               let d = client.attributedSubstring(from: NSRange(location: s, length: nU16))?.string, d.utf16.count == nU16 {
                old = d + shown
            }
        }
        let common = old.map { Self.commonPrefix($0, target) } ?? 0
        let del = old.map { String($0.dropFirst(common)) }         // nil: unknown text, n + shown chars
        let delCount = del?.count ?? (n + shown.count)
        let ins = String(target.dropFirst(common))
        let newShown = out.marked
        func expect(_ c: Int?) { caret = canRead && out.handled ? c : nil }

        // Let the app handle the key natively when that gives exactly the new text (autocorrect, key repeat).
        if let event, let key {
            let chars = event.characters ?? ""
            var pass = false, caretAfter: Int? = nil
            var textKey = key == .space
            if case .char = key { textKey = true }
            if out.handled, textKey, delCount == 0, !ins.isEmpty, ins == chars {
                pass = true; caretAfter = loc.map { $0 + chars.utf16.count }
            } else if out.handled, key == .backspace, ins.isEmpty, delCount == 1, let del {
                pass = true; caretAfter = loc.map { $0 - del.utf16.count }
            } else if !out.handled, delCount == 0, ins.isEmpty {
                pass = true
            }
            if pass {
                shown = newShown
                if out.handled { expect(caretAfter) } else { caret = nil }
                return false
            }
        }

        let none = NSRange(location: NSNotFound, length: 0)
        if delCount == 0 {
            if !ins.isEmpty { client.insertText(ins, replacementRange: none) }
            expect(loc.map { $0 + ins.utf16.count })
        } else if let del, let loc, canRead, loc >= del.utf16.count,
                  case let r = NSRange(location: loc - del.utf16.count, length: del.utf16.count),
                  client.attributedSubstring(from: r)?.string == del {
            client.insertText(ins, replacementRange: r)
            expect(r.location + ins.utf16.count)
        } else {
            // Could not verify the text (rare: word started where the app's text was unreadable). Best effort:
            // replace by range if we know the cursor, else just append.
            caret = nil
            if let del, let loc, loc >= del.utf16.count {
                client.insertText(ins, replacementRange: NSRange(location: loc - del.utf16.count, length: del.utf16.count))
            } else {
                client.insertText(ins, replacementRange: none)
            }
        }
        shown = newShown
        return out.handled
    }

    /// Classic IMK composition (underlined) for apps where direct editing is impossible.
    private func applyMarked(_ out: ComposerOutput, client: IMKTextInput) -> Bool {
        let none = NSRange(location: NSNotFound, length: 0)
        let nU16 = composer.lastDeleteUTF16Count
        if nU16 > 0 {
            // Esc flip of a committed word: only possible if the app lets us address it.
            let m = client.markedRange(), sel = client.selectedRange()
            let loc = hasMarked && m.location != NSNotFound ? m.location : sel.location
            guard loc != NSNotFound, loc >= nU16 else { return out.handled }
            client.insertText(out.commit, replacementRange: NSRange(location: loc - nU16, length: nU16 + (hasMarked ? m.length : 0)))
            hasMarked = false
        } else if !out.commit.isEmpty {
            client.insertText(out.commit, replacementRange: none)
            hasMarked = false
        }
        if !out.marked.isEmpty || hasMarked {
            let a = NSAttributedString(string: out.marked, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue, .markedClauseSegment: 0])
            client.setMarkedText(a, selectionRange: NSRange(location: (out.marked as NSString).length, length: 0), replacementRange: none)
            hasMarked = !out.marked.isEmpty
        }
        caret = nil
        return out.handled
    }

    /// Common prefix length in Characters.
    static func commonPrefix(_ a: String, _ b: String) -> Int {
        var n = 0
        for (x, y) in zip(a, b) { if x != y { break }; n += 1 }
        return n
    }

    private func updateCandidates(_ cands: [String], client: IMKTextInput) {
        guard !cands.isEmpty else { CandidateWindow.shared.hide(); return }
        // Bar sits under the start of the in-progress word (it is plain text now, not marked text).
        let sel = client.selectedRange()
        let start = sel.location == NSNotFound ? 0 : max(0, sel.location - shown.utf16.count)
        // Caret line rect (reliable height), moved left to the word's first character.
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        var actual = NSRange()
        let first = client.firstRect(forCharacterRange: NSRange(location: start, length: shown.isEmpty ? 0 : 1), actualRange: &actual)
        if first != .zero, first.minX <= rect.minX, rect.minX - first.minX < 2000 { rect.origin.x = first.minX }
        CandidateWindow.shared.onPick = { [weak self] i in self?.pick(i) }
        CandidateWindow.shared.show(cands, under: rect)
    }

    private func pick(_ i: Int) {
        guard let client = client() else { return }
        apply(composer.pick(i), client: client)
    }

    // MARK: lifecycle

    /// Forget the word being composed. Its text is already in the document, so nothing is inserted
    /// (except in marked-text mode, where the marked word is committed as it stands).
    private func reset(_ sender: Any? = nil) {
        let text = composer.flush()
        if hasMarked, let client = (sender as? IMKTextInput) ?? client() {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        hasMarked = false
        shown = ""
        caret = nil
        CandidateWindow.shared.hide()
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        state.forceHidden = state.defaults.bool(forKey: "ForceHidden")
        reset()
    }

    override func deactivateServer(_ sender: Any!) {
        reset(sender)
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
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
