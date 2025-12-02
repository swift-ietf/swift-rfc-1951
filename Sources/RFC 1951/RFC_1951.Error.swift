// RFC_1951.Error.swift

extension RFC_1951 {
    /// Errors that can occur during DEFLATE decompression
    public enum Error: Swift.Error, Sendable, Equatable {
        /// Input data is empty
        case empty

        /// Invalid block type encountered (must be 0, 1, or 2)
        case invalidBlockType(_ value: UInt8)

        /// Stored block length validation failed (LEN != ~NLEN)
        case invalidStoredBlockLength

        /// Huffman code is invalid or incomplete
        case invalidHuffmanCode

        /// Back-reference distance is zero (invalid)
        case invalidDistance

        /// Back-reference points before start of output
        case distanceTooFar

        /// Unexpected end of input stream
        case unexpectedEndOfInput

        /// Code length code lengths are invalid
        case invalidCodeLengthCodes

        /// Literal/length tree is invalid
        case invalidLiteralLengthTree

        /// Distance tree is invalid
        case invalidDistanceTree

        /// Reserved or invalid length code encountered
        case invalidLengthCode(_ code: Int)

        /// Reserved or invalid distance code encountered
        case invalidDistanceCode(_ code: Int)
    }
}

extension RFC_1951.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty:
            return "Input data is empty"
        case .invalidBlockType(let value):
            return "Invalid block type: \(value) (must be 0, 1, or 2)"
        case .invalidStoredBlockLength:
            return "Stored block length validation failed (LEN != ~NLEN)"
        case .invalidHuffmanCode:
            return "Invalid or incomplete Huffman code"
        case .invalidDistance:
            return "Invalid back-reference distance (zero)"
        case .distanceTooFar:
            return "Back-reference points before start of output"
        case .unexpectedEndOfInput:
            return "Unexpected end of input stream"
        case .invalidCodeLengthCodes:
            return "Invalid code length code lengths"
        case .invalidLiteralLengthTree:
            return "Invalid literal/length Huffman tree"
        case .invalidDistanceTree:
            return "Invalid distance Huffman tree"
        case .invalidLengthCode(let code):
            return "Invalid length code: \(code)"
        case .invalidDistanceCode(let code):
            return "Invalid distance code: \(code)"
        }
    }
}
