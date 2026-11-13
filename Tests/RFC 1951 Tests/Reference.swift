import Byte

@testable import RFC_1951

enum Reference {}

extension Reference {

    static func decompress(_ input: [Byte], into output: inout [Byte]) throws(RFC_1951.Error) {
        guard !input.isEmpty else {
            throw .empty
        }
        var reader = BitReader(input)
        let origin = output.count
        var isFinal = false
        while !isFinal {
            isFinal = try decodeBlock(from: &reader, into: &output, origin: origin)
        }
    }

    private static func decodeBlock(
        from reader: inout BitReader,
        into output: inout [Byte],
        origin: Int
    ) throws(RFC_1951.Error) -> Bool {
        let isFinal = try reader.readBit() == 1
        let btype = try reader.readBits(2)
        switch btype {
        case 0:
            reader.alignToByte()
            let len = try reader.readUInt16LE()
            let nlen = try reader.readUInt16LE()
            guard len == ~nlen else {
                throw .invalidStoredBlockLength
            }
            output.append(contentsOf: try reader.readBytes(Int(len)))

        case 1:
            try decodeHuffmanBlock(
                from: &reader,
                literalTree: Tree(lengths: RFC_1951.fixedLiteralLengths),
                distanceTree: Tree(lengths: [Int](repeating: 5, count: 32)),
                into: &output,
                origin: origin
            )

        case 2:
            let (literalTree, distanceTree) = try readDynamicTrees(from: &reader)
            try decodeHuffmanBlock(
                from: &reader,
                literalTree: literalTree,
                distanceTree: distanceTree,
                into: &output,
                origin: origin
            )

        default:
            throw .invalidBlockType(Byte(UInt8(btype)))
        }
        return isFinal
    }

    private static func decodeHuffmanBlock(
        from reader: inout BitReader,
        literalTree: Tree,
        distanceTree: Tree,
        into output: inout [Byte],
        origin: Int
    ) throws(RFC_1951.Error) {
        while true {
            let symbol = try literalTree.decode(from: &reader)
            if symbol < 256 {
                output.append(Byte(UInt8(symbol)))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard index < RFC_1951.lengthBase.count else {
                    throw .invalidLengthCode(symbol)
                }
                let length =
                    RFC_1951.lengthBase[index]
                    + Int(try reader.readBits(RFC_1951.lengthExtraBits[index]))
                let code = try distanceTree.decode(from: &reader)
                guard code < RFC_1951.distanceBase.count else {
                    throw .invalidDistanceCode(code)
                }
                let distance =
                    RFC_1951.distanceBase[code]
                    + Int(try reader.readBits(RFC_1951.distanceExtraBits[code]))
                guard distance <= output.count - origin else {
                    throw .distanceTooFar
                }
                let start = output.count - distance
                for i in 0..<length {
                    output.append(output[start + i % distance])
                }
            }
        }
    }

    private static func readDynamicTrees(
        from reader: inout BitReader
    ) throws(RFC_1951.Error) -> (Tree, Tree) {
        let hlit = Int(try reader.readBits(5)) + 257
        let hdist = Int(try reader.readBits(5)) + 1
        let hclen = Int(try reader.readBits(4)) + 4

        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for i in 0..<hclen {
            codeLengthLengths[RFC_1951.codeLengthOrder[i]] = Int(try reader.readBits(3))
        }
        let codeLengthTree = Tree(lengths: codeLengthLengths)

        var all = [Int]()
        while all.count < hlit + hdist {
            let symbol = try codeLengthTree.decode(from: &reader)
            if symbol < 16 {
                all.append(symbol)
            } else if symbol == 16 {
                guard let last = all.last else {
                    throw .invalidLiteralLengthTree
                }
                all += [Int](repeating: last, count: Int(try reader.readBits(2)) + 3)
            } else if symbol == 17 {
                all += [Int](repeating: 0, count: Int(try reader.readBits(3)) + 3)
            } else if symbol == 18 {
                all += [Int](repeating: 0, count: Int(try reader.readBits(7)) + 11)
            }
        }

        let literal = Array(all.prefix(hlit))
        let distance = Array(all.dropFirst(hlit).prefix(hdist))
        let distanceTree = distance.allSatisfy { $0 == 0 } ? Tree(lengths: [1]) : Tree(lengths: distance)
        return (Tree(lengths: literal), distanceTree)
    }
}
