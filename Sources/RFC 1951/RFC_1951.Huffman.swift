// RFC_1951.Huffman.swift

extension RFC_1951 {
    /// Huffman tree for decoding DEFLATE streams
    ///
    /// Per RFC 1951 Section 3.2.2, Huffman codes are packed with the first bit
    /// being the most significant bit of the code.
    struct HuffmanTree: Sendable {
        /// Maximum code length in bits
        private static let maxBits = 15

        /// Lookup table: for codes up to `fastBits` in length, direct lookup
        private static let fastBits = 9
        private var fastLookup: [FastEntry]

        /// For longer codes, use tree traversal
        private var tree: [TreeNode]

        struct FastEntry: Sendable {
            var symbol: UInt16  // Decoded symbol
            var length: UInt8  // Code length (0 = need tree lookup)
        }

        struct TreeNode: Sendable {
            var children: (left: Int, right: Int)  // -1 = invalid, >= 0 = next node or symbol
            var isLeaf: Bool
            var symbol: UInt16
        }

        /// Build a Huffman tree from code lengths
        ///
        /// - Parameter lengths: Array where lengths[i] is the code length for symbol i (0 = unused)
        init?(lengths: [Int]) {
            // Count codes of each length
            var blCount = [Int](repeating: 0, count: Self.maxBits + 1)
            for len in lengths where len > 0 {
                blCount[len] += 1
            }

            // Find the numerical value of the smallest code for each code length
            var nextCode = [Int](repeating: 0, count: Self.maxBits + 1)
            var code = 0
            for bits in 1...Self.maxBits {
                code = (code + blCount[bits - 1]) << 1
                nextCode[bits] = code
            }

            // Assign codes to symbols
            var codes = [(symbol: Int, code: Int, length: Int)]()
            for (symbol, len) in lengths.enumerated() where len > 0 {
                codes.append((symbol, nextCode[len], len))
                nextCode[len] += 1
            }

            // Build fast lookup table
            fastLookup = [FastEntry](
                repeating: FastEntry(symbol: 0, length: 0),
                count: 1 << Self.fastBits
            )
            tree = []

            for (symbol, code, length) in codes {
                if length <= Self.fastBits {
                    // Fill all entries that match this code
                    let baseBits = Self.fastBits - length
                    let reversedCode = Self.reverseBits(code, count: length)
                    for extra in 0..<(1 << baseBits) {
                        let index = reversedCode | (extra << length)
                        fastLookup[index] = FastEntry(symbol: UInt16(symbol), length: UInt8(length))
                    }
                }
            }

            // Build tree for codes longer than fastBits
            // For simplicity in MVP, we'll use a slower but correct approach for long codes
            // by storing them and doing bit-by-bit lookup
            self.tree = []
            for (symbol, code, length) in codes where length > Self.fastBits {
                // Add to tree (slow path, rarely used in practice)
                insertIntoTree(symbol: symbol, code: code, length: length)
            }
        }

        private mutating func insertIntoTree(symbol: Int, code: Int, length: Int) {
            // For MVP, we store codes longer than fastBits in a simple list
            // and do linear search. This is suboptimal but correct.
            // Real implementation would build a proper tree structure.
            let node = TreeNode(
                children: (code, length),  // Abuse children to store code/length
                isLeaf: true,
                symbol: UInt16(symbol)
            )
            tree.append(node)
        }

        /// Reverse the bits in a code (DEFLATE uses reversed bit order)
        private static func reverseBits(_ value: Int, count: Int) -> Int {
            var result = 0
            var v = value
            for _ in 0..<count {
                result = (result << 1) | (v & 1)
                v >>= 1
            }
            return result
        }

