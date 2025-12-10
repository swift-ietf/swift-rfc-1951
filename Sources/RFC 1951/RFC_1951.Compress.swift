// RFC_1951.Compress.swift

extension RFC_1951 {
    /// Compress data using DEFLATE
    ///
    /// - Parameters:
    ///   - input: The data to compress
    ///   - output: Buffer to append compressed data to
    ///   - level: Compression level (default: `.balanced`)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let data: [UInt8] = Array("Hello, World!".utf8)
    /// var compressed: [UInt8] = []
    /// RFC_1951.compress(data, into: &compressed)
    /// ```
    public static func compress<Input, Output>(
        _ input: Input,
        into output: inout Output,
        level: Level = .balanced
    )
    where
        Input: Collection,
        Input.Element == UInt8,
        Output: RangeReplaceableCollection,
        Output.Element == UInt8
    {
        let inputArray = Array(input)

        if inputArray.isEmpty {
            // Empty input: emit single empty stored block
            var writer = BitWriter(into: output)
            encodeStoredBlock(data: inputArray[...], isFinal: true, into: &writer)
            output = writer.finish()
            return
        }

        if level == .none {
            // No compression: use stored blocks
            compressStored(inputArray, into: &output)
        } else {
            // LZ77 + Huffman compression
            compressDeflate(inputArray, into: &output, level: level)
        }
    }

    /// Convenience: compress and return new array
    ///
    /// - Parameters:
    ///   - input: The data to compress
    ///   - level: Compression level (default: `.balanced`)
    /// - Returns: Compressed data
    ///
    /// ## Example
    ///
    /// ```swift
    /// let compressed = RFC_1951.compress(data)
    /// ```
    public static func compress<Bytes>(
        _ input: Bytes,
        level: Level = .balanced
    ) -> [UInt8] where Bytes: Collection, Bytes.Element == UInt8 {
        var output: [UInt8] = []
        compress(input, into: &output, level: level)
        return output
    }

    /// Compress using stored blocks (no compression)
    private static func compressStored<Output: RangeReplaceableCollection>(
        _ input: [UInt8],
        into output: inout Output
    ) where Output.Element == UInt8 {
        var writer = BitWriter(into: output)
        var position = 0

        while position < input.count {
            let remaining = input.count - position
            let blockSize = min(remaining, maxStoredBlockSize)
            let isFinal = position + blockSize >= input.count

            let slice = input[position..<(position + blockSize)]
            encodeStoredBlock(data: slice, isFinal: isFinal, into: &writer)

            position += blockSize
        }

        output = writer.finish()
    }

    /// Compress using LZ77 + Huffman coding
    private static func compressDeflate<Output: RangeReplaceableCollection>(
        _ input: [UInt8],
        into output: inout Output,
        level: Level
    ) where Output.Element == UInt8 {
        // For MVP, we use fixed Huffman codes which are simpler
        // Dynamic Huffman would give better compression for some data

        var writer = BitWriter(into: output)

        // Process in chunks to limit memory usage
        let chunkSize = 32768  // 32KB chunks
        var position = 0

        while position < input.count {
            let remaining = input.count - position
            let currentChunkSize = min(remaining, chunkSize)
            let isFinal = position + currentChunkSize >= input.count

            let chunk = Array(input[position..<(position + currentChunkSize)])

            // Encode to LZ77 tokens
            let tokens = encodeLZ77(chunk, level: level)

            // Decide: stored vs compressed
            // For very small data or incompressible data, stored might be better
            let estimatedCompressedSize = estimateCompressedSize(tokens: tokens)
            let storedSize = chunk.count + 5  // 5 bytes header

            if storedSize <= estimatedCompressedSize && chunk.count <= maxStoredBlockSize {
                encodeStoredBlock(data: chunk[...], isFinal: isFinal, into: &writer)
            } else {
                encodeFixedHuffmanBlock(tokens: tokens, isFinal: isFinal, into: &writer)
            }

            position += currentChunkSize
        }

        output = writer.finish()
    }

    /// Rough estimate of compressed size for deciding stored vs compressed
    private static func estimateCompressedSize(tokens: [LZ77Token]) -> Int {
        var bits = 3  // Block header

        for token in tokens {
            switch token {
            case .literal:
                bits += 9  // Average literal code length
            case .reference:
                bits += 15  // Length code + distance code + extras
            }
        }

        bits += 7  // End of block marker

        return (bits + 7) / 8
    }
}

// MARK: - Raw DEFLATE API (without ZLIB wrapper)

extension RFC_1951 {
    /// Compress data using raw DEFLATE (no ZLIB header/trailer)
    ///
    /// Use this for contexts that require raw DEFLATE streams without
    /// ZLIB wrapping, such as PNG image data.
    ///
    /// - Parameters:
    ///   - input: The data to compress
    ///   - output: Buffer to append compressed data to
    ///   - level: Compression level (default: `.balanced`)
    public static func compressRaw<Input, Output>(
        _ input: Input,
        into output: inout Output,
        level: Level = .balanced
    )
    where
        Input: Collection,
        Input.Element == UInt8,
        Output: RangeReplaceableCollection,
        Output.Element == UInt8
    {
        // Raw DEFLATE is the same as compress - ZLIB wrapper is added by RFC 1950
        compress(input, into: &output, level: level)
    }

    /// Convenience: raw compress and return new array
    public static func compressRaw<Bytes>(
        _ input: Bytes,
        level: Level = .balanced
    ) -> [UInt8] where Bytes: Collection, Bytes.Element == UInt8 {
        compress(input, level: level)
    }
}
