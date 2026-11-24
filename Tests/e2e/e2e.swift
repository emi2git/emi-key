// End-to-end test: types real key events into an app with Emi Key selected and checks the text.
//   swift Tests/e2e/e2e.swift [--app textedit|chrome|chrome-user|safari|notes|terminal|ghostty|ghostty-user] [--field textarea|input] [cases-file]
//   (defaults: --app textedit, Tests/e2e/cases.txt; --field omnibox = Chrome's address bar, never sent Enter)
// Needs: Accessibility (to post key events) and Automation → the target app for the app running this
// (Terminal / Ghostty / …). Emi Key must be installed (./build.sh).
// Case file: `input<TAB>expected` per line, `#` comments. ⎋ = Esc, ⌫ = Backspace, ⏎ = Return.
// `~text` as expected = the result only has to contain `text` (e.g. closest-match candidates).
//
// Leaves no trail: it only types into windows/documents/notes it created, closes them without saving, deletes
// its scratch files, restores app settings it changed, the clipboard and the input source. Apps it had to
// launch are quit again at the end.
import AppKit
import ApplicationServices
import Carbon

let emiID = "com.emi2git.inputmethod.EmiKey"
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

var argv = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    let v = argv[i + 1]; argv.removeSubrange(i...i + 1); return v
}
let appName = option("--app") ?? "textedit"
let fieldKind = option("--field") ?? "textarea"
/// --hid: post keys through the HID event tap (like a real keyboard) instead of straight to the app's pid.
/// The focus guard still checks the test window before every key.
let viaHID = argv.contains("--hid")
argv.removeAll { $0 == "--hid" }
/// --reselect: switch to ABC and back to Emi Key once the test window has focus (diagnostics).
let reselect = argv.contains("--reselect")
argv.removeAll { $0 == "--reselect" }
let casesURL = argv.first.map { URL(fileURLWithPath: $0) } ?? scriptDir.appendingPathComponent("cases.txt")

var cleanups: [() -> Void] = []
func cleanupAll() { while let c = cleanups.popLast() { c() } }
func fail(_ msg: String) -> Never { cleanupAll(); print("ERROR: \(msg)"); exit(2) }
func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }
signal(SIGINT) { _ in cleanupAll(); exit(130) }

// Emi Key logs one content-free line per key ("key handled=… marked=…") only while KeyLog is set: turn it on for
// this run (Emi Key re-reads it when a field gains focus) and restore the previous value at the end.
do {
    let had = run("/usr/bin/defaults", ["read", emiID, "KeyLog"])
    run("/usr/bin/defaults", ["write", emiID, "KeyLog", "-bool", "YES"])
    cleanups.append {
        if had.status == 0 { run("/usr/bin/defaults", ["write", emiID, "KeyLog", "-bool", had.out == "1" ? "YES" : "NO"]) }
        else { run("/usr/bin/defaults", ["delete", emiID, "KeyLog"]) }
    }
}

// MARK: input sources
func prop<T>(_ s: TISInputSource, _ k: CFString) -> T? {
    guard let p = TISGetInputSourceProperty(s, k) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() as? T
}
func currentSource() -> TISInputSource { TISCopyCurrentKeyboardInputSource().takeRetainedValue() }
func sourceID(_ s: TISInputSource) -> String { prop(s, kTISPropertyInputSourceID) ?? "?" }
func select(_ s: TISInputSource) -> Bool {
    for _ in 0..<6 {
        if TISSelectInputSource(s) == noErr, sourceID(currentSource()) == sourceID(s) { return true }
        pause(0.5)
    }
    return false
}
func emiSource() -> TISInputSource? {
    let l = TISCreateInputSourceList([kTISPropertyInputSourceID as String: emiID] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource]
    return l?.first
}

