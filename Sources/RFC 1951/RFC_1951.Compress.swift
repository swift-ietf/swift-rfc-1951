public import Byte_Primitives

extension RFC_1951 {

    public static func compress<Input, Output>(
        _ input: Input,
        into output: inout Output,
        level: Level = .balanced
    )
    where
        Input: Swift.Collection, Input.Element == Byte, Output: RangeReplaceableCollection,
        Output.Element == Byte
    {
        let inputArray = Array(input)

        if inputArray.isEmpty {

            var writer = BitWriter(into: output)
            encodeStoredBlock(data: inputArray[...], isFinal: true, into: &writer)
            output = writer.finish()
            return
        }

        if level == .none {

            compressStored(inputArray, into: &output)
        } else {

            compressDeflate(inputArray, into: &output, level: level)
        }
    }

    public static func compress<Bytes>(
        _ input: Bytes,
        level: Level = .balanced
    ) -> [Byte] where Bytes: Swift.Collection, Bytes.Element == Byte {
        var output: [Byte] = []
        compress(input, into: &output, level: level)
        return output
    }

    private static func compressStored<Output: RangeReplaceableCollection>(
        _ input: [Byte],
        into output: inout Output
    ) where Output.Element == Byte {
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

    private static func compressDeflate<Output: RangeReplaceableCollection>(
        _ input: [Byte],
        into output: inout Output,
        level: Level
    ) where Output.Element == Byte {

        var writer = BitWriter(into: output)

        let chunkSize = 32768
        var position = 0

        while position < input.count {
            let remaining = input.count - position
            let currentChunkSize = min(remaining, chunkSize)
            let isFinal = position + currentChunkSize >= input.count

            let chunk = Array(input[position..<(position + currentChunkSize)])

            let tokens = encodeLZ77(chunk, level: level)

            let estimatedCompressedSize = estimateCompressedSize(tokens: tokens)
            let storedSize = chunk.count + 5

            if storedSize <= estimatedCompressedSize && chunk.count <= maxStoredBlockSize {
                encodeStoredBlock(data: chunk[...], isFinal: isFinal, into: &writer)
            } else {
                encodeFixedHuffmanBlock(tokens: tokens, isFinal: isFinal, into: &writer)
            }

            position += currentChunkSize
        }

        output = writer.finish()
    }

    private static func estimateCompressedSize(tokens: [LZ77Token]) -> Int {
        var bits = 3

        for token in tokens {
            switch token {
            case .literal:
                bits += 9

            case .reference:
                bits += 15
            }
        }

        bits += 7

        return (bits + 7) / 8
    }
}

extension RFC_1951 {

    public static func compressRaw<Input, Output>(
        _ input: Input,
        into output: inout Output,
        level: Level = .balanced
    )
    where
        Input: Swift.Collection, Input.Element == Byte, Output: RangeReplaceableCollection,
        Output.Element == Byte
    {

        compress(input, into: &output, level: level)
    }

    public static func compressRaw<Bytes>(
        _ input: Bytes,
        level: Level = .balanced
    ) -> [Byte] where Bytes: Swift.Collection, Bytes.Element == Byte {
        compress(input, level: level)
    }
}
