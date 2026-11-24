import Cocoa
import InputMethodKit
import EmiKeyCore
import os

let log = Logger(subsystem: AppState.bundleID, category: "input")

/// Tags on CGEvents we synthesise ourselves, so we recognise them when they come back through the IME.
enum Synth {
    static let backspaceTag: Int64 = 0x456D_694B_0001   // "EmiK" + 1: let the app delete
    static let markerTag: Int64 = 0x456D_694B_0002      // after the backspaces: insert the pending commit
    static let markerKeyCode: CGKeyCode = 90             // F20, produces no text

    static func post(backspaces n: Int) {
        let src = CGEventSource(stateID: .privateState)
        func send(_ code: CGKeyCode, tag: Int64) {
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
                e.flags = []
                e.setIntegerValueField(.eventSourceUserData, value: tag)
                e.post(tap: .cghidEventTap)
            }
        }
        for _ in 0..<n { send(51, tag: backspaceTag) }
        send(markerKeyCode, tag: markerTag)
    }
}

@objc(EmiKeyInputController)
final class InputController: IMKInputController {
    private var state: AppState { .shared }
    private var composer: Composer { AppState.shared.composer }
    private var hasMarked = false
    /// Output waiting for our synthesised backspaces to be processed (fallback path).
    private var pending: ComposerOutput?

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    // MARK: keys

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        if let cg = event.cgEvent {
            switch cg.getIntegerValueField(.eventSourceUserData) {
            case Synth.backspaceTag: return false
            case Synth.markerTag:
                if let out = pending { pending = nil; apply(out, deleteCount: 0, client: client) }
                return true
            default: break
            }
        }
        let key = Self.keyInput(event)
        let out = composer.handle(key, precedingText: precedingText(client))
        let n = composer.deleteCount
        log.notice("key handled=\(out.handled, privacy: .public) delete=\(n, privacy: .public)")
        apply(out, deleteCount: n, client: client)
        return out.handled
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

    /// Up to 200 characters before the composition (or cursor). nil when the app does not expose its text.
    private func precedingText(_ client: IMKTextInput) -> String? {
        guard let loc = compositionStart(client) else { return nil }
        if loc == 0 { return "" }
        let start = max(0, loc - 200)
        return client.attributedSubstring(from: NSRange(location: start, length: loc - start))?.string
    }

    private func compositionStart(_ client: IMKTextInput) -> Int? {
        let m = client.markedRange()
        if hasMarked, m.location != NSNotFound, m.length > 0 { return m.location }
        let s = client.selectedRange()
        return s.location == NSNotFound ? nil : s.location
    }

    // MARK: output

    private func apply(_ out: ComposerOutput, deleteCount n: Int, client: IMKTextInput) {
        defer { updateCandidates(out.candidates, client: client) }
        if n > 0 {
            if let loc = compositionStart(client), loc >= n,
               let before = client.attributedSubstring(from: NSRange(location: loc - n, length: n)), before.length == n {
                let markedLen = hasMarked ? max(0, client.markedRange().length) : 0
                client.insertText(out.commit, replacementRange: NSRange(location: loc - n, length: n + markedLen))
                hasMarked = false
                setMarked(out.marked, client: client)
            } else {
                // App hides its text: clear our marked text, let it delete via real backspaces, then finish.
                setMarked("", client: client)
                pending = ComposerOutput(commit: out.commit, marked: out.marked, candidates: out.candidates, handled: out.handled)
                Synth.post(backspaces: composer.lastDeleteCount)
            }
            return
        }
        if !out.commit.isEmpty {
            client.insertText(out.commit, replacementRange: NSRange(location: NSNotFound, length: 0))
            hasMarked = false
        }
        setMarked(out.marked, client: client)
    }

    private func setMarked(_ text: String, client: IMKTextInput) {
        if text.isEmpty && !hasMarked { return }
        let attrs: [NSAttributedString.Key: Any] = [.underlineStyle: NSUnderlineStyle.single.rawValue,
                                                    .markedClauseSegment: 0]
        let s = NSAttributedString(string: text, attributes: attrs)
        client.setMarkedText(s, selectionRange: NSRange(location: (text as NSString).length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarked = !text.isEmpty
    }

    private func updateCandidates(_ cands: [String], client: IMKTextInput) {
        guard !cands.isEmpty else { CandidateWindow.shared.hide(); return }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        CandidateWindow.shared.onPick = { [weak self] i in self?.pick(i) }
        CandidateWindow.shared.show(cands, under: rect)
    }

    private func pick(_ i: Int) {
        guard let client = client() else { return }
        apply(composer.pick(i), deleteCount: composer.deleteCount, client: client)
    }

    // MARK: lifecycle

    private func flush(_ sender: Any?) {
        let text = composer.flush()
        let client = (sender as? IMKTextInput) ?? client()
        if let client {
            if !text.isEmpty {
                client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                hasMarked = false
            } else {
                setMarked("", client: client)
            }
        }
        hasMarked = false
        CandidateWindow.shared.hide()
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        _ = composer.flush()      // new focus: start clean
        hasMarked = false
    }

    override func deactivateServer(_ sender: Any!) {
        flush(sender)
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        flush(sender)
    }

    // MARK: menu

    override func menu() -> NSMenu! {
        let m = NSMenu(title: "Emi Key")
        func add(_ title: String, _ sel: Selector, on: Bool? = nil) {
            let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            it.target = self
            if let on { it.state = on ? .on : .off }
            m.addItem(it)
        }
        add("Traditional Chinese", #selector(toggleTraditional(_:)), on: state.traditional)
        m.addItem(.separator())
        add("Vietnamese tone style: New (hoà)", #selector(toneNew(_:)), on: state.toneStyle == .new)
        add("Vietnamese tone style: Old (hòa)", #selector(toneOld(_:)), on: state.toneStyle == .old)
        m.addItem(.separator())
        add("Settings…", #selector(showSettings(_:)))
        add("Help", #selector(showHelp(_:)))
        add("About Emi Key", #selector(showAbout(_:)))
        return m
    }

    @objc func toggleTraditional(_ sender: Any?) { state.traditional.toggle() }
    @objc func toneNew(_ sender: Any?) { state.toneStyle = .new }
    @objc func toneOld(_ sender: Any?) { state.toneStyle = .old }
    @objc func showSettings(_ sender: Any?) { Windows.showSettings() }
    @objc func showHelp(_ sender: Any?) { Windows.showHelp() }
    @objc func showAbout(_ sender: Any?) { Windows.showAbout() }
}
