internal import Byte_Primitives

extension RFC_1951 {

    struct HuffmanTree: Sendable {

        private var fastLookup: [FastEntry]

        private var tree: [TreeNode]

        init?(lengths: [Int]) {

            var blCount = [Int](repeating: 0, count: Self.maxBits + 1)
            for len in lengths where len > 0 {
                blCount[len] += 1
            }

            var nextCode = [Int](repeating: 0, count: Self.maxBits + 1)
            var code = 0
            (1...Self.maxBits).forEach { bits in
                code = (code + blCount[bits - 1]) << 1
                nextCode[bits] = code
            }

            var codes = [(symbol: Int, code: Int, length: Int)]()
            for (symbol, len) in lengths.enumerated() where len > 0 {
                codes.append((symbol, nextCode[len], len))
                nextCode[len] += 1
            }

            fastLookup = [FastEntry](
                repeating: FastEntry(symbol: 0, length: 0),
                count: 1 << Self.fastBits
            )
            tree = []

            for (symbol, code, length) in codes {
                if length <= Self.fastBits {

                    let baseBits = Self.fastBits - length
                    let reversedCode = Self.reverseBits(code, count: length)
                    (0..<(1 << baseBits)).forEach { extra in
                        let index = reversedCode | (extra << length)
                        fastLookup[index] = FastEntry(symbol: UInt16(symbol), length: UInt8(length))
                    }
                }
            }

            self.tree = []
            for (symbol, code, length) in codes where length > Self.fastBits {

                insertIntoTree(symbol: symbol, code: code, length: length)
            }
        }
    }
}

extension RFC_1951.HuffmanTree {

    private static let maxBits = 15

    private static let fastBits = 9

    private mutating func insertIntoTree(symbol: Int, code: Int, length: Int) {

        let node = TreeNode(
            children: (code, length),
            isLeaf: true,
            symbol: UInt16(symbol)
        )
        tree.append(node)
    }

    private static func reverseBits(_ value: Int, count: Int) -> Int {
        var result = 0
        var v = value
        for _ in 0..<count {
            result = (result << 1) | (v & 1)
            v >>= 1
        }
        return result
    }

    mutating func decode<Bytes: Swift.Collection>(
        from reader: inout RFC_1951.BitReader<Bytes>
    ) throws(RFC_1951.Error) -> Int {

        var bits: UInt32 = 0
        var bitsRead = 0

        while bitsRead < Self.fastBits && reader.hasMoreBits {
            let bit = try reader.readBit()
            bits |= UInt32(bit) << bitsRead
            bitsRead += 1

            if bitsRead <= Self.fastBits {
                let entry = fastLookup[Int(bits)]
                if entry.length > 0 && entry.length <= bitsRead {

                    if entry.length == bitsRead {
                        return Int(entry.symbol)
                    }
                }
            }
        }

        if bitsRead > 0 {
            let entry = fastLookup[Int(bits) & ((1 << Self.fastBits) - 1)]
            if entry.length > 0 && entry.length <= bitsRead {
                return Int(entry.symbol)
            }
        }

        while bitsRead < Self.maxBits && reader.hasMoreBits {
            let bit = try reader.readBit()
            bits |= UInt32(bit) << bitsRead
            bitsRead += 1

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

extension RFC_1951 {

    static func makeFixedLiteralLengthTree() -> HuffmanTree {
        var lengths = [Int](repeating: 0, count: 288)

        (0...143).forEach { lengths[$0] = 8 }
        (144...255).forEach { lengths[$0] = 9 }
        (256...279).forEach { lengths[$0] = 7 }
        (280...287).forEach { lengths[$0] = 8 }

        return HuffmanTree(lengths: lengths)!
    }

    static func makeFixedDistanceTree() -> HuffmanTree {
        let lengths = [Int](repeating: 5, count: 32)
        return HuffmanTree(lengths: lengths)!
    }
}

extension RFC_1951 {

    static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10,
        11, 13, 15, 17,
        19, 23, 27, 31,
        35, 43, 51, 59,
        67, 83, 99, 115,
        131, 163, 195, 227,
        258,
    ]

    static let lengthExtraBits: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1,
        2, 2, 2, 2,
        3, 3, 3, 3,
        4, 4, 4, 4,
        5, 5, 5, 5,
        0,
    ]

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

    static func decodeLength<Bytes: Swift.Collection>(
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

    static func decodeDistance<Bytes: Swift.Collection>(
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

extension RFC_1951 {

    static let codeLengthOrder: [Int] = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ]

    static func readDynamicTrees<Bytes: Swift.Collection>(
        from reader: inout BitReader<Bytes>
    ) throws(Error) -> (literalLength: HuffmanTree, distance: HuffmanTree) {

        let hlit = Int(try reader.readBits(5)) + 257
        let hdist = Int(try reader.readBits(5)) + 1
        let hclen = Int(try reader.readBits(4)) + 4

        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for i in 0..<hclen {
            codeLengthLengths[codeLengthOrder[i]] = Int(try reader.readBits(3))
        }

        guard let codeLengthTree = HuffmanTree(lengths: codeLengthLengths) else {
            throw .invalidCodeLengthCodes
        }

        var allLengths = [Int]()
        allLengths.reserveCapacity(hlit + hdist)

        var codeLengthTreeVar = codeLengthTree
        while allLengths.count < hlit + hdist {
            let symbol = try codeLengthTreeVar.decode(from: &reader)

            if symbol < 16 {

                allLengths.append(symbol)
            } else if symbol == 16 {

                guard let last = allLengths.last else {
                    throw .invalidLiteralLengthTree
                }
                let repeatCount = Int(try reader.readBits(2)) + 3
                for _ in 0..<repeatCount {
                    allLengths.append(last)
                }
            } else if symbol == 17 {

                let repeatCount = Int(try reader.readBits(3)) + 3
                for _ in 0..<repeatCount {
                    allLengths.append(0)
                }
            } else if symbol == 18 {

                let repeatCount = Int(try reader.readBits(7)) + 11
                for _ in 0..<repeatCount {
                    allLengths.append(0)
                }
            }
        }

        let literalLengths = Array(allLengths.prefix(hlit))
        let distanceLengths = Array(allLengths.dropFirst(hlit).prefix(hdist))

        guard let literalTree = HuffmanTree(lengths: literalLengths) else {
            throw .invalidLiteralLengthTree
        }

        let distanceTree: HuffmanTree
        if distanceLengths.allSatisfy({ $0 == 0 }) {

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
