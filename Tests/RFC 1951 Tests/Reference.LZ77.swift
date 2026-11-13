import Byte

@testable import RFC_1951

extension Reference {

    struct LZ77 {
        private var head = [Int](repeating: -1, count: 1 << 15)
        private var previous = [Int](repeating: -1, count: 32768)
    }
}

extension Reference.LZ77 {

    private static func hash(of bytes: [Byte], at position: Int) -> Int {
        let packed =
            Int(bytes[position].underlying) | (Int(bytes[position + 1].underlying) << 8)
            | (Int(bytes[position + 2].underlying) << 16)
        return ((packed &* 2_654_435_761) >> 9) & ((1 << 15) - 1)
    }

    private func findMatch(
        in bytes: [Byte],
        at position: Int,
        maxLazyMatch: Int,
        maxChain: Int
    ) -> (length: Int, distance: Int)? {
        guard position + 3 <= bytes.count else { return nil }
        var bestLength = 2
        var bestDistance = 0
        let limit = min(258, bytes.count - position)
        var candidate = head[Self.hash(of: bytes, at: position)]
        var chain = maxChain
        while candidate >= 0, chain > 0 {
            let distance = position - candidate
            guard distance > 0, distance <= 32768 else { break }
            var length = 0
            while length < limit && bytes[candidate + length] == bytes[position + length] {
                length += 1
            }
            if length > bestLength {
                bestLength = length
                bestDistance = distance
                if length >= maxLazyMatch || length == limit { break }
            }
            let next = previous[candidate & 32767]
            guard next < candidate else { break }
            candidate = next
            chain -= 1
        }
        guard bestLength >= 3 else { return nil }
        return (bestLength, bestDistance)
    }

    private mutating func updateHash(for bytes: [Byte], at position: Int) {
        guard position + 2 < bytes.count else { return }
        let h = Self.hash(of: bytes, at: position)
        previous[position & 32767] = head[h]
        head[h] = position
    }

    static func tokens(_ input: [Byte], level: RFC_1951.Level) -> [RFC_1951.LZ77Token] {
        if level == .none || input.isEmpty {
            return input.map { .literal($0) }
        }
        let (lazy, maxChain): (Int, Int)
        switch level {
        case .none: (lazy, maxChain) = (0, 0)
        case .fast: (lazy, maxChain) = (8, 4)
        case .balanced: (lazy, maxChain) = (32, 32)
        case .best: (lazy, maxChain) = (258, 4096)
        }
        var lz77 = Reference.LZ77()
        var tokens: [RFC_1951.LZ77Token] = []
        var position = 0
        while position < input.count {
            if let match = lz77.findMatch(in: input, at: position, maxLazyMatch: lazy, maxChain: maxChain) {
                tokens.append(.reference(length: match.length, distance: match.distance))
                for offset in 0..<match.length {
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