// MARK: helpers
@discardableResult
func osa(_ src: String, quiet: Bool = false) -> String? {
    var err: NSDictionary?
    let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err { if !quiet { print("AppleScript error: \(err[NSAppleScript.errorMessage] ?? err)") }; return nil }
    return r?.stringValue
}
@discardableResult
func run(_ exe: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process(); let out = Pipe()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args; p.standardOutput = out; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, "") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}
/// The user's instance of an app (headless/automation copies, e.g. puppeteer Chromes, are not `.regular`).
func running(_ bundle: String) -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { $0.activationPolicy == .regular }
}
func waitFor(_ secs: Double = 10, _ cond: () -> Bool) -> Bool {
    var t = 0.0
    while !cond() { if t > secs { return false }; pause(0.25); t += 0.25 }
    return true
}
func asLiteral(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

// Accessibility: value of the focused element of an app.
func axFocusedValue(_ pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)
    var f: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f) == .success, let el = f else { return nil }
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el as! AXUIElement, kAXValueAttribute as CFString, &v) == .success else { return nil }
    return v as? String
}

func axAttr(_ el: AXUIElement, _ a: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, a as CFString, &v) == .success ? v : nil
}
func axFocusedWindow(_ pid: pid_t) -> AXUIElement? {
    axAttr(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute).map { $0 as! AXUIElement }
}
func axTitle(_ w: AXUIElement?) -> String { w.flatMap { axAttr($0, kAXTitleAttribute) as? String } ?? "" }
func axWindows(_ pid: pid_t) -> [AXUIElement] { (axAttr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
func axWindow(_ pid: pid_t, titleContains s: String) -> AXUIElement? { axWindows(pid).first { axTitle($0).contains(s) } }
/// Bring one window of an app to the front and make it key.
func raise(_ app: NSRunningApplication, _ w: AXUIElement) {
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(w, kAXMainAttribute as CFString, kCFBooleanTrue)
    app.activate()
    if !waitFor(1, { NSWorkspace.shared.frontmostApplication == app }) {
        // Activation from a background process can be refused; System Events can always do it.
        osa("tell application \"System Events\" to set frontmost of (first process whose unix id is \(app.processIdentifier)) to true", quiet: true)
    }
    _ = waitFor(3) { NSWorkspace.shared.frontmostApplication == app && axFocusedWindow(app.processIdentifier).map { CFEqual($0, w) } == true }
}
/// Focus the first element with `role` inside `el` (depth-first), not descending into `skipping` (e.g. the toolbar).
func axFocus(_ el: AXUIElement, role: String, skipping: String, depth: Int = 0) -> Bool {
    if depth > 14 { return false }
    let r = axAttr(el, kAXRoleAttribute) as? String
    if r == role { return AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success }
    if r == skipping { return false }
    for c in (axAttr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] where axFocus(c, role: role, skipping: skipping, depth: depth + 1) { return true }
    return false
}
func axPressClose(_ w: AXUIElement) {
    if let b = axAttr(w, kAXCloseButtonAttribute) { AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString) }
}

func axFocusedSelection(_ pid: pid_t) -> CFRange? {
    guard let f = axAttr(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
          let v = axAttr(f as! AXUIElement, kAXSelectedTextRangeAttribute) else { return nil }
    var r = CFRange(); return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
}

// MARK: keys (US / ABC layout virtual key codes)
let keyCodes: [Character: (CGKeyCode, Bool)] = {
    var m: [Character: (CGKeyCode, Bool)] = [:]
    let plain: [(String, CGKeyCode)] = [("a",0),("s",1),("d",2),("f",3),("h",4),("g",5),("z",6),("x",7),("c",8),("v",9),("b",11),("q",12),("w",13),("e",14),("r",15),("y",16),("t",17),("1",18),("2",19),("3",20),("4",21),("6",22),("5",23),("=",24),("9",25),("7",26),("-",27),("8",28),("0",29),("]",30),("o",31),("u",32),("[",33),("i",34),("p",35),("l",37),("j",38),("'",39),("k",40),(";",41),("\\",42),(",",43),("/",44),("n",45),("m",46),(".",47),("`",50),(" ",49),("⏎",36),("⎋",53),("⌫",51),("\t",48)]
    for (s, c) in plain { m[Character(s)] = (c, false) }
    for c in "abcdefghijklmnopqrstuvwxyz" { m[Character(c.uppercased())] = (m[c]!.0, true) }
    let shifted: [(String, String)] = [("!","1"),("@","2"),("#","3"),("$","4"),("%","5"),("^","6"),("&","7"),("*","8"),("(","9"),(")","0"),("_","-"),("+","="),("{","["),("}","]"),("|","\\"),(":",";"),("\"","'"),("<",","),(">","."),("?","/"),("~","`")]
    for (s, base) in shifted { m[Character(s)] = (m[Character(base)]!.0, true) }
    return m
}()

/// Safety: checked before every key. Keys are only sent while the window the case opened is the focused one.
var focusGuard: (() -> Bool)?
var focusLost = false
func key(_ code: CGKeyCode, _ flags: CGEventFlags = [], pid: pid_t) {
    if focusLost { return }
    if let g = focusGuard, !g() { focusLost = true; print("  (focus left the test window, or you typed — stopped typing)"); return }
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
        e.flags = flags
        if viaHID { e.post(tap: .cghidEventTap) } else { e.postToPid(pid) }   // pid: never leaks into another app
        pause(0.012)
    }
}
func type(_ text: String, pid: pid_t) {
    for ch in text {
        guard let (code, shift) = keyCodes[ch] else { print("  (no key for \(ch), skipped)"); continue }
        key(code, shift ? .maskShift : [], pid: pid)
        pause(0.04)
    }
}

// MARK: targets
/// One app under test. `open` makes a fresh, focused, empty field; `read` returns its text; `close` disposes of it.
struct Target {
    var bundle: String
    /// The process to type into (default: the user's instance of `bundle`).
    var app: (() -> NSRunningApplication?)? = nil
    var setup: () -> Void = {}
    var open: () -> Bool
    var read: () -> String?
    var close: () -> Void
    var teardown: () -> Void = {}
    var skip: (String) -> Bool = { _ in false }
    /// Is this (focused) window one the test opened? Typing only starts if so.
    var isOurs: (String) -> Bool
}

func launchIfNeeded(_ bundle: String, quitAtEnd: Bool = true) {
    if running(bundle) != nil { return }
    run("/usr/bin/open", ["-g", "-b", bundle])
    _ = waitFor(15) { running(bundle) != nil }
    pause(2)
    if quitAtEnd { cleanups.append { running(bundle)?.terminate(); _ = waitFor(10) { running(bundle) == nil } } }
}
func activate(_ bundle: String) {
    guard let app = running(bundle) else { return }
    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundle {
        app.activate()
        _ = waitFor(3) { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle }
        pause(0.3)
    }
}

let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("emikey-e2e-\(getpid())")
try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
cleanups.append { try? FileManager.default.removeItem(at: tmpDir) }

// Test page for browsers: one <textarea> and one <input>, no spellcheck/autocorrect.
let pageURL = tmpDir.appendingPathComponent("emikey-test.html")
try? """
<!doctype html><meta charset="utf-8"><title>Emi Key e2e</title>
<body style="font:20px -apple-system">
<textarea id="textarea" rows="6" cols="60" spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"\(fieldKind == "textarea" ? " autofocus" : "")></textarea><br>
<input id="input" size="60" spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"\(fieldKind == "input" ? " autofocus" : "")>
<script>document.title = 'Emi Key e2e ' + (location.search.slice(1) || (location.pathname.match(/emikey-test-(\\w+)\\.html$/) || [, ''])[1]); document.getElementById('\(fieldKind)').focus()</script>
""".write(to: pageURL, atomically: true, encoding: .utf8)

func textEdit() -> Target {
    let b = "com.apple.TextEdit"
    // Keep TextEdit from "helping" (autocorrect, capitalisation, smart punctuation); restored at the end.
    // TextEdit is sandboxed; the `defaults` tool finds its container, UserDefaults(suiteName:) does not.
    let keys = ["NSAutomaticSpellingCorrectionEnabled", "NSAutomaticCapitalizationEnabled", "NSAutomaticPeriodSubstitutionEnabled",
                "NSAutomaticQuoteSubstitutionEnabled", "NSAutomaticDashSubstitutionEnabled", "NSAutomaticTextCompletionEnabled",
                "NSAutomaticTextReplacementEnabled", "WebAutomaticSpellingCorrectionEnabled", "CheckSpellingWhileTyping",
                "CorrectSpellingAutomatically", "SmartQuotes", "SmartDashes", "TextReplacement", "SmartCopyPaste", "RichText"]
    var name = ""
    let icloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~TextEdit/Documents")
    let before = Set((try? FileManager.default.contentsOfDirectory(atPath: icloud.path)) ?? [])
    return Target(bundle: b, setup: {
        let saved = keys.map { run("/usr/bin/defaults", ["read", b, $0]) }
        for k in keys { run("/usr/bin/defaults", ["write", b, k, "-int", "0"]) }
        cleanups.append {
            for (k, v) in zip(keys, saved) {
                if v.status == 0 { run("/usr/bin/defaults", ["write", b, k, "-int", v.out]) } else { run("/usr/bin/defaults", ["delete", b, k]) }
            }
        }
        // TextEdit reads those settings at launch: restart it if it is running with no documents open.
        if running(b) != nil {
            if osa("tell application \"TextEdit\" to count documents") == "0" {
                osa("tell application \"TextEdit\" to quit"); _ = waitFor { running(b) == nil }
            } else { print("note: TextEdit has open documents, so autocorrect/capitalisation settings may still apply") }
        }
        launchIfNeeded(b)
        // Autosaved copies of our untitled documents (iCloud TextEdit folder) — only files that appeared now.
        cleanups.append {
            let now = Set((try? FileManager.default.contentsOfDirectory(atPath: icloud.path)) ?? [])
            for f in now.subtracting(before) where f.hasPrefix("Untitled") { try? FileManager.default.removeItem(at: icloud.appendingPathComponent(f)) }
        }
    }, open: {
        guard let n = osa("tell application \"TextEdit\"\nactivate\nset d to make new document\nreturn name of d\nend tell") else { return false }
        name = n; pause(0.6); activate(b); return true
    }, read: {
        osa("tell application \"TextEdit\" to get text of document \(asLiteral(name))")
    }, close: {
        osa("tell application \"TextEdit\" to close document \(asLiteral(name)) saving no")
    }, isOurs: { $0 == name || $0.hasPrefix(name + " ") })
}

/// Chromium. Default: a separate Chrome instance with a throw-away profile (never touches the user's windows,
/// tabs or settings; it is quit and its profile deleted at the end). `user: true` (--app chrome-user) uses the
/// user's running Chrome instead, in a new window of its own.
func chrome(user: Bool) -> Target {
    let b = "com.google.Chrome"
    let exe = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let profile = tmpDir.appendingPathComponent("chrome-profile")
    var tag = "", proc: Process?, instance: NSRunningApplication?
    func app() -> NSRunningApplication? { user ? running(b) : instance }
    // AppleScript "Google Chrome" may reach any copy (e.g. headless puppeteer ones), so Chrome is driven by its
    // command line (`--new-window` goes to the instance owning that profile) and Accessibility (by pid).
    func newWindow(_ url: String) {
        var args = ["--new-window", url]
        if !user { args = ["--user-data-dir=\(profile.path)", "--no-first-run", "--no-default-browser-check", "--disable-sync"] + args }
        if !user, proc == nil {
            let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); proc = p
            _ = waitFor(15) { instance = NSRunningApplication(processIdentifier: p.processIdentifier); return instance != nil }
            pause(2)
        } else {
            run(exe, args)
        }
    }
    return Target(bundle: b, app: app, setup: {
        if user {
            guard running(b) != nil else { fail("Chrome is not running (--app chrome-user uses the user's Chrome)") }
        } else {
            cleanups.append {
                instance?.terminate()
                if !waitFor(8, { proc?.isRunning != true }) { proc?.terminate() }
                _ = waitFor(5) { proc?.isRunning != true }
                try? FileManager.default.removeItem(at: profile)
            }
        }
    }, open: {
        tag = UUID().uuidString.prefix(8).lowercased()
        newWindow(pageURL.absoluteString + "?" + tag)
        guard let app = app() else { return false }
        // Chrome builds its accessibility tree only when asked; the previous setting is restored at the end.
        let el = AXUIElementCreateApplication(app.processIdentifier)
        if (axAttr(el, "AXManualAccessibility") as? Bool) != true {
            AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if user { cleanups.append { AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanFalse) } }
        }
        if !user { AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        var w: AXUIElement?
        guard waitFor(10, { w = axWindow(app.processIdentifier, titleContains: tag); return w != nil }), let w else {
            print("  (chrome: no window \(tag); windows: \(axWindows(app.processIdentifier).map(axTitle)))"); return false
        }
        raise(app, w)
        var ok = waitFor(10) { axFocusedValue(app.processIdentifier) == "" }
        if ok, fieldKind == "omnibox" {
            // The address bar: ⌘L, then it must be empty-ish (it shows the URL selected; typing replaces it).
            focusGuard = { axFocusedWindow(app.processIdentifier).map { CFEqual($0, w) } == true }
            key(37, .maskCommand, pid: app.processIdentifier)
            focusGuard = nil
            ok = waitFor(4) { (axFocusedValue(app.processIdentifier) ?? "").contains("emikey-test") }
        }
        if !ok { print("  (chrome: field not focused; front=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) app=\(app.processIdentifier) focused=\(axTitle(axFocusedWindow(app.processIdentifier))) value=\(axFocusedValue(app.processIdentifier) ?? "nil"))") }
        return ok
    }, read: {
        guard let app = app(), let v = axFocusedValue(app.processIdentifier) else { return nil }
        // Address bar: drop Chrome's inline autocomplete (the selected suggestion after the cursor).
        if fieldKind == "omnibox", let r = axFocusedSelection(app.processIdentifier), r.length > 0, r.location + r.length == (v as NSString).length {
            return (v as NSString).substring(to: r.location)
        }
        return v
    }, close: {
        guard let app = app(), let w = axWindow(app.processIdentifier, titleContains: tag) else { return }
        if fieldKind == "omnibox" {   // Esc twice: drop the typed text (never Enter), then close the window
            focusGuard = { axFocusedWindow(app.processIdentifier).map { CFEqual($0, w) } == true }
            key(53, pid: app.processIdentifier); pause(0.2); key(53, pid: app.processIdentifier); pause(0.2)
            focusGuard = nil
        }
        axPressClose(w)
        _ = waitFor(3) { axWindow(app.processIdentifier, titleContains: tag) == nil }
    }, isOurs: { $0.contains("Emi Key e2e \(tag)") })
}

