// End-to-end test: types real key events into TextEdit with Emi Key selected and checks the text.
//   swift Tests/e2e/e2e.swift [cases-file]        (default Tests/e2e/cases.txt)
// Needs: Accessibility (to post key events) and Automation → TextEdit for the app running this
// (Terminal / Ghostty / …). Emi Key must be installed (./build.sh).
// Case file: `input<TAB>expected` per line, `#` comments. ⎋ = Esc, ⌫ = Backspace, ⏎ = Return.
import AppKit
import ApplicationServices
import Carbon

let emiID = "com.emi2git.inputmethod.EmiKey"
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let casesURL = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : scriptDir.appendingPathComponent("cases.txt")

var cleanup: (() -> Void)?
func fail(_ msg: String) -> Never { cleanup?(); print("ERROR: \(msg)"); exit(2) }
func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

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

// MARK: AppleScript
@discardableResult
func osa(_ src: String) -> String? {
    var err: NSDictionary?
    let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err { print("AppleScript error: \(err[NSAppleScript.errorMessage] ?? err)"); return nil }
    return r?.stringValue
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

func type(_ text: String, pid: pid_t) {
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in text {
        guard let (code, shift) = keyCodes[ch] else { print("  (no key for \(ch), skipped)"); continue }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = shift ? .maskShift : []
            e.postToPid(pid)   // straight to TextEdit: never leaks into another app if focus moves
            pause(0.012)
        }
        pause(0.03)
    }
}

// MARK: main
guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
    fail("Accessibility permission missing. System Settings → Privacy & Security → Accessibility → enable the terminal app running this script, then rerun.")
}
guard let emi = emiSource() else { fail("Emi Key is not installed/enabled — run ./build.sh first.") }
guard let caseText = try? String(contentsOf: casesURL, encoding: .utf8) else { fail("cannot read \(casesURL.path)") }
let cases: [(String, String)] = caseText.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
    if line.hasPrefix("#") { return nil }
    let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    return (String(parts[0]), String(parts[1]).replacingOccurrences(of: "⏎", with: "\n"))
}

// Keep TextEdit from "helping" (autocorrect, capitalisation, smart punctuation); restored at the end.
// TextEdit is sandboxed; the `defaults` tool finds its container, UserDefaults(suiteName:) does not.
func defaultsCmd(_ args: [String]) -> String? {
    let p = Process(); let out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    p.arguments = args; p.standardOutput = out; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
    let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return p.terminationStatus == 0 ? s : nil
}
func teGet(_ k: String) -> String? { defaultsCmd(["read", "com.apple.TextEdit", k]) }
func teSet(_ k: String, _ v: String?) {
    _ = v.map { defaultsCmd(["write", "com.apple.TextEdit", k, "-int", $0]) } ?? defaultsCmd(["delete", "com.apple.TextEdit", k])
}
let helperKeys = ["NSAutomaticSpellingCorrectionEnabled", "NSAutomaticCapitalizationEnabled", "NSAutomaticPeriodSubstitutionEnabled",
                  "NSAutomaticQuoteSubstitutionEnabled", "NSAutomaticDashSubstitutionEnabled", "NSAutomaticTextCompletionEnabled",
                  "NSAutomaticTextReplacementEnabled", "WebAutomaticSpellingCorrectionEnabled", "CheckSpellingWhileTyping",
                  "CorrectSpellingAutomatically", "SmartQuotes", "SmartDashes", "TextReplacement", "SmartCopyPaste"]
let savedHelpers = helperKeys.map { teGet($0) }
for k in helperKeys { teSet(k, "0") }
let savedRich = teGet("RichText")
teSet("RichText", "0")

let previous = currentSource()
func restoreAll() {
    _ = select(previous)
    for (k, v) in zip(helperKeys, savedHelpers) { teSet(k, v) }
    teSet("RichText", savedRich)
}
cleanup = restoreAll
// TextEdit reads those settings at launch: restart it if it is running with no documents open.
if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty {
    if osa("tell application \"TextEdit\" to count documents") == "0" {
        osa("tell application \"TextEdit\" to quit")
        for _ in 0..<40 where !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty { pause(0.25) }
    } else {
        print("note: TextEdit has open documents, so autocorrect/capitalisation settings may still apply")
    }
}
if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", "TextEdit"]
    try? open.run(); open.waitUntilExit()
    for _ in 0..<40 where NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty { pause(0.25) }
    pause(1.5)
}
print("input source: \(sourceID(previous)) → \(emiID)")
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
    guard let name = osa("tell application \"TextEdit\"\nactivate\nset d to make new document\nreturn name of d\nend tell") else {
        fail("Automation permission for TextEdit missing. Allow it when macOS asks, or System Settings → Privacy & Security → Automation → <your terminal> → TextEdit.")
    }
    pause(0.6)
    guard let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { fail("TextEdit not running") }
    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.TextEdit" { te.activate(); pause(0.4) }
    if sourceID(currentSource()) != emiID { _ = select(emi) }
    type(input, pid: te.processIdentifier)
    pause(0.5)
    let got = osa("tell application \"TextEdit\" to get text of document \"\(name)\"") ?? "<read failed>"
    osa("tell application \"TextEdit\" to close document \"\(name)\" saving no")
    return (got, userIdle() < Date().timeIntervalSince(t0))   // a real key press landed during the case
}

for (input, expected) in cases {
    var r = runCase(input)
    for _ in 0..<3 where r.disturbed && r.got != expected { print("  (user typed during \"\(input)\", retrying)"); r = runCase(input) }
    rows.append((input, expected, r.got, r.got == expected))
}
let elapsed = Int(Date().timeIntervalSince(started)) + 2

restoreAll()

// Did the IME actually see the keys? (InputController logs one content-free line per key.)
let p = Process(); let pipe = Pipe()
p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
p.arguments = ["show", "--last", "\(elapsed)s", "--style", "compact", "--predicate", "subsystem == \"\(emiID)\""]
p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
try? p.run(); p.waitUntilExit()
let imeKeys = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .split(separator: "\n").filter { $0.contains("key handled=") }.count
let typedKeys = cases.reduce(0) { $0 + $1.0.count }

func show(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: "⏎") }
let w = max(10, rows.map { show($0.0).count }.max() ?? 0)
print("\n" + "RESULT".padding(toLength: 6, withPad: " ", startingAt: 0) + "  " + "INPUT".padding(toLength: w, withPad: " ", startingAt: 0) + "  EXPECTED → GOT")
for (i, e, g, ok) in rows {
    print((ok ? "PASS" : "FAIL").padding(toLength: 6, withPad: " ", startingAt: 0) + "  " + show(i).padding(toLength: w, withPad: " ", startingAt: 0)
          + "  \(show(e))" + (ok ? "" : "  →  \(show(g))"))
}
let passed = rows.filter { $0.3 }.count
print("\n\(passed)/\(rows.count) passed · Emi Key saw \(imeKeys) of \(typedKeys) key events · input source restored to \(sourceID(currentSource()))")
exit(passed == rows.count && imeKeys > 0 ? 0 : 1)