        /// Decode a symbol from the bit stream
        mutating func decode<Bytes: Collection>(
            from reader: inout BitReader<Bytes>
        ) throws(Error) -> Int {
            // Try fast lookup first
            var bits: UInt32 = 0
            var bitsRead = 0

            // Read up to fastBits
            while bitsRead < Self.fastBits && reader.hasMoreBits {
                let bit = try reader.readBit()
                bits |= UInt32(bit) << bitsRead
                bitsRead += 1

                if bitsRead <= Self.fastBits {
                    let entry = fastLookup[Int(bits)]
                    if entry.length > 0 && entry.length <= bitsRead {
                        // We have enough bits - but we may have read too many
                        // Actually for LSB-first, we read exactly what we need
                        // The fast table handles this by filling all matching patterns
                        if entry.length == bitsRead {
                            return Int(entry.symbol)
                        }
                    }
                }
            }

            // Check fast lookup
            if bitsRead > 0 {
                let entry = fastLookup[Int(bits) & ((1 << Self.fastBits) - 1)]
                if entry.length > 0 && entry.length <= bitsRead {
                    return Int(entry.symbol)
                }
            }

            // Slow path: search tree for longer codes
            while bitsRead < Self.maxBits && reader.hasMoreBits {
                let bit = try reader.readBit()
                bits |= UInt32(bit) << bitsRead
                bitsRead += 1

                // Search in tree
                for node in tree {
                    let nodeCode = node.children.left
                    let nodeLen = node.children.right
                    if nodeLen == bitsRead {
                        let reversedBits = Self.reverseBits(Int(bits), count: bitsRead)
                        if reversedBits == nodeCode {
                            return Int(node.symbol)
                        }
                    }
                }
            }

            throw .invalidHuffmanCode
        }
    }
}

// MARK: - Fixed Huffman Tables (RFC 1951 Section 3.2.6)

extension RFC_1951 {
    /// Fixed Huffman tree for literal/length codes
    ///
    /// Per RFC 1951:
    /// - Lit values 0-143: 8-bit codes 00110000 - 10111111
    /// - Lit values 144-255: 9-bit codes 110010000 - 111111111
    /// - Lit values 256-279: 7-bit codes 0000000 - 0010111
    /// - Lit values 280-287: 8-bit codes 11000000 - 11000111
    static func makeFixedLiteralLengthTree() -> HuffmanTree {
        var lengths = [Int](repeating: 0, count: 288)

        for i in 0...143 { lengths[i] = 8 }
        for i in 144...255 { lengths[i] = 9 }
        for i in 256...279 { lengths[i] = 7 }
        for i in 280...287 { lengths[i] = 8 }

        return HuffmanTree(lengths: lengths)!
    }

    /// Fixed Huffman tree for distance codes (all 5-bit codes)
    static func makeFixedDistanceTree() -> HuffmanTree {
        let lengths = [Int](repeating: 5, count: 32)
        return HuffmanTree(lengths: lengths)!
    }
}

// MARK: - Length and Distance Tables (RFC 1951 Section 3.2.5)

extension RFC_1951 {
    /// Length code base values and extra bits
    /// Code 257-285 map to lengths 3-258
    static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10,  // 257-264
        11, 13, 15, 17,  // 265-268
        19, 23, 27, 31,  // 269-272
        35, 43, 51, 59,  // 273-276
        67, 83, 99, 115,  // 277-280
        131, 163, 195, 227,  // 281-284
        258,  // 285
    ]

    static let lengthExtraBits: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0,  // 257-264
        1, 1, 1, 1,  // 265-268
        2, 2, 2, 2,  // 269-272
        3, 3, 3, 3,  // 273-276
        4, 4, 4, 4,  // 277-280
        5, 5, 5, 5,  // 281-284
        0,  // 285
    ]

    /// Distance code base values and extra bits
    /// Codes 0-29 map to distances 1-32768
    static let distanceBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13,
        17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073,
        4097, 6145, 8193, 12289, 16385, 24577,
    ]

    static let distanceExtraBits: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2,
        3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10,
        11, 11, 12, 12, 13, 13,
    ]

    /// Decode a length value from a length code (257-285)
    static func decodeLength<Bytes: Collection>(
        code: Int,
        from reader: inout BitReader<Bytes>
    ) throws(Error) -> Int {
        let index = code - 257
        guard index >= 0, index < lengthBase.count else {
            throw .invalidLengthCode(code)
        }
        let base = lengthBase[index]
        let extraBits = lengthExtraBits[index]
        if extraBits > 0 {
            let extra = try reader.readBits(extraBits)
            return base + Int(extra)
        }
        return base
    }

    /// Decode a distance value from a distance code (0-29)
    static func decodeDistance<Bytes: Collection>(
        code: Int,
        from reader: inout BitReader<Bytes>
    ) throws(Error) -> Int {
        guard code >= 0, code < distanceBase.count else {
            throw .invalidDistanceCode(code)
        }
        let base = distanceBase[code]
        let extraBits = distanceExtraBits[code]
        if extraBits > 0 {
            let extra = try reader.readBits(extraBits)
            return base + Int(extra)
        }
        return base
    }
}