/// Safari, driven without AppleScript (no Automation prompt): `open` loads the page in a new window/tab, Accessibility
/// reads the field and closes that window.
func safari() -> Target {
    let b = "com.apple.Safari"
    var tag = ""
    return Target(bundle: b, setup: {
        launchIfNeeded(b)
    }, open: {
        tag = UUID().uuidString.prefix(8).lowercased()
        // Safari drops ?query and #hash on file URLs: the tag goes into a per-case copy's name.
        let page = tmpDir.appendingPathComponent("emikey-test-\(tag).html")
        try? FileManager.default.copyItem(at: pageURL, to: page)
        run("/usr/bin/open", ["-a", "Safari", page.absoluteString])
        guard let app = running(b) else { return false }
        var w: AXUIElement?
        guard waitFor(8, { w = axWindow(app.processIdentifier, titleContains: tag); return w != nil }), let w else { return false }
        raise(app, w)
        // `open` leaves the address bar focused: focus the page's field through Accessibility.
        _ = waitFor(10) { axFocus(w, role: fieldKind == "input" ? "AXTextField" : "AXTextArea", skipping: "AXToolbar") }
        return waitFor(6) { axFocusedValue(app.processIdentifier) == "" }
    }, read: {
        running(b).flatMap { axFocusedValue($0.processIdentifier) }
    }, close: {
        guard let app = running(b), let w = axWindow(app.processIdentifier, titleContains: tag) else { return }
        axPressClose(w)
        _ = waitFor(3) { axWindow(app.processIdentifier, titleContains: tag) == nil }
    }, isOurs: { $0.contains("Emi Key e2e \(tag)") })
}

