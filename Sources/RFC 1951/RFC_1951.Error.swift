public import Byte_Primitives

extension RFC_1951 {

    public enum Error: Swift.Error, Sendable, Equatable {

        case empty

        case invalidBlockType(_ value: Byte)

        case invalidStoredBlockLength

        case invalidHuffmanCode

        case invalidDistance

        case distanceTooFar

        case unexpectedEndOfInput

        case invalidCodeLengthCodes

        case invalidLiteralLengthTree

        case invalidDistanceTree

        case invalidLengthCode(_ code: Int)

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
