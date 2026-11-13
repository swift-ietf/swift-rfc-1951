import Byte

@testable import RFC_1951

extension Reference {

    struct BitReader {
        private let bytes: [Byte]
        private var index = 0
        private var currentByte: UInt8 = 0
        private var bitsRemaining = 0

        init(_ bytes: [Byte]) {
            self.bytes = bytes
        }
    }
}

extension Reference.BitReader {

    var hasMoreBits: Bool {
        bitsRemaining > 0 || index < bytes.count
    }

    mutating func readBit() throws(RFC_1951.Error) -> UInt8 {
        if bitsRemaining == 0 {
            guard index < bytes.count else {
                throw .unexpectedEndOfInput
            }
            currentByte = bytes[index].underlying
            index += 1
            bitsRemaining = 8
        }
        let bit = currentByte & 1
        currentByte >>= 1
        bitsRemaining -= 1
        return bit
    }

    mutating func readBits(_ count: Int) throws(RFC_1951.Error) -> UInt32 {
        var result: UInt32 = 0
        for i in 0..<count {
            result |= UInt32(try readBit()) << i
        }
        return result
    }

    mutating func alignToByte() {
        bitsRemaining = 0
    }

    mutating func readBytes(_ count: Int) throws(RFC_1951.Error) -> [Byte] {
        alignToByte()
        guard count <= bytes.count - index else {
            throw .unexpectedEndOfInput
        }
        defer { index += count }
        return Array(bytes[index..<(index + count)])
    }

    mutating func readUInt16LE() throws(RFC_1951.Error) -> UInt16 {
        let pair = try readBytes(2)
        return UInt16(pair[0].underlying) | UInt16(pair[1].underlying) << 8
    }
}
