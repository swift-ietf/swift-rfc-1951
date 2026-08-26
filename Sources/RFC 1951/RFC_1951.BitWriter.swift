internal import Binary_Endianness
internal import Binary_Standard_Library_Integration
internal import Byte

extension RFC_1951 {

    struct BitWriter<Buffer: RangeReplaceableCollection> where Buffer.Element == Byte {
        private var buffer: Buffer
        private var currentByte: UInt8 = 0
        private var bitPosition: Int = 0

        init(into buffer: Buffer) {
            self.buffer = buffer
        }
    }
}

extension RFC_1951.BitWriter {

    mutating func writeBit(_ bit: UInt8) {
        currentByte |= (bit & 1) << bitPosition
        bitPosition += 1
        if bitPosition == 8 {
            buffer.append(Byte(currentByte))
            currentByte = 0
            bitPosition = 0
        }
    }

    mutating func writeBits(_ value: UInt32, count: Int) {
        var v = value
        (0..<count).forEach { _ in
            writeBit(UInt8(v & 1))
            v >>= 1
        }
    }

    mutating func writeBitsReversed(_ value: UInt32, count: Int) {
        for i in stride(from: count - 1, through: 0, by: -1) {
            writeBit(UInt8((value >> i) & 1))
        }
    }

    mutating func alignToByte() {
        if bitPosition > 0 {
            buffer.append(Byte(currentByte))
            currentByte = 0
            bitPosition = 0
        }
    }

    mutating func writeByte(_ byte: UInt8) {
        alignToByte()
        buffer.append(Byte(byte))
    }

    mutating func writeBytes<Bytes: Swift.Sequence>(_ bytes: Bytes) where Bytes.Element == Byte {
        alignToByte()
        buffer.append(contentsOf: bytes)
    }

    mutating func writeUInt16LE(_ value: UInt16) {
        writeBytes(value.bytes(endianness: .little))
    }

    mutating func finish() -> Buffer {
        alignToByte()
        return buffer
    }

    var output: Buffer {
        var copy = buffer
        if bitPosition > 0 {
            copy.append(Byte(currentByte))
        }
        return copy
    }
}
