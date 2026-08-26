public import Byte

extension RFC_1951 {

    public static func decompress<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error)
    where
        Input: Swift.Collection, Input.Element == Byte, Output: RangeReplaceableCollection,
        Output.Element == Byte
    {
        guard !input.isEmpty else {
            throw .empty
        }

        var reader = BitReader(input)

        var isFinal = false
        while !isFinal {
            isFinal = try decodeBlock(from: &reader, into: &output)
        }
    }

    public static func decompress<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [Byte] where Bytes: Swift.Collection, Bytes.Element == Byte {
        var output: [Byte] = []
        try decompress(input, into: &output)
        return output
    }
}

extension RFC_1951 {

    public static func decompressRaw<Input, Output>(
        _ input: Input,
        into output: inout Output
    ) throws(Error)
    where
        Input: Swift.Collection, Input.Element == Byte, Output: RangeReplaceableCollection,
        Output.Element == Byte
    {

        try decompress(input, into: &output)
    }

    public static func decompressRaw<Bytes>(
        _ input: Bytes
    ) throws(Error) -> [Byte] where Bytes: Swift.Collection, Bytes.Element == Byte {
        try decompress(input)
    }
}
