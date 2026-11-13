internal import Byte

extension RFC_1951 {

    enum BlockType: UInt8 {

        case stored = 0

        case fixedHuffman = 1

        case dynamicHuffman = 2

        case reserved = 3
    }

    static let maxStoredBlockSize = 65535
}

extension RFC_1951 {

    static func encodeStoredBlock(
        data: ArraySlice<Byte>,
        isFinal: Bool,
        into writer: inout BitWriter
    ) {

        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(0, count: 2)

        writer.alignToByte()

        let len = UInt16(data.count)
        let nlen = ~len
        writer.writeUInt16LE(len)
        writer.writeUInt16LE(nlen)

        writer.writeBytes(data)
    }

    static func encodeFixedHuffmanBlock(
        tokens: [LZ77Token],
        isFinal: Bool,
        into writer: inout BitWriter
    ) {

        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(1, count: 2)
        writer.reserveCapacity(tokens.count * 2 + 8)

        fixedLiteralCodes.withUnsafeBufferPointer { literalCodes in
            for token in tokens {
                switch token {
                case .literal(let byte):
                    unsafe writeCode(literalCodes[Int(byte.underlying)], into: &writer)

                case .reference(let length, let distance):
                    unsafe encodeFixedLengthDistance(
                        length: length,
                        distance: distance,
                        literalCodes: literalCodes,
                        into: &writer
                    )
                }
            }
        }

        encodeFixedLiteral(256, into: &writer)
    }

    @inline(__always)
    private static func writeCode(_ code: UInt32, into writer: inout BitWriter) {
        writer.writeBits(code & 0xFFFF, count: Int(code >> 16))
    }

    static let fixedLiteralCodes: [UInt32] = (0..<288).map { value in
        let (code, count) = fixedLiteralCode(value)
        var reversed: UInt32 = 0
        var remaining = UInt32(code)
        for _ in 0..<count {
            reversed = reversed << 1 | remaining & 1
            remaining >>= 1
        }
        return reversed | UInt32(count) << 16
    }

    private static func fixedLiteralCode(_ value: Int) -> (code: Int, count: Int) {
        if value <= 143 {
            return (0x30 + value, 8)
        } else if value <= 255 {
            return (0x190 + (value - 144), 9)
        } else if value <= 279 {
            return (value - 256, 7)
        } else {
            return (0xC0 + (value - 280), 8)
        }
    }

    private static func encodeFixedLiteral(
        _ value: Int,
        into writer: inout BitWriter
    ) {
        writeCode(fixedLiteralCodes[value], into: &writer)
    }

    @inline(__always)
    private static func encodeFixedLengthDistance(
        length: Int,
        distance: Int,
        literalCodes: UnsafeBufferPointer<UInt32>,
        into writer: inout BitWriter
    ) {

        let (lengthCode, lengthExtra, lengthExtraBits) = encodeLengthCode(length)
        unsafe writeCode(literalCodes[lengthCode], into: &writer)
        writer.writeBits(UInt32(lengthExtra), count: lengthExtraBits)

        let (distCode, distExtra, distExtraBits) = encodeDistanceCode(distance)
        writer.writeBitsReversed(UInt32(distCode), count: 5)
        writer.writeBits(UInt32(distExtra), count: distExtraBits)
    }

    static func encodeLengthCode(_ length: Int) -> (code: Int, extra: Int, extraBits: Int) {
        guard length >= 3, length <= 258 else {
            return (285, 0, 0)
        }
        let index = Int(lengthCodeIndex[length])
        return (257 + index, length - lengthBase[index], lengthExtraBits[index])
    }

    static func encodeDistanceCode(
        _ distance: Int
    ) -> (code: Int, extra: Int, extraBits: Int) {
        let index: Int
        if distance >= 1, distance <= 256 {
            index = Int(distanceCodeIndex[distance - 1])
        } else if distance > 256, distance <= 32768 {
            index = Int(distanceCodeIndex[256 + ((distance - 1) >> 7)])
        } else {
            index = 29
        }
        return (index, distance - distanceBase[index], distanceExtraBits[index])
    }

    static let lengthCodeIndex: [UInt8] = (0...258).map { length in
        UInt8(lengthBase.lastIndex { $0 <= length } ?? 0)
    }

    static let distanceCodeIndex: [UInt8] =
        (1...256).map { distance in
            UInt8(distanceBase.lastIndex { $0 <= distance } ?? 0)
        }
        + (0..<256).map { high in
            UInt8(distanceBase.lastIndex { $0 <= (high << 7) + 1 } ?? 0)
        }
}