// MARK: - Code Length Decoding (for dynamic Huffman blocks)

extension RFC_1951 {
    /// Order of code length codes (RFC 1951 Section 3.2.7)
    static let codeLengthOrder: [Int] = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ]

    /// Read dynamic Huffman trees from the bit stream
    static func readDynamicTrees<Bytes: Collection>(
        from reader: inout BitReader<Bytes>
    ) throws(Error) -> (literalLength: HuffmanTree, distance: HuffmanTree) {
        // Read header
        let hlit = Int(try reader.readBits(5)) + 257  // # of literal/length codes
        let hdist = Int(try reader.readBits(5)) + 1  // # of distance codes
        let hclen = Int(try reader.readBits(4)) + 4  // # of code length codes

        // Read code length code lengths
        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for i in 0..<hclen {
            codeLengthLengths[codeLengthOrder[i]] = Int(try reader.readBits(3))
        }

        // Build code length Huffman tree
        guard let codeLengthTree = HuffmanTree(lengths: codeLengthLengths) else {
            throw .invalidCodeLengthCodes
        }

        // Read literal/length and distance code lengths
        var allLengths = [Int]()
        allLengths.reserveCapacity(hlit + hdist)

        var codeLengthTreeVar = codeLengthTree
        while allLengths.count < hlit + hdist {
            let symbol = try codeLengthTreeVar.decode(from: &reader)

            if symbol < 16 {
                // Literal code length
                allLengths.append(symbol)
            } else if symbol == 16 {
                // Repeat previous length 3-6 times
                guard let last = allLengths.last else {
                    throw .invalidLiteralLengthTree
                }
                let repeatCount = Int(try reader.readBits(2)) + 3
                for _ in 0..<repeatCount {
                    allLengths.append(last)
                }
            } else if symbol == 17 {
                // Repeat 0 length 3-10 times
                let repeatCount = Int(try reader.readBits(3)) + 3
                for _ in 0..<repeatCount {
                    allLengths.append(0)
                }
            } else if symbol == 18 {
                // Repeat 0 length 11-138 times
                let repeatCount = Int(try reader.readBits(7)) + 11
                for _ in 0..<repeatCount {
                    allLengths.append(0)
                }
            }
        }

        // Split into literal/length and distance lengths
        let literalLengths = Array(allLengths.prefix(hlit))
        let distanceLengths = Array(allLengths.dropFirst(hlit).prefix(hdist))

        // Build trees
        guard let literalTree = HuffmanTree(lengths: literalLengths) else {
            throw .invalidLiteralLengthTree
        }

        // Distance tree may have all zeros (no distances used)
        let distanceTree: HuffmanTree
        if distanceLengths.allSatisfy({ $0 == 0 }) {
            // Create a dummy tree (won't be used)
            distanceTree = HuffmanTree(lengths: [1])!
        } else {
            guard let tree = HuffmanTree(lengths: distanceLengths) else {
                throw .invalidDistanceTree
            }
            distanceTree = tree
        }

        return (literalTree, distanceTree)
    }
}
