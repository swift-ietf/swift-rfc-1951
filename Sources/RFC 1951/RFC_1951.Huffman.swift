internal import Byte

extension RFC_1951 {

    struct HuffmanTree: Sendable {

        private(set) var table: [UInt32]

        private var fastLookup: [FastEntry]

        private var tree: [TreeNode]

        private var payloads: [UInt32]

        let isOversubscribed: Bool

        init(lengths: [Int], payload: (Int) -> UInt32 = { UInt32($0) }) {

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

            var kraft = 0
            (1...Self.maxBits).forEach { bits in
                kraft += blCount[bits] << (Self.maxBits - bits)
            }

            var codes = [(symbol: Int, code: Int, length: Int)]()
            for (symbol, len) in lengths.enumerated() where len > 0 {
                codes.append((symbol, nextCode[len], len))
                nextCode[len] += 1
            }

            table = []
            fastLookup = []
            tree = []
            payloads = []
            isOversubscribed = kraft > 1 << Self.maxBits

            if isOversubscribed {
                buildPlain(codes: codes, count: lengths.count, payload: payload)
            } else {
                buildTable(codes: codes, payload: payload)
            }
        }
    }
}

extension RFC_1951.HuffmanTree {

    private static let maxBits = 15

    private static let fastBits = 9

    static let primaryBits = 10

    static let link: UInt32 = 1 << 31

    private static func reverseBits(_ value: Int, count: Int) -> Int {
        var result = 0
        var v = value
        for _ in 0..<count {
            result = (result << 1) | (v & 1)
            v >>= 1
        }
        return result
    }

    private mutating func buildTable(
        codes: [(symbol: Int, code: Int, length: Int)],
        payload: (Int) -> UInt32
    ) {
        let primaryMask = (1 << Self.primaryBits) - 1
        table = [UInt32](repeating: 0, count: 1 << Self.primaryBits)

        var subtableBits = [Int](repeating: 0, count: 1 << Self.primaryBits)
        for (_, code, length) in codes where length > Self.primaryBits {
            let prefix = Self.reverseBits(code, count: length) & primaryMask
            subtableBits[prefix] = max(subtableBits[prefix], length - Self.primaryBits)
        }
        for (prefix, bits) in subtableBits.enumerated() where bits > 0 {
            table[prefix] = Self.link | UInt32(bits) << 16 | UInt32(table.count)
            table.append(contentsOf: repeatElement(0, count: 1 << bits))
        }

        for (symbol, code, length) in codes {
            let entry = payload(symbol) | UInt32(length) << 16
            let reversed = Self.reverseBits(code, count: length)
            if length <= Self.primaryBits {
                for index in stride(from: reversed, to: 1 << Self.primaryBits, by: 1 << length) {
                    table[index] = entry
                }
            } else {
                let link = table[reversed & primaryMask]
                let offset = Int(link & 0xFFFF)
                let bits = Int((link >> 16) & 31)
                let start = reversed >> Self.primaryBits
                for index in stride(from: start, to: 1 << bits, by: 1 << (length - Self.primaryBits)) {
                    table[offset + index] = entry
                }
            }
        }
    }

    private mutating func buildPlain(
        codes: [(symbol: Int, code: Int, length: Int)],
        count: Int,
        payload: (Int) -> UInt32
    ) {
        fastLookup = [FastEntry](
            repeating: FastEntry(symbol: 0, length: 0),
            count: 1 << Self.fastBits
        )
        payloads = (0..<count).map(payload)

        for (symbol, code, length) in codes where length <= Self.fastBits {
            let baseBits = Self.fastBits - length
            let reversedCode = Self.reverseBits(code, count: length)
            (0..<(1 << baseBits)).forEach { extra in
                fastLookup[reversedCode | (extra << length)] = FastEntry(
                    symbol: UInt16(symbol),
                    length: UInt8(length)
                )
            }
        }

        for (symbol, code, length) in codes where length > Self.fastBits {
            tree.append(TreeNode(children: (code, length), isLeaf: true, symbol: UInt16(symbol)))
        }
    }

    @inline(__always)
    func decode(from reader: inout RFC_1951.BitReader) throws(RFC_1951.Error) -> UInt32 {
        guard !isOversubscribed else {
            return payloads[try decodePlain(from: &reader)]
        }
        return try table.withUnsafeBufferPointer { table throws(RFC_1951.Error) in
            try unsafe Self.decode(table, from: &reader)
        }
    }

    @inline(__always)
    static func decode(
        _ table: UnsafeBufferPointer<UInt32>,
        from reader: inout RFC_1951.BitReader
    ) throws(RFC_1951.Error) -> UInt32 {
        let bits = reader.buffer
        var entry = unsafe table[Int(truncatingIfNeeded: bits) & ((1 << primaryBits) - 1)]
        if entry & link != 0 {
            let width = (entry >> 16) & 31
            let index = Int(truncatingIfNeeded: (bits >> UInt64(primaryBits)) & ((1 &<< UInt64(width)) &- 1))
            entry = unsafe table[Int(entry & 0xFFFF) &+ index]
        }
        let length = Int((entry >> 16) & 31)
        guard length != 0, length <= reader.available else {
            throw .invalidHuffmanCode
        }
        reader.consume(length)
        return entry
    }

