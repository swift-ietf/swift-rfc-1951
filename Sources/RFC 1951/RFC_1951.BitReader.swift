extension RFC_1951 {

    @safe
    struct BitReader {
        private let bytes: UnsafeRawBufferPointer
        private var position: Int = 0
        private(set) var buffer: UInt64 = 0
        private(set) var available: Int = 0

        init(_ bytes: UnsafeRawBufferPointer) {
            unsafe self.bytes = bytes
        }
    }
}

extension RFC_1951.BitReader {

    @inline(__always)
    mutating func refill() {
        guard available <= 56 else { return }
        if unsafe position &+ 8 <= bytes.count {
            let word = unsafe bytes.loadUnaligned(fromByteOffset: position, as: UInt64.self)
            buffer |= UInt64(littleEndian: word) &<< UInt64(available)
            position &+= (63 &- available) &>> 3
            available |= 56
        } else {
            while available <= 56, unsafe position < bytes.count {
                buffer |= UInt64(unsafe bytes[position]) &<< UInt64(available)
                position &+= 1
                available &+= 8
            }
        }
    }

    @inline(__always)
    mutating func consume(_ count: Int) {
        buffer &>>= UInt64(count)
        available &-= count
    }

    @inline(__always)
    mutating func take(_ count: Int) throws(RFC_1951.Error) -> UInt32 {
        guard count <= available else {
            throw .unexpectedEndOfInput
        }
        let value = UInt32(truncatingIfNeeded: buffer & ((1 &<< UInt64(count)) &- 1))
        consume(count)
        return value
    }

    mutating func readBits(_ count: Int) throws(RFC_1951.Error) -> UInt32 {
        refill()
        return try take(count)
    }

    mutating func readBit() throws(RFC_1951.Error) -> UInt32 {
        try readBits(1)
    }

    var hasMoreBits: Bool {
        mutating get {
            refill()
            return available > 0
        }
    }

    mutating func alignToByte() {
        consume(available & 7)
        position &-= available &>> 3
        buffer = 0
        available = 0
    }

    mutating func readUInt16LE() throws(RFC_1951.Error) -> UInt16 {
        alignToByte()
        guard unsafe position &+ 2 <= bytes.count else {
            throw .unexpectedEndOfInput
        }
        let value = UInt16(unsafe bytes[position]) | UInt16(unsafe bytes[position &+ 1]) &<< 8
        position &+= 2
        return value
    }

    mutating func readBytes(
        _ count: Int,
        into window: inout RFC_1951.Window
    ) throws(RFC_1951.Error) {
        alignToByte()
        guard unsafe count <= bytes.count &- position else {
            throw .unexpectedEndOfInput
        }
        unsafe window.append(UnsafeRawBufferPointer(rebasing: bytes[position..<(position &+ count)]))
        position &+= count
    }
}
