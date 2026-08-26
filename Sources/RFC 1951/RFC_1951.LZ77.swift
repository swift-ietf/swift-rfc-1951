internal import Byte
internal import Byte_Standard_Library_Integration

extension RFC_1951 {

    struct LZ77 {

        private var hashTable: [Int: [Int]]
        private var windowStart: Int = 0

        init() {
            hashTable = [:]
        }
    }
}

extension RFC_1951.LZ77 {

    static let maxDistance = 32768

    static let maxLength = 258

    static let minMatch = 3

    private func hash(of bytes: [Byte], at position: Int) -> Int {
        guard position + 2 < bytes.count else { return 0 }
        return Int(bytes[position]) | (Int(bytes[position + 1]) << 8)
            | (Int(bytes[position + 2]) << 16)
    }

    mutating func findMatch(
        in bytes: [Byte],
        at position: Int,
        maxLazyMatch: Int
    ) -> (length: Int, distance: Int)? {
        guard position + Self.minMatch <= bytes.count else { return nil }

        let h = hash(of: bytes, at: position)
        var bestLength = Self.minMatch - 1
        var bestDistance = 0

        if let candidates = hashTable[h] {
            let minPos = max(0, position - Self.maxDistance)

            for candidatePos in candidates.reversed() {
                guard candidatePos >= minPos else { break }

                let distance = position - candidatePos
                guard distance > 0, distance <= Self.maxDistance else { continue }

                var length = 0
                while position + length < bytes.count && length < Self.maxLength
                    && bytes[candidatePos + length] == bytes[position + length]
                {
                    length += 1
                }

                if length > bestLength {
                    bestLength = length
                    bestDistance = distance

                    if length >= maxLazyMatch {
                        break
                    }
                }
            }
        }

        guard bestLength >= Self.minMatch else { return nil }
        return (bestLength, bestDistance)
    }

    mutating func updateHash(for bytes: [Byte], at position: Int) {
        guard position + 2 < bytes.count else { return }

        let h = hash(of: bytes, at: position)
        if hashTable[h] == nil {
            hashTable[h] = []
        }
        hashTable[h]!.append(position)

        let minPos = max(0, position - Self.maxDistance)
        hashTable[h] = hashTable[h]!.filter { $0 >= minPos }
    }

    mutating func reset() {
        hashTable.removeAll()
        windowStart = 0
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
        switch level {
        case .none: lazyMatchThreshold = 0
        case .fast: lazyMatchThreshold = 8
        case .balanced: lazyMatchThreshold = 32
        case .best: lazyMatchThreshold = 258
        }

        while position < input.count {
            if let match = lz77.findMatch(in: input, at: position, maxLazyMatch: lazyMatchThreshold)
            {
                tokens.append(.reference(length: match.length, distance: match.distance))

                (0..<match.length).forEach { i in
                    lz77.updateHash(for: input, at: position + i)
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