    private func decodePlain(from reader: inout RFC_1951.BitReader) throws(RFC_1951.Error) -> Int {

        var bits: UInt32 = 0
        var bitsRead = 0

        while bitsRead < Self.fastBits && reader.hasMoreBits {
            let bit = try reader.readBit()
            bits |= bit << bitsRead
            bitsRead += 1

            let entry = fastLookup[Int(bits)]
            if entry.length > 0 && Int(entry.length) == bitsRead {
                return Int(entry.symbol)
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
            bits |= bit << bitsRead
            bitsRead += 1

            let reversedBits = Self.reverseBits(Int(bits), count: bitsRead)
            for node in tree where node.children.right == bitsRead && node.children.left == reversedBits {
                return Int(node.symbol)
            }
        }

        throw .invalidHuffmanCode
    }
}

extension RFC_1951 {

    static let fixedLiteralLengths: [Int] =
        [Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112)
        + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8)

    static let fixedLiteralLengthTree = HuffmanTree(
        lengths: fixedLiteralLengths,
        payload: literalLengthPayload
    )

    static let fixedDistanceTree = HuffmanTree(
        lengths: [Int](repeating: 5, count: 32),
        payload: distancePayload
    )
}

extension RFC_1951 {

    static let kindShift: UInt32 = 25

    static let kindLiteral: UInt32 = 0

    static let kindLengthOrDistance: UInt32 = 1

    static let kindEnd: UInt32 = 2

    static let kindInvalid: UInt32 = 3

    static let extraShift: UInt32 = 21

    static func literalLengthPayload(_ symbol: Int) -> UInt32 {
        if symbol < 256 {
            return UInt32(symbol)
        }
        if symbol == 256 {
            return kindEnd << kindShift
        }
        let index = symbol - 257
        guard index < lengthBase.count else {
            return kindInvalid << kindShift | UInt32(symbol)
        }
        return kindLengthOrDistance << kindShift | UInt32(lengthExtraBits[index]) << extraShift
            | UInt32(lengthBase[index])
    }

    static func distancePayload(_ symbol: Int) -> UInt32 {
        guard symbol < distanceBase.count else {
            return kindInvalid << kindShift | UInt32(symbol)
        }
        return kindLengthOrDistance << kindShift | UInt32(distanceExtraBits[symbol]) << extraShift
            | UInt32(distanceBase[symbol])
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
}

extension RFC_1951 {

    static let codeLengthOrder: [Int] = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ]

    static func readDynamicTrees(
        from reader: inout BitReader
    ) throws(Error) -> (literalLength: HuffmanTree, distance: HuffmanTree) {

        let hlit = Int(try reader.readBits(5)) + 257
        let hdist = Int(try reader.readBits(5)) + 1
        let hclen = Int(try reader.readBits(4)) + 4

        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for i in 0..<hclen {
            codeLengthLengths[codeLengthOrder[i]] = Int(try reader.readBits(3))
        }

        let codeLengthTree = HuffmanTree(lengths: codeLengthLengths)

        var allLengths = [Int]()
        allLengths.reserveCapacity(hlit + hdist + 138)

        while allLengths.count < hlit + hdist {
            reader.refill()
            let symbol = Int(try codeLengthTree.decode(from: &reader) & 0xFFFF)

            if symbol < 16 {

                allLengths.append(symbol)
            } else if symbol == 16 {

                guard let last = allLengths.last else {
                    throw .invalidLiteralLengthTree
                }
                let repeatCount = Int(try reader.readBits(2)) + 3
                allLengths.append(contentsOf: repeatElement(last, count: repeatCount))
            } else if symbol == 17 {

                let repeatCount = Int(try reader.readBits(3)) + 3
                allLengths.append(contentsOf: repeatElement(0, count: repeatCount))
            } else if symbol == 18 {

                let repeatCount = Int(try reader.readBits(7)) + 11
                allLengths.append(contentsOf: repeatElement(0, count: repeatCount))
            }
        }

        let literalLengths = Array(allLengths.prefix(hlit))
        let distanceLengths = Array(allLengths.dropFirst(hlit).prefix(hdist))

        let literalTree = HuffmanTree(lengths: literalLengths, payload: literalLengthPayload)

        let distanceTree =
            if distanceLengths.allSatisfy({ $0 == 0 }) {
                HuffmanTree(lengths: [1], payload: distancePayload)
            } else {
                HuffmanTree(lengths: distanceLengths, payload: distancePayload)
            }

        return (literalTree, distanceTree)
    }
}