func notes() -> Target {
    let b = "com.apple.Notes"
    var noteID = "", tag = ""
    func purge() {
        // Deleted notes go to Recently Deleted; delete them there too (by id: deleting while iterating misses some).
        let ids = osa("""
        tell application "Notes"
          set r to {}
          repeat with f in folders
            if name of f is "Recently Deleted" then
              repeat with n in (notes of f whose name starts with "2026 e2e")
                set end of r to id of n
              end repeat
            end if
          end repeat
          set AppleScript's text item delimiters to linefeed
          return r as text
        end tell
        """, quiet: true) ?? ""
        for id in ids.split(separator: "\n") where !id.isEmpty {
            osa("tell application \"Notes\" to delete note id \(asLiteral(String(id)))", quiet: true)
        }
    }
    return Target(bundle: b, setup: {
        // Notes' own autocorrect / auto-capitalisation stay on (it is the user's running app; not restarted):
        // differences like "Tôi" or "đi" → "dì" are Notes, not Emi Key.
        launchIfNeeded(b)
        cleanups.append { purge() }
    }, open: {
        guard let app = running(b) else { return false }
        // Digits only: the title line is the text before the cursor, it must not look English or Vietnamese.
        tag = String(Int.random(in: 10_000_000...99_999_999))
        // A fresh note in its own window (Notes names a note after its first line).
        guard let id = osa("tell application \"Notes\"\nset n to make new note with properties {body:\"<div>2026 e2e \(tag)</div><div><br></div>\"}\nreturn id of n\nend tell") else { return false }
        noteID = id
        osa("tell application \"Notes\" to show note id \(asLiteral(id)) separately true")
        var w: AXUIElement?
        guard waitFor(6, { w = axWindow(app.processIdentifier, titleContains: tag); return w != nil }), let w else { return false }
        raise(app, w); pause(0.5)
        focusGuard = { axFocusedWindow(app.processIdentifier).map { CFEqual($0, w) } == true }
        key(125, .maskCommand, pid: app.processIdentifier)   // ⌘↓: end of the note (the empty second line)
        focusGuard = nil
        pause(0.3)
        return true
    }, read: {
        guard let t = osa("tell application \"Notes\" to get plaintext of note id \(asLiteral(noteID))") else { return nil }
        let prefix = "2026 e2e \(tag)\n"
        guard t.hasPrefix(prefix) else { return "<\(t)>" }
        var rest = Substring(t.dropFirst(prefix.count))
        if rest.hasPrefix("\n") { rest = rest.dropFirst() }   // the empty line the cursor was put on
        return String(rest)
    }, close: {
        if let app = running(b), let w = axWindow(app.processIdentifier, titleContains: tag) { axPressClose(w); pause(0.3) }
        osa("tell application \"Notes\" to delete note id \(asLiteral(noteID))", quiet: true)
        pause(0.3)
        purge()
    }, isOurs: { $0.contains("2026 e2e \(tag)") })
}

