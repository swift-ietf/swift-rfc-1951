@testable import RFC_1951

extension Reference {

    struct Tree {
        private var fastLookup: [(symbol: Int, length: Int)]
        private var long: [(symbol: Int, code: Int, length: Int)] = []

        init(lengths: [Int]) {
            var blCount = [Int](repeating: 0, count: 16)
            for len in lengths where len > 0 {
                blCount[len] += 1
            }
            var nextCode = [Int](repeating: 0, count: 16)
            var code = 0
            for bits in 1...15 {
                code = (code + blCount[bits - 1]) << 1
                nextCode[bits] = code
            }
            fastLookup = [(symbol: Int, length: Int)](repeating: (0, 0), count: 512)
            for (symbol, len) in lengths.enumerated() where len > 0 {
                let code = nextCode[len]
                nextCode[len] += 1
                if len <= 9 {
                    let reversed = Self.reverse(code, len)
                    for extra in 0..<(1 << (9 - len)) {
                        fastLookup[reversed | extra << len] = (symbol, len)
                    }
                } else {
                    long.append((symbol, code, len))
                }
            }
        }
    }
}

extension Reference.Tree {

    static func reverse(_ value: Int, _ count: Int) -> Int {
        var result = 0
        var v = value
        for _ in 0..<count {
            result = result << 1 | v & 1
            v >>= 1
        }
        return result
    }

    func decode(from reader: inout Reference.BitReader) throws(RFC_1951.Error) -> Int {
        var bits = 0
        var bitsRead = 0
        while bitsRead < 9 && reader.hasMoreBits {
            bits |= Int(try reader.readBit()) << bitsRead
            bitsRead += 1
            let entry = fastLookup[bits]
            if entry.length > 0 && entry.length == bitsRead {
                return entry.symbol
            }
        }
        if bitsRead > 0 {
            let entry = fastLookup[bits & 511]
            if entry.length > 0 && entry.length <= bitsRead {
                return entry.symbol
            }
        }
        while bitsRead < 15 && reader.hasMoreBits {
            bits |= Int(try reader.readBit()) << bitsRead
            bitsRead += 1
            for node in long where node.length == bitsRead && Self.reverse(bits, bitsRead) == node.code {
                return node.symbol
            }
        }
        throw .invalidHuffmanCode
    }
}
