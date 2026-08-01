// RFC_1951.LZ77Token.swift

internal import Byte_Primitives

extension RFC_1951 {
    /// A token in the LZ77-encoded stream
    enum LZ77Token {
        /// A literal byte
        case literal(Byte)
        /// A back-reference (length, distance)
        case reference(length: Int, distance: Int)
    }
}
