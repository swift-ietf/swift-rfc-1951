import Byte

@testable import RFC_1951

extension Corpus {

    static func completeLengths(count: Int, maxLength: Int, using rng: inout Seeded) -> [Int] {
        guard count > 1 else {
            return [Int](repeating: 1, count: count)
        }
        var depths = [0]
        while depths.count < count {
            let index = Int.random(in: depths.indices, using: &rng)
            guard depths[index] < maxLength else { continue }
            let depth = depths[index] + 1
            depths[index] = depth
            depths.append(depth)
        }
        depths.shuffle(using: &rng)
        return depths
    }

    static func canonicalCodes(_ lengths: [Int]) -> [Int] {
        var blCount = [Int](repeating: 0, count: 16)
        for length in lengths where length > 0 {
            blCount[length] += 1
        }
        var nextCode = [Int](repeating: 0, count: 16)
        var code = 0
        for bits in 1...15 {
            code = (code + blCount[bits - 1]) << 1
            nextCode[bits] = code
        }
        return lengths.map { length in
            guard length > 0 else { return 0 }
            defer { nextCode[length] += 1 }
            return nextCode[length]
        }
    }

    static func tokens(
        count: Int,
        referenceShare: Double,
        maxDistance: Int = 32768,
        using rng: inout Seeded
    ) -> [RFC_1951.LZ77Token] {
        var produced = 0
        var tokens: [RFC_1951.LZ77Token] = []
        for _ in 0..<count {
            if produced > 0, Double.random(in: 0..<1, using: &rng) < referenceShare {
                let length = Int.random(in: 3...258, using: &rng)
                let distance = Int.random(in: 1...min(produced, maxDistance), using: &rng)
                tokens.append(.reference(length: length, distance: distance))
                produced += length
            } else {
                tokens.append(.literal(Byte(UInt8.random(in: 0...255, using: &rng))))
                produced += 1
            }
        }
        return tokens
    }

    static func writeDynamicHeader(
        literalLengths: [Int],
        distanceLengths: [Int],
        codeLengthLengths: [Int],
        useRuns: Bool,
        isFinal: Bool,
        into writer: inout Reference.BitWriter
    ) {
        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(2, count: 2)
        writer.writeBits(UInt32(literalLengths.count - 257), count: 5)
        writer.writeBits(UInt32(distanceLengths.endIndex - 1), count: 5)
        writer.writeBits(15, count: 4)
        for symbol in RFC_1951.codeLengthOrder {
            writer.writeBits(UInt32(codeLengthLengths[symbol]), count: 3)
        }
        let codes = canonicalCodes(codeLengthLengths)
        func emit(_ symbol: Int) {
            writer.writeBitsReversed(UInt32(codes[symbol]), count: codeLengthLengths[symbol])
        }
        let all = literalLengths + distanceLengths
        var i = 0
        while i < all.count {
            let value = all[i]
            var run = 1
            while i + run < all.count && all[i + run] == value {
                run += 1
            }
            if useRuns && value == 0 && run >= 11 {
                let n = min(run, 138)
                emit(18)
                writer.writeBits(UInt32(n - 11), count: 7)
                i += n
            } else if useRuns && value == 0 && run >= 3 {
                let n = min(run, 10)
                emit(17)
                writer.writeBits(UInt32(n - 3), count: 3)
                i += n
            } else if useRuns && i > 0 && all[i - 1] == value && run >= 3 {
                let n = min(run, 6)
                emit(16)
                writer.writeBits(UInt32(n - 3), count: 2)
                i += n
            } else {
                emit(value)
                i += 1
            }
        }
    }

    static func dynamicBlock(
        _ tokens: [RFC_1951.LZ77Token],
        literalLengths: [Int],
        distanceLengths: [Int],
        codeLengthLengths: [Int],
        useRuns: Bool,
        isFinal: Bool,
        into writer: inout Reference.BitWriter
    ) {
        writeDynamicHeader(
            literalLengths: literalLengths,
            distanceLengths: distanceLengths,
            codeLengthLengths: codeLengthLengths,
            useRuns: useRuns,
            isFinal: isFinal,
            into: &writer
        )
        let literalCodes = canonicalCodes(literalLengths)
        let distanceCodes = canonicalCodes(distanceLengths)
        func literal(_ symbol: Int) {
            writer.writeBitsReversed(UInt32(literalCodes[symbol]), count: literalLengths[symbol])
        }
        for token in tokens {
            switch token {
            case .literal(let byte):
                literal(Int(byte.underlying))

            case .reference(let length, let distance):
                let (lengthCode, lengthExtra, lengthBits) = Reference.lengthCode(length)
                literal(lengthCode)
                writer.writeBits(UInt32(lengthExtra), count: lengthBits)
                let (distanceCode, distanceExtra, distanceBits) = Reference.distanceCode(distance)
                writer.writeBitsReversed(UInt32(distanceCodes[distanceCode]), count: distanceLengths[distanceCode])
                writer.writeBits(UInt32(distanceExtra), count: distanceBits)
            }
        }
        literal(256)
    }

    static func fixedStream(_ tokens: [RFC_1951.LZ77Token]) -> [Byte] {
        var writer = Reference.BitWriter()
        Reference.encodeFixedHuffmanBlock(tokens, isFinal: true, into: &writer)
        return writer.finish()
    }
}