/// Terminals: a new window running `cat > file`; Ctrl-D ends it and the file holds what was typed.
/// `ghostty`: a separate Ghostty instance per case (`open -n`), so the user's Ghostty windows are never touched and
/// a fresh process talks to the current Emi Key; it quits when `cat` ends. `ghostty-user` opens a window in theirs.
func terminal(ghostty: Bool, separate: Bool = false) -> Target {
    let b = ghostty ? "com.mitchellh.ghostty" : "com.apple.Terminal"
    var file = URL(fileURLWithPath: "/dev/null"), winID = "", tag = ""
    var instance: NSRunningApplication?
    func app() -> NSRunningApplication? { separate ? instance : running(b) }
    func ourWindow() -> AXUIElement? { app().flatMap { axWindow($0.processIdentifier, titleContains: tag) } }
    return Target(bundle: b, app: app, setup: {
        if !separate { launchIfNeeded(b) }
        cleanups.append { if separate, let i = instance, !i.isTerminated { i.terminate() } }
    }, open: {
        tag = "emikey-e2e-" + UUID().uuidString.prefix(8).lowercased()
        file = tmpDir.appendingPathComponent("\(tag).txt")
        // A tiny script: set the window title (OSC 0, marks the window as ours), then cat into the file.
        let script = tmpDir.appendingPathComponent("\(tag).sh")
        try? "#!/bin/sh\nprintf '\\033]0;\(tag)\\007'\nexec /bin/cat > '\(file.path)'\n".write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o755)
        if separate {
            let before = Set(NSRunningApplication.runningApplications(withBundleIdentifier: b).map(\.processIdentifier))
            run("/usr/bin/open", ["-n", "-a", "/Applications/Ghostty.app", "--args", "--command=\(script.path)",
                                  "--quit-after-last-window-closed=true"])
            guard waitFor(10, { instance = NSRunningApplication.runningApplications(withBundleIdentifier: b).first { !before.contains($0.processIdentifier) }; return instance != nil }) else { return false }
        } else if ghostty {
            guard let id = osa("tell application \"Ghostty\"\nset w to new window with configuration {command:\(asLiteral(script.path)), wait after command:false}\nreturn id of w\nend tell") else { return false }
            winID = id
        } else {
            guard let id = osa("tell application \"Terminal\"\nset t to do script \(asLiteral("exec " + script.path))\nreturn id of (first window whose tabs contains t)\nend tell") else { return false }
            winID = id
        }
        var w: AXUIElement?
        guard waitFor(8, { w = ourWindow(); return w != nil }), let w, let app = app() else { return false }
        raise(app, w); pause(0.5)
        return true
    }, read: {
        guard let app = app() else { return nil }
        key(2, .maskControl, pid: app.processIdentifier); pause(0.3)   // ⌃D flushes an unfinished line
        key(2, .maskControl, pid: app.processIdentifier)               // ⌃D again = end of input
        pause(1.0)
        return try? String(contentsOf: file, encoding: .utf8)
    }, close: {
        if separate {
            if let i = instance, !waitFor(3, { i.isTerminated }) { i.terminate(); if !waitFor(3, { i.isTerminated }) { i.forceTerminate() } }
        } else if ghostty { osa("tell application \"Ghostty\" to close window id \(asLiteral(winID))", quiet: true) }
        else { osa("tell application \"Terminal\" to close (every window whose id is \(winID))", quiet: true) }
        if let w = ourWindow() { axPressClose(w) }
        try? FileManager.default.removeItem(at: file)
    }, isOurs: { $0.contains(tag) })
}

