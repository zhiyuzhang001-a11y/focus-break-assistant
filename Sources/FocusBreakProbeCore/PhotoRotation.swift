import Foundation

public struct PhotoRotation: Codable {
    private var remaining: [String] = []
    private var known: [String] = []
    private var lastShown: String?

    public init() {}

    public mutating func next(in photos: [String], avoiding: Set<String> = []) -> String? {
        let current = Array(Set(photos)).sorted()
        guard !current.isEmpty else { return nil }
        if current != known {
            remaining = []
            known = current
        }
        if remaining.isEmpty {
            remaining = current.shuffled()
            if remaining.count > 1, let lastShown, let index = remaining.firstIndex(of: lastShown) {
                remaining.remove(at: index)
                remaining.insert(lastShown, at: 0)
            }
        }
        if let index = remaining.lastIndex(where: { !avoiding.contains($0) && (remaining.count == 1 || $0 != lastShown) }) {
            return remaining.remove(at: index)
        }
        return remaining.popLast()
    }

    public mutating func didShow(_ photo: String) { lastShown = photo }
}
