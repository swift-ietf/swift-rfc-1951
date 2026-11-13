internal import Byte

extension RFC_1951 {

    struct LZ77 {

        private var head: [Int32]
        private var previous: [Int32]

        init() {
            head = [Int32](repeating: -1, count: Self.hashSize)
            previous = [Int32](repeating: -1, count: Self.maxDistance)
        }
    }
}

extension RFC_1951.LZ77 {

    static let maxDistance = 32768

    static let maxLength = 258

    static let minMatch = 3

    static let hashSize = 1 << 15

    @inline(__always)
    private static func hash(of bytes: UnsafeRawBufferPointer, at position: Int) -> Int {
        let packed =
            Int(unsafe bytes[position]) | (Int(unsafe bytes[position + 1]) << 8)
            | (Int(unsafe bytes[position + 2]) << 16)
        return ((packed &* 2_654_435_761) >> 9) & (hashSize - 1)
    }

    @inline(__always)
    private static func matchLength(
        in bytes: UnsafeRawBufferPointer,
        _ candidate: Int,
        _ position: Int,
        limit: Int
    ) -> Int {
        var length = 0
        while length &+ 8 <= limit {
            let a = unsafe bytes.loadUnaligned(fromByteOffset: candidate &+ length, as: UInt64.self)
            let b = unsafe bytes.loadUnaligned(fromByteOffset: position &+ length, as: UInt64.self)
            let difference = UInt64(littleEndian: a) ^ UInt64(littleEndian: b)
            guard difference == 0 else {
                return length &+ difference.trailingZeroBitCount &>> 3
            }
            length &+= 8
        }
        while unsafe length < limit && bytes[candidate &+ length] == bytes[position &+ length] {
            length &+= 1
        }
        return length
    }

    @inline(__always)
    private static func findMatch(
        in bytes: UnsafeRawBufferPointer,
        at position: Int,
        head: UnsafeMutableBufferPointer<Int32>,
        previous: UnsafeMutableBufferPointer<Int32>,
        maxLazyMatch: Int,
        maxChain: Int
    ) -> (length: Int, distance: Int)? {
        guard position + minMatch <= bytes.count else { return nil }

        var bestLength = minMatch - 1
        var bestDistance = 0
        let limit = min(maxLength, bytes.count - position)
        var candidate = Int(unsafe head[hash(of: bytes, at: position)])
        var chain = maxChain

        while candidate >= 0, chain > 0 {
            let distance = position - candidate
            guard distance > 0, distance <= maxDistance else { break }

            let length = unsafe matchLength(in: bytes, candidate, position, limit: limit)

            if length > bestLength {
                bestLength = length
                bestDistance = distance
                if length >= maxLazyMatch || length == limit { break }
            }

            let next = Int(unsafe previous[candidate & (maxDistance - 1)])
            guard next < candidate else { break }
            candidate = next
            chain -= 1
        }

        guard bestLength >= minMatch else { return nil }
        return (bestLength, bestDistance)
    }

    @inline(__always)
    private static func updateHash(
        for bytes: UnsafeRawBufferPointer,
        at position: Int,
        head: UnsafeMutableBufferPointer<Int32>,
        previous: UnsafeMutableBufferPointer<Int32>
    ) {
        guard position + 2 < bytes.count else { return }

        let h = unsafe hash(of: bytes, at: position)
        unsafe previous[position & (maxDistance - 1)] = head[h]
        unsafe head[h] = Int32(truncatingIfNeeded: position)
    }

    mutating func encode(
        _ input: [Byte],
        lazyMatchThreshold: Int,
        maxChain: Int,
        into tokens: inout [RFC_1951.LZ77Token]
    ) {
        precondition(input.count <= Int(Int32.max), "LZ77 positions fit in 32 bits")
        input.withUnsafeBytes { bytes in
            head.withUnsafeMutableBufferPointer { head in
                previous.withUnsafeMutableBufferPointer { previous in
                    var position = 0
                    while position < bytes.count {
                        if let match = unsafe Self.findMatch(
                            in: bytes,
                            at: position,
                            head: head,
                            previous: previous,
                            maxLazyMatch: lazyMatchThreshold,
                            maxChain: maxChain
                        ) {
                            tokens.append(.reference(length: match.length, distance: match.distance))

                            for offset in 0..<match.length {
                                unsafe Self.updateHash(
                                    for: bytes,
                                    at: position + offset,
                                    head: head,
                                    previous: previous
                                )
                            }
                            position += match.length
                        } else {
                            tokens.append(.literal(input[position]))
                            unsafe Self.updateHash(for: bytes, at: position, head: head, previous: previous)
                            position += 1
                        }
                    }
                }
            }
        }
    }
}

extension RFC_1951 {

    static func encodeLZ77(_ input: [Byte], level: Level) -> [LZ77Token] {
        if level == .none || input.isEmpty {
            return input.map { .literal($0) }
        }

        var tokens: [LZ77Token] = []
        tokens.reserveCapacity(input.count)

        let lazyMatchThreshold: Int
        let maxChain: Int
        switch level {
        case .none: (lazyMatchThreshold, maxChain) = (0, 0)
        case .fast: (lazyMatchThreshold, maxChain) = (8, 4)
        case .balanced: (lazyMatchThreshold, maxChain) = (32, 32)
        case .best: (lazyMatchThreshold, maxChain) = (258, 4096)
        }

        var lz77 = LZ77()
        lz77.encode(input, lazyMatchThreshold: lazyMatchThreshold, maxChain: maxChain, into: &tokens)
        return tokens
    }
}