let target: Target
switch appName {
case "textedit": target = textEdit()
case "chrome": target = chrome(user: false)
case "chrome-user": target = chrome(user: true)
case "safari": target = safari()
case "notes": target = notes()
case "terminal": target = terminal(ghostty: false)
case "ghostty": target = terminal(ghostty: true, separate: true)
case "ghostty-user": target = terminal(ghostty: true)
default: fail("unknown --app \(appName) (textedit, chrome, chrome-user, safari, notes, terminal, ghostty, ghostty-user)")
}

// MARK: main
guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
    fail("Accessibility permission missing. System Settings → Privacy & Security → Accessibility → enable the terminal app running this script, then rerun.")
}
guard let emi = emiSource() else { fail("Emi Key is not installed/enabled — run ./build.sh first.") }
guard let caseText = try? String(contentsOf: casesURL, encoding: .utf8) else { fail("cannot read \(casesURL.path)") }
var cases: [(String, String)] = caseText.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
    if line.hasPrefix("#") { return nil }
    let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    return (String(parts[0]), String(parts[1]).replacingOccurrences(of: "⏎", with: "\n"))
}
// A single-line field has no newlines: Enter cases only make sense in multi-line fields.
// Never Enter in the address bar (it would navigate / search).
if fieldKind == "input" || fieldKind == "omnibox" { cases = cases.filter { !$0.0.contains("⏎") } }
// In a terminal Esc belongs to the program (it reaches `cat` as ^[), so the Esc flip is not tested there.
if appName == "terminal" || appName.hasPrefix("ghostty") { cases = cases.filter { !$0.0.contains("⎋") } }

