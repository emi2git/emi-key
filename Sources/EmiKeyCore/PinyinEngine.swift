import Foundation
// STUB — owned by agent "pinyin".
public final class PinyinEngine: PinyinLookup, @unchecked Sendable {
    public init(resources: URL) {}
    public func segmentsAsPinyin(_ letters: String) -> Bool { false }
    public func candidates(for input: String, traditional: Bool, limit: Int) -> [PinyinCandidate] { [] }
}
