internal import Byte
internal import Byte_Standard_Library_Integration

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

    static func encodeStoredBlock<Buffer: RangeReplaceableCollection>(
        data: ArraySlice<Byte>,
        isFinal: Bool,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == Byte {

        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(0, count: 2)

        writer.alignToByte()

        let len = UInt16(data.count)
        let nlen = ~len
        writer.writeUInt16LE(len)
        writer.writeUInt16LE(nlen)

        writer.writeBytes(data)
    }

    static func encodeFixedHuffmanBlock<Buffer: RangeReplaceableCollection>(
        tokens: [LZ77Token],
        isFinal: Bool,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == Byte {

        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(1, count: 2)

        for token in tokens {
            switch token {
            case .literal(let byte):
                encodeFixedLiteral(Int(byte), into: &writer)

            case .reference(let length, let distance):
                encodeFixedLengthDistance(length: length, distance: distance, into: &writer)
            }
        }

        encodeFixedLiteral(256, into: &writer)
    }

    private static func encodeFixedLiteral<Buffer: RangeReplaceableCollection>(
        _ value: Int,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == Byte {

        if value <= 143 {

            let code = 0x30 + value
            writer.writeBitsReversed(UInt32(code), count: 8)
        } else if value <= 255 {

            let code = 0x190 + (value - 144)
            writer.writeBitsReversed(UInt32(code), count: 9)
        } else if value <= 279 {

            let code = value - 256
            writer.writeBitsReversed(UInt32(code), count: 7)
        } else if value <= 287 {

            let code = 0xC0 + (value - 280)
            writer.writeBitsReversed(UInt32(code), count: 8)
        }
    }

    private static func encodeFixedLengthDistance<Buffer: RangeReplaceableCollection>(
        length: Int,
        distance: Int,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == Byte {

        let (lengthCode, lengthExtra, lengthExtraBits) = encodeLengthCode(length)
        encodeFixedLiteral(lengthCode, into: &writer)
        if lengthExtraBits > 0 {
            writer.writeBits(UInt32(lengthExtra), count: lengthExtraBits)
        }

        let (distCode, distExtra, distExtraBits) = encodeDistanceCode(distance)
        writer.writeBitsReversed(UInt32(distCode), count: 5)
        if distExtraBits > 0 {
            writer.writeBits(UInt32(distExtra), count: distExtraBits)
        }
    }

    private static func encodeLengthCode(_ length: Int) -> (code: Int, extra: Int, extraBits: Int) {
        for (i, base) in lengthBase.enumerated() {
            let nextBase = lengthBase.indices.contains(i + 1) ? lengthBase[i + 1] : 259
            if length >= base && length < nextBase {
                return (257 + i, length - base, lengthExtraBits[i])
            }
        }

        return (285, 0, 0)
    }

    private static func encodeDistanceCode(
        _ distance: Int
    ) -> (code: Int, extra: Int, extraBits: Int) {
        for (i, base) in distanceBase.enumerated() {
            let nextBase = distanceBase.indices.contains(i + 1) ? distanceBase[i + 1] : 32769
            if distance >= base && distance < nextBase {
                return (i, distance - base, distanceExtraBits[i])
            }
        }

        return (29, distance - distanceBase[29], distanceExtraBits[29])
    }
}

extension RFC_1951 {

    static func decodeBlock<Bytes: Swift.Collection, Output: RangeReplaceableCollection>(
        from reader: inout BitReader<Bytes>,
        into output: inout Output
    ) throws(Error) -> Bool where Bytes.Element == Byte, Output.Element == Byte {

        let isFinal = try reader.readBit() == 1
        let btype = try reader.readBits(2)

        guard let blockType = BlockType(rawValue: UInt8(btype)) else {
            throw .invalidBlockType(Byte(UInt8(btype)))
        }

        switch blockType {
        case .stored:
            try decodeStoredBlock(from: &reader, into: &output)

        case .fixedHuffman:
            var literalTree = makeFixedLiteralLengthTree()
            var distanceTree = makeFixedDistanceTree()
            try decodeHuffmanBlock(
                from: &reader,
                literalTree: &literalTree,
                distanceTree: &distanceTree,
                into: &output
            )

        case .dynamicHuffman:
            var (literalTree, distanceTree) = try readDynamicTrees(from: &reader)
            try decodeHuffmanBlock(
                from: &reader,
                literalTree: &literalTree,
                distanceTree: &distanceTree,
                into: &output
            )

        case .reserved:
            throw .invalidBlockType(3)
        }

        return isFinal
    }

    private static func decodeStoredBlock<
        Bytes: Swift.Collection,
        Output: RangeReplaceableCollection
    >(
        from reader: inout BitReader<Bytes>,
        into output: inout Output
    ) throws(Error) where Bytes.Element == Byte, Output.Element == Byte {

        reader.alignToByte()

        let len = try reader.readUInt16LE()
        let nlen = try reader.readUInt16LE()

        guard len == ~nlen else {
            throw .invalidStoredBlockLength
        }

        let data = try reader.readBytes(Int(len))
        output.append(contentsOf: data)
    }

    private static func decodeHuffmanBlock<
        Bytes: Swift.Collection,
        Output: RangeReplaceableCollection
    >(
        from reader: inout BitReader<Bytes>,
        literalTree: inout HuffmanTree,
        distanceTree: inout HuffmanTree,
        into output: inout Output
    ) throws(Error) where Bytes.Element == Byte, Output.Element == Byte {
        while true {
            let symbol = try literalTree.decode(from: &reader)

            if symbol < 256 {

                output.append(Byte(UInt8(symbol)))
            } else if symbol == 256 {

                break
            } else {

                let length = try decodeLength(code: symbol, from: &reader)
                let distanceCode = try distanceTree.decode(from: &reader)
                let distance = try decodeDistance(code: distanceCode, from: &reader)

                guard distance > 0 else {
                    throw .invalidDistance
                }

                var outputArray = Array(output)
                guard distance <= outputArray.count else {
                    throw .distanceTooFar
                }

                let startPos = outputArray.count - distance
                (0..<length).forEach { i in

                    let srcPos = startPos + (i % distance)
                    outputArray.append(outputArray[srcPos])
                }

                output = Output(outputArray)
            }
        }
    }
}
