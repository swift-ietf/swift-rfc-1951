// RFC_1951.LZ77.swift

extension RFC_1951 {
    /// LZ77 compression engine
    ///
    /// Finds repeated sequences in the input and represents them as
    /// (length, distance) pairs.
    struct LZ77 {
        /// Maximum backward distance (32KB window)
        static let maxDistance = 32768

        /// Maximum match length
        static let maxLength = 258

        /// Minimum match length (shorter matches aren't worth encoding)
        static let minMatch = 3

        /// Hash table for finding matches
        private var hashTable: [Int: [Int]]  // hash -> list of positions
        private var windowStart: Int = 0

        init() {
            hashTable = [:]
        }

        /// Compute hash for 3 bytes at position
        private func hash(of bytes: [UInt8], at position: Int) -> Int {
            guard position + 2 < bytes.count else { return 0 }
            return Int(bytes[position]) | (Int(bytes[position + 1]) << 8)
                | (Int(bytes[position + 2]) << 16)
        }

        /// Find the longest match at the current position
        mutating func findMatch(
            in bytes: [UInt8],
            at position: Int,
            maxLazyMatch: Int
        ) -> (length: Int, distance: Int)? {
            guard position + Self.minMatch <= bytes.count else { return nil }

            let h = hash(of: bytes, at: position)
            var bestLength = Self.minMatch - 1
            var bestDistance = 0

            if let candidates = hashTable[h] {
                let minPos = max(0, position - Self.maxDistance)

                // Search from most recent to oldest
                for candidatePos in candidates.reversed() {
                    guard candidatePos >= minPos else { break }

                    let distance = position - candidatePos
                    guard distance > 0, distance <= Self.maxDistance else { continue }

                    // Count matching bytes
                    var length = 0
                    while position + length < bytes.count && length < Self.maxLength
                        && bytes[candidatePos + length] == bytes[position + length]
                    {
                        length += 1
                    }

                    if length > bestLength {
                        bestLength = length
                        bestDistance = distance

                        // Early exit for long matches
                        if length >= maxLazyMatch {
                            break
                        }
                    }
                }
            }

            guard bestLength >= Self.minMatch else { return nil }
            return (bestLength, bestDistance)
        }

        /// Update hash table with current position
        mutating func updateHash(for bytes: [UInt8], at position: Int) {
            guard position + 2 < bytes.count else { return }

            let h = hash(of: bytes, at: position)
            if hashTable[h] == nil {
                hashTable[h] = []
            }
            hashTable[h]!.append(position)

            // Prune old entries outside the window
            let minPos = max(0, position - Self.maxDistance)
            hashTable[h] = hashTable[h]!.filter { $0 >= minPos }
        }

        /// Reset the compressor state
        mutating func reset() {
            hashTable.removeAll()
            windowStart = 0
        }
    }
}

// MARK: - LZ77 Token

extension RFC_1951 {
    /// A token in the LZ77-encoded stream
    enum LZ77Token {
        /// A literal byte
        case literal(UInt8)
        /// A back-reference (length, distance)
        case reference(length: Int, distance: Int)
    }

    /// Encode input bytes to LZ77 tokens
    static func encodeLZ77(_ input: [UInt8], level: Level) -> [LZ77Token] {
        if level == .none || input.isEmpty {
            return input.map { .literal($0) }
        }

        var tokens: [LZ77Token] = []
        tokens.reserveCapacity(input.count)

        var lz77 = LZ77()
        var position = 0

        // Lazy match threshold based on compression level
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

                // Update hash for all positions in the match
                for i in 0..<match.length {
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
