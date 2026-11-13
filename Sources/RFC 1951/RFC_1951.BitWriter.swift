internal import Binary
internal import Byte

extension RFC_1951 {

    struct BitWriter {
        private var buffer: [Byte]
        private var accumulator: UInt64 = 0
        private var bitCount: Int = 0

        init(into buffer: [Byte]) {
            self.buffer = buffer
        }
    }
}

extension RFC_1951.BitWriter {

    mutating func reserveCapacity(_ additional: Int) {
        buffer.reserveCapacity(buffer.count + additional)
    }

    mutating func writeBit(_ bit: UInt8) {
        writeBits(UInt32(bit & 1), count: 1)
    }

    @inline(__always)
    mutating func writeBits(_ value: UInt32, count: Int) {
        let masked = UInt64(value) & ((1 &<< UInt64(count)) &- 1)
        accumulator |= masked &<< UInt64(bitCount)
        bitCount &+= count
        if bitCount >= 32 {
            let word = UInt32(truncatingIfNeeded: accumulator)
            buffer.append(Byte(UInt8(truncatingIfNeeded: word)))
            buffer.append(Byte(UInt8(truncatingIfNeeded: word &>> 8)))
            buffer.append(Byte(UInt8(truncatingIfNeeded: word &>> 16)))
            buffer.append(Byte(UInt8(truncatingIfNeeded: word &>> 24)))
            accumulator &>>= 32
            bitCount &-= 32
        }
    }

    @inline(__always)
    mutating func writeBitsReversed(_ value: UInt32, count: Int) {
        var reversed: UInt32 = 0
        var remaining = value
        for _ in 0..<count {
            reversed = reversed &<< 1 | remaining & 1
            remaining &>>= 1
        }
        writeBits(reversed, count: count)
    }

    mutating func alignToByte() {
        while bitCount > 0 {
            buffer.append(Byte(UInt8(truncatingIfNeeded: accumulator)))
            accumulator &>>= 8
            bitCount = Swift.max(bitCount &- 8, 0)
        }
        accumulator = 0
    }

    mutating func writeByte(_ byte: UInt8) {
        alignToByte()
        buffer.append(Byte(byte))
    }

    mutating func writeBytes<Bytes: Swift::Sequence>(_ bytes: Bytes) where Bytes.Element == Byte {
        alignToByte()
        buffer.append(contentsOf: bytes)
    }

    mutating func writeUInt16LE(_ value: UInt16) {
        writeBytes(value.bytes(endianness: .little))
    }

    mutating func finish() -> [Byte] {
        alignToByte()
        return buffer
    }
}
