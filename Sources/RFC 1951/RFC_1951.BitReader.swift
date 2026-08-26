internal import Binary_Endianness
internal import Binary_Standard_Library_Integration
internal import Byte
internal import Byte_Standard_Library_Integration

extension RFC_1951 {

    struct BitReader<Bytes: Swift.Collection> where Bytes.Element == Byte {
        private let bytes: Bytes
        private var index: Bytes.Index
        private var currentByte: UInt8 = 0
        private var bitsRemaining: Int = 0

        init(_ bytes: Bytes) {
            self.bytes = bytes
            self.index = bytes.startIndex
        }
    }
}

extension RFC_1951.BitReader {

    var hasMoreBits: Bool {
        bitsRemaining > 0 || index < bytes.endIndex
    }

    mutating func readBit() throws(RFC_1951.Error) -> UInt8 {
        if bitsRemaining == 0 {
            guard index < bytes.endIndex else {
                throw .unexpectedEndOfInput
            }
            currentByte = bytes[index].underlying
            bytes.formIndex(after: &index)
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
            let bit = try readBit()
            result |= UInt32(bit) << i
        }
        return result
    }

    mutating func alignToByte() {
        bitsRemaining = 0
    }

    mutating func readBytes(_ count: Int) throws(RFC_1951.Error) -> [Byte] {
        alignToByte()
        var result: [Byte] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard index < bytes.endIndex else {
                throw .unexpectedEndOfInput
            }
            result.append(bytes[index])
            bytes.formIndex(after: &index)
        }
        return result
    }

    mutating func readUInt16LE() throws(RFC_1951.Error) -> UInt16 {
        let bytes = try readBytes(2)
        return UInt16(bytes: bytes, endianness: .little)!
    }
}
