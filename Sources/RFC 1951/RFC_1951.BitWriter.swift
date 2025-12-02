// RFC_1951.BitWriter.swift

extension RFC_1951 {
    /// Writes bits to a byte buffer, LSB first (per DEFLATE spec)
    struct BitWriter<Buffer: RangeReplaceableCollection> where Buffer.Element == UInt8 {
        private var buffer: Buffer
        private var currentByte: UInt8 = 0
        private var bitPosition: Int = 0

        init(into buffer: Buffer) {
            self.buffer = buffer
        }

        /// Write a single bit
        mutating func writeBit(_ bit: UInt8) {
            currentByte |= (bit & 1) << bitPosition
            bitPosition += 1
            if bitPosition == 8 {
                buffer.append(currentByte)
                currentByte = 0
                bitPosition = 0
            }
        }

        /// Write multiple bits (LSB first)
        mutating func writeBits(_ value: UInt32, count: Int) {
            var v = value
            for _ in 0..<count {
                writeBit(UInt8(v & 1))
                v >>= 1
            }
        }

        /// Write bits in reverse order (MSB first) - for Huffman codes
        mutating func writeBitsReversed(_ value: UInt32, count: Int) {
            for i in stride(from: count - 1, through: 0, by: -1) {
                writeBit(UInt8((value >> i) & 1))
            }
        }

        /// Align to byte boundary by padding with zeros
        mutating func alignToByte() {
            if bitPosition > 0 {
                buffer.append(currentByte)
                currentByte = 0
                bitPosition = 0
            }
        }

        /// Write a byte directly (must be byte-aligned)
        mutating func writeByte(_ byte: UInt8) {
            alignToByte()
            buffer.append(byte)
        }

        /// Write bytes directly (must be byte-aligned)
        mutating func writeBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
            alignToByte()
            buffer.append(contentsOf: bytes)
        }

        /// Write a 16-bit little-endian value (must be byte-aligned)
        mutating func writeUInt16LE(_ value: UInt16) {
            writeByte(UInt8(value & 0xFF))
            writeByte(UInt8(value >> 8))
        }

        /// Flush any remaining bits and return the buffer
        mutating func finish() -> Buffer {
            alignToByte()
            return buffer
        }

        /// Get current buffer content without finishing
        var output: Buffer {
            var copy = buffer
            if bitPosition > 0 {
                copy.append(currentByte)
            }
            return copy
        }
    }
}
