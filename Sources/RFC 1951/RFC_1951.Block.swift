// RFC_1951.Block.swift

extension RFC_1951 {
    /// DEFLATE block types (RFC 1951 Section 3.2.3)
    enum BlockType: UInt8 {
        /// No compression - data stored as-is
        case stored = 0
        /// Compressed with fixed Huffman codes
        case fixedHuffman = 1
        /// Compressed with dynamic Huffman codes
        case dynamicHuffman = 2
        /// Reserved (error)
        case reserved = 3
    }

    /// Maximum size of a stored block (65535 bytes)
    static let maxStoredBlockSize = 65535
}

// MARK: - Block Encoding

extension RFC_1951 {
    /// Encode a stored (uncompressed) block
    static func encodeStoredBlock<Buffer: RangeReplaceableCollection>(
        data: ArraySlice<UInt8>,
        isFinal: Bool,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == UInt8 {
        // Block header: BFINAL (1 bit) + BTYPE (2 bits)
        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(0, count: 2)  // BTYPE = 00 (stored)

        // Align to byte boundary
        writer.alignToByte()

        // LEN and NLEN
        let len = UInt16(data.count)
        let nlen = ~len
        writer.writeUInt16LE(len)
        writer.writeUInt16LE(nlen)

        // Data
        writer.writeBytes(data)
    }

    /// Encode tokens with fixed Huffman codes
    static func encodeFixedHuffmanBlock<Buffer: RangeReplaceableCollection>(
        tokens: [LZ77Token],
        isFinal: Bool,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == UInt8 {
        // Block header: BFINAL (1 bit) + BTYPE (2 bits)
        writer.writeBit(isFinal ? 1 : 0)
        writer.writeBits(1, count: 2)  // BTYPE = 01 (fixed Huffman)

        // Encode tokens
        for token in tokens {
            switch token {
            case .literal(let byte):
                encodeFixedLiteral(Int(byte), into: &writer)
            case .reference(let length, let distance):
                encodeFixedLengthDistance(length: length, distance: distance, into: &writer)
            }
        }

        // End of block marker (code 256)
        encodeFixedLiteral(256, into: &writer)
    }

    /// Encode a literal/length code with fixed Huffman coding
    private static func encodeFixedLiteral<Buffer: RangeReplaceableCollection>(
        _ value: Int,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == UInt8 {
        // Fixed Huffman codes per RFC 1951 Section 3.2.6
        if value <= 143 {
            // 8-bit codes: 00110000 (48) + value
            let code = 0x30 + value
            writer.writeBitsReversed(UInt32(code), count: 8)
        } else if value <= 255 {
            // 9-bit codes: 110010000 (400) + (value - 144)
            let code = 0x190 + (value - 144)
            writer.writeBitsReversed(UInt32(code), count: 9)
        } else if value <= 279 {
            // 7-bit codes: 0000000 (0) + (value - 256)
            let code = value - 256
            writer.writeBitsReversed(UInt32(code), count: 7)
        } else if value <= 287 {
            // 8-bit codes: 11000000 (192) + (value - 280)
            let code = 0xC0 + (value - 280)
            writer.writeBitsReversed(UInt32(code), count: 8)
        }
    }

    /// Encode a length/distance pair with fixed Huffman coding
    private static func encodeFixedLengthDistance<Buffer: RangeReplaceableCollection>(
        length: Int,
        distance: Int,
        into writer: inout BitWriter<Buffer>
    ) where Buffer.Element == UInt8 {
        // Encode length
        let (lengthCode, lengthExtra, lengthExtraBits) = encodeLengthCode(length)
        encodeFixedLiteral(lengthCode, into: &writer)
        if lengthExtraBits > 0 {
            writer.writeBits(UInt32(lengthExtra), count: lengthExtraBits)
        }

        // Encode distance (5-bit fixed codes)
        let (distCode, distExtra, distExtraBits) = encodeDistanceCode(distance)
        writer.writeBitsReversed(UInt32(distCode), count: 5)
        if distExtraBits > 0 {
            writer.writeBits(UInt32(distExtra), count: distExtraBits)
        }
    }

    /// Get length code, extra bits value, and number of extra bits for a length
    private static func encodeLengthCode(_ length: Int) -> (code: Int, extra: Int, extraBits: Int) {
        for (i, base) in lengthBase.enumerated() {
            let nextBase = i + 1 < lengthBase.count ? lengthBase[i + 1] : 259
            if length >= base && length < nextBase {
                return (257 + i, length - base, lengthExtraBits[i])
            }
        }
        // Length 258 (maximum)
        return (285, 0, 0)
    }

    /// Get distance code, extra bits value, and number of extra bits for a distance
    private static func encodeDistanceCode(_ distance: Int) -> (code: Int, extra: Int, extraBits: Int) {
        for (i, base) in distanceBase.enumerated() {
            let nextBase = i + 1 < distanceBase.count ? distanceBase[i + 1] : 32769
            if distance >= base && distance < nextBase {
                return (i, distance - base, distanceExtraBits[i])
            }
        }
        // Should not reach here for valid distances
        return (29, distance - distanceBase[29], distanceExtraBits[29])
    }
}

// MARK: - Block Decoding

extension RFC_1951 {
    /// Decode a DEFLATE block
    static func decodeBlock<Bytes: Collection, Output: RangeReplaceableCollection>(
        from reader: inout BitReader<Bytes>,
        into output: inout Output
    ) throws(Error) -> Bool where Bytes.Element == UInt8, Output.Element == UInt8 {
        // Read block header
        let isFinal = try reader.readBit() == 1
        let btype = try reader.readBits(2)

        guard let blockType = BlockType(rawValue: UInt8(btype)) else {
            throw .invalidBlockType(UInt8(btype))
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

    /// Decode a stored (uncompressed) block
    private static func decodeStoredBlock<Bytes: Collection, Output: RangeReplaceableCollection>(
        from reader: inout BitReader<Bytes>,
        into output: inout Output
    ) throws(Error) where Bytes.Element == UInt8, Output.Element == UInt8 {
        // Align to byte boundary
        reader.alignToByte()

        // Read LEN and NLEN
        let len = try reader.readUInt16LE()
        let nlen = try reader.readUInt16LE()

        // Validate
        guard len == ~nlen else {
            throw .invalidStoredBlockLength
        }

        // Read data
        let data = try reader.readBytes(Int(len))
        output.append(contentsOf: data)
    }

    /// Decode a Huffman-compressed block
    private static func decodeHuffmanBlock<Bytes: Collection, Output: RangeReplaceableCollection>(
        from reader: inout BitReader<Bytes>,
        literalTree: inout HuffmanTree,
        distanceTree: inout HuffmanTree,
        into output: inout Output
    ) throws(Error) where Bytes.Element == UInt8, Output.Element == UInt8 {
        while true {
            let symbol = try literalTree.decode(from: &reader)

            if symbol < 256 {
                // Literal byte
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                // End of block
                break
            } else {
                // Length/distance pair
                let length = try decodeLength(code: symbol, from: &reader)
                let distanceCode = try distanceTree.decode(from: &reader)
                let distance = try decodeDistance(code: distanceCode, from: &reader)

                guard distance > 0 else {
                    throw .invalidDistance
                }

                // Copy from output buffer
                // We need to access output as an array for back-references
                var outputArray = Array(output)
                guard distance <= outputArray.count else {
                    throw .distanceTooFar
                }

                let startPos = outputArray.count - distance
                for i in 0..<length {
                    // Handle overlapping copies (e.g., distance=1, length=10 repeats last byte)
                    let srcPos = startPos + (i % distance)
                    outputArray.append(outputArray[srcPos])
                }

                output = Output(outputArray)
            }
        }
    }
}
