import Foundation

/// English vocabulary loaded from `english.txt` (one lowercase word per line).
public final class EnglishWords: EnglishLexicon, @unchecked Sendable {
    private let words: Set<String>

    public init(resources: URL) {
        let url = resources.appendingPathComponent("english.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var set = Set<String>(minimumCapacity: 40_000)
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let w = line.trimmingCharacters(in: .whitespaces)
            if !w.isEmpty { set.insert(w.lowercased()) }
        }
        words = set
    }

    public var count: Int { words.count }

    public func isWord(_ w: String) -> Bool { words.contains(w.lowercased()) }
}