extension RFC_1951 {

    static func decodeBlock(
        from reader: inout BitReader,
        into window: inout Window
    ) throws(Error) -> Bool {

        let isFinal = try reader.readBit() == 1
        let btype = try reader.readBits(2)

        guard let blockType = BlockType(rawValue: UInt8(btype)) else {
            throw .invalidBlockType(Byte(UInt8(btype)))
        }

        switch blockType {
        case .stored:
            try decodeStoredBlock(from: &reader, into: &window)

        case .fixedHuffman:
            try decodeHuffmanBlock(
                from: &reader,
                literalTree: fixedLiteralLengthTree,
                distanceTree: fixedDistanceTree,
                into: &window
            )

        case .dynamicHuffman:
            let (literalTree, distanceTree) = try readDynamicTrees(from: &reader)
            try decodeHuffmanBlock(
                from: &reader,
                literalTree: literalTree,
                distanceTree: distanceTree,
                into: &window
            )

        case .reserved:
            throw .invalidBlockType(Byte(3))
        }

        return isFinal
    }

    private static func decodeStoredBlock(
        from reader: inout BitReader,
        into window: inout Window
    ) throws(Error) {

        reader.alignToByte()

        let len = try reader.readUInt16LE()
        let nlen = try reader.readUInt16LE()

        guard len == ~nlen else {
            throw .invalidStoredBlockLength
        }

        try reader.readBytes(Int(len), into: &window)
    }

    private static func decodeHuffmanBlock(
        from reader: inout BitReader,
        literalTree: borrowing HuffmanTree,
        distanceTree: borrowing HuffmanTree,
        into window: inout Window
    ) throws(Error) {
        try literalTree.table.withUnsafeBufferPointer { literal throws(Error) in
            try distanceTree.table.withUnsafeBufferPointer { distance throws(Error) in
                try unsafe decodeSymbols(
                    from: &reader,
                    into: &window,
                    literal: literal,
                    literalTree: literalTree,
                    distance: distance,
                    distanceTree: distanceTree
                )
            }
        }
    }

    @inline(never)
    private static func decodePlain(
        _ tree: borrowing HuffmanTree,
        from reader: inout BitReader
    ) throws(Error) -> UInt32 {
        try tree.decode(from: &reader)
    }

    private static func decodeSymbols(
        from reader: inout BitReader,
        into window: inout Window,
        literal: UnsafeBufferPointer<UInt32>,
        literalTree: borrowing HuffmanTree,
        distance: UnsafeBufferPointer<UInt32>,
        distanceTree: borrowing HuffmanTree
    ) throws(Error) {
        let literalIsPlain = literalTree.isOversubscribed
        let distanceIsPlain = distanceTree.isOversubscribed
        var bits = reader
        var out = window
        defer {
            reader = bits
            window = out
        }
        while true {
            out.reserve(Window.slack)
            if bits.available < 15 {
                bits.refill()
            }
            let entry: UInt32
            if literalIsPlain {
                reader = bits
                entry = try decodePlain(literalTree, from: &reader)
                bits = reader
            } else {
                entry = try unsafe HuffmanTree.decode(literal, from: &bits)
            }

            switch entry >> kindShift {
            case kindLiteral:
                out.append(UInt8(truncatingIfNeeded: entry))

            case kindEnd:
                return

            case kindLengthOrDistance:
                bits.refill()
                let length = Int(entry & 0xFFFF) &+ Int(try bits.take(Int((entry >> extraShift) & 15)))
                let distanceEntry: UInt32
                if distanceIsPlain {
                    reader = bits
                    distanceEntry = try decodePlain(distanceTree, from: &reader)
                    bits = reader
                } else {
                    distanceEntry = try unsafe HuffmanTree.decode(distance, from: &bits)
                }
                guard distanceEntry >> kindShift == kindLengthOrDistance else {
                    throw .invalidDistanceCode(Int(distanceEntry & 0xFFFF))
                }
                let distance =
                    Int(distanceEntry & 0xFFFF)
                    &+ Int(try bits.take(Int((distanceEntry >> extraShift) & 15)))
                guard distance <= out.count else {
                    throw .distanceTooFar
                }
                out.copy(distance: distance, length: length)

            default:
                throw .invalidLengthCode(Int(entry & 0xFFFF))
            }
        }
    }
}
