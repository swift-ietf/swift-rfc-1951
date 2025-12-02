// RFC_1951.BitReader.swift

extension RFC_1951 {
    /// Reads bits from a byte stream, LSB first (per DEFLATE spec)
    struct BitReader<Bytes: Collection> where Bytes.Element == UInt8 {
        private let bytes: Bytes
        private var index: Bytes.Index
        private var currentByte: UInt8 = 0
        private var bitsRemaining: Int = 0

        init(_ bytes: Bytes) {
            self.bytes = bytes
            self.index = bytes.startIndex
        }

        /// Whether there are more bits available
        var hasMoreBits: Bool {
            bitsRemaining > 0 || index < bytes.endIndex
        }

        /// Read a single bit (LSB first within each byte)
        mutating func readBit() throws(Error) -> UInt8 {
            if bitsRemaining == 0 {
                guard index < bytes.endIndex else {
                    throw .unexpectedEndOfInput
                }
                currentByte = bytes[index]
                bytes.formIndex(after: &index)
                bitsRemaining = 8
            }

            let bit = currentByte & 1
            currentByte >>= 1
            bitsRemaining -= 1
            return bit
        }

        /// Read multiple bits (LSB first), returns value with first bit in LSB position
        mutating func readBits(_ count: Int) throws(Error) -> UInt32 {
            var result: UInt32 = 0
            for i in 0..<count {
                let bit = try readBit()
                result |= UInt32(bit) << i
            }
            return result
        }

        /// Align to byte boundary (discard remaining bits in current byte)
        mutating func alignToByte() {
            bitsRemaining = 0
        }

        /// Read bytes directly (must be byte-aligned)
        mutating func readBytes(_ count: Int) throws(Error) -> [UInt8] {
            alignToByte()
            var result: [UInt8] = []
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

        /// Read a 16-bit little-endian value (must be byte-aligned)
        mutating func readUInt16LE() throws(Error) -> UInt16 {
            let bytes = try readBytes(2)
            return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        }
    }
}