let previous = currentSource()
cleanups.append { _ = select(previous) }
let pasteboard = NSPasteboard.general.string(forType: .string)
cleanups.append { if let p = pasteboard, NSPasteboard.general.string(forType: .string) != p { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(p, forType: .string) } }
let frontBefore = NSWorkspace.shared.frontmostApplication
cleanups.insert({ frontBefore?.activate() }, at: 0)

target.setup()
print("app: \(appName) · input source: \(sourceID(previous)) → \(emiID)")
guard select(emi) else { fail("could not select Emi Key (TISSelectInputSource)") }

let started = Date()
var rows: [(String, String, String, Bool)] = []
/// Seconds since the user last touched a real key (our postToPid events do not count).
func userIdle() -> Double { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) }
func waitForIdle() {
    var waited = 0.0
    while userIdle() < 2, waited < 60 { if waited == 0 { print("  (waiting for the keyboard to be idle…)") }; pause(0.5); waited += 0.5 }
}

func runCase(_ input: String) -> (got: String, disturbed: Bool) {
    waitForIdle()
    let t0 = Date()
    focusGuard = nil; focusLost = false
    guard target.open() else { target.close(); return ("<open failed>", false) }
    guard let app = target.app?() ?? running(target.bundle) else { fail("\(appName) not running") }
    let win = axFocusedWindow(app.processIdentifier)
    guard let win, NSWorkspace.shared.frontmostApplication == app, target.isOurs(axTitle(win)) else {
        print("  (focused window is not the test window: \"\(axTitle(win))\" — case skipped)")
        target.close(); return ("<not our window>", false)
    }
    let typingStart = Date()
    focusGuard = {
        NSWorkspace.shared.frontmostApplication == app && axFocusedWindow(app.processIdentifier).map { CFEqual($0, win) } == true
            && (viaHID || userIdle() >= Date().timeIntervalSince(typingStart))   // a real key press: the user is typing, stop
    }
    if reselect, let abc = TISCreateInputSourceList([kTISPropertyInputSourceID as String: (ProcessInfo.processInfo.environment["RESELECT_VIA"] ?? "com.apple.keylayout.ABC")] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource], let a = abc.first {
        _ = select(a); pause(0.3); _ = select(emi); pause(0.3)
    }
    if sourceID(currentSource()) != emiID { _ = select(emi) }
    type(input, pid: app.processIdentifier)
    pause(0.6)
    let got = focusLost ? "<focus lost>" : target.read() ?? "<read failed>"
    focusGuard = nil
    target.close()
    frontBefore?.activate()   // give the keyboard back between cases: the user's keys never land in a test window
    return (got, userIdle() < Date().timeIntervalSince(t0))   // a real key press landed during the case
}

