import Byte

extension Reference {

    struct BitWriter {
        private(set) var buffer: [Byte] = []
        private var currentByte: UInt8 = 0
        private var bitPosition = 0
    }
}

extension Reference.BitWriter {

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
        for _ in 0..<count {
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

    mutating func writeBytes(_ bytes: [Byte]) {
        alignToByte()
        buffer.append(contentsOf: bytes)
    }

    mutating func finish() -> [Byte] {
        alignToByte()
        return buffer
    }
}
