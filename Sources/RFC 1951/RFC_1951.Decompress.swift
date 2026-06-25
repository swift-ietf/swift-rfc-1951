// RFC_1951.Decompress.swift

public import Byte_Primitives

extension RFC_1951 {
    /// Decompress DEFLATE-compressed data
    ///
    /// - Parameters:
    ///   - input: The compressed data
    ///   - output: Buffer to append decompressed data to
    /// - Throws: `Error` if the data is invalid or corrupted
    ///
    /// ## Example
    ///
    /// ```swift
    /// var decompressed: [Byte] = []
    /// try RFC_1951.decompress(compressed, into: &decompressed)
    /// let text = String(decoding: decompressed, as: UTF8.self)
    /// ```
    public static func decompress<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error) where Input: Collection, Input.Element == Byte, Output: RangeReplaceableCollection, Output.Element == Byte {
        guard !input.isEmpty else {
            throw .empty
        }

        var reader = BitReader(input)

        // Decode blocks until we hit a final block
        var isFinal = false
        while !isFinal {
            isFinal = try decodeBlock(from: &reader, into: &output)
        }
    }

    /// Convenience: decompress and return new array
    ///
    /// - Parameter input: The compressed data
    /// - Returns: Decompressed data
    /// - Throws: `Error` if the data is invalid or corrupted
    ///
    /// ## Example
    ///
    /// ```swift
    /// let decompressed = try RFC_1951.decompress(compressed)
    /// ```
    public static func decompress<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [Byte] where Bytes: Collection, Bytes.Element == Byte {
        var output: [Byte] = []
        try decompress(input, into: &output)
        return output
    }
}

// MARK: - Raw DEFLATE API

extension RFC_1951 {
    /// Decompress raw DEFLATE data (no ZLIB header/trailer)
    ///
    /// Use this for contexts that use raw DEFLATE streams without
    /// ZLIB wrapping, such as PNG image data.
    ///
    /// - Parameters:
    ///   - input: The compressed data
    ///   - output: Buffer to append decompressed data to
    /// - Throws: `Error` if the data is invalid or corrupted
    public static func decompressRaw<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error) where Input: Collection, Input.Element == Byte, Output: RangeReplaceableCollection, Output.Element == Byte {
        // Raw DEFLATE is the same as decompress - ZLIB unwrapping is done by RFC 1950
        try decompress(input, into: &output)
    }

    /// Convenience: raw decompress and return new array
    public static func decompressRaw<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [Byte] where Bytes: Collection, Bytes.Element == Byte {
        try decompress(input)
    }
}