for (input, expected) in cases where !target.skip(input) {
    var r = runCase(input)
    for _ in 0..<3 where r.disturbed { print("  (user typed during \"\(input)\", retrying)"); r = runCase(input) }
    // Notes capitalises sentence starts itself (it is the user's app; its settings are left alone): ignore case there.
    let (g, e) = appName == "notes" ? (r.got.lowercased(), expected.lowercased()) : (r.got, expected)
    let ok = e.hasPrefix("~") ? g.contains(e.dropFirst()) : g == e
    rows.append((input, expected, r.got, ok))
}
let elapsed = Int(Date().timeIntervalSince(started)) + 2

cleanupAll()

// Did the IME actually see the keys? (With KeyLog, InputController logs one content-free line per key.)
let logOut = run("/usr/bin/log", ["show", "--last", "\(elapsed)s", "--style", "compact", "--predicate", "subsystem == \"\(emiID)\""]).out
let imeKeys = logOut.split(separator: "\n").filter { $0.contains("key handled=") }.count
let markedKeys = logOut.split(separator: "\n").filter { $0.contains("key handled=") && $0.contains("marked=true") }.count
let typedKeys = rows.reduce(0) { $0 + $1.0.count }

func show(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "⏎") }
let w = max(10, rows.map { show($0.0).count }.max() ?? 0)
print("\n" + "RESULT".padding(toLength: 6, withPad: " ", startingAt: 0) + "  " + "INPUT".padding(toLength: w, withPad: " ", startingAt: 0) + "  EXPECTED → GOT")
for (i, e, g, ok) in rows {
    print((ok ? "PASS" : "FAIL").padding(toLength: 6, withPad: " ", startingAt: 0) + "  " + show(i).padding(toLength: w, withPad: " ", startingAt: 0)
          + "  \(show(e))" + (ok ? "" : "  →  \(show(g))"))
}
let passed = rows.filter { $0.3 }.count
let mode = markedKeys == 0 ? "direct" : markedKeys == imeKeys ? "marked" : "mixed (\(markedKeys) marked)"
print("\n\(appName): \(passed)/\(rows.count) passed · Emi Key saw \(imeKeys) of \(typedKeys) key events · mode \(mode) · input source restored to \(sourceID(currentSource()))")
exit(passed == rows.count && imeKeys > 0 ? 0 : 1)
