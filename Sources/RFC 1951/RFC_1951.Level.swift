extension RFC_1951 {

    public enum Level: Int, Sendable, Hashable, Codable, CaseIterable {

        case none = 0

        case fast = 1

        case balanced = 5

        case best = 9
    }
}
