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
    /// "Blind" app (see AppState.isBlind): trust `caret` and `shadow` over what the app reports.
    private var blind = false
    /// Blind apps: the text Emi Key knows is just before `caret` (what it typed since tracking began).
    private var shadow = ""
    private var lastReported: Int?
    /// Where the cursor should be after our last edit even when the text could not be read (see `caret`).
    private var guess: Int?
    /// No key handled yet since the text field gained focus.
    private var freshField = true

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
        let key = Self.keyInput(event)
        let sel = client.selectedRange()
        if state.debug {
            let around = sel.location == NSNotFound ? nil : client.attributedSubstring(from: NSRange(location: max(0, sel.location - 12), length: min(12, sel.location)))?.string
            log.notice("dbg key=\(String(describing: key), privacy: .public) app=\(client.bundleIdentifier() ?? "?", privacy: .public) sel=\(sel.location, privacy: .public),\(sel.length, privacy: .public) caret=\(self.caret.map(String.init) ?? "nil", privacy: .public) shown=\(self.shown, privacy: .public) before=\(around ?? "<nil>", privacy: .public) marked=\(client.markedRange().location, privacy: .public)")
        }
        blind = state.isBlind(client.bundleIdentifier()) && !state.forceHidden
        if blind {
            // Terminal.app handles Backspace/Esc itself (they never reach us) while nothing is marked. Its cursor
            // drifts forward on some letters but only goes back when text was deleted: then forget the word.
            let r = sel.location == NSNotFound ? nil : sel.location
            if caret != nil, let r, let last = lastReported, r < last { reset() }
            lastReported = r
        }
        let loc = cursor(client)
        // Cursor moved / clicked elsewhere / selection: the shown text simply stays; forget the word.
        // A selection that starts right at our cursor is the app's inline autocomplete (Chrome's address bar,
        // Spotlight, search fields): the word is still ours.
        if let c = caret, loc != c {
            // The app's cursor did not move although we typed into it (e.g. Ghostty, some terminals and
            // Electron apps report a fixed location). It can't be edited in place: use marked text there from now on.
            if let l = loc, l == lastLoc, sel.length == 0, !shown.isEmpty { state.markUntracked(client.bundleIdentifier()) }
            reset()
        }
        lastLoc = loc
        // The app's text was unreadable after the last key (word began at the very start of the field), so `caret`
        // is unknown — but where the cursor should be is known: if it is elsewhere now (a click), forget the word.
        if caret == nil, let g = guess, !shown.isEmpty, !markedMode, !blind, let l = loc, l != g { reset() }
        guess = nil
        if shown.isEmpty && !hasMarked {
            // Right after a field gains focus Chromium may not have told macOS where the cursor is yet
            // (selectedRange = NotFound for the first key). That says nothing about the app: stay direct.
            let settling = loc == nil && freshField && !state.forceHidden
            markedMode = state.isUntracked(client.bundleIdentifier()) || (!settling && readable(client, loc) == false)
        }
        freshField = false
        var start = loc.map { $0 - shown.utf16.count }
        if markedMode, hasMarked, case let m = client.markedRange(), m.location != NSNotFound { start = m.location }
        let out = composer.handle(key, precedingText: precedingText(client, start))
        if state.keyLog || state.debug {
            log.notice("key handled=\(out.handled, privacy: .public) delete=\(self.composer.deleteCount, privacy: .public) marked=\(self.markedMode, privacy: .public)")
        }
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

    /// Replace `r` (just before the cursor) by `s`. Pty apps get DEL × length + text instead.
    private func edit(_ client: IMKTextInput, _ s: String, _ r: NSRange, deleting: String?) {
        if state.isPty(client.bundleIdentifier()) {
            let n = deleting?.count ?? 0
            client.insertText(String(repeating: "\u{7F}", count: n) + s, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            client.insertText(s, replacementRange: r)
        }
    }

    /// Where the cursor is: the app's answer, or for blind apps our own record once we have one.
    private func cursor(_ client: IMKTextInput) -> Int? {
        if blind, let c = caret { return c }
        let l = client.selectedRange().location
        if blind, caret == nil { shadow = "" }
        // Blind apps only edit relative to the cursor; when Terminal does not say where it is, any origin will do.
        if blind, l == NSNotFound { return 1 << 20 }
        return l == NSNotFound ? nil : l
    }

    /// Text in `r`. Blind apps: only what we typed (the shadow, which ends at `caret`), clipped to it.
    private func text(_ client: IMKTextInput, _ r: NSRange) -> String? {
        guard blind else { return client.attributedSubstring(from: r)?.string }
        guard let c = caret ?? cursor(client) else { return nil }
        let u = Array(shadow.utf16), from = c - u.count
        let lo = max(r.location, from), hi = min(r.location + r.length, c)
        if r.length == 0 || r.location + r.length > c { return r.length == 0 ? "" : nil }
        if lo >= hi { return "" }
        return String(decoding: u[(lo - from)..<(hi - from)], as: UTF16.self)
    }

    /// Up to 200 characters before `start` (the start of the shown word). nil when the app does not expose its text.
    private func precedingText(_ client: IMKTextInput, _ start: Int?) -> String? {
        guard let start, start >= 0, !state.forceHidden else { return nil }
        if start == 0 { return "" }
        let from = max(0, start - 200)
        return text(client, NSRange(location: from, length: start - from))
    }

    /// Does the app let us read its text around `loc`? (nil = cannot tell, e.g. at the very start.)
    private func readable(_ client: IMKTextInput, _ loc: Int?) -> Bool? {
        guard let loc, !state.forceHidden else { return false }
        if blind { return true }
        if loc == 0 { return nil }
        return client.attributedSubstring(from: NSRange(location: loc - 1, length: 1)) != nil
    }

    // MARK: output

    /// Turns a composer output into an edit of the document. Returns whether the key was consumed.
    @discardableResult
    private func apply(_ out: ComposerOutput, client: IMKTextInput, event: NSEvent? = nil, key: KeyInput? = nil) -> Bool {
        defer { updateCandidates(out.candidates, client: client) }
        if markedMode { return applyMarked(out, client: client, key: key) }
        let loc = cursor(client)
        let canRead = readable(client, loc) == true
        let n = composer.lastDeleteCount, nU16 = composer.lastDeleteUTF16Count
        let target = out.commit + out.marked

        // Old text being replaced: `n` committed characters (Esc flip) + the shown word. nil = unknown.
        var old: String? = shown
        if n > 0 {
            old = nil
            if canRead, let loc, case let s = loc - shown.utf16.count - nU16, s >= 0,
               let d = text(client, NSRange(location: s, length: nU16)), d.utf16.count == nU16 {
                old = d + shown
            }
        }
        let common = old.map { Self.commonPrefix($0, target) } ?? 0
        let del = old.map { String($0.dropFirst(common)) }         // nil: unknown text, n + shown chars
        let delCount = del?.count ?? (n + shown.count)
        let ins = String(target.dropFirst(common))
        let newShown = out.marked
        func expect(_ c: Int?) { caret = canRead && out.handled ? c : nil; guess = out.handled ? c : nil }
        // Blind apps: keep our record of the text before the cursor in step with the edit.
        let oldChars = old?.count ?? (n + shown.count)
        defer {
            if blind {
                if out.handled || delCount > 0 || !ins.isEmpty { shadow = String(shadow.dropLast(oldChars)) + target }
                if !out.handled {
                    switch key {
                    case .space?: shadow += " "; caret = loc.map { $0 + 1 }
                    case .backspace? where !shadow.isEmpty && delCount == 0 && ins.isEmpty:
                        shadow.removeLast(); caret = loc.map { $0 - 1 }
                    default: shadow = ""; caret = nil
                    }
                }
                if shadow.count > 400 { shadow = String(shadow.suffix(200)) }
            }
        }

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
            // Backspace that changes more than the last character (`việt` ⌫ → viêt). Chromium delivers the
            // Backspace to the page even when an input method consumed it, AppKit apps do so when we pass it on:
            // so always pass it, and leave one extra character (the old last one) for it to delete.
            if !pass, out.handled, key == .backspace, canRead, let old, let last = old.last, let del, let loc,
               loc >= del.utf16.count, case let r = NSRange(location: loc - del.utf16.count, length: del.utf16.count),
               text(client, r) == del {
                dbg("backspace replace \(r.location),\(r.length) del=\(del) ins=\(ins)+\(last)")
                edit(client, ins + String(last), r, deleting: del)
                shown = newShown
                expect(r.location + ins.utf16.count)
                return false
            }
            if pass {
                dbg("pass old=\(old ?? "nil") target=\(target) caretAfter=\(caretAfter.map(String.init) ?? "nil")")
                shown = newShown
                if out.handled { expect(caretAfter) } else { caret = nil }
                return false
            }
        }

        let none = NSRange(location: NSNotFound, length: 0)
        if delCount == 0 {
            dbg("insert \(ins)")
            if !ins.isEmpty { client.insertText(ins, replacementRange: none) }
            expect(loc.map { $0 + ins.utf16.count })
        } else if let del, let loc, canRead, loc >= del.utf16.count,
                  case let r = NSRange(location: loc - del.utf16.count, length: del.utf16.count),
                  text(client, r) == del {
            dbg("replace \(r.location),\(r.length) del=\(del) ins=\(ins)")
            edit(client, ins, r, deleting: del)
            expect(r.location + ins.utf16.count)
        } else {
            // Could not verify the text (rare: word started where the app's text was unreadable). Best effort:
            // replace by range if we know the cursor, else just append.
            caret = nil
            dbg("unverified del=\(del ?? "nil") delCount=\(delCount) ins=\(ins) loc=\(loc.map(String.init) ?? "nil") canRead=\(canRead)")
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
    private func applyMarked(_ out: ComposerOutput, client: IMKTextInput, key: KeyInput? = nil) -> Bool {
        let none = NSRange(location: NSNotFound, length: 0)
        // Terminals (Ghostty …) treat a key that ended a composition as part of it and drop it, or send the
        // committed text in its place: Enter would be lost. Send the key's own character with the text instead.
        if !out.handled, !out.commit.isEmpty, state.isPty(client.bundleIdentifier()),
           let k = key, let ch = k == .enter ? "\r" : k == .tab ? "\t" : nil {
            client.insertText(out.commit + ch, replacementRange: none)
            hasMarked = false
            caret = nil
            return true
        }
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
        guess = nil
        shadow = ""
        CandidateWindow.shared.hide()
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        state.forceHidden = state.defaults.bool(forKey: "ForceHidden")
        state.debug = state.defaults.bool(forKey: "DebugLog")
        state.keyLog = state.defaults.bool(forKey: "KeyLog")
        let id = (sender as? IMKTextInput)?.bundleIdentifier()
        dbg("activate \(id ?? "?")")
        // Chromium deactivates and re-activates the input method right after the first key in a newly focused field:
        // keep the word when that blip comes straight back to this same controller and app.
        if let p = Self.pending, p.controller == ObjectIdentifier(self), p.bundle == id, Date().timeIntervalSince(p.time) < 0.5 {
            Self.pending = nil
            return
        }
        Self.pending = nil
        reset()
        freshField = true
    }

    private static var pending: (controller: ObjectIdentifier, bundle: String?, time: Date)?

    override func deactivateServer(_ sender: Any!) {
        let id = (sender as? IMKTextInput)?.bundleIdentifier()
        dbg("deactivate \(id ?? "?")")
        if !markedMode, !hasMarked, !shown.isEmpty {
            // Direct mode: the word is already plain text in the document, nothing to commit. Decide on activation.
            Self.pending = (ObjectIdentifier(self), id, Date())
            CandidateWindow.shared.hide()
        } else {
            reset(sender)
        }
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
