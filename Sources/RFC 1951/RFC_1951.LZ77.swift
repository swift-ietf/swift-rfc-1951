internal import Byte

extension RFC_1951 {

    struct LZ77 {

        private var head: [Int]
        private var previous: [Int]

        init() {
            head = [Int](repeating: -1, count: Self.hashSize)
            previous = [Int](repeating: -1, count: Self.maxDistance)
        }
    }
}

extension RFC_1951.LZ77 {

    static let maxDistance = 32768

    static let maxLength = 258

    static let minMatch = 3

    static let hashSize = 1 << 15

    private static func hash(of bytes: [Byte], at position: Int) -> Int {
        let packed =
            Int(bytes[position].underlying) | (Int(bytes[position + 1].underlying) << 8)
            | (Int(bytes[position + 2].underlying) << 16)
        return ((packed &* 2_654_435_761) >> 9) & (hashSize - 1)
    }

    func findMatch(
        in bytes: [Byte],
        at position: Int,
        maxLazyMatch: Int,
        maxChain: Int
    ) -> (length: Int, distance: Int)? {
        guard position + Self.minMatch <= bytes.count else { return nil }

        var bestLength = Self.minMatch - 1
        var bestDistance = 0
        let limit = min(Self.maxLength, bytes.count - position)
        var candidate = head[Self.hash(of: bytes, at: position)]
        var chain = maxChain

        while candidate >= 0, chain > 0 {
            let distance = position - candidate
            guard distance > 0, distance <= Self.maxDistance else { break }

            var length = 0
            while length < limit && bytes[candidate + length] == bytes[position + length] {
                length += 1
            }

            if length > bestLength {
                bestLength = length
                bestDistance = distance
                if length >= maxLazyMatch || length == limit { break }
            }

            let next = previous[candidate & (Self.maxDistance - 1)]
            guard next < candidate else { break }
            candidate = next
            chain -= 1
        }

        guard bestLength >= Self.minMatch else { return nil }
        return (bestLength, bestDistance)
    }

    mutating func updateHash(for bytes: [Byte], at position: Int) {
        guard position + 2 < bytes.count else { return }

        let h = Self.hash(of: bytes, at: position)
        previous[position & (Self.maxDistance - 1)] = head[h]
        head[h] = position
    }
}

extension RFC_1951 {

    static func encodeLZ77(_ input: [Byte], level: Level) -> [LZ77Token] {
        if level == .none || input.isEmpty {
            return input.map { .literal($0) }
        }

        var tokens: [LZ77Token] = []
        tokens.reserveCapacity(input.count)

        var lz77 = LZ77()
        var position = 0

        let lazyMatchThreshold: Int
        let maxChain: Int
        switch level {
        case .none: (lazyMatchThreshold, maxChain) = (0, 0)
        case .fast: (lazyMatchThreshold, maxChain) = (8, 4)
        case .balanced: (lazyMatchThreshold, maxChain) = (32, 32)
        case .best: (lazyMatchThreshold, maxChain) = (258, 4096)
        }

        while position < input.count {
            if let match = lz77.findMatch(in: input, at: position, maxLazyMatch: lazyMatchThreshold, maxChain: maxChain) {
                tokens.append(.reference(length: match.length, distance: match.distance))

                (0..<match.length).forEach { offset in
                    lz77.updateHash(for: input, at: position + offset)
                }
                position += match.length
            } else {
                tokens.append(.literal(input[position]))
                lz77.updateHash(for: input, at: position)
                position += 1
            }
        }

        return tokens
    }
}
