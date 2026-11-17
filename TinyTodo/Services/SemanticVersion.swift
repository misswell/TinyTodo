import Foundation

/// Numeric semantic version (`1.1.0`, `v1.1.0`, `1.1` all parse). Pre-release suffixes are not used
/// by TinyTodo releases and are rejected rather than guessed at.
struct SemanticVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    private let components: [Int]

    init?(_ raw: String) {
        let normalized = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let pieces = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              pieces.count <= 4 else {
            return nil
        }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == pieces.count else { return nil }
        self.components = numbers
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        normalized(lhs.components) == normalized(rhs.components)
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(Self.normalized(components))
    }

    private static func normalized(_ components: [Int]) -> [Int] {
        var result = components
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return result
    }
}
