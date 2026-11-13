import Byte

@testable import RFC_1951

extension Reference {

    static func compress(_ input: [Byte], level: RFC_1951.Level) -> [Byte] {
        var writer = BitWriter()
        if input.isEmpty {
            encodeStoredBlock(input[...], isFinal: true, into: &writer)
            return writer.finish()
        }
        let chunkSize = level == .none ? 65535 : 32768
        var position = 0
        while position < input.count {
            let size = min(input.count - position, chunkSize)
            let isFinal = position + size >= input.count
            let chunk = Array(input[position..<(position + size)])
            if level == .none {
                encodeStoredBlock(chunk[...], isFinal: isFinal, into: &writer)
            } else {
                let tokens = LZ77.tokens(chunk, level: level)
                var bits = 3 + 7
                for token in tokens {
                    switch token {
                    case .literal: bits += 9
                    case .reference: bits += 15
                    }
                }
                if chunk.count + 5 <= (bits + 7) / 8 {
                    encodeStoredBlock(chunk[...], isFinal: isFinal, into: &writer)
                } else {
                    encodeFixedHuffmanBlock(tokens, isFinal: isFinal, into: &writer)
                }
            }
            position += size
        }
        return writer.finish()
    }

    private static func encodeStoredBlock(_ data: ArraySlice<Byte>, isFinal: Bool, into writer: inout BitWriter) {
        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(0, count: 2)
        writer.alignToByte()
        let len = UInt16(data.count)
        let nlen = ~len
        writer.writeBytes([Byte(UInt8(len & 0xFF)), Byte(UInt8(len >> 8))])
        writer.writeBytes([Byte(UInt8(nlen & 0xFF)), Byte(UInt8(nlen >> 8))])
        writer.writeBytes(Array(data))
    }

    static func encodeFixedHuffmanBlock(
        _ tokens: [RFC_1951.LZ77Token],
        isFinal: Bool,
        into writer: inout BitWriter
    ) {
        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(1, count: 2)
        for token in tokens {
            switch token {
            case .literal(let byte):
                encodeFixedLiteral(Int(byte.underlying), into: &writer)

            case .reference(let length, let distance):
                let (lengthCode, lengthExtra, lengthExtraBits) = lengthCode(length)
                encodeFixedLiteral(lengthCode, into: &writer)
                writer.writeBits(UInt32(lengthExtra), count: lengthExtraBits)
                let (distCode, distExtra, distExtraBits) = distanceCode(distance)
                writer.writeBitsReversed(UInt32(distCode), count: 5)
                writer.writeBits(UInt32(distExtra), count: distExtraBits)
            }
        }
        encodeFixedLiteral(256, into: &writer)
    }

    private static func encodeFixedLiteral(_ value: Int, into writer: inout BitWriter) {
        if value <= 143 {
            writer.writeBitsReversed(UInt32(0x30 + value), count: 8)
        } else if value <= 255 {
            writer.writeBitsReversed(UInt32(0x190 + (value - 144)), count: 9)
        } else if value <= 279 {
            writer.writeBitsReversed(UInt32(value - 256), count: 7)
        } else if value <= 287 {
            writer.writeBitsReversed(UInt32(0xC0 + (value - 280)), count: 8)
        }
    }

    static func lengthCode(_ length: Int) -> (code: Int, extra: Int, extraBits: Int) {
        let bases = RFC_1951.lengthBase
        for (i, base) in bases.enumerated() {
            let nextBase = bases.indices.contains(i + 1) ? bases[i + 1] : 259
            if length >= base && length < nextBase {
                return (257 + i, length - base, RFC_1951.lengthExtraBits[i])
            }
        }
        return (285, 0, 0)
    }

    static func distanceCode(_ distance: Int) -> (code: Int, extra: Int, extraBits: Int) {
        let bases = RFC_1951.distanceBase
        for (i, base) in bases.enumerated() {
            let nextBase = bases.indices.contains(i + 1) ? bases[i + 1] : 32769
            if distance >= base && distance < nextBase {
                return (i, distance - base, RFC_1951.distanceExtraBits[i])
            }
        }
        return (29, distance - bases[29], RFC_1951.distanceExtraBits[29])
    }
}
