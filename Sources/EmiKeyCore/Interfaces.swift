// Shared contracts between the engines. Owned by the main session — change only by agreement.
import Foundation

public enum Lang: Equatable, Sendable { case en, vi, zh }

/// Vietnamese tone placement style.
public enum ToneStyle: Sendable { case new /* hoà, thuý */, old /* hòa, thúy */ }

/// Telex: raw Latin letters → Vietnamese word, or nil when the result is not a valid Vietnamese syllable
/// or the raw letters contain no Telex action.  (`vieetj` → "việt", `class` → nil, `ma` → nil)
public protocol TelexTransforming: Sendable {
    func transform(_ raw: String, style: ToneStyle) -> String?
}

/// Pinyin dictionary + parser.  Input is letters with optional tone digits 0–5, e.g. "xiao4yang2shangshan".
public protocol PinyinLookup: Sendable {
    /// True when `letters` (no digits) ends with a complete valid pinyin syllable and the whole
    /// string segments into valid syllables, e.g. "nihao" ✓, "mp" ✗, "iphone" ✗.
    func segmentsAsPinyin(_ letters: String) -> Bool
    /// Ranked candidates: exact-tone matches first by frequency, then closest (wrong-tone) matches.
    /// Each candidate covers the whole input (phrase), or a prefix of it when no phrase exists.
    func candidates(for input: String, traditional: Bool, limit: Int) -> [PinyinCandidate]
}

public struct PinyinCandidate: Equatable, Sendable {
    public let text: String          // 你好
    public let consumed: Int         // how many characters of the input (letters+digits) this covers
    public init(text: String, consumed: Int) { self.text = text; self.consumed = consumed }
}

/// English vocabulary.
public protocol EnglishLexicon: Sendable {
    func isWord(_ w: String) -> Bool   // case-insensitive
}

// MARK: - Composer contract (implemented in Composer.swift, used by the IMK app)

public enum KeyInput: Equatable, Sendable {
    case char(Character)      // printable character as typed (letters, digits, punctuation)
    case space, enter, escape, backspace, tab
    case other                // arrows, function keys, anything with ⌘/⌃ — composer commits and passes it on
}

public struct ComposerOutput: Equatable, Sendable {
    public var commit: String = ""        // text to insert for good
    public var marked: String = ""        // in-progress text shown underlined
    public var candidates: [String] = []  // Chinese candidate bar (empty = hide)
    public var handled: Bool = true       // false = let the app receive the key itself (after `commit`)
    public init(commit: String = "", marked: String = "", candidates: [String] = [], handled: Bool = true) {
        self.commit = commit; self.marked = marked; self.candidates = candidates; self.handled = handled
    }
}

public struct ComposerSettings: Sendable {
    public var traditional = false
    public var toneStyle: ToneStyle = .new
    public init() {}
}
